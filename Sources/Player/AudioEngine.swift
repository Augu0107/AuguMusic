import AVFoundation
import SFBAudioEngine

/// Un "piatto" del motore: player + velocità/tono e il brano caricato.
/// Ce ne sono due per poter fare il crossfade tra un brano e l'altro.
private final class Deck {
    let player = AVAudioPlayerNode()
    let pitch = AVAudioUnitTimePitch()
    var connectedFormat: AVAudioFormat?

    var file: AVAudioFile?
    var decoder: AudioDecoder?
    var decoderFormat: AVAudioFormat?
    var converter: AVAudioConverter?
    var decoderEnded = false
    var pendingBuffers = 0

    var segmentStart: AVAudioFramePosition = 0
    var pausedTime: Double = 0
    var generation = 0

    var hasSource: Bool { file != nil || decoder != nil }

    var sampleRate: Double {
        if let f = file { return f.processingFormat.sampleRate }
        if let fmt = decoderFormat { return fmt.sampleRate }
        return 44_100
    }

    var lengthFrames: AVAudioFramePosition {
        if let f = file { return f.length }
        if let d = decoder { return max(0, d.length) }
        return 0
    }

    var duration: Double { hasSource ? Double(lengthFrames) / sampleRate : 0 }

    func closeSource() {
        if let d = decoder { try? d.close() }
        file = nil
        decoder = nil
        decoderFormat = nil
        converter = nil
        decoderEnded = false
        pendingBuffers = 0
    }
}

