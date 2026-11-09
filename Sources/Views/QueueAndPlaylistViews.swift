import SwiftUI
import UniformTypeIdentifiers

// MARK: - Code multiple

struct QueuesView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var ui: UIState

    @State private var pendingRemoval: UUID?
    @State private var renaming: UUID?
    @State private var newName = ""

    var body: some View {
        List {
            if player.queues.isEmpty {
                ContentUnavailableView("Nessuna coda", systemImage: "list.number",
                                       description: Text("Tocca un brano per creare la prima coda. Puoi averne fino a \(settings.maxQueues)."))
            }
            ForEach(player.queues) { q in
                NavigationLink(value: Route.queue(q.id)) {
                    queueRow(q)
                }
                .contextMenu { menu(for: q) }
                .swipeActions(edge: .leading) {
                    Button { player.switchToQueue(q.id) } label: { Label("Riprendi", systemImage: "play.fill") }
                        .tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { requestRemoval(q.id) } label: { Label("Rimuovi", systemImage: "trash") }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Code (\(player.queues.count)/\(settings.maxQueues))")
        .confirmationDialog("Rimuovere questa coda?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Rimuovi", role: .destructive) {
                if let id = pendingRemoval { player.removeQueue(id) }
                pendingRemoval = nil
            }
        }
        .alert("Rinomina coda", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nome", text: $newName)
            Button("Salva") {
                if let id = renaming { player.renameQueue(id, to: newName) }
                renaming = nil
            }
            Button("Annulla", role: .cancel) { renaming = nil }
        }
    }

    private func queueRow(_ q: PlayQueue) -> some View {
        let isActive = q.id == player.activeQueueID
        let current = q.currentID.flatMap { library.byID[$0] }
        return HStack(spacing: 12) {
            Image(systemName: isActive ? (player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill") : "list.number")
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(q.name).font(.body.weight(isActive ? .semibold : .regular)).lineLimit(1)
                    if q.isShuffled {
                        Image(systemName: "shuffle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("\(q.items.isEmpty ? 0 : q.index + 1)/\(q.items.count) · \(current?.displayTitle ?? "Vuota")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func menu(for q: PlayQueue) -> some View {
        Button { player.switchToQueue(q.id) } label: { Label("Riprendi questa coda", systemImage: "play") }
        Button {
            newName = q.name
            renaming = q.id
        } label: { Label("Rinomina", systemImage: "pencil") }
        Button {
            userData.createPlaylist(name: q.name, items: q.items)
            ui.showToast("Salvata come playlist")
        } label: { Label("Salva come playlist", systemImage: "music.note.list") }
        Button { player.removeOtherQueues(except: q.id) } label: { Label("Rimuovi tutte le altre", systemImage: "rectangle.stack.badge.minus") }
        Button(role: .destructive) { requestRemoval(q.id) } label: { Label("Rimuovi", systemImage: "trash") }
    }

    private func requestRemoval(_ id: UUID) {
        if settings.confirmQueueRemoval { pendingRemoval = id } else { player.removeQueue(id) }
    }
}

struct QueueDetailView: View {
    let queueID: UUID
    var embedded = false

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @AppStorage(Prefs.queueArtwork) private var showArtwork = true
    @AppStorage(Prefs.queueSwipeRemove) private var swipeRemove = true
    @AppStorage(Prefs.queueSearch) private var showSearch = true

    var body: some View {
        if let q = player.queue(queueID) {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(q.items.enumerated()), id: \.offset) { index, id in
                        if query.isEmpty || matches(id) {
                            row(q: q, index: index, id: id)
                                .id(index)
                        }
                    }
                    .onMove { player.moveInQueue(queueID, from: $0, to: $1) }
                    .onDelete { player.removeFromQueue(queueID, at: $0) }
                    .moveDisabled(!query.isEmpty)
                }
                .listStyle(.plain)
                .themedBackground()
                .selectionScope(library.tracks(for: q.items))
                .onAppear { proxy.scrollTo(q.index, anchor: .center) }
                .onChange(of: q.index) { _, i in
                    withAnimation { proxy.scrollTo(i, anchor: .center) }
                }
            }
            .navigationTitle(embedded ? "" : q.name)
            .modifier(OptionalSearch(enabled: showSearch, query: $query, prompt: "Cerca in questa coda"))
            .toolbar {
                if !embedded {
                    ToolbarItemGroup(placement: .primaryAction) {
                        EditButton()
                        Menu {
                            Button { player.switchToQueue(queueID) } label: { Label("Riprendi questa coda", systemImage: "play") }
                            if queueID == player.activeQueueID {
                                Button { player.toggleShuffle() } label: {
                                    Label(q.isShuffled ? "Disattiva casuale" : "Attiva casuale", systemImage: "shuffle")
                                }
                                if q.isShuffled {
                                    Button { player.reshuffle() } label: { Label("Rimescola", systemImage: "arrow.triangle.2.circlepath") }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("Coda rimossa", systemImage: "list.number")
        }
    }

    private func matches(_ id: String) -> Bool {
        guard let t = library.byID[id] else { return false }
        return t.displayTitle.matchesSearch(query) || t.displayArtist.matchesSearch(query) || t.displayAlbum.matchesSearch(query)
    }

    @ViewBuilder
    private func row(q: PlayQueue, index: Int, id: String) -> some View {
        let isCurrent = q.id == player.activeQueueID && index == q.index
        if let track = library.byID[id] {
            TrackListRow(track: track, isCurrent: isCurrent, showArtwork: showArtwork, leadingNumber: index + 1, sourceName: q.name) {
                player.playQueueItem(queueID: queueID, index: index)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if swipeRemove {
                    Button(role: .destructive) { player.removeFromQueue(queueID, at: IndexSet(integer: index)) } label: {
                        Label("Rimuovi", systemImage: "trash")
                    }
                }
            }
        } else {
            Text("Brano non disponibile").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Playlist

struct PlaylistsView: View {
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var showNew = false
    @State private var newName = ""
    @State private var query = ""
    @AppStorage(Prefs.playlistsSearch) private var searchEnabled = true

    private var filteredPlaylists: [Playlist] {
        query.isEmpty ? userData.playlists : userData.playlists.filter { $0.name.matchesSearch(query) }
    }

    var body: some View {
        List {
            row(.allSongs, "Tutti i brani", value: .smart(.allSongs))
            row(.favorites, "Preferiti", value: .favorites)
            row(.recentlyAdded, "Aggiunti di recente", value: .smart(.recentlyAdded))
            row(.recentlyPlayed, "Riprodotti di recente", value: .smart(.recentlyPlayed))
            row(.mostPlayed, "Più riprodotti", value: .smart(.mostPlayed))
            row(.neverPlayed, "Mai riprodotti", value: .smart(.neverPlayed))

            Text("Le tue playlist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 14)
                .listRowSeparator(.hidden)

            ForEach(filteredPlaylists) { p in
                NavigationLink(value: Route.playlist(p.id)) {
                    HStack(spacing: 14) {
                        AppIconView(glyph: .playlist, size: 20)
                            .foregroundStyle(.secondary)
                        Text(p.name)
                        Spacer()
                        Text("\(p.items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
                .contextMenu {
                    TrackMenu(tracks: library.tracks(for: p.items), sourceName: p.name, showNavigation: false, menuKey: Prefs.menuPlaylist)
                    Divider()
                    Button(role: .destructive) { userData.deletePlaylist(p.id) } label: { Label("Elimina playlist", systemImage: "trash") }
                }
            }
            .onDelete { offsets in
                let list = filteredPlaylists
                let ids = offsets.map { list[$0].id }
                for id in ids { userData.deletePlaylist(id) }
            }

            Button {
                newName = ""
                showNew = true
            } label: {
                Label("Nuova playlist", systemImage: "plus")
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .themedBackground()
        .navigationTitle("Playlist")
        .modifier(OptionalSearch(enabled: searchEnabled, query: $query, prompt: "Cerca playlist"))
        .alert("Nuova playlist", isPresented: $showNew) {
            TextField("Nome", text: $newName)
            Button("Crea") { userData.createPlaylist(name: newName) }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func row(_ glyph: AppGlyph, _ title: String, value: Route) -> some View {
        NavigationLink(value: value) {
            HStack(spacing: 14) {
                AppIconView(glyph: glyph, size: 22)
                    .foregroundStyle(.secondary)
                Text(title)
            }
            .padding(.vertical, 2)
        }
        .listRowSeparator(.hidden)
    }
}

/// Playlist automatiche: tutti i brani, aggiunti/riprodotti di recente, più e mai riprodotti.
struct SmartListView: View {
    let list: SmartList
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var userData: UserDataStore

    var body: some View {
        let stats = userData.stats
        let tracks: [Track] = {
            switch list {
            case .allSongs:
                return library.tracks
            case .recentlyAdded:
                return Array(library.tracks.sorted { $0.dateAdded > $1.dateAdded }.prefix(300))
            case .recentlyPlayed:
                return stats.filter { library.byID[$0.key] != nil }
                    .sorted { $0.value.lastPlayed > $1.value.lastPlayed }
                    .prefix(300)
                    .compactMap { library.byID[$0.key] }
            case .mostPlayed:
                return stats.filter { $0.value.count > 0 && library.byID[$0.key] != nil }
                    .sorted { $0.value.count > $1.value.count }
                    .prefix(300)
                    .compactMap { library.byID[$0.key] }
            case .neverPlayed:
                return library.tracks.filter { stats[$0.id] == nil }
            }
        }()
        if tracks.isEmpty {
            ContentUnavailableView(list.title, systemImage: "music.note",
                                   description: Text(list == .recentlyPlayed || list == .mostPlayed
                                                     ? "Gli ascolti si contano dopo metà brano (massimo 30 secondi)."
                                                     : "Nessun brano."))
                .navigationTitle(list.title)
        } else {
            TrackListScreen(title: list.title, subtitle: nil, tracks: tracks,
                            initialSort: list == .allSongs ? .title : .original)
        }
    }
}

/// Scheda Coda: la coda attiva, con il selettore delle code in alto.
/// Casella di ricerca che si può spegnere dalle Impostazioni ("Casella di ricerca rapida").
struct OptionalSearch: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    let prompt: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, prompt: prompt)
        } else {
            content.onAppear { query = "" }
        }
    }
}

struct QueueTabView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @State private var showAllQueues = false
    @State private var confirmRemoveOthers = false
    @AppStorage(Prefs.queueRemoveOthers) private var removeOthers = true

    var body: some View {
        Group {
            if let id = player.activeQueueID {
                QueueDetailView(queueID: id)
            } else {
                ContentUnavailableView("Nessuna coda", systemImage: "music.note.list",
                                       description: Text("Tocca un brano per creare la prima coda."))
                    .navigationTitle("Coda")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(player.queues) { q in
                        Button {
                            player.switchToQueue(q.id, autoplay: false)
                        } label: {
                            if q.id == player.activeQueueID {
                                Label("\(q.name) (\(q.items.count))", systemImage: "checkmark")
                            } else {
                                Text("\(q.name) (\(q.items.count))")
                            }
                        }
                    }
                    Divider()
                    Button { showAllQueues = true } label: { Label("Gestisci le code…", systemImage: "list.number") }
                    if removeOthers && player.queues.count > 1 {
                        Button(role: .destructive) {
                            if settings.confirmQueueRemoval { confirmRemoveOthers = true } else { removeOtherQueues() }
                        } label: {
                            Label("Elimina tutte le code tranne quella in riproduzione", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Code (\(player.queues.count))", systemImage: "rectangle.stack")
                }
            }
        }
        .confirmationDialog("Eliminare tutte le altre code?", isPresented: $confirmRemoveOthers, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { removeOtherQueues() }
        }
        .sheet(isPresented: $showAllQueues) {
            NavigationStack {
                QueuesView()
                    .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Fine") { showAllQueues = false } }
                    }
            }
        }
    }

    private func removeOtherQueues() {
        for q in player.queues where q.id != player.activeQueueID { player.removeQueue(q.id) }
    }
}

/// Elenco modificabile di ID brano (usato da playlist e preferiti).
struct EditableTrackList: View {
    let title: String
    let ids: [String]
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (IndexSet) -> Void

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        let available = ids.compactMap { library.byID[$0] }
        List {
            HStack(spacing: 12) {
                Button { player.play(available, startAt: 0, source: title) } label: {
                    Label("Riproduci", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { player.shuffleAndPlay(available, source: title) } label: {
                    Label("Casuale", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .listRowSeparator(.hidden)
            .disabled(available.isEmpty)

            ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                if let track = library.byID[id] {
                    TrackListRow(track: track, isCurrent: player.loadedTrackID == id, sourceName: title) {
                        let playIndex = ids[..<index].filter { library.byID[$0] != nil }.count
                        player.play(available, startAt: playIndex, source: title)
                    }
                } else {
                    Text("Brano non disponibile").foregroundStyle(.secondary)
                }
            }
            .onMove(perform: onMove)
            .onDelete(perform: onDelete)
        }
        .listStyle(.plain)
        .themedBackground()
        .selectionScope(available)
    }
}

struct PlaylistDetailView: View {
    let playlistID: UUID
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var library: LibraryStore
    @State private var renaming = false
    @State private var newName = ""
    @State private var exportDocument: TextDocument?

    var body: some View {
        if let p = userData.playlists.first(where: { $0.id == playlistID }) {
            EditableTrackList(title: p.name, ids: p.items,
                              onMove: { userData.moveItems(from: $0, to: $1, in: playlistID) },
                              onDelete: { userData.removeItems(at: $0, from: playlistID) })
                .navigationTitle(p.name)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        EditButton()
                        Menu {
                            TrackMenu(tracks: library.tracks(for: p.items), sourceName: p.name, showNavigation: false, menuKey: Prefs.menuPlaylist)
                            Divider()
                            Button {
                                newName = p.name
                                renaming = true
                            } label: { Label("Rinomina", systemImage: "pencil") }
                            Button {
                                exportDocument = TextDocument(text: userData.m3u(for: p.items, library: library))
                            } label: { Label("Esporta M3U…", systemImage: "square.and.arrow.up") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .alert("Rinomina playlist", isPresented: $renaming) {
                    TextField("Nome", text: $newName)
                    Button("Salva") { userData.rename(playlistID: playlistID, to: newName) }
                    Button("Annulla", role: .cancel) {}
                }
                .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                              document: exportDocument,
                              contentType: .m3uPlaylist,
                              defaultFilename: p.name) { _ in exportDocument = nil }
        } else {
            ContentUnavailableView("Playlist eliminata", systemImage: "music.note.list")
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var userData: UserDataStore

    var body: some View {
        EditableTrackList(title: "Preferiti", ids: userData.favorites,
                          onMove: { userData.favorites.move(fromOffsets: $0, toOffset: $1) },
                          onDelete: { userData.favorites.remove(atOffsets: $0) })
            .navigationTitle("Preferiti")
            .toolbar { EditButton() }
    }
}

struct PlaylistPickerSheet: View {
    let trackIDs: [String]
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    newName = ""
                    showNew = true
                } label: { Label("Nuova playlist…", systemImage: "plus") }
                Button {
                    userData.addFavorites(trackIDs)
                    ui.showToast("Aggiunto ai preferiti")
                    dismiss()
                } label: { Label("Preferiti", systemImage: "heart") }
                Section("Playlist") {
                    ForEach(userData.playlists) { p in
                        Button {
                            userData.add(trackIDs, to: p.id)
                            ui.showToast("Aggiunto a \(p.name)")
                            dismiss()
                        } label: {
                            Label(p.name, systemImage: "music.note.list")
                        }
                    }
                }
            }
            .navigationTitle(trackIDs.count == 1 ? "Aggiungi a playlist" : "Aggiungi \(trackIDs.count) brani")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .alert("Nuova playlist", isPresented: $showNew) {
                TextField("Nome", text: $newName)
                Button("Crea") {
                    userData.createPlaylist(name: newName, items: trackIDs)
                    ui.showToast("Playlist creata")
                    dismiss()
                }
                Button("Annulla", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.m3uPlaylist, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
