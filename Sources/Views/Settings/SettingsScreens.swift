import SwiftUI

// MARK: - Schermata principale (a schermo intero)

struct SettingsScreen: View {
    @StateObject private var nav = SettingsNav()
    var start: [SettingsDest] = []

    var body: some View {
        NavigationStack(path: $nav.path) {
            SettingsRootPage()
                .navigationDestination(for: SettingsDest.self) { dest in
                    switch dest {
                    case .interface: InterfaceSettingsPage()
                    case .audio: AudioSettingsPage()
                    case .library: LibrarySettingsPage()
                    case .headset: HeadsetSettingsPage()
                    case .widget: WidgetSettingsPage()
                    case .advanced: AdvancedSettingsPage()
                    case .backup: BackupSettingsPage()
                    case .csvExport: CSVExportPage()
                    case .advancedShuffle: AdvancedShufflePage()
                    case .ignoreWords: IgnoreWordsPage()
                    case .preventAutoplay: PreventAutoplayPage()
                    case .scanFolders: ScanFoldersPage()
                    case .excludedFolders: ExcludedFoldersPage()
                    case .libraryAdvanced: LibraryAdvancedPage()
                    case .hideExtra: HideExtraPage()
                    case .eqSettings: EqualizerSettingsPage()
                    case .replayGain: ReplayGainSettingsPage()
                    case .replayGainCalc: ReplayGainCalcPage()
                    case .theme: ThemeSettingsPage()
                    case .optionsMenus: OptionsMenusPage()
                    case .menuQueue: QueueMenuSettingsPage()
                    case .menuNowPlaying: NowPlayingMenuSettingsPage()
                    case .menuFolders: FoldersMenuSettingsPage()
                    case .menuAlbums: AlbumsMenuSettingsPage()
                    case .menuArtists: ArtistsMenuSettingsPage()
                    case .menuGenres: GenresMenuSettingsPage()
                    case .menuPlaylists: PlaylistsMenuSettingsPage()
                    }
                }
        }
        .environmentObject(nav)
        .onAppear { if !start.isEmpty { nav.path = start } }
    }
}

struct SettingsRootPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var library: LibraryStore
    @State private var showLanguage = false
    @State private var showImporter = false
    @State private var language = "it"

    var body: some View {
        SettingsPage(title: "Impostazioni") {
            List {
                Section {
                    SettingsRow(title: "Lingua", subtitle: "italiano", systemIcon: "globe") { showLanguage = true }
                    SettingsRow(title: "Interfaccia", systemIcon: "paintpalette.fill") { nav.path = [.interface] }
                    SettingsRow(title: "Audio", systemIcon: "speaker.wave.2.fill") { nav.path = [.audio] }
                    SettingsRow(title: "Libreria brani e tag", systemIcon: "music.note.list") { nav.path = [.library] }
                    SettingsRow(title: "Auricolare, Bluetooth e altoparlanti", systemIcon: "headphones") { nav.path = [.headset] }
                    SettingsRow(title: "Widget HomeScreen", systemIcon: "square.grid.2x2.fill") { nav.path = [.widget] }
                    SettingsRow(title: "Avanzati", systemIcon: "gearshape.2.fill") { nav.path = [.advanced] }
                    SettingsRow(title: "Backup/Ripristino", systemIcon: "externaldrive.fill.badge.timemachine") { nav.path = [.backup] }
                }
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.insetGrouped)
        }
        .settingsDialog(isPresented: $showLanguage) {
            RadioDialog(title: "Scegli lingua", options: [ChoiceOption(id: "it", label: "italiano")],
                        selection: $language) { showLanguage = false }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                library.addFolder(url)
            }
        }
    }
}

// MARK: - Interfaccia

struct InterfaceSettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var settings: AppSettings
    @AppStorage(Prefs.tabBarTop) private var tabBarTop = false
    @State private var showBarPosition = false
    @State private var showOrder = false
    @State private var showStartTab = false

    private var barPosition: Binding<String> {
        Binding(get: { tabBarTop ? "top" : "bottom" }, set: { tabBarTop = $0 == "top" })
    }

    var body: some View {
        SettingsPage(title: "Interfaccia") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Tema", subtitle: settings.theme.label) { nav.path.append(.theme) }
                    SettingsRow(title: "Posizione della barra delle schede", subtitle: tabBarTop ? "Superiore" : "In basso") {
                        showBarPosition = true
                    }
                    SettingsRow(title: "Ordina i menù", subtitle: "Organizza menù, o abilitali/disabilitali") { showOrder = true }
                    SettingsRow(title: "Scheda all'avvio", subtitle: MainTab(rawValue: settings.startTab)?.title ?? "Album") {
                        showStartTab = true
                    }

                    SettingsSectionHeader(title: "Impostazioni dei menù")
                    SettingsRow(title: "Code") { nav.path.append(.menuQueue) }
                    SettingsRow(title: "In riproduzione") { nav.path.append(.menuNowPlaying) }
                    SettingsRow(title: "Cartelle") { nav.path.append(.menuFolders) }
                    SettingsRow(title: "Album") { nav.path.append(.menuAlbums) }
                    SettingsRow(title: "Artisti") { nav.path.append(.menuArtists) }
                    SettingsRow(title: "Genere") { nav.path.append(.menuGenres) }
                    SettingsRow(title: "Playlist") { nav.path.append(.menuPlaylists) }

                    SettingsSectionHeader(title: "Opzioni e menù")
                    SettingsRow(title: "Opzioni e menù", subtitle: "Mostra/nascondi le voci dei menù e le scorciatoie") {
                        nav.path.append(.optionsMenus)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .settingsDialog(isPresented: $showBarPosition) {
            RadioDialog(title: "Posizione della barra delle schede",
                        options: [ChoiceOption(id: "top", label: "Superiore"), ChoiceOption(id: "bottom", label: "In basso")],
                        selection: barPosition) { showBarPosition = false }
        }
        .settingsDialog(isPresented: $showOrder) {
            TabOrderDialog { showOrder = false }
        }
        .settingsDialog(isPresented: $showStartTab) {
            RadioDialog(title: "Scheda all'avvio",
                        options: MainTab.allCases.map { ChoiceOption(id: $0.rawValue, label: $0.title) },
                        selection: $settings.startTab) { showStartTab = false }
        }
    }
}

