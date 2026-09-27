import Foundation

enum Lens: String, CaseIterable, Codable, Identifiable {
    case drums = "Drums", vocals = "Vocal layers", delay = "Delay", space = "Reverb"
    case stereo = "Stereo", arrangement = "Arrangement", bass = "Low end", dynamics = "Dynamics", texture = "Texture"
    var id: String { rawValue }
    var symbol: String {
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

enum DAW: String, CaseIterable, Identifiable {
    case studio = "Studio Pro", logic = "Logic Pro"
    var id: String { rawValue }
}

struct Moment: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var start: Double
    var end: Double
    var level: Double
    var change: Double
    var label: String
}

struct AudioMetrics: Codable, Sendable {
    var duration: Double
    var sampleRate: Double
    var channels: Int
    var peak: Double
    var rms: Double
    var crest: Double
    var correlation: Double
    var sideFraction: Double
    var lowSideFraction: Double
    var midSideFraction: Double
    var balance: Double
    var bands: [Double]
    var bpm: Double?
    var tempoStrength: Double
    var transientRate: Double
    var tailSeconds: Double?
    var nearFullScale: Double
    var waveform: [Double]
    var moments: [Moment]
}

struct Study: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var created = Date()
    var filename: String
    var source: String
    var metrics: AudioMetrics
    var tempoOverride: Double?
    var notes = ""
    var completed: [String] = []
    var tempo: Double? { tempoOverride ?? metrics.bpm }
    var shareText: String {
        let intro = "EAR — \(title)\n\(clock(metrics.duration)) • \(source)\n"
        return intro + "\n" + Lens.allCases.map { lens in
            let f = Finding.make(lens, study: self)
            return "\(lens.rawValue.uppercased()) — \(f.title)\n\(f.kind)\n\(f.evidence)\nListen: \(f.listen)"
        }.joined(separator: "\n\n") + "\n\nMY NOTES\n\(notes)\n\nEAR measures the stereo mix. Production causes remain hypotheses; it does not identify exact plugins, isolate stems or count vocal takes."
    }
}

struct Finding: Identifiable {
    var lens: Lens
    var title: String
    var kind: String
    var evidence: String
    var listen: String
    var id: Lens { lens }

