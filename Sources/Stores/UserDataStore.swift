import SwiftUI

private struct UserDataSnapshot: Codable {
    var playlists: [Playlist]
    var favorites: [String]
    var bookmarks: [Bookmark]
    var stats: [String: PlayStat]?
}

@MainActor
final class UserDataStore: ObservableObject {
    static weak var shared: UserDataStore?

    @Published var playlists: [Playlist] = [] { didSet { save() } }
    @Published var favorites: [String] = [] {
        didSet {
            favoriteSet = Set(favorites)
            save()
            PlayerController.shared?.refreshWidget()
        }
    }
    @Published var bookmarks: [Bookmark] = [] { didSet { save() } }
    @Published private(set) var stats: [String: PlayStat] = [:] { didSet { save() } }

    private var favoriteSet: Set<String> = []
    private var isLoading = false

    func load() {
        isLoading = true
        defer { isLoading = false }
        guard let snap = Storage.load(UserDataSnapshot.self, from: "userdata.json") else { return }
        playlists = snap.playlists
        favorites = snap.favorites
        bookmarks = snap.bookmarks
        stats = snap.stats ?? [:]
    }

    private func save() {
        guard !isLoading else { return }
        Storage.save(UserDataSnapshot(playlists: playlists, favorites: favorites, bookmarks: bookmarks, stats: stats), to: "userdata.json")
    }

    // MARK: Statistiche di ascolto

    func recordPlay(_ id: String) {
        var stat = stats[id] ?? PlayStat(count: 0, lastPlayed: Date())
        stat.count += 1
        stat.lastPlayed = Date()
        stats[id] = stat
    }

    func playCount(_ id: String) -> Int { stats[id]?.count ?? 0 }

    // MARK: Preferiti

    func isFavorite(_ id: String) -> Bool { favoriteSet.contains(id) }

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.append(id) }
    }

    func addFavorites(_ ids: [String]) {
        let new = ids.filter { !favoriteSet.contains($0) }
        if !new.isEmpty { favorites.append(contentsOf: new) }
    }

    // MARK: Playlist

    @discardableResult
    func createPlaylist(name: String, items: [String] = []) -> UUID {
        let p = Playlist(name: name.isEmpty ? "Nuova playlist" : name, items: items)
        playlists.append(p)
        return p.id
    }

    func add(_ ids: [String], to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].items.append(contentsOf: ids)
    }

    func rename(playlistID: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }), !name.isEmpty else { return }
        playlists[i].name = name
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
    }

    func removeItems(at offsets: IndexSet, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].items.remove(atOffsets: offsets)
    }

    func moveItems(from source: IndexSet, to destination: Int, in playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].items.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Segnalibri

    func bookmarks(for trackID: String) -> [Bookmark] {
        bookmarks.filter { $0.trackID == trackID }.sorted { $0.time < $1.time }
    }

    func addBookmark(trackID: String, time: Double, note: String) {
        bookmarks.append(Bookmark(trackID: trackID, time: time, note: note))
    }

    func deleteBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    // MARK: Esportazione M3U

    func m3u(for ids: [String], library: LibraryStore) -> String {
        var lines = ["#EXTM3U"]
        for id in ids {
            guard let t = library.byID[id] else { continue }
            lines.append("#EXTINF:\(Int(t.duration)),\(t.displayArtist) - \(t.displayTitle)")
            lines.append(t.relativePath)
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class UIState: ObservableObject {
    @Published var showNowPlaying = false
    @Published var pendingRoute: Route?
    @Published var addToPlaylist: TrackIDList?
    @Published var infoTrack: Track?
    @Published var tagEditor: TrackIDList?
    @Published var toast: String?

    private var toastTask: Task<Void, Never>?

    // MARK: Selezione multipla (tenere premuto un brano)

    @Published private(set) var selection: [String] = []
    /// Elenco visibile in quel momento, per "Seleziona tutto" e simili.
    var selectionScope: [Track] = []

    var isSelecting: Bool { !selection.isEmpty }

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    func toggleSelection(_ id: String) {
        if let i = selection.firstIndex(of: id) { selection.remove(at: i) } else { selection.append(id) }
    }

    func clearSelection() { selection = [] }

    func selectAll() {
        var set = Set(selection)
        for t in selectionScope where set.insert(t.id).inserted { selection.append(t.id) }
    }

    func invertSelection() {
        let current = Set(selection)
        selection = selectionScope.map(\.id).filter { !current.contains($0) }
    }

    /// Seleziona tutto quello che sta tra il primo e l'ultimo brano già selezionati.
    func selectRange() {
        let ids = selectionScope.map(\.id)
        let positions = selection.compactMap { ids.firstIndex(of: $0) }
        guard let lo = positions.min(), let hi = positions.max(), hi > lo else { return }
        var set = Set(selection)
        for id in ids[lo...hi] where set.insert(id).inserted { selection.append(id) }
    }

    func navigate(_ route: Route) {
        pendingRoute = route
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
