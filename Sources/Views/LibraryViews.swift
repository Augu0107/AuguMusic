import SwiftUI

// MARK: - Elenco gruppi (cartelle, artisti, generi, compositori)

struct GroupListView: View {
    let kind: GroupKind
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var query = ""

    var body: some View {
        let all = library.groups(of: kind)
        let groups = query.isEmpty ? all : all.filter { $0.name.matchesSearch(query) || $0.subtitle.matchesSearch(query) }
        Group {
            if all.isEmpty {
                LibraryEmptyView()
            } else {
                List(groups) { group in
                    NavigationLink(value: Route.group(kind, group.id)) {
                        GroupRow(group: group)
                    }
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        TrackMenu(tracks: library.tracks(for: group.trackIDs), sourceName: group.name, showNavigation: false)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            player.play(library.tracks(for: group.trackIDs), startAt: 0, source: group.name)
                        } label: {
                            Label("Riproduci", systemImage: "play.fill")
                        }
                        .tint(.accentColor)
                    }
                }
                .listStyle(.plain)
                .themedBackground()
            }
        }
        .navigationTitle(kind.title)
        .searchable(text: $query, prompt: "Cerca in \(kind.title.lowercased())")
        .toolbar {
            if !all.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let tracks = groups.flatMap { library.tracks(for: $0.trackIDs) }
                        player.shuffleAndPlay(tracks, source: kind.title)
                    } label: {
                        Label("Casuale", systemImage: "shuffle")
                    }
                }
            }
        }
    }
}

struct GroupRow: View {
    let group: TrackGroup
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        switch group.kind {
        case .folder:
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).lineLimit(1)
                    Text("\(group.trackIDs.count) brani · \(group.subtitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .album:
            HStack(spacing: 12) {
                ArtworkView(track: library.byID[group.trackIDs.first ?? ""], maxPixel: 132, cornerRadius: 5, mode: .fill)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).lineLimit(1)
                    Text(formatTime(group.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .artist, .albumArtist, .composer, .genre:
            // Come Musicolet: solo il nome e la durata totale.
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).lineLimit(1)
                Text(formatTime(group.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Scheda Artisti (artisti / artisti album / compositori)

struct ArtistsTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @AppStorage("artistsTabMode") private var modeRaw = GroupKind.artist.rawValue
    @State private var showSearch = false

    private let modes: [GroupKind] = [.artist, .albumArtist, .composer]
    private var mode: GroupKind { GroupKind(rawValue: modeRaw) ?? .artist }

    var body: some View {
        let groups = library.groups(of: mode)
        List(groups) { group in
            NavigationLink(value: Route.group(mode, group.id)) {
                GroupRow(group: group)
            }
            .listRowSeparator(.hidden)
            .contextMenu {
                TrackMenu(tracks: library.tracks(for: group.trackIDs), sourceName: group.name, showNavigation: false)
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .overlay {
            if groups.isEmpty { LibraryEmptyView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(modes, id: \.self) { kind in
                        let selected = kind == mode
                        let title = kind == .artist ? "Artisti" : kind == .albumArtist ? "Artisti album" : "Compositori"
                        Button { modeRaw = kind.rawValue } label: {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selected ? Color.white : Color.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selected ? Color.accentColor : Color(uiColor: .systemBackground),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selected ? Color.accentColor : Color(uiColor: .systemGray4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
                SearchFieldButton(prompt: "Cerca \(mode == .artist ? "artisti" : mode == .albumArtist ? "artisti album" : "compositori")") {
                    showSearch = true
                }
            }
        }
        .sheet(isPresented: $showSearch) { GroupSearchSheet(kind: mode) }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    player.shuffleAndPlay(groups.flatMap { library.tracks(for: $0.trackIDs) }, source: mode.title)
                } label: {
                    Label("Casuale", systemImage: "shuffle")
                }
                .disabled(groups.isEmpty)
            }
        }
    }
}

// MARK: - Griglia album

struct AlbumGridView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var showSearch = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)]

    var body: some View {
        let all = library.groups(of: .album)
        let albums = all
        Group {
            if all.isEmpty {
                LibraryEmptyView()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                        ForEach(albums) { album in
                            NavigationLink(value: Route.group(.album, album.id)) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                TrackMenu(tracks: library.tracks(for: album.trackIDs), sourceName: album.name, showNavigation: false)
                            }
                        }
                    }
                    .padding(14)
                }
                .themedBackground()
                .safeAreaInset(edge: .top, spacing: 0) {
                    SearchFieldButton(prompt: "Cerca album") { showSearch = true }
                }
            }
        }
        .sheet(isPresented: $showSearch) { GroupSearchSheet(kind: .album) }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Rettangolo verticale bianco con bordino grigio: copertina quadrata e sotto il titolo (come Musicolet).
struct AlbumCard: View {
    let album: TrackGroup
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(track: library.byID[album.trackIDs.first ?? ""], maxPixel: 460, cornerRadius: 0, mode: .fill)
            Text(album.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(uiColor: .systemGray4), lineWidth: 1))
    }
}

