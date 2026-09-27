import SwiftUI
import AVFoundation
import Observation

@MainActor @Observable final class EarStore {
    var studies: [Study] = []
    var currentID: UUID?
    var busy = false
    var progress = 0.0
    var status = "Reading audio"
    var error: String?
    var playing = false
    var position = 0.0
    var loop: Moment?
    var loopStart: Double?
    var mono = false
    var preparingMono = false
    var recording = false
    var requestingMicrophone = false
    var recordingSeconds = 0
    var microphoneLevel = 0.0
    var showStudy = false
    var current: Study? { studies.first { $0.id == currentID } }
    var canStartStudy: Bool { !busy && !recording && !requestingMicrophone && !loadFailed }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var worker: Task<Study, Error>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var monoWorker: Task<Void, Error>?
    @ObservationIgnored private var monoURL: URL?
    @ObservationIgnored private var requestedMono = UUID()
    @ObservationIgnored private var recordingRequest = UUID()
    @ObservationIgnored private var analysisRequest = UUID()
    @ObservationIgnored private var loadFailed = false
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let indexURL: URL

    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Studies", isDirectory: true)
        indexURL = folder.appendingPathComponent("notebook.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let saved = try NotebookFiles.load(from: indexURL)
            studies = saved.studies
            if saved.recovered { error = "EAR recovered your notebook from its last good save. Your audio files are unchanged; the most recent edit may need to be repeated." }
        } catch { self.error = "Could not open your notebook. Your saved files have been preserved. \(error.localizedDescription)"; loadFailed = true }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard self != nil else { return }
                self?.tick()
            }
        }
    }

    deinit { timer?.cancel(); worker?.cancel(); monoWorker?.cancel() }

    func importFile(_ source: URL, sourceName: String = "Imported file", removeSourceAfterImport: Bool = false) {
        guard canStartStudy else {
            error = loadFailed ? "Your notebook must be recovered before adding studies." : "Finish the current capture or analysis before opening another song."
            if removeSourceAfterImport { try? FileManager.default.removeItem(at: source) }
            return
        }
        let reportProgress = begin(status: "Opening your audio file")
        let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension.lowercased())
        worker = Task.detached(priority: .userInitiated) {
            defer { if removeSourceAfterImport { try? FileManager.default.removeItem(at: source) } }
            do {
                try AudioFiles.importCopy(source: source, destination: destination)
                let metrics = try AudioAnalyzer.analyze(destination, progress: reportProgress)
                try Task.checkCancellation()
                return Study(title: source.deletingPathExtension().lastPathComponent, filename: destination.lastPathComponent, source: sourceName, metrics: metrics)
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        finishWorker()
    }

    func demo() {
        guard canStartStudy else { return }
        if let saved = studies.first(where: { $0.source == "EAR original study" }),
           FileManager.default.fileExists(atPath: audioURL(saved).path) { open(saved); return }
        let reportProgress = begin(status: "Preparing Afterglow")
        let destination = folder.appendingPathComponent(UUID().uuidString + ".caf")
        worker = Task.detached(priority: .userInitiated) {
            do {
                try AudioFiles.demo(at: destination)
                let metrics = try AudioAnalyzer.analyze(destination, progress: reportProgress)
                try Task.checkCancellation()
                return Study(title: "Afterglow", filename: destination.lastPathComponent, source: "EAR original study", metrics: metrics)
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        finishWorker()
    }

    private func begin(status: String) -> @Sendable (Double) -> Void {
        pause(); cancelMono(); showStudy = false
        busy = true; progress = 0; self.status = status
        let request = UUID(); analysisRequest = request
        return { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.busy, self.analysisRequest == request else { return }
                self.status = "Listening beneath the surface"
                self.progress = value
            }
        }
    }

    private func finishWorker() {
        guard let worker else { return }
        Task {
            defer { busy = false; self.worker = nil }
            do {
                let study = try await worker.value
                // Cancellation can arrive after decoding has returned but before this task resumes.
                guard !worker.isCancelled else { try? FileManager.default.removeItem(at: audioURL(study)); return }
                studies.insert(study, at: 0)
                do { try persist() }
                catch { studies.removeAll { $0.id == study.id }; try? FileManager.default.removeItem(at: audioURL(study)); throw error }
                busy = false
                open(study)
            } catch is CancellationError { }
            catch { self.error = "Couldn’t finish this study. \(error.localizedDescription)" }
        }
    }
    func cancelAnalysis() { analysisRequest = UUID(); status = "Stopping analysis"; worker?.cancel() }
    func audioURL(_ study: Study) -> URL { folder.appendingPathComponent(study.filename) }
    private func persist() throws { try NotebookFiles.save(studies, to: indexURL) }

    @discardableResult func update(_ study: Study) -> Bool {
        guard !loadFailed, let index = studies.firstIndex(where: { $0.id == study.id }) else { return false }
        let old = studies[index]; studies[index] = study
        do { try persist(); return true }
        catch { studies[index] = old; self.error = "Could not save your changes. \(error.localizedDescription)"; return false }
    }

    func delete(_ study: Study) {
        guard canStartStudy else { return }
        let old = studies
        studies.removeAll { $0.id == study.id }
        do { try persist() }
        catch { studies = old; self.error = "Could not remove the study. \(error.localizedDescription)"; return }
        if currentID == study.id {
            pause(); player = nil; currentID = nil; showStudy = false
            cancelMono(); clearMonoCache(); clearLoop(); position = 0; mono = false
        }
        do {
            let url = audioURL(study)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch {
            studies = old
            do { try persist() } catch { loadFailed = true }
            self.error = "Could not remove the audio copy. \(error.localizedDescription)"
        }
    }

    func open(_ study: Study) {
        guard canStartStudy else { return }
        pause(); player = nil; cancelMono(); clearMonoCache()
        currentID = study.id; clearLoop(); mono = false; position = 0; showStudy = true
        do { player = try AVAudioPlayer(contentsOf: audioURL(study)); player?.prepareToPlay() }
        catch { self.error = "The saved audio is unavailable. Import the original file again to listen; your notes are still here. \(error.localizedDescription)" }
    }

    func togglePlayback() {
        guard !busy, !recording, !requestingMicrophone, !preparingMono else { return }
        if playing { pause(); return }
        do {
            guard let player else { throw EarError.message("Open a study with available audio to play.") }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            if position >= player.duration - 0.01 { player.currentTime = loop?.start ?? 0 }
            guard player.play() else { throw EarError.message("Playback could not start.") }
            position = player.currentTime; playing = true
        } catch { self.error = error.localizedDescription }
    }
    func pause() { if playing { position = player?.currentTime ?? position }; player?.pause(); playing = false }
    func seek(_ seconds: Double) {
        guard let player, seconds.isFinite else { return }
        let time = min(max(0, seconds), player.duration)
        if let loop, time < loop.start || time >= loop.end { self.loop = nil }
        player.currentTime = time; position = time
    }
    func select(_ moment: Moment) { seek(moment.start); loopStart = nil; loop = moment; if !playing { togglePlayback() } }
    func clearLoop() { loop = nil; loopStart = nil }
    func markLoopStart() { loop = nil; loopStart = position }
    func markLoopEnd() {
        guard let start = loopStart, position - start >= 0.25 else { error = "Set the loop end at least a quarter-second after its start."; return }
        select(Moment(id: -1, start: start, end: position, level: 0, change: 0, label: "Your phrase"))
    }

    private func cancelMono() { monoWorker?.cancel(); monoWorker = nil; requestedMono = UUID(); preparingMono = false }
    private func clearMonoCache() { if let monoURL { try? FileManager.default.removeItem(at: monoURL) }; monoURL = nil }
    func toggleMono() {
        guard let study = current, !busy, !recording, !requestingMicrophone, !preparingMono, study.metrics.channels == 2 else { return }
        if mono { replacePlayer(url: audioURL(study), isMono: false); return }
        if let monoURL, FileManager.default.fileExists(atPath: monoURL.path) { replacePlayer(url: monoURL, isMono: true); return }
        // Each request owns its output. A cancelled conversion cannot delete a newer conversion's file.
        let request = UUID()
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("mono-\(study.id)-\(request).caf")
        let source = audioURL(study)
        requestedMono = request; preparingMono = true
        let task = Task.detached(priority: .userInitiated) { try AudioFiles.mono(source: source, destination: destination) }
        monoWorker = task
        Task {
            do {
                try await task.value
                guard requestedMono == request, !task.isCancelled, currentID == study.id else {
                    try? FileManager.default.removeItem(at: destination); return
                }
                monoURL = destination
                replacePlayer(url: destination, isMono: true)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if requestedMono == request, !(error is CancellationError) { self.error = "Could not prepare mono playback. \(error.localizedDescription)" }
            }
            if requestedMono == request { preparingMono = false; monoWorker = nil }
        }
    }
    private func replacePlayer(url: URL, isMono: Bool) {
        let time = playing ? (player?.currentTime ?? position) : position, resume = playing
        do {
            let replacement = try AVAudioPlayer(contentsOf: url)
            pause(); player = replacement; replacement.currentTime = min(time, replacement.duration); position = replacement.currentTime; mono = isMono
            preparingMono = false
            if resume { togglePlayback() }
        } catch { self.error = error.localizedDescription }
    }

    func startRecording() async {
        guard canStartStudy else { return }
        let request = UUID(); recordingRequest = request; requestingMicrophone = true
        defer { if recordingRequest == request { requestingMicrophone = false } }
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard recordingRequest == request, !Task.isCancelled else { return }
        guard permitted else { error = "Microphone access is off. Enable it for EAR in Settings, or import an audio file."; return }
        pause(); cancelMono()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Capture-\(UUID().uuidString).m4a")
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let rec = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            rec.isMeteringEnabled = true
            guard rec.record(forDuration: 30) else { throw EarError.message("The microphone could not start recording.") }
            recorder = rec; recordingURL = url; recording = true; recordingSeconds = 0
        } catch {
            try? FileManager.default.removeItem(at: url)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.error = error.localizedDescription
        }
    }
    func stopRecording(keep: Bool) {
        guard recording else { return }
        let duration = max(recorder?.currentTime ?? 0, Double(recordingSeconds))
        recorder?.stop(); recorder = nil; recording = false; microphoneLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = recordingURL else { return }
        recordingURL = nil
        if keep && duration >= 3 {
            importFile(url, sourceName: "Microphone • room and speaker affect results", removeSourceAfterImport: true)
        } else {
            try? FileManager.default.removeItem(at: url)
            if keep { error = "Record at least 3 seconds so EAR has enough audio to study." }
        }
    }
    func suspendAudio() {
        recordingRequest = UUID(); requestingMicrophone = false
        pause(); cancelMono()
        if recording { stopRecording(keep: true) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tick() {
        if recording, let recorder {
            if !recorder.isRecording { stopRecording(keep: recordingSeconds >= 3); return }
            recordingSeconds = Int(recorder.currentTime)
            recorder.updateMeters(); microphoneLevel = Double(pow(10, recorder.averagePower(forChannel: 0) / 30))
        }
        guard playing, let player else { return }
        if let loop, player.currentTime >= loop.end || !player.isPlaying {
            player.currentTime = loop.start
            if !player.isPlaying && !player.play() { playing = false; error = "Loop playback could not continue." }
        } else if !player.isPlaying {
            // AVAudioPlayer may reset currentTime at EOF. Keep the UI at the end until Replay.
            position = player.duration; playing = false; return
        }
        position = player.currentTime
    }
}
