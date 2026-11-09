import SwiftUI

// Pezzi grafici delle Impostazioni, nello stile di Musicolet.

/// Pagine raggiungibili dentro le Impostazioni.
enum SettingsDest: Hashable {
    case interface, theme, optionsMenus
    case audio, eqSettings, replayGain, replayGainCalc
    case library, scanFolders, excludedFolders, libraryAdvanced, hideExtra
    case headset, preventAutoplay, widget
    case advanced, csvExport, advancedShuffle, ignoreWords
    case menuQueue, menuNowPlaying, menuFolders, menuAlbums, menuArtists, menuGenres, menuPlaylists

    var title: String {
        switch self {
        case .interface: "Interfaccia"
        case .audio: "Audio"
        case .library: "Libreria brani e tag"
        case .headset: "Auricolare, Bluetooth e altoparlanti"
        case .widget: "Widget HomeScreen"
        case .advanced: "Avanzati"
        case .csvExport: "Esporta CSV"
        case .advancedShuffle: "Shuffle avanzato"
        case .ignoreWords: "Ignora alcune parole all'inizio"
        case .preventAutoplay: "Prevenire la riproduzione automatica indesiderata"
        case .scanFolders: "Cartelle da analizzare"
        case .excludedFolders: "Cartelle escluse"
        case .libraryAdvanced: "Avanzati"
        case .hideExtra: "Nascondi contenuti extra dai tag"
        case .eqSettings: "Equalizzatore di AuguMusic"
        case .replayGain: "ReplayGain"
        case .replayGainCalc: "Leggi/Calcola RG"
        case .theme: "Tema"
        case .optionsMenus: "Opzioni e menù"
        case .menuQueue: "Code"
        case .menuNowPlaying: "In riproduzione"
        case .menuFolders: "Cartelle"
        case .menuAlbums: "Album"
        case .menuArtists: "Artisti"
        case .menuGenres: "Genere"
        case .menuPlaylists: "Playlist"
        }
    }
}

@MainActor
final class SettingsNav: ObservableObject {
    @Published var path: [SettingsDest] = []
}

// MARK: - Barra in alto

/// Barra grigia: ← Titolo 🔍. Con la lente il titolo diventa il campo per cercare un'impostazione.
struct SettingsHeader: View {
    let title: String
    let onBack: () -> Void
    @Binding var searching: Bool
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 18) {
            Button {
                if searching {
                    searching = false
                    query = ""
                } else {
                    onBack()
                }
            } label: {
                Image(systemName: "arrow.left")
                    .font(.title3.weight(.medium))
                    .frame(width: 32, height: 44)
            }
            if searching {
                TextField("Cerca un'impostazione", text: $query)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onAppear { focused = true }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark").font(.title3).frame(width: 32, height: 44)
                    }
                }
            } else {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button { searching = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3.weight(.medium))
                        .frame(width: 32, height: 44)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(0.75))
        .padding(.horizontal, 16)
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGray6))
    }
}

/// Contenitore di una pagina: barra in alto, contenuto e (mentre cerchi) i risultati sopra.
struct SettingsPage<Content: View>: View {
    let title: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @EnvironmentObject private var nav: SettingsNav
    @Environment(\.dismiss) private var dismiss
    @State private var searching = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: title, onBack: { (onBack ?? defaultBack)() }, searching: $searching, query: $query)
            ZStack(alignment: .top) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if searching && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SettingsSearchResults(query: query) { entry in
                        searching = false
                        query = ""
                        nav.path = entry.path
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    private func defaultBack() {
        if nav.path.isEmpty { dismiss() } else { nav.path.removeLast() }
    }
}

// MARK: - Righe

