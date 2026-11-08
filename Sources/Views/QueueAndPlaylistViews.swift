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
                .onAppear { proxy.scrollTo(q.index, anchor: .center) }
                .onChange(of: q.index) { _, i in
                    withAnimation { proxy.scrollTo(i, anchor: .center) }
                }
            }
            .navigationTitle(embedded ? "" : q.name)
            .searchable(text: $query, prompt: "Cerca in questa coda")
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
            Button {
                player.playQueueItem(queueID: queueID, index: index)
            } label: {
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                    TrackRow(track: track, isCurrent: isCurrent)
                }
            }
            .buttonStyle(.plain)
            .contextMenu { TrackMenu(tracks: [track], sourceName: q.name) }
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

    var body: some View {
        List {
            NavigationLink(value: Route.favorites) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Preferiti")
                        Text("\(userData.favorites.count) brani").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
            }
            Section("Playlist") {
                if userData.playlists.isEmpty {
                    Text("Nessuna playlist. Creane una con +.").foregroundStyle(.secondary)
                }
                ForEach(userData.playlists) { p in
                    NavigationLink(value: Route.playlist(p.id)) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text("\(p.items.count) brani").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "music.note.list")
                        }
                    }
                    .contextMenu {
                        TrackMenu(tracks: library.tracks(for: p.items), sourceName: p.name, showNavigation: false)
                        Divider()
                        Button(role: .destructive) { userData.deletePlaylist(p.id) } label: { Label("Elimina playlist", systemImage: "trash") }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { userData.playlists[$0].id }
                    for id in ids { userData.deletePlaylist(id) }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Playlist")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newName = ""
                    showNew = true
                } label: { Label("Nuova playlist", systemImage: "plus") }
            }
        }
        .alert("Nuova playlist", isPresented: $showNew) {
            TextField("Nome", text: $newName)
            Button("Crea") { userData.createPlaylist(name: newName) }
            Button("Annulla", role: .cancel) {}
        }
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
                    Button {
                        let playIndex = ids[..<index].filter { library.byID[$0] != nil }.count
                        player.play(available, startAt: playIndex, source: title)
                    } label: {
                        TrackRow(track: track, isCurrent: player.loadedTrackID == id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { TrackMenu(tracks: [track], sourceName: title) }
                } else {
                    Text("Brano non disponibile").foregroundStyle(.secondary)
                }
            }
            .onMove(perform: onMove)
            .onDelete(perform: onDelete)
        }
        .listStyle(.plain)
        .themedBackground()
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
                            TrackMenu(tracks: library.tracks(for: p.items), sourceName: p.name, showNavigation: false)
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
