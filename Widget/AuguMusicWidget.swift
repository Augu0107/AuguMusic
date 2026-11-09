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

/// Contenitore comune: sfondo, link all'app e messaggio quando non suona niente.
private struct WidgetShell<Content: View>: View {
    let entry: NowPlayingEntry
    @ViewBuilder let content: (WidgetSnapshot) -> Content

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                content(snap)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list").font(.title)
                    Text("Apri AuguMusic e fai partire un brano")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) { WidgetBackground(snap: entry.snapshot) }
        .widgetURL(URL(string: "augumusic://nowplaying"))
    }
}

struct SimpleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AuguMusicSimple", provider: NowPlayingProvider()) { entry in
            SimpleFamilyView(entry: entry)
        }
        .configurationDisplayName("Semplice")
        .description("Precedente, play sulla copertina, titolo e successivo.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SimpleFamilyView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetShell(entry: entry) { snap in
            SimpleWidgetContent(snap: snap, artwork: entry.artwork, small: family == .systemSmall)
        }
    }
}

struct AdvancedWidget: Widget {
    // Stesso "kind" del vecchio widget, così quello già sulla Home non sparisce.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AuguMusicNowPlaying", provider: NowPlayingProvider()) { entry in
            WidgetShell(entry: entry) { snap in
                AdvancedWidgetContent(snap: snap, artwork: entry.artwork)
            }
        }
        .configurationDisplayName("Avanzati")
        .description("Copertina, titolo e tutti i comandi.")
        .supportedFamilies([.systemMedium])
    }
}

struct QueueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AuguMusicQueue", provider: NowPlayingProvider()) { entry in
            QueueFamilyView(entry: entry)
        }
        .configurationDisplayName("Coda corrente")
        .description("Il brano attuale e i brani della coda.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

private struct QueueFamilyView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetShell(entry: entry) { snap in
            QueueWidgetContent(snap: snap, artwork: entry.artwork, rows: family == .systemExtraLarge ? 9 : 5)
        }
    }
}

@main
struct AuguMusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        SimpleWidget()
        AdvancedWidget()
        QueueWidget()
    }
}
