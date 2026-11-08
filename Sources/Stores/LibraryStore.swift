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
    private var separators: [String] = [";"]
    private var exceptions: [String] = []
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        separators = settings.artistSeparators
        exceptions = settings.artistExceptions
        settings.$artistSeparators
            .combineLatest(settings.$artistExceptions)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] seps, excs in
                guard let self else { return }
                self.separators = seps
                self.exceptions = excs
                self.setTracks(self.tracks)
            }
            .store(in: &cancellables)
    }

    /// Artisti di un brano, divisi con i separatori scelti dall'utente.
    func artistNames(for t: Track) -> [String] {
        let parts = ArtistSplitter.split(t.artist, separators: separators, exceptions: exceptions)
        return parts.isEmpty ? [t.displayArtist] : parts
    }

    func albumArtistNames(for t: Track) -> [String] {
        if t.albumArtist.isEmpty { return artistNames(for: t) }
        let parts = ArtistSplitter.split(t.albumArtist, separators: separators, exceptions: exceptions)
        return parts.isEmpty ? [t.displayAlbumArtist] : parts
    }

    func composerNames(for t: Track) -> [String] {
        ArtistSplitter.split(t.composer, separators: separators, exceptions: exceptions)
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
    private func saveTracks() { Storage.save(tracks, to: "library.json") }

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
        setTracks(tracks.filter { $0.folderID != id })
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

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        progress.done = 0
        progress.total = 0

        let roots: [(UUID, URL)] = folders.compactMap { f in folderURLs[f.id].map { (f.id, $0) } }
        let unreachable = Set(folders.map(\.id)).subtracting(roots.map { $0.0 })
        let entries = await Task.detached(priority: .userInitiated) {
            LibraryScanner.listFiles(roots: roots)
        }.value

        let old = byID
        var result: [Track] = tracks.filter { unreachable.contains($0.folderID) }
        var pending: [FileEntry] = []
        for entry in entries {
            if let t = old[entry.id], t.modified == entry.modified, t.fileSize == entry.size {
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
                    group.addTask { await MetadataReader.read(entry, dateAdded: added) }
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
        isScanning = false
    }

    /// Rilegge i tag di alcuni brani (dopo il tag editor).
    func refresh(trackIDs: [String]) async {
        var entries: [FileEntry] = []
        for id in trackIDs {
            guard let t = byID[id], let url = url(for: t) else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            entries.append(FileEntry(id: t.id, folderID: t.folderID, url: url, relativePath: t.relativePath,
                                     size: Int64(values?.fileSize ?? Int(t.fileSize)),
                                     modified: values?.contentModificationDate ?? Date()))
        }
        var updated = byID
        for e in entries {
            let added = byID[e.id]?.dateAdded ?? Date()
            updated[e.id] = await MetadataReader.read(e, dateAdded: added)
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
        let sorted = list.sorted { $0.displayTitle.localizedLess($1.displayTitle) }
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

    private static func albumKey(_ t: Track) -> String {
        let album = t.album.lowercased()
        if !t.albumArtist.isEmpty { return album + "\u{1}" + t.albumArtist.lowercased() }
        return album + "\u{1}" + t.folderID.uuidString + "/" + t.directory.lowercased()
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
            let ak = Self.albumKey(t)
            albumKeys[t.id] = ak
            albums[ak, default: []].append(t)
            for a in artistNames(for: t) { add(&artists, a, t) }
            for a in albumArtistNames(for: t) { add(&albumArtists, a, t) }
            for g in t.genreList { add(&genres, g, t) }
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
                              trackIDs: sorted.map(\.id), year: sorted.compactMap(\.year).max())
        }.sorted { $0.name.localizedLess($1.name) }

        func groups(_ kind: GroupKind, _ dict: [String: Bucket]) -> [TrackGroup] {
            dict.map { key, bucket -> TrackGroup in
                let sorted = bucket.tracks.sorted { a, b in
                    if a.album != b.album { return a.displayAlbum.localizedLess(b.displayAlbum) }
                    return Self.albumOrder(a, b)
                }
                let albumCount = Set(sorted.map { albumKeys[$0.id] ?? "" }).count
                let subtitle = "\(albumCount) album · \(sorted.count) brani"
                return TrackGroup(kind: kind, id: key, name: bucket.name, subtitle: subtitle,
                                  trackIDs: sorted.map(\.id), year: nil)
            }.sorted { $0.name.localizedLess($1.name) }
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
            return TrackGroup(kind: .folder, id: key, name: name, subtitle: path, trackIDs: sorted.map(\.id), year: nil)
        }.sorted { $0.subtitle.localizedLess($1.subtitle) }

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
}

enum LibraryScanner {
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "flac", "wav", "aif", "aiff", "aifc", "caf", "alac",
        "ogg", "oga", "opus", "spx", "wv", "ape", "mpc", "tta",
    ]

    static func listFiles(roots: [(UUID, URL)]) -> [FileEntry] {
        let fm = FileManager.default
        var out: [FileEntry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        for (folderID, root) in roots {
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                let name = url.lastPathComponent
                if name.hasPrefix(".") {
                    if name.hasSuffix(".icloud") {
                        try? fm.startDownloadingUbiquitousItem(at: url)
                    } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
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
