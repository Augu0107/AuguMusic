import SwiftUI

enum NowPlayingSheet: String, Identifiable {
    case equalizer, sleepTimer, playback, queue, bookmarks, info, addToPlaylist, tagEditor
    var id: String { rawValue }
}

enum SidePanel: String, CaseIterable, Identifiable {
    case queue, lyrics, bookmarks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .queue: "Coda"
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

    @AppStorage("nowPlayingSidePanel") private var sidePanel: SidePanel = .queue
    @State private var showLyricsInline = false
    @State private var lyrics: Lyrics?
    @State private var sheet: NowPlayingSheet?
    @State private var artistChoices: [String] = []

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width > 700
            ZStack {
                background
                VStack(spacing: 0) {
                    topBar
                    if wide {
                        HStack(alignment: .top, spacing: 28) {
                            playerPanel(wide: true)
                                .frame(maxWidth: min(geo.size.width * 0.44, 520))
                            sidePanelView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .padding(.horizontal, 28)
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
        .overlay { ToastOverlay() }
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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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

    private var background: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if settings.theme == .black { Color.black }
            ArtworkView(track: player.currentTrack, maxPixel: 300, cornerRadius: 0, mode: .fill)
                .scaleEffect(1.6)
                .blur(radius: 70)
                .opacity(settings.theme == .black ? 0.25 : 0.45)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
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
            moreMenu
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var moreMenu: some View {
        Menu {
            if let t = player.currentTrack {
                Button { sheet = .info } label: { Label("Informazioni", systemImage: "info.circle") }
                Button { sheet = .addToPlaylist } label: { Label("Aggiungi a playlist…", systemImage: "music.note.list") }
                Button { sheet = .tagEditor } label: { Label("Modifica tag…", systemImage: "tag") }
                if let albumID = library.albumID(for: t) {
                    Button { ui.navigate(.group(.album, albumID)) } label: { Label("Vai all'album", systemImage: "square.stack") }
                }
                Button { openArtist(t) } label: {
                    Label("Vai all'artista", systemImage: "music.mic")
                }
                Button { ui.navigate(.group(.folder, library.folderID(for: t))) } label: {
                    Label("Vai alla cartella", systemImage: "folder")
                }
            }
            Divider()
            Button { player.skip(by: -10) } label: { Label("Indietro di 10 s", systemImage: "gobackward.10") }
            Button { player.skip(by: 10) } label: { Label("Avanti di 10 s", systemImage: "goforward.10") }
            Divider()
            Menu {
                Button { player.setABPointA() } label: { Label("Imposta punto A", systemImage: "a.circle") }
                Button { player.setABPointB() } label: { Label("Imposta punto B", systemImage: "b.circle") }
                if player.abRepeat.a != nil {
                    Button(role: .destructive) { player.clearAB() } label: { Label("Disattiva A-B", systemImage: "xmark") }
                }
            } label: { Label("Ripetizione A-B", systemImage: "repeat") }
            if let qi = player.activeQueue, qi.isShuffled {
                Button { player.reshuffle() } label: { Label("Rimescola la coda", systemImage: "arrow.triangle.2.circlepath") }
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
            Group {
                if !wide && showLyricsInline {
                    LyricsView(lyrics: lyrics)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ArtworkView(track: player.currentTrack, maxPixel: 1000, cornerRadius: 16, mode: .natural)
                        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onTapGesture {
                if !wide { withAnimation(.easeInOut(duration: 0.25)) { showLyricsInline.toggle() } }
            }
            .layoutPriority(1)

            titleBlock
            SeekBar()
            transportControls
            secondaryControls(wide: wide)
            Spacer(minLength: 4)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.displayTitle ?? "Niente in riproduzione")
                    .font(.title2.bold())
                    .lineLimit(2)
                if let t = player.currentTrack {
                    HStack(spacing: 6) {
                        Button { openArtist(t) } label: {
                            Text(t.displayArtist).lineLimit(1)
                        }
                        Text("—")
                        Button {
                            if let albumID = library.albumID(for: t) { ui.navigate(.group(.album, albumID)) }
                        } label: {
                            Text(t.displayAlbum).lineLimit(1)
                        }
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            if let t = player.currentTrack {
                Button { userData.toggleFavorite(t.id) } label: {
                    Image(systemName: userData.isFavorite(t.id) ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(userData.isFavorite(t.id) ? Color.pink : Color.secondary)
                }
                .buttonStyle(.plain)
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
            Button { player.previous() } label: {
                TransportIcon(glyph: .previous, size: 26).frame(maxWidth: .infinity, minHeight: 56)
            }
            Button { player.togglePlayPause() } label: {
                TransportIcon(glyph: player.isPlaying ? .pause : .play, size: 44)
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
            Button { player.next() } label: {
                TransportIcon(glyph: .next, size: 26).frame(maxWidth: .infinity, minHeight: 56)
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

    private func secondaryControls(wide: Bool) -> some View {
        HStack(spacing: 0) {
            if !wide {
                controlButton(icon: "list.bullet", label: "Coda") { sheet = .queue }
                controlButton(icon: showLyricsInline ? "quote.bubble.fill" : "quote.bubble", label: "Testo",
                              active: showLyricsInline) {
                    withAnimation { showLyricsInline.toggle() }
                }
            }
            controlButton(icon: "slider.vertical.3", label: "EQ", active: settings.eqEnabled) { sheet = .equalizer }
            controlButton(icon: "moon.zzz", label: sleepLabel, active: player.sleepTimer != nil) { sheet = .sleepTimer }
            controlButton(icon: "speedometer", label: settings.speed.formatted(.number.precision(.fractionLength(0...2))) + "x",
                          active: settings.speed != 1 || settings.pitch != 0) { sheet = .playback }
            if !wide {
                controlButton(icon: "bookmark", label: "Segnalibri") { sheet = .bookmarks }
            }
            if player.abRepeat.a != nil {
                controlButton(icon: "repeat", label: player.abRepeat.isActive ? "A-B" : "A…", active: true) { player.clearAB() }
            }
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
            case .queue:
                if let id = player.activeQueueID {
                    QueueDetailView(queueID: id, embedded: true)
                        .scrollContentBackground(.hidden)
                } else {
                    ContentUnavailableView("Nessuna coda", systemImage: "list.number")
                }
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
        case .playback: PlaybackSettingsView()
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
        }
    }
}

// MARK: - Barra di avanzamento

struct SeekBar: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var clock: PlaybackClock
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        let shown = dragging ? dragValue : clock.time
        VStack(spacing: 4) {
            Slider(value: Binding(get: { shown }, set: { dragValue = $0 }),
                   in: 0...max(player.duration, 0.1),
                   onEditingChanged: { editing in
                       if editing {
                           dragValue = clock.time
                           dragging = true
                       } else {
                           player.seek(to: dragValue)
                           dragging = false
                       }
                   })
            HStack {
                Text(formatTime(shown))
                Spacer()
                if let a = player.abRepeat.a {
                    Text("A \(formatTime(a))" + (player.abRepeat.b.map { "  B \(formatTime($0))" } ?? ""))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                Text("-" + formatTime(max(0, player.duration - shown)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Testi sincronizzati

struct LyricsView: View {
    let lyrics: Lyrics?
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var clock: PlaybackClock

    var body: some View {
        if let lyrics, !lyrics.lines.isEmpty {
            if lyrics.synced {
                synced(lyrics)
            } else {
                ScrollView {
                    Text(lyrics.lines.map(\.text).joined(separator: "\n"))
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(lyrics.lines) { line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.title3.weight(line.id == current ? .bold : .medium))
                            .foregroundStyle(line.id == current ? Color.primary : Color.secondary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
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
