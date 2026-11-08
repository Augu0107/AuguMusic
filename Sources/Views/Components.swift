import SwiftUI

// MARK: - Copertina

enum ArtworkMode {
    /// Riempie un quadrato tagliando i bordi (solo per lo sfondo sfocato).
    case fill
    /// Sta tutta dentro un quadrato, senza tagli (righe degli elenchi).
    case fitInSquare
    /// Prende la forma dell'immagine: rettangolare, verticale o quadrata (come Musicolet).
    case natural
}

struct ArtworkView: View {
    @EnvironmentObject private var library: LibraryStore
    let track: Track?
    var maxPixel: CGFloat = 150
    var cornerRadius: CGFloat = 6
    var mode: ArtworkMode = .fitInSquare

    @State private var image: UIImage?

    var body: some View {
        content
            .task(id: track?.id) {
                image = nil
                guard let track, let url = library.url(for: track) else { return }
                image = await ArtworkLoader.shared.image(for: track, url: url, maxPixel: maxPixel)
            }
    }

    @ViewBuilder
    private var content: some View {
        if mode == .natural, let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        if mode == .fill {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                    } else {
                        placeholder
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var placeholder: some View {
        let seed = (track?.album ?? "").unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let hue = Double(seed % 360) / 360
        return ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.55),
                                    Color(hue: hue, saturation: 0.6, brightness: 0.3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .padding(maxPixel > 300 ? 60 : 12)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

// MARK: - Riga brano

struct TrackRow: View {
    let track: Track
    var isCurrent = false
    var showArtwork = true
    var leadingNumber: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let leadingNumber {
                Text("\(leadingNumber)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
            }
            if showArtwork {
                ArtworkView(track: track, maxPixel: 132, cornerRadius: 5)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                Text("\(track.displayArtist) · \(track.displayAlbum)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(formatTime(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Riga di un elenco: tocco = riproduci, tieni premuto = seleziona, tasto ⋯ = menu del brano (come Musicolet).
struct TrackListRow: View {
    let track: Track
    var isCurrent = false
    var showArtwork = true
    var leadingNumber: Int? = nil
    var sourceName: String = "Coda"
    let onTap: () -> Void

    @EnvironmentObject private var ui: UIState

    var body: some View {
        let selected = ui.isSelected(track.id)
        HStack(spacing: 8) {
            if ui.isSelecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            TrackRow(track: track, isCurrent: isCurrent, showArtwork: showArtwork, leadingNumber: leadingNumber)
                .contentShape(Rectangle())
                .onTapGesture {
                    if ui.isSelecting { ui.toggleSelection(track.id) } else { onTap() }
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    ui.toggleSelection(track.id)
                }
            TrackMenuButton(tracks: [track], sourceName: sourceName)
        }
        .listRowBackground(selected ? Color.accentColor.opacity(0.16) : nil)
    }
}

/// Imposta l'elenco usato da "Seleziona tutto" / "Inverti selezione".
struct SelectionScopeModifier: ViewModifier {
    let tracks: [Track]
    @EnvironmentObject private var ui: UIState

    func body(content: Content) -> some View {
        content
            .onAppear { ui.selectionScope = tracks }
            .onChange(of: tracks.count) { _, _ in ui.selectionScope = tracks }
    }
}

extension View {
    func selectionScope(_ tracks: [Track]) -> some View { modifier(SelectionScopeModifier(tracks: tracks)) }
}

/// Pannello in basso quando ci sono brani selezionati.
struct SelectionBar: View {
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var library: LibraryStore
    @State private var expanded = false

    var body: some View {
        if ui.isSelecting {
            let tracks = library.tracks(for: ui.selection)
            let total = tracks.reduce(0) { $0 + $1.duration }
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tracks.count == 1 ? "1 brano selezionato" : "\(tracks.count) brani selezionati")
                            .font(.subheadline.weight(.semibold))
                        Text(formatTime(total))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        TrackMenu(tracks: tracks, sourceName: "Selezione", showNavigation: false, clearsSelection: true)
                    } label: {
                        Label("Opzioni", systemImage: "ellipsis.circle")
                    }
                    Menu {
                        Button { ui.selectAll() } label: { Label("Seleziona tutto", systemImage: "checklist.checked") }
                        Button { ui.invertSelection() } label: { Label("Inverti selezione", systemImage: "arrow.left.arrow.right") }
                        Button { ui.selectRange() } label: { Label("Seleziona l'intervallo", systemImage: "arrow.up.and.down") }
                    } label: {
                        Label("Selezione avanzata", systemImage: "checklist")
                    }
                    Button("Annulla", role: .cancel) {
                        ui.clearSelection()
                        expanded = false
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if expanded {
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(tracks) { t in
                                HStack {
                                    Text(t.displayTitle).lineLimit(1)
                                    Spacer()
                                    Button { ui.toggleSelection(t.id) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

/// Quadratino arrotondato con i tre puntini.
struct TrackMenuButton: View {
    let tracks: [Track]
    var sourceName: String = "Coda"
    var showNavigation = true

    var body: some View {
        Menu {
            TrackMenu(tracks: tracks, sourceName: sourceName, showNavigation: showNavigation)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Menu azioni sui brani

struct TrackMenu: View {
    let tracks: [Track]
    var sourceName: String = "Coda"
    var showNavigation = true
    /// Usato dal pannello di selezione: dopo l'azione la selezione si chiude.
    var clearsSelection = false

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        if tracks.count > 1 {
            Button { player.play(tracks, startAt: 0, source: sourceName); done() } label: {
                Label("Riproduci", systemImage: "play")
            }
            Button { player.shuffleAndPlay(tracks, source: sourceName); done() } label: {
                Label("Riproduci in ordine casuale", systemImage: "shuffle")
            }
        }
        Button { player.playNext(tracks); done() } label: {
            Label("Riproduci dopo", systemImage: "text.insert")
        }
        Button { player.addToQueue(tracks); done() } label: {
            Label("Aggiungi alla coda attuale", systemImage: "text.append")
        }
        Menu {
            ForEach(player.queues) { q in
                Button(q.name) { player.addToQueue(tracks, queueID: q.id); done() }
            }
            Divider()
            Button { player.addToNewQueue(tracks, name: sourceName); done() } label: {
                Label("Nuova coda", systemImage: "plus")
            }
        } label: {
            Label("Aggiungi a una coda…", systemImage: "list.number")
        }
        Button { ui.addToPlaylist = TrackIDList(ids: tracks.map(\.id)); done() } label: {
            Label("Aggiungi a playlist…", systemImage: "music.note.list")
        }
        Button { ui.tagEditor = TrackIDList(ids: tracks.map(\.id)); done() } label: {
            Label(tracks.count == 1 ? "Modifica tag…" : "Modifica tag di \(tracks.count) brani…", systemImage: "tag")
        }
        if tracks.count == 1, let t = tracks.first {
            Button { userData.toggleFavorite(t.id) } label: {
                if userData.isFavorite(t.id) {
                    Label("Rimuovi dai preferiti", systemImage: "heart.slash")
                } else {
                    Label("Aggiungi ai preferiti", systemImage: "heart")
                }
            }
            if showNavigation {
                Divider()
                if let albumID = library.albumID(for: t) {
                    Button { ui.navigate(.group(.album, albumID)) } label: {
                        Label("Vai all'album", systemImage: "square.stack")
                    }
                }
                let names = library.artistNames(for: t)
                if names.count == 1 {
                    Button { ui.navigate(.group(.artist, library.artistID(for: names[0]))) } label: {
                        Label("Vai all'artista", systemImage: "music.mic")
                    }
                } else {
                    Menu {
                        ForEach(names, id: \.self) { name in
                            Button(name) { ui.navigate(.group(.artist, library.artistID(for: name))) }
                        }
                    } label: {
                        Label("Vai all'artista", systemImage: "music.mic")
                    }
                }
                Button { ui.navigate(.group(.folder, library.folderID(for: t))) } label: {
                    Label("Vai alla cartella", systemImage: "folder")
                }
            }
            Button { ui.infoTrack = t } label: {
                Label("Informazioni", systemImage: "info.circle")
            }
        } else {
            Button { userData.addFavorites(tracks.map(\.id)); ui.showToast("Aggiunti ai preferiti"); done() } label: {
                Label("Aggiungi ai preferiti", systemImage: "heart")
            }
        }
    }

    private func done() {
        if clearsSelection { ui.clearSelection() }
    }
}

// MARK: - Mini player

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: UIState

    var body: some View {
        if let t = player.currentTrack {
            VStack(spacing: 0) {
                MiniProgress()
                HStack(spacing: 12) {
                    ArtworkView(track: t, maxPixel: 150, cornerRadius: 6)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(t.displayArtist) · \(player.activeQueue?.name ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 22) {
                        Button { player.previous() } label: { TransportIcon(glyph: .previous, size: 18) }
                        Button { player.togglePlayPause() } label: {
                            TransportIcon(glyph: player.isPlaying ? .pause : .play, size: 24)
                                .frame(width: 36, height: 36)
                        }
                        Button { player.next() } label: { TransportIcon(glyph: .next, size: 18) }
                    }
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .contentShape(Rectangle())
            .onTapGesture { ui.showNowPlaying = true }
        }
    }
}

private struct MiniProgress: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var clock: PlaybackClock

    var body: some View {
        GeometryReader { geo in
            let fraction = player.duration > 0 ? min(1, clock.time / player.duration) : 0
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * fraction)
        }
        .frame(height: 2)
    }
}

// MARK: - Avvisi e tema

struct ToastOverlay: View {
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack {
            Spacer()
            if let text = ui.toast {
                Text(text)
                    .font(.subheadline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: ui.toast)
        .allowsHitTesting(false)
    }
}

struct ThemedBackground: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        if settings.theme == .black {
            content
                .scrollContentBackground(.hidden)
                .background(Color.black)
        } else {
            content
        }
    }
}

extension View {
    func themedBackground() -> some View { modifier(ThemedBackground()) }
}

struct LibraryEmptyView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ContentUnavailableView {
            Label(library.isScanning ? "Scansione in corso…" : "Nessun brano", systemImage: "music.note.house")
        } description: {
            Text("Copia la musica nella cartella AuguMusic dell'app File (Sull'iPad), oppure aggiungi una cartella da Impostazioni.")
        }
    }
}