/// Sembra una barra di ricerca larga quanto lo schermo; toccandola si apre il pannello di ricerca.
struct SearchFieldButton: View {
    let prompt: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(prompt)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Pannello di ricerca di Artisti/Album: campo di testo in alto e risultati sotto, separati da lineette.
struct GroupSearchSheet: View {
    let kind: GroupKind
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let all = library.groups(of: kind)
        let results = query.isEmpty ? all : all.filter { $0.name.matchesSearch(query) }
        NavigationStack {
            List(results) { group in
                Button {
                    dismiss()
                    let route = Route.group(kind, group.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ui.navigate(route) }
                } label: {
                    HStack(spacing: 12) {
                        if kind == .album {
                            ArtworkView(track: library.byID[group.trackIDs.first ?? ""], maxPixel: 90, cornerRadius: 3, mode: .fill)
                                .frame(width: 30, height: 30)
                        }
                        Text(group.name).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                WideSearchField(text: $query, prompt: kind == .album ? "Cerca album" : "Cerca \(kind.title.lowercased())",
                                autoFocus: true)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
            }
        }
    }
}

/// Barra di ricerca larga quanto tutto lo schermo.
struct WideSearchField: View {
    @Binding var text: String
    let prompt: String
    var autoFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onAppear {
                    if autoFocus {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
                    }
                }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Tutti i brani

struct AllSongsView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        if library.tracks.isEmpty {
            LibraryEmptyView().navigationTitle("Brani")
        } else {
            TrackListScreen(title: "Brani", subtitle: nil, tracks: library.tracks, initialSort: .title)
        }
    }
}

// MARK: - Elenco brani generico

enum TrackSort: String, CaseIterable, Identifiable {
    case original, title, artist, album, fileName, duration, year, dateAdded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: "Predefinito"
        case .title: "Titolo"
        case .artist: "Artista"
        case .album: "Album"
        case .fileName: "Nome file"
        case .duration: "Durata"
        case .year: "Anno"
        case .dateAdded: "Data di aggiunta"
        }
    }

    func apply(_ tracks: [Track]) -> [Track] {
        switch self {
        case .original: return tracks
        case .title: return tracks.sorted { $0.displayTitle.localizedLess($1.displayTitle) }
        case .artist: return tracks.sorted {
            $0.displayArtist == $1.displayArtist ? LibraryStore.albumOrder($0, $1) : $0.displayArtist.localizedLess($1.displayArtist)
        }
        case .album: return tracks.sorted {
            $0.displayAlbum == $1.displayAlbum ? LibraryStore.albumOrder($0, $1) : $0.displayAlbum.localizedLess($1.displayAlbum)
        }
        case .fileName: return tracks.sorted { $0.fileName.localizedLess($1.fileName) }
        case .duration: return tracks.sorted { $0.duration < $1.duration }
        case .year: return tracks.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .dateAdded: return tracks.sorted { $0.dateAdded > $1.dateAdded }
        }
    }
}

