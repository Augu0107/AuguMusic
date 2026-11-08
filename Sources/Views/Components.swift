import SwiftUI

// MARK: - Copertina

struct ArtworkView: View {
    @EnvironmentObject private var library: LibraryStore
    let track: Track?
    var maxPixel: CGFloat = 150
    var cornerRadius: CGFloat = 6

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: track?.id) {
                image = nil
                guard let track, let url = library.url(for: track) else { return }
                image = await ArtworkLoader.shared.image(for: track, url: url, maxPixel: maxPixel)
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
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            Text(formatTime(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Menu azioni sui brani

struct TrackMenu: View {
    let tracks: [Track]
    var sourceName: String = "Coda"
    var showNavigation = true

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        if tracks.count > 1 {
            Button { player.play(tracks, startAt: 0, source: sourceName) } label: {
                Label("Riproduci", systemImage: "play")
            }
            Button { player.shuffleAndPlay(tracks, source: sourceName) } label: {
                Label("Riproduci in ordine casuale", systemImage: "shuffle")
            }
        }
        Button { player.playNext(tracks) } label: {
            Label("Riproduci dopo", systemImage: "text.insert")
        }
        Button { player.addToQueue(tracks) } label: {
            Label("Aggiungi alla coda attuale", systemImage: "text.append")
        }
        Menu {
            ForEach(player.queues) { q in
                Button(q.name) { player.addToQueue(tracks, queueID: q.id) }
            }
            Divider()
            Button { player.addToNewQueue(tracks, name: sourceName) } label: {
                Label("Nuova coda", systemImage: "plus")
            }
        } label: {
            Label("Aggiungi a una coda…", systemImage: "list.number")
        }
        Button { ui.addToPlaylist = TrackIDList(ids: tracks.map(\.id)) } label: {
            Label("Aggiungi a playlist…", systemImage: "music.note.list")
        }
        Button { ui.tagEditor = TrackIDList(ids: tracks.map(\.id)) } label: {
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
            Button { userData.addFavorites(tracks.map(\.id)); ui.showToast("Aggiunti ai preferiti") } label: {
                Label("Aggiungi ai preferiti", systemImage: "heart")
            }
        }
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
                        Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .frame(width: 36)
                        }
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
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
