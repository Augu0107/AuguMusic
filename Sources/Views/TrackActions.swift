import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

// Azioni extra dei menù (Condividi, Sposta, Cancella, Anteprima...), attivabili in
// Impostazioni › Interfaccia › Opzioni e menù.

struct FileTransferRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    let asCopy: Bool
}

enum AudioQuickSheet: String, Identifiable {
    case crossfade, replayGain
    var id: String { rawValue }
}

/// Voci extra da mettere in un Menu, scelte in base alla preferenza `menuKey`.
struct TrackExtraActions: View {
    let tracks: [Track]
    let menuKey: String
    var clearsSelection = false

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var ui: UIState
    @AppStorage private var enabled: String

    init(tracks: [Track], menuKey: String, clearsSelection: Bool = false) {
        self.tracks = tracks
        self.menuKey = menuKey
        self.clearsSelection = clearsSelection
        _enabled = AppStorage(wrappedValue: Prefs.defaults[menuKey] as? String ?? "", menuKey)
    }

    private func on(_ id: String) -> Bool { enabled.csvContains(id) }
    private var urls: [URL] { tracks.compactMap { library.url(for: $0) } }

    var body: some View {
        if !tracks.isEmpty {
            if on("advShuffle") && tracks.count > 1 {
                Menu {
                    ForEach(AdvancedShuffle.allCases) { mode in
                        Button(mode.label) {
                            player.play(AdvancedShuffle.order(tracks, by: mode, library: library), startAt: 0, source: "Shuffle avanzato")
                            done()
                        }
                    }
                } label: { Label("Shuffle avanzato", systemImage: "shuffle.circle") }
            }
            if on("share"), !urls.isEmpty {
                ShareLink(items: urls) { Label("Condividi", systemImage: "square.and.arrow.up") }
            }
            if on("speed") {
                Button { ui.showPlaybackSettings = true } label: { Label("Velocità di riproduzione", systemImage: "speedometer") }
            }
            if on("rg") {
                Button {
                    let ids = tracks.map(\.id)
                    Task {
                        await library.refresh(trackIDs: ids)
                        if let current = player.loadedTrackID, ids.contains(current) { player.reloadCurrentTrack() }
                        ui.showToast("ReplayGain riletto")
                    }
                    done()
                } label: { Label("Leggi RG", systemImage: "waveform.badge.magnifyingglass") }
            }
            if on("move"), !urls.isEmpty {
                Button { ui.fileTransfer = FileTransferRequest(urls: urls, asCopy: false); done() } label: {
                    Label("Sposta in una cartella…", systemImage: "folder.badge.gearshape")
                }
            }
            if on("copy"), !urls.isEmpty {
                Button { ui.fileTransfer = FileTransferRequest(urls: urls, asCopy: true); done() } label: {
                    Label("Copia in una cartella…", systemImage: "doc.on.doc")
                }
            }
            if tracks.count == 1, let t = tracks.first {
                if on("preview") {
                    Button { ui.previewTrack = t } label: { Label("Anteprima", systemImage: "play.rectangle") }
                }
                if on("stopAfter") {
                    Button {
                        player.stopAfterTrackID = player.stopAfterTrackID == t.id ? nil : t.id
                        ui.showToast(player.stopAfterTrackID == nil ? "Annullato" : "La riproduzione si fermerà dopo questo brano")
                    } label: {
                        Label(player.stopAfterTrackID == t.id ? "Non fermarti dopo questa canzone" : "Fermati dopo questa canzone",
                              systemImage: "stop.circle")
                    }
                }
            }
            if on("clearHistory") {
                Button {
                    userData.clearHistory(tracks.map(\.id))
                    ui.showToast("Cronologia cancellata")
                    done()
                } label: { Label("Cancella cronologia di riproduzione", systemImage: "clock.arrow.circlepath") }
            }
            if on("delete") {
                Button(role: .destructive) { ui.deleteRequest = TrackIDList(ids: tracks.map(\.id)); done() } label: {
                    Label("Cancella definitivamente", systemImage: "trash")
                }
            }
        }
    }

    private func done() {
        if clearsSelection { ui.clearSelection() }
    }
}

// MARK: - Shuffle avanzato

enum AdvancedShuffle: String, CaseIterable, Identifiable {
    case songs, albums, artists, folders
    var id: String { rawValue }

    var label: String {
        switch self {
        case .songs: "Mescola i brani"
        case .albums: "Mescola gli album (brani in ordine)"
        case .artists: "Mescola gli artisti"
        case .folders: "Mescola le cartelle"
        }
    }

    /// Mescola i gruppi tenendo i brani di ogni gruppo nell'ordine originale.
    @MainActor
    static func order(_ tracks: [Track], by mode: AdvancedShuffle, library: LibraryStore) -> [Track] {
        let key: (Track) -> String
        switch mode {
        case .songs: return tracks.shuffled()
        case .albums: key = { library.albumID(for: $0) ?? $0.album }
        case .artists: key = { $0.artist.lowercased() }
        case .folders: key = { library.folderID(for: $0) }
        }
        var order: [String] = []
        var groups: [String: [Track]] = [:]
        for t in tracks {
            let k = key(t)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(t)
        }
        return order.shuffled().flatMap { groups[$0] ?? [] }
    }
}

// MARK: - Sposta / Copia in una cartella

struct DocumentExporter: UIViewControllerRepresentable {
    let request: FileTransferRequest
    let completion: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: request.urls, asCopy: request.asCopy)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion([]) }
    }
}

// MARK: - Anteprima

