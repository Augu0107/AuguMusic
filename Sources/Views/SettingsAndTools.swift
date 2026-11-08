import SwiftUI
import UniformTypeIdentifiers

// MARK: - Equalizzatore

struct EqualizerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var savingPreset = false
    @State private var presetName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Toggle("Equalizzatore attivo", isOn: $settings.eqEnabled)
                        .font(.headline)

                    HStack {
                        Text("Preset")
                        Spacer()
                        Menu {
                            ForEach(EQPresets.builtIn) { preset in
                                Button(preset.name) { settings.applyPreset(name: preset.name, gains: preset.gains) }
                            }
                            if !settings.customPresets.isEmpty {
                                Divider()
                                ForEach(settings.customPresets.keys.sorted(), id: \.self) { name in
                                    Button(name) { settings.applyPreset(name: name, gains: settings.customPresets[name] ?? []) }
                                }
                            }
                            Divider()
                            Button {
                                presetName = ""
                                savingPreset = true
                            } label: { Label("Salva come preset…", systemImage: "plus") }
                        } label: {
                            Label(settings.eqPresetName, systemImage: "chevron.up.chevron.down")
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(0..<10, id: \.self) { i in
                                bandSlider(i)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                    .disabled(!settings.eqEnabled)
                    .opacity(settings.eqEnabled ? 1 : 0.45)

                    VStack(alignment: .leading, spacing: 18) {
                        labeledSlider("Preamplificazione", value: $settings.eqPreamp, range: -12...12, unit: "dB")
                        labeledSlider("Bass boost", value: $settings.bassBoost, range: 0...12, unit: "dB")
                    }
                    .disabled(!settings.eqEnabled)
                    .opacity(settings.eqEnabled ? 1 : 0.45)

                    Button("Reimposta tutto a zero") {
                        settings.applyPreset(name: "Flat", gains: Array(repeating: 0, count: 10))
                        settings.eqPreamp = 0
                        settings.bassBoost = 0
                    }
                    .buttonStyle(.bordered)

                    if !settings.customPresets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("I tuoi preset").font(.headline)
                            ForEach(settings.customPresets.keys.sorted(), id: \.self) { name in
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Button(role: .destructive) {
                                        settings.customPresets[name] = nil
                                    } label: { Image(systemName: "trash") }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Equalizzatore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
            .alert("Salva preset", isPresented: $savingPreset) {
                TextField("Nome", text: $presetName)
                Button("Salva") {
                    let name = presetName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    settings.customPresets[name] = settings.eqGains
                    settings.eqPresetName = name
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    private func bandSlider(_ i: Int) -> some View {
        let binding = Binding<Double>(
            get: { settings.eqGains.indices.contains(i) ? settings.eqGains[i] : 0 },
            set: { newValue in
                guard settings.eqGains.indices.contains(i) else { return }
                settings.eqGains[i] = newValue
                settings.eqPresetName = "Personalizzato"
            }
        )
        return VStack(spacing: 6) {
            Text(String(format: "%+.1f", binding.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: binding, in: -12...12, step: 0.5)
                .rotationEffect(.degrees(-90))
                .frame(width: 200)
                .frame(width: 44, height: 200)
            Text(EQPresets.frequencyLabels[i])
                .font(.caption2.weight(.semibold))
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%+.1f %@", value.wrappedValue, unit))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.5)
        }
    }
}

// MARK: - Timer di spegnimento

struct SleepTimerView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sleepFinishSong") private var finishSong = true
    @AppStorage("sleepCustomMinutes") private var customMinutes = 25
    @AppStorage("sleepSongs") private var songs = 3

    var body: some View {
        NavigationStack {
            Form {
                if let timer = player.sleepTimer {
                    Section("Attivo") {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(description(timer))
                        }
                        Button("Annulla il timer", role: .destructive) { player.cancelSleepTimer() }
                    }
                }
                Section {
                    Toggle("Finisci il brano in corso", isOn: $finishSong)
                }
                Section("Ferma tra") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 10) {
                        ForEach([5, 10, 15, 20, 30, 45, 60, 90, 120], id: \.self) { m in
                            Button("\(m) min") {
                                player.setSleepTimer(minutes: m, finishCurrentSong: finishSong)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                    Stepper("Personalizzato: \(customMinutes) min", value: $customMinutes, in: 1...600)
                    Button("Avvia \(customMinutes) min") {
                        player.setSleepTimer(minutes: customMinutes, finishCurrentSong: finishSong)
                        dismiss()
                    }
                }
                Section("Ferma dopo") {
                    Button("Questo brano") {
                        player.setSleepAfterCurrentSong()
                        dismiss()
                    }
                    Stepper("\(songs) brani", value: $songs, in: 2...200)
                    Button("Ferma dopo \(songs) brani") {
                        player.setSleepAfterSongs(songs)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Timer di spegnimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func description(_ timer: SleepTimer) -> String {
        switch timer.mode {
        case .at(let date):
            let remaining = formatTime(max(0, date.timeIntervalSinceNow))
            return "Mi fermo tra \(remaining)" + (timer.finishCurrentSong ? ", a fine brano" : "")
        case .afterCurrentSong:
            return "Mi fermo alla fine di questo brano"
        case .afterSongs(let n):
            return "Mi fermo tra \(n) brani"
        }
    }
}

// MARK: - Velocità, tono, bilanciamento

struct PlaybackSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Velocità: \(settings.speed.formatted(.number.precision(.fractionLength(2))))x") {
                    Slider(value: $settings.speed, in: 0.5...2.0, step: 0.05)
                    HStack {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { v in
                            Button(v.formatted(.number.precision(.fractionLength(0...2))) + "x") { settings.speed = v }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                Section("Tono: \(settings.pitch >= 0 ? "+" : "")\(Int(settings.pitch)) semitoni") {
                    Slider(value: $settings.pitch, in: -12...12, step: 1)
                }
                Section("Bilanciamento: \(balanceLabel)") {
                    Slider(value: $settings.balance, in: -1...1, step: 0.05)
                }
                Section {
                    Button("Reimposta") { settings.resetPlaybackEffects() }
                }
            }
            .navigationTitle("Riproduzione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var balanceLabel: String {
        if abs(settings.balance) < 0.01 { return "centro" }
        let pct = Int(abs(settings.balance) * 100)
        return settings.balance < 0 ? "\(pct)% sinistra" : "\(pct)% destra"
    }
}

// MARK: - Informazioni brano

struct TrackInfoView: View {
    let track: Track
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ArtworkView(track: track, maxPixel: 600, cornerRadius: 12, mode: .natural)
                            .frame(maxWidth: 220, maxHeight: 260)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Tag") {
                    row("Titolo", track.displayTitle)
                    row("Artista", track.displayArtist)
                    row("Album", track.displayAlbum)
                    row("Artista album", track.albumArtist)
                    row("Compositore", track.composer)
                    row("Genere", track.genre)
                    row("Anno", track.year.map { String($0) } ?? "")
                    row("Traccia", track.trackNumber.map { String($0) } ?? "")
                    row("Disco", track.discNumber.map { String($0) } ?? "")
                }
                Section("File") {
                    row("Durata", formatTime(track.duration))
                    row("Formato", track.fileExtension.uppercased())
                    row("Formato reale", track.formatName ?? "")
                    row("Dimensione", ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))
                    row("Cartella", library.folderName(track.folderID))
                    row("Percorso", track.relativePath)
                    row("Aggiunto", track.dateAdded.formatted(date: .abbreviated, time: .shortened))
                    if let rg = track.replayGainTrack {
                        row("ReplayGain brano", String(format: "%+.2f dB", rg))
                    }
                    if let rg = track.replayGainAlbum {
                        row("ReplayGain album", String(format: "%+.2f dB", rg))
                    }
                }
            }
            .navigationTitle("Informazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label) {
                Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - Impostazioni

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ScanProgress
    @State private var showImporter = false

    var body: some View {
        Form {
            Section {
                ForEach(library.folders) { folder in
                    HStack(spacing: 12) {
                        Image(systemName: folder.isAppDocuments ? "ipad" : "folder.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.isAppDocuments ? "Sull'iPad › AuguMusic" : folder.name)
                            Text(library.isAvailable(folder.id) ? "\(library.trackCount(in: folder.id)) brani" : "Non raggiungibile (ricollegala)")
                                .font(.caption)
                                .foregroundStyle(library.isAvailable(folder.id) ? Color.secondary : Color.red)
                        }
                    }
                    .swipeActions {
                        if !folder.isAppDocuments {
                            Button(role: .destructive) { library.removeFolder(folder.id) } label: {
                                Label("Rimuovi", systemImage: "trash")
                            }
                        }
                    }
                }
                Button { showImporter = true } label: {
                    Label("Aggiungi cartella…", systemImage: "folder.badge.plus")
                }
                Button {
                    Task { await library.rescan() }
                } label: {
                    if library.isScanning {
                        Label(progress.total > 0 ? "Scansione \(progress.done)/\(progress.total)…" : "Scansione…", systemImage: "hourglass")
                    } else {
                        Label("Aggiorna la libreria", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(library.isScanning)
            } header: {
                Text("Cartelle musicali · \(library.tracks.count) brani")
            } footer: {
                Text("Copia la musica nella cartella AuguMusic dell'app File (Sull'iPad), oppure aggiungi qualsiasi cartella: iCloud Drive, una chiavetta USB-C, un disco esterno o un server SMB. Scorri a sinistra per rimuovere una cartella.")
            }

            Section {
                StringListEditor(items: $settings.artistSeparators, placeholder: "Nuovo separatore (es. &, feat., /)", showQuotes: true)
            } header: {
                Text("Separatori artisti")
            } footer: {
                Text("Con \"&\", \"Karen Méndez & Mike Bahía\" diventano due artisti distinti. Vale per artisti, artisti album e compositori. Gli spazi contano: \" x \" non divide \"Max\".")
            }

            Section {
                StringListEditor(items: $settings.artistExceptions, placeholder: "Es. Simon & Garfunkel", showQuotes: false)
            } header: {
                Text("Eccezioni (mai divisi)")
            } footer: {
                Text("Nomi che contengono un separatore ma sono un solo artista.")
            }

            Section {
                ForEach(MainTab.allCases.filter { !$0.isRequired }) { item in
                    Toggle(isOn: Binding(get: { !settings.isTabHidden(item.rawValue) },
                                         set: { settings.setTab(item.rawValue, hidden: !$0) })) {
                        Label {
                            Text(item.title)
                        } icon: {
                            AppIconView(glyph: item.glyph, size: 20)
                        }
                    }
                }
            } header: {
                Text("Schede visibili")
            } footer: {
                Text("Puoi anche tenere premuta una scheda nella barra in basso e scegliere \"Nascondi\". Coda e In riproduzione restano sempre visibili.")
            }

            Section("Aspetto") {
                Picker("Tema", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                Picker("Colore", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                Toggle("Schermo sempre acceso in riproduzione", isOn: $settings.keepScreenOn)
            }

            Section {
                Picker("Colore del widget", selection: $settings.widgetStyle) {
                    ForEach(WidgetStyle.allCases) { Text($0.label).tag($0) }
                }
                if !WidgetBridge.shared.isAvailable {
                    Text("Il widget non riesce a ricevere i dati: l'App Group non è attivo. Prova a reinstallare l'app con AltStore.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Widget Home")
            } footer: {
                Text("Tieni premuto sulla Home dell'iPad → Modifica → Aggiungi widget → AuguMusic.")
            }

            Section {
                Picker("Toccando un brano", selection: $settings.tapAction) {
                    ForEach(TapAction.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Numero massimo di code: \(settings.maxQueues)", value: $settings.maxQueues, in: 2...50)
                Toggle("Conferma prima di rimuovere una coda", isOn: $settings.confirmQueueRemoval)
            } header: {
                Text("Code")
            }

            Section("Riproduzione") {
                VStack(alignment: .leading) {
                    Text(settings.crossfadeDuration == 0
                         ? "Crossfade tra i brani: disattivato"
                         : "Crossfade tra i brani: \(Int(settings.crossfadeDuration)) s")
                    Slider(value: $settings.crossfadeDuration, in: 0...12, step: 1)
                }
                Toggle("Dissolvenza su play e pausa", isOn: $settings.fadeEnabled)
                if settings.fadeEnabled {
                    VStack(alignment: .leading) {
                        Text("Durata dissolvenza: \(settings.fadeDuration.formatted(.number.precision(.fractionLength(1)))) s")
                        Slider(value: $settings.fadeDuration, in: 0.1...3, step: 0.1)
                    }
                }
                Picker("ReplayGain", selection: $settings.replayGain) {
                    ForEach(ReplayGainMode.allCases) { Text($0.label).tag($0) }
                }
                if settings.replayGain != .off {
                    VStack(alignment: .leading) {
                        Text("Preamp ReplayGain: \(String(format: "%+.1f", settings.replayGainPreamp)) dB")
                        Slider(value: $settings.replayGainPreamp, in: -12...12, step: 0.5)
                    }
                }
            }

            Section("Informazioni") {
                LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                Text("AuguMusic è un'app personale di Chiara, ispirata a Musicolet. Funziona solo con file locali: niente account, niente pubblicità, niente internet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .themedBackground()
        .navigationTitle("Impostazioni")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                library.addFolder(url)
            }
        }
    }
}

// MARK: - Editor di elenchi di testo

struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    let showQuotes: Bool
    @State private var newItem = ""

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            HStack {
                Text(showQuotes ? "\u{201C}\(item)\u{201D}" : item)
                    .font(.body.monospaced())
                Spacer()
                Button(role: .destructive) {
                    items.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        HStack {
            TextField(placeholder, text: $newItem)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(add)
            Button("Aggiungi", action: add)
                .disabled(newItem.isEmpty)
        }
    }

    private func add() {
        guard !newItem.isEmpty, !items.contains(newItem) else { return }
        items.append(newItem)
        newItem = ""
    }
}
