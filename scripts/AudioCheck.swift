import Foundation
import AVFoundation

@main struct AudioCheck {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let demo = folder.appendingPathComponent("study.caf")
        try AudioFiles.demo(at: demo)
        let result = try AudioAnalyzer.analyze(demo)
        precondition(abs(result.duration - 30) < 0.01 && result.channels == 2)
        precondition(result.crest.isFinite && result.bands.count == 5 && abs(result.bands.reduce(0,+) - 1) < 0.001)
        precondition(result.waveform.count <= 420 && result.moments.count >= 5)
        let study = Study(title: "Check", filename: "study.caf", source: "Generated fixture", metrics: result)
        let roundTrip = try JSONDecoder().decode(Study.self, from: JSONEncoder().encode(study))
        precondition(roundTrip.title == "Check")
        let notebook = folder.appendingPathComponent("notebook.json")
        try NotebookFiles.save([study], to: notebook)
        var edited = study; edited.notes = "A saved listening note"; edited.tempoOverride = 96
        try NotebookFiles.save([edited], to: notebook)
        let saved = try NotebookFiles.load(from: notebook)
        precondition(saved.studies[0].notes == edited.notes && !saved.recovered)
        try Data("damaged index".utf8).write(to: notebook)
        let recovered = try NotebookFiles.load(from: notebook)
        precondition(recovered.recovered && recovered.studies[0].id == study.id)
        let preserved = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(preserved.contains { $0.hasPrefix("notebook-damaged-") })
        for bad in ["../outside.caf", "/outside.caf", "..", ""] {
            var invalid = study; invalid.filename = bad
            do { _ = try NotebookFiles.decode(JSONEncoder().encode([invalid])); preconditionFailure("Unsafe path must be rejected") }
            catch EarError.message(_) { }
        }
        var invalid = study; invalid.metrics.bands = []
        do { _ = try NotebookFiles.decode(JSONEncoder().encode([invalid])); preconditionFailure("Invalid spectrum must not reach the UI") }
        catch EarError.message(_) { }
        let imported = folder.appendingPathComponent("import.caf")
        try AudioFiles.importCopy(source: demo, destination: imported)
        let sourceBytes = try Data(contentsOf: demo), copiedBytes = try Data(contentsOf: imported)
        precondition(sourceBytes == copiedBytes, "Import must preserve source bytes")
        for lens in Lens.allCases {
            precondition(!Finding.make(lens, study: study).evidence.isEmpty)
            precondition(Experiment.make(lens, daw: .studio, tempo: 120).steps.count >= 4)
            precondition(Experiment.make(lens, daw: .logic, tempo: 120).steps.count >= 4)
        }
        let envelope = (0..<1200).map { $0 % 50 == 0 ? 1.0 : 0.01 }
        let pulse = AudioAnalyzer.estimateTempo(envelope, frameRate: 100)
        precondition(pulse.bpm == 120 || pulse.bpm == 60, "120 BPM pulse must yield the pulse or half-time candidate")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        func fixture(_ name: String, inverted: Bool, silent: Bool) throws -> URL {
            let url = folder.appendingPathComponent(name + ".caf")
            let writer = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 4)!
            buffer.frameLength = buffer.frameCapacity
            for i in 0..<Int(buffer.frameLength) {
                let value = silent ? Float(0) : Float(sin(Double(i) * 2 * .pi * 100 / 44100) * 0.4)
                buffer.floatChannelData![0][i] = value
                buffer.floatChannelData![1][i] = inverted ? -value : value
            }
            try writer.write(from: buffer)
            return url
        }
        let centered = try AudioAnalyzer.analyze(fixture("center", inverted: false, silent: false))
        precondition(centered.correlation > 0.999 && centered.sideFraction < 0.00001)
        precondition(centered.bands[0] > 0.95 && centered.bpm == nil)
        precondition(abs(centered.peak - (-7.96)) < 0.1 && abs(centered.crest - 3.01) < 0.1)
        let invertedURL = try fixture("inverted", inverted: true, silent: false)
        let inverted = try AudioAnalyzer.analyze(invertedURL)
        precondition(inverted.correlation < -0.999 && inverted.sideFraction > 0.999)
        precondition(inverted.bands[0] > 0.95, "Spectrum must preserve antiphase source energy")
        let mono = folder.appendingPathComponent("mono.caf")
        try AudioFiles.mono(source: invertedURL, destination: mono)
        do { _ = try AudioAnalyzer.analyze(mono); preconditionFailure("Antiphase mono sum should be silent") }
        catch EarError.message(_) { }
        let silence = try fixture("silence", inverted: false, silent: true)
        do { _ = try AudioAnalyzer.analyze(silence); preconditionFailure("Silence must be rejected") }
        catch EarError.message(_) { }
        let cancelledURL = folder.appendingPathComponent("cancelled.caf")
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try AudioFiles.mono(source: demo, destination: cancelledURL)
        }
        do { try await cancelled.value; preconditionFailure("Cancelled conversion must throw") }
        catch is CancellationError { }
        precondition(!FileManager.default.fileExists(atPath: cancelledURL.path), "Cancelled conversion must remove its partial output")
        let restoredMono = folder.appendingPathComponent("complete-mono.caf")
        try AudioFiles.mono(source: demo, destination: restoredMono)
        let monoMetrics = try AudioAnalyzer.analyze(restoredMono)
        precondition(monoMetrics.channels == 1 && abs(monoMetrics.duration - result.duration) < 0.01)
        print("PASS: streaming decode, known peak/RMS/crest, low-band spectrum, center/antiphase stereo, mono cancellation, silence, pulse, persistence recovery and validation, byte-preserving import, cancelled-output cleanup, full-length mono and all nine experiment paths.")
        print("Demo: \(result.duration)s, tempo candidate \(result.bpm.map { String($0) } ?? "none"), \(result.moments.count) sections")
    }
}
