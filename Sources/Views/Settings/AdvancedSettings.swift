import SwiftUI

// MARK: - Avanzati

struct AdvancedSettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(Prefs.showFileName) private var showFileName = false
    @AppStorage(Prefs.nextPrevAsSeek) private var nextPrevAsSeek = false
    @AppStorage(Prefs.rememberPosition) private var rememberPosition = false
    @AppStorage(Prefs.playCountPercent) private var playCountPercent = 30
    @AppStorage(Prefs.prevBehavior) private var prevBehavior = "always"
    @AppStorage(Prefs.confirmQuit) private var confirmQuit = true
    @AppStorage(Prefs.shuffleMode) private var shuffleMode = "all"
    @AppStorage(Prefs.randomSortMode) private var randomSortMode = "all"
    @AppStorage(Prefs.sameNameQueue) private var sameNameQueue = "replace"
    @AppStorage(Prefs.autoplayOnLaunch) private var autoplayOnLaunch = false
    @AppStorage(Prefs.castEnabled) private var castEnabled = true
    @AppStorage(Prefs.loadArtwork) private var loadArtwork = true
    @AppStorage(Prefs.externalControl) private var externalControl = true
    @AppStorage(Prefs.seekForwardSeconds) private var seekForward = 10
    @AppStorage(Prefs.seekBackSeconds) private var seekBack = 10
    @AppStorage(Prefs.searchEngine) private var searchEngine = "google"
    @AppStorage(Prefs.artQuery) private var artQuery = "<ar> <t>"
    @AppStorage(Prefs.lyricsQuery) private var lyricsQuery = "lyrics <t> <al>"
    @AppStorage(Prefs.naturalSortTags) private var naturalTags = ""

    private enum Dialog: Identifiable {
        case nextPrev, remember, playCount, prev, shuffle, random, sameName, seekForward, seekBack, engine, artQuery, lyricsQuery, natural
        var id: String { "\(self)" }
    }
    @State private var dialog: Dialog?

    static let playCountOptions = [10, 30, 50, 90].map { ChoiceOption(id: "\($0)", label: "\($0)% della durata") }
    static let prevOptions = [
        ChoiceOption(id: "always", label: "Riproduci sempre il brano precedente"),
        ChoiceOption(id: "restart10", label: "Se il brano corrente è riprodotto per più di 10 secondi allora riproduci nuovamente dall'inizio, altrimenti riproduci il brano precedente"),
    ]
    static let shuffleOptions = [
        ChoiceOption(id: "all", label: "Shuffle tutti i brani in ogni Coda"),
        ChoiceOption(id: "after", label: "Shuffle solo i brani successivi a quello in riproduzione"),
    ]
    static let randomOptions = [
        ChoiceOption(id: "all", label: "Shuffle tutti i brani nella Coda"),
        ChoiceOption(id: "after", label: "Shuffle solo i brani successivi a quello in riproduzione"),
    ]
    static let sameNameOptions = [
        ChoiceOption(id: "replace", label: "Sostituisci la coda esistente con la sorgente"),
        ChoiceOption(id: "merge", label: "Unisci la coda esistente con la sorgente"),
    ]
    static let engineOptions = [ChoiceOption(id: "ask", label: "Chiedi ogni volta")]
        + OnlineSearch.engines.map { ChoiceOption(id: $0.id, label: $0.name) }
    static let tagOptions = [
        ChoiceOption(id: "title", label: "Titolo"),
        ChoiceOption(id: "fileName", label: "Nome file"),
        ChoiceOption(id: "folder", label: "Cartella"),
        ChoiceOption(id: "album", label: "Album"),
        ChoiceOption(id: "artist", label: "Artista"),
        ChoiceOption(id: "albumArtist", label: "Artista album"),
        ChoiceOption(id: "composer", label: "Compositore"),
    ]

    private func label(_ options: [ChoiceOption], _ id: String) -> String? { options.first { $0.id == id }?.label }

    private var naturalSummary: String {
        let chosen = Self.tagOptions.filter { naturalTags.csvContains($0.id) }.map(\.label)
        return chosen.isEmpty ? "Nessuno" : chosen.joined(separator: ", ")
    }

    var body: some View {
        SettingsPage(title: "Avanzati") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsCheckRow(title: "Invece del titolo del brano mostra il nome del file, ovunque", isOn: $showFileName)
                    SettingsRow(title: "Fai in modo che i pulsanti \"Successivo\" e \"Precedente\" funzionino come i pulsanti di \"Avanti veloce\" e \"Riavvolgi\".",
                                subtitle: "Utile per andare avanti o indietro nel brano con i tasti successivo/precedente di cuffie, telecomandi, ecc.") {
                        dialog = .nextPrev
                    }
                    SettingsRow(title: "Ricorda l'ultima posizione di tutti i brani",
                                subtitle: "Utile per riprendere da dove eri rimasto in brani lunghi, podcast, audiolibri ecc.") { dialog = .remember }
                    SettingsRow(title: "Durata minima per considerarla una riproduzione",
                                subtitle: "Durata minima della riproduzione per considerare il brano come riprodotto: \(playCountPercent)%") { dialog = .playCount }
                    SettingsRow(title: "Funzionamento pulsante Brano precedente",
                                subtitle: "Decidi cosa fare quando premi il pulsante brano precedente dal lettore, dalla Schermata di blocco o dagli auricolari") {
                        dialog = .prev
                    }
                    SettingsCheckRow(title: "Conferma prima di chiudere l'app con \"Chiudi app\"", isOn: $confirmQuit)
                    SettingsRow(title: "Quando attivo la 'Modalità Shuffle'…", subtitle: label(Self.shuffleOptions, shuffleMode)) { dialog = .shuffle }
                    SettingsRow(title: "Quando seleziono 'Random' come opzione di ordinamento per una Coda…",
                                subtitle: label(Self.randomOptions, randomSortMode)) { dialog = .random }
                    SettingsRow(title: "Quando esiste già una coda con lo stesso nome della sorgente (playlist/album/artista/cartella/genere)…",
                                subtitle: label(Self.sameNameOptions, sameNameQueue)) { dialog = .sameName }
                    SettingsToggleRow(title: "Avvia la riproduzione all'avvio dell'app", isOn: $autoplayOnLaunch)
                    SettingsToggleRow(title: "Cast", subtitle: "AirPlay (pulsante in alto in 'In riproduzione')", isOn: $castEnabled)
                    SettingsRow(title: "Esporta automaticamente i dati dei brani/artisti più ascoltati in file CSV", systemIcon: "tablecells") {
                        nav.path.append(.csvExport)
                    }
                    SettingsToggleRow(title: "Carica la copertina dell'album",
                                      subtitle: "Se disabilitato, la copertina dell'album non verrà caricata in nessun punto dell'app.", isOn: $loadArtwork)
                    SettingsToggleRow(title: "Controllo esterno avanzato",
                                      subtitle: "Consenti alla schermata di blocco e ai dispositivi esterni di controllare: Opzioni di ripetizione, Modalità casuale, Preferiti",
                                      isOn: $externalControl)
                    SettingsRow(title: "Durata dell'Avanti-veloce", subtitle: "\(seekForward) secondi") { dialog = .seekForward }
                    SettingsRow(title: "Durata del Riavvolgi", subtitle: "\(seekBack) secondi") { dialog = .seekBack }

                    SettingsSectionHeader(title: "Cerca usando altre app")
                    SettingsRow(title: "Motore di ricerca predefinito", subtitle: "Per cercare copertine e testi di album") { dialog = .engine }
                    SettingsRow(title: "Interrogazione per cercare la copertina dell'album", subtitle: artQuery) { dialog = .artQuery }
                    SettingsRow(title: "Interrogazione per cercare i testi", subtitle: lyricsQuery) { dialog = .lyricsQuery }

                    SettingsSectionHeader(title: "Ordina")
                    SettingsRow(title: "Shuffle avanzato") { nav.path.append(.advancedShuffle) }
                    SettingsRow(title: "Ignora alcune parole all'inizio durante l'ordinamento",
                                subtitle: "Utile per ignorare \"A\", \"An\", \"The\" ecc. da vari tag durante l'ordinamento.") { nav.path.append(.ignoreWords) }
                    SettingsRow(title: "Ordinamento alfanumerico", subtitle: naturalSummary) { dialog = .natural }
                }
                .padding(.bottom, 40)
            }
        }
        .settingsDialog(isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })) {
            if let d = dialog { dialogView(d) }
        }
    }

    @ViewBuilder
    private func dialogView(_ d: Dialog) -> some View {
        let close = { dialog = nil }
        switch d {
        case .nextPrev:
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "backward.end.fill"); Text("="); Image(systemName: "backward.fill")
                    Divider().frame(height: 20)
                    Image(systemName: "forward.end.fill"); Text("="); Image(systemName: "forward.fill")
                }
                .foregroundStyle(.secondary)
                Toggle(isOn: $nextPrevAsSeek) {
                    Text("Fai in modo che i pulsanti \"Successivo\" e \"Precedente\" funzionino come i pulsanti di \"Avanti veloce\" e \"Riavvolgi\".")
                        .font(.headline)
                }
                .tint(Color.accentColor)
                Label("Utile per andare avanti o indietro nel brano con i tasti successivo/precedente di cuffie, telecomandi, ecc.", systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("Vale per i tasti premuti fuori dall'app (schermata di blocco, Centro di Controllo, widget, cuffie, telecomandi).", systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(26)
        case .remember:
            Toggle("Ricorda l'ultima posizione di tutti i brani", isOn: $rememberPosition)
                .font(.headline)
                .tint(Color.accentColor)
                .padding(26)
        case .playCount:
            RadioDialog(title: "Durata minima per considerarla una riproduzione", options: Self.playCountOptions,
                        selection: Binding(get: { "\(playCountPercent)" }, set: { playCountPercent = Int($0) ?? 30 }), close: close)
        case .prev:
            RadioDialog(title: "Funzionamento pulsante Brano precedente", options: Self.prevOptions, selection: $prevBehavior, close: close)
        case .shuffle:
            RadioDialog(title: "Quando attivo la 'Modalità Shuffle'…", options: Self.shuffleOptions, selection: $shuffleMode, close: close)
        case .random:
            RadioDialog(title: "Quando seleziono 'Random' come opzione di ordinamento per una Coda…", options: Self.randomOptions,
                        selection: $randomSortMode, close: close)
        case .sameName:
            RadioDialog(title: "Quando esiste già una coda con lo stesso nome della sorgente (playlist/album/artista/cartella/genere)…",
                        options: Self.sameNameOptions, selection: $sameNameQueue, close: close)
        case .seekForward:
            NumberInputDialog(title: "Durata dell'Avanti-veloce (in secondi)", value: Double(seekForward), range: 1...600, decimals: 0) { v in
                if let v { seekForward = Int(v) }
                close()
            }
        case .seekBack:
            NumberInputDialog(title: "Durata del Riavvolgi (in secondi)", value: Double(seekBack), range: 1...600, decimals: 0) { v in
                if let v { seekBack = Int(v) }
                close()
            }
        case .engine:
            RadioDialog(title: "Motore di ricerca predefinito", options: Self.engineOptions, selection: $searchEngine, resetValue: "google", close: close)
        case .artQuery:
            TextInputDialog(title: "Interrogazione per cercare la copertina dell'album", message: "<t>=Titolo, <al>=Album, <ar>=Artista",
                            initial: artQuery) { v in
                if let v, !v.isEmpty { artQuery = v }
                close()
            }
        case .lyricsQuery:
            TextInputDialog(title: "Interrogazione per cercare i testi", message: "<t>=Titolo, <al>=Album, <ar>=Artista",
                            initial: lyricsQuery) { v in
                if let v, !v.isEmpty { lyricsQuery = v }
                close()
            }
        case .natural:
            TagCheckboxDialog(title: "Ordinamento alfanumerico",
                              message: "Con questa funzione l'app potrebbe impiegare un po' più di tempo ad aprire e ordinare elenchi molto grandi. Attivala solo dove serve.",
                              stored: $naturalTags, close: close)
        }
    }
}

