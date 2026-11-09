import Foundation
import UIKit

// MARK: - Zip (senza librerie esterne)

/// Scrive file .zip "senza compressione" e legge anche quelli compressi (deflate), per esempio creati dall'app File.
enum SimpleZip {
    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }

    static func make(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for f in files {
            let name = Array(f.name.utf8)
            let crc = crc32(f.data)
            let size = UInt32(f.data.count)
            let offset = UInt32(out.count)
            var local: [UInt8] = le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            local += le32(crc) + le32(size) + le32(size) + le16(name.count) + le16(0)
            out.append(contentsOf: local + name)
            out.append(f.data)
            var entry: [UInt8] = le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            entry += le32(crc) + le32(size) + le32(size) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0)
            entry += le32(0) + le32(offset)
            central.append(contentsOf: entry + name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        var end: [UInt8] = le32(0x0605_4B50) + le16(0) + le16(0) + le16(files.count) + le16(files.count)
        end += le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        out.append(contentsOf: end)
        return out
    }

    static func read(_ data: Data) -> [String: Data]? {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { i + 1 < bytes.count ? Int(bytes[i]) | Int(bytes[i + 1]) << 8 : 0 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        // Fine della directory centrale (cercata dal fondo).
        var eocd = -1
        var i = bytes.count - 22
        while i >= 0 && i >= bytes.count - 66_000 {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard u32(p) == 0x0201_4B50 else { break }
            let method = u16(p + 10)
            let compSize = u32(p + 20)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let localOffset = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<min(bytes.count, p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen
            let lNameLen = u16(localOffset + 26), lExtraLen = u16(localOffset + 28)
            let start = localOffset + 30 + lNameLen + lExtraLen
            guard start + compSize <= bytes.count, !name.hasSuffix("/") else { continue }
            let raw = Data(bytes[start..<(start + compSize)])
            switch method {
            case 0: result[(name as NSString).lastPathComponent] = raw
            case 8:
                if let inflated = try? (raw as NSData).decompressed(using: .zlib) as Data {
                    result[(name as NSString).lastPathComponent] = inflated
                }
            default: continue
            }
        }
        return result
    }
}

// MARK: - Backup / Ripristino

@MainActor
enum BackupManager {
    static var folder: URL { Storage.documents.appendingPathComponent("Backups", isDirectory: true) }
    static let dataFiles = ["userdata.json", "queues.json", "history.json", "replaygain.json"]
    private static let lastAutoKey = "backup.lastAuto"

    /// Crea il backup (playlist, preferiti, segnalibri, conteggi, code, impostazioni) e lo salva nella cartella Backups.
    @discardableResult
    static func create(auto: Bool = false) -> URL? {
        PlayerController.shared?.persist()
        var files: [(name: String, data: Data)] = []
        for name in dataFiles {
            if let data = try? Data(contentsOf: Storage.directory.appendingPathComponent(name)) { files.append((name, data)) }
        }
        if let id = Bundle.main.bundleIdentifier, let domain = UserDefaults.standard.persistentDomain(forName: id),
           let plist = try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0) {
            files.append(("settings.plist", plist))
        }
        let info = "AuguMusic backup\nVersione app: \(appVersion)\nCreato: \(Date())\n"
        files.append(("info.txt", Data(info.utf8)))

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let url = folder.appendingPathComponent("AuguMusic \(auto ? "auto " : "")\(f.string(from: Date())).zip")
        do {
            try SimpleZip.make(files).write(to: url, options: .atomic)
        } catch {
            return nil
        }
        if auto { pruneAutoBackups() }
        return url
    }

    /// Backup automatico: al massimo uno al giorno, tengo gli ultimi 5.
    static func autoBackupIfNeeded() {
        guard Prefs.bool(Prefs.autoBackup) else { return }
        let last = UserDefaults.standard.object(forKey: lastAutoKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        if create(auto: true) != nil { UserDefaults.standard.set(Date(), forKey: lastAutoKey) }
    }

    private static func pruneAutoBackups() {
        let autos = backups().filter { $0.lastPathComponent.hasPrefix("AuguMusic auto ") }
        for old in autos.dropFirst(5) { try? FileManager.default.removeItem(at: old) }
    }

    /// Backup nella cartella, dal più recente.
    static func backups() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter { $0.pathExtension.lowercased() == "zip" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    struct Contents {
        var files: [String: Data]
        var hasLibraryData: Bool { files["userdata.json"] != nil }
        var hasQueues: Bool { files["queues.json"] != nil }
        var hasSettings: Bool { files["settings.plist"] != nil }
    }

    static func open(_ url: URL) -> Contents? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let files = SimpleZip.read(data),
              files["userdata.json"] != nil || files["settings.plist"] != nil else { return nil }
        return Contents(files: files)
    }

    struct RestoreChoice {
        var playlists = true
        var favorites = true
        var playCounts = true
        var queues = true
        var settings = true
    }

    /// Ripristina le parti scelte. Dopo bisogna riaprire l'app.
    static func restore(_ c: Contents, choice: RestoreChoice) {
        if let data = c.files["userdata.json"],
           var backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var current = (try? Data(contentsOf: Storage.directory.appendingPathComponent("userdata.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            if choice.playlists {
                current["playlists"] = backup["playlists"]
                current["bookmarks"] = backup["bookmarks"]
            }
            if choice.favorites { current["favorites"] = backup["favorites"] }
            if choice.playCounts { current["stats"] = backup["stats"] }
            for key in ["playlists", "favorites", "bookmarks"] where current[key] == nil { current[key] = backup[key] ?? [] }
            backup = current
            if let out = try? JSONSerialization.data(withJSONObject: backup) {
                try? out.write(to: Storage.directory.appendingPathComponent("userdata.json"), options: .atomic)
            }
        }
        if choice.playCounts {
            for name in ["history.json", "replaygain.json"] {
                if let d = c.files[name] { try? d.write(to: Storage.directory.appendingPathComponent(name), options: .atomic) }
            }
        }
        if choice.queues, let d = c.files["queues.json"] {
            try? d.write(to: Storage.directory.appendingPathComponent("queues.json"), options: .atomic)
        }
        if choice.settings, let d = c.files["settings.plist"], let id = Bundle.main.bundleIdentifier,
           let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
            UserDefaults.standard.setPersistentDomain(dict, forName: id)
            UserDefaults.standard.synchronize()
        }
    }

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) build\(b)"
    }
}
