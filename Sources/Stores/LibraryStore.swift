import Combine
import SwiftUI

struct FileEntry: Sendable {
    let id: String
    let folderID: UUID
    let url: URL
    let relativePath: String
    let size: Int64
    let modified: Date
}

@MainActor
final class ScanProgress: ObservableObject {
    @Published var done = 0
    @Published var total = 0
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var folders: [LibraryFolder] = []
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isScanning = false
    @Published var lastError: String?

    let progress = ScanProgress()

    private(set) var byID: [String: Track] = [:]
    private var groupStore: [GroupKind: [TrackGroup]] = [:]
    private var groupLookup: [GroupKind: [String: TrackGroup]] = [:]
    private var trackAlbumKey: [String: String] = [:]
    private var folderCounts: [UUID: Int] = [:]
    private var folderURLs: [UUID: URL] = [:]
    private var didLoad = false
    private var exceptions: [String] = []
    private(set) var options = LibraryOptions.current()
    /// Tutti i brani letti, anche quelli nascosti perché troppo corti.
    private var rawTracks: [Track] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastAutoScan = Date.distantPast

    init(settings: AppSettings) {
        exceptions = settings.artistExceptions
        TagCleaner.cleanEverywhere = options.hideExtraAll
        SortText.update(options)
        settings.$artistExceptions
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] excs in
                guard let self else { return }
                self.exceptions = excs
                self.setTracks(self.rawTracks)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.optionsMaybeChanged() }
            .store(in: &cancellables)
    }

    /// Le opzioni di "Libreria brani e tag" sono cambiate: ricostruisco album, artisti, generi.
    private func optionsMaybeChanged() {
        let new = LibraryOptions.current()
        guard new != options else { return }
        let needsRescan = new.scanHidden != options.scanHidden || new.scanNomedia != options.scanNomedia
            || new.scanVideo != options.scanVideo || new.preferTagLib != options.preferTagLib
        options = new
        TagCleaner.cleanEverywhere = new.hideExtraAll
        SortText.update(new)
        setTracks(rawTracks)
        if needsRescan { Task { await rescan(forceReread: true) } }
    }

    /// Scansione automatica all'avvio e quando si torna nell'app (al massimo una volta al minuto).
    func autoScanIfEnabled() async {
        guard Prefs.bool(Prefs.autoScan) || rawTracks.isEmpty, Date().timeIntervalSince(lastAutoScan) > 60 else { return }
        lastAutoScan = Date()
        await rescan()
    }

    private func split(_ text: String, enabled: Bool, separators: [String]) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard enabled else { return [trimmed] }
        return ArtistSplitter.split(trimmed, separators: separators, exceptions: exceptions)
    }

    /// Artisti di un brano, divisi con i separatori scelti dall'utente.
    func artistNames(for t: Track) -> [String] {
        let parts = split(t.artist, enabled: options.multiArtist, separators: options.sepArtist).map(TagCleaner.everywhere)
        return parts.isEmpty ? [t.displayArtist] : parts
    }

    func albumArtistNames(for t: Track) -> [String] {
        if t.albumArtist.isEmpty {
            return options.albumArtistFallback ? artistNames(for: t) : ["Artista album sconosciuto"]
        }
        let parts = split(t.albumArtist, enabled: options.multiAlbumArtist, separators: options.sepAlbumArtist).map(TagCleaner.everywhere)
        return parts.isEmpty ? [t.displayAlbumArtist] : parts
    }

    func composerNames(for t: Track) -> [String] {
        split(t.composer, enabled: options.multiComposer, separators: options.sepComposer)
    }

    func genreNames(for t: Track) -> [String] {
        let parts = split(t.genre, enabled: options.multiGenre, separators: options.sepGenre)
        return parts.isEmpty ? ["Genere sconosciuto"] : parts
    }

    // MARK: Caricamento

    func loadFromDisk() {
        guard !didLoad else { return }
        didLoad = true
        folders = Storage.load([LibraryFolder].self, from: "folders.json") ?? []
        if !folders.contains(where: { $0.isAppDocuments }) {
            folders.insert(LibraryFolder(id: UUID(), name: "Sull'iPad", bookmark: nil, isAppDocuments: true), at: 0)
            saveFolders()
        }
        try? FileManager.default.createDirectory(at: Storage.documents.appendingPathComponent("Musica", isDirectory: true),
                                                 withIntermediateDirectories: true)
        resolveFolders()
        if let saved = Storage.load([Track].self, from: "library.json") {
            setTracks(saved)
        }
    }

    private func resolveFolders() {
        var changed = false
        for i in folders.indices {
            let folder = folders[i]
            if folder.isAppDocuments {
                folderURLs[folder.id] = Storage.documents
                continue
            }
            guard let data = folder.bookmark else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            folderURLs[folder.id] = url
            if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                folders[i].bookmark = fresh
                changed = true
            }
        }
        if changed { saveFolders() }
    }

    private func saveFolders() { Storage.save(folders, to: "folders.json") }
    private func saveTracks() { Storage.save(rawTracks, to: "library.json") }

    // MARK: Cartelle

    func isAvailable(_ folderID: UUID) -> Bool { folderURLs[folderID] != nil }
    func trackCount(in folderID: UUID) -> Int { folderCounts[folderID] ?? 0 }

    func addFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let folder = LibraryFolder(id: UUID(), name: url.lastPathComponent, bookmark: data, isAppDocuments: false)
            folders.append(folder)
            folderURLs[folder.id] = url
            saveFolders()
            Task { await rescan() }
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            lastError = "Non riesco ad aggiungere la cartella: \(error.localizedDescription)"
        }
    }

    func removeFolder(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }), !folder.isAppDocuments else { return }
        folderURLs[id]?.stopAccessingSecurityScopedResource()
        folderURLs[id] = nil
        folders.removeAll { $0.id == id }
        saveFolders()
        setTracks(rawTracks.filter { $0.folderID != id })
        saveTracks()
    }

    func folderName(_ id: UUID) -> String {
        guard let f = folders.first(where: { $0.id == id }) else { return "?" }
        return f.isAppDocuments ? "Sull'iPad" : f.name
    }

    func url(for track: Track) -> URL? {
        folderURLs[track.folderID]?.appendingPathComponent(track.relativePath)
    }

    // MARK: Scansione

    func rescan(forceReread: Bool = false) async {
        guard !isScanning else { return }
        let opts = options
        isScanning = true
        progress.done = 0
        progress.total = 0

        let roots: [(UUID, URL)] = folders.compactMap { f in folderURLs[f.id].map { (f.id, $0) } }
        let unreachable = Set(folders.map(\.id)).subtracting(roots.map { $0.0 })
        let excludedStored = Prefs.string(Prefs.excludedFolders)
        let entries = await Task.detached(priority: .userInitiated) {
            LibraryScanner.listFiles(roots: roots, options: opts).filter { entry in
                let dir = (entry.relativePath as NSString).deletingLastPathComponent
                return !ExcludedFolders.isExcluded(entry.folderID.uuidString + "|" + dir, stored: excludedStored)
            }
        }.value

        var old: [String: Track] = [:]
        for t in rawTracks { old[t.id] = t }
        // Quando cambia il modo di leggere i tag, rileggo tutto una volta.
        let currentReaderVersion = 2
        let cacheValid = !forceReread && UserDefaults.standard.integer(forKey: "metadataReaderVersion") >= currentReaderVersion
        var result: [Track] = rawTracks.filter { unreachable.contains($0.folderID) }
        var pending: [FileEntry] = []
        for entry in entries {
            if cacheValid, let t = old[entry.id], t.modified == entry.modified, t.fileSize == entry.size {
                result.append(t)
            } else {
                pending.append(entry)
            }
        }

        progress.total = pending.count
        let now = Date()
        var start = 0
        while start < pending.count {
            let chunk = Array(pending[start..<min(start + 8, pending.count)])
            let read: [Track] = await withTaskGroup(of: Track.self) { group in
                for entry in chunk {
                    let added = old[entry.id]?.dateAdded ?? now
                    group.addTask { await MetadataReader.read(entry, dateAdded: added, preferTagLib: opts.preferTagLib) }
                }
                var out: [Track] = []
                for await t in group { out.append(t) }
                return out
            }
            result.append(contentsOf: read)
            start += chunk.count
            progress.done = start
        }

        setTracks(result)
        saveTracks()
        UserDefaults.standard.set(currentReaderVersion, forKey: "metadataReaderVersion")
        isScanning = false
    }

    /// Rilegge i tag di alcuni brani (dopo il tag editor).
    func refresh(trackIDs: [String]) async {
        var raw: [String: Track] = [:]
        for t in rawTracks { raw[t.id] = t }
        var entries: [FileEntry] = []
        for id in trackIDs {
            guard let t = raw[id], let url = url(for: t) else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            entries.append(FileEntry(id: t.id, folderID: t.folderID, url: url, relativePath: t.relativePath,
                                     size: Int64(values?.fileSize ?? Int(t.fileSize)),
                                     modified: values?.contentModificationDate ?? Date()))
        }
        var updated = raw
        for e in entries {
            let added = raw[e.id]?.dateAdded ?? Date()
            updated[e.id] = await MetadataReader.read(e, dateAdded: added, preferTagLib: options.preferTagLib)
        }
        setTracks(Array(updated.values))
        saveTracks()
    }

    // MARK: Indici

    private struct Bucket {
        var name: String
        var tracks: [Track]
    }

    private func setTracks(_ list: [Track]) {
        rawTracks = list
        let minDuration = Double(options.minDuration)
        let visible = minDuration > 0 ? list.filter { $0.duration <= 0 || $0.duration >= minDuration } : list
        let sorted = visible.sorted { SortText.less($0.displayTitle, $1.displayTitle, tag: "title") }
        var map: [String: Track] = [:]
        map.reserveCapacity(sorted.count)
        var counts: [UUID: Int] = [:]
        for t in sorted {
            map[t.id] = t
            counts[t.folderID, default: 0] += 1
        }
        byID = map
        folderCounts = counts
        buildGroups(sorted)
        tracks = sorted
    }

    nonisolated static func albumOrder(_ a: Track, _ b: Track) -> Bool {
        let da = a.discNumber ?? 0, db = b.discNumber ?? 0
        if da != db { return da < db }
        let ta = a.trackNumber ?? 0, tb = b.trackNumber ?? 0
        if ta != tb { return ta < tb }
        return a.fileName.localizedLess(b.fileName)
    }

    /// "Strategia di unione degli album": due brani sono nello stesso album se coincidono il titolo
    /// e i parametri scelti (artista album, compositore, anno). Senza titolo: un album per cartella.
    private static func albumKey(_ t: Track, merge: Set<String>) -> String {
        if t.album.isEmpty { return "\u{2}" + t.folderID.uuidString + "/" + t.directory.lowercased() }
        var key = t.album.lowercased()
        if merge.contains("albumArtist") { key += "\u{1}" + t.albumArtist.lowercased() }
        if merge.contains("composer") { key += "\u{1}" + t.composer.lowercased() }
        if merge.contains("year") { key += "\u{1}" + (t.year.map { String($0) } ?? "") }
        return key
    }

    private func buildGroups(_ list: [Track]) {
        var albums: [String: [Track]] = [:]
        var artists: [String: Bucket] = [:]
        var albumArtists: [String: Bucket] = [:]
        var genres: [String: Bucket] = [:]
        var composers: [String: Bucket] = [:]
        var folderBuckets: [String: [Track]] = [:]
        var albumKeys: [String: String] = [:]

        func add(_ dict: inout [String: Bucket], _ name: String, _ t: Track) {
            let key = name.lowercased()
            if dict[key] == nil { dict[key] = Bucket(name: name, tracks: [t]) } else { dict[key]!.tracks.append(t) }
        }

        for t in list {
            let ak = Self.albumKey(t, merge: options.albumMerge)
            albumKeys[t.id] = ak
            albums[ak, default: []].append(t)
            for a in artistNames(for: t) { add(&artists, a, t) }
            for a in albumArtistNames(for: t) { add(&albumArtists, a, t) }
            for g in genreNames(for: t) { add(&genres, g, t) }
            for c in composerNames(for: t) { add(&composers, c, t) }
            folderBuckets[Self.folderKey(t), default: []].append(t)
        }
        trackAlbumKey = albumKeys

        var store: [GroupKind: [TrackGroup]] = [:]

        store[.album] = albums.map { key, ts -> TrackGroup in
            let sorted = ts.sorted(by: Self.albumOrder)
            let artistsSet = Set(sorted.map(\.displayAlbumArtist))
            let subtitle = artistsSet.count == 1 ? (artistsSet.first ?? "") : "Artisti vari"
            return TrackGroup(kind: .album, id: key, name: sorted[0].displayAlbum, subtitle: subtitle,
                              trackIDs: sorted.map(\.id), year: sorted.compactMap(\.year).max(), duration: sorted.reduce(0) { $0 + $1.duration })
        }.sorted { SortText.less($0.name, $1.name, tag: "album") }

        func groups(_ kind: GroupKind, _ dict: [String: Bucket]) -> [TrackGroup] {
            dict.map { key, bucket -> TrackGroup in
                let sorted = bucket.tracks.sorted { a, b in
                    if a.album != b.album { return a.displayAlbum.localizedLess(b.displayAlbum) }
                    return Self.albumOrder(a, b)
                }
                let albumCount = Set(sorted.map { albumKeys[$0.id] ?? "" }).count
                let subtitle = "\(albumCount) album · \(sorted.count) brani"
                return TrackGroup(kind: kind, id: key, name: bucket.name, subtitle: subtitle,
                                  trackIDs: sorted.map(\.id), year: nil, duration: sorted.reduce(0) { $0 + $1.duration })
            }.sorted { SortText.less($0.name, $1.name, tag: kind == .composer ? "composer" : (kind == .albumArtist ? "albumArtist" : "artist")) }
        }
        store[.artist] = groups(.artist, artists)
        store[.albumArtist] = groups(.albumArtist, albumArtists)
        store[.genre] = groups(.genre, genres)
        store[.composer] = groups(.composer, composers)

        store[.folder] = folderBuckets.map { key, ts -> TrackGroup in
            let first = ts[0]
            let root = folderName(first.folderID)
            let name = first.directory.isEmpty ? root : (first.directory as NSString).lastPathComponent
            let path = first.directory.isEmpty ? root : root + "/" + first.directory
            let sorted = ts.sorted { $0.fileName.localizedLess($1.fileName) }
            return TrackGroup(kind: .folder, id: key, name: name, subtitle: path, trackIDs: sorted.map(\.id), year: nil, duration: sorted.reduce(0) { $0 + $1.duration })
        }.sorted { SortText.less($0.subtitle, $1.subtitle, tag: "folder") }

        // Cartelle con un solo album (servono per le copertine "folder.jpg").
        var single = Set<String>()
        for (key, ts) in folderBuckets where Set(ts.map { albumKeys[$0.id] ?? "" }).count == 1 {
            if let dir = directoryURL(folderKey: key) { single.insert(dir.standardizedFileURL.path) }
        }
        FolderAlbumIndex.shared.update(single)

        groupStore = store
        var lookup: [GroupKind: [String: TrackGroup]] = [:]
        for (kind, list) in store {
            var d: [String: TrackGroup] = [:]
            for g in list { d[g.id] = g }
            lookup[kind] = d
        }
        groupLookup = lookup
    }

    private static func folderKey(_ t: Track) -> String { t.folderID.uuidString + "|" + t.directory }

    // MARK: Accesso

    func groups(of kind: GroupKind) -> [TrackGroup] { groupStore[kind] ?? [] }
    func group(_ kind: GroupKind, id: String) -> TrackGroup? { groupLookup[kind]?[id] }
    func tracks(for ids: [String]) -> [Track] { ids.compactMap { byID[$0] } }

    func albumID(for t: Track) -> String? { trackAlbumKey[t.id] }
    func artistID(for name: String) -> String { name.lowercased() }
    func folderID(for t: Track) -> String { Self.folderKey(t) }

    /// Indirizzo della cartella di un gruppo "Cartelle" ("uuid|percorso").
    func directoryURL(folderKey: String) -> URL? {
        let parts = folderKey.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let uuid = UUID(uuidString: String(first)), let root = folderURLs[uuid] else { return nil }
        let dir = parts.count > 1 ? String(parts[1]) : ""
        return dir.isEmpty ? root : root.appendingPathComponent(dir, isDirectory: true)
    }
}

