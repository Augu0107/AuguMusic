import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark, black
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Automatico"
        case .light: "Chiaro"
        case .dark: "Scuro"
        case .black: "Nero (AMOLED)"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .black: .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, blue, teal, green, pink, purple, red, yellow
    var id: String { rawValue }

    var label: String {
        switch self {
        case .orange: "Arancione"
        case .blue: "Blu"
        case .teal: "Verde acqua"
        case .green: "Verde"
        case .pink: "Rosa"
        case .purple: "Viola"
        case .red: "Rosso"
        case .yellow: "Giallo"
        }
    }

    var color: Color {
        switch self {
        case .orange: .orange
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .yellow: .yellow
        }
    }
}

enum TapAction: String, CaseIterable, Identifiable {
    case replaceQueue, newQueue
    var id: String { rawValue }
    var label: String {
        switch self {
        case .replaceQueue: "Sostituisci la coda attuale"
        case .newQueue: "Crea una nuova coda"
        }
    }
}

enum ReplayGainMode: String, CaseIterable, Identifiable {
    case off, track, album
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Disattivato"
        case .track: "Brano"
        case .album: "Album"
        }
    }
}

enum WidgetStyle: String, CaseIterable, Identifiable {
    case artwork, accent, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .artwork: "Dalla copertina"
        case .accent: "Colore d'accento"
        case .dark: "Scuro"
        }
    }
}

struct EQPreset: Identifiable {
    let name: String
    let gains: [Double]
    var id: String { name }
}

