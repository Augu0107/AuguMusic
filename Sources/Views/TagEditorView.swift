import PhotosUI
import SFBAudioEngine
import SwiftUI
import UniformTypeIdentifiers

enum TagKey: String, CaseIterable, Identifiable {
    case title, artist, album, albumArtist, composer, genre, year, track, disc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Titolo"
        case .artist: "Artista"
        case .album: "Album"
        case .albumArtist: "Artista album"
        case .composer: "Compositore"
        case .genre: "Genere"
        case .year: "Anno"
        case .track: "Traccia"
        case .disc: "Disco"
        }
    }

    var isNumeric: Bool { self == .year || self == .track || self == .disc }

    /// Nel modificare più brani insieme alcuni campi non hanno senso.
    var allowsMultiple: Bool { self != .title && self != .track }
}

private enum ArtworkChange {
    case keep
    case remove
    case replace(Data)
}

/// Valori dei tag letti da un file (Sendable, così può passare tra thread).
private struct TagValues: Sendable {
    var values: [String: String] = [:]
    var lyrics = ""
}

struct TagEditorView: View {
    let trackIDs: [String]

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss

    @State private var values: [TagKey: String] = [:]
    @State private var originals: [TagKey: String] = [:]
    @State private var mixed: Set<TagKey> = []
    @State private var lyrics = ""
    @State private var originalLyrics = ""
    @State private var artwork: ArtworkChange = .keep
    @State private var newArtworkImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showImageImporter = false
    @State private var loading = true
    @State private var saving = false
    @State private var errorText: String?

