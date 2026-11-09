import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, black, timeBased, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Tema chiaro"
        case .dark: "Tema scuro"
        case .black: "Tema nero (AMOLED)"
        case .timeBased: "Giorno/notte tempo"
        case .system: "Segui il tema chiaro/scuro del sistema"
        }
    }

    /// Giorno/notte: chiaro dalle 7 alle 19, scuro il resto del tempo.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .black: return .dark
        case .timeBased:
            let hour = Calendar.current.component(.hour, from: Date())
            return (7..<19).contains(hour) ? .light : .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, red, pink, purple, indigo, blue, cyan, teal, mint, green, yellow, brown, gray
    var id: String { rawValue }

    var label: String {
        switch self {
        case .orange: "Arancione"
        case .red: "Rosso"
        case .pink: "Rosa"
        case .purple: "Viola"
        case .indigo: "Indaco"
        case .blue: "Blu"
        case .cyan: "Azzurro"
        case .teal: "Verde acqua"
        case .mint: "Menta"
        case .green: "Verde"
        case .yellow: "Giallo"
        case .brown: "Marrone"
        case .gray: "Grigio"
        }
    }

    var color: Color {
        switch self {
        case .orange: Color(red: 1.0, green: 0.55, blue: 0.24)
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .indigo: .indigo
        case .blue: .blue
        case .cyan: .cyan
        case .teal: .teal
        case .mint: .mint
        case .green: .green
        case .yellow: .yellow
        case .brown: .brown
        case .gray: .gray
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
        case .off: "spento"
        case .track: "Track gain"
        case .album: "Album gain"
        }
    }
}

/// Impostazioni dell'equalizzatore salvate per un dispositivo d'uscita (cuffie, altoparlante...).
struct EQProfile: Codable {
    var enabled: Bool
    var gains: [Double]
    var preamp: Double
    var bassBoost: Double
    var surround: Double
    var presetName: String
    var volume: Double
    var mono: Bool
    var balance: Double
    var bands: Int
}

enum WidgetStyle: String, CaseIterable, Identifiable {
    case light, dark, system, artwork
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "Tema chiaro"
        case .dark: "Tema scuro"
        case .system: "Abbina al sistema"
        case .artwork: "Adattamento dalla copertina dell'album"
        }
    }
}

struct EQPreset: Identifiable {
    let name: String
    let gains: [Double]
    var id: String { name }
}

enum EQPresets {
    static let frequencyLabels = ["31,5", "63", "125", "250", "500", "1 k", "2 k", "4 k", "8 k", "16 k"]
    /// Con 5 bande: quali delle 10 si usano (le altre restano a 0).
    static let fiveBandIndices = [1, 3, 5, 7, 9]

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

    /// Sfumatura del volume quando parte / va in pausa, in millisecondi (0 = niente).
    @Published var fadeInMs: Double { didSet { defaults.set(fadeInMs, forKey: "fadeInMs") } }
    @Published var fadeOutMs: Double { didSet { defaults.set(fadeOutMs, forKey: "fadeOutMs") } }
    @Published var gapless: Bool { didSet { defaults.set(gapless, forKey: "gapless") } }
    /// Focus audio: 0 = suona insieme alle altre app, 1 = pausa per le altre app, 2 = pausa e poi riprende.
    @Published var audioFocus: Int { didSet { defaults.set(audioFocus, forKey: "audioFocus") } }
    @Published var resumeAfterCall: Bool { didSet { defaults.set(resumeAfterCall, forKey: "resumeAfterCall") } }
    /// "augu" = prima SFBAudioEngine, "system" = prima il decoder di Apple.
    @Published var decoder: String { didSet { defaults.set(decoder, forKey: "decoder") } }
    /// "augu" = equalizzatore dell'app, "none" = nessun effetto.
    @Published var eqChoice: String { didSet { defaults.set(eqChoice, forKey: "eqChoice") } }
    @Published var reverbEnabled: Bool { didSet { defaults.set(reverbEnabled, forKey: "reverbEnabled") } }
    @Published var reverbPreset: Int { didSet { defaults.set(reverbPreset, forKey: "reverbPreset") } }
    @Published var reverbMix: Double { didSet { defaults.set(reverbMix, forKey: "reverbMix") } }
    @Published var blockZeroVolume: Bool { didSet { defaults.set(blockZeroVolume, forKey: "blockZeroVolume") } }
    @Published var pauseOnMute: Bool { didSet { defaults.set(pauseOnMute, forKey: "pauseOnMute") } }
    @Published var resumeOnUnmute: Bool { didSet { defaults.set(resumeOnUnmute, forKey: "resumeOnUnmute") } }
    @Published var replayGainPreampNoRG: Double { didSet { defaults.set(replayGainPreampNoRG, forKey: "replayGainPreampNoRG") } }
    /// Leggi/calcola RG del brano attuale e del successivo: "off", "tags", "analyze".
    @Published var rgAuto: String { didSet { defaults.set(rgAuto, forKey: "rgAuto") } }
    /// Velocità e tono salvati per singoli file: id brano → [velocità, semitoni].
    @Published var fileSpeeds: [String: [Double]] { didSet { defaults.set(fileSpeeds, forKey: "fileSpeeds") } }
    /// Secondi di sovrapposizione tra un brano e il successivo (0 = stacco netto).
    @Published var crossfadeDuration: Double { didSet { defaults.set(crossfadeDuration, forKey: "crossfadeDuration") } }
    @Published var replayGain: ReplayGainMode { didSet { defaults.set(replayGain.rawValue, forKey: "replayGain") } }
    @Published var replayGainPreamp: Double { didSet { defaults.set(replayGainPreamp, forKey: "replayGainPreamp") } }

