import Foundation
import AVFoundation

enum AudioFiles {
    static func importCopy(source: URL, destination: URL) throws {
        guard source.isFileURL, !FileManager.default.fileExists(atPath: destination.path) else {
            throw EarError.message("Choose an audio file from Files.")
        }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, Error> = .failure(EarError.message("The file provider did not make this audio available. Download it in Files and try again."))
        // File providers (including iCloud) must finish preparing their local copy before reading.
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            result = Result {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 500_000_000 else {
                    throw EarError.message("Choose a nonempty audio file no larger than 500 MB.")
                }
                try FileManager.default.copyItem(at: url, to: destination)
                try Task.checkCancellation()
                let copied = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard copied > 0, copied <= 500_000_000 else { throw EarError.message("Choose an audio file no larger than 500 MB.") }
            }
        }
        do {
            if let coordinationError { throw coordinationError }
            try result.get()
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }

    static func mono(source: URL, destination: URL) throws {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard (1...2).contains(input.processingFormat.channelCount), input.length > 0,
              !FileManager.default.fileExists(atPath: destination.path) else { throw EarError.message("Choose a mono or stereo source and a new output file.") }
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: input.processingFormat.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw EarError.message("Could not prepare mono playback.") }
        let writer = try AVAudioFile(forWriting: destination, settings: format.settings)
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer)
            output.frameLength = buffer.frameLength
            guard buffer.frameLength > 0, let a = buffer.floatChannelData, let b = output.floatChannelData else { throw EarError.message("Audio decoding stopped before the end of the file.") }
            for i in 0..<Int(buffer.frameLength) {
                let left = a[0][i], right = a[input.processingFormat.channelCount == 1 ? 0 : 1][i]
                guard left.isFinite, right.isFinite else { throw EarError.message("The file contains invalid audio samples.") }
                b[0][i] = left * 0.5 + right * 0.5
            }
            try writer.write(from: output)
        }
        try Task.checkCancellation()
        complete = true
    }

    // Original deterministic instrumental: 96 BPM, kick/bass, wide pad, hats and a breakdown.
    static func demo(at url: URL) throws {
        let rate = 44100.0, duration = 30.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { throw EarError.message("Could not prepare the study track.") }
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        var seed: UInt32 = 417
        for start in stride(from: 0, to: Int(duration * rate), by: 4096) {
            try Task.checkCancellation()
            let count = min(4096, Int(duration * rate) - start)
            buffer.frameLength = AVAudioFrameCount(count)
            guard let pcm = buffer.floatChannelData else { break }
            for i in 0..<count {
                let t = Double(start + i) / rate
                let beat = t.truncatingRemainder(dividingBy: 0.625)
                let half = t.truncatingRemainder(dividingBy: 0.3125)
                seed = 1664525 &* seed &+ 1013904223
                let noise = Double(seed) / Double(UInt32.max) * 2 - 1
                let breakdown = t >= 15 && t < 20
                let kick = breakdown ? 0 : sin(2 * .pi * (48 * beat + 6 * (1 - exp(-beat * 30)))) * exp(-beat * 20) * 0.46
                let hat = breakdown ? 0 : noise * exp(-half * 95) * 0.09
                let snarePhase = (t + 0.625).truncatingRemainder(dividingBy: 1.25)
                let snare = breakdown ? 0 : noise * exp(-snarePhase * 30) * 0.16
                let root = [55.0, 65.406, 49.0, 58.27][min(3, Int(t / 7.5))]
                let bass = sin(t * 2 * .pi * root) * 0.15 * min(1, beat * 16)
                let fade = min(1, min(t / 0.3, (duration - t) / 0.8))
                for c in 0...1 {
                    let pad = (sin(t * 2 * .pi * (root * 4 + (c == 0 ? -0.25 : 0.25))) + sin(t * 2 * .pi * root * 5.99 + Double(c))) * 0.065
                    pcm[c][i] = Float((kick + hat + snare + bass + pad) * max(0, fade))
                }
            }
            try writer.write(from: buffer)
        }
    }
}
