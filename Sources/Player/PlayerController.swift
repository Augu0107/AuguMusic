import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Tempo di riproduzione separato, così solo le viste che lo mostrano si aggiornano 4 volte al secondo.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var time: Double = 0
}

@MainActor
final class PlayerController: ObservableObject {
    static weak var shared: PlayerController?

    @Published private(set) var queues: [PlayQueue] = []
    @Published private(set) var activeQueueID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var loadedTrackID: String?
    @Published var repeatMode: RepeatMode = .repeatQueue {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") }
    }
    @Published var sleepTimer: SleepTimer?
    @Published var abRepeat = ABRepeat()
    @Published var message: String?

    let clock = PlaybackClock()

    private let audio = AudioEngine()
    private let library: LibraryStore
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var tickCount = 0
    private var fadeTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    /// Copertina del brano attuale (nil se il brano non ne ha).
    @Published private(set) var nowPlayingImage: UIImage?
    private var sessionConfigured = false
    private var resumeAfterInterruption = false
    private var listenedSeconds: Double = 0
    private var playCounted = false

    private static let queuesFile = "queues.json"

    init(library: LibraryStore, settings: AppSettings) {
        self.library = library
        self.settings = settings
        Self.shared = self
        if let raw = UserDefaults.standard.string(forKey: "repeatMode"), let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }

