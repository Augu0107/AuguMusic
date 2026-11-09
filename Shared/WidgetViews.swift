import AppIntents
import SwiftUI
import WidgetKit

// Disegno dei tre widget. È qui (codice condiviso) così l'app può mostrarne l'anteprima nelle Impostazioni.

/// Colori del widget secondo il tema scelto.
struct WidgetPalette {
    let background: Color
    let title: Color
    let text: Color
    let icon: Color
    let line: Color

    init(snap: WidgetSnapshot, scheme: ColorScheme) {
        let theme = snap.theme ?? "artwork"
        let dark = theme == "dark" || (theme == "system" && scheme == .dark)
        switch theme {
        case "light", "dark", "system":
            background = dark ? Color(red: 0.13, green: 0.13, blue: 0.15) : Color.white
            title = snap.accentColor
            text = dark ? Color.white.opacity(0.75) : Color.black.opacity(0.6)
            icon = snap.accentColor
            line = dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
        default:
            background = snap.backgroundColor
            title = snap.accentColor
            text = snap.accentColor.opacity(0.8)
            icon = snap.accentColor
            line = Color.white.opacity(0.18)
        }
    }
}

/// Copertina quadrata ad angoli vivi.
struct WidgetArtwork: View {
    let image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .widgetFullColor()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                } else {
                    ZStack {
                        Color.gray.opacity(0.25)
                        Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
    }
}

private struct IntentGlyph<I: AppIntent>: View {
    let intent: I
    let glyph: TransportGlyph
    let size: CGFloat

