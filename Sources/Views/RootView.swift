import SwiftUI

/// Schede della barra in basso (come Musicolet).
enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case queue, nowPlaying, folders, albums, artists, genres, playlists, albumArtists, composers, search

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
        case .search: "Cerca"
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
        case .search: .search
        }
    }

    /// Schede che non si possono nascondere.
    var isRequired: Bool { self == .queue || self == .nowPlaying }

    /// Schede spostabili (tutte tranne Coda e In riproduzione) nell'ordine scelto in "Ordina i menù".
    static func orderedMovable(order: String) -> [MainTab] {
        let movable = allCases.filter { !$0.isRequired }
        var result: [MainTab] = []
        for raw in order.split(separator: ",") {
            if let t = MainTab(rawValue: String(raw)), movable.contains(t), !result.contains(t) { result.append(t) }
        }
        return result + movable.filter { !result.contains($0) }
    }

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

    @State private var tabRaw = ""
    @State private var paths: [MainTab: NavigationPath] = [:]
    @State private var moreSheet: MoreSheet?
    @State private var confirmQuit = false
    @State private var tabChanges = 0
    @AppStorage(Prefs.tabOrder) private var tabOrder = ""
    @AppStorage(Prefs.tabBarTop) private var tabBarTop = false
    @AppStorage(Prefs.npBlur) private var npBlur = 3.0
    @AppStorage(Prefs.menuMain) private var menuMain = "equalizer,sleepTimer,scan,quit"
    @Namespace private var tabIndicator

    private var tab: MainTab { MainTab(rawValue: tabRaw) ?? .nowPlaying }

    private var visibleTabs: [MainTab] {
        [.queue, .nowPlaying] + MainTab.orderedMovable(order: tabOrder).filter { !settings.isTabHidden($0.rawValue) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabBarTop { tabBar }
            ZStack {
                content
                    .id(tab)
                    .zIndex(Double(tabChanges))
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal: .modifier(active: SlideBehind(x: -60), identity: SlideBehind(x: 0))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            SelectionBar()
            if !tabBarTop { tabBar }
        }
        .background {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                if barIsTransparent {
                    NowPlayingBackdrop().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: barIsTransparent)
        }
        .overlay(alignment: .top) { scanBanner }
        .overlay { ToastOverlay() }
        .modifier(TrackActionsHost())
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
            case .settings: EmptyView()
            }
        }
        .fullScreenCover(isPresented: $ui.showSettings) {
            SettingsScreen(start: ui.settingsStart)
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
        .onAppear {
            // Scheda all'avvio scelta in Impostazioni; se è nascosta, la prima visibile.
            guard tabRaw.isEmpty else { return }
            if let start = MainTab(rawValue: settings.startTab), visibleTabs.contains(start) {
                tabRaw = start.rawValue
            } else {
                tabRaw = visibleTabs.first { $0 != .queue && $0 != .nowPlaying && $0 != .search }?.rawValue
                    ?? MainTab.nowPlaying.rawValue
            }
        }
        .onChange(of: settings.hiddenTabs) { _, _ in
            if !visibleTabs.contains(tab) { select(.nowPlaying) }
        }
        .onChange(of: ui.resetFolderTree) { _, _ in
            paths[.folders] = NavigationPath()
        }
        .onOpenURL { url in
            if url.host == "nowplaying" { select(.nowPlaying) }
        }
        .onChange(of: ui.showNowPlaying) { _, show in
            guard show else { return }
            select(.nowPlaying)
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
            if phase == .active, settings.theme == .timeBased { settings.objectWillChange.send() }
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
            stack(for: .artists) { ArtistsTabView() }
        case .genres:
            stack(for: .genres) { GroupListView(kind: .genre) }
        case .playlists:
            stack(for: .playlists) { PlaylistsView() }
        case .albumArtists:
            stack(for: .albumArtists) { GroupListView(kind: .albumArtist) }
        case .composers:
            stack(for: .composers) { GroupListView(kind: .composer) }
        case .search:
            stack(for: .search) { SearchView() }
        }
    }

    private func pathBinding(_ t: MainTab) -> Binding<NavigationPath> {
        // Aprire un album, un artista... non deve avere l'animazione: quella è solo per la barra in basso.
        Binding(get: { paths[t] ?? NavigationPath() }, set: { newValue in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { paths[t] = newValue }
        })
    }

    private func stack<Content: View>(for t: MainTab, @ViewBuilder _ root: () -> Content) -> some View {
        NavigationStack(path: pathBinding(t)) {
            root()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
        .id(t)
    }

    private func open(_ route: Route) {
        let target: MainTab
        switch route {
        case .group(let kind, _):
            let preferred = MainTab.forGroup(kind)
            target = visibleTabs.contains(preferred) ? preferred : (kind == .albumArtist || kind == .composer ? .artists : .folders)
        case .playlist, .favorites, .smart:
            target = .playlists
        case .queue:
            target = .queue
        case .search:
            target = .search
        }
        var p = NavigationPath()
        p.append(route)
        paths[target] = p
        select(target)
    }

    /// La nuova schermata entra da destra e copre la precedente (circa 0,15 s).
    private func select(_ t: MainTab) {
        guard t != tab else { return }
        tabChanges += 1
        withAnimation(.easeOut(duration: 0.15)) { tabRaw = t.rawValue }
    }

    // MARK: Barra in basso

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { t in
                Button {
                    if t == tab {
                        paths[t] = NavigationPath() // secondo tocco: torna all'inizio della scheda
                    } else {
                        select(t)
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
                if menuMain.csvContains("equalizer") {
                    Button { moreSheet = .equalizer } label: { Label("Equalizzatore", systemImage: "slider.vertical.3") }
                }
                if menuMain.csvContains("sleepTimer") {
                    Button { moreSheet = .sleepTimer } label: { Label("Timer di spegnimento", systemImage: "moon.zzz") }
                }
                if menuMain.csvContains("scan") {
                    Button {
                        Task { await library.rescan() }
                        ui.showToast("Scansione della libreria…")
                    } label: { Label("Scansione", systemImage: "arrow.clockwise") }
                }
                Button { ui.showSettings = true } label: { Label("Impostazioni", systemImage: "gearshape") }
                if menuMain.csvContains("quit") {
                    Divider()
                    Button(role: .destructive) { confirmQuit = true } label: { Label("Chiudi app", systemImage: "power") }
                }
            } label: {
                tabCell(.more, selected: false)
            }
            .accessibilityLabel("Altro")
        }
        .frame(height: 54)
        // In riproduzione la barra è trasparente (resta il colore della copertina) con un separatore sopra.
        // Grigio chiaro; trasparente solo in riproduzione con un brano che ha la copertina.
        .background(barIsTransparent ? Color.clear : Color(uiColor: .systemGray6))
        .overlay(alignment: tabBarTop ? .bottom : .top) {
            if barIsTransparent { Divider() }
        }
    }

    private var barIsTransparent: Bool { tab == .nowPlaying && player.nowPlayingImage != nil && npBlur > 0 }

    private func tabCell(_ glyph: AppGlyph, selected: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.clear.frame(height: 3)
                if selected {
                    // La lineetta scivola sull'icona toccata; in riproduzione diventa nera.
                    Rectangle()
                        .fill(tab == .nowPlaying ? Color.primary : Color.accentColor)
                        .frame(height: 3)
                        .matchedGeometryEffect(id: "tabIndicator", in: tabIndicator)
                }
            }
            Spacer(minLength: 0)
            AppIconView(glyph: glyph, size: 22)
                .foregroundStyle(selected ? Color.primary.opacity(0.75) : Color(uiColor: .systemGray2))
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
                                year: group.year,
                                splitBy: kind == .genre ? .artist : (kind == .folder ? nil : .album))
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

/// Usato quando si cambia scheda: la schermata vecchia arretra un po' mentre la nuova la copre.
struct SlideBehind: ViewModifier {
    let x: CGFloat
    func body(content: Content) -> some View {
        content.offset(x: x)
    }
}