/// "Ordina i menù": trascina le schede; quelle sotto la riga sono nascoste.
struct TabOrderDialog: View {
    let close: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @AppStorage(Prefs.tabOrder) private var tabOrder = ""
    @State private var items: [String] = []
    private static let separator = "__separator__"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ordina i menù")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 8)
            fixedRow(.queue)
            fixedRow(.nowPlaying)
            List {
                ForEach(items, id: \.self) { item in
                    if item == Self.separator {
                        HStack {
                            Text("Menù sotto questa posizione saranno nascosti.")
                                .underline()
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("👇")
                        }
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                    } else if let tab = MainTab(rawValue: item) {
                        let hidden = isHidden(item)
                        HStack(spacing: 20) {
                            AppIconView(glyph: tab.glyph, size: 24).foregroundStyle(.secondary)
                            Text(tab.title)
                                .strikethrough(hidden)
                                .foregroundStyle(hidden ? Color.secondary : Color.primary)
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .frame(height: CGFloat(items.count) * 50 + 10)
            DialogButtons(cancelTitle: "CANCELLA", cancel: close, save: save)
        }
        .onAppear(perform: load)
    }

    private func fixedRow(_ tab: MainTab) -> some View {
        HStack(spacing: 20) {
            AppIconView(glyph: tab.glyph, size: 24).foregroundStyle(.secondary)
            Text(tab.title)
        }
        .padding(.leading, 26)
        .padding(.vertical, 12)
    }

    private func isHidden(_ item: String) -> Bool {
        guard let sep = items.firstIndex(of: Self.separator), let i = items.firstIndex(of: item) else { return false }
        return i > sep
    }

    private func load() {
        let ordered = MainTab.orderedMovable(order: tabOrder)
        let visible = ordered.filter { !settings.isTabHidden($0.rawValue) }.map(\.rawValue)
        let hidden = ordered.filter { settings.isTabHidden($0.rawValue) }.map(\.rawValue)
        items = visible + [Self.separator] + hidden
    }

    private func save() {
        guard let sep = items.firstIndex(of: Self.separator) else { close(); return }
        let visible = Array(items[..<sep])
        let hidden = Array(items[(sep + 1)...])
        tabOrder = (visible + hidden).joined(separator: ",")
        settings.hiddenTabs = hidden
        close()
    }
}

// MARK: - Tema

struct ThemeSettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var settings: AppSettings
    @State private var showColors = false

    var body: some View {
        SettingsPage(title: "Tema") {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TEMA")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.leading, 30)
                            .padding(.top, 30)
                            .padding(.bottom, 16)
                        ForEach(AppTheme.allCases) { theme in
                            Button { settings.theme = theme } label: {
                                HStack(spacing: 18) {
                                    RadioMark(selected: settings.theme == theme)
                                    Text(theme.label).foregroundStyle(Color.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Button { showColors = true } label: {
                            HStack(spacing: 24) {
                                Text("Colori per risalto").font(.title3).foregroundStyle(Color.primary.opacity(0.8))
                                Circle().fill(settings.accent.color).frame(width: 40, height: 40)
                            }
                            .padding(.horizontal, 26)
                            .padding(.vertical, 18)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 26)
                        .padding(.top, 14)
                    }
                }
                Button { nav.path.removeLast() } label: {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 66, height: 66)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .padding(28)
            }
        }
        .settingsDialog(isPresented: $showColors) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Colori per risalto")
                    .font(.title3.weight(.semibold))
                    .padding(26)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 14), count: 5), spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            settings.accent = choice
                            showColors = false
                        } label: {
                            ZStack {
                                Circle().fill(choice.color).frame(width: 50, height: 50)
                                if settings.accent == choice {
                                    Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.label)
                    }
                }
                .padding(.horizontal, 26)
                DialogButtons(cancel: { showColors = false })
            }
        }
    }
}

// MARK: - Impostazioni dei menù

struct QueueMenuSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage(Prefs.queueArtwork) private var artwork = true
    @AppStorage(Prefs.queueSwipeRemove) private var swipeRemove = true
    @AppStorage(Prefs.queueSearch) private var search = true
    @AppStorage(Prefs.queueRemoveOthers) private var removeOthers = true

    var body: some View {
        SettingsPage(title: "Code") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsToggleRow(title: "Mostra le copertine degli album", isOn: $artwork)
                    SettingsToggleRow(title: "Scorri verso destra per rimuovere", isOn: $swipeRemove)
                    SettingsToggleRow(title: "Casella di ricerca rapida", isOn: $search)
                    SettingsToggleRow(title: "Conferma prima di rimuovere una coda", isOn: $settings.confirmQueueRemoval)
                    SettingsToggleRow(title: "Nella schermata di dialogo della selezione Code, mostra un'opzione per eliminare tutte le Code ad eccezione di quella in riproduzione",
                                      isOn: $removeOthers)
                }
            }
        }
    }
}

