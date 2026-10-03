import Foundation
@testable import EARKit

/// Deterministic test signals fed straight into the analysis engine.
enum Signals {
    static func analyze(rate: Double = 44100, channels: Int = 2, seconds: Double,
                        _ sample: (Int, Double) -> (Float, Float)) throws -> AudioMetrics {
        var engine = try AnalysisEngine(sampleRate: rate, channels: channels)
        let total = Int(seconds * rate), chunk = 8192
        var start = 0
        while start < total {
            let count = min(chunk, total - start)
            var left = [Float](repeating: 0, count: count), right = left
            for i in 0..<count {
                let (l, r) = sample(start + i, Double(start + i) / rate)
                left[i] = l; right[i] = channels == 1 ? l : r
            }
            try engine.process(left: left, right: right)
            start += count
        }
        return try engine.finish()
    }

    static func sine(_ frequency: Double, amplitude: Double, phase: Double = 0) -> (Int, Double) -> (Float, Float) {
        { _, t in let v = Float(sin(2 * .pi * frequency * t + phase) * amplitude); return (v, v) }
    }

    static func demo() throws -> AudioMetrics {
        var track = DemoTrack()
        var engine = try AnalysisEngine(sampleRate: DemoTrack.sampleRate, channels: 2)
        var left = [Float](repeating: 0, count: 4096), right = left
        while !track.isFinished {
            let count = left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in track.render(left: l.baseAddress!, right: r.baseAddress!, capacity: 4096) }
            }
            try engine.process(left: Array(left[..<count]), right: Array(right[..<count]))
        }
        return try engine.finish()
    }

    /// A short chord sequence of sine partials, used for key estimation.
    static func chords(_ progression: [[Double]], secondsEach: Double = 2) throws -> AudioMetrics {
        try analyze(seconds: secondsEach * Double(progression.count)) { _, t in
            let chord = progression[min(progression.count - 1, Int(t / secondsEach))]
            let v = chord.reduce(0.0) { sum, midi in
                let f = 440 * pow(2, (midi - 69) / 12)
                return sum + sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t)
            } * 0.08
            return (Float(v), Float(v))
        }
    }
}
