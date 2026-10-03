import Foundation

/// Streaming analysis of a mono or stereo signal. Memory stays bounded by the envelope
/// (100 values per second) regardless of file length. No network, no source separation.
public struct AnalysisEngine: Sendable {
    public let sampleRate: Double
    public let channels: Int

    // Whole-file statistics.
    private var sumL = 0.0, sumR = 0.0, cross = 0.0, midEnergy = 0.0, sideEnergy = 0.0
    private var peak = 0.0, fullScale = 0.0, frames = 0

    // 10 ms RMS envelope for tempo, sections, decay and the waveform.
    private let hop: Int
    private var hopSum = 0.0, hopCount = 0
    private var envelope: [Double] = []

    // 2048-point mid/side spectrum for the five broad bands.
    private static let bandSize = 2048
    private let bandFFT = FFT(size: AnalysisEngine.bandSize)
    private let bandWindow: [Double]
    private let bandMap: [Int8]
    private var bandMid: [Double], bandSide: [Double], bandFill = 0
    private var midBands = [Double](repeating: 0, count: 5), sideBands = [Double](repeating: 0, count: 5)

    // 8192-point mid spectrum for the detailed third-octave view and the key estimate.
    private static let detailSize = 8192
    private let detailFFT = FFT(size: AnalysisEngine.detailSize)
    private let detailWindow: [Double]
    private let thirdMap: [Int8]
    private let chromaMap: [Int8]
    private var detail: [Double], detailFill = 0
    private var thirds = [Double](repeating: 0, count: AnalysisEngine.thirdCentres.count)
    private var chroma = [Double](repeating: 0, count: 12)

    // BS.1770 loudness and true peak.
    private var weightL: KWeighting, weightR: KWeighting
    private let subBlock: Int
    private var subSum = 0.0, subCount = 0
    private var subBlocks: [Double] = []
    private var truePeakL = TruePeakMeter(), truePeakR = TruePeakMeter()

    /// Third-octave centres from 31.5 Hz to 16 kHz.
    public static let thirdCentres: [Double] = (2...29).map { 1000 * pow(2, Double($0 - 17) / 3) }