struct NowPlayingMenuSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage(Prefs.npRemaining) private var remaining = false
    @AppStorage(Prefs.npSwipe) private var swipe = true
    @AppStorage(Prefs.npBlur) private var blur = 3.0
    @AppStorage(Prefs.lyricsKeepAwake) private var lyricsAwake = true
    @AppStorage(Prefs.npArtTap) private var artTap = "artwork"
    @AppStorage(Prefs.npShowArtist) private var showArtist = true
    @AppStorage(Prefs.npShowAlbum) private var showAlbum = true
    @AppStorage(Prefs.npIcons) private var icons = false
    @AppStorage(Prefs.npCentered) private var centered = true
    @AppStorage(Prefs.npMarquee) private var marquee = true
    @AppStorage(Prefs.npSeekButtons) private var seekButtons = "long"
    @AppStorage(Prefs.npSeekHelpers) private var seekHelpers = true
    @AppStorage(Prefs.npThumbOnly) private var thumbOnly = false
    @AppStorage(Prefs.npMonthlyHint) private var monthlyHint = true
    @State private var showLyricsLook = false
    @State private var showArtTap = false
    @State private var showSeekButtons = false

    static let artTapOptions = [
        ChoiceOption(id: "none", label: "Non fa niente"),
        ChoiceOption(id: "lyrics", label: "Mostra i testi"),
        ChoiceOption(id: "artwork", label: "Vedi copertine Album"),
        ChoiceOption(id: "playPause", label: "Riproduci o Pausa"),
    ]
    static let seekOptions = [
        ChoiceOption(id: "off", label: "spento"),
        ChoiceOption(id: "long", label: "Durante la riproduzione di audiolibri, podcast o audio lungo"),
        ChoiceOption(id: "always", label: "Sempre"),
    ]

    var body: some View {
        SettingsPage(title: "In riproduzione") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsToggleRow(title: "Mostra il tempo rimanente invece che il tempo corrente mentre riproduci un brano", isOn: $remaining)
                    SettingsToggleRow(title: "Scorri in alto per il brano successivo e in basso per il precedente", isOn: $swipe)
                    SettingsSliderRow(title: "Sfondo sfocato", value: $blur, range: 0...3, step: 1) { "\(Int($0))x" }
                    SettingsRow(title: "Aspetto dei testi") { showLyricsLook = true }
                    SettingsToggleRow(title: "Mantieni lo schermo attivo quando è mostrato il menù 'In riproduzione'", isOn: $settings.keepScreenOn)
                    SettingsToggleRow(title: "Mantieni lo schermo attivo quando sono mostrati i testi", isOn: $lyricsAwake)
                    SettingsRow(title: "Quando tocco su Album Art…",
                                subtitle: Self.artTapOptions.first { $0.id == artTap }?.label) { showArtTap = true }

                    SettingsSectionHeader(title: "Mostra/nascondi/personalizza")
                    SettingsToggleRow(title: "Nome Artista", isOn: $showArtist)
                    SettingsToggleRow(title: "Titolo Album", isOn: $showAlbum)
                    SettingsToggleRow(title: "Icone prima del titolo Album e Artista", isOn: $icons)
                    SettingsToggleRow(title: "Informazioni brano allineate al centro", isOn: $centered)
                    SettingsToggleRow(title: "Testo scorrevole", isOn: $marquee)
                    SettingsRow(title: "Pulsanti Avanti-veloce e Riavvolgi",
                                subtitle: "Suggerimento: Senza questi pulsanti puoi ancora fare Avanti-veloce e Riavvolgi tenendo premuto sui pulsanti successivo/precedente") {
                        showSeekButtons = true
                    }
                    SettingsToggleRow(title: "Pulsanti di supporto per la barra di ricerca", subtitle: "\"Vai a\", \"Cancella\"", isOn: $seekHelpers)
                    SettingsToggleRow(title: "Prevenire il tocco accidentale sulla barra di ricerca, consentire il tocco solo sul pollice (manopola).", isOn: $thumbOnly)
                    SettingsToggleRow(title: "Suggeriscimi di controllare \"Brani più ascoltati\" alla fine di ogni mese e anno.", isOn: $monthlyHint)
                }
                .padding(.bottom, 40)
            }
        }
        .settingsDialog(isPresented: $showLyricsLook) { LyricsLookDialog { showLyricsLook = false } }
        .settingsDialog(isPresented: $showArtTap) {
            RadioDialog(title: "Quando tocco su Album Art…", options: Self.artTapOptions, selection: $artTap, resetValue: "artwork") {
                showArtTap = false
            }
        }
        .settingsDialog(isPresented: $showSeekButtons) {
            RadioDialog(title: "Pulsanti Avanti-veloce e Riavvolgi", options: Self.seekOptions, selection: $seekButtons) {
                showSeekButtons = false
            }
        }
    }
}

/// Aspetto dei testi: dimensione, allineamento, carattere.
struct LyricsLookDialog: View {
    let close: () -> Void
    @AppStorage(Prefs.lyricsSize) private var size = 0
    @AppStorage(Prefs.lyricsAlign) private var align = 1
    @AppStorage(Prefs.lyricsSerif) private var serif = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Aspetto dei testi").font(.title3.weight(.semibold))
            segmented(count: 3, selected: size, set: { size = $0 }) { i in
                Text("T").font(.system(size: [16, 22, 28][i], weight: .regular))
            }
            segmented(count: 3, selected: align, set: { align = $0 }) { i in
                Image(systemName: ["text.alignleft", "text.aligncenter", "text.alignright"][i]).font(.title3)
            }
            segmented(count: 2, selected: serif ? 1 : 0, set: { serif = $0 == 1 }) { i in
                Text("Abc").font(.system(size: 20, design: i == 1 ? .serif : .default))
            }
            DialogButtons(cancelTitle: "CHIUDI", cancel: close)
                .padding(.horizontal, -26)
        }
        .padding(.horizontal, 26)
        .padding(.top, 26)
    }

    private func segmented<Label: View>(count: Int, selected: Int, set: @escaping (Int) -> Void,
                                        @ViewBuilder label: @escaping (Int) -> Label) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Button { set(i) } label: {
                    label(i)
                        .foregroundStyle(i == selected ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(i == selected ? Color.accentColor.opacity(0.08) : Color.clear)
                        .overlay(Rectangle().stroke(i == selected ? Color.accentColor : Color(uiColor: .systemGray4),
                                                    lineWidth: i == selected ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(uiColor: .systemGray4), lineWidth: 1))
    }
}