/// Motore audio: due piatti (player -> velocità/tono) -> mixer -> EQ (10 bande + bassi) -> uscita.
///
/// I file che iOS sa aprire passano da AVAudioFile; gli altri (estensione sbagliata, Opus, Ogg, WavPack...)
/// vengono decodificati a pezzi con SFBAudioEngine.
final class AudioEngine {
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    let engine = AVAudioEngine()
    private let deckMixer = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 11)
    private let decks = [Deck(), Deck()]
    private var currentIndex = 0
    private var current: Deck { decks[currentIndex] }
    private var other: Deck { decks[1 - currentIndex] }
    private let bufferFrames: AVAudioFrameCount = 32_768

    private var crossfadeTimer: Timer?
    private var crossfadeStep = 0
    private var crossfadeSteps = 1
    private var rate: Float = 1
    private var pitchCents: Float = 0
    private var pan: Float = 0

    /// Chiamato sul main thread quando il brano attuale finisce davvero di suonare.
    var onFinished: (() -> Void)?

    private(set) var isCrossfading = false

    init() {
        engine.attach(deckMixer)
        engine.attach(eq)
        for deck in decks {
            engine.attach(deck.player)
            engine.attach(deck.pitch)
            connect(deck, format: nil)
        }
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
        engine.connect(deckMixer, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        engine.prepare()
    }

    private func connect(_ deck: Deck, format: AVAudioFormat?) {
        engine.connect(deck.player, to: deck.pitch, format: format)
        engine.connect(deck.pitch, to: deckMixer, format: format)
        deck.connectedFormat = format
    }

    /// Ricollega un piatto se il formato cambia (è a monte di un mixer, quindi si può fare a motore acceso).
    private func reconnectIfNeeded(_ deck: Deck, _ format: AVAudioFormat) {
        guard deck.connectedFormat?.sampleRate != format.sampleRate || deck.connectedFormat?.channelCount != format.channelCount else { return }
        engine.disconnectNodeOutput(deck.player)
        engine.disconnectNodeOutput(deck.pitch)
        connect(deck, format: format)
    }

    // MARK: Informazioni

    var duration: Double { current.duration }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var currentTime: Double { time(of: current) }

    private func time(of deck: Deck) -> Double {
        guard deck.hasSource else { return 0 }
        guard engine.isRunning, deck.player.isPlaying,
              let nodeTime = deck.player.lastRenderTime,
              let playerTime = deck.player.playerTime(forNodeTime: nodeTime) else { return deck.pausedTime }
        let t = Double(deck.segmentStart) / deck.sampleRate + Double(playerTime.sampleTime) / playerTime.sampleRate
        let d = deck.duration
        return d > 0 ? min(max(0, t), d) : max(0, t)
    }

    // MARK: Caricamento

    private func open(_ url: URL, into deck: Deck) throws {
        deck.generation += 1
        deck.player.stop()
        deck.closeSource()
        do {
            let file = try AVAudioFile(forReading: url)
            reconnectIfNeeded(deck, file.processingFormat)
            deck.file = file
        } catch {
            // Estensione sbagliata o formato che iOS non apre da solo: provo con SFBAudioEngine.
            let dec = try AudioDecoder(url: url, detectContentType: true)
            try dec.open()
            let source = dec.processingFormat
            guard let standard = AVAudioFormat(standardFormatWithSampleRate: source.sampleRate,
                                               channels: source.channelCount) else { throw error }
            deck.converter = source == standard ? nil : AVAudioConverter(from: source, to: standard)
            reconnectIfNeeded(deck, standard)
            deck.decoder = dec
            deck.decoderFormat = standard
        }
        deck.segmentStart = 0
        deck.pausedTime = 0
        deck.player.volume = 1
        applyEffects(to: deck)
    }

    func load(url: URL) throws {
        finishCrossfadeNow()
        try open(url, into: current)
    }

    func unload() {
        finishCrossfadeNow()
        current.generation += 1
        current.player.stop()
        current.closeSource()
        current.pausedTime = 0
    }

    // MARK: Trasporto

    /// Posiziona il brano; se `play` è true parte subito.
    func start(at time: Double, play: Bool) throws {
        current.pausedTime = max(0, time)
        if play {
            try self.play()
        } else {
            current.generation += 1
            current.player.stop()
        }
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func play() throws {
        guard current.hasSource else { return }
        try startEngineIfNeeded()
        schedule(current, from: current.pausedTime)
        current.player.play()
    }

    func pause() {
        finishCrossfadeNow()
        current.pausedTime = currentTime
        current.generation += 1
        current.player.pause()
        engine.pause()
    }

    func seek(to time: Double, play: Bool) throws {
        finishCrossfadeNow()
        let d = duration
        current.pausedTime = d > 0 ? max(0, min(time, d)) : max(0, time)
        if play {
            try self.play()
        } else {
            current.generation += 1
            current.player.stop()
        }
    }

    /// Usato dopo un cambio di configurazione dell'audio (es. cuffie Bluetooth).
    func setPausedTime(_ time: Double) {
        finishCrossfadeNow()
        current.pausedTime = time
    }

    func stopPlayback() {
        finishCrossfadeNow()
        current.pausedTime = currentTime
        current.generation += 1
        current.player.stop()
        engine.pause()
    }

    // MARK: Crossfade

    /// Carica `url` sull'altro piatto e lo fa entrare mentre quello attuale sfuma.
    /// Da subito il "brano attuale" diventa quello nuovo.
    func crossfade(to url: URL, duration fadeDuration: Double) throws {
        finishCrossfadeNow()
        let outgoing = current
        let incoming = other
        try open(url, into: incoming)
        try startEngineIfNeeded()
        incoming.player.volume = 0
        incoming.pausedTime = 0
        schedule(incoming, from: 0)
        incoming.player.play()

        // L'uscente non deve più avvisare a fine brano: ormai il brano attuale è l'altro.
        outgoing.generation += 1
        currentIndex = 1 - currentIndex
        isCrossfading = true

        crossfadeSteps = max(1, Int(fadeDuration / 0.05))
        crossfadeStep = 0
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.crossfadeTick() }
        }
    }

    private func crossfadeTick() {
        guard isCrossfading else { return }
        crossfadeStep += 1
        let progress = min(1, Float(crossfadeStep) / Float(crossfadeSteps))
        current.player.volume = progress
        other.player.volume = 1 - progress
        if progress >= 1 { finishCrossfadeNow() }
    }

    /// Chiude subito un crossfade in corso (pausa, salto, nuovo brano...).
    private func finishCrossfadeNow() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        guard isCrossfading else { return }
        isCrossfading = false
        let outgoing = other
        outgoing.generation += 1
        outgoing.player.stop()
        outgoing.closeSource()
        outgoing.player.volume = 1
        current.player.volume = 1
    }

    // MARK: Programmazione dell'audio

    private func finishLater(_ deck: Deck, _ gen: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, gen == deck.generation, deck === self.current else { return }
            self.onFinished?()
        }
    }

    private func schedule(_ deck: Deck, from time: Double) {
        deck.generation += 1
        deck.player.stop()
        let gen = deck.generation
        let safeTime = time.isFinite ? max(0, time) : 0
        let start = max(0, min(AVAudioFramePosition(safeTime * deck.sampleRate), deck.lengthFrames))

        if let f = deck.file {
            let frames = AVAudioFrameCount(max(0, f.length - start))
            deck.segmentStart = start
            guard frames > 0 else { finishLater(deck, gen); return }
            deck.player.scheduleSegment(f, startingFrame: start, frameCount: frames, at: nil,
                                        completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, gen == deck.generation, deck === self.current else { return }
                    self.onFinished?()
                }
            }
            return
        }

        guard let dec = deck.decoder else { return }
        if dec.supportsSeeking { try? dec.seek(to: start) }
        deck.segmentStart = max(0, dec.position)
        deck.decoderEnded = false
        deck.pendingBuffers = 0
        for _ in 0..<4 { scheduleNextDecodedBuffer(deck, gen) }
        if deck.pendingBuffers == 0 { finishLater(deck, gen) }
    }

    /// Decodifica e accoda il prossimo pezzo; quando un pezzo finisce ne accoda un altro.
    private func scheduleNextDecodedBuffer(_ deck: Deck, _ gen: Int) {
        guard gen == deck.generation, !deck.decoderEnded, let dec = deck.decoder, let outFormat = deck.decoderFormat,
              let raw = AVAudioPCMBuffer(pcmFormat: dec.processingFormat, frameCapacity: bufferFrames) else { return }
        do {
            try dec.decode(into: raw, length: bufferFrames)
        } catch {
            deck.decoderEnded = true
            return
        }
        guard raw.frameLength > 0 else {
            deck.decoderEnded = true
            return
        }
        var buffer = raw
        if let converter = deck.converter {
            guard let converted = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: raw.frameLength) else {
                deck.decoderEnded = true
                return
            }
            do {
                try converter.convert(to: converted, from: raw)
            } catch {
                deck.decoderEnded = true
                return
            }
            buffer = converted
        }
        deck.pendingBuffers += 1
        deck.player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == deck.generation else { return }
                deck.pendingBuffers -= 1
                self.scheduleNextDecodedBuffer(deck, gen)
                if deck.decoderEnded && deck.pendingBuffers == 0 && deck === self.current {
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
        self.rate = rate
        self.pitchCents = pitchCents
        decks.forEach(applyEffects)
    }

    func setBalance(_ pan: Float) {
        self.pan = max(-1, min(1, pan))
        decks.forEach(applyEffects)
    }

    private func applyEffects(to deck: Deck) {
        deck.pitch.rate = rate
        deck.pitch.pitch = pitchCents
        deck.pitch.bypass = rate == 1 && pitchCents == 0
        deck.player.pan = pan
    }
}