/// Ascolta un brano senza toccare la coda (la riproduzione principale va in pausa).
struct PreviewPlayerView: View {
    let track: Track
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var audio: AVAudioPlayer?
    @State private var time: Double = 0
    @State private var playing = false
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                ArtworkView(track: track, maxPixel: 200, cornerRadius: 0)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.displayTitle).font(.headline).lineLimit(2)
                    Text(track.displayArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            Slider(value: Binding(get: { time }, set: { time = $0; audio?.currentTime = $0 }),
                   in: 0...max(audio?.duration ?? 1, 0.1))
            HStack {
                Text(formatTime(time))
                Spacer()
                Text(formatTime(audio?.duration ?? 0))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            Button {
                guard let audio else { return }
                if audio.isPlaying { audio.pause() } else { audio.play() }
                playing = audio.isPlaying
            } label: {
                TransportIcon(glyph: playing ? .pause : .play, size: 40).frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            if audio == nil {
                Text("Anteprima non disponibile per questo formato").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .presentationDetents([.height(300)])
        .onAppear {
            guard let url = library.url(for: track) else { return }
            if player.isPlaying { player.pause() }
            audio = try? AVAudioPlayer(contentsOf: url)
            audio?.play()
            playing = audio?.isPlaying ?? false
        }
        .onDisappear { audio?.stop() }
        .onReceive(timer) { _ in
            time = audio?.currentTime ?? 0
            playing = audio?.isPlaying ?? false
        }
    }
}

// MARK: - Crossfade / ReplayGain veloci

struct AudioQuickView: View {
    let which: AudioQuickSheet
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch which {
                case .crossfade:
                    Section {
                        VStack(alignment: .leading) {
                            Text(settings.crossfadeDuration == 0 ? "Disattivato" : "\(Int(settings.crossfadeDuration)) secondi")
                            Slider(value: $settings.crossfadeDuration, in: 0...60, step: 1)
                        }
                    } footer: {
                        Text("Il brano successivo entra sfumando mentre finisce quello attuale.")
                    }
                case .replayGain:
                    Picker("ReplayGain", selection: $settings.replayGain) {
                        ForEach(ReplayGainMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle(which == .crossfade ? "Crossfade" : "ReplayGain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AirPlay

/// Il pulsante di sistema per scegliere dove riprodurre (AirPlay, altoparlanti, auricolari).
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .secondaryLabel
        view.activeTintColor = UIColor(Color.accentColor)
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

// MARK: - Gestione globale (in RootView)

struct TrackActionsHost: ViewModifier {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: UIState
    @State private var newFolderName = ""

    func body(content: Content) -> some View {
        content
            .alert("Rinomina la cartella",
                   isPresented: Binding(get: { ui.renameFolder != nil }, set: { if !$0 { ui.renameFolder = nil } })) {
                TextField("Nome", text: $newFolderName)
                Button("Rinomina") { renameFolder() }
                Button("Annulla", role: .cancel) { ui.renameFolder = nil }
            }
            .onChange(of: ui.renameFolder) { _, group in
                if let group { newFolderName = group.name }
            }
            .sheet(item: $ui.fileTransfer) { request in
                DocumentExporter(request: request) { picked in
                    ui.fileTransfer = nil
                    guard !picked.isEmpty else { return }
                    ui.showToast(request.asCopy ? "Copiato" : "Spostato")
                    if !request.asCopy { Task { await library.rescan() } }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $ui.previewTrack) { track in
                PreviewPlayerView(track: track)
            }
            .sheet(isPresented: $ui.showPlaybackSettings) {
                SpeedPitchSheet()
            }
            .sheet(item: $ui.showAudioQuick) { which in
                AudioQuickView(which: which)
            }
            .confirmationDialog(deleteTitle,
                                isPresented: Binding(get: { ui.deleteRequest != nil }, set: { if !$0 { ui.deleteRequest = nil } }),
                                titleVisibility: .visible) {
                Button("Cancella", role: .destructive) { deleteFiles() }
                Button("Annulla", role: .cancel) { ui.deleteRequest = nil }
            } message: {
                Text("I file vengono eliminati dal dispositivo. Non si può annullare.")
            }
    }

    private var deleteTitle: String {
        let n = ui.deleteRequest?.ids.count ?? 0
        return n == 1 ? "Cancellare definitivamente il brano?" : "Cancellare definitivamente \(n) brani?"
    }

    private func renameFolder() {
        guard let group = ui.renameFolder else { return }
        ui.renameFolder = nil
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), let url = library.directoryURL(folderKey: group.id),
              url.lastPathComponent != name else { return }
        if library.tracks(for: group.trackIDs).contains(where: { $0.id == player.loadedTrackID }) {
            ui.showToast("Ferma prima il brano in riproduzione di questa cartella")
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true))
            ui.showToast("Cartella rinominata")
            Task {
                await library.rescan()
                player.libraryDidChange()
            }
        } catch {
            ui.showToast("Non riesco a rinominare: \(error.localizedDescription)")
        }
    }

    private func deleteFiles() {
        guard let request = ui.deleteRequest else { return }
        ui.deleteRequest = nil
        var failed = 0
        for t in library.tracks(for: request.ids) {
            if t.id == player.loadedTrackID { player.next() }
            guard let url = library.url(for: t) else { failed += 1; continue }
            do { try FileManager.default.removeItem(at: url) } catch { failed += 1 }
        }
        ui.showToast(failed == 0 ? "Cancellato" : "Non sono riuscita a cancellare \(failed) file")
        Task {
            await library.rescan()
            player.libraryDidChange()
        }
    }
}