/// Opzioni "Mostra le informazioni extra" (cartelle, album, artisti, generi).
enum ExtraInfo {
    static let base = [
        ChoiceOption(id: "auto", label: "Decide automaticamente il tipo di ordinamento"),
        ChoiceOption(id: "none", label: "Nessuno"),
        ChoiceOption(id: "count", label: "Numero di brani"),
        ChoiceOption(id: "duration", label: "Durata"),
        ChoiceOption(id: "date", label: "Data aggiornata"),
    ]
    static let withYear = base + [ChoiceOption(id: "year", label: "Anno")]
    static let album = withYear + [
        ChoiceOption(id: "artist", label: "Artista"),
        ChoiceOption(id: "albumArtist", label: "Artista album"),
        ChoiceOption(id: "composer", label: "Compositore"),
    ]
}

struct FoldersMenuSettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var ui: UIState
    @AppStorage(Prefs.foldersSearch) private var search = true
    @AppStorage(Prefs.foldersInfo) private var info = "duration"
    @AppStorage(Prefs.foldersHierarchical) private var hierarchical = false
    @State private var showInfo = false
    @State private var showStructure = false

    var body: some View {
        SettingsPage(title: "Cartelle") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsToggleRow(title: "Casella di ricerca rapida", isOn: $search)
                    SettingsRow(title: "Mostra le informazioni extra nella lista delle Cartelle") { showInfo = true }
                    SettingsRow(title: "Struttura Menù Cartelle",
                                subtitle: hierarchical ? "Gerarchico (cartelle all'interno di cartelle)" : "Lineare (tutte le cartelle in fila)") {
                        showStructure = true
                    }
                    SettingsRow(title: "Reset la Cartella musicale principale",
                                subtitle: hierarchical ? "Torna all'inizio delle cartelle" : "Non disponibile per struttura delle cartelle lineare",
                                enabled: hierarchical) {
                        ui.resetFolderTree += 1
                        ui.showToast("Cartella principale ripristinata")
                    }
                }
            }
        }
        .settingsDialog(isPresented: $showInfo) {
            RadioDialog(title: "Mostra le informazioni extra nella lista delle Cartelle", options: ExtraInfo.base,
                        selection: $info, resetValue: "duration") { showInfo = false }
        }
        .settingsDialog(isPresented: $showStructure) {
            RadioDialog(title: "Struttura Menù Cartelle",
                        options: [ChoiceOption(id: "linear", label: "Lineare (tutte le cartelle in fila)"),
                                  ChoiceOption(id: "tree", label: "Gerarchico (cartelle all'interno di cartelle)")],
                        selection: Binding(get: { hierarchical ? "tree" : "linear" }, set: { hierarchical = $0 == "tree" })) {
                showStructure = false
            }
        }
    }
}

struct AlbumsMenuSettingsPage: View {
    @AppStorage(Prefs.albumsView) private var viewMode = "grid"
    @AppStorage(Prefs.albumsGridSize) private var gridSize = 2
    @AppStorage(Prefs.albumsInfo) private var info = "auto"
    @AppStorage(Prefs.albumsSplit) private var split = true
    @AppStorage(Prefs.albumsSearch) private var search = true
    @State private var showView = false
    @State private var showGrid = false
    @State private var showInfo = false

    static let viewOptions = [
        ChoiceOption(id: "listPlain", label: "Elenco senza copertine"),
        ChoiceOption(id: "listArt", label: "Elenco con copertine"),
        ChoiceOption(id: "grid", label: "Vista a griglia"),
    ]
    static let gridOptions = ["Molto piccolo", "Piccolo", "medio", "Grande", "Molto grande"]

    var body: some View {
        SettingsPage(title: "Album") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Modalità vista Album", subtitle: Self.viewOptions.first { $0.id == viewMode }?.label) { showView = true }
                    SettingsRow(title: "Dimensioni della griglia", subtitle: Self.gridOptions[max(0, min(4, gridSize))],
                                enabled: viewMode == "grid") { showGrid = true }
                    SettingsRow(title: "Mostra le informazioni extra nella lista degli Album") { showInfo = true }
                    SettingsToggleRow(title: "Dividi i brani in ogni Album in sottocategorie come ad esempio Artisti, Artisti album o Compositori",
                                      isOn: $split)
                    SettingsToggleRow(title: "Casella di ricerca rapida", isOn: $search)
                }
            }
        }
        .settingsDialog(isPresented: $showView) {
            RadioDialog(title: "Modalità vista Album", options: Self.viewOptions, selection: $viewMode) { showView = false }
        }
        .settingsDialog(isPresented: $showGrid) {
            RadioDialog(title: "Dimensioni della griglia",
                        options: Self.gridOptions.enumerated().map { ChoiceOption(id: "\($0.offset)", label: $0.element) },
                        selection: Binding(get: { "\(gridSize)" }, set: { gridSize = Int($0) ?? 2 })) { showGrid = false }
        }
        .settingsDialog(isPresented: $showInfo) {
            RadioDialog(title: "Mostra le informazioni extra nella lista degli Album", options: ExtraInfo.album,
                        selection: $info) { showInfo = false }
        }
    }
}