    @Published var eqEnabled: Bool { didSet { defaults.set(eqEnabled, forKey: "eqEnabled") } }
    @Published var eqGains: [Double] { didSet { defaults.set(eqGains, forKey: "eqGains") } }
    @Published var eqPreamp: Double { didSet { defaults.set(eqPreamp, forKey: "eqPreamp") } }
    @Published var bassBoost: Double { didSet { defaults.set(bassBoost, forKey: "bassBoost") } }
    /// Suono surround 0...1.
    @Published var surround: Double { didSet { defaults.set(surround, forKey: "surround") } }
    /// Volume interno dell'app 0...1.
    @Published var eqVolume: Double { didSet { defaults.set(eqVolume, forKey: "eqVolume") } }
    @Published var mono: Bool { didSet { defaults.set(mono, forKey: "mono") } }
    /// Numero di bande mostrate: 5 o 10.
    @Published var eqBands: Int { didSet { defaults.set(eqBands, forKey: "eqBands") } }
    /// Dispositivo d'uscita a cui appartengono le impostazioni attuali dell'equalizzatore.
    @Published private(set) var eqDevice: String { didSet { defaults.set(eqDevice, forKey: "eqDevice") } }
    /// Impostazioni salvate degli altri dispositivi.
    @Published private(set) var eqProfiles: [String: EQProfile] {
        didSet { defaults.set(try? JSONEncoder().encode(eqProfiles), forKey: "eqProfiles") }
    }
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
        // Dalla v0.7 la dissolvenza è in millisecondi, separata per play e pausa.
        let oldFade = d.bool(forKey: "fadeEnabled") ? (d.object(forKey: "fadeDuration") as? Double ?? 0.4) * 1000 : 0
        fadeInMs = double("fadeInMs", oldFade)
        fadeOutMs = double("fadeOutMs", oldFade)
        gapless = bool("gapless", true)
        audioFocus = d.object(forKey: "audioFocus") as? Int ?? 2
        resumeAfterCall = bool("resumeAfterCall", true)
        decoder = d.string(forKey: "decoder") ?? "system"
        eqChoice = d.string(forKey: "eqChoice") ?? "augu"
        reverbEnabled = bool("reverbEnabled", false)
        reverbPreset = d.object(forKey: "reverbPreset") as? Int ?? 1
        reverbMix = double("reverbMix", 25)
        blockZeroVolume = bool("blockZeroVolume", true)
        pauseOnMute = bool("pauseOnMute", true)
        resumeOnUnmute = bool("resumeOnUnmute", true)
        crossfadeDuration = double("crossfadeDuration", 3)
        replayGain = ReplayGainMode(rawValue: d.string(forKey: "replayGain") ?? "") ?? .off
        replayGainPreamp = double("replayGainPreamp", 0)
        replayGainPreampNoRG = double("replayGainPreampNoRG", 0)
        rgAuto = d.string(forKey: "rgAuto") ?? "analyze"
        fileSpeeds = d.dictionary(forKey: "fileSpeeds") as? [String: [Double]] ?? [:]

        eqEnabled = bool("eqEnabled", false)
        var gains = d.array(forKey: "eqGains") as? [Double] ?? []
        if gains.count != 10 { gains = Array(repeating: 0, count: 10) }
        eqGains = gains
        eqPreamp = double("eqPreamp", 0)
        bassBoost = double("bassBoost", 0)
        surround = double("surround", 0)
        eqVolume = double("eqVolume", 1)
        mono = bool("mono", false)
        eqBands = d.object(forKey: "eqBands") as? Int ?? 10
        eqDevice = d.string(forKey: "eqDevice") ?? ""
        if let data = d.data(forKey: "eqProfiles"), let profiles = try? JSONDecoder().decode([String: EQProfile].self, from: data) {
            eqProfiles = profiles
        } else {
            eqProfiles = [:]
        }
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

    // MARK: Equalizzatore per dispositivo

    var currentEQProfile: EQProfile {
        EQProfile(enabled: eqEnabled, gains: eqGains, preamp: eqPreamp, bassBoost: bassBoost, surround: surround,
                  presetName: eqPresetName, volume: eqVolume, mono: mono, balance: balance, bands: eqBands)
    }

    private func apply(_ p: EQProfile) {
        eqEnabled = p.enabled
        eqGains = p.gains.count == 10 ? p.gains : Array(repeating: 0, count: 10)
        eqPreamp = p.preamp
        bassBoost = p.bassBoost
        surround = p.surround
        eqPresetName = p.presetName
        eqVolume = p.volume
        mono = p.mono
        balance = p.balance
        eqBands = p.bands
    }

    /// Le cuffie/l'altoparlante sono cambiati: salva le impostazioni del vecchio e carica quelle del nuovo.
    func switchEQDevice(to name: String) {
        guard !name.isEmpty, name != eqDevice else { return }
        if !eqDevice.isEmpty { eqProfiles[eqDevice] = currentEQProfile }
        if let saved = eqProfiles[name] { apply(saved) }
        eqProfiles[name] = nil
        eqDevice = name
    }

    var otherEQDevices: [String] { eqProfiles.keys.sorted() }

    func forgetEQDevice(_ name: String) { eqProfiles[name] = nil }

    func resetEQ() {
        eqGains = Array(repeating: 0, count: 10)
        eqPresetName = "Flat"
        eqPreamp = 0
        bassBoost = 0
        surround = 0
        eqVolume = 1
        mono = false
        balance = 0
    }

    // MARK: Velocità per file

    func speedAndPitch(for trackID: String?) -> (speed: Double, pitch: Double, perFile: Bool) {
        if let id = trackID, let v = fileSpeeds[id], v.count == 2 { return (v[0], v[1], true) }
        return (speed, pitch, false)
    }
}