/// Caselle con i tag (Titolo, Nome file, Cartella...) e i tasti CANCELLA / OK.
struct TagCheckboxDialog: View {
    let title: String
    let message: String
    @Binding var stored: String
    let close: () -> Void
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 26).padding(.top, 26)
            Text(message).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.vertical, 14)
            ForEach(AdvancedSettingsPage.tagOptions) { option in
                Button {
                    if selected.contains(option.id) { selected.remove(option.id) } else { selected.insert(option.id) }
                } label: {
                    HStack(spacing: 24) {
                        CheckMark(checked: selected.contains(option.id))
                        Text(option.label).foregroundStyle(Color.primary.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 40) {
                Spacer()
                Button("CANCELLA", action: close)
                Button("OK") {
                    stored = String.csv(selected)
                    close()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .padding(26)
        }
        .onAppear { selected = stored.csvItems }
    }
}

// MARK: - Esporta CSV

struct CSVExportPage: View {
    @AppStorage(Prefs.csvExport) private var enabled = false

    var body: some View {
        SettingsPage(title: "Esporta automaticamente…") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Image(systemName: "tablecells").font(.title2).foregroundStyle(.secondary).frame(width: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Esporta automaticamente i dati dei brani/artisti più ascoltati in file CSV")
                            Text("alla fine di ogni settimana, mese e anno").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 16)
                        Toggle("", isOn: $enabled).labelsHidden().tint(Color.accentColor)
                    }
                    .padding(.vertical, 16)
                    .padding(.trailing, 20)
                    SettingsRow(title: "Posizione", subtitle: "Sull'iPad › AuguMusic › Exported Play Counts", enabled: false) {}
                    Text("Contano solo gli ascolti fatti da questa versione in poi: prima l'app non salvava la data di ogni ascolto.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 72)
                        .padding(.trailing, 20)
                }
            }
        }
    }
}