    static func make(_ lens: Lens, study: Study) -> Finding {
        let m = study.metrics
        switch lens {
        case .drums:
            return Finding(lens: lens, title: m.transientRate > 2.5 ? "An active transient pattern" : "Space between the hits", kind: "MEASURED → INTERPRETATION", evidence: "The mix has about \(decimal(m.transientRate, 1)) distinct energy rises per second. Its peak-to-average gap is \(decimal(m.crest, 1)) dB. Sharp hits may be drums, plucks or consonants; these are not isolated drum measurements.", listen: "Loop a busy passage. Is the kick short and percussive, or does it ring into the bass? Does the snare sound dry, roomy or deliberately softened?")
        case .vocals:
            return Finding(lens: lens, title: m.midSideFraction > 0.14 ? "Explore the edges of the lead" : "Look for a central anchor", kind: "LISTENING HYPOTHESIS", evidence: "\(percent(m.midSideFraction)) of the 500 Hz–2.5 kHz mid/side energy is in the difference signal. Panned instruments, doubles and effects can all contribute. EAR cannot establish vocal presence or take count from this measurement.", listen: "Listen for independent consonants, breaths and pitch movement around the lead. Identical timing with repeating tails suggests an effect; different articulation can suggest a real double. Instrumental track? Apply this to its lead instrument.")
        case .delay:
            let timing = study.tempo.map { "At \(decimal($0, 0)) BPM, an eighth note is \(decimal(30000 / $0, 0)) ms and a dotted eighth is \(decimal(45000 / $0, 0)) ms." } ?? "The pulse is unclear. Set or tap a tempo to calculate delay times."
            return Finding(lens: lens, title: "Follow the repeats", kind: "TEMPO-BASED EXPERIMENT", evidence: timing + " These are timing candidates to audition, not detected echoes. Repeated drums can resemble delay in a mixed waveform.", listen: "Loop the end of a phrase. Follow the first clear repeat and count its distance from the original. Listen for darker repeats, left/right movement and feedback that lasts into the next line.")
        case .space:
            let decay = m.tailSeconds.map { "Selected falling-energy windows take about \(decimal($0, 2)) s to drop 12 dB. " } ?? "There are too few clean falling-energy windows for a useful decay estimate. "
            return Finding(lens: lens, title: "Find the space after the sound", kind: "LISTENING HYPOTHESIS", evidence: decay + "This describes the mix envelope, not a measured reverb time. Sustained notes, noise and overlapping hits can mask or imitate a tail.", listen: "Find an exposed stop. A short cluster of reflections can suggest a room; a smooth dense tail can suggest a plate or hall. Listen for a small dry gap before the ambience starts.")
        case .stereo:
            let title = m.channels == 1 ? "A mono source" : m.correlation < 0 ? "A strong difference signal" : m.sideFraction > 0.20 ? "A wide stereo field" : "A focused stereo image"
            return Finding(lens: lens, title: title, kind: "MEASURED", evidence: "Stereo correlation: \(decimal(m.correlation, 2)). Side energy: \(percent(m.sideFraction)). \(abs(m.balance) < 0.08 ? "Average left/right energy is balanced." : "Average energy leans \(m.balance > 0 ? "right" : "left").") Side means L−R information, not a separated instrument. Negative correlation can indicate cancellation when summed.", listen: "Use the Mono audition button. Which layers shrink or disappear? Keep the emotional center stable while checking whether the width still serves the track in mono.")
        case .arrangement:
            let strongest = m.moments.dropFirst().max { abs($0.change) < abs($1.change) }
            return Finding(lens: lens, title: "Trace the changes in energy", kind: "MEASURED → INTERPRETATION", evidence: (strongest.map { "The largest measured section-level change is near \(clock($0.start)): \(decimal($0.change, 1)) dB against the preceding window. " } ?? "This clip is too short to map several sections. ") + "Windows reflect energy changes; they are not automatic verse/chorus labels.", listen: "Jump between the moments. What enters or leaves: hats, bass, doubles, reverb or silence? A lift can come from contrast, not simply a louder master.")
        case .bass:
            return Finding(lens: lens, title: m.bands[0] > 0.45 ? "Low frequencies carry the weight" : "Listen to the kick–bass handoff", kind: "MEASURED → INTERPRETATION", evidence: "20–160 Hz contributes \(percent(m.bands[0])) of the measured spectral energy; \(percent(m.lowSideFraction)) of low-band mid/side energy is on the sides. This does not separate kick from bass or prove sidechain compression.", listen: "Listen for the bass dipping when the kick hits, or a bass note starting just after it. Compare timing, note length and register before reaching for more processing.")
        case .dynamics:
            return Finding(lens: lens, title: m.crest < 9 ? "A dense amplitude envelope" : "Transient headroom remains", kind: "MEASURED → INTERPRETATION", evidence: "Sample peak \(decimal(m.peak, 1)) dBFS • RMS \(decimal(m.rms, 1)) dBFS • crest \(decimal(m.crest, 1)) dB. A smaller crest can come from limiting, compression, clipping or sustained sources. These values are not LUFS, true peak or compressor settings.", listen: "Do loud hits push the rest of the mix down? Does it recover before the next beat? Compare a sparse section with the busiest one to distinguish arrangement density from audible pumping.")
        case .texture:
            return Finding(lens: lens, title: "Separate grit from brightness", kind: "LISTENING HYPOTHESIS", evidence: "\(percent(m.nearFullScale)) of samples reach ±0.999; high-band spectral energy is \(percent(m.bands[3] + m.bands[4])). Neither establishes distortion. Saturation may remain after a track is turned down, and cymbals can create similar high-frequency energy.", listen: "Listen to held vowels and bass notes. Does the grain follow note level? Is the texture on one instrument or the whole mix? Crackle, aliasing, clipping and intentional saturation are different causes.")
        }
    }
}

func decimal(_ value: Double, _ digits: Int) -> String { String(format: "%.*f", digits, value) }
func percent(_ value: Double) -> String { decimal(value * 100, 0) + "%" }
func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", s / 60, s % 60)
}