    var body: some View {
        Button(intent: intent) {
            TransportIcon(glyph: glyph, size: size)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct IntentSymbol<I: AppIntent>: View {
    let intent: I
    let symbol: String

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Riga dei comandi: (preferito) ⏮ (−10) ▶ (+10) ⏭ (playlist).
private struct WidgetControls: View {
    let snap: WidgetSnapshot
    let favorite: Bool
    let seek: Bool
    let playlist: Bool
    let size: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if favorite { IntentSymbol(intent: WidgetFavoriteIntent(), symbol: snap.isFavorite ? "heart.fill" : "heart") }
            IntentGlyph(intent: WidgetPreviousIntent(), glyph: .previous, size: size * 0.7)
            if seek { IntentSymbol(intent: WidgetRewindIntent(), symbol: "gobackward.10") }
            IntentGlyph(intent: WidgetTogglePlayIntent(), glyph: snap.isPlaying ? .pause : .play, size: size)
            if seek { IntentSymbol(intent: WidgetForwardIntent(), symbol: "goforward.10") }
            IntentGlyph(intent: WidgetNextIntent(), glyph: .next, size: size * 0.7)
            if playlist {
                Link(destination: URL(string: "augumusic://addtoplaylist")!) {
                    Image(systemName: "text.badge.plus")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
        }
    }
}

// MARK: - Semplice

struct SimpleWidgetContent: View {
    let snap: WidgetSnapshot
    let artwork: UIImage?
    var small = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = WidgetPalette(snap: snap, scheme: scheme)
        let showArt = snap.option(WidgetOption.simpleArt)
        Group {
            if small {
                VStack(spacing: 8) {
                    playOverArt(showArt: showArt, size: 70, p: p)
                    Text(snap.title).font(.subheadline.weight(.semibold)).foregroundStyle(p.title).lineLimit(1)
                    HStack {
                        IntentGlyph(intent: WidgetPreviousIntent(), glyph: .previous, size: 16)
                        IntentGlyph(intent: WidgetNextIntent(), glyph: .next, size: 16)
                    }
                    .foregroundStyle(p.icon)
                }
            } else {
                HStack(spacing: 14) {
                    IntentGlyph(intent: WidgetPreviousIntent(), glyph: .previous, size: 20)
                        .frame(width: 44)
                    playOverArt(showArt: showArt, size: 76, p: p)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snap.title).font(.headline).foregroundStyle(p.title).lineLimit(1)
                        Text(snap.artist).font(.subheadline).foregroundStyle(p.text).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    IntentGlyph(intent: WidgetNextIntent(), glyph: .next, size: 20)
                        .frame(width: 44)
                }
                .foregroundStyle(p.icon)
            }
        }
    }

    /// Copertina con il tasto play sopra (o solo il tasto se la copertina è nascosta).
    private func playOverArt(showArt: Bool, size: CGFloat, p: WidgetPalette) -> some View {
        Button(intent: WidgetTogglePlayIntent()) {
            ZStack {
                if showArt {
                    WidgetArtwork(image: artwork).frame(width: size, height: size)
                }
                TransportIcon(glyph: snap.isPlaying ? .pause : .play, size: size * 0.38)
                    .foregroundStyle(p.icon)
                    .shadow(color: .black.opacity(showArt ? 0.35 : 0), radius: 3)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avanzati

struct AdvancedWidgetContent: View {
    let snap: WidgetSnapshot
    let artwork: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = WidgetPalette(snap: snap, scheme: scheme)
        HStack(spacing: 14) {
            if snap.option(WidgetOption.advancedArt) {
                WidgetArtwork(image: artwork).frame(width: 96, height: 96)
            }
            VStack(spacing: 8) {
                Text(snap.title).font(.headline).foregroundStyle(p.title).lineLimit(1)
                Text(snap.artist).font(.subheadline).foregroundStyle(p.text).lineLimit(1)
                WidgetControls(snap: snap,
                               favorite: snap.option(WidgetOption.advancedFavorite),
                               seek: snap.option(WidgetOption.advancedSeek),
                               playlist: snap.option(WidgetOption.advancedPlaylist),
                               size: 30)
                    .foregroundStyle(p.icon)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Coda corrente

struct QueueWidgetContent: View {
    let snap: WidgetSnapshot
    let artwork: UIImage?
    var rows = 5
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = WidgetPalette(snap: snap, scheme: scheme)
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if snap.option(WidgetOption.queueArt) {
                    WidgetArtwork(image: artwork).frame(width: 64, height: 64)
                }
                VStack(spacing: 6) {
                    Text(snap.title).font(.headline).foregroundStyle(p.title).lineLimit(1)
                    WidgetControls(snap: snap,
                                   favorite: snap.option(WidgetOption.queueFavorite),
                                   seek: snap.option(WidgetOption.queueSeek),
                                   playlist: snap.option(WidgetOption.queuePlaylist),
                                   size: 26)
                        .foregroundStyle(p.icon)
                }
            }
            VStack(spacing: 0) {
                Text("\(snap.queueName) (\(snap.position))")
                    .font(.subheadline)
                    .foregroundStyle(p.text)
                    .padding(.vertical, 6)
                ForEach((snap.queue ?? []).prefix(rows), id: \.self) { item in
                    HStack(spacing: 12) {
                        Text("\(item.number)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(item.isCurrent ? p.title : p.text)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline).foregroundStyle(item.isCurrent ? p.title : p.text.opacity(1)).lineLimit(1)
                            Text(item.artist).font(.caption).foregroundStyle(p.text.opacity(0.8)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(item.duration).font(.caption.monospacedDigit()).foregroundStyle(p.text)
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 0.5) }
                }
            }
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(p.line.opacity(0.35)))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sfondo

struct WidgetBackground: View {
    let snap: WidgetSnapshot?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let snap {
            let p = WidgetPalette(snap: snap, scheme: scheme)
            if (snap.theme ?? "artwork") == "artwork" {
                LinearGradient(colors: [p.background, p.background.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .background(Color.black)
            } else {
                p.background
            }
        } else {
            Color(red: 0.16, green: 0.16, blue: 0.18)
        }
    }
}

extension Image {
    /// Con il tema "colorato" della Home la copertina resta a colori (come Musica di Apple).
    @ViewBuilder
    func widgetFullColor() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
