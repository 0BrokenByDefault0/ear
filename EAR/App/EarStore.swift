import SwiftUI
import AVFoundation
import Observation
import OSLog
import EARKit

func earTrace(_ event: String) {
    #if DEBUG
    Logger(subsystem: "com.aeon.ear", category: "Diagnostics").notice("\(event, privacy: .public)")
    #endif
}

/// App state: the notebook, analysis jobs, playback and capture. All mutations happen on the main actor;
/// decoding and analysis run in detached tasks.
@MainActor @Observable final class EarStore {
    var studies: [Study] = []
    var labTried: Set<String> = []
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
    /// Becomes true briefly after a study finishes analysing, for a one-off success haptic.
    var justFinished = 0

    var current: Study? { studies.first { $0.id == currentID } }
    var canStartStudy: Bool { !busy && !recording && !requestingMicrophone && !loadFailed }
    var notebookReadOnly: Bool { loadFailed }

    @ObservationIgnored private let playback = PlaybackEngine()
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var worker: Task<Study, Error>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var monoWorker: Task<Void, Error>?
    @ObservationIgnored private var requestedMono = UUID()
    @ObservationIgnored private var recordingRequest = UUID()
    @ObservationIgnored private var analysisRequest = UUID()
    @ObservationIgnored private var loadFailed = false
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let cache: URL
    @ObservationIgnored private let indexURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Studies", isDirectory: true)
        cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mono", isDirectory: true)
        indexURL = folder.appendingPathComponent("notebook.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let saved = try NotebookFiles.load(from: indexURL)
            studies = saved.notebook.studies
            labTried = Set(saved.notebook.labTried)
            if saved.recovered { error = "EAR recovered your notebook from its last good save. Your audio files are unchanged; the most recent edit may need to be repeated." }
            migrateLabProgress()
        } catch let failure as NotebookError {
            error = failure.localizedDescription; loadFailed = true
        } catch {
            self.error = "Could not open your notebook. Your saved files have been preserved. \(error.localizedDescription)"; loadFailed = true
        }
        playback.onStop = { [weak self] in self?.playbackStopped() }
        prepareTestHooks()
    }

    // MARK: Notebook

    private func persist() throws { try NotebookFiles.save(Notebook(studies: studies, labTried: labTried.sorted()), to: indexURL) }

    /// EAR 1.2 kept Lab progress in user defaults. Move it into the notebook so it is backed up with everything else.
    private func migrateLabProgress() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: "ear.lab.tried"), !loadFailed else { return }
        let ids = legacy.split(separator: "\n").map(String.init)
        guard !ids.isEmpty else { defaults.removeObject(forKey: "ear.lab.tried"); return }
        labTried.formUnion(ids)
        do { try persist(); defaults.removeObject(forKey: "ear.lab.tried") } catch { labTried.subtract(ids) }
    }

    private var readOnlyMessage: String {
        "Your notebook is read-only until it can be opened safely. Your saved files have been preserved."
    }

    @discardableResult func update(_ study: Study) -> Bool {
        guard !loadFailed else { error = readOnlyMessage; return false }
        guard let index = studies.firstIndex(where: { $0.id == study.id }) else { error = "This study is no longer in your notebook."; return false }
        let old = studies[index]; studies[index] = study
        do { try persist(); return true }
        catch { studies[index] = old; self.error = "Could not save your changes. \(error.localizedDescription)"; return false }
    }

    func rename(_ study: Study, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var renamed = study; renamed.title = String(trimmed.prefix(120))
        update(renamed)
    }

    func toggleCompleted(_ experimentID: String, in studyID: UUID?) {
        guard !loadFailed else { error = readOnlyMessage; return }
        if let studyID, var study = studies.first(where: { $0.id == studyID }) {
            if study.completed.contains(experimentID) { study.completed.removeAll { $0 == experimentID } }
            else { study.completed.append(experimentID) }
            update(study)
        } else {
            let old = labTried
            if labTried.contains(experimentID) { labTried.remove(experimentID) } else { labTried.insert(experimentID) }
            do { try persist() } catch { labTried = old; self.error = "Could not save your progress. \(error.localizedDescription)" }
        }
    }

    func isCompleted(_ experimentID: String, in studyID: UUID?) -> Bool {
        if let studyID, let study = studies.first(where: { $0.id == studyID }) { return study.completed.contains(experimentID) }
        return labTried.contains(experimentID)
    }

    /// Every experiment tried anywhere: in the Lab or inside any study.
    var everTried: Set<String> { labTried.union(studies.flatMap(\.completed)) }

    func delete(_ study: Study) {
        guard canStartStudy else { return }
        guard !loadFailed else { error = readOnlyMessage; return }
        let old = studies
        studies.removeAll { $0.id == study.id }
        do { try persist() }
        catch { studies = old; self.error = "Could not remove the study. \(error.localizedDescription)"; return }
        if currentID == study.id { closeCurrent() }
        try? FileManager.default.removeItem(at: monoURL(study))
        do {
            let url = audioURL(study)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch {
            studies = old
            do { try persist() } catch { loadFailed = true }
            self.error = "Could not remove the audio copy. \(error.localizedDescription)"
        }
    }

    func audioURL(_ study: Study) -> URL { folder.appendingPathComponent(study.filename) }
    private func monoURL(_ study: Study) -> URL { cache.appendingPathComponent("mono-\(study.id.uuidString).caf") }

    // MARK: Studies

    func importFile(_ source: URL, sourceName: String = "Imported file", removeSourceAfterImport: Bool = false) {
        earTrace("Import requested; available=\(canStartStudy)")
        guard canStartStudy else {
            error = loadFailed ? readOnlyMessage : "Finish the current capture or analysis before opening another song."
            if removeSourceAfterImport { try? FileManager.default.removeItem(at: source) }
            return
        }
        let reportProgress = begin(status: "Opening your audio file")
        let ext = source.pathExtension.lowercased()
        let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "audio" : ext)
        // The selection's security scope is held from the picker callback through the private copy.
        let access = source.startAccessingSecurityScopedResource()
        let title = source.deletingPathExtension().lastPathComponent
        worker = Task.detached(priority: .userInitiated) {
            defer {
                if access { source.stopAccessingSecurityScopedResource() }
                if removeSourceAfterImport { try? FileManager.default.removeItem(at: source) }
            }
            do {
                try AudioFiles.importCopy(source: source, destination: destination)
                earTrace("Import copy complete")
                let metrics = try AudioAnalyzer.analyze(destination, progress: reportProgress)
                try Task.checkCancellation()
                return Study(title: title.isEmpty ? "Untitled study" : title, filename: destination.lastPathComponent, source: sourceName, metrics: metrics)
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        finishWorker()
    }

    func demo() {
        guard canStartStudy else { return }
        if let saved = studies.first(where: \.isDemo), saved.metrics.isCurrent,
           FileManager.default.fileExists(atPath: audioURL(saved).path) { open(saved); return }
        if let outdated = studies.first(where: \.isDemo), FileManager.default.fileExists(atPath: audioURL(outdated).path) {
            remeasure(outdated); return
        }
        let reportProgress = begin(status: "Preparing Afterglow")
        let destination = folder.appendingPathComponent(UUID().uuidString + ".caf")
        worker = Task.detached(priority: .userInitiated) {
            do {
                try AudioFiles.demo(at: destination)
                let metrics = try AudioAnalyzer.analyze(destination, progress: reportProgress)
                try Task.checkCancellation()
                return Study(title: DemoTrack.title, filename: destination.lastPathComponent, source: Study.demoSource, metrics: metrics)
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        finishWorker()
    }

    /// Re-runs the current measurements on a saved study, keeping notes, tempo and progress.
    func remeasure(_ study: Study) {
        guard canStartStudy else { return }
        let source = audioURL(study)
        guard FileManager.default.fileExists(atPath: source.path) else {
            error = "The saved audio is unavailable, so this study cannot be re-measured. Your notes are still here."; return
        }
        let reportProgress = begin(status: "Re-measuring \(study.title)")
        worker = Task.detached(priority: .userInitiated) {
            var updated = study
            updated.metrics = try AudioAnalyzer.analyze(source, progress: reportProgress)
            return updated
        }
        finishWorker(replacing: study.id)
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

    private func finishWorker(replacing existing: UUID? = nil) {
        guard let worker else { return }
        Task {
            defer { busy = false; self.worker = nil }
            do {
                let study = try await worker.value
                // Cancellation can arrive after decoding has returned but before this task resumes.
                guard !worker.isCancelled else {
                    if existing == nil { try? FileManager.default.removeItem(at: audioURL(study)) }
                    return
                }
                if let existing, let index = studies.firstIndex(where: { $0.id == existing }) {
                    let old = studies[index]
                    studies[index] = study
                    do { try persist() } catch { studies[index] = old; throw error }
                } else {
                    studies.insert(study, at: 0)
                    do { try persist() }
                    catch { studies.removeAll { $0.id == study.id }; try? FileManager.default.removeItem(at: audioURL(study)); throw error }
                }
                busy = false
                justFinished += 1
                open(study)
                earTrace("Study saved and opened")
            } catch is CancellationError {
            } catch {
                earTrace("Study failed: \((error as NSError).domain) \((error as NSError).code)")
                self.error = "Couldn’t finish this study. \(error.localizedDescription)"
            }
        }
    }

    func cancelAnalysis() { analysisRequest = UUID(); status = "Stopping analysis"; worker?.cancel() }

    // MARK: Playback

    func open(_ study: Study) {
        guard canStartStudy else { return }
        closeCurrent()
        currentID = study.id; showStudy = true
        do { try playback.load(audioURL(study)) }
        catch { self.error = "The saved audio is unavailable. Import the original file again to listen; your notes are still here. \(error.localizedDescription)" }
    }

    func close() { pause(); showStudy = false }

    private func closeCurrent() {
        pause(); cancelMono(); playback.unload()
        currentID = nil; clearLoopState(); mono = false; position = 0
    }

    func togglePlayback() {
        earTrace("Playback tapped; busy=\(busy), recording=\(recording), preparingMono=\(preparingMono)")
        guard !busy, !recording, !requestingMicrophone, !preparingMono else { return }
        if playing { pause(); return }
        do {
            guard playback.isLoaded else { throw PlaybackError.noAudio }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try playback.play()
            position = playback.currentTime; playing = true
            startTicker()
            earTrace("Playback started")
        } catch { self.error = error.localizedDescription }
    }

    func pause() {
        if playing { earTrace("Playback paused") }
        playback.pause()
        position = playback.isLoaded ? playback.currentTime : position
        playing = false
    }

    func seek(_ seconds: Double) {
        guard playback.isLoaded, seconds.isFinite else { return }
        let time = min(max(0, seconds), playback.duration)
        do {
            if let loop, time < loop.start || time >= loop.end { clearLoopState(); try playback.setLoop(nil, startAt: time) }
            else { try playback.seek(to: time) }
        } catch { self.error = error.localizedDescription }
        position = time
    }

    func skip(_ seconds: Double) { seek((playing ? playback.currentTime : position) + seconds) }

    func select(_ moment: Moment) {
        loopStart = nil; loop = moment
        do { try playback.setLoop(moment.start...moment.end, startAt: moment.start) } catch { self.error = error.localizedDescription }
        position = moment.start
        if !playing { togglePlayback() }
    }

    func clearLoop() {
        clearLoopState()
        do { try playback.setLoop(nil) } catch { self.error = error.localizedDescription }
    }

    private func clearLoopState() { loop = nil; loopStart = nil }

    func markLoopStart() {
        let now = playing ? playback.currentTime : position
        if loop != nil { clearLoop() }
        loopStart = now
    }

    func markLoopEnd() {
        let now = playing ? playback.currentTime : position
        guard let start = loopStart, now - start >= 0.25 else { error = "Set the loop end at least a quarter-second after its start."; return }
        select(Moment(id: -1, start: start, end: now, level: 0, change: 0, label: "Your phrase"))
    }

    private func playbackStopped() {
        playing = false
        position = playback.currentTime
    }

    private func cancelMono() { monoWorker?.cancel(); monoWorker = nil; requestedMono = UUID(); preparingMono = false }

    func toggleMono() {
        guard let study = current, !busy, !recording, !requestingMicrophone, !preparingMono, study.metrics.channels == 2 else { return }
        if mono { replaceAudio(audioURL(study), isMono: false); return }
        let destination = monoURL(study)
        if FileManager.default.fileExists(atPath: destination.path) { replaceAudio(destination, isMono: true); return }
        // Each request owns its output. A cancelled conversion cannot delete a newer conversion's file.
        let request = UUID()
        let temporary = cache.appendingPathComponent("mono-\(request.uuidString).partial.caf")
        let source = audioURL(study)
        requestedMono = request; preparingMono = true
        let task = Task.detached(priority: .userInitiated) {
            try AudioFiles.mono(source: source, destination: temporary)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        monoWorker = task
        Task {
            do {
                try await task.value
                guard requestedMono == request, !task.isCancelled, currentID == study.id else { return }
                preparingMono = false
                replaceAudio(destination, isMono: true)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                if requestedMono == request, !(error is CancellationError) { self.error = "Could not prepare mono playback. \(error.localizedDescription)" }
            }
            if requestedMono == request { preparingMono = false; monoWorker = nil }
        }
    }

    private func replaceAudio(_ url: URL, isMono: Bool) {
        let time = playing ? playback.currentTime : position, resume = playing
        do {
            try playback.load(url, at: time)
            if let loop { try playback.setLoop(loop.start...loop.end, startAt: time) }
            mono = isMono
            if resume { try playback.play() }
            position = time
        } catch { playing = false; self.error = error.localizedDescription }
    }

    // MARK: Capture

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
            let rec = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                                                               AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            rec.isMeteringEnabled = true
            guard rec.record(forDuration: 30) else { throw EarError.message("The microphone could not start recording.") }
            recorder = rec; recordingURL = url; recording = true; recordingSeconds = 0
            startTicker()
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

    func suspendAudio(reason: String = "lifecycle") {
        earTrace("Suspending audio: \(reason)")
        recordingRequest = UUID(); requestingMicrophone = false
        pause(); cancelMono()
        if recording { stopRecording(keep: true) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func mediaServicesReset() {
        suspendAudio(reason: "media services reset")
        if let study = current { let wasShowing = showStudy; open(study); showStudy = wasShowing }
    }

    /// Updates the playhead and microphone meter only while something is moving.
    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.playing || self.recording else { break }
                self.tick()
                do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
            }
            self?.ticker = nil
        }
    }

    private func tick() {
        if recording, let recorder {
            if !recorder.isRecording { stopRecording(keep: recordingSeconds >= 3); return }
            recordingSeconds = Int(recorder.currentTime)
            recorder.updateMeters(); microphoneLevel = Double(pow(10, recorder.averagePower(forChannel: 0) / 30))
        }
        if playing { position = playback.currentTime }
    }

    // MARK: Test hooks

    private func prepareTestHooks() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let documents = folder.deletingLastPathComponent()
        if arguments.contains("--reset-onboarding") { UserDefaults.standard.removeObject(forKey: "ear.onboarded") }
        if arguments.contains("--import-ui-check") {
            do {
                let fixture = documents.appendingPathComponent("EAR Import Check.caf")
                if !FileManager.default.fileExists(atPath: fixture.path) { try AudioFiles.demo(at: fixture) }
                try Data("Not an audio recording".utf8).write(to: documents.appendingPathComponent("EAR Invalid Check.txt"))
            } catch { self.error = "Could not prepare import test files. \(error.localizedDescription)" }
        }
        // Exercises the complete import pipeline (security scope, copy, analysis, persistence) without the
        // system document browser, whose simulator file provider cannot be driven reliably in CI.
        if let index = arguments.firstIndex(of: "--import-fixture"), arguments.indices.contains(index + 1) {
            let name = arguments[index + 1]
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try? FileManager.default.removeItem(at: fixture)
                if name.hasSuffix(".caf") { try AudioFiles.demo(at: fixture) }
                else { try Data("Not an audio recording".utf8).write(to: fixture) }
                Task { @MainActor in self.importFile(fixture, removeSourceAfterImport: true) }
            } catch { self.error = "Could not prepare the import fixture. \(error.localizedDescription)" }
        }
        #endif
    }
}