// MARK: - Shuffle avanzato

struct AdvancedShufflePage: View {
    @State private var open: AdvancedShuffle?
    @State private var refresh = 0

    private let modes: [(AdvancedShuffle, String)] = [
        (.albums, "album"), (.artists, "artista"), (.albumArtists, "artista album"),
        (.composers, "compositore"), (.genres, "genere"), (.folders, "cartella"),
    ]

    var body: some View {
        SettingsPage(title: "Shuffle avanzato") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(modes.indices, id: \.self) { i in
                        let mode = modes[i].0
                        let noun = modes[i].1
                        let current = UserDefaults.standard.string(forKey: mode.sortKey) ?? "default"
                        SettingsRow(title: "Ordinamento per \"\(mode.label)\"",
                                    subtitle: "Decidi come saranno ordinati i brani all'interno di ogni \(noun) quando usi '\(mode.label)'. Ora: "
                                        + (AdvancedShuffle.sortOptions.first { $0.id == current }?.label ?? "")) {
                            open = mode
                        }
                    }
                }
                .id(refresh)
            }
        }
        .settingsDialog(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) {
            if let mode = open {
                RadioDialog(title: "Ordinamento per \"\(mode.label)\"", options: AdvancedShuffle.sortOptions,
                            selection: Binding(get: { UserDefaults.standard.string(forKey: mode.sortKey) ?? "default" },
                                               set: { UserDefaults.standard.set($0, forKey: mode.sortKey); refresh += 1 })) {
                    open = nil
                }
            }
        }
    }
}

