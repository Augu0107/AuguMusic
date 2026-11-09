import SwiftUI
import WidgetKit

// MARK: - Widget HomeScreen

enum WidgetSettings {
    static let prefix = "widget."

    static func options() -> [String: Bool] {
        var out: [String: Bool] = [:]
        for (key, def) in WidgetOption.defaults {
            out[key] = UserDefaults.standard.object(forKey: prefix + key) as? Bool ?? def
        }
        return out
    }

    static func set(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: prefix + key)
    }
}

struct WidgetSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerController
    @AppStorage("widgetSettingsTab") private var tab = 0
    @State private var options = WidgetSettings.options()

    private var snapshot: WidgetSnapshot {
        var s = WidgetSnapshot.load() ?? .placeholder
        s.theme = settings.widgetStyle.rawValue
        s.options = options
        if s.queue == nil { s.queue = WidgetSnapshot.placeholder.queue }
        return s
    }

    var body: some View {
        SettingsPage(title: "Widget HomeScreen") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    preview
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemBackground))

                    Text("Tema del widget:")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 30)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    ForEach(WidgetStyle.allCases) { style in
                        Button { settings.widgetStyle = style; refresh() } label: {
                            HStack(spacing: 22) {
                                RadioMark(selected: settings.widgetStyle == style)
                                Text(L(style.label)).foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 34)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 0) {
                        tabButton("SEMPLICE", 0)
                        tabButton("AVANZATI", 1)
                        tabButton("CODA CORRENTE", 2)
                    }
                    .padding(.top, 26)
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case 0:
                            check("Copertina Album", WidgetOption.simpleArt)
                        case 1:
                            check("Copertina Album", WidgetOption.advancedArt)
                            check("Aggiungi alle playlist", WidgetOption.advancedPlaylist)
                            check("Aggiungi/rimuovi dai preferiti", WidgetOption.advancedFavorite)
                            check("Pulsanti Avanti-veloce e Riavvolgi", WidgetOption.advancedSeek)
                        default:
                            check("Copertina Album", WidgetOption.queueArt)
                            check("Aggiungi alle playlist", WidgetOption.queuePlaylist)
                            check("Aggiungi/rimuovi dai preferiti", WidgetOption.queueFavorite)
                            check("Pulsanti Avanti-veloce e Riavvolgi", WidgetOption.queueSeek)
                        }
                    }
                    .padding(.top, 10)

                    Text("Per aggiungere un widget: tieni premuto sulla Home dell'iPad → Modifica → Aggiungi widget → AuguMusic, poi scegli \"Semplice\", \"Avanzati\" o \"Coda corrente\".")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(30)
                    if !WidgetBridge.shared.isAvailable {
                        Text("Il widget non riesce a ricevere i dati: l'App Group non è attivo. Prova a reinstallare l'app con AltStore.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 30)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let snap = snapshot
        let art = WidgetSnapshot.loadArtwork()
        Group {
            switch tab {
            case 0: SimpleWidgetContent(snap: snap, artwork: art).frame(width: 340, height: 110)
            case 1: AdvancedWidgetContent(snap: snap, artwork: art).frame(width: 340, height: 130)
            default: QueueWidgetContent(snap: snap, artwork: art, rows: 4).frame(width: 340, height: 330)
            }
        }
        .padding(18)
        .background(WidgetBackground(snap: snap))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .allowsHitTesting(false)
    }

    private func tabButton(_ title: String, _ i: Int) -> some View {
        Button { tab = i } label: {
            VStack(spacing: 10) {
                Text(L(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tab == i ? Color.primary : Color.secondary)
                Rectangle().fill(tab == i ? Color.primary : Color.clear).frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func check(_ title: String, _ key: String) -> some View {
        Button {
            options[key] = !(options[key] ?? false)
            WidgetSettings.set(key, options[key] ?? false)
            refresh()
        } label: {
            HStack(spacing: 18) {
                CheckMark(checked: options[key] ?? false)
                Text(L(title)).foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refresh() {
        WidgetBridge.shared.invalidate()
        player.refreshWidget()
    }
}
