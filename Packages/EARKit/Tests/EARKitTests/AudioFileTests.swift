#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Testing
@testable import EARKit

/// File import, decoding and mono fold-down. These need AVFoundation, so they run on macOS only.
@Suite struct AudioFileTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { folder.appendingPathComponent(name) }

    func fixture(_ name: String, inverted: Bool) throws -> URL {
        let url = file(name + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 4)!
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) {
            let value = Float(sin(Double(i) * 2 * .pi * 100 / 44100) * 0.4)
            buffer.floatChannelData![0][i] = value
            buffer.floatChannelData![1][i] = inverted ? -value : value
        }
        try writer.write(from: buffer)
        return url
    }

    @Test func demoFileMatchesTheEngine() throws {
        let demo = file("study.caf")
        try AudioFiles.demo(at: demo)
        let fromFile = try AudioAnalyzer.analyze(demo)
        let direct = try Signals.demo()
        #expect(abs(fromFile.duration - 30) < 0.01 && fromFile.channels == 2)
        #expect(abs((fromFile.integratedLoudness ?? 0) - (direct.integratedLoudness ?? 1)) < 0.01)
        #expect(fromFile.bpm == direct.bpm)
    }

    @Test func importPreservesBytesAndNeverOverwrites() throws {
        let source = try fixture("center", inverted: false)
        let imported = file("import.caf")
        try AudioFiles.importCopy(source: source, destination: imported)
        let sourceBytes = try Data(contentsOf: source)
        #expect(try Data(contentsOf: imported) == sourceBytes, "Import must preserve source bytes")
        #expect(throws: EarError.self) { try AudioFiles.importCopy(source: source, destination: imported) }
        #expect(try Data(contentsOf: imported) == sourceBytes)
    }

    @Test func emptyImportFailsCleanly() throws {
        let empty = file("empty.wav")
        try Data().write(to: empty)
        let rejected = file("rejected.wav")
        #expect(throws: EarError.self) { try AudioFiles.importCopy(source: empty, destination: rejected) }
        #expect(!FileManager.default.fileExists(atPath: rejected.path))
    }

    @Test func audioIsValidatedByContentNotExtension() throws {
        let bad = file("not-a-song.wav")
        try Data("This is text, despite its extension".utf8).write(to: bad)
        do { _ = try AudioAnalyzer.analyze(bad); Issue.record("Must validate audio bytes, not extensions") }
        catch EarError.message(let message) { #expect(message.contains("decoded as audio")) }
    }

    @Test func cancelledImportLeavesNothingBehind() async throws {
        let source = try fixture("cancel-source", inverted: false)
        let destination = file("cancelled-import.caf")
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try AudioFiles.importCopy(source: source, destination: destination)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(arguments: ["wav", "aiff", "m4a"])
    func commonContainersImportAndDecode(ext: String) throws {
        let centre = try fixture("format-\(ext)", inverted: false)
        let source = file("format-check." + ext)
        let settings: [String: Any] = ext == "m4a"
            ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000]
            : [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
               AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: ext == "aiff"]
        do {
            let reader = try AVAudioFile(forReading: centre)
            let writer = try AVAudioFile(forWriting: source, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 8192)!
            while reader.framePosition < reader.length { try reader.read(into: buffer); try writer.write(from: buffer) }
        }
        let copy = file("copied-format." + ext)
        try AudioFiles.importCopy(source: source, destination: copy)
        #expect(try Data(contentsOf: source) == Data(contentsOf: copy))
        let decoded = try AudioAnalyzer.analyze(copy)
        #expect(abs(decoded.duration - 4) < 0.1 && decoded.channels == 2)
    }

    @Test func antiphaseMonoFoldDownCancels() throws {
        let inverted = try fixture("inverted", inverted: true)
        let mono = file("mono.caf")
        try AudioFiles.mono(source: inverted, destination: mono)
        #expect(throws: EarError.self, "Antiphase mono sum should be silent") { try AudioAnalyzer.analyze(mono) }
    }

    @Test func monoFoldDownKeepsDurationAndCleansUpWhenCancelled() async throws {
        let demo = file("demo.caf")
        try AudioFiles.demo(at: demo)
        let cancelledURL = file("cancelled.caf")
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try AudioFiles.mono(source: demo, destination: cancelledURL)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(!FileManager.default.fileExists(atPath: cancelledURL.path), "Cancelled conversion must remove its partial output")
        let restored = file("complete-mono.caf")
        try AudioFiles.mono(source: demo, destination: restored)
        let metrics = try AudioAnalyzer.analyze(restored)
        #expect(metrics.channels == 1 && abs(metrics.duration - 30) < 0.01)
    }
}
#endif
