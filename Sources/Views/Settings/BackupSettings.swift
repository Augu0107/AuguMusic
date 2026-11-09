import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup/Ripristino

struct BackupSettingsPage: View {
    @EnvironmentObject private var ui: UIState
    @AppStorage(Prefs.autoBackup) private var autoBackup = true
    @State private var showRestoreList = false
    @State private var showImporter = false
    @State private var pending: BackupManager.Contents?
    @State private var pendingName = ""
    @State private var exportURL: URL?
    @State private var errorText: String?

    var body: some View {
        SettingsPage(title: "Backup/Ripristino") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Backup manuale")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 72)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                    SettingsRow(title: "Esegui il backup ora",
                                subtitle: "Esegui il backup delle playlist, dei preferiti, del conteggio delle riproduzioni, delle code e delle impostazioni di AuguMusic.") {
                        if let url = BackupManager.create() {
                            exportURL = url
                        } else {
                            errorText = "Non sono riuscita a creare il backup."
                        }
                    }

                    SettingsSectionHeader(title: "Backup automatico")
                    SettingsToggleRow(title: "Backup automatico", subtitle: "Una volta al giorno, tiene gli ultimi 5", isOn: $autoBackup)
                    SettingsRow(title: "Posizione", subtitle: "Sull'iPad › AuguMusic › Backups", enabled: false) {}

                    SettingsSectionHeader(title: "Ripristinare")
                    SettingsRow(title: "Ripristina ora", subtitle: "Scegliere un backup da cui si desidera ripristinare qualcosa.") {
                        showRestoreList = true
                    }

                    SettingsSectionHeader(title: "Informazione")
                    SettingsRow(title: "Un backup non include i file audio. Contiene solo dati come playlist, Preferiti, conteggi di riproduzione, code e Impostazioni.",
                                systemIcon: "info.circle", enabled: false) {}
                }
                .padding(.bottom, 40)
            }
        }
        .settingsDialog(isPresented: $showRestoreList) {
            BackupListDialog(close: { showRestoreList = false },
                             pick: { url in
                                 showRestoreList = false
                                 load(url)
                             },
                             browse: {
                                 showRestoreList = false
                                 showImporter = true
                             })
        }
        .settingsDialog(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let contents = pending {
                RestoreDialog(name: pendingName, contents: contents) { pending = nil }
            }
        }
        .settingsDialog(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let url = exportURL {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Backup creato").font(.title3.weight(.semibold))
                    Text("Salvato come \"\(url.lastPathComponent)\" in File › Sull'iPad › AuguMusic › Backups.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 40) {
                        Spacer()
                        ShareLink(item: url) { Text("CONDIVIDI") }
                        Button("OK") { exportURL = nil }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
                .padding(26)
            }
        }
        .alert("Errore", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    private func load(_ url: URL) {
        guard let contents = BackupManager.open(url) else {
            errorText = "Questo file non sembra un backup di AuguMusic."
            return
        }
        pendingName = url.deletingPathExtension().lastPathComponent
        pending = contents
    }
}

private struct BackupListDialog: View {
    let close: () -> Void
    let pick: (URL) -> Void
    let browse: () -> Void
    private let items = BackupManager.backups()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scegli un backup").font(.title3.weight(.semibold)).padding(26)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if items.isEmpty {
                        Text("Nessun backup nella cartella Backups.").foregroundStyle(.secondary).padding(.horizontal, 26)
                    }
                    ForEach(items, id: \.self) { url in
                        Button { pick(url) } label: {
                            HStack(spacing: 18) {
                                Image(systemName: "doc.zipper").font(.title3).foregroundStyle(.secondary)
                                Text(url.deletingPathExtension().lastPathComponent).foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 30) {
                Button("ALTRO FILE…", action: browse)
                Spacer()
                Button("CANCELLA", action: close)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .padding(26)
        }
    }
}

private struct RestoreDialog: View {
    let name: String
    let contents: BackupManager.Contents
    let close: () -> Void
    @State private var choice = BackupManager.RestoreChoice()
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(done ? "Ripristino completato" : "Cosa vuoi ripristinare?").font(.title3.weight(.semibold)).padding(26)
            if done {
                Text("Chiudi e riapri AuguMusic per vedere i dati ripristinati.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 26)
                HStack {
                    Spacer()
                    Button("CHIUDI L'APP") { exit(0) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                }
                .padding(26)
            } else {
                Text(name).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.bottom, 8)
                if contents.hasLibraryData {
                    check("Playlist e segnalibri", $choice.playlists)
                    check("Preferiti", $choice.favorites)
                    check("Conteggio delle riproduzioni", $choice.playCounts)
                }
                if contents.hasQueues { check("Code", $choice.queues) }
                if contents.hasSettings { check("Impostazioni", $choice.settings) }
                HStack(spacing: 40) {
                    Spacer()
                    Button("CANCELLA", action: close)
                    Button("RIPRISTINA") {
                        if !contents.hasQueues { choice.queues = false }
                        if !contents.hasSettings { choice.settings = false }
                        BackupManager.restore(contents, choice: choice)
                        done = true
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .padding(26)
            }
        }
    }

    private func check(_ title: String, _ value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: 24) {
                CheckMark(checked: value.wrappedValue)
                Text(title).foregroundStyle(Color.primary.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Aiuto ed info

struct HelpInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "arrow.left").font(.title2) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                ZStack {
                    Circle().fill(Color.accentColor).frame(width: 110, height: 110)
                    Image(systemName: "music.note").font(.system(size: 50, weight: .bold)).foregroundStyle(.white)
                }
                Text("AuguMusic").font(.largeTitle.weight(.semibold))
                Text(BackupManager.appVersion).foregroundStyle(.secondary)
                Text("Lettore musicale per iPad pensato per essere semplice, veloce e tutto offline, ispirato a Musicolet.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)

                infoBox(icon: "checkmark.seal", title: "Come è fatta") {
                    VStack(alignment: .leading, spacing: 8) {
                        point("Nessuna pubblicità, nessun account.")
                        point("Funziona solo con i tuoi file: non va mai su internet da sola.")
                        point("Nessun dato viene raccolto o inviato da nessuna parte.")
                        point("Le playlist, i preferiti e i conteggi restano sull'iPad (e nei backup che fai tu).")
                    }
                }
                infoBox(icon: "questionmark.circle", title: "Dove metto la musica?") {
                    Text("Nell'app File: Sull'iPad › AuguMusic. Oppure aggiungi una cartella qualsiasi (iCloud Drive, chiavetta, disco esterno) da Impostazioni › Libreria brani e tag › Cartelle da analizzare.")
                        .foregroundStyle(.secondary)
                }
                infoBox(icon: "star.square", title: "Credit") {
                    VStack(alignment: .leading, spacing: 8) {
                        point("Fatta da Chiara per uso personale.")
                        point("SFBAudioEngine (Stephen F. Booth) per leggere i formati audio.")
                        point("TagLib per leggere e scrivere i tag.")
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func infoBox<C: View>(icon: String, title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.title3.weight(.semibold))
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark").foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
