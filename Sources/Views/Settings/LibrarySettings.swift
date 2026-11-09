import AVFoundation
import SFBAudioEngine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Libreria brani e tag

struct LibrarySettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var progress: ScanProgress
    @EnvironmentObject private var ui: UIState
    @AppStorage(Prefs.minDuration) private var minDuration = 0
    @AppStorage(Prefs.autoScan) private var autoScan = true
    @AppStorage(Prefs.albumMerge) private var albumMerge = ""
    @AppStorage(Prefs.multiArtist) private var multiArtist = true
    @AppStorage(Prefs.multiAlbumArtist) private var multiAlbumArtist = true
    @AppStorage(Prefs.multiComposer) private var multiComposer = false
    @AppStorage(Prefs.multiGenre) private var multiGenre = false
    @AppStorage(Prefs.sepArtist) private var sepArtist = Prefs.defaultSeparators
    @AppStorage(Prefs.sepAlbumArtist) private var sepAlbumArtist = Prefs.defaultSeparators
    @AppStorage(Prefs.sepComposer) private var sepComposer = Prefs.defaultSeparators
    @AppStorage(Prefs.sepGenre) private var sepGenre = ", ; / | &"
    @AppStorage(Prefs.folderArtwork) private var folderArtwork = "always"
    @AppStorage(Prefs.lyricsSource) private var lyricsSource = "embedded"

    @State private var showMinDuration = false
    @State private var showMerge = false
    @State private var editSeparators: SeparatorKind?
    @State private var showFolderArt = false
    @State private var showLyrics = false
    @State private var showTypes = false
    @State private var showStorage = false
    @State private var showExceptions = false

    enum SeparatorKind: String, Identifiable {
        case artist, albumArtist, composer, genre
        var id: String { rawValue }
        var title: String {
            switch self {
            case .artist: "Separatori per \"Multi Artisti\""
            case .albumArtist: "Separatori per \"Multi Artisti album\""
            case .composer: "Separatori per \"Multi Compositori\""
            case .genre: "Separatori per \"Multi Genere\""
            }
        }
    }

    static let folderArtOptions = [
        ChoiceOption(id: "never", label: "Mai"),
        ChoiceOption(id: "singleAlbum", label: "Se la cartella contiene brani di solo 1 album"),
        ChoiceOption(id: "always", label: "Sempre"),
    ]
    static let lyricsOptions = [
        ChoiceOption(id: "embedded", label: "Testi incorporati"),
        ChoiceOption(id: "lrc", label: ".LRC file"),
    ]
    static let mergeOptions = [
        ChoiceOption(id: "albumArtist", label: "Artista album"),
        ChoiceOption(id: "composer", label: "Compositore"),
        ChoiceOption(id: "year", label: "Anno"),
    ]

    private var mergeSummary: Text {
        let chosen = ["Titolo Album"] + Self.mergeOptions.filter { albumMerge.csvContains($0.id) }.map(\.label)
        return Text("Considera 2 album uguali, se ") + Text("tutti i parametri selezionati").bold()
            + Text(" sono uguali:\n") + Text(chosen.joined(separator: ", ")).bold()
    }

    var body: some View {
        SettingsPage(title: "Libreria brani e tag") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("Libreria brani", first: true)
                    SettingsRow(title: "Cartelle da analizzare") { nav.path.append(.scanFolders) }
                    SettingsRow(title: "Cartelle escluse") { nav.path.append(.excludedFolders) }
                    SettingsRow(title: "Escludi file dalla durata breve",
                                subtitle: minDuration > 0 ? "Più corti di \(minDuration / 60):\(String(format: "%02d", minDuration % 60))" : nil) {
                        showMinDuration = true
                    }
                    SettingsRow(title: "Avanzati") { nav.path.append(.libraryAdvanced) }

                    SettingsSectionHeader(title: "Scansione")
                    SettingsRow(title: library.isScanning
                                ? (progress.total > 0 ? "Scansione \(progress.done)/\(progress.total)…" : "Scansione…")
                                : "Scansione",
                                systemIcon: "arrow.triangle.2.circlepath", enabled: !library.isScanning) {
                        Task { await library.rescan() }
                    }
                    SettingsCheckRow(title: "Scansione automatica",
                                     subtitle: "Scansione automatica all'avvio dell'app e quando torni nell'app.",
                                     isOn: $autoScan)

                    SettingsSectionHeader(title: "Tag, Copertine Album, Testi")
                    Button { showMerge = true } label: {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Strategia di unione degli album").foregroundStyle(Color.primary)
                                mergeSummary.font(.subheadline).foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 16)
                        }
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    multiBlock("Multi Artisti", isOn: $multiArtist, separators: sepArtist, kind: .artist)
                    multiBlock("Multi Artisti album", isOn: $multiAlbumArtist, separators: sepAlbumArtist, kind: .albumArtist)
                    multiBlock("Multi Compositori", isOn: $multiComposer, separators: sepComposer, kind: .composer)
                    multiBlock("Multi Genere", isOn: $multiGenre, separators: sepGenre, kind: .genre)
                    SettingsRow(title: "Eccezioni (mai divisi)",
                                subtitle: settings.artistExceptions.isEmpty ? "Nomi con un separatore che sono un solo artista (es. Simon & Garfunkel)"
                                                                            : settings.artistExceptions.joined(separator: ", ")) {
                        showExceptions = true
                    }
                    Button { showFolderArt = true } label: {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Usa i file folder.jpg, cover.jpg ecc").foregroundStyle(Color.primary)
                                (Text("Utilizza i file \"folder.jpg\", \"AlbumArt.jpg\" ecc. dalla stessa cartella, se AlbumArt non è incorporato nel file audio: ")
                                    + Text(Self.folderArtOptions.first { $0.id == folderArtwork }?.label ?? "").bold())
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 16)
                        }
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    SettingsRow(title: "Sorgente preferita per i testi",
                                subtitle: "Quando è disponibile più di una fonte per i testi, seleziona quale è la preferita") { showLyrics = true }
                    SettingsRow(title: "Nascondi contenuti extra dai tag") { nav.path.append(.hideExtra) }

                    SettingsSectionHeader(title: "Informazione")
                    SettingsRow(title: "Tipi di file supportati") { showTypes = true }
                    SettingsRow(title: "Dispositivi di memoria") { showStorage = true }
                }
                .padding(.bottom, 40)
            }
        }
        .settingsDialog(isPresented: $showMinDuration) {
            MinDurationDialog(seconds: $minDuration) { showMinDuration = false }
        }
        .settingsDialog(isPresented: $showMerge) {
            AlbumMergeDialog(stored: $albumMerge) { showMerge = false }
        }
        .settingsDialog(isPresented: Binding(get: { editSeparators != nil }, set: { if !$0 { editSeparators = nil } })) {
            if let kind = editSeparators {
                TextInputDialog(title: kind.title,
                                message: "I separatori sono i simboli/stringhe utilizzati per dividere il tag specificato. Aggiungi uno spazio tra due separatori.",
                                initial: separators(kind).wrappedValue) { value in
                    if let value { separators(kind).wrappedValue = value.trimmingCharacters(in: .whitespaces) }
                    editSeparators = nil
                }
            }
        }
        .settingsDialog(isPresented: $showFolderArt) {
            RadioDialog(title: "Utilizza i file \"folder.jpg\", \"AlbumArt.jpg\" ecc. dalla stessa cartella, se AlbumArt non è incorporato nel file audio:",
                        options: Self.folderArtOptions, selection: $folderArtwork) { showFolderArt = false }
        }
        .settingsDialog(isPresented: $showLyrics) {
            RadioDialog(title: "Sorgente preferita per i testi", options: Self.lyricsOptions, selection: $lyricsSource) { showLyrics = false }
        }
        .settingsDialog(isPresented: $showTypes) { SupportedTypesDialog { showTypes = false } }
        .sheet(isPresented: $showStorage) { StorageDevicesSheet() }
        .sheet(isPresented: $showExceptions) {
            NavigationStack {
                Form {
                    Section {
                        StringListEditor(items: $settings.artistExceptions, placeholder: "Es. Simon & Garfunkel", showQuotes: false)
                    } footer: {
                        Text("Nomi che contengono un separatore ma sono un solo artista: non vengono mai divisi.")
                    }
                }
                .navigationTitle("Eccezioni")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { showExceptions = false } } }
            }
        }
    }

    private func separators(_ kind: SeparatorKind) -> Binding<String> {
        switch kind {
        case .artist: $sepArtist
        case .albumArtist: $sepAlbumArtist
        case .composer: $sepComposer
        case .genre: $sepGenre
        }
    }

    private func sectionTitle(_ title: String, first: Bool = false) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.leading, 72)
            .padding(.top, first ? 22 : 0)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func multiBlock(_ title: String, isOn: Binding<Bool>, separators: String, kind: SeparatorKind) -> some View {
        SettingsCheckRow(title: title, isOn: isOn)
        SettingsRow(title: kind.title, subtitle: separators, enabled: isOn.wrappedValue) { editSeparators = kind }
    }
}

