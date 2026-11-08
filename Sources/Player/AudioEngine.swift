import AVFoundation

/// Motore audio: AVAudioPlayerNode -> TimePitch (velocità/tono) -> EQ (10 bande + bassi) -> mixer.
final class AudioEngine {
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 11)

    private(set) var file: AVAudioFile?
    private var connectedFormat: AVAudioFormat?
    private var segmentStart: AVAudioFramePosition = 0
    private var pausedTime: Double = 0
    private var generation = 0

    /// Chiamato sul main thread quando il brano finisce davvero di suonare.
    var onFinished: (() -> Void)?

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

    var duration: Double {
        guard let f = file else { return 0 }
        return Double(f.length) / f.processingFormat.sampleRate
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var currentTime: Double {
        guard let f = file else { return 0 }
        guard engine.isRunning, player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return pausedTime }
        let t = Double(segmentStart) / f.processingFormat.sampleRate + Double(playerTime.sampleTime) / playerTime.sampleRate
        return min(max(0, t), duration)
    }

    // MARK: Caricamento e trasporto

    func load(url: URL) throws {
        invalidate()
        player.stop()
        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat
        if connectedFormat?.sampleRate != format.sampleRate || connectedFormat?.channelCount != format.channelCount {
            if engine.isRunning { engine.stop() }
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(timePitch)
            engine.disconnectNodeOutput(eq)
            connect(format: format)
            engine.prepare()
        }
        file = newFile
        segmentStart = 0
        pausedTime = 0
    }

    func unload() {
        invalidate()
        player.stop()
        file = nil
        pausedTime = 0
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
        guard file != nil else { return }
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
        pausedTime = max(0, min(time, duration))
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

    private func schedule(from time: Double) {
        guard let f = file else { return }
        let sampleRate = f.processingFormat.sampleRate
        let safeTime = time.isFinite ? max(0, time) : 0
        let start = max(0, min(AVAudioFramePosition(safeTime * sampleRate), f.length))
        let frames = AVAudioFrameCount(max(0, f.length - start))
        segmentStart = start
        invalidate()
        let gen = generation
        guard frames > 0 else {
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.onFinished?()
            }
            return
        }
        player.scheduleSegment(f, startingFrame: start, frameCount: frames, at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.onFinished?()
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
