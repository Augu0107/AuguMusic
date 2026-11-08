import AVFoundation
import Foundation
import SFBAudioEngine

// MARK: - Lettura dei tag

enum MetadataReader {
    static func read(_ entry: FileEntry, dateAdded: Date) async -> Track {
        var t = Track(id: entry.id, folderID: entry.folderID, relativePath: entry.relativePath,
                      fileSize: entry.size, modified: entry.modified, dateAdded: dateAdded)

        if entry.url.pathExtension.lowercased() == "flac" {
            if let info = FLACParser.parse(url: entry.url, includePicture: false) {
                t.duration = info.duration
                apply(vorbis: info.comments, to: &t)
            }
            if t.duration <= 0 { t.duration = await assetDuration(entry.url) }
            return t
        }

        if avFoundationExtensions.contains(entry.url.pathExtension.lowercased()) {
            let asset = AVURLAsset(url: entry.url)
            if let d = try? await asset.load(.duration), d.isNumeric { t.duration = d.seconds }
            if let formats = try? await asset.load(.availableMetadataFormats) {
                for format in formats {
                    if let items = try? await asset.loadMetadata(for: format) {
                        await apply(items: items, to: &t)
                    }
                }
            }
            let tagsComplete = !t.title.isEmpty && !t.artist.isEmpty && !t.album.isEmpty
            if t.duration > 0 && tagsComplete { return t }
        }
        // iOS non lo apre o non trova tutti i tag (ID3 particolari, Ogg, Opus...): TagLib completa i campi mancanti.
        applyTagLib(url: entry.url, to: &t)
        return t
    }