// MARK: - Finestre

struct MinDurationDialog: View {
    @Binding var seconds: Int
    let close: () -> Void
    @State private var mm = ""
    @State private var ss = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            (Text("Brani e audio ") + Text("più piccoli di").bold() + Text(" questa durata saranno esclusi dalla scansione."))
                .font(.title3)
            HStack(spacing: 20) {
                box("mm", $mm)
                Text(":").font(.title3)
                box("ss", $ss)
                Spacer()
            }
            Text("Tenere questi due valori vuoti a 0:0 non escluderà alcun file")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 40) {
                Spacer()
                Button("CANCELLA", action: close)
                Button("SALVA") {
                    seconds = max(0, (Int(mm) ?? 0) * 60 + min(59, Int(ss) ?? 0))
                    close()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
        }
        .padding(26)
        .onAppear {
            mm = "\(seconds / 60)"
            ss = "\(seconds % 60)"
        }
    }

    private func box(_ label: String, _ text: Binding<String>) -> some View {
        TextField("0", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.title3)
            .frame(width: 110, height: 84)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(uiColor: .systemGray3), lineWidth: 1.5))
            .overlay(alignment: .top) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(Color(uiColor: .systemBackground))
                    .offset(y: -8)
            }
    }
}

struct AlbumMergeDialog: View {
    @Binding var stored: String
    let close: () -> Void
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Strategia di unione degli album")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 26)
                .padding(.top, 26)
            (Text("Considera 2 album uguali, se ") + Text("tutti i parametri selezionati").bold() + Text(" sono uguali:"))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
            HStack(spacing: 24) {
                CheckMark(checked: true).opacity(0.4)
                Text("Titolo Album").foregroundStyle(Color.primary.opacity(0.8))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 13)
            ForEach(LibrarySettingsPage.mergeOptions) { option in
                Button {
                    if selected.contains(option.id) { selected.remove(option.id) } else { selected.insert(option.id) }
                } label: {
                    HStack(spacing: 24) {
                        CheckMark(checked: selected.contains(option.id))
                        Text(option.label).foregroundStyle(Color.primary.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
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

/// Finestra con un testo da scrivere (CANCELLA / OK).
struct TextInputDialog: View {
    let title: String
    var message: String? = nil
    let initial: String
    let done: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.weight(.semibold))
            if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            TextField("", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.accentColor).frame(height: 2) }
            HStack(spacing: 40) {
                Spacer()
                Button("CANCELLA") { done(nil) }
                Button("OK") { done(text) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
        }
        .padding(26)
        .onAppear {
            text = initial
            focused = true
        }
    }
}

struct SupportedTypesDialog: View {
    let close: () -> Void

    private var auguTypes: String {
        AudioDecoder.supportedPathExtensions.map { $0.lowercased() }.sorted().joined(separator: ", ")
    }

    private var systemTypes: String {
        let exts = AVURLAsset.audiovisualTypes().flatMap { UTType($0.rawValue)?.tags[.filenameExtension] ?? [] }
        return Set(exts.map { $0.lowercased() }).sorted().joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tipi di file supportati")
                .font(.title3.weight(.semibold))
                .padding(26)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Decoder AuguMusic").underline().font(.headline)
                    Text("I tipi di file supportati dal \"Decoder AuguMusic\" sono:\n" + auguTypes)
                    Text("Decoder sistema").underline().font(.headline).padding(.top, 18)
                    Text("I tipi di file supportati dal \"Decoder sistema\" di questo dispositivo (\(UIDevice.current.model)) sono:\n" + systemTypes)
                }
                .foregroundStyle(Color.primary.opacity(0.8))
                .padding(.horizontal, 26)
            }
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("OK", action: close)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
            }
            .padding(26)
        }
    }
}

