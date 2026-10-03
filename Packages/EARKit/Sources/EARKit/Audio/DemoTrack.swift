import Foundation

/// "Afterglow": an original deterministic instrumental at 96 BPM with kick, bass, a wide pad,
/// hats and a breakdown. It is never presented as a commercial reference.
public struct DemoTrack: Sendable {
    public static let sampleRate = 44100.0
    public static let duration = 30.0
    public static let title = "Afterglow"
    public static var frameCount: Int { Int(duration * sampleRate) }

    private var seed: UInt32 = 417
    private var position = 0

    public init() {}

    public var isFinished: Bool { position >= Self.frameCount }

    /// Renders up to `capacity` frames into the two channel buffers and returns the frame count.
    public mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        let rate = Self.sampleRate, duration = Self.duration
        let count = min(capacity, Self.frameCount - position)
        for i in 0..<max(0, count) {
            let t = Double(position + i) / rate
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
            let fade = max(0, min(1, min(t / 0.3, (duration - t) / 0.8)))
            let common = kick + hat + snare + bass
            let padL = (sin(t * 2 * .pi * (root * 4 - 0.25)) + sin(t * 2 * .pi * root * 5.99)) * 0.065
            let padR = (sin(t * 2 * .pi * (root * 4 + 0.25)) + sin(t * 2 * .pi * root * 5.99 + 1)) * 0.065
            left[i] = Float((common + padL) * fade)
            right[i] = Float((common + padR) * fade)
        }
        position += max(0, count)
        return max(0, count)
    }
}