struct ArtistsMenuSettingsPage: View {
    @AppStorage(Prefs.artistsInfo) private var info = "duration"
    @AppStorage(Prefs.artistsSplit) private var split = true
    @AppStorage(Prefs.artistsAlbumSort) private var albumSort = "yearDesc"
    @AppStorage(Prefs.artistsSearch) private var search = true
    @State private var showInfo = false
    @State private var showSort = false

    static let sortOptions = [
        ChoiceOption(id: "name", label: "Nome"),
        ChoiceOption(id: "yearAsc", label: "Anno (dal più vecchio)"),
        ChoiceOption(id: "yearDesc", label: "Anno (dal più recente)"),
    ]

    var body: some View {
        SettingsPage(title: "Artisti") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Mostra le informazioni extra nella lista degli Artisti") { showInfo = true }
                    SettingsToggleRow(title: "Dividi i brani per ogni artista/artista album/compositori in sottocategorie come ad esempio i loro album",
                                      isOn: $split)
                    SettingsRow(title: "Ordina Album di un artista/artista album/compositore",
                                subtitle: Self.sortOptions.first { $0.id == albumSort }?.label) { showSort = true }
                    SettingsToggleRow(title: "Casella di ricerca rapida", isOn: $search)
                }
            }
        }
        .settingsDialog(isPresented: $showInfo) {
            RadioDialog(title: "Mostra le informazioni extra nella lista degli Artisti", options: ExtraInfo.withYear,
                        selection: $info, resetValue: "duration") { showInfo = false }
        }
        .settingsDialog(isPresented: $showSort) {
            RadioDialog(title: "Ordina Album di un artista/artista album/compositore", options: Self.sortOptions,
                        selection: $albumSort) { showSort = false }
        }
    }
}

struct GenresMenuSettingsPage: View {
    @AppStorage(Prefs.genresInfo) private var info = "auto"
    @AppStorage(Prefs.genresSplit) private var split = true
    @AppStorage(Prefs.genresSearch) private var search = true
    @State private var showInfo = false

    var body: some View {
        SettingsPage(title: "Genere") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Mostra le informazioni extra nella lista dei Generi") { showInfo = true }
                    SettingsToggleRow(title: "Dividi i brani per ogni Genere in sottocategorie come ad esempio Artisti, Artisti album o Compositori",
                                      isOn: $split)
                    SettingsToggleRow(title: "Casella di ricerca rapida", isOn: $search)
                }
            }
        }
        .settingsDialog(isPresented: $showInfo) {
            RadioDialog(title: "Mostra le informazioni extra nella lista dei Generi", options: ExtraInfo.withYear,
                        selection: $info) { showInfo = false }
        }
    }
}

struct PlaylistsMenuSettingsPage: View {
    @AppStorage(Prefs.playlistsSearch) private var search = true

    var body: some View {
        SettingsPage(title: "Playlist") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsToggleRow(title: "Casella di ricerca rapida", isOn: $search)
                }
            }
        }
    }
}

// MARK: - Opzioni e menù

enum MenuOptions {
    static let main = [
        ChoiceOption(id: "equalizer", label: "Equalizzatore"),
        ChoiceOption(id: "sleepTimer", label: "Sleep timer"),
        ChoiceOption(id: "scan", label: "Scansione"),
        ChoiceOption(id: "quit", label: "Chiudi l'app"),
    ]
    static let quick = [
        ChoiceOption(id: "favorite", label: "Aggiungi/rimuovi dai preferiti"),
        ChoiceOption(id: "info", label: "Info del brano"),
        ChoiceOption(id: "lyrics", label: "Mostra i testi"),
        ChoiceOption(id: "bookmarks", label: "Segnalibri/Note"),
        ChoiceOption(id: "ab", label: "Ripeti tra A-B"),
        ChoiceOption(id: "speed", label: "Velocità di riproduzione e Tono"),
        ChoiceOption(id: "crossfade", label: "Crossfade"),
        ChoiceOption(id: "replayGain", label: "ReplayGain"),
        ChoiceOption(id: "addToPlaylist", label: "Aggiungi alle playlist"),
        ChoiceOption(id: "share", label: "Condividi brano"),
        ChoiceOption(id: "search", label: "Ricerca"),
        ChoiceOption(id: "sleepTimer", label: "Sleep timer"),
        ChoiceOption(id: "equalizer", label: "Equalizzatore"),
    ]
    static let nowPlaying = [
        ChoiceOption(id: "lyrics", label: "Mostra i testi"),
        ChoiceOption(id: "bookmarks", label: "Segnalibri/Note"),
        ChoiceOption(id: "info", label: "Info del brano"),
        ChoiceOption(id: "favorite", label: "Aggiungi/rimuovi dai preferiti"),
        ChoiceOption(id: "ab", label: "Ripeti tra A-B"),
        ChoiceOption(id: "speed", label: "Velocità di riproduzione e Tono"),
        ChoiceOption(id: "crossfade", label: "Crossfade"),
        ChoiceOption(id: "cast", label: "Cast (AirPlay)"),
        ChoiceOption(id: "share", label: "Condividi brano"),
        ChoiceOption(id: "tagEditor", label: "Modifica tag"),
        ChoiceOption(id: "replayGain", label: "ReplayGain"),
        ChoiceOption(id: "move", label: "Sposta in una cartella"),
        ChoiceOption(id: "copy", label: "Copia in una cartella"),
        ChoiceOption(id: "delete", label: "Cancella definitivamente"),
        ChoiceOption(id: "customize", label: "Mostra/nascondi/personalizza"),
        ChoiceOption(id: "quickSettings", label: "Scorciatoie \"accesso rapido\""),
    ]
    static let track = [
        ChoiceOption(id: "share", label: "Condividi"),
        ChoiceOption(id: "tagEditor", label: "Modifica tag"),
        ChoiceOption(id: "speed", label: "Velocità di riproduzione"),
        ChoiceOption(id: "rg", label: "Leggi RG"),
        ChoiceOption(id: "move", label: "Sposta in una cartella"),
        ChoiceOption(id: "copy", label: "Copia in una cartella"),
        ChoiceOption(id: "delete", label: "Cancella definitivamente"),
        ChoiceOption(id: "preview", label: "Anteprima"),
        ChoiceOption(id: "stopAfter", label: "Fermati dopo questa canzone"),
    ]
    static let multi = [
        ChoiceOption(id: "advShuffle", label: "Shuffle avanzato"),
        ChoiceOption(id: "share", label: "Condividi"),
        ChoiceOption(id: "tagEditor", label: "Modifica tag"),
        ChoiceOption(id: "speed", label: "Velocità di riproduzione"),
        ChoiceOption(id: "rg", label: "Leggi RG"),
        ChoiceOption(id: "move", label: "Sposta in una cartella"),
        ChoiceOption(id: "copy", label: "Copia in una cartella"),
        ChoiceOption(id: "delete", label: "Cancella definitivamente"),
        ChoiceOption(id: "clearHistory", label: "Cancella cronologia di riproduzione"),
    ]
    static let group = [
        ChoiceOption(id: "advShuffle", label: "Shuffle avanzato"),
        ChoiceOption(id: "share", label: "Condividi"),
        ChoiceOption(id: "tagEditor", label: "Modifica tag"),
        ChoiceOption(id: "speed", label: "Velocità di riproduzione"),
        ChoiceOption(id: "rg", label: "Leggi RG"),
        ChoiceOption(id: "move", label: "Sposta in una cartella"),
        ChoiceOption(id: "copy", label: "Copia in una cartella"),
        ChoiceOption(id: "delete", label: "Cancella definitivamente"),
    ]
    static let folder = [
        ChoiceOption(id: "rename", label: "Rinomina la cartella"),
        ChoiceOption(id: "exclude", label: "Escludi questa cartella dalla scansione"),
    ] + group
}

