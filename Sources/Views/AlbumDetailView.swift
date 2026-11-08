import SwiftUI

/// Pagina album come Musicolet: nome, filtro per artisti/artisti album/compositori, riquadri, brani.
struct AlbumDetailView: View {
    let albumID: String

    enum FilterKind: String, CaseIterable, Identifiable {
        case artists, albumArtists, composers
        var id: String { rawValue }
        var label: String {
            switch self {
            case .artists: "Artisti"
            case .albumArtists: "Artisti album"
            case .composers: "Compositori"
            }
        }
        var allLabel: String {
            switch self {
            case .artists: "Tutti gli artisti"
            case .albumArtists: "Tutti gli artisti album"
            case .composers: "Tutti i compositori"
            }
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @State private var filterKind: FilterKind = .artists
    @State private var selectedName: String?
    @State private var query = ""

    private func names(for t: Track) -> [String] {
        switch filterKind {
        case .artists: library.artistNames(for: t)
        case .albumArtists: library.albumArtistNames(for: t)
        case .composers: library.composerNames(for: t)
        }
    }

    var body: some View {
        if let album = library.group(.album, id: albumID) {
            content(album)
        } else {
            ContentUnavailableView("Album non trovato", systemImage: "square.stack")
        }
    }

    private func content(_ album: TrackGroup) -> some View {
        let all = library.tracks(for: album.trackIDs)
        var seen = Set<String>()
        var people: [String] = []
        for t in all {
            for n in names(for: t) where seen.insert(n.lowercased()).inserted { people.append(n) }
        }
        let byPerson = selectedName.map { sel in all.filter { names(for: $0).contains { $0.caseInsensitiveCompare(sel) == .orderedSame } } } ?? all
        let shown = query.isEmpty ? byPerson : byPerson.filter {
            $0.displayTitle.matchesSearch(query) || $0.displayArtist.matchesSearch(query)
        }

        return List {
            VStack(alignment: .leading, spacing: 12) {
                Text(album.name)
                    .font(.largeTitle.bold())
                    .lineLimit(3)
                Text("\(shown.count)/\(all.count) brani")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Picker("Filtra per", selection: $filterKind) {
                    ForEach(FilterKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        tile(filterKind.allLabel, selected: selectedName == nil) { selectedName = nil }
                        ForEach(people, id: \.self) { name in
                            tile(name, selected: selectedName?.caseInsensitiveCompare(name) == .orderedSame) {
                                selectedName = name
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowSeparator(.hidden)
            .padding(.top, 4)

            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            ForEach(Array(shown.enumerated()), id: \.offset) { index, track in
                TrackListRow(track: track,
                             isCurrent: player.loadedTrackID == track.id,
                             showArtwork: false,
                             leadingNumber: track.trackNumber,
                             sourceName: album.name) {
                    player.play(shown, startAt: index, source: album.name)
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
        .selectionScope(shown)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca nell'album")
        .onChange(of: filterKind) { _, _ in selectedName = nil }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { player.shuffleAndPlay(shown, source: album.name) } label: {
                    Label("Casuale", systemImage: "shuffle")
                }
                .disabled(shown.isEmpty)
                Menu {
                    TrackMenu(tracks: shown, sourceName: album.name, showNavigation: false)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func tile(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(8)
                .frame(width: 96, height: 96)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
