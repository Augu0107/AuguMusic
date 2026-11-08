import AVFoundation
import SFBAudioEngine

/// Motore audio: AVAudioPlayerNode -> TimePitch (velocità/tono) -> EQ (10 bande + bassi) -> mixer.
///
/// I file che iOS sa aprire da solo passano da AVAudioFile. Gli altri (estensione sbagliata, Opus, Ogg Vorbis,
/// WavPack, ...) vengono decodificati a pezzi con SFBAudioEngine, che riconosce il formato dal contenuto.
final class AudioEngine {
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 11)

    private var file: AVAudioFile?
    private var decoder: AudioDecoder?
    private var decoderFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var decoderEnded = false
    private var pendingBuffers = 0
    private let bufferFrames: AVAudioFrameCount = 32_768

    private var connectedFormat: AVAudioFormat?
    private var segmentStart: AVAudioFramePosition = 0
    private var pausedTime: Double = 0
    private var generation = 0

    /// Chiamato sul main thread quando il brano finisce davvero di suonare.
    var onFinished: (() -> Void)?

    /// true se il brano attuale passa dal decoder di riserva.
    private(set) var usesFallbackDecoder = false

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(eq)
        for (i, freq) in Self.frequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = true
        }
        let bass = eq.bands[10]
        bass.filterType = .lowShelf
        bass.frequency = 110
        bass.gain = 0
        bass.bypass = true
        connect(format: nil)
        engine.prepare()
    }

    private func connect(format: AVAudioFormat?) {
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        connectedFormat = format
    }

    private func reconnectIfNeeded(_ format: AVAudioFormat) {
        guard connectedFormat?.sampleRate != format.sampleRate || connectedFormat?.channelCount != format.channelCount else { return }
        if engine.isRunning { engine.stop() }
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(eq)
        connect(format: format)
        engine.prepare()
    }

    // MARK: Informazioni

    private var sampleRate: Double {
        if let f = file { return f.processingFormat.sampleRate }
        if let fmt = decoderFormat { return fmt.sampleRate }
        return 44_100
    }

    private var lengthFrames: AVAudioFramePosition {
        if let f = file { return f.length }
        if let d = decoder { return max(0, d.length) }
        return 0
    }

    private var hasSource: Bool { file != nil || decoder != nil }

    var duration: Double {
        guard hasSource else { return 0 }
        return Double(lengthFrames) / sampleRate
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var currentTime: Double {
        guard hasSource else { return 0 }
        guard engine.isRunning, player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return pausedTime }
        let t = Double(segmentStart) / sampleRate + Double(playerTime.sampleTime) / playerTime.sampleRate
        let d = duration
        return d > 0 ? min(max(0, t), d) : max(0, t)
    }

    // MARK: Caricamento e trasporto

    func load(url: URL) throws {
        invalidate()
        player.stop()
        closeDecoder()
        file = nil
        usesFallbackDecoder = false

        do {
            let newFile = try AVAudioFile(forReading: url)
            reconnectIfNeeded(newFile.processingFormat)
            file = newFile
        } catch {
            // Estensione sbagliata o formato che iOS non apre da solo: provo con SFBAudioEngine.
            let dec = try AudioDecoder(url: url, detectContentType: true)
            try dec.open()
            let source = dec.processingFormat
            guard let standard = AVAudioFormat(standardFormatWithSampleRate: source.sampleRate,
                                               channels: source.channelCount) else { throw error }
            converter = source == standard ? nil : AVAudioConverter(from: source, to: standard)
            reconnectIfNeeded(standard)
            decoder = dec
            decoderFormat = standard
            usesFallbackDecoder = true
        }
        segmentStart = 0
        pausedTime = 0
    }

    func unload() {
        invalidate()
        player.stop()
        file = nil
        closeDecoder()
        pausedTime = 0
    }

    private func closeDecoder() {
        if let d = decoder { try? d.close() }
        decoder = nil
        decoderFormat = nil
        converter = nil
        decoderEnded = false
        pendingBuffers = 0
    }

    /// Posiziona il brano; se `play` è true parte subito.
    func start(at time: Double, play: Bool) throws {
        pausedTime = max(0, time)
        if play {
            try self.play()
        } else {
            invalidate()
            player.stop()
        }
    }

    func play() throws {
        guard hasSource else { return }
        invalidate()
        player.stop()
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        schedule(from: pausedTime)
        player.play()
    }

    func pause() {
        pausedTime = currentTime
        invalidate()
        player.pause()
        engine.pause()
    }

    func seek(to time: Double, play: Bool) throws {
        let d = duration
        pausedTime = d > 0 ? max(0, min(time, d)) : max(0, time)
        if play {
            try self.play()
        } else {
            invalidate()
            player.stop()
        }
    }

    /// Usato dopo un cambio di configurazione dell'audio (es. cuffie Bluetooth).
    func setPausedTime(_ time: Double) {
        pausedTime = time
    }

    func stopPlayback() {
        pausedTime = currentTime
        invalidate()
        player.stop()
        engine.pause()
    }

    private func invalidate() { generation += 1 }

    private func finishLater(_ gen: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, gen == self.generation else { return }
            self.onFinished?()
        }
    }

    private func schedule(from time: Double) {
        let safeTime = time.isFinite ? max(0, time) : 0
        let start = max(0, min(AVAudioFramePosition(safeTime * sampleRate), lengthFrames))
        invalidate()
        let gen = generation

        if let f = file {
            let frames = AVAudioFrameCount(max(0, f.length - start))
            segmentStart = start
            guard frames > 0 else { finishLater(gen); return }
            player.scheduleSegment(f, startingFrame: start, frameCount: frames, at: nil,
                                   completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, gen == self.generation else { return }
                    self.onFinished?()
                }
            }
            return
        }

        guard let dec = decoder else { return }
        if dec.supportsSeeking {
            try? dec.seek(to: start)
        }
        segmentStart = max(0, dec.position)
        decoderEnded = false
        pendingBuffers = 0
        for _ in 0..<4 { scheduleNextDecodedBuffer(gen) }
        if pendingBuffers == 0 { finishLater(gen) }
    }

    /// Decodifica e accoda il prossimo pezzo; quando un pezzo finisce ne accoda un altro.
    private func scheduleNextDecodedBuffer(_ gen: Int) {
        guard gen == generation, !decoderEnded, let dec = decoder, let outFormat = decoderFormat,
              let raw = AVAudioPCMBuffer(pcmFormat: dec.processingFormat, frameCapacity: bufferFrames) else { return }
        do {
            try dec.decode(into: raw, length: bufferFrames)
        } catch {
            decoderEnded = true
            return
        }
        guard raw.frameLength > 0 else {
            decoderEnded = true
            return
        }
        var buffer = raw
        if let converter {
            guard let converted = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: raw.frameLength) else {
                decoderEnded = true
                return
            }
            do {
                try converter.convert(to: converted, from: raw)
            } catch {
                decoderEnded = true
                return
            }
            buffer = converted
        }
        pendingBuffers += 1
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.pendingBuffers -= 1
                self.scheduleNextDecodedBuffer(gen)
                if self.decoderEnded && self.pendingBuffers == 0 {
                    self.onFinished?()
                }
            }
        }
    }

    // MARK: Effetti

    func setEQ(enabled: Bool, gains: [Float], bass: Float) {
        for i in 0..<Self.frequencies.count {
            let band = eq.bands[i]
            band.gain = i < gains.count ? gains[i] : 0
            band.bypass = !enabled
        }
        let bassBand = eq.bands[10]
        bassBand.gain = bass
        bassBand.bypass = !enabled || bass == 0
    }

    func setGlobalGain(_ gain: Float) {
        eq.globalGain = max(-96, min(24, gain))
    }

    func setRate(_ rate: Float, pitchCents: Float) {
        timePitch.rate = rate
        timePitch.pitch = pitchCents
        timePitch.bypass = rate == 1 && pitchCents == 0
    }

    func setBalance(_ pan: Float) {
        player.pan = max(-1, min(1, pan))
    }
}