struct OptionsMenusPage: View {
    private enum Which: String, Identifiable {
        case main, quick, nowPlaying, track, multi, folder, album, artist, genre, playlist
        var id: String { rawValue }
    }

    @AppStorage(Prefs.menuMain) private var main = ""
    @AppStorage(Prefs.menuQuick) private var quick = ""
    @AppStorage(Prefs.menuNowPlaying) private var nowPlaying = ""
    @AppStorage(Prefs.menuTrack) private var track = ""
    @AppStorage(Prefs.menuMulti) private var multi = ""
    @AppStorage(Prefs.menuFolder) private var folder = ""
    @AppStorage(Prefs.menuAlbum) private var album = ""
    @AppStorage(Prefs.menuArtist) private var artist = ""
    @AppStorage(Prefs.menuGenre) private var genre = ""
    @AppStorage(Prefs.menuPlaylist) private var playlist = ""
    @State private var open: Which?

    var body: some View {
        SettingsPage(title: "Opzioni e menù") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Menù principale", systemIcon: "ellipsis") { open = .main }
                    SettingsRow(title: "Scorciatoie \"accesso rapido\"", systemIcon: "play.circle.fill") { open = .quick }
                    SettingsRow(title: "Opzioni per Menù 'In riproduzione'", systemIcon: "ellipsis.rectangle.fill") { open = .nowPlaying }
                    SettingsRow(title: "Opzioni per un singolo brano", systemIcon: "ellipsis.rectangle.fill") { open = .track }
                    SettingsRow(title: "Opzioni per la 'selezione multipla'", systemIcon: "ellipsis.rectangle.fill") { open = .multi }
                    SettingsRow(title: "Opzioni per una Cartella", systemIcon: "ellipsis.rectangle.fill") { open = .folder }
                    SettingsRow(title: "Opzioni per un Album", systemIcon: "ellipsis.rectangle.fill") { open = .album }
                    SettingsRow(title: "Opzioni per un artista/artista album/compositore", systemIcon: "ellipsis.rectangle.fill") { open = .artist }
                    SettingsRow(title: "Opzioni per un Genere", systemIcon: "ellipsis.rectangle.fill") { open = .genre }
                    SettingsRow(title: "Opzioni per una playlist", systemIcon: "ellipsis.rectangle.fill") { open = .playlist }
                }
            }
        }
        .settingsDialog(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) {
            if let which = open { dialog(which) }
        }
    }

    @ViewBuilder
    private func dialog(_ which: Which) -> some View {
        let close = { open = nil }
        switch which {
        case .main: CheckboxDialog(title: "Menù principale", options: MenuOptions.main, stored: $main, close: close)
        case .quick: CheckboxDialog(title: "Scorciatoie \"accesso rapido\"", options: MenuOptions.quick, stored: $quick, close: close)
        case .nowPlaying:
            CheckboxDialog(title: "Opzioni per Menù 'In riproduzione'", options: MenuOptions.nowPlaying, stored: $nowPlaying,
                           resetValue: Prefs.defaults[Prefs.menuNowPlaying] as? String, close: close)
        case .track: CheckboxDialog(title: "Opzioni per un singolo brano", options: MenuOptions.track, stored: $track, close: close)
        case .multi: CheckboxDialog(title: "Opzioni per la 'selezione multipla'", options: MenuOptions.multi, stored: $multi, close: close)
        case .folder: CheckboxDialog(title: "Opzioni per una Cartella", options: MenuOptions.folder, stored: $folder, close: close)
        case .album: CheckboxDialog(title: "Opzioni per un Album", options: MenuOptions.group, stored: $album, close: close)
        case .artist: CheckboxDialog(title: "Opzioni per un artista/artista album/compositore", options: MenuOptions.group, stored: $artist, close: close)
        case .genre: CheckboxDialog(title: "Opzioni per un Genere", options: MenuOptions.group, stored: $genre, close: close)
        case .playlist: CheckboxDialog(title: "Opzioni per una playlist", options: MenuOptions.group, stored: $playlist, close: close)
        }
    }
}

