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
        HStack(spacing: 12) {
            if group.kind == .folder {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
            } else {
                ArtworkView(track: library.byID[group.trackIDs.first ?? ""], maxPixel: 132,
                            cornerRadius: group.kind == .artist || group.kind == .albumArtist ? 22 : 5)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).lineLimit(1)
                Text(group.kind == .folder ? "\(group.trackIDs.count) brani · \(group.subtitle)" : group.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Griglia album

struct AlbumGridView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 18)]

    var body: some View {
        let all = library.groups(of: .album)
        let albums = query.isEmpty ? all : all.filter { $0.name.matchesSearch(query) || $0.subtitle.matchesSearch(query) }
        Group {
            if all.isEmpty {
                LibraryEmptyView()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(albums) { album in
                            NavigationLink(value: Route.group(.album, album.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(track: library.byID[album.trackIDs.first ?? ""], maxPixel: 460, cornerRadius: 10)
                                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                                    Text(album.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(album.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                TrackMenu(tracks: library.tracks(for: album.trackIDs), sourceName: album.name, showNavigation: false)
                            }
                        }
                    }
                    .padding()
                }
                .themedBackground()
            }
        }
        .navigationTitle("Album")
        .searchable(text: $query, prompt: "Cerca album")
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
                    ArtworkView(track: library.byID[headerTrackID], maxPixel: 500, cornerRadius: 12)
                        .frame(width: 170, height: 170)
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
                Button {
                    player.play(list, startAt: index, source: title)
                } label: {
                    TrackRow(track: track,
                             isCurrent: player.loadedTrackID == track.id,
                             showArtwork: headerTrackID == nil,
                             leadingNumber: headerTrackID != nil ? track.trackNumber : nil)
                }
                .buttonStyle(.plain)
                .contextMenu { TrackMenu(tracks: [track], sourceName: title) }
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
        .navigationTitle(headerTrackID == nil ? title : "")
        .navigationBarTitleDisplayMode(headerTrackID == nil ? .large : .inline)
        .searchable(text: $query, prompt: "Cerca in questo elenco")
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

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        List {
            if !q.isEmpty {
                let songs = Array(library.tracks.filter {
                    $0.displayTitle.matchesSearch(q) || $0.displayArtist.matchesSearch(q) || $0.displayAlbum.matchesSearch(q) || $0.fileName.matchesSearch(q)
                }.prefix(200))
                if !songs.isEmpty {
                    Section("Brani (\(songs.count))") {
                        ForEach(Array(songs.prefix(30).enumerated()), id: \.offset) { index, track in
                            Button {
                                player.play(songs, startAt: index, source: "Ricerca: \(q)")
                            } label: {
                                TrackRow(track: track, isCurrent: player.loadedTrackID == track.id)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { TrackMenu(tracks: [track], sourceName: "Ricerca: \(q)") }
                        }
                    }
                }
                ForEach([GroupKind.album, .artist, .albumArtist, .folder, .genre, .composer], id: \.self) { kind in
                    let matches = library.groups(of: kind).filter { $0.name.matchesSearch(q) }.prefix(15)
                    if !matches.isEmpty {
                        Section(kind.title) {
                            ForEach(Array(matches)) { group in
                                NavigationLink(value: Route.group(kind, group.id)) { GroupRow(group: group) }
                            }
                        }
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Cerca")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Brani, album, artisti, cartelle")
        .overlay {
            if q.isEmpty {
                ContentUnavailableView("Cerca nella libreria", systemImage: "magnifyingglass",
                                       description: Text("Titoli, artisti, album, cartelle, generi e compositori."))
            }
        }
    }
}
