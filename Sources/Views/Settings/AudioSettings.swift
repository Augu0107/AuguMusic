import SwiftUI

// MARK: - Audio

struct AudioSettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var settings: AppSettings
    @State private var showSpeed = false
    @State private var showFocus = false
    @State private var showCrossfade = false
    @State private var showDecoder = false
    @State private var showEQChoice = false

    static let crossfadeOptions: [ChoiceOption] =
        [ChoiceOption(id: "0", label: "spento")] + (2...59).map { ChoiceOption(id: "\($0)", label: "\($0) secondi") }
        + [ChoiceOption(id: "60", label: "1 minuto")]
    static let decoderOptions = [
        ChoiceOption(id: "augu", label: "Decoder AuguMusic"),
        ChoiceOption(id: "system", label: "Decoder sistema"),
    ]
    static let eqOptions = [
        ChoiceOption(id: "none", label: "Nessuno"),
        ChoiceOption(id: "augu", label: "Equalizzatore di AuguMusic"),
    ]

    private var crossfadeLabel: String {
        let s = Int(settings.crossfadeDuration)
        return s == 0 ? "spento" : (s == 60 ? "1 minuto" : "\(s) secondi")
    }

    var body: some View {
        SettingsPage(title: "Audio") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Velocità di riproduzione e Tono") { showSpeed = true }
                    SettingsRow(title: "Focus audio", subtitle: "Livello \(settings.audioFocus)") { showFocus = true }
                    SettingsToggleRow(title: "Riproduzione Gapless", subtitle: settings.crossfadeDuration > 0 ? "Non serve con il crossfade attivo" : nil,
                                      isOn: $settings.gapless)
                    SettingsRow(title: "Crossfade", subtitle: crossfadeLabel) { showCrossfade = true }
                    SettingsSliderRow(title: "Sfuma il volume quando riproduci", value: $settings.fadeInMs, range: 0...3000, step: 50) {
                        "\(Int($0)) ms"
                    }
                    SettingsSliderRow(title: "Sfuma il volume quando vai in pausa", value: $settings.fadeOutMs, range: 0...3000, step: 50) {
                        "\(Int($0)) ms"
                    }

                    SettingsSectionHeader(title: "Decoder")
                    SettingsRow(title: "Decoder",
                                subtitle: Self.decoderOptions.first { $0.id == settings.decoder }?.label) { showDecoder = true }

                    SettingsSectionHeader(title: "Equalizzatore")
                    SettingsRow(title: "Equalizzatore da usare",
                                subtitle: Self.eqOptions.first { $0.id == settings.eqChoice }?.label) { showEQChoice = true }
                    SettingsRow(title: "Equalizzatore di AuguMusic", subtitle: "Impostazioni per l'equalizzatore AuguMusic",
                                enabled: settings.eqChoice == "augu") { nav.path.append(.eqSettings) }

                    SettingsSectionHeader(title: "Volume")
                    SettingsToggleRow(title: "Non consentire la riproduzione se il volume dell'audio è 0", isOn: $settings.blockZeroVolume)
                    SettingsToggleRow(title: "Metti in pausa quando l'audio è disattivato", isOn: $settings.pauseOnMute)
                    SettingsCheckRow(title: "Riprendi quando l'audio è nuovamente abilitato",
                                     subtitle: "Se la riproduzione è stata sospesa in precedenza perché l'audio era disattivato",
                                     isOn: $settings.resumeOnUnmute, enabled: settings.pauseOnMute)

                    SettingsSectionHeader(title: "Normalizzazione del volume")
                    SettingsRow(title: "ReplayGain", subtitle: settings.replayGain.label) { nav.path.append(.replayGain) }
                }
                .padding(.bottom, 40)
            }
        }
        .settingsDialog(isPresented: $showSpeed) { SpeedPitchDialog { showSpeed = false } }
        .settingsDialog(isPresented: $showFocus) { AudioFocusDialog() }
        .settingsDialog(isPresented: $showCrossfade) {
            RadioDialog(title: "Crossfade", options: Self.crossfadeOptions,
                        selection: Binding(get: { "\(Int(settings.crossfadeDuration))" },
                                           set: { settings.crossfadeDuration = Double($0) ?? 0 }),
                        resetValue: "3") { showCrossfade = false }
        }
        .settingsDialog(isPresented: $showDecoder) {
            RadioDialog(title: "Decoder", options: Self.decoderOptions, selection: $settings.decoder) { showDecoder = false }
        }
        .settingsDialog(isPresented: $showEQChoice) {
            RadioDialog(title: "Equalizzatore da usare", options: Self.eqOptions, selection: $settings.eqChoice) { showEQChoice = false }
        }
    }
}