    public init(sampleRate rate: Double, channels: Int) throws {
        guard (1...2).contains(channels), rate >= 8000, rate <= 192000 else {
            throw EarError.message("Choose a mono or stereo audio file at 8–192 kHz. Export surround audio as stereo first.")
        }
        sampleRate = rate
        self.channels = channels
        hop = max(1, Int(rate / 100))
        subBlock = max(1, Int((rate * 0.1).rounded()))
        weightL = KWeighting(sampleRate: rate)
        weightR = KWeighting(sampleRate: rate)

        func hann(_ n: Int) -> [Double] { (0..<n).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n)) } }
        bandWindow = hann(Self.bandSize)
        detailWindow = hann(Self.detailSize)
        bandMid = [Double](repeating: 0, count: Self.bandSize)
        bandSide = bandMid
        detail = [Double](repeating: 0, count: Self.detailSize)

        bandMap = (0..<Self.bandSize / 2).map { bin in
            let f = Double(bin) * rate / Double(Self.bandSize)
            if f < 20 { return -1 }
            if f < 160 { return 0 }
            if f < 500 { return 1 }
            if f < 2500 { return 2 }
            if f < 8000 { return 3 }
            return 4
        }
        let edges = Self.thirdCentres.map { ($0 * pow(2, -1.0 / 6), $0 * pow(2, 1.0 / 6)) }
        thirdMap = (0..<Self.detailSize / 2).map { bin in
            let f = Double(bin) * rate / Double(Self.detailSize)
            return Int8(edges.firstIndex { f >= $0.0 && f < $0.1 } ?? -1)
        }
        chromaMap = (0..<Self.detailSize / 2).map { bin in
            let f = Double(bin) * rate / Double(Self.detailSize)
            guard f >= 100, f <= 5000 else { return -1 }
            let semitone = Int((12 * log2(f / 440)).rounded())
            return Int8(((semitone + 9) % 12 + 12) % 12)
        }
    }

    /// Feeds equal-length channel buffers. Pass the same buffer twice for mono material.
    public mutating func process(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>) throws {
        let count = min(left.count, right.count)
        let stereo = channels == 2
        for i in 0..<count {
            let l = Double(left[i]), r = stereo ? Double(right[i]) : l
            guard l.isFinite, r.isFinite else { throw EarError.message("The file contains invalid audio samples. Try a fresh WAV export.") }
            let m = (l + r) * 0.5, s = (l - r) * 0.5
            sumL += l * l; sumR += r * r; cross += l * r
            midEnergy += m * m; sideEnergy += s * s
            let magnitude = max(abs(l), abs(r))
            if magnitude > peak { peak = magnitude }
            if abs(l) >= 0.999 { fullScale += 1 }
            if abs(r) >= 0.999 { fullScale += 1 }
            frames += 1

            hopSum += (l * l + r * r) * 0.5; hopCount += 1
            if hopCount == hop { envelope.append(sqrt(hopSum / Double(hop))); hopSum = 0; hopCount = 0 }

            bandMid[bandFill] = m; bandSide[bandFill] = s; bandFill += 1
            if bandFill == Self.bandSize { analyzeBands(); bandFill = 0 }
            detail[detailFill] = m; detailFill += 1
            if detailFill == Self.detailSize { analyzeDetail(); detailFill = 0 }

            let wl = weightL.process(l)
            subSum += wl * wl
            if stereo { let wr = weightR.process(r); subSum += wr * wr }
            subCount += 1
            if subCount == subBlock { subBlocks.append(subSum / Double(subBlock)); subSum = 0; subCount = 0 }

            truePeakL.process(l)
            if stereo { truePeakR.process(r) }
        }
    }

    public mutating func process(left: [Float], right: [Float]) throws {
        try left.withUnsafeBufferPointer { l in
            try right.withUnsafeBufferPointer { r in try process(left: l, right: r) }
        }
    }

    private mutating func analyzeBands() {
        // One complex FFT carries both real signals: z = mid + i·side.
        var real = [Double](repeating: 0, count: Self.bandSize), imag = real
        for i in 0..<bandFill { real[i] = bandMid[i] * bandWindow[i]; imag[i] = bandSide[i] * bandWindow[i] }
        bandFFT.transform(&real, &imag)
        let n = Self.bandSize
        for k in 1..<n / 2 {
            let band = Int(bandMap[k])
            guard band >= 0 else { continue }
            let a = real[k], b = imag[k], c = real[n - k], d = imag[n - k]
            midBands[band] += ((a + c) * (a + c) + (b - d) * (b - d)) / 4
            sideBands[band] += ((a - c) * (a - c) + (b + d) * (b + d)) / 4
        }
    }

    private mutating func analyzeDetail() {
        var real = [Double](repeating: 0, count: Self.detailSize), imag = real
        for i in 0..<detailFill { real[i] = detail[i] * detailWindow[i] }
        detailFFT.transform(&real, &imag)
        for k in 1..<Self.detailSize / 2 {
            let power = real[k] * real[k] + imag[k] * imag[k]
            let third = Int(thirdMap[k])
            if third >= 0 { thirds[third] += power }
            let pitch = Int(chromaMap[k])
            if pitch >= 0 { chroma[pitch] += sqrt(power) }
        }
    }

    public mutating func finish() throws -> AudioMetrics {
        guard Double(frames) > sampleRate * 2, peak > 0.00001 else {
            throw EarError.message("This clip is silent or too quiet to analyze. Try a louder source.")
        }
        if bandFill > 0 {
            for i in bandFill..<Self.bandSize { bandMid[i] = 0; bandSide[i] = 0 }
            analyzeBands()
        }
        if detailFill > Self.detailSize / 4 { analyzeDetail() }
        if hopCount > 0 { envelope.append(sqrt(hopSum / Double(hopCount))) }
        truePeakL.flush(); if channels == 2 { truePeakR.flush() }

        var bands = (0..<5).map { midBands[$0] + sideBands[$0] }
        let total = max(1e-20, bands.reduce(0, +))
        bands = bands.map { $0 / total }
        let frameRate = sampleRate / Double(hop)
        let pulse = Self.estimateTempo(envelope, frameRate: frameRate)
        let samples = Double(frames)
        let rms = sqrt((sumL + sumR) / (2 * samples))
        let duration = samples / sampleRate

        let waveformStride = max(1, Int(ceil(Double(envelope.count) / 420)))
        let waveform = stride(from: 0, to: envelope.count, by: waveformStride).map { start in
            envelope[start..<min(start + waveformStride, envelope.count)].max() ?? 0
        }
        let waveMax = max(1e-8, waveform.max() ?? 1)
        let loudness = Loudness.measure(subBlocks: subBlocks)
        let truePeak = max(truePeakL.maximum, truePeakR.maximum, peak)

        return AudioMetrics(duration: duration, sampleRate: sampleRate, channels: channels,
            peak: Self.db(peak), rms: Self.db(rms), crest: Self.db(peak) - Self.db(rms),
            correlation: max(-1, min(1, cross / max(1e-20, sqrt(sumL * sumR)))),
            sideFraction: sideEnergy / max(1e-20, midEnergy + sideEnergy),
            lowSideFraction: sideBands[0] / max(1e-20, midBands[0] + sideBands[0]),
            midSideFraction: sideBands[2] / max(1e-20, midBands[2] + sideBands[2]),
            balance: (sumR - sumL) / max(1e-20, sumR + sumL), bands: bands,
            bpm: pulse.bpm, tempoStrength: pulse.strength, transientRate: pulse.rate,
            tailSeconds: Self.estimateTail(envelope, frameRate: frameRate), nearFullScale: fullScale / (2 * samples),
            waveform: waveform.map { $0 / waveMax },
            moments: Self.sections(envelope, frameRate: frameRate, duration: duration),
            analysisVersion: AudioMetrics.currentVersion,
            integratedLoudness: loudness.integrated, shortTermMax: loudness.shortTermMax,
            loudnessRange: loudness.range, truePeak: Self.db(truePeak),
            key: KeyFinder.estimate(chroma), spectrum: Self.relativeSpectrum(thirds),
            loudnessTimeline: loudness.timeline)
    }

    public static func db(_ value: Double) -> Double { 20 * log10(max(1e-8, value)) }

    static func relativeSpectrum(_ powers: [Double]) -> [Double]? {
        guard let strongest = powers.max(), strongest > 0 else { return nil }
        var values = powers
        // A band can be empty at low frequencies or low sample rates; borrow its neighbour.
        for i in values.indices where values[i] <= 0 {
            values[i] = values[..<i].last { $0 > 0 } ?? values[i...].first { $0 > 0 } ?? strongest * 1e-6
        }
        return values.map { max(-60, 10 * log10($0 / strongest)) }
    }

    static func sections(_ envelope: [Double], frameRate: Double, duration: Double) -> [Moment] {
        let sectionLength = max(4.0, duration / 8)
        let sectionFrames = max(1, Int(sectionLength * frameRate))
        var moments: [Moment] = []
        for start in stride(from: 0, to: envelope.count, by: sectionFrames) {
            let part = envelope[start..<min(start + sectionFrames, envelope.count)]
            let end = min(duration, Double(start + part.count) / frameRate)
            // A short remainder is not a section; extend the previous one instead.
            if part.count < sectionFrames / 2, let last = moments.indices.last {
                moments[last].end = max(moments[last].end, end)
                continue
            }
            let level = db(sqrt(part.reduce(0) { $0 + $1 * $1 } / Double(part.count)))
            let change = moments.last.map { level - $0.level } ?? 0
            let label = moments.isEmpty ? "Opening" : change > 2.5 ? "Energy lift" : change < -2.5 ? "Pullback" : "Steady passage"
            let startTime = Double(start) / frameRate
            guard end > startTime else { continue }
            moments.append(Moment(id: moments.count, start: startTime, end: end, level: level, change: change, label: label))
        }
        return moments
    }

    public static func estimateTempo(_ envelope: [Double], frameRate: Double) -> (bpm: Double?, strength: Double, rate: Double) {
        guard envelope.count > Int(frameRate * 3) else { return (nil, 0, 0) }
        var onset = [Double](repeating: 0, count: envelope.count)
        for i in 2..<envelope.count { onset[i] = max(0, envelope[i] - (envelope[i - 1] + envelope[i - 2]) * 0.5) }
        let sorted = onset.sorted()
        let threshold = max((sorted.last ?? 0) * 0.12, sorted[Int(Double(sorted.count) * 0.8)] * 1.5)
        var hits = 0, previous = -1000
        for i in onset.indices where onset[i] > threshold && onset[i] > 0.0001 {
            if i - previous > Int(frameRate * 0.09) { hits += 1; previous = i }
        }
        let hitRate = Double(hits) / (Double(envelope.count) / frameRate)
        guard hits >= 6 else { return (nil, 0, hitRate) }
        // Onset autocorrelation gives a tempo candidate, not a beat tracker; the user can tap, halve or double.
        let lags = Int(frameRate * 60 / 180)...Int(frameRate * 60 / 60)
        var scores: [Int: Double] = [:]
        func score(_ lag: Int) -> Double {
            if let cached = scores[lag] { return cached }
            guard lag > 0, lag < onset.count else { return 0 }
            var product = 0.0, a = 0.0, b = 0.0
            for i in lag..<onset.count { product += onset[i] * onset[i - lag]; a += onset[i] * onset[i]; b += onset[i - lag] * onset[i - lag] }
            let value = product / max(1e-20, sqrt(a * b))
            scores[lag] = value
            return value
        }
        var bestLag = 0, bestScore = 0.0
        for lag in lags where score(lag) > bestScore { bestScore = score(lag); bestLag = lag }
        guard bestScore >= 0.16, bestLag > 0 else { return (nil, bestScore, hitRate) }
        // Parabolic interpolation recovers tempo between whole-frame lags (±2.4 BPM at 120 BPM otherwise).
        let before = score(bestLag - 1), after = score(bestLag + 1)
        let curvature = before - 2 * bestScore + after
        let offset = curvature < 0 ? max(-0.5, min(0.5, 0.5 * (before - after) / curvature)) : 0
        let bpm = 60 * frameRate / (Double(bestLag) + offset)
        return (min(240, max(40, (bpm * 10).rounded() / 10)), bestScore, hitRate)
    }

    public static func estimateTail(_ envelope: [Double], frameRate: Double) -> Double? {
        var tails: [Double] = []
        var i = 1
        while i < envelope.count - Int(frameRate * 0.25) {
            let start = envelope[i]
            if start > 0.015 && start > envelope[i - 1] * 1.4 {
                let end = min(envelope.count - 1, i + Int(frameRate * 1.5))
                if end > i {
                    for j in (i + 1)...end {
                        if envelope[j] > start * 1.2 { break }
                        if envelope[j] < start * 0.2512 {
                            let seconds = Double(j - i) / frameRate
                            if seconds >= 0.20 { tails.append(seconds) }
                            i = j; break
                        }
                    }
                }
            }
            i += 1
        }
        guard tails.count >= 4 else { return nil }
        return tails.sorted()[tails.count / 2]
    }
}
