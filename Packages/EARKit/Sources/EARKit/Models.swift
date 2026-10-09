import Foundation

public enum EarError: LocalizedError, Equatable, Sendable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

public enum Lens: String, CaseIterable, Codable, Identifiable, Sendable {
    case drums = "Drums", vocals = "Vocal layers", delay = "Delay", space = "Reverb"
    case stereo = "Stereo", arrangement = "Arrangement", bass = "Low end", dynamics = "Dynamics", texture = "Texture"

    public var id: String { rawValue }

    /// Stable key used by the bundled knowledge file.
    public var key: String {
        switch self {
        case .drums: "drums"
        case .vocals: "vocals"
        case .delay: "delay"
        case .space: "space"
        case .stereo: "stereo"
        case .arrangement: "arrangement"
        case .bass: "bass"
        case .dynamics: "dynamics"
        case .texture: "texture"
        }
    }

    public var symbol: String {
        switch self {
        case .drums: "waveform.path"
        case .vocals: "person.wave.2"
        case .delay: "repeat"
        case .space: "sparkles"
        case .stereo: "arrow.left.and.right"
        case .arrangement: "rectangle.split.3x1"
        case .bass: "waveform.path.ecg"
        case .dynamics: "slider.horizontal.3"
        case .texture: "circle.lefthalf.filled"
        }
    }
}

public enum DAW: String, CaseIterable, Codable, Identifiable, Sendable {
    case studio = "Studio Pro", logic = "Logic Pro"
    public var id: String { rawValue }
}

public struct Moment: Codable, Identifiable, Hashable, Sendable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var level: Double
    public var change: Double
    public var label: String

    public init(id: Int, start: Double, end: Double, level: Double, change: Double, label: String) {
        self.id = id; self.start = start; self.end = end
        self.level = level; self.change = change; self.label = label
    }
}

/// A tonal-centre candidate from chroma profile matching. It is a listening aid, not a transcription.
public struct KeyEstimate: Codable, Hashable, Sendable {
    public var tonic: Int
    public var minor: Bool
    public var confidence: Double

    public init(tonic: Int, minor: Bool, confidence: Double) {
        self.tonic = tonic; self.minor = minor; self.confidence = confidence
    }

    static let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    public var name: String { "\(Self.names[((tonic % 12) + 12) % 12]) \(minor ? "minor" : "major")" }
    public var shortName: String { "\(Self.names[((tonic % 12) + 12) % 12])\(minor ? "m" : "")" }

    /// Camelot wheel code used by DJs and producers, e.g. C major = 8B, A minor = 8A.
    public var camelot: String {
        let major = minor ? (tonic + 3) % 12 : tonic % 12
        return "\((7 + 7 * major) % 12 + 1)\(minor ? "A" : "B")"
    }

    public var strength: String { confidence >= 0.6 ? "Strong" : confidence >= 0.3 ? "Moderate" : "Tentative" }
}

public struct AudioMetrics: Codable, Sendable {
    /// Bumped whenever measurements change meaningfully; older studies can be re-measured in place.
    public static let currentVersion = 2

    public var duration: Double
    public var sampleRate: Double
    public var channels: Int
    public var peak: Double
    public var rms: Double
    public var crest: Double
    public var correlation: Double
    public var sideFraction: Double
    public var lowSideFraction: Double
    public var midSideFraction: Double
    public var balance: Double
    public var bands: [Double]
    public var bpm: Double?
    public var tempoStrength: Double
    public var transientRate: Double
    public var tailSeconds: Double?
    public var nearFullScale: Double
    public var waveform: [Double]
    public var moments: [Moment]

    // Version 2. Optional so that version-1 notebooks continue to decode.
    public var analysisVersion: Int?
    public var integratedLoudness: Double?
    public var shortTermMax: Double?
    public var loudnessRange: Double?
    public var truePeak: Double?
    public var key: KeyEstimate?
    /// Third-octave spectrum from 31.5 Hz to 16 kHz, in dB relative to the strongest band.
    public var spectrum: [Double]?
    /// Short-term (3 s) loudness over time in LUFS.
    public var loudnessTimeline: [Double]?

    public init(duration: Double, sampleRate: Double, channels: Int, peak: Double, rms: Double, crest: Double,
                correlation: Double, sideFraction: Double, lowSideFraction: Double, midSideFraction: Double,
                balance: Double, bands: [Double], bpm: Double?, tempoStrength: Double, transientRate: Double,
                tailSeconds: Double?, nearFullScale: Double, waveform: [Double], moments: [Moment],
                analysisVersion: Int? = nil, integratedLoudness: Double? = nil, shortTermMax: Double? = nil,
                loudnessRange: Double? = nil, truePeak: Double? = nil, key: KeyEstimate? = nil,
                spectrum: [Double]? = nil, loudnessTimeline: [Double]? = nil) {
        self.duration = duration; self.sampleRate = sampleRate; self.channels = channels
        self.peak = peak; self.rms = rms; self.crest = crest; self.correlation = correlation
        self.sideFraction = sideFraction; self.lowSideFraction = lowSideFraction; self.midSideFraction = midSideFraction
        self.balance = balance; self.bands = bands; self.bpm = bpm; self.tempoStrength = tempoStrength
        self.transientRate = transientRate; self.tailSeconds = tailSeconds; self.nearFullScale = nearFullScale
        self.waveform = waveform; self.moments = moments; self.analysisVersion = analysisVersion
        self.integratedLoudness = integratedLoudness; self.shortTermMax = shortTermMax
        self.loudnessRange = loudnessRange; self.truePeak = truePeak; self.key = key
        self.spectrum = spectrum; self.loudnessTimeline = loudnessTimeline
    }

    public var isCurrent: Bool { (analysisVersion ?? 1) >= Self.currentVersion }
}

public struct Study: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var created = Date()
    public var filename: String
    public var source: String
    public var metrics: AudioMetrics
    public var tempoOverride: Double?
    public var notes = ""
    public var completed: [String] = []

    public init(title: String, filename: String, source: String, metrics: AudioMetrics) {
        self.title = title; self.filename = filename; self.source = source; self.metrics = metrics
    }

    public var tempo: Double? { tempoOverride ?? metrics.bpm }
    public static let demoSource = "EAR original study"
    public var isDemo: Bool { source == Self.demoSource }
}

public func decimal(_ value: Double, _ digits: Int) -> String { String(format: "%.*f", digits, value) }
public func percent(_ value: Double) -> String { decimal(value * 100, 0) + "%" }
public func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", s / 60, s % 60)
}
