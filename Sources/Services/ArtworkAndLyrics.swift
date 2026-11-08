import AVFoundation
import ImageIO
import SFBAudioEngine
import UIKit

// MARK: - Copertine

final class ArtworkLoader: @unchecked Sendable {
    static let shared = ArtworkLoader()

    private final class Box {
        let image: UIImage?
        init(_ image: UIImage?) { self.image = image }
    }

    private let cache = NSCache<NSString, Box>()

    private init() {
        cache.countLimit = 500
    }

    func image(for track: Track, url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(track.id)#\(Int(maxPixel))#\(track.modified.timeIntervalSince1970)" as NSString
        if let box = cache.object(forKey: key) { return box.image }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = await ArtworkLoader.artworkData(url: url) else { return nil }
            return ArtworkLoader.downscale(data, maxPixel: maxPixel)
        }.value
        cache.setObject(Box(image), forKey: key)
        return image
    }

    static func artworkData(url: URL) async -> Data? {
        if url.pathExtension.lowercased() == "flac" {
            if let picture = FLACParser.parse(url: url, includePicture: true)?.picture { return picture }
        } else {
            let asset = AVURLAsset(url: url)
            if let items = try? await asset.load(.commonMetadata) {
                for item in items where item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue) { return data }
                }
            }
        }
        // TagLib (file con estensione sbagliata, Ogg, Opus...)
        if let metadata = MetadataReader.openTagLibFile(url)?.metadata {
            if let front = metadata.attachedPictures(ofType: .frontCover).first { return front.imageData }
            if let any = metadata.attachedPictures.first { return any.imageData }
        }
        // Copertina nella cartella (cover.jpg, folder.jpg, ...)
        let dir = url.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let names = ["cover", "folder", "front", "albumart", "album"]
        for name in names {
            if let file = files.first(where: {
                $0.deletingPathExtension().lastPathComponent.lowercased() == name &&
                    ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased())
            }), let data = try? Data(contentsOf: file) {
                return data
            }
        }
        return nil
    }

    static func downscale(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Testi

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double?
    let text: String
}

struct Lyrics: Equatable {
    var lines: [LyricLine]
    var synced: Bool
    var source: String

    func currentLineID(at time: Double) -> Int? {
        guard synced else { return nil }
        var current: Int?
        for line in lines {
            guard let t = line.time else { continue }
            if t <= time + 0.15 { current = line.id } else { break }
        }
        return current
    }
}

enum LyricsLoader {
    static func load(url: URL) async -> Lyrics? {
        let dir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            if let lrc = files.first(where: {
                $0.pathExtension.lowercased() == "lrc" && $0.deletingPathExtension().lastPathComponent.lowercased() == baseName
            }), let text = readText(lrc) {
                return parse(text, source: "File .lrc")
            }
            if let txt = files.first(where: {
                $0.pathExtension.lowercased() == "txt" && $0.deletingPathExtension().lastPathComponent.lowercased() == baseName
            }), let text = readText(txt) {
                return parse(text, source: "File .txt")
            }
        }
        if let text = await MetadataReader.embeddedLyrics(url: url),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return parse(text, source: "Testo nei tag")
        }
        return nil
    }

    static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)

    static func parse(_ text: String, source: String) -> Lyrics {
        var offset = 0.0
        var timed: [(Double, String)] = []
        var plain: [String] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("[offset:") {
                let value = line.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces)
                offset = (Double(value) ?? 0) / 1000
                continue
            }
            let ns = line as NSString
            let matches = timeTag.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty {
                if line.range(of: #"^\[[A-Za-z#]+:.*\]$"#, options: .regularExpression) != nil { continue }
                plain.append(raw)
                continue
            }
            let last = matches[matches.count - 1]
            var lyric = ns.substring(from: last.range.location + last.range.length)
            lyric = lyric.replacingOccurrences(of: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    fraction = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                timed.append((minutes * 60 + seconds + fraction, lyric))
            }
        }

        if !timed.isEmpty {
            let sorted = timed.sorted { $0.0 < $1.0 }
            let lines = sorted.enumerated().map { i, item in
                LyricLine(id: i, time: max(0, item.0 - offset), text: item.1)
            }
            return Lyrics(lines: lines, synced: true, source: source)
        }
        while plain.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { plain.removeLast() }
        let lines = plain.enumerated().map { i, text in LyricLine(id: i, time: nil, text: text) }
        return Lyrics(lines: lines, synced: false, source: source)
    }
}