struct StorageDevicesSheet: View {
    @EnvironmentObject private var library: LibraryStore

    private var capacity: (used: Int64, total: Int64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(total) - free, Int64(total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: "externaldrive.fill").font(.title2)
                Text("Dispositivi di memoria").font(.title2.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Image(systemName: "ipad").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UIDevice.current.name).font(.headline)
                        if let c = capacity {
                            Text("Archiviazione interna (\(gb(c.used))/\(gb(c.total)))").foregroundStyle(.secondary)
                            ProgressView(value: Double(c.used), total: Double(max(c.total, 1))).tint(Color.primary.opacity(0.7))
                        }
                    }
                }
            }
            .padding(18)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
            ForEach(library.folders.filter { !$0.isAppDocuments }) { folder in
                HStack(spacing: 16) {
                    Image(systemName: "folder.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(folder.name).font(.headline)
                        Text(library.isAvailable(folder.id) ? "Cartella collegata · \(library.trackCount(in: folder.id)) brani" : "Non raggiungibile")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(18)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
            }
            Spacer()
        }
        .padding(26)
        .presentationDetents([.medium])
    }

    private func gb(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / 1_000_000_000).rounded())) GB"
    }
}

// MARK: - Cartelle da analizzare

struct ScanFoldersPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(Prefs.excludedFolders) private var excluded = ""
    @State private var showImporter = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Button { nav.path.removeLast() } label: {
                        Image(systemName: "arrow.left").font(.title2).foregroundStyle(Color.primary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    Text("Cartelle da analizzare")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.75))
                    Text("Seleziona le cartelle in cui tieni i file audio.").foregroundStyle(.secondary)
                    ForEach(library.folders) { folder in
                        HStack(spacing: 18) {
                            Image(systemName: folder.isAppDocuments ? "ipad" : (library.isAvailable(folder.id) ? "folder" : "folder.badge.questionmark"))
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(folder.isAppDocuments ? "Sull'iPad › AuguMusic" : folder.name)
                                Text(library.isAvailable(folder.id) ? "\(library.trackCount(in: folder.id)) brani" : "Non raggiungibile: aggiungila di nuovo")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !folder.isAppDocuments {
                                Button { library.removeFolder(folder.id) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(Color.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 560, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
                    }
                    Button { showImporter = true } label: {
                        HStack(spacing: 18) {
                            Image(systemName: "folder.fill.badge.plus").font(.title2)
                            Text("AGGIUNGI CARTELLA").font(.headline)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 20)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    HairlineSeparator()
                    Button("Cartelle escluse: \(ExcludedFolders.list(excluded).count)") { nav.path.append(.excludedFolders) }
                        .underline()
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                    Text("Copia la musica nella cartella AuguMusic dell'app File (Sull'iPad), oppure aggiungi qualsiasi cartella: iCloud Drive, una chiavetta USB-C, un disco esterno o un server SMB.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
            Button {
                Task { await library.rescan() }
                nav.path.removeLast()
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .padding(28)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { library.addFolder(url) }
        }
    }
}

// MARK: - Cartelle escluse

struct ExcludedFoldersPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(Prefs.excludedFolders) private var excluded = ""
    @State private var items: [String] = []
    @State private var loaded = false
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button { nav.path.removeLast() } label: { Image(systemName: "arrow.left").font(.title2) }
                Text("Cartelle escluse").font(.title2.weight(.semibold))
                Spacer()
                Button {
                    excluded = items.joined(separator: "\n")
                    Task { await library.rescan() }
                    nav.path.removeLast()
                } label: {
                    Image(systemName: "checkmark").font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.8))
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color(uiColor: .systemGray6))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    (Text("I brani nelle cartelle elencate sotto non saranno scansionati. Anche i brani nelle loro ")
                        + Text("sotto-cartelle non saranno scansionati.").bold())
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items, id: \.self) { key in
                            Button { items.removeAll { $0 == key } } label: {
                                HStack(spacing: 18) {
                                    Image(systemName: "minus.circle").font(.title2)
                                    Text(displayPath(key)).multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if items.isEmpty {
                            Text("Nessuna cartella esclusa").foregroundStyle(.secondary).padding(22)
                        }
                        Spacer(minLength: 30)
                        HairlineSeparator()
                        Button { showPicker = true } label: {
                            HStack(spacing: 18) {
                                Image(systemName: "plus").font(.title2)
                                Text("Aggiungi cartella").font(.headline)
                                Spacer()
                            }
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .padding(22)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
                }
                .padding(30)
                .frame(maxWidth: 720)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            items = ExcludedFolders.list(excluded)
        }
        .sheet(isPresented: $showPicker) {
            FolderPickerSheet(exclude: Set(items)) { key in
                if !items.contains(key) { items.append(key) }
            }
        }
    }

    private func displayPath(_ key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let root = parts.first.flatMap { UUID(uuidString: String($0)) }.map { library.folderName($0) } ?? "?"
        let dir = parts.count > 1 ? String(parts[1]) : ""
        return ([root] + dir.split(separator: "/").map(String.init)).joined(separator: " › ")
    }
}

/// Elenco di tutte le cartelle della libreria (anche quelle intermedie) da cui sceglierne una.
struct FolderPickerSheet: View {
    let exclude: Set<String>
    let pick: (String) -> Void
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    private var keys: [String] {
        var all = Set<String>()
        for g in library.groups(of: .folder) {
            let parts = g.id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let root = parts.first else { continue }
            let dir = parts.count > 1 ? String(parts[1]) : ""
            var comps = dir.split(separator: "/").map(String.init)
            while !comps.isEmpty {
                all.insert(String(root) + "|" + comps.joined(separator: "/"))
                comps.removeLast()
            }
        }
        return all.subtracting(exclude).sorted { $0.localizedLess($1) }
    }

    var body: some View {
        NavigationStack {
            List(keys, id: \.self) { key in
                Button {
                    pick(key)
                    dismiss()
                } label: {
                    let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                    let root = parts.first.flatMap { UUID(uuidString: String($0)) }.map { library.folderName($0) } ?? "?"
                    Label(([root] + (parts.count > 1 ? parts[1].split(separator: "/").map(String.init) : [])).joined(separator: " › "),
                          systemImage: "folder")
                }
            }
            .navigationTitle("Scegli la cartella da escludere")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
        }
    }
}

// MARK: - Avanzati

struct LibraryAdvancedPage: View {
    @AppStorage(Prefs.scannerPref) private var scanner = "system"
    @AppStorage(Prefs.albumArtistFallback) private var fallback = false
    @AppStorage(Prefs.scanHidden) private var hidden = false
    @AppStorage(Prefs.scanNomedia) private var nomedia = false
    @AppStorage(Prefs.scanVideo) private var video = false
    @State private var showScanner = false

    static let scannerOptions = [
        ChoiceOption(id: "system", label: "Scanner di sistema"),
        ChoiceOption(id: "augu", label: "Scanner per AuguMusic"),
    ]

    var body: some View {
        SettingsPage(title: "Avanzati") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Scanner preferito", subtitle: Self.scannerOptions.first { $0.id == scanner }?.label) { showScanner = true }
                    SettingsCheckRow(title: "Se il tag AlbumArtist non è presente, utilizza il tag Artista.", isOn: $fallback)
                    SettingsCheckRow(title: "Scansione all'interno di cartelle nascoste",
                                     subtitle: "Scansione all'interno di cartelle i cui nomi iniziano con un punto (.)", isOn: $hidden)
                    SettingsCheckRow(title: "Scansione all'interno di cartelle \"nomedia\"",
                                     subtitle: "Scansione all'interno di cartelle che contengono un file \".nomedia\"", isOn: $nomedia)
                    SettingsCheckRow(title: "Scansione di file video",
                                     subtitle: "Verranno riprodotti come file audio. Non tutti i formati sono supportati.", isOn: $video)
                }
            }
        }
        .settingsDialog(isPresented: $showScanner) {
            RadioDialog(title: "Scanner preferito", options: Self.scannerOptions, selection: $scanner) { showScanner = false }
        }
    }
}