    static let avFoundationExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "aifc", "caf", "alac", "mp4"]

    static func openTagLibFile(_ url: URL) -> AudioFile? {
        guard let file = try? AudioFile(url: url, detectContentType: true) else { return nil }
        do {
            try file.readPropertiesAndMetadata()
            return file
        } catch {
            return nil
        }
    }

    static func applyTagLib(url: URL, to t: inout Track) {
        guard let file = openTagLibFile(url) else { return }
        let m = file.metadata
        // Riempie solo i campi vuoti: quello che iOS ha già letto resta com'è.
        func take(_ value: String?, _ field: inout String) {
            guard field.isEmpty else { return }
            if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { field = v }
        }
        take(m.title, &t.title)
        take(m.artist, &t.artist)
        take(m.albumTitle, &t.album)
        take(m.albumArtist, &t.albumArtist)
        take(m.composer, &t.composer)
        take(m.genre, &t.genre)
        if t.year == nil, let y = parseYear(m.releaseDate) { t.year = y }
        if t.trackNumber == nil, let n = m.trackNumber, n > 0 { t.trackNumber = n }
        if t.discNumber == nil, let n = m.discNumber, n > 0 { t.discNumber = n }
        if t.replayGainTrack == nil, let g = m.replayGainTrackGain { t.replayGainTrack = g }
        if t.replayGainAlbum == nil, let g = m.replayGainAlbumGain { t.replayGainAlbum = g }
        if t.duration <= 0, let d = file.properties.duration, d > 0 { t.duration = d }
        t.formatName = file.properties.formatName
    }

    static func assetDuration(_ url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration), d.isNumeric { return d.seconds }
        return 0
    }

    private static func setIfEmpty(_ field: inout String, _ value: String?) {
        guard field.isEmpty, let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
        field = v.replacingOccurrences(of: "\u{0}", with: ";")
    }

    static func apply(items: [AVMetadataItem], to t: inout Track) async {
        for item in items {
            guard let ident = item.identifier else { continue }
            let str = try? await item.load(.stringValue)
            switch ident {
            case .commonIdentifierTitle, .id3MetadataTitleDescription, .iTunesMetadataSongName, .quickTimeMetadataTitle:
                setIfEmpty(&t.title, str)
            case .commonIdentifierArtist, .id3MetadataLeadPerformer, .iTunesMetadataArtist, .quickTimeMetadataArtist:
                setIfEmpty(&t.artist, str)
            case .commonIdentifierAlbumName, .id3MetadataAlbumTitle, .iTunesMetadataAlbum, .quickTimeMetadataAlbum:
                setIfEmpty(&t.album, str)
            case .id3MetadataBand, .iTunesMetadataAlbumArtist:
                setIfEmpty(&t.albumArtist, str)
            case .id3MetadataComposer, .iTunesMetadataComposer, .quickTimeMetadataComposer:
                setIfEmpty(&t.composer, str)
            case .id3MetadataContentType, .iTunesMetadataUserGenre, .quickTimeMetadataGenre:
                setIfEmpty(&t.genre, cleanGenre(str))
            case .id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate,
                 .commonIdentifierCreationDate, .quickTimeMetadataYear:
                if t.year == nil { t.year = parseYear(str) }
            case .id3MetadataTrackNumber, .iTunesMetadataTrackNumber:
                if t.trackNumber == nil { t.trackNumber = await parseNumber(item, str) }
            case .id3MetadataPartOfASet, .iTunesMetadataDiscNumber:
                if t.discNumber == nil { t.discNumber = await parseNumber(item, str) }
            case .id3MetadataUserText:
                if let attrs = try? await item.load(.extraAttributes),
                   let info = attrs[.info] as? String {
                    applyReplayGain(key: info, value: str, to: &t)
                }
            default:
                break
            }
        }
    }

    static func apply(vorbis c: [String: [String]], to t: inout Track) {
        func first(_ keys: String...) -> String? {
            for k in keys {
                if let v = c[k]?.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { return v }
            }
            return nil
        }
        func all(_ key: String) -> String? {
            guard let values = c[key]?.filter({ !$0.isEmpty }), !values.isEmpty else { return nil }
            return values.joined(separator: "; ")
        }
        if let v = first("TITLE") { t.title = v }
        if let v = all("ARTIST") { t.artist = v }
        if let v = first("ALBUM") { t.album = v }
        if let v = first("ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST") { t.albumArtist = v }
        if let v = all("COMPOSER") { t.composer = v }
        if let v = all("GENRE") { t.genre = v }
        t.year = parseYear(first("DATE", "YEAR", "ORIGINALDATE"))
        t.trackNumber = parseInt(first("TRACKNUMBER"))
        t.discNumber = parseInt(first("DISCNUMBER"))
        t.replayGainTrack = parseGain(first("REPLAYGAIN_TRACK_GAIN"))
        t.replayGainAlbum = parseGain(first("REPLAYGAIN_ALBUM_GAIN"))
    }

    private static func applyReplayGain(key: String, value: String?, to t: inout Track) {
        switch key.uppercased() {
        case "REPLAYGAIN_TRACK_GAIN": t.replayGainTrack = parseGain(value)
        case "REPLAYGAIN_ALBUM_GAIN": t.replayGainAlbum = parseGain(value)
        default: break
        }
    }

    private static func parseNumber(_ item: AVMetadataItem, _ s: String?) async -> Int? {
        if let n = parseInt(s) { return n }
        if let data = try? await item.load(.dataValue), data.count >= 4 {
            let bytes = [UInt8](data)
            let n = Int(bytes[2]) << 8 | Int(bytes[3])
            return n > 0 ? n : nil
        }
        if let number = try? await item.load(.numberValue) {
            let n = number.intValue
            return n > 0 ? n : nil
        }
        return nil
    }

    static func parseInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        let head = s.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard let n = Int(head), n > 0 else { return nil }
        return n
    }

    static func parseYear(_ s: String?) -> Int? {
        guard let s, let r = s.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(s[r])
    }

    static func parseGain(_ s: String?) -> Double? {
        guard let s else { return nil }
        let token = s.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        return Double(token.replacingOccurrences(of: "+", with: ""))
    }

    private static func cleanGenre(_ s: String?) -> String? {
        guard let s else { return nil }
        let cleaned = s.replacingOccurrences(of: #"^\(\d+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? s : cleaned
    }

    // MARK: Testi incorporati

    static func embeddedLyrics(url: URL) async -> String? {
        if url.pathExtension.lowercased() == "flac" {
            guard let info = FLACParser.parse(url: url, includePicture: false) else { return nil }
            for key in ["LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "SYNCEDLYRICS"] {
                if let v = info.comments[key]?.first, !v.isEmpty { return v }
            }
            return nil
        }
        let asset = AVURLAsset(url: url)
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                guard let items = try? await asset.loadMetadata(for: format) else { continue }
                for item in items {
                    guard let ident = item.identifier,
                          ident == .id3MetadataUnsynchronizedLyric || ident == .iTunesMetadataLyrics else { continue }
                    if let s = try? await item.load(.stringValue), !s.isEmpty { return s }
                }
            }
        }
        if let lyrics = openTagLibFile(url)?.metadata.lyrics, !lyrics.isEmpty { return lyrics }
        return nil
    }
}

// MARK: - FLAC (commenti Vorbis e copertina)

struct FLACInfo {
    var comments: [String: [String]] = [:]
    var duration: Double = 0
    var picture: Data?
}