enum LibraryScanner {
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "flac", "wav", "aif", "aiff", "aifc", "caf", "alac",
        "ogg", "oga", "opus", "spx", "wv", "ape", "mpc", "tta",
    ]

    static func listFiles(roots: [(UUID, URL)], options: LibraryOptions) -> [FileEntry] {
        let extensions = options.scanVideo ? audioExtensions.union(LibraryOptions.videoExtensions) : audioExtensions
        let fm = FileManager.default
        var out: [FileEntry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        for (folderID, root) in roots {
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { continue }
            if !options.scanNomedia, fm.fileExists(atPath: root.appendingPathComponent(".nomedia").path) { continue }
            while let url = enumerator.nextObject() as? URL {
                let name = url.lastPathComponent
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if name.hasPrefix(".") {
                    if name.hasSuffix(".icloud") {
                        try? fm.startDownloadingUbiquitousItem(at: url)
                        continue
                    }
                    if isDir && !options.scanHidden {
                        enumerator.skipDescendants()
                        continue
                    }
                    if !isDir { continue }
                }
                if isDir {
                    // Cartelle con un file ".nomedia": saltate, come su Android.
                    if !options.scanNomedia, fm.fileExists(atPath: url.appendingPathComponent(".nomedia").path) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory != true else { continue }
                let full = url.resolvingSymlinksInPath().standardizedFileURL.path
                let relative: String
                if full.hasPrefix(rootPath + "/") {
                    relative = String(full.dropFirst(rootPath.count + 1))
                } else {
                    relative = name
                }
                out.append(FileEntry(id: folderID.uuidString + "|" + relative,
                                     folderID: folderID,
                                     url: url,
                                     relativePath: relative,
                                     size: Int64(values.fileSize ?? 0),
                                     modified: values.contentModificationDate ?? .distantPast))
            }
        }
        return out
    }
}