        audio.onFinished = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.trackFinished() }
        }

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAudioSettings() }
            .store(in: &cancellables)

        Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] n in self?.handleInterruption(n) }
            .store(in: &cancellables)
        center.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] n in self?.handleRouteChange(n) }
            .store(in: &cancellables)
        center.publisher(for: .AVAudioEngineConfigurationChange, object: audio.engine)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleConfigurationChange() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.persist() }
            .store(in: &cancellables)

        setupRemoteCommands()
        applyAudioSettings()
    }

    // MARK: Stato

    var activeQueueIndex: Int? { queues.firstIndex { $0.id == activeQueueID } }
    var activeQueue: PlayQueue? { activeQueueIndex.map { queues[$0] } }
    var currentTrack: Track? { loadedTrackID.flatMap { library.byID[$0] } }
    var currentTime: Double { audio.currentTime }

    func queue(_ id: UUID) -> PlayQueue? { queues.first { $0.id == id } }

    // MARK: Salvataggio

    func persist() {
        saveElapsed()
        Storage.save(QueueSnapshot(queues: queues, activeQueueID: activeQueueID), to: Self.queuesFile)
    }

    func restore() {
        guard let snap = Storage.load(QueueSnapshot.self, from: Self.queuesFile) else { return }
        queues = snap.queues
        activeQueueID = snap.activeQueueID ?? queues.first?.id
        if let q = activeQueue, q.currentID != nil {
            loadCurrent(autoplay: false, at: q.elapsed)
        }
    }

    /// Dopo una nuova scansione: ricarica il brano se prima non era disponibile.
    func libraryDidChange() {
        if loadedTrackID == nil, let q = activeQueue, q.currentID != nil {
            loadCurrent(autoplay: false, at: q.elapsed)
        }
    }

    private func saveElapsed() {
        guard let qi = activeQueueIndex, loadedTrackID != nil else { return }
        queues[qi].elapsed = audio.currentTime
    }

    // MARK: Caricamento brano

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if !sessionConfigured {
            try? session.setCategory(.playback, mode: .default, options: [])
            sessionConfigured = true
        }
        try? session.setActive(true)
    }

    private func loadCurrent(autoplay: Bool, at time: Double = 0) {
        guard let qi = activeQueueIndex, let id = queues[qi].currentID else {
            audio.unload()
            loadedTrackID = nil
            isPlaying = false
            duration = 0
            clock.time = 0
            updateNowPlaying()
            return
        }
        abRepeat = ABRepeat()
        listenedSeconds = 0
        playCounted = false
        guard let track = library.byID[id], let url = library.url(for: track) else {
            handleLoadFailure(autoplay: autoplay, reason: "Brano non trovato, passo al successivo")
            return
        }
        do {
            try audio.load(url: url)
            loadedTrackID = id
            duration = audio.duration
            applyReplayGain()
            if autoplay { activateSession() }
            fadeTask?.cancel()
            audio.volume = (autoplay && settings.fadeEnabled) ? 0 : 1
            try audio.start(at: min(time, max(0, audio.duration - 0.5)), play: autoplay)
            if autoplay && settings.fadeEnabled { fade(to: 1, thenPause: false) }
            isPlaying = autoplay
            clock.time = audio.currentTime
            queues[qi].elapsed = clock.time
            consecutiveFailures = 0
            loadNowPlayingArtwork(track: track, url: url)
            updateNowPlaying()
        } catch {
            handleLoadFailure(autoplay: autoplay, reason: "Non riesco a riprodurre \(track.displayTitle)")
        }
    }

    private func handleLoadFailure(autoplay: Bool, reason: String) {
        message = reason
        consecutiveFailures += 1
        guard let qi = activeQueueIndex, consecutiveFailures < min(queues[qi].items.count, 50) else {
            consecutiveFailures = 0
            loadedTrackID = nil
            isPlaying = false
            audio.unload()
            updateNowPlaying()
            return
        }
        queues[qi].index = queues[qi].index + 1 < queues[qi].items.count ? queues[qi].index + 1 : 0
        queues[qi].elapsed = 0
        loadCurrent(autoplay: autoplay)
    }

    /// Dopo aver modificato i tag del brano in riproduzione: lo riapre dallo stesso punto.
    func reloadCurrentTrack() {
        guard loadedTrackID != nil else { return }
        let time = audio.currentTime
        let wasPlaying = isPlaying
        loadCurrent(autoplay: wasPlaying, at: time)
    }

    // MARK: Trasporto

    func play() {
        guard activeQueueIndex != nil else { return }
        if loadedTrackID == nil {
            loadCurrent(autoplay: true, at: activeQueue?.elapsed ?? 0)
            return
        }
        activateSession()
        fadeTask?.cancel()
        if settings.fadeEnabled { audio.volume = 0 } else { audio.volume = 1 }
        do {
            try audio.play()
        } catch {
            message = "Errore audio: \(error.localizedDescription)"
            return
        }
        isPlaying = true
        if settings.fadeEnabled { fade(to: 1, thenPause: false) }
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        if settings.fadeEnabled {
            fade(to: 0, thenPause: true)
        } else {
            audio.pause()
            clock.time = audio.currentTime
            saveElapsed()
        }
        updateNowPlaying()
        persist()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    private func fade(to target: Float, thenPause: Bool) {
        fadeTask?.cancel()
        let steps = 12
        let start = audio.volume
        let stepDelay = UInt64(max(0.05, settings.fadeDuration) / Double(steps) * 1_000_000_000)
        fadeTask = Task { [weak self] in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: stepDelay)
                if Task.isCancelled { return }
                guard let self else { return }
                self.audio.volume = start + (target - start) * Float(i) / Float(steps)
            }
            guard let self, !Task.isCancelled else { return }
            if thenPause {
                self.audio.pause()
                self.clock.time = self.audio.currentTime
                self.saveElapsed()
            }
        }
    }

    func next() {
        guard let qi = activeQueueIndex, !queues[qi].items.isEmpty else { return }
        queues[qi].index = queues[qi].index + 1 < queues[qi].items.count ? queues[qi].index + 1 : 0
        queues[qi].elapsed = 0
        loadCurrent(autoplay: isPlaying)
        persist()
    }

    func previous() {
        guard let qi = activeQueueIndex, !queues[qi].items.isEmpty else { return }
        if audio.currentTime > 3 {
            seek(to: 0)
            return
        }
        if queues[qi].index > 0 {
            queues[qi].index -= 1
        } else {
            queues[qi].index = queues[qi].items.count - 1
        }
        queues[qi].elapsed = 0
        loadCurrent(autoplay: isPlaying)
        persist()
    }

    func seek(to time: Double) {
        let t = max(0, min(time, duration))
        try? audio.seek(to: t, play: isPlaying)
        clock.time = t
        if let qi = activeQueueIndex { queues[qi].elapsed = t }
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: audio.currentTime + seconds)
    }

    private func tick() {
        guard isPlaying else { return }
        let t = audio.currentTime
        clock.time = t
        // Conta un ascolto dopo metà brano (al massimo 30 secondi), come le statistiche di Musicolet.
        listenedSeconds += 0.25 * settings.speed
        if !playCounted, let id = loadedTrackID, listenedSeconds >= min(30, max(5, duration * 0.5)) {
            playCounted = true
            UserDataStore.shared?.recordPlay(id)
        }
        if let a = abRepeat.a, let b = abRepeat.b, b > a, t >= b {
            seek(to: a)
        }
        startCrossfadeIfNeeded(currentTime: t)
        if let timer = sleepTimer, case .at(let date) = timer.mode, Date() >= date {
            if timer.finishCurrentSong {
                sleepTimer = SleepTimer(mode: .afterCurrentSong, finishCurrentSong: false)
            } else {
                sleepTimer = nil
                pause()
                message = "Fermato dal timer di spegnimento"
            }
        }
        tickCount += 1
        if tickCount % 40 == 0 { persist() }
    }

    private func trackFinished() {
        guard let qi = activeQueueIndex else { return }
        if let timer = sleepTimer {
            switch timer.mode {
            case .afterCurrentSong:
                sleepTimer = nil
                message = "Fermato dal timer di spegnimento"
                advanceAndStop(qi)
                return
            case .afterSongs(let n):
                if n <= 1 {
                    sleepTimer = nil
                    message = "Fermato dal timer di spegnimento"
                    advanceAndStop(qi)
                    return
                }
                sleepTimer?.mode = .afterSongs(n - 1)
            case .at:
                break
            }
        }
        switch repeatMode {
        case .repeatSong:
            queues[qi].elapsed = 0
            loadCurrent(autoplay: true)
        case .stopAfterSong:
            advanceAndStop(qi)
        case .repeatQueue, .jumpToNextQueue, .stopAfterQueue:
            if queues[qi].index + 1 < queues[qi].items.count {
                queues[qi].index += 1
                queues[qi].elapsed = 0
                loadCurrent(autoplay: true)
            } else {
                endOfQueue(qi)
            }
        }
        persist()
    }

    /// Quando mancano pochi secondi alla fine, fa entrare il brano successivo sovrapposto.
    private func startCrossfadeIfNeeded(currentTime t: Double) {
        let fade = settings.crossfadeDuration
        guard fade > 0, !audio.isCrossfading, abRepeat.b == nil, duration > fade * 2,
              let qi = activeQueueIndex, duration - t <= fade, duration - t > 0.3 else { return }
        if let timer = sleepTimer {
            switch timer.mode {
            case .afterCurrentSong: return
            case .afterSongs(let n) where n <= 1: return
            default: break
            }
        }
        var nextIndex = queues[qi].index + 1
        switch repeatMode {
        case .repeatSong, .stopAfterSong, .jumpToNextQueue:
            if repeatMode != .jumpToNextQueue || nextIndex >= queues[qi].items.count { return }
        case .repeatQueue:
            if nextIndex >= queues[qi].items.count { nextIndex = 0 }
        case .stopAfterQueue:
            if nextIndex >= queues[qi].items.count { return }
        }
        guard queues[qi].items.indices.contains(nextIndex),
              let next = library.byID[queues[qi].items[nextIndex]],
              let url = library.url(for: next) else { return }
        do {
            try audio.crossfade(to: url, duration: fade)
        } catch {
            return // il brano successivo partirà normalmente alla fine
        }
        if case .afterSongs(let n)? = sleepTimer?.mode { sleepTimer?.mode = .afterSongs(n - 1) }
        queues[qi].index = nextIndex
        queues[qi].elapsed = 0
        loadedTrackID = next.id
        duration = audio.duration
        abRepeat = ABRepeat()
        listenedSeconds = 0
        playCounted = false
        applyReplayGain()
        loadNowPlayingArtwork(track: next, url: url)
        updateNowPlaying()
        persist()
    }

    private func advanceAndStop(_ qi: Int) {
        queues[qi].index = queues[qi].index + 1 < queues[qi].items.count ? queues[qi].index + 1 : 0
        queues[qi].elapsed = 0
        isPlaying = false
        loadCurrent(autoplay: false)
    }

    private func endOfQueue(_ qi: Int) {
        queues[qi].index = 0
        queues[qi].elapsed = 0
        switch repeatMode {
        case .repeatQueue:
            loadCurrent(autoplay: true)
        case .jumpToNextQueue:
            let nextIndex = (qi + 1) % queues.count
            activeQueueID = queues[nextIndex].id
            message = "Coda successiva: \(queues[nextIndex].name)"
            loadCurrent(autoplay: true, at: queues[nextIndex].elapsed)
        default:
            isPlaying = false
            loadCurrent(autoplay: false)
            message = "Fine della coda"
        }
    }

    // MARK: Code

    private func enforceQueueLimit(keeping keep: UUID) {
        while queues.count > max(1, settings.maxQueues) {
            guard let i = queues.firstIndex(where: { $0.id != keep && $0.id != activeQueueID }) else { break }
            let removed = queues.remove(at: i)
            message = "Limite di code raggiunto: rimossa \"\(removed.name)\""
        }
    }

    /// Riproduce un elenco (tocco su un brano).
    func play(_ tracks: [Track], startAt index: Int, source: String, forceNewQueue: Bool = false) {
        guard !tracks.isEmpty else { return }
        let ids = tracks.map(\.id)
        let start = max(0, min(index, ids.count - 1))
        saveElapsed()
        if forceNewQueue || settings.tapAction == .newQueue || activeQueueIndex == nil {
            let q = PlayQueue(name: source, items: ids, index: start)
            queues.append(q)
            activeQueueID = q.id
            enforceQueueLimit(keeping: q.id)
        } else if let qi = activeQueueIndex {
            let wasShuffled = queues[qi].isShuffled
            queues[qi].name = source
            queues[qi].items = ids
            queues[qi].unshuffled = nil
            queues[qi].index = start
            queues[qi].elapsed = 0
            if wasShuffled { queues[qi].setShuffle(true) }
        }
        loadCurrent(autoplay: true)
        persist()
    }

    func shuffleAndPlay(_ tracks: [Track], source: String) {
        play(tracks.shuffled(), startAt: 0, source: source)
    }

    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard let qi = activeQueueIndex else {
            createQueue(tracks, name: "Coda", activate: true)
            return
        }
        queues[qi].insertNext(tracks.map(\.id))
        message = tracks.count == 1 ? "Riprodotto dopo: \(tracks[0].displayTitle)" : "\(tracks.count) brani riprodotti dopo"
        if loadedTrackID == nil { loadCurrent(autoplay: false) }
        persist()
    }

    func addToQueue(_ tracks: [Track], queueID: UUID? = nil) {
        guard !tracks.isEmpty else { return }
        let targetIndex: Int?
        if let queueID {
            targetIndex = queues.firstIndex(where: { $0.id == queueID })
        } else {
            targetIndex = activeQueueIndex
        }
        guard let qi = targetIndex else {
            createQueue(tracks, name: "Coda", activate: true)
            return
        }
        queues[qi].append(tracks.map(\.id))
        message = tracks.count == 1 ? "Aggiunto a \(queues[qi].name)" : "\(tracks.count) brani aggiunti a \(queues[qi].name)"
        if queues[qi].id == activeQueueID && loadedTrackID == nil { loadCurrent(autoplay: false) }
        persist()
    }

    func addToNewQueue(_ tracks: [Track], name: String) {
        guard !tracks.isEmpty else { return }
        createQueue(tracks, name: name, activate: activeQueueIndex == nil)
    }

    private func createQueue(_ tracks: [Track], name: String, activate: Bool) {
        let q = PlayQueue(name: name, items: tracks.map(\.id))
        queues.append(q)
        enforceQueueLimit(keeping: q.id)
        message = "Nuova coda: \(name)"
        if activate {
            activeQueueID = q.id
            loadCurrent(autoplay: false)
        }
        persist()
    }

    func switchToQueue(_ id: UUID, autoplay: Bool = true) {
        guard let q = queue(id) else { return }
        if id == activeQueueID {
            if autoplay && !isPlaying { play() }
            return
        }
        saveElapsed()
        activeQueueID = id
        loadCurrent(autoplay: autoplay, at: q.elapsed)
        persist()
    }

    func playQueueItem(queueID: UUID, index: Int) {
        guard let qi = queues.firstIndex(where: { $0.id == queueID }), queues[qi].items.indices.contains(index) else { return }
        saveElapsed()
        activeQueueID = queueID
        queues[qi].index = index
        queues[qi].elapsed = 0
        loadCurrent(autoplay: true)
        persist()
    }

    func removeQueue(_ id: UUID) {
        guard let i = queues.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = id == activeQueueID
        queues.remove(at: i)
        if wasActive {
            activeQueueID = queues.isEmpty ? nil : queues[min(i, queues.count - 1)].id
            loadCurrent(autoplay: false, at: activeQueue?.elapsed ?? 0)
        }
        persist()
    }

    func removeOtherQueues(except id: UUID) {
        let wasActive = activeQueueID == id
        queues.removeAll { $0.id != id }
        if !wasActive {
            activeQueueID = id
            loadCurrent(autoplay: false, at: activeQueue?.elapsed ?? 0)
        }
        persist()
    }

    func renameQueue(_ id: UUID, to name: String) {
        guard let i = queues.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        queues[i].name = name
        persist()
    }

    func removeFromQueue(_ id: UUID, at offsets: IndexSet) {
        guard let i = queues.firstIndex(where: { $0.id == id }) else { return }
        let currentRemoved = queues[i].remove(atOffsets: offsets)
        if id == activeQueueID && currentRemoved { loadCurrent(autoplay: isPlaying) }
        persist()
    }

    func moveInQueue(_ id: UUID, from source: IndexSet, to destination: Int) {
        guard let i = queues.firstIndex(where: { $0.id == id }) else { return }
        queues[i].move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func toggleShuffle() {
        guard let qi = activeQueueIndex else { return }
        queues[qi].setShuffle(!queues[qi].isShuffled)
        message = queues[qi].isShuffled ? "Modalità casuale attiva" : "Modalità casuale disattivata"
        persist()
    }

    func reshuffle() {
        guard let qi = activeQueueIndex else { return }
        queues[qi].reshuffle()
        persist()
    }

    // MARK: Timer e A-B

    func setSleepTimer(minutes: Int, finishCurrentSong: Bool) {
        sleepTimer = SleepTimer(mode: .at(Date().addingTimeInterval(Double(minutes) * 60)), finishCurrentSong: finishCurrentSong)
        message = "Timer: \(minutes) minuti"
    }

    func setSleepAfterCurrentSong() {
        sleepTimer = SleepTimer(mode: .afterCurrentSong, finishCurrentSong: true)
        message = "Mi fermo dopo questo brano"
    }

    func setSleepAfterSongs(_ n: Int) {
        sleepTimer = SleepTimer(mode: .afterSongs(max(1, n)), finishCurrentSong: true)
        message = "Mi fermo dopo \(n) brani"
    }

    func cancelSleepTimer() {
        sleepTimer = nil
    }

    func setABPointA() {
        abRepeat = ABRepeat(a: audio.currentTime, b: nil)
    }

    func setABPointB() {
        let t = audio.currentTime
        guard let a = abRepeat.a, t > a + 0.5 else {
            message = "Imposta prima il punto A"
            return
        }
        abRepeat.b = t
        seek(to: a)
    }

    func clearAB() {
        abRepeat = ABRepeat()
    }

    // MARK: Effetti audio

    private func applyAudioSettings() {
        audio.setEQ(enabled: settings.eqEnabled, gains: settings.eqGains.map { Float($0) }, bass: Float(settings.bassBoost))
        audio.setRate(Float(settings.speed), pitchCents: Float(settings.pitch * 100))
        audio.setBalance(Float(settings.balance))
        applyReplayGain()
        if loadedTrackID != nil { updateNowPlaying() }
    }

    private func applyReplayGain() {
        var gain = settings.eqEnabled ? settings.eqPreamp : 0
        if let t = currentTrack {
            switch settings.replayGain {
            case .off:
                break
            case .track:
                if let rg = t.replayGainTrack ?? t.replayGainAlbum { gain += rg + settings.replayGainPreamp }
            case .album:
                if let rg = t.replayGainAlbum ?? t.replayGainTrack { gain += rg + settings.replayGainPreamp }
            }
        }
        audio.setGlobalGain(Float(gain))
    }

    // MARK: Sistema (interruzioni, cuffie, Bluetooth)

    private func handleInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isPlaying {
                resumeAfterInterruption = true
                isPlaying = false
                audio.stopPlayback()
                clock.time = audio.currentTime
                saveElapsed()
                updateNowPlaying()
            }
        case .ended:
            let optionsRaw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) && resumeAfterInterruption { play() }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable && isPlaying {
            isPlaying = false
            audio.pause()
            clock.time = audio.currentTime
            saveElapsed()
            updateNowPlaying()
            persist()
        }
    }

    private func handleConfigurationChange() {
        guard loadedTrackID != nil else { return }
        audio.setPausedTime(clock.time)
        if isPlaying {
            do { try audio.play() } catch { isPlaying = false }
        }
    }

    // MARK: Centro di controllo e schermata di blocco

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        _ = c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }
            return .success
        }
        _ = c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        _ = c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        _ = c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        _ = c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        _ = c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
    }

    private func loadNowPlayingArtwork(track: Track, url: URL) {
        // Tengo la copertina precedente finché non arriva la nuova, così sfondo e barra non lampeggiano.
        let id = track.id
        Task { [weak self] in
            let image = await ArtworkLoader.shared.image(for: track, url: url, maxPixel: 600)
            guard let self, self.loadedTrackID == id else { return }
            self.nowPlayingImage = image
            self.updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let t = currentTrack else {
            center.nowPlayingInfo = nil
            refreshWidget()
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.displayTitle,
            MPMediaItemPropertyArtist: t.displayArtist,
            MPMediaItemPropertyAlbumTitle: t.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? settings.speed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let q = activeQueue {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = q.index
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = q.items.count
        }
        if let image = nowPlayingImage {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image)
        }
        center.nowPlayingInfo = info
        refreshWidget()
    }

    // MARK: Widget

    func toggleCurrentFavorite() {
        guard let id = loadedTrackID else { return }
        UserDataStore.shared?.toggleFavorite(id)
    }

    func refreshWidget() {
        var upNext: [String] = []
        var position = ""
        if let q = activeQueue {
            position = q.items.isEmpty ? "" : "\(q.index + 1)/\(q.items.count)"
            let start = q.index + 1
            if start < q.items.count {
                for id in q.items[start..<min(q.items.count, start + 9)] {
                    if let t = library.byID[id] { upNext.append("\(t.displayTitle) — \(t.displayArtist)") }
                }
            }
        }
        let state = WidgetBridge.State(track: currentTrack,
                                       artwork: nowPlayingImage,
                                       isPlaying: isPlaying,
                                       isFavorite: loadedTrackID.map { UserDataStore.shared?.isFavorite($0) ?? false } ?? false,
                                       queueName: activeQueue?.name ?? "",
                                       position: position,
                                       upNext: upNext,
                                       style: settings.widgetStyle,
                                       accent: UIColor(settings.accent.color))
        WidgetBridge.shared.update(state)
    }

    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