// MARK: - Ricerca nelle impostazioni

struct SettingsEntry: Identifiable {
    let id = UUID()
    let title: String
    let path: [SettingsDest]

    var category: String { path.isEmpty ? "Impostazioni" : path.map(\.title).joined(separator: " > ") }

    static let all: [SettingsEntry] = {
        func e(_ title: String, _ path: SettingsDest...) -> SettingsEntry { SettingsEntry(title: title, path: path) }
        return [
            e("Lingua"),
            e("Interfaccia", .interface),
            e("Tema", .interface, .theme),
            e("Tema chiaro", .interface, .theme),
            e("Tema scuro", .interface, .theme),
            e("Tema nero (AMOLED)", .interface, .theme),
            e("Giorno/notte tempo", .interface, .theme),
            e("Colori per risalto", .interface, .theme),
            e("Posizione della barra delle schede", .interface),
            e("Ordina i menù", .interface),
            e("Scheda all'avvio", .interface),
            e("Mostra le copertine degli album", .interface, .menuQueue),
            e("Scorri verso destra per rimuovere", .interface, .menuQueue),
            e("Casella di ricerca rapida", .interface, .menuQueue),
            e("Conferma prima di rimuovere una coda", .interface, .menuQueue),
            e("Eliminare tutte le Code ad eccezione di quella in riproduzione", .interface, .menuQueue),
            e("Mostra il tempo rimanente invece che il tempo corrente", .interface, .menuNowPlaying),
            e("Scorri in alto per il brano successivo e in basso per il precedente", .interface, .menuNowPlaying),
            e("Sfondo sfocato", .interface, .menuNowPlaying),
            e("Aspetto dei testi", .interface, .menuNowPlaying),
            e("Mantieni lo schermo attivo", .interface, .menuNowPlaying),
            e("Quando tocco su Album Art", .interface, .menuNowPlaying),
            e("Nome Artista", .interface, .menuNowPlaying),
            e("Titolo Album", .interface, .menuNowPlaying),
            e("Icone prima del titolo Album e Artista", .interface, .menuNowPlaying),
            e("Informazioni brano allineate al centro", .interface, .menuNowPlaying),
            e("Testo scorrevole", .interface, .menuNowPlaying),
            e("Pulsanti Avanti-veloce e Riavvolgi", .interface, .menuNowPlaying),
            e("Pulsanti di supporto per la barra di ricerca", .interface, .menuNowPlaying),
            e("Prevenire il tocco accidentale sulla barra di ricerca", .interface, .menuNowPlaying),
            e("Brani più ascoltati alla fine di ogni mese e anno", .interface, .menuNowPlaying),
            e("Mostra le informazioni extra nella lista delle Cartelle", .interface, .menuFolders),
            e("Struttura Menù Cartelle", .interface, .menuFolders),
            e("Reset la Cartella musicale principale", .interface, .menuFolders),
            e("Casella di ricerca rapida", .interface, .menuFolders),
            e("Modalità vista Album", .interface, .menuAlbums),
            e("Dimensioni della griglia", .interface, .menuAlbums),
            e("Mostra le informazioni extra nella lista degli Album", .interface, .menuAlbums),
            e("Dividi i brani in ogni Album in sottocategorie", .interface, .menuAlbums),
            e("Casella di ricerca rapida", .interface, .menuAlbums),
            e("Mostra le informazioni extra nella lista degli Artisti", .interface, .menuArtists),
            e("Dividi i brani per ogni artista in sottocategorie", .interface, .menuArtists),
            e("Ordina Album di un artista", .interface, .menuArtists),
            e("Casella di ricerca rapida", .interface, .menuArtists),
            e("Mostra le informazioni extra nella lista dei Generi", .interface, .menuGenres),
            e("Dividi i brani per ogni Genere in sottocategorie", .interface, .menuGenres),
            e("Casella di ricerca rapida", .interface, .menuGenres),
            e("Casella di ricerca rapida", .interface, .menuPlaylists),
            e("Menù principale", .interface, .optionsMenus),
            e("Scorciatoie \"accesso rapido\"", .interface, .optionsMenus),
            e("Opzioni per Menù 'In riproduzione'", .interface, .optionsMenus),
            e("Opzioni per un singolo brano", .interface, .optionsMenus),
            e("Opzioni per la 'selezione multipla'", .interface, .optionsMenus),
            e("Opzioni per una Cartella", .interface, .optionsMenus),
            e("Opzioni per un Album", .interface, .optionsMenus),
            e("Opzioni per un artista/artista album/compositore", .interface, .optionsMenus),
            e("Opzioni per un Genere", .interface, .optionsMenus),
            e("Opzioni per una playlist", .interface, .optionsMenus),
            e("Audio", .audio),
            e("Velocità di riproduzione e Tono", .audio),
            e("Focus audio", .audio),
            e("Riproduzione Gapless", .audio),
            e("Crossfade", .audio),
            e("Sfuma il volume quando riproduci", .audio),
            e("Sfuma il volume quando vai in pausa", .audio),
            e("Decoder", .audio),
            e("Equalizzatore da usare", .audio),
            e("Equalizzatore di AuguMusic", .audio, .eqSettings),
            e("Effetti di riverbero", .audio, .eqSettings),
            e("Non consentire la riproduzione se il volume dell'audio è 0", .audio),
            e("Metti in pausa quando l'audio è disattivato", .audio),
            e("Riprendi quando l'audio è nuovamente abilitato", .audio),
            e("ReplayGain", .audio, .replayGain),
            e("Modalità ReplayGain", .audio, .replayGain),
            e("Leggi/Calcola RG", .audio, .replayGain, .replayGainCalc),
            e("Leggi/calcola automaticamente il RG della canzone corrente e la canzone successiva", .audio, .replayGain),
            e("Preamp per file con RG", .audio, .replayGain),
            e("Preamp per file senza RG", .audio, .replayGain),
            e("Libreria brani e tag", .library),
            e("Cartelle da analizzare", .library, .scanFolders),
            e("Aggiungi cartella", .library, .scanFolders),
            e("Cartelle escluse", .library, .excludedFolders),
            e("Escludi file dalla durata breve", .library),
            e("Avanzati", .library, .libraryAdvanced),
            e("Scanner preferito", .library, .libraryAdvanced),
            e("Se il tag AlbumArtist non è presente, utilizza il tag Artista", .library, .libraryAdvanced),
            e("Scansione all'interno di cartelle nascoste", .library, .libraryAdvanced),
            e("Scansione all'interno di cartelle \"nomedia\"", .library, .libraryAdvanced),
            e("Scansione di file video", .library, .libraryAdvanced),
            e("Scansione", .library),
            e("Scansione automatica", .library),
            e("Strategia di unione degli album", .library),
            e("Multi Artisti", .library),
            e("Separatori per \"Multi Artisti\"", .library),
            e("Multi Artisti album", .library),
            e("Multi Compositori", .library),
            e("Multi Genere", .library),
            e("Eccezioni (mai divisi)", .library),
            e("Usa i file folder.jpg, cover.jpg ecc", .library),
            e("Sorgente preferita per i testi", .library),
            e("Nascondi contenuti extra dai tag", .library, .hideExtra),
            e("Tipi di file supportati", .library),
            e("Auricolare, Bluetooth e altoparlanti", .headset),
            e("Interrompi quando disconnetti", .headset),
            e("Riprendi solo se messo in pausa dalla disconnessione prima", .headset),
            e("Riprendi quando il bluetooth si collega", .headset),
            e("Riprendi quando si collegano cuffie/altoparlanti cablati", .headset),
            e("Prevenire la riproduzione automatica indesiderata", .headset, .preventAutoplay),
            e("Restrizioni più severe", .headset, .preventAutoplay),
            e("Azione a doppia pressione del pulsante dell'auricolare", .headset),
            e("Azione a tripla pressione del pulsante dell'auricolare", .headset),
            e("Widget HomeScreen", .widget),
            e("Mostra il nome del file invece del titolo", .advanced),
            e("Successivo e Precedente come Avanti veloce e Riavvolgi", .advanced),
            e("Ricorda l'ultima posizione di tutti i brani", .advanced),
            e("Durata minima per considerarla una riproduzione", .advanced),
            e("Funzionamento pulsante Brano precedente", .advanced),
            e("Conferma prima di chiudere l'app", .advanced),
            e("Quando attivo la 'Modalità Shuffle'", .advanced),
            e("Quando seleziono 'Random' come ordinamento per una Coda", .advanced),
            e("Quando esiste già una coda con lo stesso nome della sorgente", .advanced),
            e("Avvia la riproduzione all'avvio dell'app", .advanced),
            e("Cast", .advanced),
            e("Esporta automaticamente i più ascoltati in file CSV", .advanced, .csvExport),
            e("Carica la copertina dell'album", .advanced),
            e("Controllo esterno avanzato", .advanced),
            e("Durata dell'Avanti-veloce", .advanced),
            e("Durata del Riavvolgi", .advanced),
            e("Motore di ricerca predefinito", .advanced),
            e("Interrogazione per cercare la copertina dell'album", .advanced),
            e("Interrogazione per cercare i testi", .advanced),
            e("Shuffle avanzato", .advanced, .advancedShuffle),
            e("Ignora alcune parole all'inizio durante l'ordinamento", .advanced, .ignoreWords),
            e("Ordinamento alfanumerico", .advanced),
            e("Backup/Ripristino", .backup),
            e("Esegui il backup ora", .backup),
            e("Backup automatico", .backup),
            e("Ripristina ora", .backup),
            e("Tema del widget", .widget),
            e("Copertina Album", .widget),
            e("Aggiungi alle playlist", .widget),
            e("Aggiungi/rimuovi dai preferiti", .widget),
            e("Pulsanti Avanti-veloce e Riavvolgi", .widget),
            e("Dispositivi di memoria", .library),
        ]
    }()
}

struct SettingsSearchResults: View {
    let query: String
    let open: (SettingsEntry) -> Void

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let results = SettingsEntry.all.filter { $0.title.matchesSearch(q) || $0.category.matchesSearch(q) }
        let categories = Set(results.map(\.category)).count
        VStack(alignment: .leading, spacing: 0) {
            Text(results.isEmpty ? "Nessun risultato" : (categories == 1 ? "Trovato in 1 categoria" : "Trovato in \(categories) categorie"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            HairlineSeparator()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { entry in
                        Button { open(entry) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(entry.title)
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HairlineSeparator()
                    }
                }
            }
            .frame(maxHeight: 520)
        }
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(uiColor: .systemGray4), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(16)
    }
}