    private var tracks: [Track] { library.tracks(for: trackIDs) }
    private var isSingle: Bool { trackIDs.count == 1 }
    private var keys: [TagKey] { TagKey.allCases.filter { isSingle || $0.allowsMultiple } }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    HStack { Spacer(); ProgressView("Leggo i tag…"); Spacer() }
                } else {
                    artworkSection
                    Section(isSingle ? "Tag" : "Tag comuni a \(trackIDs.count) brani") {
                        ForEach(keys) { key in
                            fieldRow(key)
                        }
                    }
                    if isSingle {
                        Section("Testo") {
                            TextEditor(text: $lyrics)
                                .frame(minHeight: 160)
                                .font(.callout)
                        }
                    }
                    if let errorText {
                        Section { Text(errorText).foregroundStyle(.red) }
                    }
                    Section {
                        Text(isSingle
                             ? "Le modifiche vengono scritte direttamente nel file."
                             : "Lascia vuoto un campo con \"valori diversi\" per non toccarlo. Quello che scrivi viene applicato a tutti i brani.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isSingle ? "Modifica tag" : "Modifica \(trackIDs.count) brani")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Salva") { save() }
                            .disabled(loading || !hasChanges)
                    }
                }
            }
            .task { await loadValues() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { setNewArtwork(data) }
                }
            }
            .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { setNewArtwork(data) }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    // MARK: Parti

    private var artworkSection: some View {
        Section("Copertina") {
            HStack(spacing: 16) {
                Group {
                    switch artwork {
                    case .keep:
                        ArtworkView(track: tracks.first, maxPixel: 400, cornerRadius: 10)
                    case .remove:
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.2))
                            .overlay { Image(systemName: "photo.badge.minus").font(.title).foregroundStyle(.secondary) }
                    case .replace:
                        if let image = newArtworkImage {
                            Image(uiImage: image).resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Dalle foto", systemImage: "photo")
                    }
                    Button { showImageImporter = true } label: {
                        Label("Da File", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        artwork = .remove
                        newArtworkImage = nil
                    } label: {
                        Label("Rimuovi", systemImage: "trash")
                    }
                    if case .keep = artwork {} else {
                        Button { artwork = .keep; newArtworkImage = nil } label: {
                            Label("Annulla modifica", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func fieldRow(_ key: TagKey) -> some View {
        HStack {
            Text(key.label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            TextField(mixed.contains(key) ? "Valori diversi" : key.label,
                      text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }))
                .keyboardType(key.isNumeric ? .numberPad : .default)
                .textInputAutocapitalization(key.isNumeric ? .never : .words)
                .autocorrectionDisabled()
        }
    }

    private var hasChanges: Bool {
        if case .keep = artwork {} else { return true }
        if isSingle && lyrics != originalLyrics { return true }
        return keys.contains { (values[$0] ?? "") != (originals[$0] ?? "") }
    }

    private func setNewArtwork(_ data: Data) {
        guard let image = UIImage(data: data) else {
            errorText = "Immagine non valida"
            return
        }
        let maxSide: CGFloat = 1200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.9) else { return }
        newArtworkImage = resized
        artwork = .replace(jpeg)
    }

    // MARK: Lettura

    private func loadValues() async {
        let urls = tracks.compactMap { library.url(for: $0) }
        let read: [TagValues] = await Task.detached(priority: .userInitiated) {
            urls.map { url -> TagValues in
                var out = TagValues()
                guard let m = MetadataReader.openTagLibFile(url)?.metadata else { return out }
                out.values[TagKey.title.rawValue] = m.title ?? ""
                out.values[TagKey.artist.rawValue] = m.artist ?? ""
                out.values[TagKey.album.rawValue] = m.albumTitle ?? ""
                out.values[TagKey.albumArtist.rawValue] = m.albumArtist ?? ""
                out.values[TagKey.composer.rawValue] = m.composer ?? ""
                out.values[TagKey.genre.rawValue] = m.genre ?? ""
                out.values[TagKey.year.rawValue] = m.releaseDate ?? ""
                out.values[TagKey.track.rawValue] = m.trackNumber.map { String($0) } ?? ""
                out.values[TagKey.disc.rawValue] = m.discNumber.map { String($0) } ?? ""
                out.lyrics = m.lyrics ?? ""
                return out
            }
        }.value

        var vals: [TagKey: String] = [:]
        var mix: Set<TagKey> = []
        for key in TagKey.allCases {
            let all = read.map { $0.values[key.rawValue] ?? "" }
            let unique = Set(all)
            if unique.count <= 1 {
                vals[key] = all.first ?? ""
            } else {
                vals[key] = ""
                mix.insert(key)
            }
        }
        values = vals
        originals = vals
        mixed = mix
        lyrics = read.first?.lyrics ?? ""
        originalLyrics = lyrics
        loading = false
    }

    // MARK: Salvataggio

    private func save() {
        var edits: [String: String] = [:]
        for key in keys where (values[key] ?? "") != (originals[key] ?? "") {
            edits[key.rawValue] = (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let newLyrics: String? = (isSingle && lyrics != originalLyrics) ? lyrics : nil
        var artworkData: Data?
        var removeArtwork = false
        switch artwork {
        case .keep: break
        case .remove: removeArtwork = true
        case .replace(let data): artworkData = data
        }
        let ids = trackIDs
        let urls = tracks.compactMap { library.url(for: $0) }
        let removeArt = removeArtwork
        let newArt = artworkData
        let fieldEdits = edits
        let editedCurrent = player.loadedTrackID.map { ids.contains($0) } ?? false
        saving = true
        errorText = nil

        Task {
            let failures: [String] = await Task.detached(priority: .userInitiated) {
                var failed: [String] = []
                for url in urls {
                    guard let file = MetadataReader.openTagLibFile(url) else {
                        failed.append(url.lastPathComponent)
                        continue
                    }
                    let m = file.metadata
                    for (raw, value) in fieldEdits {
                        let v: String? = value.isEmpty ? nil : value
                        switch TagKey(rawValue: raw) {
                        case .title: m.title = v
                        case .artist: m.artist = v
                        case .album: m.albumTitle = v
                        case .albumArtist: m.albumArtist = v
                        case .composer: m.composer = v
                        case .genre: m.genre = v
                        case .year: m.releaseDate = v
                        case .track: m.trackNumber = v.flatMap { Int($0) }
                        case .disc: m.discNumber = v.flatMap { Int($0) }
                        case .none: break
                        }
                    }
                    if let newLyrics { m.lyrics = newLyrics.isEmpty ? nil : newLyrics }
                    if removeArt { m.removeAllAttachedPictures() }
                    if let newArt {
                        m.removeAllAttachedPictures()
                        m.attachPicture(AttachedPicture(imageData: newArt, type: .frontCover))
                    }
                    do {
                        try file.writeMetadata()
                    } catch {
                        failed.append(url.lastPathComponent)
                    }
                }
                return failed
            }.value

            await library.refresh(trackIDs: ids)
            if editedCurrent { player.reloadCurrentTrack() }
            saving = false
            if failures.isEmpty {
                ui.showToast(ids.count == 1 ? "Tag salvati" : "Tag salvati in \(ids.count) brani")
                dismiss()
            } else {
                errorText = "Non sono riuscita a scrivere: " + failures.prefix(5).joined(separator: ", ")
            }
        }
    }
}
