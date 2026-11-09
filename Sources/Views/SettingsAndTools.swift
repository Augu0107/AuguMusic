import SwiftUI
import UniformTypeIdentifiers

// MARK: - Timer di spegnimento

struct SleepTimerView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sleepFinishSong") private var finishSong = true
    @AppStorage("sleepCustomMinutes") private var customMinutes = 25
    @AppStorage("sleepSongs") private var songs = 3

    var body: some View {
        NavigationStack {
            Form {
                if let timer = player.sleepTimer {
                    Section("Attivo") {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(description(timer))
                        }
                        Button("Annulla il timer", role: .destructive) { player.cancelSleepTimer() }
                    }
                }
                Section {
                    Toggle("Finisci il brano in corso", isOn: $finishSong)
                }
                Section("Ferma tra") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 10) {
                        ForEach([5, 10, 15, 20, 30, 45, 60, 90, 120], id: \.self) { m in
                            Button("\(m) min") {
                                player.setSleepTimer(minutes: m, finishCurrentSong: finishSong)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                    Stepper("Personalizzato: \(customMinutes) min", value: $customMinutes, in: 1...600)
                    Button("Avvia \(customMinutes) min") {
                        player.setSleepTimer(minutes: customMinutes, finishCurrentSong: finishSong)
                        dismiss()
                    }
                }
                Section("Ferma dopo") {
                    Button("Questo brano") {
                        player.setSleepAfterCurrentSong()
                        dismiss()
                    }
                    Stepper("\(songs) brani", value: $songs, in: 2...200)
                    Button("Ferma dopo \(songs) brani") {
                        player.setSleepAfterSongs(songs)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Timer di spegnimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func description(_ timer: SleepTimer) -> String {
        switch timer.mode {
        case .at(let date):
            let remaining = formatTime(max(0, date.timeIntervalSinceNow))
            return "Mi fermo tra \(remaining)" + (timer.finishCurrentSong ? ", a fine brano" : "")
        case .afterCurrentSong:
            return "Mi fermo alla fine di questo brano"
        case .afterSongs(let n):
            return "Mi fermo tra \(n) brani"
        }
    }
}

// MARK: - Velocità, tono, bilanciamento

struct PlaybackSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Velocità: \(settings.speed.formatted(.number.precision(.fractionLength(2))))x") {
                    Slider(value: $settings.speed, in: 0.5...2.0, step: 0.05)
                    HStack {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { v in
                            Button(v.formatted(.number.precision(.fractionLength(0...2))) + "x") { settings.speed = v }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                Section("Tono: \(settings.pitch >= 0 ? "+" : "")\(Int(settings.pitch)) semitoni") {
                    Slider(value: $settings.pitch, in: -12...12, step: 1)
                }
                Section("Bilanciamento: \(balanceLabel)") {
                    Slider(value: $settings.balance, in: -1...1, step: 0.05)
                }
                Section {
                    Button("Reimposta") { settings.resetPlaybackEffects() }
                }
            }
            .navigationTitle("Riproduzione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var balanceLabel: String {
        if abs(settings.balance) < 0.01 { return "centro" }
        let pct = Int(abs(settings.balance) * 100)
        return settings.balance < 0 ? "\(pct)% sinistra" : "\(pct)% destra"
    }
}

// MARK: - Informazioni brano

struct TrackInfoView: View {
    let track: Track
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ArtworkView(track: track, maxPixel: 600, cornerRadius: 0, mode: .fill)
                            .frame(maxWidth: 220, maxHeight: 260)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Tag") {
                    row("Titolo", track.displayTitle)
                    row("Artista", track.displayArtist)
                    row("Album", track.displayAlbum)
                    row("Artista album", track.albumArtist)
                    row("Compositore", track.composer)
                    row("Genere", track.genre)
                    row("Anno", track.year.map { String($0) } ?? "")
                    row("Traccia", track.trackNumber.map { String($0) } ?? "")
                    row("Disco", track.discNumber.map { String($0) } ?? "")
                }
                Section("File") {
                    row("Durata", formatTime(track.duration))
                    row("Formato", track.fileExtension.uppercased())
                    row("Formato reale", track.formatName ?? "")
                    row("Dimensione", ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))
                    row("Cartella", library.folderName(track.folderID))
                    row("Percorso", track.relativePath)
                    row("Aggiunto", track.dateAdded.formatted(date: .abbreviated, time: .shortened))
                    if let rg = track.replayGainTrack {
                        row("ReplayGain brano", String(format: "%+.2f dB", rg))
                    }
                    if let rg = track.replayGainAlbum {
                        row("ReplayGain album", String(format: "%+.2f dB", rg))
                    }
                }
            }
            .navigationTitle("Informazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label) {
                Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - Impostazioni (opzioni non ancora divise in categorie)

/// Sezioni che restano sotto "Lingua" e "Interfaccia" finché non creiamo le loro categorie.
struct OtherSettingsSections: View {
    @Binding var showImporter: Bool
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ScanProgress
    @AppStorage(Prefs.excludedFolders) private var excluded = ""

    var body: some View {
        Section {
            Picker("Toccando un brano", selection: $settings.tapAction) {
                ForEach(TapAction.allCases) { Text($0.label).tag($0) }
            }
            Stepper("Numero massimo di code: \(settings.maxQueues)", value: $settings.maxQueues, in: 2...50)
        } header: {
            Text("Code")
        }

        Section("Informazioni") {
            LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
            Text("AuguMusic è un'app personale di Chiara, ispirata a Musicolet. Funziona solo con file locali: niente account, niente pubblicità, niente internet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Cartelle escluse dalla scansione, salvate una per riga (percorso relativo, es. "AuguMusic/Podcast").
enum ExcludedFolders {
    static func list(_ stored: String) -> [String] {
        stored.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func adding(_ path: String, to stored: String) -> String {
        var l = list(stored)
        if !l.contains(path) { l.append(path) }
        return l.joined(separator: "\n")
    }

    static func removing(_ path: String, from stored: String) -> String {
        list(stored).filter { $0 != path }.joined(separator: "\n")
    }

    /// "uuid|Musica/Podcast" → "Musica/Podcast".
    static func displayName(_ key: String) -> String {
        let dir = key.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? key
        return dir.isEmpty ? "Cartella principale" : dir
    }

    /// Vero se il file (percorso relativo) sta dentro una cartella esclusa.
    static func isExcluded(_ relativePath: String, stored: String) -> Bool {
        list(stored).contains { relativePath == $0 || relativePath.hasPrefix($0 + "/") }
    }
}

// MARK: - Editor di elenchi di testo

struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    let showQuotes: Bool
    @State private var newItem = ""

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            HStack {
                Text(showQuotes ? "\u{201C}\(item)\u{201D}" : item)
                    .font(.body.monospaced())
                Spacer()
                Button(role: .destructive) {
                    items.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        HStack {
            TextField(placeholder, text: $newItem)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(add)
            Button("Aggiungi", action: add)
                .disabled(newItem.isEmpty)
        }
    }

    private func add() {
        guard !newItem.isEmpty, !items.contains(newItem) else { return }
        items.append(newItem)
        newItem = ""
    }
}
