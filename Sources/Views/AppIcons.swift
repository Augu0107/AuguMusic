import SwiftUI

/// Icone stile Musicolet. Dove SF Symbols ha già la forma giusta uso quella, il resto è disegnato.
enum AppGlyph: Hashable {
    case queue, nowPlaying, folders, albums, artists, genres, playlists, albumArtists, composers, more, search
    case allSongs, favorites, recentlyAdded, recentlyPlayed, mostPlayed, neverPlayed, playlist
}

struct AppIconView: View {
    let glyph: AppGlyph
    var size: CGFloat = 22

    var body: some View {
        content
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var content: some View {
        switch glyph {
        case .queue:
            symbol("music.note.list")
        case .nowPlaying:
            symbol("play.circle")
        case .folders:
            symbol("folder.fill")
        case .albums:
            VinylShape().fill(.foreground, style: FillStyle(eoFill: true))
        case .artists:
            symbol("person.fill")
        case .genres:
            symbol("tag.fill")
        case .playlists:
            PlaylistsIcon()
        case .albumArtists:
            symbol("person.2.fill")
        case .composers:
            symbol("music.quarternote.3")
        case .more:
            symbol("ellipsis")
        case .search:
            symbol("magnifyingglass")
        case .allSongs:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                    .stroke(.foreground, lineWidth: max(1.5, size * 0.08))
                    .frame(width: size * 0.78, height: size)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.5, weight: .semibold))
            }
        case .favorites:
            symbol("heart.fill")
        case .recentlyAdded:
            badged("clock", badge: "plus.circle.fill")
        case .recentlyPlayed:
            badged("clock", badge: "play.circle.fill")
        case .mostPlayed:
            symbol("flame.fill")
        case .neverPlayed:
            symbol("nosign")
        case .playlist:
            PlaylistRowsIcon()
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
    }

    private func badged(_ name: String, badge: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .padding(.trailing, size * 0.12)
                .padding(.bottom, size * 0.12)
            Image(systemName: badge)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.48, height: size * 0.48)
                .background(Circle().fill(Color(uiColor: .systemBackground)).padding(-1))
        }
    }
}

/// Disco vinile: cerchio pieno, anello trasparente, puntino al centro.
private struct VinylShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let hole = r * 0.46
        p.addEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: hole * 2, height: hole * 2))
        let dot = r * 0.2
        p.addEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
        return p
    }
}

/// Quadrato con la nota davanti e, dietro, solo il bordo basso di un altro quadrato.
private struct PlaylistsIcon: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let line = max(1.5, s * 0.08)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: s * 0.12, style: .continuous)
                    .stroke(.foreground, lineWidth: line)
                    .frame(width: s * 0.78, height: s * 0.78)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: s * 0.42, weight: .bold))
                    }
                Rectangle()
                    .fill(.foreground)
                    .frame(width: s * 0.78, height: line)
                    .offset(x: s * 0.22, y: s - line)
                Rectangle()
                    .fill(.foreground)
                    .frame(width: line, height: s * 0.78)
                    .offset(x: s - line, y: s * 0.22)
            }
            .frame(width: s, height: s, alignment: .topLeading)
        }
    }
}

/// Tre quadratini uno sotto l'altro, ognuno con un rettangolino accanto.
private struct PlaylistRowsIcon: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let box = s * 0.24
            VStack(alignment: .leading, spacing: (s - box * 3) / 2) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: s * 0.12) {
                        RoundedRectangle(cornerRadius: box * 0.2).fill(.foreground).frame(width: box, height: box)
                        RoundedRectangle(cornerRadius: box * 0.2).fill(.foreground).frame(width: s * 0.58, height: box * 0.55)
                    }
                }
            }
            .frame(width: s, height: s)
        }
    }
}

/// Tasto ⋯ dei brani: tre pallini grandi che vanno quasi da bordo a bordo.
struct DotsGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let d = w * 0.2
            HStack(spacing: (w * 0.84 - d * 3) / 2) {
                Circle().frame(width: d, height: d)
                Circle().frame(width: d, height: d)
                Circle().frame(width: d, height: d)
            }
            .frame(width: w, height: geo.size.height)
        }
    }
}
