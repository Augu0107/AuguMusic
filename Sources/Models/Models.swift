import Foundation
import SwiftUI

// MARK: - Brano

struct Track: Codable, Identifiable, Hashable {
    var id: String
    var folderID: UUID
    var relativePath: String
    var fileSize: Int64
    var modified: Date
    var dateAdded: Date
    var title: String = ""
    var artist: String = ""
    var albumArtist: String = ""
    var album: String = ""
    var composer: String = ""
    var genre: String = ""
    var year: Int? = nil
    var trackNumber: Int? = nil
    var discNumber: Int? = nil
    var duration: Double = 0
    var replayGainTrack: Double? = nil
    var replayGainAlbum: Double? = nil
    /// Formato riconosciuto da TagLib quando l'estensione non basta (nil = normale).
    var formatName: String? = nil

    static func == (a: Track, b: Track) -> Bool { a.id == b.id && a.modified == b.modified }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var fileName: String { (relativePath as NSString).lastPathComponent }
    var fileExtension: String { (relativePath as NSString).pathExtension.lowercased() }
    var directory: String { (relativePath as NSString).deletingLastPathComponent }

    var displayTitle: String {
        if title.isEmpty || SortText.showFileName { return (fileName as NSString).deletingPathExtension }
        return TagCleaner.everywhere(title)
    }
    var displayArtist: String { artist.isEmpty ? "Artista sconosciuto" : TagCleaner.everywhere(artist) }
    var displayAlbum: String { album.isEmpty ? "Album sconosciuto" : TagCleaner.everywhere(album) }
    var displayAlbumArtist: String { albumArtist.isEmpty ? displayArtist : TagCleaner.everywhere(albumArtist) }

    var genreList: [String] {
        let parts = genre.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? ["Genere sconosciuto"] : parts
    }
}

// MARK: - Separatore artisti

enum ArtistSplitter {
    /// Divide "Karen Méndez & Mike Bahía" in due artisti. Le eccezioni (es. "Simon & Garfunkel") non vengono mai divise.
    static func split(_ text: String, separators: [String], exceptions: [String]) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var work = trimmed
        var protected: [(token: String, original: String)] = []
        for (i, ex) in exceptions.enumerated() {
            let exTrim = ex.trimmingCharacters(in: .whitespaces)
            guard !exTrim.isEmpty else { continue }
            let token = "\u{E000}\(i)\u{E001}"
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            if work.range(of: exTrim, options: options) != nil {
                work = work.replacingOccurrences(of: exTrim, with: token, options: options)
                protected.append((token, exTrim))
            }
        }
        var parts = [work]
        for sep in separators where !sep.isEmpty {
            parts = parts.flatMap { splitCaseInsensitive($0, by: sep) }
        }
        var seen = Set<String>()
        var out: [String] = []
        for var p in parts {
            for item in protected { p = p.replacingOccurrences(of: item.token, with: item.original) }
            let clean = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { continue }
            out.append(clean)
        }
        return out
    }

    private static func splitCaseInsensitive(_ s: String, by sep: String) -> [String] {
        var result: [String] = []
        var rest = Substring(s)
        while let r = rest.range(of: sep, options: .caseInsensitive) {
            result.append(String(rest[rest.startIndex..<r.lowerBound]))
            rest = rest[r.upperBound...]
        }
        result.append(String(rest))
        return result
    }
}

// MARK: - Cartelle della libreria

struct LibraryFolder: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var bookmark: Data?
    var isAppDocuments: Bool
}

// MARK: - Raggruppamenti

enum GroupKind: String, Hashable, CaseIterable, Codable {
    case album, artist, albumArtist, genre, composer, folder

    var title: String {
        switch self {
        case .album: "Album"
        case .artist: "Artisti"
        case .albumArtist: "Artisti album"
        case .genre: "Generi"
        case .composer: "Compositori"
        case .folder: "Cartelle"
        }
    }

    var icon: String {
        switch self {
        case .album: "square.stack"
        case .artist: "music.mic"
        case .albumArtist: "person.2"
        case .genre: "guitars"
        case .composer: "music.quarternote.3"
        case .folder: "folder"
        }
    }
}

struct TrackGroup: Identifiable, Hashable {
    let kind: GroupKind
    let id: String
    let name: String
    let subtitle: String
    let trackIDs: [String]
    let year: Int?
    var duration: Double = 0

    static func == (a: TrackGroup, b: TrackGroup) -> Bool { a.kind == b.kind && a.id == b.id && a.trackIDs.count == b.trackIDs.count }
    func hash(into hasher: inout Hasher) { hasher.combine(kind); hasher.combine(id) }
}

enum Route: Hashable {
    case group(GroupKind, String)
    case playlist(UUID)
    case favorites
    case queue(UUID)
    case smart(SmartList)
    case search
}

/// Playlist automatiche della scheda Playlist (come Musicolet).
enum SmartList: String, Hashable, CaseIterable, Identifiable {
    case allSongs, recentlyAdded, recentlyPlayed, mostPlayed, neverPlayed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allSongs: "Tutti i brani"
        case .recentlyAdded: "Aggiunti di recente"
        case .recentlyPlayed: "Riprodotti di recente"
        case .mostPlayed: "Più riprodotti"
        case .neverPlayed: "Mai riprodotti"
        }
    }
}

struct PlayStat: Codable, Equatable {
    var count: Int
    var lastPlayed: Date
}

// MARK: - Code

