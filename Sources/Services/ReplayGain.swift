import AVFoundation
import Foundation
import SFBAudioEngine

// ReplayGain 2.0: misura la loudness (EBU R128, filtro K) e calcola il guadagno per arrivare a -18 LUFS.

/// Risultato dell'analisi di un file: potenza dei blocchi da 400 ms (servono anche per il guadagno album).
struct LoudnessBlocks: Sendable {
    var powers: [Double]
}

enum LoudnessAnalyzer {
    static let target = -18.0

    /// Loudness integrata (LUFS) di un insieme di blocchi, con i due "cancelli" della norma.
    static func loudness(_ powers: [Double]) -> Double? {
        let absGate = pow(10, (-70 + 0.691) / 10)
        let aboveAbs = powers.filter { $0 > absGate }
        guard !aboveAbs.isEmpty else { return nil }
        let relGate = aboveAbs.reduce(0, +) / Double(aboveAbs.count) * 0.1
        let gated = aboveAbs.filter { $0 > relGate }
        guard !gated.isEmpty else { return nil }
        return -0.691 + 10 * log10(gated.reduce(0, +) / Double(gated.count))
    }

    static func gain(_ powers: [Double]) -> Double? {
        loudness(powers).map { (target - $0 * 1).rounded(toPlaces: 2) }
    }

    /// Decodifica tutto il file e misura i blocchi. Lento: va chiamato fuori dal main thread.
    static func analyze(url: URL, cancelled: () -> Bool = { false }) -> LoudnessBlocks? {
        guard let reader = PCMReader(url: url) else { return nil }
        let rate = reader.format.sampleRate
        let channels = Int(reader.format.channelCount)
        guard rate > 0, channels > 0 else { return nil }
        var filters = (0..<channels).map { _ in KWeighting(sampleRate: rate) }
        let subBlock = max(1, Int(rate * 0.1))
        var subSums: [Double] = []
        var acc = 0.0
        var accCount = 0

        while let buffer = reader.next() {
            if cancelled() { return nil }
            guard let data = buffer.floatChannelData else { continue }
            let frames = Int(buffer.frameLength)
            for i in 0..<frames {
                var sum = 0.0
                for c in 0..<channels {
                    let y = filters[c].process(Double(data[c][i]))
                    sum += y * y
                }
                acc += sum
                accCount += 1
                if accCount == subBlock {
                    subSums.append(acc / Double(subBlock))
                    acc = 0
                    accCount = 0
                }
            }
        }
        // Blocchi da 400 ms che si sovrappongono del 75% (4 pezzi da 100 ms).
        guard subSums.count >= 4 else {
            return subSums.isEmpty ? nil : LoudnessBlocks(powers: [subSums.reduce(0, +) / Double(subSums.count)])
        }
        var powers: [Double] = []
        powers.reserveCapacity(subSums.count)
        for i in 0...(subSums.count - 4) {
            powers.append((subSums[i] + subSums[i + 1] + subSums[i + 2] + subSums[i + 3]) / 4)
        }
        return LoudnessBlocks(powers: powers)
    }
}

/// Filtro K (due biquad) per un canale.
private struct KWeighting {
    private var b1: (Double, Double, Double), a1: (Double, Double)
    private var b2: (Double, Double, Double), a2: (Double, Double)
    private var z1 = (0.0, 0.0), z2 = (0.0, 0.0)

    init(sampleRate fs: Double) {
        // Mensola sugli acuti
        var f0 = 1681.974450955533
        let g = 3.999843853973347
        var q = 0.7071752369554196
        var k = tan(Double.pi * f0 / fs)
        let vh = pow(10, g / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        b1 = ((vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0)
        a1 = (2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
        // Passa-alto
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / fs)
        a0 = 1 + k / q + k * k
        b2 = (1, -2, 1)
        a2 = (2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
    }

    mutating func process(_ x: Double) -> Double {
        // Forma diretta II trasposta
        let y1 = b1.0 * x + z1.0
        z1.0 = b1.1 * x - a1.0 * y1 + z1.1
        z1.1 = b1.2 * x - a1.1 * y1
        let y2 = b2.0 * y1 + z2.0
        z2.0 = b2.1 * y1 - a2.0 * y2 + z2.1
        z2.1 = b2.2 * y1 - a2.1 * y2
        return y2
    }
}

/// Legge un file audio a pezzi in float non interlacciato (Apple prima, poi SFBAudioEngine).
final class PCMReader {
    let format: AVAudioFormat
    private var file: AVAudioFile?
    private var decoder: AudioDecoder?
    private var converter: AVAudioConverter?
    private let chunk: AVAudioFrameCount = 65_536

    init?(url: URL) {
        if let f = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) {
            file = f
            format = f.processingFormat
            return
        }
        guard let dec = try? AudioDecoder(url: url, detectContentType: true), (try? dec.open()) != nil,
              let standard = AVAudioFormat(standardFormatWithSampleRate: dec.processingFormat.sampleRate,
                                           channels: dec.processingFormat.channelCount) else { return nil }
        decoder = dec
        format = standard
        converter = dec.processingFormat == standard ? nil : AVAudioConverter(from: dec.processingFormat, to: standard)
    }

    deinit { try? decoder?.close() }

    func next() -> AVAudioPCMBuffer? {
        if let file {
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return nil }
            do { try file.read(into: buf, frameCount: chunk) } catch { return nil }
            return buf.frameLength > 0 ? buf : nil
        }
        guard let dec = decoder, let raw = AVAudioPCMBuffer(pcmFormat: dec.processingFormat, frameCapacity: chunk) else { return nil }
        do { try dec.decode(into: raw, length: chunk) } catch { return nil }
        guard raw.frameLength > 0 else { return nil }
        guard let converter else { return raw }
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: raw.frameLength) else { return nil }
        do { try converter.convert(to: out, from: raw) } catch { return nil }
        return out
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10, Double(p))
        return (self * m).rounded() / m
    }
}

