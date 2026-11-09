import SwiftUI

enum NowPlayingSheet: String, Identifiable {
    case equalizer, sleepTimer, playback, queue, bookmarks, info, addToPlaylist, tagEditor, search
    var id: String { rawValue }
}

enum SidePanel: String, CaseIterable, Identifiable {
    case lyrics, bookmarks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lyrics: "Testo"
        case .bookmarks: "Segnalibri"
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss

    @AppStorage("nowPlayingSidePanel") private var sidePanel: SidePanel = .lyrics
    @State private var showLyricsInline = false
    @State private var lyrics: Lyrics?
    @State private var sheet: NowPlayingSheet?
    @State private var artistChoices: [String] = []
    @State private var showFullArtwork = false
    @State private var showEqualizer = false
    @State private var pendingSearch: (query: String, images: Bool)?

    @AppStorage(Prefs.npSwipe) private var swipeTracks = true
    @AppStorage(Prefs.lyricsKeepAwake) private var lyricsAwake = true
    @AppStorage(Prefs.npArtTap) private var artTap = "artwork"
    @AppStorage(Prefs.npShowArtist) private var showArtist = true
    @AppStorage(Prefs.npShowAlbum) private var showAlbum = true
    @AppStorage(Prefs.npIcons) private var titleIcons = false
    @AppStorage(Prefs.npCentered) private var centered = true
    @AppStorage(Prefs.npMarquee) private var marquee = true
    @AppStorage(Prefs.npSeekButtons) private var seekButtons = "long"
    @AppStorage(Prefs.npMonthlyHint) private var monthlyHint = true
    @AppStorage(Prefs.lastMonthlyHint) private var lastMonthlyHint = ""
    @AppStorage(Prefs.menuQuick) private var quickItems = ""
    @AppStorage(Prefs.menuNowPlaying) private var menuItems = ""

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width > 700
            ZStack {
                VStack(spacing: 0) {
                    topBar
                    if wide {
                        // Tablet in orizzontale: copertina (o testo) a sinistra, tasti di riproduzione a destra.
                        HStack(alignment: .center, spacing: 36) {
                            artworkArea(wide: true)
                                .frame(maxWidth: geo.size.width * 0.48, maxHeight: .infinity)
                            VStack(spacing: 22) {
                                Spacer(minLength: 0)
                                titleBlock
                                SeekBar()
                                transportControls
                                secondaryControls(wide: true)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: 520)
                        }
                        .padding(.horizontal, 36)
                        .padding(.bottom, 20)
                    } else {
                        playerPanel(wide: false)
                            .frame(maxWidth: 620)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(NowPlayingBackdrop())
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
        .task(id: player.loadedTrackID) {
            lyrics = nil
            guard let track = player.currentTrack, let url = library.url(for: track) else { return }
            lyrics = await LyricsLoader.load(url: url)
        }
        .confirmationDialog("Vai all'artista",
                            isPresented: Binding(get: { !artistChoices.isEmpty }, set: { if !$0 { artistChoices = [] } }),
                            titleVisibility: .visible) {
            ForEach(artistChoices, id: \.self) { name in
                Button(name) {
                    ui.navigate(.group(.artist, library.artistID(for: name)))
                    artistChoices = []
                }
            }
        }
        .confirmationDialog("Cerca con…",
                            isPresented: Binding(get: { pendingSearch != nil }, set: { if !$0 { pendingSearch = nil } }),
                            titleVisibility: .visible) {
            ForEach(OnlineSearch.engines.indices, id: \.self) { i in
                let engine = OnlineSearch.engines[i]
                Button(engine.name) {
                    if let s = pendingSearch { OnlineSearch.open(engine: engine.id, query: s.query, images: s.images) }
                    pendingSearch = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showEqualizer) { EqualizerView() }
        .fullScreenCover(isPresented: $showFullArtwork) {
            FullArtworkView(image: player.nowPlayingImage) { showFullArtwork = false }
        }
        .onAppear {
            updateIdleTimer()
            showMonthlyHintIfNeeded()
        }
        .onChange(of: showLyricsInline) { _, _ in updateIdleTimer() }
        .onChange(of: settings.keepScreenOn) { _, _ in updateIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// "Motore di ricerca predefinito": apre la ricerca, oppure chiede quale motore usare.
    private func searchOnline(_ query: String, images: Bool) {
        let engine = Prefs.string(Prefs.searchEngine)
        if engine == "ask" {
            pendingSearch = (query, images)
        } else {
            OnlineSearch.open(engine: engine, query: query, images: images)
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn || (showLyricsInline && lyricsAwake)
    }

    /// A inizio mese (e d'anno) ricorda di guardare i "Brani più ascoltati", come Musicolet.
    private func showMonthlyHintIfNeeded() {
        guard monthlyHint else { return }
        let cal = Calendar.current
        let now = Date()
        guard cal.component(.day, from: now) <= 3 else { return }
        let key = now.formatted(.dateTime.year().month(.twoDigits))
        guard lastMonthlyHint != key else { return }
        lastMonthlyHint = key
        let newYear = cal.component(.month, from: now) == 1
        ui.showToast(newYear ? "È finito l'anno: guarda i tuoi \"Brani più ascoltati\" in Playlist"
                             : "È finito il mese: guarda i tuoi \"Brani più ascoltati\" in Playlist")
    }

    private func artTapped() {
        switch artTap {
        case "lyrics": withAnimation(.easeInOut(duration: 0.25)) { showLyricsInline.toggle() }
        case "artwork": if player.nowPlayingImage != nil { showFullArtwork = true }
        case "playPause": player.togglePlayPause()
        default: break
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard swipeTracks, abs(value.translation.height) > abs(value.translation.width) * 1.5 else { return }
                if value.translation.height < -60 { player.next() } else if value.translation.height > 60 { player.previous() }
            }
    }

    private var showSeekButtons: Bool {
        switch seekButtons {
        case "always": true
        case "long": player.duration >= 20 * 60
        default: false
        }
    }

    private func openArtist(_ t: Track) {
        let names = library.artistNames(for: t)
        if names.count == 1 {
            ui.navigate(.group(.artist, library.artistID(for: names[0])))
        } else {
            artistChoices = names
        }
    }

    // MARK: Parti

    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer()
            VStack(spacing: 2) {
                Text(player.activeQueue?.name ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let q = player.activeQueue {
                    Text("\(q.items.isEmpty ? 0 : q.index + 1) di \(q.items.count)\(q.isShuffled ? " · casuale" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if menuItems.csvContains("cast") && Prefs.bool(Prefs.castEnabled) {
                AirPlayButton().frame(width: 40, height: 40)
            }
            moreMenu
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var moreMenu: some View {
        Menu {
            if let t = player.currentTrack {
                if menuItems.csvContains("lyrics") {
                    Button { withAnimation { showLyricsInline.toggle() } } label: { Label("Mostra i testi", systemImage: "quote.bubble") }
                }
                if menuItems.csvContains("bookmarks") {
                    Button { sheet = .bookmarks } label: { Label("Segnalibri/Note", systemImage: "bookmark") }
                }
                Button { sheet = .info } label: { Label("Informazioni", systemImage: "info.circle") }
                if menuItems.csvContains("favorite") {
                    Button { userData.toggleFavorite(t.id) } label: {
                        Label(userData.isFavorite(t.id) ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
                              systemImage: userData.isFavorite(t.id) ? "heart.slash" : "heart")
                    }
                }
                Button { sheet = .addToPlaylist } label: { Label("Aggiungi a playlist…", systemImage: "music.note.list") }
                if menuItems.csvContains("tagEditor") {
                    Button { sheet = .tagEditor } label: { Label("Modifica tag…", systemImage: "tag") }
                }
                if let albumID = library.albumID(for: t) {
                    Button { ui.navigate(.group(.album, albumID)) } label: { Label("Vai all'album", systemImage: "square.stack") }
                }
                Button { openArtist(t) } label: {
                    Label("Vai all'artista", systemImage: "music.mic")
                }
                Button { ui.navigate(.group(.folder, library.folderID(for: t))) } label: {
                    Label("Vai alla cartella", systemImage: "folder")
                }
                Menu {
                    Button { searchOnline(OnlineSearch.query(Prefs.string(Prefs.artQuery), track: t), images: true) } label: {
                        Label("Cerca la copertina", systemImage: "photo")
                    }
                    Button { searchOnline(OnlineSearch.query(Prefs.string(Prefs.lyricsQuery), track: t), images: false) } label: {
                        Label("Cerca il testo", systemImage: "quote.bubble")
                    }
                } label: { Label("Cerca online", systemImage: "globe") }
                Divider()
                if menuItems.csvContains("speed") {
                    Button { sheet = .playback } label: { Label("Velocità di riproduzione e Tono", systemImage: "speedometer") }
                }
                if menuItems.csvContains("crossfade") {
                    Button { ui.showAudioQuick = .crossfade } label: { Label("Crossfade", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                }
                if menuItems.csvContains("replayGain") {
                    Button { ui.showAudioQuick = .replayGain } label: { Label("ReplayGain", systemImage: "waveform") }
                }
                if menuItems.csvContains("ab") {
                    Menu {
                        Button { player.setABPointA() } label: { Label("Imposta punto A", systemImage: "a.circle") }
                        Button { player.setABPointB() } label: { Label("Imposta punto B", systemImage: "b.circle") }
                        if player.abRepeat.a != nil {
                            Button(role: .destructive) { player.clearAB() } label: { Label("Disattiva A-B", systemImage: "xmark") }
                        }
                    } label: { Label("Ripeti tra A-B", systemImage: "repeat") }
                }
                if let qi = player.activeQueue, qi.isShuffled {
                    Button { player.reshuffle() } label: { Label("Rimescola la coda", systemImage: "arrow.triangle.2.circlepath") }
                }
                if let url = library.url(for: t), menuItems.csvContains("share") {
                    ShareLink(item: url) { Label("Condividi brano", systemImage: "square.and.arrow.up") }
                }
                if let url = library.url(for: t) {
                    if menuItems.csvContains("move") {
                        Button { ui.fileTransfer = FileTransferRequest(urls: [url], asCopy: false) } label: {
                            Label("Sposta in una cartella…", systemImage: "folder.badge.gearshape")
                        }
                    }
                    if menuItems.csvContains("copy") {
                        Button { ui.fileTransfer = FileTransferRequest(urls: [url], asCopy: true) } label: {
                            Label("Copia in una cartella…", systemImage: "doc.on.doc")
                        }
                    }
                }
                if menuItems.csvContains("delete") {
                    Button(role: .destructive) { ui.deleteRequest = TrackIDList(ids: [t.id]) } label: {
                        Label("Cancella definitivamente", systemImage: "trash")
                    }
                }
            }
            if menuItems.csvContains("customize") || menuItems.csvContains("quickSettings") {
                Divider()
            }
            if menuItems.csvContains("customize") {
                Button { ui.openSettings([.interface, .menuNowPlaying]) } label: {
                    Label("Mostra/nascondi/personalizza", systemImage: "slider.horizontal.3")
                }
            }
            if menuItems.csvContains("quickSettings") {
                Button { ui.openSettings([.interface, .optionsMenus]) } label: {
                    Label("Scorciatoie \"accesso rapido\"", systemImage: "square.grid.2x2")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private func playerPanel(wide: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)
            artworkArea(wide: wide)
                .layoutPriority(1)

            titleBlock
            SeekBar()
            transportControls
            secondaryControls(wide: wide)
            Spacer(minLength: 4)
        }
    }

    /// Copertina, oppure il testo quando è attivo (tocca per passare dall'uno all'altro).
    private func artworkArea(wide: Bool) -> some View {
        Group {
            if showLyricsInline {
                LyricsView(lyrics: lyrics)
                    .frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil)
                    .aspectRatio(wide ? nil : 1, contentMode: .fit)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ArtworkView(track: player.currentTrack, maxPixel: 1000, cornerRadius: 16, mode: .natural)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if showLyricsInline {
                withAnimation(.easeInOut(duration: 0.25)) { showLyricsInline = false }
            } else {
                artTapped()
            }
        }
        .gesture(swipeGesture, including: showLyricsInline ? .subviews : .all)
    }

    /// Titolo centrato, sotto l'artista e sotto ancora l'album (come Musicolet).
    private var titleBlock: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 4) {
            infoLine(player.currentTrack.map { TagCleaner.nowPlaying($0.displayTitle) } ?? "Niente in riproduzione", font: .title2, color: .primary, lines: 2)
            if let t = player.currentTrack {
                if showArtist {
                    Button { openArtist(t) } label: {
                        infoLine(TagCleaner.nowPlaying(t.displayArtist), icon: titleIcons ? "music.mic" : nil, font: .body, color: .secondary, lines: 1)
                    }
                    .buttonStyle(.plain)
                }
                if showAlbum {
                    Button {
                        if let albumID = library.albumID(for: t) { ui.navigate(.group(.album, albumID)) }
                    } label: {
                        infoLine(TagCleaner.nowPlaying(t.displayAlbum), icon: titleIcons ? "square.stack" : nil, font: .callout,
                                 color: Color.secondary.opacity(0.8), lines: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    @ViewBuilder
    private func infoLine(_ text: String, icon: String? = nil, font: Font, color: Color, lines: Int) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.caption).foregroundStyle(.secondary) }
            if marquee {
                MarqueeText(text: text, font: font, color: color, centered: centered)
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .lineLimit(lines)
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            Menu {
                Picker("Ripetizione", selection: $player.repeatMode) {
                    ForEach(RepeatMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            } label: {
                Image(systemName: player.repeatMode.icon)
                    .font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            if showSeekButtons {
                Button { player.seekBackward() } label: {
                    Image(systemName: "gobackward").font(.title3).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            HoldToSeekButton(tap: { player.previous() }, step: -5) {
                TransportIcon(glyph: .previous, size: 26).frame(maxWidth: .infinity, minHeight: 56)
            }
            Button { player.togglePlayPause() } label: {
                TransportIcon(glyph: player.isPlaying ? .pause : .play, size: 44)
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
            HoldToSeekButton(tap: { player.next() }, step: 5) {
                TransportIcon(glyph: .next, size: 26).frame(maxWidth: .infinity, minHeight: 56)
            }
            if showSeekButtons {
                Button { player.seekForward() } label: {
                    Image(systemName: "goforward").font(.title3).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(player.activeQueue?.isShuffled == true ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    /// Scorciatoie "accesso rapido" sotto i comandi (scelte in Impostazioni › Opzioni e menù).
    private func secondaryControls(wide: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.quickOrder.filter { quickItems.csvContains($0) }, id: \.self) { id in
                quickButton(id)
            }
            if player.abRepeat.a != nil && !quickItems.csvContains("ab") {
                controlButton(icon: "repeat", label: player.abRepeat.isActive ? "A-B" : "A…", active: true) { player.clearAB() }
            }
        }
    }

    static let quickOrder = ["lyrics", "favorite", "equalizer", "sleepTimer", "speed", "bookmarks", "ab", "info",
                             "crossfade", "replayGain", "addToPlaylist", "share", "search"]

    @ViewBuilder
    private func quickButton(_ id: String) -> some View {
        switch id {
        case "lyrics":
            controlButton(icon: showLyricsInline ? "quote.bubble.fill" : "quote.bubble", label: "Testo", active: showLyricsInline) {
                withAnimation { showLyricsInline.toggle() }
            }
        case "favorite":
            if let t = player.currentTrack {
                controlButton(icon: userData.isFavorite(t.id) ? "heart.fill" : "heart", label: "Preferito",
                              active: userData.isFavorite(t.id)) { userData.toggleFavorite(t.id) }
            }
        case "equalizer":
            controlButton(icon: "slider.vertical.3", label: "EQ", active: settings.eqEnabled) { showEqualizer = true }
        case "sleepTimer":
            controlButton(icon: "moon.zzz", label: sleepLabel, active: player.sleepTimer != nil) { sheet = .sleepTimer }
        case "speed":
            controlButton(icon: "speedometer", label: player.effectiveSpeed.formatted(.number.precision(.fractionLength(0...2))) + "x",
                          active: player.effectiveSpeed != 1 || settings.pitch != 0) { sheet = .playback }
        case "bookmarks":
            controlButton(icon: "bookmark", label: "Segnalibri") { sheet = .bookmarks }
        case "ab":
            controlButton(icon: "repeat", label: player.abRepeat.isActive ? "A-B" : (player.abRepeat.a != nil ? "A…" : "A-B"),
                          active: player.abRepeat.a != nil) {
                if player.abRepeat.a == nil { player.setABPointA() } else if !player.abRepeat.isActive { player.setABPointB() } else { player.clearAB() }
            }
        case "info":
            controlButton(icon: "info.circle", label: "Info") { sheet = .info }
        case "crossfade":
            controlButton(icon: "arrow.left.and.right", label: "Crossfade", active: settings.crossfadeDuration > 0) {
                ui.showAudioQuick = .crossfade
            }
        case "replayGain":
            controlButton(icon: "waveform", label: "RG", active: settings.replayGain != .off) { ui.showAudioQuick = .replayGain }
        case "addToPlaylist":
            controlButton(icon: "text.badge.plus", label: "Playlist") { sheet = .addToPlaylist }
        case "share":
            if let t = player.currentTrack, let url = library.url(for: t) {
                ShareLink(item: url) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up").font(.title3)
                        Text("Condividi").font(.caption2).lineLimit(1)
                    }
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        case "search":
            controlButton(icon: "magnifyingglass", label: "Cerca") { sheet = .search }
        default:
            EmptyView()
        }
    }

    private var sleepLabel: String {
        guard let timer = player.sleepTimer else { return "Timer" }
        switch timer.mode {
        case .at(let date): return formatTime(max(0, date.timeIntervalSinceNow))
        case .afterCurrentSong: return "Fine brano"
        case .afterSongs(let n): return "\(n) brani"
        }
    }

    private func controlButton(icon: String, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2).lineLimit(1)
            }
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var sidePanelView: some View {
        VStack(spacing: 0) {
            Picker("Pannello", selection: $sidePanel) {
                ForEach(SidePanel.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(12)
            switch sidePanel {
            case .lyrics:
                LyricsView(lyrics: lyrics)
            case .bookmarks:
                BookmarksPanel()
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: NowPlayingSheet) -> some View {
        switch which {
        case .equalizer: EqualizerView()
        case .sleepTimer: SleepTimerView()
        case .playback: SpeedPitchSheet()
        case .queue:
            NavigationStack {
                if let id = player.activeQueueID {
                    QueueDetailView(queueID: id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { sheet = nil } }
                        }
                } else {
                    ContentUnavailableView("Nessuna coda", systemImage: "list.number")
                }
            }
        case .bookmarks:
            NavigationStack {
                BookmarksPanel()
                    .navigationTitle("Segnalibri")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { sheet = nil } }
                    }
            }
            .presentationDetents([.medium, .large])
        case .info:
            if let t = player.currentTrack { TrackInfoView(track: t) }
        case .addToPlaylist:
            if let t = player.currentTrack { PlaylistPickerSheet(trackIDs: [t.id]) }
        case .tagEditor:
            if let t = player.currentTrack { TagEditorView(trackIDs: [t.id]) }
        case .search:
            SongSearchSheet(tracks: library.tracks, sourceName: "Ricerca")
        }
    }
}

// MARK: - Barra di avanzamento

struct SeekBar: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var clock: PlaybackClock
    @AppStorage(Prefs.npRemaining) private var showRemaining = false
    @AppStorage(Prefs.npSeekHelpers) private var helpers = true
    @AppStorage(Prefs.npThumbOnly) private var thumbOnly = false
    @State private var dragging = false
    @State private var dragValue: Double = 0
    @State private var undoTime: Double?
    @State private var hideTask: Task<Void, Never>?
    @State private var askGoTo = false
    @State private var goToText = ""

    var body: some View {
        let shown = dragging ? dragValue : clock.time
        let total = max(player.duration, 0.1)
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let x = CGFloat(min(1, max(0, shown / total))) * width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Color.accentColor).frame(width: x, height: 4)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: dragging ? 22 : 16, height: dragging ? 22 : 16)
                        .offset(x: x - (dragging ? 11 : 8))
                }
                .frame(height: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !dragging {
                                // Con "solo il pollice" la barra risponde solo se tocchi vicino alla manopola.
                                if thumbOnly && abs(value.startLocation.x - x) > 28 { return }
                                dragging = true
                                undoTime = clock.time
                            }
                            dragValue = Double(min(max(0, value.location.x), width) / max(width, 1)) * total
                        }
                        .onEnded { _ in
                            guard dragging else { return }
                            player.seek(to: dragValue)
                            dragging = false
                            if helpers { showHelpers() }
                        }
                )
            }
            .frame(height: 32)
            HStack {
                Text(showRemaining ? "-" + formatTime(max(0, player.duration - shown)) : formatTime(shown))
                Spacer()
                if helpers, undoTime != nil, !dragging {
                    HStack(spacing: 16) {
                        Button("Vai a") {
                            goToText = formatTime(clock.time)
                            askGoTo = true
                        }
                        Button("Annulla") {
                            if let t = undoTime { player.seek(to: t) }
                            undoTime = nil
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    Spacer()
                } else if let a = player.abRepeat.a {
                    Text("A \(formatTime(a))" + (player.abRepeat.b.map { "  B \(formatTime($0))" } ?? ""))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                Text(formatTime(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .alert("Vai a", isPresented: $askGoTo) {
            TextField("mm:ss", text: $goToText)
                .keyboardType(.numbersAndPunctuation)
            Button("Vai") {
                if let t = Self.parseTime(goToText) { player.seek(to: t) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Scrivi il punto del brano (es. 1:30)")
        }
    }

    private func showHelpers() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { undoTime = nil }
        }
    }

    /// "1:30" → 90, "1:02:03" → 3723, "45" → 45.
    static func parseTime(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}

/// Tocco = azione normale; tenendo premuto va avanti/indietro nel brano finché non lasci.
struct HoldToSeekButton<Label: View>: View {
    let tap: () -> Void
    let step: Double
    @ViewBuilder let label: () -> Label
    @EnvironmentObject private var player: PlayerController
    @State private var holdTask: Task<Void, Never>?
    @State private var held = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 60, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
                if pressing {
                    held = false
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        while !Task.isCancelled {
                            held = true
                            player.skip(by: step)
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                    }
                } else {
                    holdTask?.cancel()
                    holdTask = nil
                    if !held { tap() }
                    held = false
                }
            })
    }
}

/// Testo su una riga che scorre lentamente quando non ci sta.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var centered = true
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var animate = false

    var body: some View {
        let overflow = textWidth > boxWidth + 1
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background(GeometryReader { g in Color.clear.onAppear { textWidth = g.size.width }.onChange(of: text) { _, _ in textWidth = g.size.width } })
            .offset(x: overflow && animate ? -(textWidth - boxWidth) : 0)
            .frame(maxWidth: .infinity, alignment: overflow ? .leading : (centered ? .center : .leading))
            .background(GeometryReader { g in Color.clear.onAppear { boxWidth = g.size.width }.onChange(of: g.size.width) { _, w in boxWidth = w } })
            .clipped()
            .onAppear { restart() }
            .onChange(of: text) { _, _ in restart() }
    }

    private func restart() {
        animate = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let distance = max(0, textWidth - boxWidth)
            guard distance > 1 else { return }
            withAnimation(.linear(duration: Double(distance) / 30).delay(0).repeatForever(autoreverses: true)) { animate = true }
        }
    }
}

/// Copertina a tutto schermo (tocca per chiudere).
struct FullArtworkView: View {
    let image: UIImage?
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .onTapGesture(perform: close)
    }
}

// MARK: - Testi sincronizzati

struct LyricsView: View {
    let lyrics: Lyrics?
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var clock: PlaybackClock
    @AppStorage(Prefs.lyricsSize) private var size = 0
    @AppStorage(Prefs.lyricsAlign) private var align = 1
    @AppStorage(Prefs.lyricsSerif) private var serif = true

    private var textSize: CGFloat { [20, 26, 32][max(0, min(2, size))] }
    private var design: Font.Design { serif ? .serif : .default }
    private var textAlign: TextAlignment { [TextAlignment.leading, .center, .trailing][max(0, min(2, align))] }
    private var frameAlign: Alignment { [Alignment.leading, .center, .trailing][max(0, min(2, align))] }

    var body: some View {
        if let lyrics, !lyrics.lines.isEmpty {
            if lyrics.synced {
                synced(lyrics)
            } else {
                ScrollView {
                    Text(lyrics.lines.map(\.text).joined(separator: "\n"))
                        .font(.system(size: textSize, design: design))
                        .multilineTextAlignment(textAlign)
                        .frame(maxWidth: .infinity, alignment: frameAlign)
                        .padding(20)
                }
            }
        } else {
            ContentUnavailableView {
                Label("Nessun testo", systemImage: "quote.bubble")
            } description: {
                Text("Metti un file .lrc con lo stesso nome del brano nella sua cartella, oppure incorpora il testo nei tag.")
            }
        }
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        let current = lyrics.currentLineID(at: clock.time)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(lyrics.lines) { line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: textSize, weight: line.id == current ? .bold : .medium, design: design))
                            .foregroundStyle(line.id == current ? Color.primary : Color.secondary.opacity(0.7))
                            .multilineTextAlignment(textAlign)
                            .frame(maxWidth: .infinity, alignment: frameAlign)
                            .id(line.id)
                            .onTapGesture {
                                if let t = line.time { player.seek(to: t) }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 160)
            }
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: .center) }
            }
            .onChange(of: current) { _, new in
                guard let new else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }
}

// MARK: - Segnalibri

struct BookmarksPanel: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var userData: UserDataStore
    @State private var addingAt: Double?
    @State private var note = ""

    var body: some View {
        let marks = player.loadedTrackID.map { userData.bookmarks(for: $0) } ?? []
        List {
            Button {
                note = ""
                addingAt = player.currentTime
            } label: {
                Label("Aggiungi segnalibro qui", systemImage: "bookmark.fill")
            }
            .disabled(player.loadedTrackID == nil)
            ForEach(marks) { mark in
                Button { player.seek(to: mark.time) } label: {
                    HStack {
                        Text(formatTime(mark.time)).font(.body.monospacedDigit()).foregroundStyle(Color.accentColor)
                        Text(mark.note.isEmpty ? "Senza nota" : mark.note).lineLimit(2)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { userData.deleteBookmark(mark.id) } label: { Label("Elimina", systemImage: "trash") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .alert("Nuovo segnalibro", isPresented: Binding(get: { addingAt != nil }, set: { if !$0 { addingAt = nil } })) {
            TextField("Nota (facoltativa)", text: $note)
            Button("Salva") {
                if let t = addingAt, let id = player.loadedTrackID {
                    userData.addBookmark(trackID: id, time: t, note: note)
                }
                addingAt = nil
            }
            Button("Annulla", role: .cancel) { addingAt = nil }
        } message: {
            Text("A \(formatTime(addingAt ?? 0))")
        }
    }
}

/// Sfondo sfocato preso dalla copertina; lo disegna RootView dietro la scheda e la barra in basso.
struct NowPlayingBackdrop: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @AppStorage(Prefs.npBlur) private var blur = 3.0

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if settings.theme == .black { Color.black }
            // Solo se il brano ha una copertina vera: altrimenti lo sfondo resta pieno (bianco).
            // "Sfondo sfocato" 0x = niente sfondo dalla copertina, 3x = il più sfocato.
            if blur > 0, let image = player.nowPlayingImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.6)
                    .blur(radius: 25 * blur)
                    .opacity((settings.theme == .black ? 0.25 : 0.45) * (0.5 + blur / 6))
            }
        }
        .clipped()
        .ignoresSafeArea()
    }
}