struct TrackListScreen: View {
    let title: String
    var subtitle: String?
    let tracks: [Track]
    var headerTrackID: String? = nil
    var year: Int? = nil
    var initialSort: TrackSort = .original

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState
    @State private var sort: TrackSort?
    @State private var descending = false
    @State private var query = ""

    private var displayed: [Track] {
        var list = (sort ?? initialSort).apply(tracks)
        if descending { list.reverse() }
        if !query.isEmpty {
            list = list.filter {
                $0.displayTitle.matchesSearch(query) || $0.displayArtist.matchesSearch(query) || $0.displayAlbum.matchesSearch(query)
            }
        }
        return list
    }

    var body: some View {
        let list = displayed
        let totalDuration = tracks.reduce(0) { $0 + $1.duration }
        List {
            if let headerTrackID, query.isEmpty {
                HStack(alignment: .bottom, spacing: 18) {
                    ArtworkView(track: library.byID[headerTrackID], maxPixel: 500, cornerRadius: 12, mode: .natural)
                        .frame(maxWidth: 190, maxHeight: 240, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title2.bold()).lineLimit(3)
                        if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
                        Text([year.map { String($0) }, "\(tracks.count) brani", formatTime(totalDuration)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
            }

            HStack(spacing: 12) {
                Button {
                    player.play(list, startAt: 0, source: title)
                } label: {
                    Label("Riproduci", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    player.shuffleAndPlay(list, source: title)
                } label: {
                    Label("Casuale", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .listRowSeparator(.hidden)
            .disabled(list.isEmpty)

            ForEach(Array(list.enumerated()), id: \.offset) { index, track in
                TrackListRow(track: track,
                             isCurrent: player.loadedTrackID == track.id,
                             showArtwork: headerTrackID == nil,
                             leadingNumber: headerTrackID != nil ? track.trackNumber : nil,
                             sourceName: title) {
                    player.play(list, startAt: index, source: title)
                }
                .swipeActions(edge: .leading) {
                    Button { player.playNext([track]) } label: { Label("Dopo", systemImage: "text.insert") }
                        .tint(.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button { player.addToQueue([track]) } label: { Label("In coda", systemImage: "text.append") }
                        .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .selectionScope(list)
        .navigationTitle(headerTrackID == nil ? title : "")
        .navigationBarTitleDisplayMode(headerTrackID == nil ? .large : .inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca in questo elenco")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Ordina per", selection: Binding(get: { sort ?? initialSort }, set: { sort = $0 })) {
                        ForEach(TrackSort.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Ordine inverso", isOn: $descending)
                    Divider()
                    TrackMenu(tracks: list, sourceName: title, showNavigation: false)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

// MARK: - Ricerca globale

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var query = ""

    private func searchSongs(_ q: String) -> [Track] {
        guard !q.isEmpty else { return [] }
        return library.tracks.filter {
            $0.displayTitle.matchesSearch(q) || $0.displayArtist.matchesSearch(q) || $0.displayAlbum.matchesSearch(q) || $0.fileName.matchesSearch(q)
        }
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let songs = searchSongs(q)
        List {
            ForEach(Array(songs.prefix(500).enumerated()), id: \.offset) { index, track in
                TrackListRow(track: track, isCurrent: player.loadedTrackID == track.id,
                             sourceName: "Ricerca: \(q)") {
                    player.play(songs, startAt: index, source: "Ricerca: \(q)")
                }
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .selectionScope(songs)
        .safeAreaInset(edge: .top, spacing: 0) {
            WideSearchField(text: $query, prompt: "Cerca tra tutti i brani", autoFocus: true)
        }
        .navigationTitle(q.isEmpty ? "Cerca brani" : "\(songs.count) brani")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if q.isEmpty {
                ContentUnavailableView("Cerca brani", systemImage: "magnifyingglass",
                                       description: Text("Per titolo, artista, album o nome del file."))
            } else if songs.isEmpty {
                ContentUnavailableView.search(text: q)
            }
        }
    }
}
