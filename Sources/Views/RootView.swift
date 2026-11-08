import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case queues, folders, albums, artists, albumArtists, genres, composers, songs, playlists, search, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queues: "Code"
        case .folders: "Cartelle"
        case .albums: "Album"
        case .artists: "Artisti"
        case .albumArtists: "Artisti album"
        case .genres: "Generi"
        case .composers: "Compositori"
        case .songs: "Brani"
        case .playlists: "Playlist"
        case .search: "Cerca"
        case .settings: "Impostazioni"
        }
    }

    var icon: String {
        switch self {
        case .queues: "list.number"
        case .folders: "folder"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .albumArtists: "person.2"
        case .genres: "guitars"
        case .composers: "music.quarternote.3"
        case .songs: "music.note"
        case .playlists: "music.note.list"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }

    static let library: [SidebarItem] = [.folders, .albums, .artists, .albumArtists, .genres, .composers, .songs]
    static let personal: [SidebarItem] = [.queues, .playlists, .search, .settings]
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ScanProgress
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ui: UIState
    @Environment(\.scenePhase) private var scenePhase

    @SceneStorage("sidebarSelection") private var selectionRaw = SidebarItem.folders.rawValue
    @State private var path = NavigationPath()

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectionRaw) },
            set: { selectionRaw = ($0 ?? .folders).rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: selection) {
                    let libraryItems = SidebarItem.library.filter { !settings.isTabHidden($0.rawValue) }
                    if !libraryItems.isEmpty {
                        Section("Libreria") {
                            ForEach(libraryItems) { item in sidebarRow(item) }
                        }
                    }
                    Section("Le mie cose") {
                        ForEach(SidebarItem.personal.filter { !settings.isTabHidden($0.rawValue) }) { item in
                            sidebarRow(item)
                        }
                    }
                }
                .navigationTitle("AuguMusic")
            } detail: {
                NavigationStack(path: $path) {
                    detail(for: SidebarItem(rawValue: selectionRaw) ?? .folders)
                        .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                }
            }
            SelectionBar()
            MiniPlayerBar()
        }
        .overlay(alignment: .top) { scanBanner }
        .overlay { ToastOverlay() }
        .fullScreenCover(isPresented: $ui.showNowPlaying) {
            NowPlayingView()
        }
        .sheet(item: $ui.addToPlaylist) { list in
            PlaylistPickerSheet(trackIDs: list.ids)
        }
        .sheet(item: $ui.infoTrack) { track in
            TrackInfoView(track: track)
        }
        .sheet(item: $ui.tagEditor) { list in
            TagEditorView(trackIDs: list.ids)
        }
        .onChange(of: selectionRaw) { _, _ in path = NavigationPath() }
        .onChange(of: settings.hiddenTabs) { _, hidden in
            if hidden.contains(selectionRaw) {
                selectionRaw = SidebarItem.allCases.first { !hidden.contains($0.rawValue) }?.rawValue ?? SidebarItem.settings.rawValue
            }
        }
        .onOpenURL { url in
            if url.host == "nowplaying" { ui.showNowPlaying = true }
        }
        .onChange(of: ui.pendingRoute) { _, route in
            guard let route else { return }
            ui.showNowPlaying = false
            path.append(route)
            ui.pendingRoute = nil
        }
        .onChange(of: player.message) { _, message in
            guard let message else { return }
            ui.showToast(message)
            player.message = nil
        }
        .onChange(of: library.lastError) { _, error in
            guard let error else { return }
            ui.showToast(error)
            library.lastError = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.persist() }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.icon)
            .tag(item)
            .contextMenu {
                if item != .settings {
                    Button(role: .destructive) {
                        settings.setTab(item.rawValue, hidden: true)
                        ui.showToast("\(item.title) nascosta. La riattivi da Impostazioni.")
                    } label: {
                        Label("Nascondi \(item.title)", systemImage: "eye.slash")
                    }
                }
            }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .queues: QueuesView()
        case .folders: GroupListView(kind: .folder)
        case .albums: AlbumGridView()
        case .artists: GroupListView(kind: .artist)
        case .albumArtists: GroupListView(kind: .albumArtist)
        case .genres: GroupListView(kind: .genre)
        case .composers: GroupListView(kind: .composer)
        case .songs: AllSongsView()
        case .playlists: PlaylistsView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private var scanBanner: some View {
        if library.isScanning {
            HStack(spacing: 8) {
                ProgressView()
                Text(progress.total > 0 ? "Lettura brani \(progress.done)/\(progress.total)" : "Scansione cartelle…")
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 6)
        }
    }
}

struct RouteDestination: View {
    let route: Route
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        switch route {
        case .group(.album, let id):
            AlbumDetailView(albumID: id)
        case .group(let kind, let id):
            if let group = library.group(kind, id: id) {
                TrackListScreen(title: group.name,
                                subtitle: group.subtitle,
                                tracks: library.tracks(for: group.trackIDs),
                                headerTrackID: kind == .album ? group.trackIDs.first : nil,
                                year: group.year)
            } else {
                ContentUnavailableView("Non trovato", systemImage: "questionmark.folder")
            }
        case .playlist(let id):
            PlaylistDetailView(playlistID: id)
        case .favorites:
            FavoritesView()
        case .queue(let id):
            QueueDetailView(queueID: id)
        }
    }
}