/// Riga con la casella a destra (come "Riprendi quando l'audio è nuovamente abilitato").
struct SettingsCheckRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(title)).font(.body).foregroundStyle(Color.primary.opacity(enabled ? 0.8 : 0.35))
                    if let subtitle {
                        Text(L(subtitle)).font(.subheadline).foregroundStyle(Color.secondary.opacity(enabled ? 1 : 0.5))
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 16)
                CheckMark(checked: isOn).opacity(enabled ? 1 : 0.4)
            }
            .padding(.vertical, 14)
            .padding(.trailing, 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Velocità e tono

/// Finestra "Velocità di riproduzione e Tono" (Semplice / Avanzati, per tutti i file o solo per questo).
struct SpeedPitchDialog: View {
    let close: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerController
    @AppStorage("speedDialogAdvanced") private var advanced = false
    @State private var onlyThisFile = false
    @State private var overrideAll = false
    @State private var speed = 1.0
    @State private var pitchRatio = 1.0
    @State private var loaded = false

    static let simpleSteps: [Double] = [0.5, 0.75, 0.9, 1, 1.25, 1.5, 2]

    private var trackID: String? { player.loadedTrackID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if advanced {
                scopePicker
                HairlineSeparator()
                valueEditor(title: "Velocità di riproduzione", value: $speed, range: 0.25...3)
                HairlineSeparator().padding(.horizontal, 26)
                valueEditor(title: "Tono", value: $pitchRatio, range: 0.5...2)
            } else {
                Text("Velocità di riproduzione")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 26)
                    .padding(.top, 26)
                    .padding(.bottom, 14)
                HStack(spacing: 0) {
                    ForEach(Self.simpleSteps, id: \.self) { v in
                        let selected = abs(speed - v) < 0.001
                        Button {
                            speed = v
                            commit()
                        } label: {
                            Text(v.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.callout.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
                                .overlay(Rectangle().stroke(selected ? Color.accentColor : Color(uiColor: .systemGray4),
                                                            lineWidth: selected ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            HairlineSeparator()
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    modeButton("Semplice", selected: !advanced) { advanced = false }
                    modeButton("Avanzati", selected: advanced) { advanced = true }
                }
                Spacer()
                if advanced {
                    squareButton(systemImage: "arrow.counterclockwise") {
                        speed = 1
                        pitchRatio = 1
                    }
                }
                squareButton(systemImage: "checkmark", tint: Color.accentColor) {
                    commit()
                    close()
                }
            }
            .padding(16)
        }
        .onAppear(perform: load)
    }

    private var scopePicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                scopeButton("Per tutti i file", selected: !onlyThisFile) { onlyThisFile = false }
                scopeButton("Solo per questo file", selected: onlyThisFile, enabled: trackID != nil) { onlyThisFile = true }
            }
            if !onlyThisFile {
                Menu {
                    Button("ma escludendo quei file che hanno già le proprie impostazioni.") { overrideAll = false }
                    Button("anche per i file che hanno le proprie impostazioni (le rimuove).") { overrideAll = true }
                } label: {
                    HStack {
                        Text(overrideAll ? "anche per i file che hanno le proprie impostazioni (le rimuove)."
                                         : "ma escludendo quei file che hanno già le proprie impostazioni.")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
                }
            }
        }
        .padding(20)
    }

    private func valueEditor(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(title)).font(.title3.weight(.semibold))
            HStack(spacing: 20) {
                stepButton("–") { value.wrappedValue = max(range.lowerBound, (value.wrappedValue - 0.05).roundedTo(0.01)) }
                TextField("", value: value, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .frame(maxWidth: 130)
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary).frame(height: 1) }
                stepButton("+") { value.wrappedValue = min(range.upperBound, (value.wrappedValue + 0.05).roundedTo(0.01)) }
            }
            Slider(value: Binding(get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) },
                                  set: { value.wrappedValue = $0.roundedTo(0.01) }),
                   in: range)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }

    private func stepButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L(title))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 60, height: 46)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(uiColor: .systemGray4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .frame(width: 104, height: 46)
                .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
                .overlay(Rectangle().stroke(selected ? Color.accentColor : Color(uiColor: .systemGray4), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func scopeButton(_ title: String, selected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L(title))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(enabled ? 1 : 0.4))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
                .overlay(Rectangle().stroke(selected ? Color.accentColor : Color(uiColor: .systemGray4), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func squareButton(systemImage: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 46)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(uiColor: .systemGray4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let sp = settings.speedAndPitch(for: trackID)
        speed = sp.speed
        pitchRatio = pow(2, sp.pitch / 12).roundedTo(0.01)
        onlyThisFile = sp.perFile
    }

    private func commit() {
        let semitones = 12 * log2(max(0.01, pitchRatio))
        let clampedSpeed = min(3, max(0.25, speed))
        if onlyThisFile, let id = trackID {
            settings.fileSpeeds[id] = [clampedSpeed, semitones]
        } else {
            if let id = trackID, settings.fileSpeeds[id] != nil, !overrideAll {
                // Il brano attuale ha le sue impostazioni: restano.
            }
            if overrideAll { settings.fileSpeeds = [:] }
            settings.speed = clampedSpeed
            settings.pitch = semitones
        }
    }
}

/// La finestra di velocità/tono aperta fuori dalle Impostazioni (In riproduzione, menù dei brani).
struct SpeedPitchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            SpeedPitchDialog { dismiss() }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private extension Double {
    func roundedTo(_ step: Double) -> Double { (self / step).rounded() * step }
}

// MARK: - Focus audio

struct AudioFocusDialog: View {
    @EnvironmentObject private var settings: AppSettings

    private static let levels = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Focus audio").font(.title3.weight(.semibold))
            GeometryReader { geo in
                let w = geo.size.width
                let step = w / CGFloat(Self.levels - 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.accentColor).frame(height: 3)
                    ForEach(0..<Self.levels, id: \.self) { i in
                        Circle().fill(Color.primary.opacity(0.7)).frame(width: 7, height: 7)
                            .offset(x: CGFloat(i) * step - 3.5)
                    }
                    Circle().fill(Color.accentColor).frame(width: 26, height: 26)
                        .overlay(Circle().fill(Color.primary.opacity(0.7)).frame(width: 7, height: 7))
                        .offset(x: CGFloat(settings.audioFocus) * step - 13)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let level = Int((v.location.x / max(step, 1)).rounded())
                    settings.audioFocus = max(0, min(Self.levels - 1, level))
                })
            }
            .frame(height: 30)
            .padding(.horizontal, 10)

            Text("Livello \(settings.audioFocus)").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 14) {
                switch settings.audioFocus {
                case 0:
                    point("Continua a suonare insieme alle altre app (video, giochi, altre app di musica).")
                    point("Le chiamate interrompono comunque la musica: su iPad non si può evitare.")
                    resumeCheckbox
                case 1:
                    point("Interrompi musica durante le chiamate.")
                    point("Interrompi musica quando un'altra app inizia a suonare, e non riprendere da sola.")
                    point("Gli audio brevi (notifiche, navigatore, Siri) abbassano solo il volume: lo decide iPadOS.", small: true)
                default:
                    point("Interrompi musica durante le chiamate.")
                    resumeCheckbox
                    point("Interrompi musica quando un'altra app inizia a suonare e riprendi quando ha finito (se iPadOS lo permette).")
                    point("Gli audio brevi (notifiche, navigatore, Siri) abbassano solo il volume: lo decide iPadOS.", small: true)
                }
            }
        }
        .padding(28)
    }

    private var resumeCheckbox: some View {
        Button { settings.resumeAfterCall.toggle() } label: {
            HStack(spacing: 14) {
                CheckMark(checked: settings.resumeAfterCall)
                Text("Riprendi al termine della chiamata").foregroundStyle(Color.primary)
            }
            .padding(.leading, 30)
        }
        .buttonStyle(.plain)
    }

    private func point(_ text: String, small: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !small { Text("✓") }
            Text(L(text))
        }
        .font(small ? .footnote : .body)
        .foregroundStyle(small ? Color.secondary : Color.primary)
    }
}

