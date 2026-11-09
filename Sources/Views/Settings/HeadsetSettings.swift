import SwiftUI

// MARK: - Auricolare, Bluetooth e altoparlanti

struct HeadsetSettingsPage: View {
    @EnvironmentObject private var nav: SettingsNav
    @AppStorage(Prefs.pauseOnDisconnect) private var pauseOnDisconnect = true
    @AppStorage(Prefs.resumeOnlyAfterDisconnect) private var onlyAfterDisconnect = false
    @AppStorage(Prefs.resumeBluetooth) private var resumeBluetooth = false
    @AppStorage(Prefs.resumeWired) private var resumeWired = false
    @State private var showDelays = false
    @State private var showNote = false

    var body: some View {
        SettingsPage(title: "Auricolare, Bluetooth e altoparlanti") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Interrompi quando disconnetti")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 72)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                    SettingsToggleRow(title: "Interrompi quando disconnetti",
                                      subtitle: "Interrompi riproduzione quando cuffie, speaker o Bluetooth sono disconnessi",
                                      isOn: $pauseOnDisconnect)

                    SettingsSectionHeader(title: "Riprendi quando ti connetti")
                    SettingsCheckRow(title: "Riprendi solo se messo in pausa dalla disconnessione prima", isOn: $onlyAfterDisconnect,
                                     enabled: resumeBluetooth || resumeWired)
                    SettingsToggleRow(title: "Riprendi quando il bluetooth si collega", isOn: $resumeBluetooth)
                    SettingsToggleRow(title: "Riprendi quando si collegano cuffie/altoparlanti cablati", isOn: $resumeWired)

                    SettingsSectionHeader(title: "Prevenire la riproduzione automatica indesiderata")
                    SettingsRow(title: "Prevenire la riproduzione automatica indesiderata") { nav.path.append(.preventAutoplay) }

                    SettingsSectionHeader(title: "Bottone microfono cuffie")
                    SettingsRow(title: "Azione a doppia pressione del pulsante dell'auricolare", subtitle: "Prossimo brano (decide iPadOS)",
                                enabled: false) {}
                    SettingsRow(title: "Azione a tripla pressione del pulsante dell'auricolare", subtitle: "Brano precedente (decide iPadOS)",
                                enabled: false) {}
                    SettingsRow(title: "Tieni premuto il pulsante dell'auricolare per andare avanti veloce, se le cuffie lo permettono",
                                systemIcon: "forward.fill", enabled: false) {}
                    SettingsRow(title: "Tocca qui per conoscere i ritardi consentiti tra due pressioni consecutive del pulsante dell'auricolare.",
                                systemIcon: "info.circle") { showDelays = true }
                    SettingsRow(title: "Nota: su iPad le azioni del pulsante non si possono cambiare. Premi per leggere le ragioni.",
                                systemIcon: "exclamationmark.triangle.fill") { showNote = true }
                }
                .padding(.bottom, 40)
            }
        }
        .settingsDialog(isPresented: $showDelays) {
            InfoDialog(title: "Ritardi tra le pressioni",
                       text: "Su iPad il tempo concesso tra una pressione e l'altra lo decide iPadOS, non l'app: in genere bisogna premere di nuovo entro circa mezzo secondo perché la doppia o tripla pressione venga riconosciuta.") {
                showDelays = false
            }
        }
        .settingsDialog(isPresented: $showNote) {
            InfoDialog(title: "Perché non si possono cambiare?",
                       text: "Su Android l'app riceve ogni singola pressione del pulsante e decide cosa fare. Su iPad invece è iPadOS a contare le pressioni e manda all'app solo il comando finale: 1 pressione = play/pausa, 2 = brano successivo, 3 = brano precedente.\n\nQuesti comandi sono identici a quelli dei tasti della schermata di blocco e del Centro di Controllo, quindi cambiarli cambierebbe anche quei tasti. Per questo le due azioni restano fisse.") {
                showNote = false
            }
        }
    }
}

struct PreventAutoplayPage: View {
    @AppStorage(Prefs.preventAutoplay) private var enabled = true
    @AppStorage(Prefs.strictAutoplay) private var strict = true
    @State private var showHelp = false

    var body: some View {
        SettingsPage(title: "Prevenire la riproduzione automatica indesiderata") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: "A cosa serve questa funzione?", systemIcon: "questionmark.circle") { showHelp = true }
                    SettingsToggleRow(title: "Prevenire la riproduzione automatica indesiderata", isOn: $enabled)
                    SettingsCheckRow(title: "Restrizioni più severe",
                                     subtitle: "Ignora i \"comandi di riproduzione\" che arrivano mentre l'app è in background ed è in pausa da più di 5 minuti. Con questa opzione attiva, in quel caso non potrai far ripartire la musica dalle cuffie o dall'auto: apri prima l'app.",
                                     isOn: $strict, enabled: enabled)
                }
            }
        }
        .settingsDialog(isPresented: $showHelp) {
            InfoDialog(title: "Prevenire la riproduzione automatica indesiderata",
                       text: "A cosa serve questa funzione?\n\nCerte auto, cuffie Bluetooth o accessori USB mandano da soli un comando \"play\" quando si collegano o subito prima di scollegarsi. L'app non può sapere se quel comando l'hai dato tu o il dispositivo, e quindi farebbe partire la musica.\n\nSe ti succede che la musica parte da sola quando colleghi o scolleghi l'iPad da un dispositivo, questa funzione ti aiuta: per alcuni secondi dopo ogni collegamento o scollegamento, i comandi \"play\" che arrivano dall'esterno vengono ignorati.") {
                showHelp = false
            }
        }
    }
}

/// Finestra con un testo lungo e il tasto FATTO.
struct InfoDialog: View {
    let title: String
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(26)
            ScrollView {
                Text(text)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
            }
            .frame(maxHeight: 480)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("FATTO", action: close)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
            }
            .padding(26)
        }
    }
}