// MARK: - Valori calcolati

/// ReplayGain calcolati dall'app (non scritti nei file). Hanno la precedenza sui tag.
@MainActor
final class ReplayGainStore: ObservableObject {
    static let shared = ReplayGainStore()
    private static let fileName = "replaygain.json"

    struct Entry: Codable {
        var track: Double?
        var album: Double?
    }

    @Published private(set) var entries: [String: Entry] = [:]

    init() {
        entries = Storage.load([String: Entry].self, from: Self.fileName) ?? [:]
    }

    func trackGain(_ t: Track) -> Double? { entries[t.id]?.track ?? t.replayGainTrack }
    func albumGain(_ t: Track) -> Double? { entries[t.id]?.album ?? t.replayGainAlbum }

    func set(track: Double?, for id: String) {
        var e = entries[id] ?? Entry()
        e.track = track
        entries[id] = e
    }

    func set(album: Double?, for id: String) {
        var e = entries[id] ?? Entry()
        e.album = album
        entries[id] = e
    }

    func save() { Storage.save(entries, to: Self.fileName) }
}

// MARK: - Calcolo su tutta la libreria

@MainActor
final class ReplayGainCalculator: ObservableObject {
    static let shared = ReplayGainCalculator()

    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var lastResult: String?
    private var task: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    struct Options {
        var album: Bool
        var reloadKnown: Bool
        var preferTags: Bool
    }

    func cancel() {
        cancelFlag.set()
    }

    func run(tracks: [Track], albums: [[Track]], library: LibraryStore, options: Options) {
        guard !running else { return }
        let store = ReplayGainStore.shared
        running = true
        done = 0
        lastResult = nil
        let flag = CancelFlag()
        cancelFlag = flag

        // Brani da analizzare per il guadagno brano.
        var trackJobs: [(Track, URL)] = []
        for t in tracks {
            let known = store.trackGain(t) != nil
            if known && !options.reloadKnown { continue }
            if options.preferTags, let tag = t.replayGainTrack {
                store.set(track: tag, for: t.id)
                continue
            }
            if let url = library.url(for: t) { trackJobs.append((t, url)) }
        }
        // Album da analizzare per il guadagno album.
        var albumJobs: [[(Track, URL)]] = []
        if options.album {
            for album in albums {
                let known = album.allSatisfy { store.albumGain($0) != nil }
                if known && !options.reloadKnown { continue }
                if options.preferTags, album.allSatisfy({ $0.replayGainAlbum != nil }) {
                    for t in album { store.set(album: t.replayGainAlbum, for: t.id) }
                    continue
                }
                albumJobs.append(album.compactMap { t in library.url(for: t).map { (t, $0) } })
            }
        }
        let albumTrackIDs = Set(albumJobs.flatMap { $0.map(\.0.id) })
        let onlyTrackJobs = trackJobs.filter { !albumTrackIDs.contains($0.0.id) }
        total = onlyTrackJobs.count + albumJobs.reduce(0) { $0 + $1.count }
        store.save()
        let wantTrack = Set(trackJobs.map(\.0.id))

        task = Task { [weak self] in
            var analyzed = 0
            for (t, url) in onlyTrackJobs {
                if flag.isSet { break }
                let blocks = await Self.analyzeDetached(url, flag)
                if let blocks { store.set(track: LoudnessAnalyzer.gain(blocks.powers), for: t.id); analyzed += 1 }
                self?.done += 1
            }
            for album in albumJobs {
                if flag.isSet { break }
                var all: [Double] = []
                var perTrack: [(String, Double?)] = []
                for (t, url) in album {
                    if flag.isSet { break }
                    if let blocks = await Self.analyzeDetached(url, flag) {
                        all += blocks.powers
                        perTrack.append((t.id, LoudnessAnalyzer.gain(blocks.powers)))
                        analyzed += 1
                    }
                    self?.done += 1
                }
                if flag.isSet { break }
                let albumGain = LoudnessAnalyzer.gain(all)
                for (id, g) in perTrack {
                    store.set(album: albumGain, for: id)
                    if wantTrack.contains(id) || store.entries[id]?.track == nil { store.set(track: g, for: id) }
                }
                store.save()
            }
            store.save()
            guard let self else { return }
            self.running = false
            self.lastResult = flag.isSet ? "Interrotto: analizzati \(analyzed) file" : "Fatto: analizzati \(analyzed) file"
            PlayerController.shared?.replayGainDidChange()
        }
    }

    nonisolated static func analyzeDetached(_ url: URL, _ flag: CancelFlag) async -> LoudnessBlocks? {
        await Task.detached(priority: .utility) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return LoudnessAnalyzer.analyze(url: url) { flag.isSet }
        }.value
    }
}