// MARK: - Equalizzatore di AuguMusic (impostazioni)

struct EqualizerSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showPreset = false

    static let reverbPresets = ["Stanza piccola", "Stanza media", "Stanza grande", "Sala media", "Sala grande", "Cattedrale", "Piastra"]

    var body: some View {
        SettingsPage(title: "Equalizzatore di AuguMusic") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sperimentale")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 72)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                    SettingsToggleRow(title: "Effetti di riverbero", isOn: $settings.reverbEnabled)
                    if settings.reverbEnabled {
                        SettingsRow(title: "Tipo di riverbero",
                                    subtitle: Self.reverbPresets[max(0, min(Self.reverbPresets.count - 1, settings.reverbPreset))]) {
                            showPreset = true
                        }
                        SettingsSliderRow(title: "Quantità di riverbero", value: $settings.reverbMix, range: 0...100, step: 1) {
                            "\(Int($0))%"
                        }
                    }
                }
            }
        }
        .settingsDialog(isPresented: $showPreset) {
            RadioDialog(title: "Tipo di riverbero",
                        options: Self.reverbPresets.enumerated().map { ChoiceOption(id: "\($0.offset)", label: $0.element) },
                        selection: Binding(get: { "\(settings.reverbPreset)" }, set: { settings.reverbPreset = Int($0) ?? 1 })) {
                showPreset = false
            }
        }
    }
}