struct PlayQueue: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var items: [String]
    /// Ordine originale, presente solo quando la modalità casuale è attiva.
    var unshuffled: [String]? = nil
    var index: Int = 0
    var elapsed: Double = 0

    var isShuffled: Bool { unshuffled != nil }
    var currentID: String? { items.indices.contains(index) ? items[index] : nil }

    mutating func insertNext(_ ids: [String]) {
        let pos = items.isEmpty ? 0 : min(index + 1, items.count)
        items.insert(contentsOf: ids, at: pos)
        unshuffled?.append(contentsOf: ids)
    }

    mutating func append(_ ids: [String]) {
        items.append(contentsOf: ids)
        unshuffled?.append(contentsOf: ids)
    }

    /// Ritorna true se il brano in riproduzione è stato rimosso.
    @discardableResult
    mutating func remove(atOffsets offsets: IndexSet) -> Bool {
        let removedIDs = offsets.compactMap { items.indices.contains($0) ? items[$0] : nil }
        var tagged = Array(items.enumerated())
        tagged.remove(atOffsets: offsets)
        items = tagged.map { $0.element }
        var currentRemoved = false
        if let newIndex = tagged.firstIndex(where: { $0.offset == index }) {
            index = newIndex
        } else {
            currentRemoved = true
            let before = offsets.filter { $0 < index }.count
            index = max(0, min(index - before, items.count - 1))
            elapsed = 0
        }
        if unshuffled != nil {
            for id in removedIDs {
                if let i = unshuffled?.firstIndex(of: id) { unshuffled?.remove(at: i) }
            }
        }
        return currentRemoved
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var tagged = Array(items.enumerated())
        tagged.move(fromOffsets: source, toOffset: destination)
        items = tagged.map { $0.element }
        if let i = tagged.firstIndex(where: { $0.offset == index }) { index = i }
    }

    mutating func setShuffle(_ on: Bool, onlyAfterCurrent: Bool = false) {
        if on {
            guard unshuffled == nil else { return }
            unshuffled = items
            if onlyAfterCurrent { shuffleAfterCurrent() } else { shuffleKeepingCurrent() }
        } else {
            guard let original = unshuffled else { return }
            let current = currentID
            var counts: [String: Int] = [:]
            for id in items { counts[id, default: 0] += 1 }
            var restored: [String] = []
            for id in original where (counts[id] ?? 0) > 0 {
                restored.append(id)
                counts[id]! -= 1
            }
            for id in items where (counts[id] ?? 0) > 0 {
                restored.append(id)
                counts[id]! -= 1
            }
            items = restored
            unshuffled = nil
            if let current, let i = items.firstIndex(of: current) { index = i } else { index = 0 }
        }
    }

    mutating func reshuffle() {
        guard isShuffled else { return }
        shuffleKeepingCurrent()
    }

    /// Mescola solo i brani dopo quello in riproduzione (quelli prima restano dove sono).
    private mutating func shuffleAfterCurrent() {
        guard index + 1 < items.count else { return }
        let head = Array(items[...index])
        items = head + items[(index + 1)...].shuffled()
    }

    /// Ordine casuale permanente (non si può "togliere" come la modalità casuale).
    mutating func randomize(onlyAfterCurrent: Bool) {
        unshuffled = nil
        if onlyAfterCurrent { shuffleAfterCurrent() } else { shuffleKeepingCurrent() }
    }

    private mutating func shuffleKeepingCurrent() {
        guard let current = currentID else { items.shuffle(); index = 0; return }
        var rest = items
        rest.remove(at: index)
        rest.shuffle()
        items = [current] + rest
        index = 0
    }
}

struct QueueSnapshot: Codable {
    var queues: [PlayQueue]
    var activeQueueID: UUID?
}

// MARK: - Dati utente

struct Playlist: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var items: [String]
    var created = Date()
}

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var trackID: String
    var time: Double
    var note: String
    var created = Date()
}

struct TrackIDList: Identifiable {
    let id = UUID()
    let ids: [String]
}

// MARK: - Modalità di riproduzione

enum RepeatMode: String, CaseIterable, Identifiable, Codable {
    case repeatQueue, repeatSong, jumpToNextQueue, stopAfterQueue, stopAfterSong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .repeatQueue: "Ripeti la coda"
        case .repeatSong: "Ripeti il brano"
        case .jumpToNextQueue: "Passa alla coda successiva"
        case .stopAfterQueue: "Ferma a fine coda"
        case .stopAfterSong: "Ferma dopo ogni brano"
        }
    }

    var icon: String {
        switch self {
        case .repeatQueue: "repeat"
        case .repeatSong: "repeat.1"
        case .jumpToNextQueue: "arrow.turn.down.right"
        case .stopAfterQueue: "arrow.right.to.line"
        case .stopAfterSong: "stop.circle"
        }
    }
}

enum SleepMode: Equatable {
    case at(Date)
    case afterCurrentSong
    case afterSongs(Int)
}

struct SleepTimer: Equatable {
    var mode: SleepMode
    var finishCurrentSong: Bool
}

struct ABRepeat: Equatable {
    var a: Double?
    var b: Double?
    var isActive: Bool { a != nil && b != nil }
}

// MARK: - Utilità

enum Storage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuguMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

extension String {
    func matchesSearch(_ query: String) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    func localizedLess(_ other: String) -> Bool {
        localizedStandardCompare(other) == .orderedAscending
    }
}
