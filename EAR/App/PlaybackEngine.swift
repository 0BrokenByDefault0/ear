import AVFoundation
import Foundation

/// Sample-accurate playback built on AVAudioEngine.
///
/// Loops are scheduled as back-to-back file segments, so the boundary is exact rather than
/// polled. Two loop passes are always queued ahead of the one playing; each consumed pass queues
/// another. A generation counter discards callbacks from schedules that were stopped or replaced.
@MainActor final class PlaybackEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var connectedFormat: AVAudioFormat?
    private var scheduleStart: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition = 0
    private var loopRange: Range<AVAudioFramePosition>?
    private var generation = 0
    private var observer: NSObjectProtocol?

    private(set) var isPlaying = false
    /// Called when playback reaches the end of the file, or the output route stops the engine.
    var onStop: (@MainActor () -> Void)?

    init() {
        engine.attach(player)
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
    }

    var isLoaded: Bool { file != nil }
    var sampleRate: Double { file?.processingFormat.sampleRate ?? 44100 }
    var length: AVAudioFramePosition { file?.length ?? 0 }
    var duration: Double { Double(length) / sampleRate }

    var currentTime: Double {
        guard isPlaying, let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return Double(pausedFrame) / sampleRate }
        return Double(frame(after: max(0, playerTime.sampleTime))) / sampleRate
    }

    /// Loads a file, keeping the requested position. Replacing the file (for example stereo ↔ mono) keeps loop and play state.
    func load(_ url: URL, at seconds: Double = 0, resume: Bool = false) throws {
        let newFile = try AVAudioFile(forReading: url)
        stopPlayer()
        if connectedFormat.map({ !$0.isEqual(newFile.processingFormat) }) ?? true {
            if engine.isRunning { engine.stop() }
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: newFile.processingFormat)
            connectedFormat = newFile.processingFormat
        }
        file = newFile
        pausedFrame = frame(for: seconds)
        if resume { try play() }
    }

    func unload() {
        stopPlayer()
        file = nil
        loopRange = nil
        pausedFrame = 0
        if engine.isRunning { engine.stop() }
    }

    func play() throws {
        guard let file else { throw PlaybackError.noAudio }
        guard !isPlaying else { return }
        if pausedFrame >= length - 1 { pausedFrame = loopRange?.lowerBound ?? 0 }
        if !engine.isRunning { engine.prepare(); try engine.start() }
        generation += 1
        let current = generation
        scheduleStart = pausedFrame
        if let loop = loopRange, loop.contains(pausedFrame) {
            player.scheduleSegment(file, startingFrame: pausedFrame, frameCount: AVAudioFrameCount(loop.upperBound - pausedFrame),
                                   at: nil, completionCallbackType: .dataConsumed) { _ in }
            scheduleLoopPass(current)
            scheduleLoopPass(current)
        } else {
            player.scheduleSegment(file, startingFrame: pausedFrame, frameCount: AVAudioFrameCount(max(1, length - pausedFrame)),
                                   at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.reachedEnd(current) }
            }
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        pausedFrame = frame(for: currentTime)
        stopPlayer()
    }

    func seek(to seconds: Double) throws {
        let resume = isPlaying
        stopPlayer()
        pausedFrame = frame(for: seconds)
        if resume { try play() }
    }

    /// Sets or clears the loop. If playing, playback continues from the same moment with the new loop.
    func setLoop(_ range: ClosedRange<Double>?, startAt start: Double? = nil) throws {
        let resume = isPlaying
        let position = start ?? currentTime
        stopPlayer()
        loopRange = range.map { frame(for: $0.lowerBound)..<max(frame(for: $0.lowerBound) + 1, frame(for: $0.upperBound)) }
        pausedFrame = frame(for: position)
        if resume { try play() }
    }

    private func scheduleLoopPass(_ current: Int) {
        guard let file, let loop = loopRange, current == generation else { return }
        player.scheduleSegment(file, startingFrame: loop.lowerBound, frameCount: AVAudioFrameCount(loop.count),
                               at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in
                guard let self, current == self.generation, self.isPlaying else { return }
                self.scheduleLoopPass(current)
            }
        }
    }

    private func reachedEnd(_ current: Int) {
        guard current == generation, isPlaying, loopRange == nil else { return }
        pausedFrame = length
        stopPlayer()
        onStop?()
    }

    private func configurationChanged() {
        // The output route changed (for example headphones unplugged). Keep the position and stop cleanly.
        guard isPlaying else { return }
        pause()
        onStop?()
    }

    private func stopPlayer() {
        generation += 1
        player.stop()
        isPlaying = false
    }

    private func frame(for seconds: Double) -> AVAudioFramePosition {
        guard seconds.isFinite else { return 0 }
        return min(length, max(0, AVAudioFramePosition(seconds * sampleRate)))
    }

    private func frame(after elapsed: AVAudioFramePosition) -> AVAudioFramePosition {
        guard let loop = loopRange, loop.contains(scheduleStart) else { return min(length, scheduleStart + elapsed) }
        let first = loop.upperBound - scheduleStart
        if elapsed < first { return scheduleStart + elapsed }
        return loop.lowerBound + (elapsed - first) % AVAudioFramePosition(loop.count)
    }
}

enum PlaybackError: LocalizedError {
    case noAudio
    var errorDescription: String? { "Open a study with available audio to play." }
}