enum EQPresets {
    static let frequencyLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    static let builtIn: [EQPreset] = [
        EQPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bassi", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Rock", gains: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]),
        EQPreset(name: "Pop", gains: [-1, 0, 2, 4, 5, 4, 2, 0, -1, -1]),
        EQPreset(name: "Jazz", gains: [4, 3, 1, 2, -1, -1, 0, 1, 3, 4]),
        EQPreset(name: "Classica", gains: [5, 4, 3, 2, -1, -1, 0, 2, 3, 4]),
        EQPreset(name: "Elettronica", gains: [5, 4, 1, 0, -2, 2, 1, 1, 4, 5]),
        EQPreset(name: "Hip hop", gains: [5, 4, 1, 3, -1, -1, 1, -1, 2, 3]),
        EQPreset(name: "Voce", gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
        EQPreset(name: "Acustica", gains: [4, 4, 3, 1, 2, 2, 3, 3, 2, 1]),
        EQPreset(name: "Alti", gains: [0, 0, 0, 0, 0, 1, 3, 5, 6, 7]),
        EQPreset(name: "Notte (volume basso)", gains: [4, 3, 2, 0, 0, 0, 0, 1, 3, 4]),
    ]
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    @Published var tapAction: TapAction { didSet { defaults.set(tapAction.rawValue, forKey: "tapAction") } }
    @Published var maxQueues: Int { didSet { defaults.set(maxQueues, forKey: "maxQueues") } }
    @Published var confirmQueueRemoval: Bool { didSet { defaults.set(confirmQueueRemoval, forKey: "confirmQueueRemoval") } }
    @Published var keepScreenOn: Bool { didSet { defaults.set(keepScreenOn, forKey: "keepScreenOn") } }

    @Published var fadeEnabled: Bool { didSet { defaults.set(fadeEnabled, forKey: "fadeEnabled") } }
    @Published var fadeDuration: Double { didSet { defaults.set(fadeDuration, forKey: "fadeDuration") } }
    /// Secondi di sovrapposizione tra un brano e il successivo (0 = stacco netto).
    @Published var crossfadeDuration: Double { didSet { defaults.set(crossfadeDuration, forKey: "crossfadeDuration") } }
    @Published var replayGain: ReplayGainMode { didSet { defaults.set(replayGain.rawValue, forKey: "replayGain") } }
    @Published var replayGainPreamp: Double { didSet { defaults.set(replayGainPreamp, forKey: "replayGainPreamp") } }

    @Published var eqEnabled: Bool { didSet { defaults.set(eqEnabled, forKey: "eqEnabled") } }
    @Published var eqGains: [Double] { didSet { defaults.set(eqGains, forKey: "eqGains") } }
    @Published var eqPreamp: Double { didSet { defaults.set(eqPreamp, forKey: "eqPreamp") } }
    @Published var bassBoost: Double { didSet { defaults.set(bassBoost, forKey: "bassBoost") } }
    @Published var eqPresetName: String { didSet { defaults.set(eqPresetName, forKey: "eqPresetName") } }
    @Published var customPresets: [String: [Double]] { didSet { defaults.set(customPresets, forKey: "customPresets") } }

    @Published var speed: Double { didSet { defaults.set(speed, forKey: "speed") } }
    @Published var pitch: Double { didSet { defaults.set(pitch, forKey: "pitch") } }
    @Published var balance: Double { didSet { defaults.set(balance, forKey: "balance") } }

    @Published var artistSeparators: [String] { didSet { defaults.set(artistSeparators, forKey: "artistSeparators") } }
    @Published var artistExceptions: [String] { didSet { defaults.set(artistExceptions, forKey: "artistExceptions") } }
    @Published var hiddenTabs: [String] { didSet { defaults.set(hiddenTabs, forKey: "hiddenTabs") } }
    @Published var widgetStyle: WidgetStyle { didSet { defaults.set(widgetStyle.rawValue, forKey: "widgetStyle") } }
    /// Scheda aperta all'avvio (rawValue di MainTab).
    @Published var startTab: String { didSet { defaults.set(startTab, forKey: "startTab") } }

    init() {
        let d = UserDefaults.standard
        func double(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) as? Double ?? fallback }
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }

        theme = AppTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .orange
        tapAction = TapAction(rawValue: d.string(forKey: "tapAction") ?? "") ?? .replaceQueue
        maxQueues = d.object(forKey: "maxQueues") as? Int ?? 20
        confirmQueueRemoval = bool("confirmQueueRemoval", true)
        keepScreenOn = bool("keepScreenOn", false)

        // La dissolvenza su play/pausa ora parte spenta (Musicolet non la fa). Spenta una volta anche per chi l'aveva.
        if !d.bool(forKey: "fadeOffV1") {
            d.set(false, forKey: "fadeEnabled")
            d.set(true, forKey: "fadeOffV1")
        }
        fadeEnabled = bool("fadeEnabled", false)
        fadeDuration = double("fadeDuration", 0.4)
        crossfadeDuration = double("crossfadeDuration", 3)
        replayGain = ReplayGainMode(rawValue: d.string(forKey: "replayGain") ?? "") ?? .off
        replayGainPreamp = double("replayGainPreamp", 0)

        eqEnabled = bool("eqEnabled", false)
        var gains = d.array(forKey: "eqGains") as? [Double] ?? []
        if gains.count != 10 { gains = Array(repeating: 0, count: 10) }
        eqGains = gains
        eqPreamp = double("eqPreamp", 0)
        bassBoost = double("bassBoost", 0)
        eqPresetName = d.string(forKey: "eqPresetName") ?? "Flat"
        customPresets = d.dictionary(forKey: "customPresets") as? [String: [Double]] ?? [:]

        speed = double("speed", 1)
        pitch = double("pitch", 0)
        balance = double("balance", 0)

        artistSeparators = d.stringArray(forKey: "artistSeparators") ?? [";", "&"]
        artistExceptions = d.stringArray(forKey: "artistExceptions") ?? []
        // v0.4: schede in basso. Artisti album e Compositori partono nascoste, come in Musicolet.
        if !d.bool(forKey: "bottomTabsV1") {
            d.set(["albumArtists", "composers"], forKey: "hiddenTabs")
            d.set(true, forKey: "bottomTabsV1")
        }
        hiddenTabs = d.stringArray(forKey: "hiddenTabs") ?? []
        widgetStyle = WidgetStyle(rawValue: d.string(forKey: "widgetStyle") ?? "") ?? .artwork
        startTab = d.string(forKey: "startTab") ?? "albums"
    }

    func isTabHidden(_ raw: String) -> Bool { hiddenTabs.contains(raw) }

    func setTab(_ raw: String, hidden: Bool) {
        if hidden {
            if !hiddenTabs.contains(raw) { hiddenTabs.append(raw) }
        } else {
            hiddenTabs.removeAll { $0 == raw }
        }
    }

    func applyPreset(name: String, gains: [Double]) {
        guard gains.count == 10 else { return }
        eqGains = gains
        eqPresetName = name
    }

    func resetPlaybackEffects() {
        speed = 1
        pitch = 0
        balance = 0
    }
}
