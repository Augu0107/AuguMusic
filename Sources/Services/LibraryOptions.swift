import Foundation

/// Opzioni di "Libreria brani e tag", lette una volta (anche fuori dal main thread).
struct LibraryOptions: Sendable, Equatable {
    var minDuration: Int
    var preferTagLib: Bool
    var albumArtistFallback: Bool
    var scanHidden: Bool
    var scanNomedia: Bool
    var scanVideo: Bool
    var albumMerge: Set<String>
    var multiArtist: Bool
    var multiAlbumArtist: Bool
    var multiComposer: Bool
    var multiGenre: Bool
    var sepArtist: [String]
    var sepAlbumArtist: [String]
    var sepComposer: [String]
    var sepGenre: [String]
    var hideExtraAll: Bool

    static func current() -> LibraryOptions {
        func seps(_ key: String) -> [String] {
            Prefs.string(key).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        }
        return LibraryOptions(
            minDuration: Prefs.int(Prefs.minDuration),
            preferTagLib: Prefs.string(Prefs.scannerPref) == "augu",
            albumArtistFallback: Prefs.bool(Prefs.albumArtistFallback),
            scanHidden: Prefs.bool(Prefs.scanHidden),
            scanNomedia: Prefs.bool(Prefs.scanNomedia),
            scanVideo: Prefs.bool(Prefs.scanVideo),
            albumMerge: Prefs.string(Prefs.albumMerge).csvItems,
            multiArtist: Prefs.bool(Prefs.multiArtist),
            multiAlbumArtist: Prefs.bool(Prefs.multiAlbumArtist),
            multiComposer: Prefs.bool(Prefs.multiComposer),
            multiGenre: Prefs.bool(Prefs.multiGenre),
            sepArtist: seps(Prefs.sepArtist),
            sepAlbumArtist: seps(Prefs.sepAlbumArtist),
            sepComposer: seps(Prefs.sepComposer),
            sepGenre: seps(Prefs.sepGenre),
            hideExtraAll: Prefs.bool(Prefs.hideExtraAll)
        )
    }

    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "3gp", "3gpp", "mkv", "webm", "avi"]
}

// MARK: - Nascondi contenuti extra dai tag

/// Toglie siti web, "320kbps" e simili da titoli/artisti/album.
enum TagCleaner {
    /// Vale per tutti i brani (impostazione "Tutti i brani"). Aggiornato quando cambia la preferenza.
    nonisolated(unsafe) static var cleanEverywhere = Prefs.bool(Prefs.hideExtraAll)

    private static let domain = try! NSRegularExpression(
        pattern: #"(?i)(https?://)?(www\.)?[a-z0-9][a-z0-9\-]*(\.[a-z0-9\-]+)*\.(com|net|org|info|in|co|me|io|pk|ru|xyz|cc|biz|to|fm|club|site|online|live|website|mobi|link|top|eu|us|uk|it|pw|ws|tk|ml|ga|cf|gq)(/\S*)?"#)
    private static let bitrate = try! NSRegularExpression(pattern: #"(?i)\b\d{2,3}\s?kbps\b"#)
    private static let emptyBrackets = try! NSRegularExpression(pattern: #"[\(\[\{]\s*[\)\]\}]"#)
    private static let edgeJunk = CharacterSet(charactersIn: " -–—|:_,.~/\\").union(.whitespacesAndNewlines)

    static func clean(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var s = text
        for re in [domain, bitrate, emptyBrackets] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = emptyBrackets.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        // Separatori rimasti soli (" - | ") in mezzo o in fondo.
        while let r = s.range(of: #"\s[-–—|]\s+[-–—|]\s"#, options: .regularExpression) { s.replaceSubrange(r, with: " - ") }
        s = s.trimmingCharacters(in: edgeJunk)
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.isEmpty ? text : s
    }

    static func everywhere(_ text: String) -> String { cleanEverywhere ? clean(text) : text }

    /// Copia del brano con i tag "puliti", per In riproduzione, schermata di blocco e widget.
    static func forNowPlaying(_ t: Track) -> Track {
        guard Prefs.bool(Prefs.hideExtraNowPlaying) || cleanEverywhere else { return t }
        var c = t
        c.title = clean(t.title)
        c.artist = clean(t.artist)
        c.album = clean(t.album)
        c.albumArtist = clean(t.albumArtist)
        return c
    }

    static func nowPlaying(_ text: String) -> String {
        (Prefs.bool(Prefs.hideExtraNowPlaying) || cleanEverywhere) ? clean(text) : text
    }
}

// MARK: - Cartelle con un solo album (per "Usa i file folder.jpg...")

final class FolderAlbumIndex: @unchecked Sendable {
    static let shared = FolderAlbumIndex()
    private let lock = NSLock()
    private var singleAlbumDirs: Set<String> = []

    func update(_ dirs: Set<String>) {
        lock.lock()
        singleAlbumDirs = dirs
        lock.unlock()
    }

    func isSingleAlbum(_ dir: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return singleAlbumDirs.contains(dir.standardizedFileURL.path)
    }
}
