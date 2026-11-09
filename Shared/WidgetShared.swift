import AppIntents
import SwiftUI
import UIKit

// Codice condiviso tra l'app e il widget.

// MARK: - App Group (compatibile con AltStore)

enum AppGroup {
    static let baseIdentifier = "group.com.augugames.augumusic"

    /// AltStore aggiunge il Team ID al nome del gruppo: provo tutte le varianti possibili.
    static let containerURL: URL? = {
        var candidates: [String] = []
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            candidates.append(contentsOf: groups)
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            for part in bundleID.split(separator: ".") where part.count == 10 && part.allSatisfy({ $0.isUppercase || $0.isNumber }) {
                candidates.append(baseIdentifier + "." + part)
            }
        }
        candidates.append(baseIdentifier)
        for id in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        return nil
    }()
}

// MARK: - Stato mostrato dal widget

struct WidgetQueueItem: Codable, Hashable {
    var number: Int
    var title: String
    var artist: String
    var duration: String
    var isCurrent: Bool
}

/// Opzioni dei tre widget (Semplice, Avanzati, Coda corrente), scelte nelle Impostazioni dell'app.
enum WidgetOption {
    static let simpleArt = "simple.art"
    static let advancedArt = "advanced.art"
    static let advancedPlaylist = "advanced.playlist"
    static let advancedFavorite = "advanced.favorite"
    static let advancedSeek = "advanced.seek"
    static let queueArt = "queue.art"
    static let queuePlaylist = "queue.playlist"
    static let queueFavorite = "queue.favorite"
    static let queueSeek = "queue.seek"

    static let defaults: [String: Bool] = [
        simpleArt: true,
        advancedArt: true, advancedPlaylist: false, advancedFavorite: false, advancedSeek: false,
        queueArt: true, queuePlaylist: true, queueFavorite: true, queueSeek: false,
    ]
}

struct WidgetSnapshot: Codable {
    var trackID: String?
    var title: String
    var artist: String
    var album: String
    var queueName: String
    var position: String
    var isPlaying: Bool
    var isFavorite: Bool
    var upNext: [String]
    var background: [Double]
    var accent: [Double]
    var updated: Date
    /// "light", "dark", "system", "artwork"
    var theme: String? = nil
    var options: [String: Bool]? = nil
    var queue: [WidgetQueueItem]? = nil

    func option(_ key: String) -> Bool { options?[key] ?? WidgetOption.defaults[key] ?? false }

    static let placeholder = WidgetSnapshot(trackID: nil, title: "Titolo del brano", artist: "Artista", album: "Album",
                                            queueName: "Coda", position: "1/12", isPlaying: false, isFavorite: false,
                                            upNext: ["Brano successivo", "Un altro brano", "E un altro ancora"],
                                            background: [0.32, 0.18, 0.12], accent: [1.0, 0.62, 0.3], updated: Date(),
                                            theme: "artwork", options: nil,
                                            queue: [WidgetQueueItem(number: 1, title: "Titolo", artist: "Artista", duration: "3:12", isCurrent: true),
                                                    WidgetQueueItem(number: 2, title: "Brano successivo", artist: "Artista", duration: "4:05", isCurrent: false),
                                                    WidgetQueueItem(number: 3, title: "Un altro brano", artist: "Artista", duration: "2:58", isCurrent: false)])

    private static let fileName = "widget.json"
    private static let artworkName = "widget-artwork.jpg"

    var backgroundColor: Color { Self.color(background, fallback: Color(red: 0.2, green: 0.2, blue: 0.22)) }
    var accentColor: Color { Self.color(accent, fallback: .orange) }

    private static func color(_ c: [Double], fallback: Color) -> Color {
        guard c.count >= 3 else { return fallback }
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    static func load() -> WidgetSnapshot? {
        guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = AppGroup.containerURL?.appendingPathComponent(Self.fileName),
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadArtwork() -> UIImage? {
        guard let url = AppGroup.containerURL?.appendingPathComponent(artworkName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func saveArtwork(_ image: UIImage?) {
        guard let url = AppGroup.containerURL?.appendingPathComponent(artworkName) else { return }
        if let data = image?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Pulsanti del widget (eseguiti dentro l'app)

struct WidgetTogglePlayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play/Pausa"
    init() {}
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared?.togglePlayPause() }
        #endif
        return .result()
    }
}

struct WidgetNextIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Brano successivo"
    init() {}
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared?.next() }
        #endif
        return .result()
    }
}

struct WidgetPreviousIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Brano precedente"
    init() {}
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared?.previous() }
        #endif
        return .result()
    }
}

struct WidgetRewindIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Indietro di 10 secondi"
    init() {}
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared?.seekBackward() }
        #endif
        return .result()
    }
}

struct WidgetForwardIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Avanti di 10 secondi"
    init() {}
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared?.seekForward() }
        #endif
        return .result()
    }
}

struct WidgetFavoriteIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Preferito"
    init() {}
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared?.toggleCurrentFavorite() }
        #endif
        return .result()
    }
}
