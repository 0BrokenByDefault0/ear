import Foundation
import AVFoundation
import Accelerate

enum EarError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum AudioAnalyzer {
    // Streaming decode: bounded PCM memory, no network and no source separation.
    static func analyze(_ url: URL, progress: @Sendable (Double) -> Void = { _ in }) throws -> AudioMetrics {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
        catch {
            let detail = error as NSError
            throw EarError.message("This file could not be decoded as audio. Choose an unprotected WAV, AIFF, MP3, M4A, AAC, FLAC or CAF file. If it is already audio, download it fully in Files or export a fresh WAV. (\(detail.domain) \(detail.code))")
        }
        let rate = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)
        let duration = Double(file.length) / rate
        guard duration.isFinite, duration >= 3, duration <= 900 else {
            throw EarError.message("Choose a clip between 3 seconds and 15 minutes long.")
        }
        guard (1...2).contains(channels), rate >= 8000, rate <= 192000 else {
            throw EarError.message("Choose a mono or stereo audio file at 8–192 kHz. Export surround audio as stereo first.")
        }
        let n = 2048
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(n)),
              let dft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD) else {
            throw EarError.message("Could not prepare the audio analyzer.")
        }
        defer { vDSP_DFT_DestroySetup(dft) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        let zero = [Float](repeating: 0, count: n)
        var mid = zero, side = zero, real = zero, imag = zero
        var bands = [Double](repeating: 0, count: 5)
        var midBands = bands, sideBands = bands
        var sumL = 0.0, sumR = 0.0, cross = 0.0, midEnergy = 0.0, sideEnergy = 0.0
        var peak = 0.0, fullScale = 0.0, samples = 0.0
        var envelope: [Double] = []
        let hop = max(1, Int(rate / 100))
        var hopSum = 0.0, hopCount = 0
        var lastProgress = -1
        func bandIndex(_ frequency: Double) -> Int? {
            if frequency < 20 { return nil }
            if frequency < 160 { return 0 }
            if frequency < 500 { return 1 }
            if frequency < 2500 { return 2 }
            if frequency < 8000 { return 3 }
            return 4
        }
        let bandMap = (0..<n/2).map { bandIndex(Double($0) * rate / Double(n)) }
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(n))
            let count = Int(buffer.frameLength)
            guard count > 0, let pcm = buffer.floatChannelData else { throw EarError.message("Audio decoding stopped before the end of the file. Try a fresh audio export.") }
            for i in 0..<n {
                guard i < count else { mid[i] = 0; side[i] = 0; continue }
                let l = Double(pcm[0][i]), r = Double(pcm[channels == 1 ? 0 : 1][i])
                guard l.isFinite, r.isFinite else { throw EarError.message("The file contains invalid audio samples. Try a fresh WAV export.") }
                let m = (l + r) * 0.5, s = (l - r) * 0.5
                sumL += l*l; sumR += r*r; cross += l*r
                midEnergy += m*m; sideEnergy += s*s
                peak = max(peak, max(abs(l), abs(r)))
                fullScale += (abs(l) >= 0.999 ? 1 : 0) + (abs(r) >= 0.999 ? 1 : 0)
                samples += 1
                hopSum += (l*l + r*r) * 0.5; hopCount += 1
                if hopCount == hop { envelope.append(sqrt(hopSum / Double(hop))); hopSum = 0; hopCount = 0 }
                mid[i] = Float(m) * window[i]; side[i] = Float(s) * window[i]
            }
            vDSP_DFT_Execute(dft, mid, zero, &real, &imag)
            for i in 1..<n/2 {
                if let b = bandMap[i] { midBands[b] += Double(real[i]*real[i] + imag[i]*imag[i]) }
            }
            vDSP_DFT_Execute(dft, side, zero, &real, &imag)
            for i in 1..<n/2 {
                if let b = bandMap[i] { sideBands[b] += Double(real[i]*real[i] + imag[i]*imag[i]) }
            }
            let pct = Int(Double(file.framePosition) / Double(file.length) * 100)
            if pct != lastProgress { progress(Double(pct) / 100); lastProgress = pct }
        }
        guard samples > rate * 2, peak > 0.00001 else { throw EarError.message("This clip is silent or too quiet to analyze. Try a louder source.") }
        if hopCount > 0 { envelope.append(sqrt(hopSum / Double(hopCount))) }
        for i in 0..<5 { bands[i] = midBands[i] + sideBands[i] }
        let total = max(1e-20, bands.reduce(0, +))
        bands = bands.map { $0 / total }
        let frameRate = rate / Double(hop)
        let pulse = estimateTempo(envelope, frameRate: frameRate)
        let rms = sqrt((sumL + sumR) / (2 * samples))
        let waveformStride = max(1, Int(ceil(Double(envelope.count) / 420)))
        let waveform = stride(from: 0, to: envelope.count, by: waveformStride).map { start in
            envelope[start..<min(start + waveformStride, envelope.count)].max() ?? 0
        }
        let waveMax = max(1e-8, waveform.max() ?? 1)
        let sectionLength = max(4.0, duration / 8)
        let sectionFrames = max(1, Int(sectionLength * frameRate))
        var moments: [Moment] = []
        for start in stride(from: 0, to: envelope.count, by: sectionFrames) {
            let part = envelope[start..<min(start + sectionFrames, envelope.count)]
            let level = db(sqrt(part.reduce(0) { $0 + $1*$1 } / Double(part.count)))
            let change = moments.last.map { level - $0.level } ?? 0
            let label = moments.isEmpty ? "Opening" : change > 2.5 ? "Energy lift" : change < -2.5 ? "Pullback" : "Steady passage"
            moments.append(Moment(id: moments.count, start: Double(start) / frameRate, end: min(duration, Double(start + part.count) / frameRate), level: level, change: change, label: label))
        }
        try Task.checkCancellation()
        return AudioMetrics(duration: Double(samples) / rate, sampleRate: rate, channels: channels,
            peak: db(peak), rms: db(rms), crest: db(peak) - db(rms),
            correlation: max(-1, min(1, cross / max(1e-20, sqrt(sumL*sumR)))),
            sideFraction: sideEnergy / max(1e-20, midEnergy + sideEnergy),
            lowSideFraction: sideBands[0] / max(1e-20, midBands[0] + sideBands[0]),
            midSideFraction: sideBands[2] / max(1e-20, midBands[2] + sideBands[2]),
            balance: (sumR - sumL) / max(1e-20, sumR + sumL), bands: bands,
            bpm: pulse.bpm, tempoStrength: pulse.strength, transientRate: pulse.rate,
            tailSeconds: estimateTail(envelope, frameRate: frameRate), nearFullScale: fullScale / (2 * samples),
            waveform: waveform.map { $0 / waveMax }, moments: moments)
    }

    static func db(_ value: Double) -> Double { 20 * log10(max(1e-8, value)) }

    static func estimateTempo(_ envelope: [Double], frameRate: Double) -> (bpm: Double?, strength: Double, rate: Double) {
        guard envelope.count > Int(frameRate * 3) else { return (nil, 0, 0) }
        var onset = [Double](repeating: 0, count: envelope.count)
        for i in 2..<envelope.count { onset[i] = max(0, envelope[i] - (envelope[i-1] + envelope[i-2]) * 0.5) }
        let sorted = onset.sorted()
        let threshold = max((sorted.last ?? 0) * 0.12, sorted[Int(Double(sorted.count) * 0.8)] * 1.5)
        var hits = 0, previous = -1000
        for i in onset.indices where onset[i] > threshold && onset[i] > 0.0001 {
            if i - previous > Int(frameRate * 0.09) { hits += 1; previous = i }
        }
        let hitRate = Double(hits) / (Double(envelope.count) / frameRate)
        guard hits >= 6 else { return (nil, 0, hitRate) }
        // ponytail: onset autocorrelation is a tempo candidate, not a beat tracker; user can tap/halve/double.
        var bestLag = 0, bestScore = 0.0
        for lag in Int(frameRate * 60 / 180)...Int(frameRate * 60 / 60) {
            var product = 0.0, a = 0.0, b = 0.0
            for i in lag..<onset.count { product += onset[i]*onset[i-lag]; a += onset[i]*onset[i]; b += onset[i-lag]*onset[i-lag] }
            let score = product / max(1e-20, sqrt(a*b))
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        return (bestScore >= 0.16 ? (60 * frameRate / Double(bestLag)).rounded() : nil, bestScore, hitRate)
    }

    static func estimateTail(_ envelope: [Double], frameRate: Double) -> Double? {
        var tails: [Double] = []
        var i = 1
        while i < envelope.count - Int(frameRate * 0.25) {
            let start = envelope[i]
            if start > 0.015 && start > envelope[i-1] * 1.4 {
                let end = min(envelope.count - 1, i + Int(frameRate * 1.5))
                for j in (i+1)...end {
                    if envelope[j] > start * 1.2 { break }
                    if envelope[j] < start * 0.2512 {
                        let seconds = Double(j - i) / frameRate
                        if seconds >= 0.20 { tails.append(seconds) }
                        i = j; break
                    }
                }
            }
            i += 1
        }
        guard tails.count >= 4 else { return nil }
        return tails.sorted()[tails.count / 2]
    }
}
