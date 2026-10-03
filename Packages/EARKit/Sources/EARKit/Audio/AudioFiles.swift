#if canImport(AVFoundation)
import Foundation
import AVFoundation

public enum AudioAnalyzer {
    public static let supportedFormats = "WAV · AIFF · MP3 · M4A · AAC · FLAC · CAF"

    /// Streams the file through `AnalysisEngine`; decoded PCM memory stays bounded.
    public static func analyze(_ url: URL, progress: @Sendable (Double) -> Void = { _ in }) throws -> AudioMetrics {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
        catch {
            let detail = error as NSError
            throw EarError.message("This file could not be decoded as audio. Choose an unprotected WAV, AIFF, MP3, M4A, AAC, FLAC or CAF file. "
                + "If it is already audio, download it fully in Files or export a fresh WAV. (\(detail.domain) \(detail.code))")
        }
        let rate = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)
        let duration = Double(file.length) / rate
        guard duration.isFinite, duration >= 3, duration <= 900 else {
            throw EarError.message("Choose a clip between 3 seconds and 15 minutes long.")
        }
        var engine = try AnalysisEngine(sampleRate: rate, channels: channels)
        let capacity: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
            throw EarError.message("Could not prepare the audio analyzer.")
        }
        var lastProgress = -1
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: capacity)
            let count = Int(buffer.frameLength)
            guard count > 0, let pcm = buffer.floatChannelData else {
                throw EarError.message("Audio decoding stopped before the end of the file. Try a fresh audio export.")
            }
            let left = UnsafeBufferPointer(start: pcm[0], count: count)
            let right = UnsafeBufferPointer(start: pcm[channels == 1 ? 0 : 1], count: count)
            try engine.process(left: left, right: right)
            let pct = Int(Double(file.framePosition) / Double(file.length) * 100)
            if pct != lastProgress { progress(Double(pct) / 100); lastProgress = pct }
        }
        let metrics = try engine.finish()
        try Task.checkCancellation()
        return metrics
    }
}

public enum AudioFiles {
    public static let maximumImportBytes = 500_000_000

    /// Copies a user-selected file into EAR's private storage, coordinating with file providers such as iCloud.
    public static func importCopy(source: URL, destination: URL) throws {
        guard source.isFileURL, !FileManager.default.fileExists(atPath: destination.path) else {
            throw EarError.message("Choose an audio file from Files.")
        }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, Error> = .failure(EarError.message("The file provider did not make this audio available. Download it in Files and try again."))
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            result = Result {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumImportBytes else {
                    throw EarError.message("Choose a nonempty audio file no larger than 500 MB.")
                }
                try FileManager.default.copyItem(at: url, to: destination)
                try Task.checkCancellation()
                let copied = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard copied == size else { throw EarError.message("The audio copy was incomplete. Download the file fully in Files, then try again.") }
            }
        }
        do {
            if let coordinationError { throw coordinationError }
            try result.get()
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }

    /// Writes an exact (L+R)/2 fold-down for mono auditioning. Antiphase material cancels, as it would on a mono speaker.
    public static func mono(source: URL, destination: URL) throws {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard (1...2).contains(input.processingFormat.channelCount), input.length > 0,
              !FileManager.default.fileExists(atPath: destination.path) else { throw EarError.message("Choose a mono or stereo source and a new output file.") }
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: input.processingFormat.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw EarError.message("Could not prepare mono playback.") }
        let writer = try AVAudioFile(forWriting: destination, settings: format.settings)
        let stereo = input.processingFormat.channelCount == 2
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer)
            output.frameLength = buffer.frameLength
            guard buffer.frameLength > 0, let a = buffer.floatChannelData, let b = output.floatChannelData else {
                throw EarError.message("Audio decoding stopped before the end of the file.")
            }
            for i in 0..<Int(buffer.frameLength) {
                let left = a[0][i], right = a[stereo ? 1 : 0][i]
                guard left.isFinite, right.isFinite else { throw EarError.message("The file contains invalid audio samples.") }
                b[0][i] = left * 0.5 + right * 0.5
            }
            try writer.write(from: output)
        }
        try Task.checkCancellation()
        complete = true
    }

    /// Writes the original Afterglow study track.
    public static func demo(at url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: DemoTrack.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let pcm = buffer.floatChannelData else { throw EarError.message("Could not prepare the study track.") }
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        var track = DemoTrack()
        while !track.isFinished {
            try Task.checkCancellation()
            let count = track.render(left: pcm[0], right: pcm[1], capacity: 4096)
            buffer.frameLength = AVAudioFrameCount(count)
            try writer.write(from: buffer)
        }
    }
}
#endif