// MARK: - Ignora parole all'inizio

struct IgnoreWordsPage: View {
    @AppStorage(Prefs.ignoreWords) private var words = "A An The"
    @AppStorage(Prefs.ignoreWordsTags) private var tags = ""
    @State private var editWords = false
    @State private var editTags = false

    var body: some View {
        SettingsPage(title: "Ignora alcune parole all'inizio") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Ignora queste parole all'inizio", subtitle: words) { editWords = true }
                    SettingsRow(title: "Applica questa impostazione per questi tag",
                                subtitle: {
                                    let chosen = AdvancedSettingsPage.tagOptions.filter { tags.csvContains($0.id) }.map(\.label)
                                    return chosen.isEmpty ? "Nessuno" : chosen.joined(separator: ", ")
                                }()) { editTags = true }
                }
            }
        }
        .settingsDialog(isPresented: $editWords) {
            TextInputDialog(title: "Ignora queste parole all'inizio", message: "Separare le parole con uno spazio.", initial: words) { v in
                if let v { words = v.trimmingCharacters(in: .whitespaces) }
                editWords = false
            }
        }
        .settingsDialog(isPresented: $editTags) {
            TagCheckboxDialog(title: "Applica questa impostazione per questi tag",
                              message: "Con questa funzione l'app potrebbe impiegare un po' più di tempo ad aprire e ordinare elenchi molto grandi. Attivala solo dove serve.",
                              stored: $tags) { editTags = false }
        }
    }
}
