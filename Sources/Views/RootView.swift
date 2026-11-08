import SwiftUI

/// Schede della barra in basso (come Musicolet).
enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case queue, nowPlaying, folders, albums, artists, genres, playlists, albumArtists, composers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue: "Coda"
        case .nowPlaying: "In riproduzione"
        case .folders: "Cartelle"
        case .albums: "Album"
        case .artists: "Artisti"
        case .genres: "Genere"
        case .playlists: "Playlist"
        case .albumArtists: "Artisti album"
        case .composers: "Compositori"
        }
    }

    var glyph: AppGlyph {
        switch self {
        case .queue: .queue
        case .nowPlaying: .nowPlaying
        case .folders: .folders
        case .albums: .albums
        case .artists: .artists
        case .genres: .genres
        case .playlists: .playlists
        case .albumArtists: .albumArtists
        case .composers: .composers
        }
    }

    /// Schede che non si possono nascondere.
    var isRequired: Bool { self == .queue || self == .nowPlaying }

    static func forGroup(_ kind: GroupKind) -> MainTab {
        switch kind {
        case .album: .albums
        case .artist: .artists
        case .albumArtist: .albumArtists
        case .composer: .composers
        case .genre: .genres
        case .folder: .folders
        }
    }
}

enum MoreSheet: String, Identifiable {
    case equalizer, sleepTimer, settings
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ScanProgress
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ui: UIState
    @Environment(\.scenePhase) private var scenePhase

    @SceneStorage("mainTab") private var tabRaw = MainTab.folders.rawValue
    @State private var paths: [MainTab: NavigationPath] = [:]
    @State private var moreSheet: MoreSheet?
    @State private var confirmQuit = false

    private var tab: MainTab { MainTab(rawValue: tabRaw) ?? .folders }

    private var visibleTabs: [MainTab] {
        MainTab.allCases.filter { $0.isRequired || !settings.isTabHidden($0.rawValue) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(tab)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            SelectionBar()
            bottomBar
        }
        .overlay(alignment: .top) { scanBanner }
        .overlay { ToastOverlay() }
        .sheet(item: $ui.addToPlaylist) { list in
            PlaylistPickerSheet(trackIDs: list.ids)
        }
        .sheet(item: $ui.infoTrack) { track in
            TrackInfoView(track: track)
        }
        .sheet(item: $ui.tagEditor) { list in
            TagEditorView(trackIDs: list.ids)
        }
        .sheet(item: $moreSheet) { which in
            switch which {
            case .equalizer: EqualizerView()
            case .sleepTimer: SleepTimerView()
            case .settings:
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Fine") { moreSheet = nil } }
                        }
                }
            }
        }
        .confirmationDialog("Chiudere AuguMusic?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Chiudi app", role: .destructive) {
                player.pause()
                player.persist()
                exit(0)
            }
        } message: {
            Text("La musica si ferma e l'app si chiude.")
        }
        .onChange(of: settings.hiddenTabs) { _, _ in
            if !visibleTabs.contains(tab) { tabRaw = MainTab.nowPlaying.rawValue }
        }
        .onOpenURL { url in
            if url.host == "nowplaying" { tabRaw = MainTab.nowPlaying.rawValue }
        }
        .onChange(of: ui.showNowPlaying) { _, show in
            guard show else { return }
            tabRaw = MainTab.nowPlaying.rawValue
            ui.showNowPlaying = false
        }
        .onChange(of: ui.pendingRoute) { _, route in
            guard let route else { return }
            open(route)
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

    // MARK: Contenuto della scheda

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .nowPlaying:
            NowPlayingView()
        case .queue:
            stack(for: .queue) { QueueTabView() }
        case .folders:
            stack(for: .folders) { GroupListView(kind: .folder) }
        case .albums:
            stack(for: .albums) { AlbumGridView() }
        case .artists:
            stack(for: .artists) { GroupListView(kind: .artist) }
        case .genres:
            stack(for: .genres) { GroupListView(kind: .genre) }
        case .playlists:
            stack(for: .playlists) { PlaylistsView() }
        case .albumArtists:
            stack(for: .albumArtists) { GroupListView(kind: .albumArtist) }
        case .composers:
            stack(for: .composers) { GroupListView(kind: .composer) }
        }
    }

    private func pathBinding(_ t: MainTab) -> Binding<NavigationPath> {
        Binding(get: { paths[t] ?? NavigationPath() }, set: { paths[t] = $0 })
    }

    private func stack<Content: View>(for t: MainTab, @ViewBuilder _ root: () -> Content) -> some View {
        NavigationStack(path: pathBinding(t)) {
            root()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.search) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
        .id(t)
    }

    private func open(_ route: Route) {
        let target: MainTab
        switch route {
        case .group(let kind, _):
            let preferred = MainTab.forGroup(kind)
            target = visibleTabs.contains(preferred) ? preferred : (tab == .nowPlaying ? .folders : tab)
        case .playlist, .favorites, .smart:
            target = .playlists
        case .queue:
            target = .queue
        case .search:
            target = tab == .nowPlaying ? .folders : tab
        }
        var p = NavigationPath()
        p.append(route)
        paths[target] = p
        tabRaw = target.rawValue
    }

    // MARK: Barra in basso

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { t in
                Button {
                    if t == tab {
                        paths[t] = NavigationPath() // secondo tocco: torna all'inizio della scheda
                    } else {
                        // Dissolvenza tra le schede (il colore della riproduzione sfuma invece di sparire)
                        withAnimation(.easeInOut(duration: 0.35)) { tabRaw = t.rawValue }
                    }
                } label: {
                    tabCell(t.glyph, selected: t == tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .contextMenu {
                    if !t.isRequired {
                        Button(role: .destructive) {
                            settings.setTab(t.rawValue, hidden: true)
                            ui.showToast("\(t.title) nascosta. La riattivi da Impostazioni.")
                        } label: {
                            Label("Nascondi \(t.title)", systemImage: "eye.slash")
                        }
                    }
                }
            }
            Menu {
                Button { moreSheet = .equalizer } label: { Label("Equalizzatore", systemImage: "slider.vertical.3") }
                Button { moreSheet = .sleepTimer } label: { Label("Timer di spegnimento", systemImage: "moon.zzz") }
                Button {
                    Task { await library.rescan() }
                    ui.showToast("Scansione della libreria…")
                } label: { Label("Scansione", systemImage: "arrow.clockwise") }
                Button { moreSheet = .settings } label: { Label("Impostazioni", systemImage: "gearshape") }
                Divider()
                Button(role: .destructive) { confirmQuit = true } label: { Label("Chiudi app", systemImage: "power") }
            } label: {
                tabCell(.more, selected: false)
            }
            .accessibilityLabel("Altro")
        }
        .frame(height: 54)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func tabCell(_ glyph: AppGlyph, selected: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(selected ? Color.accentColor : Color.clear)
                .frame(height: 3)
            Spacer(minLength: 0)
            AppIconView(glyph: glyph, size: 22)
                .foregroundStyle(selected ? Color.primary.opacity(0.75) : Color(uiColor: .systemGray3))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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
                                headerTrackID: nil,
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
        case .smart(let list):
            SmartListView(list: list)
        case .search:
            SearchView()
        }
    }
}
