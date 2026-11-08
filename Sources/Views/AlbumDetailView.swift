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
                Text("\(shown.count)/\(all.count) brani · \(formatTime(shown.reduce(0) { $0 + $1.duration }))")
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
                             showArtwork: true,
                             showAlbum: false,
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
        .safeAreaInset(edge: .bottom) { searchBar }
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

    /// Barra di ricerca ancorata in fondo, sotto la lista.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Cerca nell'album", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Riquadro bianco con bordino grigio e, 2px sotto, una lineetta.
    /// Con "Tutti…" scelto tutte le lineette sono del colore d'accento; scegliendo un nome,
    /// gli altri diventano grigio chiaro (testo e lineetta).
    private func tile(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let dimmed = selectedName != nil && !selected
        let lightGray = Color(uiColor: .systemGray3)
        return Button(action: action) {
            Text(name)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(8)
                .padding(.bottom, 4)
                .frame(width: 96, height: 96)
                .foregroundStyle(dimmed ? lightGray : Color.primary)
                .overlay(alignment: .bottom) {
                    // Lineetta dentro il riquadro, in basso, centrata e staccata dai lati
                    Rectangle()
                        .fill(dimmed ? lightGray : Color.accentColor)
                        .frame(height: 3)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(uiColor: .systemGray4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
