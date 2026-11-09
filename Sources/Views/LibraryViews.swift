import SwiftUI

// MARK: - Elenco gruppi (cartelle, artisti, generi, compositori)

struct GroupListView: View {
    let kind: GroupKind

    static func menuKey(_ kind: GroupKind) -> String {
        switch kind {
        case .folder: Prefs.menuFolder
        case .album: Prefs.menuAlbum
        case .genre: Prefs.menuGenre
        case .artist, .albumArtist, .composer: Prefs.menuArtist
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var query = ""
    @AppStorage(Prefs.foldersSearch) private var foldersSearch = true
    @AppStorage(Prefs.genresSearch) private var genresSearch = true
    @AppStorage(Prefs.artistsSearch) private var artistsSearch = true

    private var searchEnabled: Bool {
        switch kind {
        case .folder: foldersSearch
        case .genre: genresSearch
        default: artistsSearch
        }
    }

    @AppStorage(Prefs.foldersHierarchical) private var hierarchical = false

    var body: some View {
        if kind == .folder && hierarchical {
            FolderTreeView(folderID: nil, path: "")
        } else {
            flatList
        }
    }

    @ViewBuilder
    private var flatList: some View {
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
                        TrackMenu(tracks: library.tracks(for: group.trackIDs), sourceName: group.name, showNavigation: false,
                                  menuKey: Self.menuKey(kind))
                        if kind == .folder { FolderExtraActions(group: group) }
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
        .modifier(OptionalSearch(enabled: searchEnabled, query: $query, prompt: "Cerca in \(kind.title.lowercased())"))
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
    @AppStorage(Prefs.foldersInfo) private var foldersInfo = "duration"
    @AppStorage(Prefs.albumsInfo) private var albumsInfo = "auto"
    @AppStorage(Prefs.artistsInfo) private var artistsInfo = "duration"
    @AppStorage(Prefs.genresInfo) private var genresInfo = "auto"

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
                    Text([GroupInfo.text(group, foldersInfo == "auto" ? "count" : foldersInfo, library: library), group.subtitle]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
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
                    if let info = GroupInfo.text(group, albumsInfo, library: library) {
                        Text(info)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        case .artist, .albumArtist, .composer, .genre:
            // Come Musicolet: il nome e sotto l'informazione scelta (di solito la durata totale).
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).lineLimit(1)
                if let info = GroupInfo.text(group, group.kind == .genre ? genresInfo : artistsInfo, library: library) {
                    Text(info)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Testo dell'informazione extra scelta in Impostazioni › Interfaccia (durata, numero di brani...).
enum GroupInfo {
    @MainActor
    static func text(_ group: TrackGroup, _ info: String, library: LibraryStore) -> String? {
        switch info {
        case "none":
            return nil
        case "count":
            return group.trackIDs.count == 1 ? "1 brano" : "\(group.trackIDs.count) brani"
        case "date":
            let latest = library.tracks(for: group.trackIDs).map(\.modified).max()
            return latest.map { $0.formatted(date: .abbreviated, time: .omitted) }
        case "year":
            return group.year.map { String($0) } ?? ""
        case "artist", "albumArtist", "composer":
            let tracks = library.tracks(for: group.trackIDs)
            let names: [String] = tracks.map { t in
                info == "artist" ? t.artist : (info == "albumArtist" ? t.albumArtist : t.composer)
            }
            return names.first { !$0.isEmpty } ?? ""
        default: // "duration" e "auto"
            return formatTime(group.duration)
        }
    }
}

/// Voci per una cartella: rinomina ed escludi dalla scansione.
struct FolderExtraActions: View {
    let group: TrackGroup
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState
    @AppStorage(Prefs.menuFolder) private var enabled = ""
    @AppStorage(Prefs.excludedFolders) private var excluded = ""

    var body: some View {
        if enabled.csvContains("rename") {
            Button { ui.renameFolder = group } label: { Label("Rinomina la cartella", systemImage: "pencil") }
        }
        if enabled.csvContains("exclude") {
            Button(role: .destructive) {
                excluded = ExcludedFolders.adding(group.id, to: excluded)
                ui.showToast("Cartella esclusa. La riattivi da Impostazioni.")
                Task { await library.rescan() }
            } label: { Label("Escludi questa cartella dalla scansione", systemImage: "folder.badge.minus") }
        }
    }
}

// MARK: - Cartelle gerarchiche

/// "Struttura Menù Cartelle: Gerarchico": cartelle dentro cartelle, con i brani della cartella sotto.
struct FolderTreeView: View {
    let folderID: UUID?
    let path: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController

    private struct Node: Identifiable {
        let id: String
        let name: String
        let folderID: UUID
        let path: String
        let count: Int
    }

    var body: some View {
        let groups = library.groups(of: .folder)
        let roots = Set(groups.compactMap { UUID(uuidString: String($0.id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")) })
        if folderID == nil && roots.count == 1, let only = roots.first {
            FolderTreeView(folderID: only, path: "")
        } else {
            let nodes = children(groups: groups, roots: roots)
            let tracks: [Track] = folderID.map { id in
                library.group(.folder, id: id.uuidString + "|" + path).map { library.tracks(for: $0.trackIDs) } ?? []
            } ?? []
            List {
                ForEach(nodes) { node in
                    NavigationLink {
                        FolderTreeView(folderID: node.folderID, path: node.path)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name).lineLimit(1)
                                Text(node.count == 1 ? "1 brano" : "\(node.count) brani")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    TrackListRow(track: track, isCurrent: player.loadedTrackID == track.id, sourceName: title) {
                        player.play(tracks, startAt: index, source: title)
                    }
                }
            }
            .listStyle(.plain)
            .themedBackground()
            .selectionScope(tracks)
            .overlay { if groups.isEmpty { LibraryEmptyView() } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        guard let folderID else { return "Cartelle" }
        return path.isEmpty ? library.folderName(folderID) : (path as NSString).lastPathComponent
    }

    private func children(groups: [TrackGroup], roots: Set<UUID>) -> [Node] {
        guard let folderID else {
            return roots.map { id in
                let count = groups.filter { $0.id.hasPrefix(id.uuidString + "|") }.reduce(0) { $0 + $1.trackIDs.count }
                return Node(id: id.uuidString, name: library.folderName(id), folderID: id, path: "", count: count)
            }
            .sorted { $0.name.localizedLess($1.name) }
        }
        let prefix = folderID.uuidString + "|"
        var counts: [String: Int] = [:]
        for g in groups where g.id.hasPrefix(prefix) {
            let dir = String(g.id.dropFirst(prefix.count))
            let rest: Substring
            if path.isEmpty {
                guard !dir.isEmpty else { continue }
                rest = Substring(dir)
            } else {
                guard dir.hasPrefix(path + "/") else { continue }
                rest = dir.dropFirst(path.count + 1)
            }
            guard let first = rest.split(separator: "/").first else { continue }
            counts[String(first), default: 0] += g.trackIDs.count
        }
        return counts.map { name, count in
            let childPath = path.isEmpty ? name : path + "/" + name
            return Node(id: childPath, name: name, folderID: folderID, path: childPath, count: count)
        }
        .sorted { $0.name.localizedLess($1.name) }
    }
}

// MARK: - Scheda Artisti (artisti / artisti album / compositori)

struct ArtistsTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @AppStorage("artistsTabMode") private var modeRaw = GroupKind.artist.rawValue
    @AppStorage(Prefs.artistsSearch) private var searchEnabled = true
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
                TrackMenu(tracks: library.tracks(for: group.trackIDs), sourceName: group.name, showNavigation: false,
                          menuKey: Prefs.menuArtist)
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .overlay {
            if groups.isEmpty { LibraryEmptyView() }
        }
        .pinnedTop {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(modes, id: \.self) { kind in
                        let selected = kind == mode
                        let title = kind == .artist ? "Artisti" : kind == .albumArtist ? "Artisti album" : "Compositori"
                        Button { modeRaw = kind.rawValue } label: {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(selected ? Color.accentColor : Color(uiColor: .systemGray4), lineWidth: selected ? 1.5 : 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
                if searchEnabled {
                    SearchFieldButton(prompt: "Cerca \(mode == .artist ? "artisti" : mode == .albumArtist ? "artisti album" : "compositori")") {
                        showSearch = true
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) { GroupSearchSheet(kind: mode) }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Griglia album

struct AlbumGridView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @AppStorage(Prefs.albumsView) private var viewMode = "grid"
    @AppStorage(Prefs.albumsGridSize) private var gridSize = 2
    @AppStorage(Prefs.albumsSearch) private var searchEnabled = true
    @State private var showSearch = false

    private var columns: [GridItem] {
        let minimum: CGFloat = [90, 120, 150, 200, 260][max(0, min(4, gridSize))]
        return [GridItem(.adaptive(minimum: minimum, maximum: minimum * 1.45), spacing: 14)]
    }

    var body: some View {
        let albums = library.groups(of: .album)
        Group {
            if albums.isEmpty {
                LibraryEmptyView()
            } else if viewMode == "grid" {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                        ForEach(albums) { album in
                            NavigationLink(value: Route.group(.album, album.id)) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { albumMenu(album) }
                        }
                    }
                    .padding(14)
                }
                .themedBackground()
            } else {
                List(albums) { album in
                    NavigationLink(value: Route.group(.album, album.id)) {
                        if viewMode == "listArt" {
                            GroupRow(group: album)
                        } else {
                            AlbumPlainRow(album: album)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .contextMenu { albumMenu(album) }
                }
                .listStyle(.plain)
                .themedBackground()
            }
        }
        .pinnedTop {
            if searchEnabled && !albums.isEmpty {
                SearchFieldButton(prompt: "Cerca album") { showSearch = true }
            }
        }
        .sheet(isPresented: $showSearch) { GroupSearchSheet(kind: .album) }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func albumMenu(_ album: TrackGroup) -> some View {
        TrackMenu(tracks: library.tracks(for: album.trackIDs), sourceName: album.name, showNavigation: false, menuKey: Prefs.menuAlbum)
    }
}

/// Riga album senza copertina ("Elenco senza copertine").
struct AlbumPlainRow: View {
    let album: TrackGroup
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(Prefs.albumsInfo) private var info = "auto"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(album.name).lineLimit(1)
            if let text = GroupInfo.text(album, info, library: library) {
                Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
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
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { HairlineSeparator() }
    }
}

/// Linea orizzontale sottile (un Divider qui veniva disegnato in verticale).
struct HairlineSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(maxWidth: .infinity)
            .frame(height: 1 / UIScreen.main.scale)
    }
}

/// Pannello di ricerca di Artisti/Album: campo di testo in alto e risultati sotto, separati da lineette.
/// Si chiude toccando un risultato o toccando l'app fuori dal pannello.
struct GroupSearchSheet: View {
    let kind: GroupKind
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let all = library.groups(of: kind)
        let results = query.isEmpty ? all : all.filter { $0.name.matchesSearch(query) }
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
        .pinnedTop {
            WideSearchField(text: $query, prompt: kind == .album ? "Cerca album" : "Cerca \(kind.title.lowercased())",
                            autoFocus: true)
        }
    }
}

/// Pannello di ricerca dei brani (es. dentro un album): toccando un brano parte da lì.
struct SongSearchSheet: View {
    let tracks: [Track]
    let sourceName: String
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let results = query.isEmpty ? tracks : tracks.filter {
            $0.displayTitle.matchesSearch(query) || $0.displayArtist.matchesSearch(query)
        }
        List(results) { track in
            Button {
                let index = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
                player.play(tracks, startAt: index, source: sourceName)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(track: track, maxPixel: 90, cornerRadius: 3, mode: .fill)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.displayTitle).lineLimit(1)
                        Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .pinnedTop {
            WideSearchField(text: $query, prompt: "Cerca brani", autoFocus: true)
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
        .overlay(alignment: .bottom) { HairlineSeparator() }
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
    /// Dividi in sottocategorie: per gli artisti i loro album, per i generi gli artisti.
    var splitBy: GroupKind? = nil

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ui: UIState
    @State private var sort: TrackSort?
    @State private var descending = false
    @State private var query = ""
    @State private var subgroup: String?
    @AppStorage(Prefs.artistsSplit) private var artistsSplit = true
    @AppStorage(Prefs.genresSplit) private var genresSplit = true
    @AppStorage(Prefs.artistsAlbumSort) private var albumSort = "yearDesc"

    private var splitting: Bool {
        guard let splitBy else { return false }
        return splitBy == .album ? artistsSplit : genresSplit
    }

    private func subKey(_ t: Track) -> String {
        splitBy == .album ? t.displayAlbum : t.displayArtist
    }

    /// Sottocategorie nell'ordine scelto (album: per nome o per anno).
    private var subgroups: [String] {
        var seen = Set<String>()
        var names: [String] = []
        var years: [String: Int] = [:]
        for t in tracks {
            let k = subKey(t)
            if seen.insert(k).inserted { names.append(k) }
            if let y = t.year, y > 0 { years[k] = max(years[k] ?? 0, y) }
        }
        if splitBy == .album {
            switch albumSort {
            case "name": return names.sorted { $0.localizedLess($1) }
            case "yearAsc": return names.sorted { (years[$0] ?? 9999, $0) < (years[$1] ?? 9999, $1) }
            default: return names.sorted { (years[$0] ?? 0, $1) > (years[$1] ?? 0, $0) }
            }
        }
        return names.sorted { $0.localizedLess($1) }
    }

    private var displayed: [Track] {
        var base = tracks
        if splitting, let subgroup { base = base.filter { subKey($0) == subgroup } }
        var list = (sort ?? initialSort).apply(base)
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
                    ArtworkView(track: library.byID[headerTrackID], maxPixel: 500, cornerRadius: 0, mode: .fill)
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

            if splitting && query.isEmpty {
                let subs = subgroups
                if subs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            SubgroupTile(title: splitBy == .album ? "Tutti gli album" : "Tutti gli artisti",
                                         selected: subgroup == nil, dimmed: subgroup != nil) { subgroup = nil }
                            ForEach(subs, id: \.self) { name in
                                SubgroupTile(title: name, selected: subgroup == name, dimmed: subgroup != nil && subgroup != name) {
                                    subgroup = name
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowSeparator(.hidden)
                }
            }

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

/// Riquadro di una sottocategoria (come le tessere dell'album).
struct SubgroupTile: View {
    let title: String
    let selected: Bool
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
            .padding(10)
            .frame(width: 150, height: 70, alignment: .topLeading)
            .background(Color(uiColor: .systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color(uiColor: .systemGray4), lineWidth: selected ? 1.5 : 1))
            .opacity(dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
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
        .overlay {
            if q.isEmpty {
                ContentUnavailableView("Cerca brani", systemImage: "magnifyingglass",
                                       description: Text("Per titolo, artista, album o nome del file."))
            } else if songs.isEmpty {
                ContentUnavailableView.search(text: q)
            }
        }
        .pinnedTop {
            WideSearchField(text: $query, prompt: "Cerca tra tutti i brani", autoFocus: true)
        }
        .navigationTitle(q.isEmpty ? "Cerca brani" : "\(songs.count) brani")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    /// Barra fissa sopra il contenuto, sempre larga quanto lo schermo.
    func pinnedTop<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        VStack(spacing: 0) {
            bar().frame(maxWidth: .infinity)
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Barra fissa sotto il contenuto, sempre larga quanto lo schermo.
    func pinnedBottom<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        VStack(spacing: 0) {
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
            bar().frame(maxWidth: .infinity)
        }
    }
}
