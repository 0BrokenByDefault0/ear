import Foundation

/// Results of ITU-R BS.1770-4 / EBU R128 loudness measurement.
public struct LoudnessResult: Sendable, Equatable {
    public var integrated: Double?
    public var shortTermMax: Double?
    public var range: Double?
    public var timeline: [Double]
}

enum Loudness {
    static func lufs(_ power: Double) -> Double { -0.691 + 10 * log10(max(1e-20, power)) }

    /// - Parameter subBlocks: channel-summed mean-square power of consecutive 100 ms K-weighted windows.
    static func measure(subBlocks: [Double], timelinePoints: Int = 300) -> LoudnessResult {
        func windows(_ count: Int) -> [Double] {
            guard subBlocks.count >= count else { return subBlocks.isEmpty ? [] : [subBlocks.reduce(0, +) / Double(subBlocks.count)] }
            var output: [Double] = [], sum = subBlocks[0..<count].reduce(0, +)
            output.reserveCapacity(subBlocks.count - count + 1)
            output.append(sum / Double(count))
            for index in count..<subBlocks.count {
                sum += subBlocks[index] - subBlocks[index - count]
                output.append(max(0, sum) / Double(count))
            }
            return output
        }

        // Integrated: 400 ms gating blocks with 75% overlap, absolute gate −70 LUFS, relative gate −10 LU.
        let momentary = windows(4)
        let audible = momentary.filter { lufs($0) > -70 }
        var integrated: Double?
        if !audible.isEmpty {
            let threshold = lufs(audible.reduce(0, +) / Double(audible.count)) - 10
            let gated = audible.filter { lufs($0) > threshold }
            if !gated.isEmpty { integrated = lufs(gated.reduce(0, +) / Double(gated.count)) }
        }

        // Short-term: 3 s windows. Loudness range uses EBU Tech 3342 gating and the 10th–95th percentiles.
        let shortTerm = windows(30)
        let shortLoudness = shortTerm.map(lufs)
        let audibleShort = shortTerm.filter { lufs($0) > -70 }
        var range: Double?
        if !audibleShort.isEmpty {
            let threshold = lufs(audibleShort.reduce(0, +) / Double(audibleShort.count)) - 20
            let values = audibleShort.map(lufs).filter { $0 >= threshold }.sorted()
            if values.count >= 2 {
                func percentile(_ p: Double) -> Double { values[min(values.count - 1, Int((Double(values.count - 1) * p).rounded()))] }
                range = max(0, percentile(0.95) - percentile(0.10))
            }
        }

        let stride = max(1, Int(ceil(Double(shortLoudness.count) / Double(timelinePoints))))
        let timeline = Swift.stride(from: 0, to: shortLoudness.count, by: stride).map { start in
            max(-70, shortLoudness[start..<min(start + stride, shortLoudness.count)].max() ?? -70)
        }
        return LoudnessResult(integrated: integrated, shortTermMax: shortLoudness.max().map { max(-70, $0) },
                              range: range, timeline: timeline)
    }
}

/// Typical loudness-normalization references. Services change policies; these are listening references.
public struct LoudnessTarget: Identifiable, Sendable {
    public var name: String
    public var lufs: Double
    public var id: String { name }

    public static let references = [
        LoudnessTarget(name: "Spotify", lufs: -14),
        LoudnessTarget(name: "YouTube", lufs: -14),
        LoudnessTarget(name: "Apple Music", lufs: -16),
        LoudnessTarget(name: "Broadcast (EBU R128)", lufs: -23),
    ]

    /// Gain a normalizing service would typically apply. Positive values are only applied by some services.
    public func adjustment(for integrated: Double) -> Double { lufs - integrated }
}

enum KeyFinder {
    // Krumhansl–Kessler key profiles, C = index 0.
    static let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func estimate(_ chroma: [Double]) -> KeyEstimate? {
        guard chroma.count == 12, chroma.reduce(0, +) > 1e-12 else { return nil }
        func correlation(_ a: [Double], _ b: [Double]) -> Double {
            let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
            var num = 0.0, da = 0.0, db = 0.0
            for i in 0..<12 { num += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) * (a[i] - ma); db += (b[i] - mb) * (b[i] - mb) }
            return num / max(1e-20, sqrt(da * db))
        }
        var scores: [(tonic: Int, minor: Bool, r: Double)] = []
        for tonic in 0..<12 {
            let rotated = (0..<12).map { chroma[($0 + tonic) % 12] }
            scores.append((tonic, false, correlation(rotated, major)))
            scores.append((tonic, true, correlation(rotated, minor)))
        }
        scores.sort { $0.r > $1.r }
        let best = scores[0]
        guard best.r > 0.2 else { return nil }
        // Relative major/minor share a scale, so measure confidence against the best unrelated key.
        let relative = best.minor ? (best.tonic + 3) % 12 : (best.tonic + 9) % 12
        let rival = scores.dropFirst().first { !($0.tonic == relative && $0.minor != best.minor) }?.r ?? 0
        let confidence = max(0, min(1, (best.r - rival) * 4 + (best.r - 0.5)))
        return KeyEstimate(tonic: best.tonic, minor: best.minor, confidence: confidence)
    }
}
