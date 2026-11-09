import Foundation
import UIKit

/// Ogni ascolto con la sua data (serve per esportare i più ascoltati della settimana/mese/anno).
enum PlayHistory {
    struct Entry: Codable {
        let id: String
        let date: Date
    }

    private static let fileName = "history.json"
    private static var cache: [Entry]?

    static func all() -> [Entry] {
        if let cache { return cache }
        let loaded = Storage.load([Entry].self, from: fileName) ?? []
        cache = loaded
        return loaded
    }

    static func append(_ id: String) {
        var list = all()
        list.append(Entry(id: id, date: Date()))
        if list.count > 60_000 { list.removeFirst(list.count - 60_000) }
        cache = list
        Storage.save(list, to: fileName)
    }
}

/// "Esporta automaticamente i dati dei brani/artisti più ascoltati in file CSV" alla fine di ogni settimana, mese e anno.
@MainActor
enum PlayCountExporter {
    static var folder: URL { Storage.documents.appendingPathComponent("Exported Play Counts", isDirectory: true) }

    static func exportIfNeeded(library: LibraryStore, userData: UserDataStore) {
        guard Prefs.bool(Prefs.csvExport) else { return }
        let cal = Calendar.current
        let now = Date()
        let periods: [(key: String, component: Calendar.Component, label: String)] = [
            (Prefs.lastCSVWeek, .weekOfYear, "Settimana"),
            (Prefs.lastCSVMonth, .month, "Mese"),
            (Prefs.lastCSVYear, .year, "Anno"),
        ]
        for p in periods {
            // Periodo appena concluso: quello prima di quello attuale.
            guard let current = cal.dateInterval(of: p.component, for: now),
                  let previous = cal.dateInterval(of: p.component, for: current.start.addingTimeInterval(-1)) else { continue }
            let id = ISO8601DateFormatter().string(from: previous.start)
            guard UserDefaults.standard.string(forKey: p.key) != id else { continue }
            if UserDefaults.standard.string(forKey: p.key) == nil {
                // Prima volta: segno il periodo senza esportare (non ci sono ancora dati suoi).
                UserDefaults.standard.set(id, forKey: p.key)
                continue
            }
            write(interval: previous, label: p.label, library: library)
            UserDefaults.standard.set(id, forKey: p.key)
        }
    }

    private static func write(interval: DateInterval, label: String, library: LibraryStore) {
        let entries = PlayHistory.all().filter { interval.contains($0.date) }
        guard !entries.isEmpty else { return }
        var trackCounts: [String: Int] = [:]
        for e in entries { trackCounts[e.id, default: 0] += 1 }
        var artistCounts: [String: Int] = [:]
        for (id, n) in trackCounts {
            guard let t = library.byID[id] else { continue }
            for a in library.artistNames(for: t) { artistCounts[a, default: 0] += n }
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let name = "\(label) \(f.string(from: interval.start))"
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var tracksCSV = "Posizione,Ascolti,Titolo,Artista,Album,File\n"
        for (i, item) in trackCounts.sorted(by: { $0.value > $1.value }).enumerated() {
            let t = library.byID[item.key]
            tracksCSV += "\(i + 1),\(item.value),\(csv(t?.displayTitle ?? "?")),\(csv(t?.displayArtist ?? "")),\(csv(t?.displayAlbum ?? "")),\(csv(t?.relativePath ?? ""))\n"
        }
        var artistsCSV = "Posizione,Ascolti,Artista\n"
        for (i, item) in artistCounts.sorted(by: { $0.value > $1.value }).enumerated() {
            artistsCSV += "\(i + 1),\(item.value),\(csv(item.key))\n"
        }
        try? tracksCSV.write(to: folder.appendingPathComponent("\(name) - brani.csv"), atomically: true, encoding: .utf8)
        try? artistsCSV.write(to: folder.appendingPathComponent("\(name) - artisti.csv"), atomically: true, encoding: .utf8)
    }

    private static func csv(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Cerca usando altre app

enum OnlineSearch {
    static let engines: [(id: String, name: String, base: String)] = [
        ("google", "Google", "https://www.google.com/search?q="),
        ("duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q="),
        ("bing", "Bing", "https://www.bing.com/search?q="),
        ("yandex", "Yandex", "https://yandex.com/search/?text="),
        ("baidu", "Baidu", "https://www.baidu.com/s?wd="),
        ("kagi", "Kagi", "https://kagi.com/search?q="),
    ]

    /// Sostituisce <t>, <al>, <ar> con titolo, album, artista.
    static func query(_ template: String, track: Track) -> String {
        template.replacingOccurrences(of: "<t>", with: track.displayTitle)
            .replacingOccurrences(of: "<al>", with: track.album)
            .replacingOccurrences(of: "<ar>", with: track.artist)
            .trimmingCharacters(in: .whitespaces)
    }

    static func url(engine: String, query: String, images: Bool) -> URL? {
        guard let e = engines.first(where: { $0.id == engine }) ?? engines.first else { return nil }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var s = e.base + q
        if images {
            switch e.id {
            case "google": s += "&tbm=isch"
            case "bing": s = "https://www.bing.com/images/search?q=" + q
            case "duckduckgo": s += "&iax=images&ia=images"
            default: break
            }
        }
        return URL(string: s)
    }

    @MainActor
    static func open(engine: String, query: String, images: Bool) {
        if let url = url(engine: engine, query: query, images: images) { UIApplication.shared.open(url) }
    }
}