/// Riga semplice (titolo e, sotto, il valore attuale in grigio). L'icona è facoltativa.
struct SettingsRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: AppGlyph? = nil
    var systemIcon: String? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Group {
                    if let icon {
                        AppIconView(glyph: icon, size: 26)
                    } else if let systemIcon {
                        Image(systemName: systemIcon).font(.title2)
                    } else {
                        Color.clear
                    }
                }
                .foregroundStyle(Color.secondary)
                .frame(width: 72, alignment: .center)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.6))
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary.opacity(enabled ? 1 : 0.6))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 16)
            }
            .padding(.vertical, 16)
            .padding(.trailing, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Riga con l'interruttore a destra.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.primary.opacity(0.8))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.accentColor)
        }
        .padding(.vertical, 14)
        .padding(.trailing, 20)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// Riga con cursore (es. "Sfondo sfocato").
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let label: (Double) -> String

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 72)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.body)
                HStack(spacing: 16) {
                    Slider(value: $value, in: range, step: step)
                    Text(label(value))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
            .padding(.trailing, 20)
        }
        .padding(.vertical, 14)
    }
}

/// Separatore e intestazione arancione di una sezione.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineSeparator()
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.leading, 72)
                .padding(.top, 22)
                .padding(.bottom, 6)
        }
    }
}

// MARK: - Finestre di scelta

struct ChoiceOption: Identifiable, Hashable {
    let id: String
    let label: String
    var detail: String? = nil
}

/// Finestra al centro dello schermo con sfondo scuro; toccando fuori si chiude.
struct DialogOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            content()
                .frame(maxWidth: 460)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(28)
        }
        .transition(.opacity)
    }
}

extension View {
    func settingsDialog<D: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> D) -> some View {
        overlay {
            if isPresented.wrappedValue {
                DialogOverlay(onDismiss: { isPresented.wrappedValue = false }, content: content)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isPresented.wrappedValue)
    }
}

struct DialogButtons: View {
    var reset: (() -> Void)? = nil
    var cancelTitle = "ANNULLA"
    let cancel: () -> Void
    var save: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 28) {
            if let reset { Button("RESET", action: reset) }
            Spacer()
            Button(cancelTitle, action: cancel)
            if let save { Button("SALVA", action: save) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.accentColor)
        .buttonStyle(.plain)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
    }
}

/// Scelta singola con i pallini (come le finestre di Musicolet).
struct RadioDialog: View {
    let title: String
    let options: [ChoiceOption]
    @Binding var selection: String
    var resetValue: String? = nil
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options) { option in
                        Button {
                            selection = option.id
                            close()
                        } label: {
                            HStack(spacing: 24) {
                                RadioMark(selected: option.id == selection)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .foregroundStyle(Color.primary.opacity(0.8))
                                    if let detail = option.detail {
                                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 26)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
            DialogButtons(reset: resetValue.map { value in { selection = value; close() } }, cancelTitle: "CANCELLA", cancel: close)
        }
    }
}

struct RadioMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(selected ? Color.accentColor : Color.secondary, lineWidth: 2)
                .frame(width: 22, height: 22)
            if selected {
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
            }
        }
    }
}

struct CheckMark: View {
    let checked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(checked ? Color.accentColor : Color.clear)
            RoundedRectangle(cornerRadius: 3)
                .stroke(checked ? Color.accentColor : Color.secondary, lineWidth: 2)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// Scelta multipla con le caselle e i tasti ANNULLA / SALVA.
struct CheckboxDialog: View {
    let title: String
    let options: [ChoiceOption]
    @Binding var stored: String
    var resetValue: String? = nil
    let close: () -> Void
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options) { option in
                        Button {
                            if selected.contains(option.id) { selected.remove(option.id) } else { selected.insert(option.id) }
                        } label: {
                            HStack(spacing: 24) {
                                CheckMark(checked: selected.contains(option.id))
                                Text(option.label)
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(Color.primary.opacity(0.8))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 26)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 500)
            .fixedSize(horizontal: false, vertical: true)
            DialogButtons(reset: resetValue.map { value in { selected = value.csvItems } },
                          cancelTitle: "CANCELLA",
                          cancel: close,
                          save: {
                              stored = String.csv(selected)
                              close()
                          })
        }
        .onAppear { selected = stored.csvItems }
    }
}