// MARK: - ReplayGain

struct ReplayGainSettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var store = ReplayGainStore.shared
    @State private var showMode = false
    @State private var showAuto = false
    @State private var editPreamp: PreampKind?

    enum PreampKind: Identifiable {
        case withRG, withoutRG
        var id: Int { self == .withRG ? 0 : 1 }
    }

    static let modeOptions = [
        ChoiceOption(id: "off", label: "spento"),
        ChoiceOption(id: "track", label: "Track gain", detail: "(Riproduce tutti i brani allo stesso volume audio.)"),
        ChoiceOption(id: "album", label: "Album gain",
                     detail: "(Riproduce tutti gli album allo stesso volume audio. Preserva la differenza di volume audio delle canzoni all'interno di ogni album.)"),
    ]
    static let autoOptions = [
        ChoiceOption(id: "off", label: "spento"),
        ChoiceOption(id: "tags", label: "Preferisci i tag RG incorporati"),
        ChoiceOption(id: "analyze", label: "Analizza il file audio e calcola RG"),
    ]

    var body: some View {
        let on = settings.replayGain != .off
        let total = library.tracks.count
        let withTrack = library.tracks.filter { store.trackGain($0) != nil }.count
        let withAlbum = library.tracks.filter { store.albumGain($0) != nil }.count
        SettingsPage(title: "ReplayGain") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "Modalità ReplayGain", subtitle: settings.replayGain.label) { showMode = true }
                    SettingsRow(title: "Leggi/Calcola RG", subtitle: "Track gain: \(withTrack)/\(total) • Album gain: \(withAlbum)/\(total)") {
                        nav.path.append(.replayGainCalc)
                    }
                    SettingsRow(title: "Leggi/calcola automaticamente il RG della canzone corrente e la canzone successiva",
                                subtitle: Self.autoOptions.first { $0.id == settings.rgAuto }?.label, enabled: on) { showAuto = true }
                    SettingsRow(title: "Preamp per file con RG", subtitle: String(format: "%.1f dB", settings.replayGainPreamp), enabled: on) {
                        editPreamp = .withRG
                    }
                    SettingsRow(title: "Preamp per file senza RG", subtitle: String(format: "%.1f dB", settings.replayGainPreampNoRG), enabled: on) {
                        editPreamp = .withoutRG
                    }
                }
            }
        }
        .settingsDialog(isPresented: $showMode) {
            RadioDialog(title: "ReplayGain", options: Self.modeOptions,
                        selection: Binding(get: { settings.replayGain.rawValue },
                                           set: { settings.replayGain = ReplayGainMode(rawValue: $0) ?? .off })) { showMode = false }
        }
        .settingsDialog(isPresented: $showAuto) {
            RadioDialog(title: "Leggi/calcola automaticamente il RG della canzone corrente e la canzone successiva",
                        options: Self.autoOptions, selection: $settings.rgAuto) { showAuto = false }
        }
        .settingsDialog(isPresented: Binding(get: { editPreamp != nil }, set: { if !$0 { editPreamp = nil } })) {
            if let kind = editPreamp {
                NumberInputDialog(
                    title: kind == .withRG ? "Preamp per file con RG (dB)" : "Preamp per file senza RG (dB)",
                    message: kind == .withRG
                        ? "Consigliato per prevenire il \"ritaglio digitale\" e preservare la \"gamma dinamica\":\nPer la maggior parte dei tipi di musica: ≤ 0 dB\nPer una musica altamente dinamica: ≤ −14 dB"
                        : nil,
                    value: kind == .withRG ? settings.replayGainPreamp : settings.replayGainPreampNoRG,
                    range: -24...24
                ) { newValue in
                    if let newValue {
                        if kind == .withRG { settings.replayGainPreamp = newValue } else { settings.replayGainPreampNoRG = newValue }
                    }
                    editPreamp = nil
                }
            }
        }
    }
}