enum FLACParser {
    static func parse(url: URL, includePicture: Bool) -> FLACInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard var head = try? handle.read(upToCount: 10), head.count >= 4 else { return nil }
        var offset: UInt64 = 0
        if head.count >= 10, head.starts(with: [0x49, 0x44, 0x33]) { // tag ID3 davanti al FLAC
            let b = [UInt8](head)
            let s1 = UInt64(b[6] & 0x7f) << 21
            let s2 = UInt64(b[7] & 0x7f) << 14
            let s3 = UInt64(b[8] & 0x7f) << 7
            let s4 = UInt64(b[9] & 0x7f)
            offset = 10 + s1 + s2 + s3 + s4
            try? handle.seek(toOffset: offset)
            guard let h = try? handle.read(upToCount: 4), h.count == 4 else { return nil }
            head = h
        }
        guard [UInt8](head.prefix(4)) == [0x66, 0x4C, 0x61, 0x43] else { return nil } // "fLaC"
        offset += 4
        try? handle.seek(toOffset: offset)

        var info = FLACInfo()
        var isLast = false
        var blocks = 0
        while !isLast && blocks < 128 {
            blocks += 1
            guard let h = try? handle.read(upToCount: 4), h.count == 4 else { break }
            let b = [UInt8](h)
            isLast = (b[0] & 0x80) != 0
            let type = b[0] & 0x7f
            let length = (Int(b[1]) << 16) | (Int(b[2]) << 8) | Int(b[3])
            offset += 4
            let wanted = type == 0 || type == 4 || (type == 6 && includePicture && info.picture == nil)
            if wanted, length < 60_000_000,
               let body = try? handle.read(upToCount: length), body.count == length {
                let d = [UInt8](body)
                switch type {
                case 0: parseStreamInfo(d, &info)
                case 4: parseComments(d, &info)
                case 6: parsePicture(d, &info)
                default: break
                }
            }
            offset += UInt64(length)
            try? handle.seek(toOffset: offset)
        }
        return info
    }

    private static func parseStreamInfo(_ d: [UInt8], _ info: inout FLACInfo) {
        guard d.count >= 18 else { return }
        let sr1 = Int(d[10]) << 12
        let sr2 = Int(d[11]) << 4
        let sr3 = Int(d[12]) >> 4
        let sampleRate = sr1 | sr2 | sr3
        let t1 = (UInt64(d[13]) & 0x0F) << 32
        let t2 = UInt64(d[14]) << 24
        let t3 = UInt64(d[15]) << 16
        let t4 = UInt64(d[16]) << 8
        let t5 = UInt64(d[17])
        let total = t1 | t2 | t3 | t4 | t5
        if sampleRate > 0 { info.duration = Double(total) / Double(sampleRate) }
    }

    private static func le32(_ d: [UInt8], _ i: Int) -> Int {
        Int(d[i]) | (Int(d[i + 1]) << 8) | (Int(d[i + 2]) << 16) | (Int(d[i + 3]) << 24)
    }

    private static func be32(_ d: [UInt8], _ i: Int) -> Int {
        (Int(d[i]) << 24) | (Int(d[i + 1]) << 16) | (Int(d[i + 2]) << 8) | Int(d[i + 3])
    }

    private static func parseComments(_ d: [UInt8], _ info: inout FLACInfo) {
        guard d.count >= 8 else { return }
        var i = 4 + le32(d, 0)
        guard i + 4 <= d.count else { return }
        let count = le32(d, i)
        i += 4
        for _ in 0..<min(count, 10_000) {
            guard i + 4 <= d.count else { break }
            let len = le32(d, i)
            i += 4
            guard len >= 0, i + len <= d.count else { break }
            if let s = String(bytes: d[i..<(i + len)], encoding: .utf8), let eq = s.firstIndex(of: "=") {
                let key = s[..<eq].uppercased()
                let value = String(s[s.index(after: eq)...])
                info.comments[key, default: []].append(value)
            }
            i += len
        }
    }

    private static func parsePicture(_ d: [UInt8], _ info: inout FLACInfo) {
        guard d.count > 32 else { return }
        var i = 4
        let mimeLen = be32(d, i)
        i += 4 + mimeLen
        guard i + 4 <= d.count else { return }
        let descLen = be32(d, i)
        i += 4 + descLen + 16
        guard i + 4 <= d.count else { return }
        let len = be32(d, i)
        i += 4
        guard len > 0, i + len <= d.count else { return }
        info.picture = Data(d[i..<(i + len)])
    }
}