// MARK: - Nascondi contenuti extra dai tag

struct HideExtraPage: View {
    @AppStorage(Prefs.hideExtraNowPlaying) private var nowPlaying = false
    @AppStorage(Prefs.hideExtraAll) private var all = false
    @State private var showHelp = false

    var body: some View {
        SettingsPage(title: "Nascondi contenuti extra…") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    checkRow(Text("Nasconde il nome del sito e altri contenuti extra dai tag da ") + Text("Solo brano in riproduzione.").bold()
                             + Text(" Si applica solo alla schermata 'In riproduzione', Widget e Schermata di blocco."), isOn: $nowPlaying)
                    checkRow(Text("Nasconde il nome del sito e altri contenuti extra dai tag da ") + Text("Tutti i brani. Si applica ovunque.").bold(),
                             isOn: $all)
                    SettingsRow(title: "A cosa serve questa funzione?", systemIcon: "questionmark.circle") { showHelp = true }
                }
            }
        }
        .settingsDialog(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 18) {
                Text("A cosa serve questa funzione?").font(.title3.weight(.semibold))
                (Text("Supponi che il titolo e l'artista di un brano siano tipo:\nTitolo:\n")
                    + Text("\"Esempio Titolo123 - 320kbps | DownloadMp3SongBlaBla.com\"").bold()
                    + Text("\nArtista:\n") + Text("\"Esempio Artista123 (www.DownloadMp3SongBlaBla.com)\"").bold()
                    + Text("\n\nQuando attivi questa funzione, diventeranno tipo:\nTitolo: ") + Text("\"Esempio Titolo123\"").bold()
                    + Text("\nArtista: ") + Text("\"Esempio Artista123\"").bold()
                    + Text("\n\nIn breve nasconde le informazioni extra come il sito web e altre informazioni extra dai tag.\n\nPuoi attivare questa funzione sia per ")
                    + Text("il solo brano attualmente in riproduzione").bold() + Text(" o ") + Text("per tutti i brani della libreria.").bold())
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("FATTO") { showHelp = false }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                }
            }
            .padding(26)
        }
    }

    private func checkRow(_ text: Text, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: 72)
                text.foregroundStyle(.secondary).multilineTextAlignment(.leading)
                Spacer(minLength: 16)
                CheckMark(checked: isOn.wrappedValue)
            }
            .padding(.vertical, 18)
            .padding(.trailing, 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