/// Finestra con un numero da scrivere (CANCELLA / OK).
struct NumberInputDialog: View {
    let title: String
    var message: String? = nil
    let value: Double
    let range: ClosedRange<Double>
    var decimals = 1
    let done: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L(title)).font(.title3.weight(.semibold))
            if let message {
                Text(L(message)).font(.subheadline).foregroundStyle(.secondary)
            }
            TextField("", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .focused($focused)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.accentColor).frame(height: 2) }
            HStack(spacing: 40) {
                Spacer()
                Button("CANCELLA") { done(nil) }
                Button("OK") {
                    let v = Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-"))
                    done(v.map { min(range.upperBound, max(range.lowerBound, $0)) })
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
        }
        .padding(26)
        .onAppear {
            text = String(format: "%.\(decimals)f", value)
            focused = true
        }
    }
}

// MARK: - Leggi/Calcola RG

struct ReplayGainCalcPage: View {
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var calc = ReplayGainCalculator.shared
    @AppStorage("rgCalcAlbum") private var album = false
    @AppStorage("rgCalcReload") private var reload = false
    @AppStorage("rgCalcPreferTags") private var preferTags = false

    var body: some View {
        SettingsPage(title: "Leggi/Calcola RG") {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("\(library.tracks.count) file audio")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .underline()
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            CheckMark(checked: true).opacity(0.4)
                            Text("Track gain").foregroundStyle(.secondary)
                        }
                        Button { album.toggle() } label: {
                            HStack(spacing: 16) {
                                CheckMark(checked: album)
                                Text("Album gain").foregroundStyle(Color.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    choiceBox(title: "Se il valore RG è già noto:",
                              options: [("Salta", !reload, { reload = false }), ("Ricaricare", reload, { reload = true })])
                    choiceBox(title: "Se sono disponibili tag RG incorporati:",
                              options: [("Analizza il file audio e calcola RG", !preferTags, { preferTags = false }),
                                        ("Preferisci i tag RG incorporati", preferTags, { preferTags = true })])
                    if calc.running {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: Double(calc.done), total: Double(max(calc.total, 1)))
                            Text("Analizzo \(calc.done)/\(calc.total)…").font(.subheadline).foregroundStyle(.secondary)
                            Button("INTERROMPI") { calc.cancel() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        Button(action: start) {
                            Text("LEGGI/CALCOLA RG")
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                        if let result = calc.lastResult {
                            Text(result).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("I valori calcolati restano nell'app: i file non vengono modificati. L'analisi legge tutto il file, quindi con tanti brani ci vuole un po'.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(26)
            }
        }
    }

    private func choiceBox(title: String, options: [(String, Bool, () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L(title)).font(.title3).foregroundStyle(Color.primary.opacity(0.8))
            ForEach(options.indices, id: \.self) { i in
                Button(action: options[i].2) {
                    HStack(spacing: 14) {
                        RadioMark(selected: options[i].1)
                        Text(options[i].0).foregroundStyle(Color.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
    }

    private func start() {
        let albums = library.groups(of: .album).map { library.tracks(for: $0.trackIDs) }
        calc.run(tracks: library.tracks, albums: albums, library: library,
                 options: .init(album: album, reloadKnown: reload, preferTags: preferTags))
    }
}
