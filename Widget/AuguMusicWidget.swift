import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let artwork: UIImage?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .placeholder, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: WidgetSnapshot.load(), artwork: WidgetSnapshot.loadArtwork())
    }
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        let snap = entry.snapshot
        Group {
            if let snap {
                switch family {
                case .systemSmall: small(snap)
                case .systemMedium: medium(snap)
                default: large(snap)
                }
            } else {
                empty
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            let bg = snap?.backgroundColor ?? Color(red: 0.16, green: 0.16, blue: 0.18)
            LinearGradient(colors: [bg, bg.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(Color.black)
        }
        .widgetURL(URL(string: "augumusic://nowplaying"))
    }

    // MARK: Parti comuni

    private var artwork: some View {
        Group {
            if let image = entry.artwork {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note").font(.title2).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func titles(_ snap: WidgetSnapshot, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snap.title)
                .font(big ? .headline : .subheadline.weight(.semibold))
                .lineLimit(big ? 2 : 1)
            Text(snap.artist)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private func controlButton<I: AppIntent>(_ intent: I, _ icon: String, size: Font = .title3) -> some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(size)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func controls(_ snap: WidgetSnapshot, full: Bool) -> some View {
        HStack(spacing: 0) {
            if full {
                controlButton(WidgetFavoriteIntent(), snap.isFavorite ? "heart.fill" : "heart", size: .body)
            }
            controlButton(WidgetPreviousIntent(), "backward.fill")
            if full { controlButton(WidgetRewindIntent(), "gobackward.10", size: .body) }
            controlButton(WidgetTogglePlayIntent(), snap.isPlaying ? "pause.circle.fill" : "play.circle.fill", size: .largeTitle)
                .foregroundStyle(snap.accentColor)
            if full { controlButton(WidgetForwardIntent(), "goforward.10", size: .body) }
            controlButton(WidgetNextIntent(), "forward.fill")
        }
    }

    // MARK: Dimensioni

    private func small(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                artwork.frame(width: 58, height: 58)
                Spacer(minLength: 4)
                Button(intent: WidgetTogglePlayIntent()) {
                    Image(systemName: snap.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(snap.accentColor)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            titles(snap, big: false)
            HStack {
                controlButton(WidgetPreviousIntent(), "backward.fill", size: .callout)
                controlButton(WidgetNextIntent(), "forward.fill", size: .callout)
            }
        }
    }

    private func medium(_ snap: WidgetSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                artwork.frame(width: 64, height: 64)
                titles(snap, big: true)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            controls(snap, full: true)
        }
    }

    private func large(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                artwork.frame(width: family == .systemExtraLarge ? 110 : 84, height: family == .systemExtraLarge ? 110 : 84)
                VStack(alignment: .leading, spacing: 4) {
                    titles(snap, big: true)
                    Text(snap.album)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            controls(snap, full: true)
            Divider().overlay(Color.white.opacity(0.25))
            HStack {
                Text(snap.queueName).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(snap.position).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            let rows = family == .systemExtraLarge ? 9 : 5
            ForEach(Array(snap.upNext.prefix(rows).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.title)
            Text("Apri AuguMusic e fai partire un brano")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
}

struct AuguMusicWidget: Widget {
    let kind = "AuguMusicNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("In riproduzione")
        .description("Il brano attuale, con i colori presi dalla copertina.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct AuguMusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        AuguMusicWidget()
    }
}
