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
    var mono = false
    var preparingMono = false
    var recording = false
    var recordingSeconds = 0
    var microphoneLevel = 0.0
    var showStudy = false
    var current: Study? { studies.first { $0.id == currentID } }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var worker: Task<Study, Error>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var monoWorker: Task<Void, Error>?
    @ObservationIgnored private var requestedMono = UUID()
    @ObservationIgnored private var loadFailed = false
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let indexURL: URL

    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Studies", isDirectory: true)
        indexURL = folder.appendingPathComponent("notebook.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                studies = try JSONDecoder().decode([Study].self, from: Data(contentsOf: indexURL))
            }
        } catch { self.error = "Could not open your notebook: \(error.localizedDescription)"; loadFailed = true }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    func importFile(_ source: URL, sourceName: String = "Imported file") {
        guard !busy, !recording, !loadFailed else { return }
        begin()
        let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension.lowercased())
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) <= 500_000_000 else { throw EarError.message("Choose an audio file smaller than 500 MB.") }
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: source, to: destination)
                let metrics = try AudioAnalyzer.analyze(destination) { value in Task { @MainActor in self?.progress = value } }
                try Task.checkCancellation()
                return Study(title: source.deletingPathExtension().lastPathComponent, filename: destination.lastPathComponent, source: sourceName, metrics: metrics)
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        finishWorker()
    }

    func demo() {
        guard !busy, !recording, !loadFailed else { return }
        if let saved = studies.first(where: { $0.source == "EAR original study" }) { open(saved); return }
        begin()
        let destination = folder.appendingPathComponent(UUID().uuidString + ".caf")
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try AudioFiles.demo(at: destination)
                let metrics = try AudioAnalyzer.analyze(destination) { value in Task { @MainActor in self?.progress = value } }
                try Task.checkCancellation()
                return Study(title: "Afterglow", filename: destination.lastPathComponent, source: "EAR original study", metrics: metrics)
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        finishWorker()
    }

    private func begin() { pause(); busy = true; progress = 0; status = "Listening beneath the surface" }
    private func finishWorker() {
        guard let worker else { return }
        Task {
            do {
                let study = try await worker.value
                studies.insert(study, at: 0)
                do { try persist(); open(study) }
                catch { studies.removeAll { $0.id == study.id }; try? FileManager.default.removeItem(at: audioURL(study)); throw error }
            } catch is CancellationError { }
            catch { self.error = "Couldn’t finish this study. \(error.localizedDescription)" }
            busy = false; self.worker = nil
        }
    }
    func cancelAnalysis() { status = "Stopping analysis"; worker?.cancel() }
    func audioURL(_ study: Study) -> URL { folder.appendingPathComponent(study.filename) }
    private func persist() throws { try JSONEncoder().encode(studies).write(to: indexURL, options: .atomic) }
    func update(_ study: Study) {
        guard let index = studies.firstIndex(where: { $0.id == study.id }) else { return }
        let old = studies[index]; studies[index] = study
        do { try persist() } catch { studies[index] = old; self.error = "Could not save your changes. \(error.localizedDescription)" }
    }
    func delete(_ study: Study) {
        let old = studies
        studies.removeAll { $0.id == study.id }
        do {
            try persist()
            if currentID == study.id {
                pause(); player = nil; currentID = nil; showStudy = false
                monoWorker?.cancel(); requestedMono = UUID(); preparingMono = false
            }
            try FileManager.default.removeItem(at: audioURL(study))
            let cached = FileManager.default.temporaryDirectory.appendingPathComponent("mono-\(study.id).caf")
            if FileManager.default.fileExists(atPath: cached.path) { try FileManager.default.removeItem(at: cached) }
        } catch {
            if FileManager.default.fileExists(atPath: audioURL(study).path) { studies = old; try? persist() }
            self.error = "Could not fully remove the study. \(error.localizedDescription)"
        }
    }
    func open(_ study: Study) {
        pause(); monoWorker?.cancel(); requestedMono = UUID(); preparingMono = false
        currentID = study.id; loop = nil; mono = false; position = 0; showStudy = true
        do { player = try AVAudioPlayer(contentsOf: audioURL(study)); player?.prepareToPlay() }
        catch { player = nil; self.error = "The saved audio is unavailable. \(error.localizedDescription)" }
    }
    func togglePlayback() {
        guard !preparingMono else { return }
        if playing { pause(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            guard let player else { throw EarError.message("Open a study to play its audio.") }
            if player.currentTime >= player.duration - 0.1 { player.currentTime = loop?.start ?? 0 }
            guard player.play() else { throw EarError.message("Playback could not start.") }
            playing = true
        } catch { self.error = error.localizedDescription }
    }
    func pause() { player?.pause(); playing = false }
    func seek(_ seconds: Double) {
        guard let player else { return }
        let time = min(max(0, seconds), player.duration)
        if let loop, time < loop.start || time >= loop.end { self.loop = nil }
        player.currentTime = time; position = time
    }
    func select(_ moment: Moment) { seek(moment.start); loop = moment; if !playing { togglePlayback() } }
    func toggleMono() {
        guard let study = current, !preparingMono else { return }
        if mono { replacePlayer(url: audioURL(study), isMono: false); return }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("mono-\(study.id).caf")
        if FileManager.default.fileExists(atPath: destination.path) { replacePlayer(url: destination, isMono: true); return }
        let source = audioURL(study), request = UUID()
        requestedMono = request; preparingMono = true
        monoWorker = Task.detached(priority: .userInitiated) {
            do { try AudioFiles.mono(source: source, destination: destination) }
            catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        Task {
            do {
                try await monoWorker?.value
                guard requestedMono == request else { return }
                replacePlayer(url: destination, isMono: true)
            } catch is CancellationError { }
            catch { self.error = "Could not prepare mono playback. \(error.localizedDescription)" }
            if requestedMono == request { preparingMono = false }
        }
    }
    private func replacePlayer(url: URL, isMono: Bool) {
        let time = position, resume = playing
        do {
            let replacement = try AVAudioPlayer(contentsOf: url)
            pause(); player = replacement; player?.currentTime = time; mono = isMono
            preparingMono = false
            if resume { togglePlayback() }
        } catch { self.error = error.localizedDescription }
    }

    func startRecording() async {
        guard !busy, !recording, !loadFailed else { return }
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard permitted else { error = "Microphone access is off. Enable it for EAR in Settings, or import an audio file."; return }
        pause()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Capture-\(UUID().uuidString).m4a")
            let rec = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            rec.isMeteringEnabled = true
            guard rec.record(forDuration: 30) else { throw EarError.message("The microphone could not start recording.") }
            recorder = rec; recordingURL = url; recording = true; recordingSeconds = 0
        } catch { self.error = error.localizedDescription }
    }
    func stopRecording(keep: Bool) {
        guard recording else { return }
        let duration = max(recorder?.currentTime ?? 0, Double(recordingSeconds))
        recorder?.stop(); recorder = nil; recording = false; microphoneLevel = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        guard let url = recordingURL else { return }
        recordingURL = nil
        if keep && duration >= 3 {
            importFile(url, sourceName: "Microphone • room and speaker affect results")
            Task { while busy { try? await Task.sleep(for: .milliseconds(300)) }; try? FileManager.default.removeItem(at: url) }
        } else {
            try? FileManager.default.removeItem(at: url)
            if keep { error = "Record at least 3 seconds so EAR has enough audio to study." }
        }
    }
    private func tick() {
        if recording, let recorder {
            if !recorder.isRecording { stopRecording(keep: recordingSeconds >= 3); return }
            recordingSeconds = Int(recorder.currentTime)
            recorder.updateMeters(); microphoneLevel = Double(pow(10, recorder.averagePower(forChannel: 0) / 30))
        }
        guard let player else { return }
        if playing, let loop, player.currentTime >= loop.end - 0.04 || (!player.isPlaying && position >= player.duration - 0.25) {
            player.currentTime = loop.start
            if !player.isPlaying { player.play() }
        }
        position = player.currentTime
        playing = player.isPlaying
    }
}
