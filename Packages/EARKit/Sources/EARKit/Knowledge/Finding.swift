import Foundation

/// A lens-specific reading of the measurements. Measurements, interpretations and listening
/// hypotheses are labelled separately so the report never overstates what a mix can reveal.
public struct Finding: Identifiable, Sendable {
    public var lens: Lens
    public var title: String
    public var kind: String
    public var evidence: String
    public var listen: String
    public var id: Lens { lens }

    public static func make(_ lens: Lens, study: Study) -> Finding {
        let m = study.metrics
        switch lens {
        case .drums:
            return Finding(
                lens: lens,
                title: m.transientRate > 2.5 ? "An active transient pattern" : "Space between the hits",
                kind: "MEASURED → INTERPRETATION",
                evidence: "The mix has about \(decimal(m.transientRate, 1)) distinct energy rises per second. "
                    + "Its peak-to-average gap is \(decimal(m.crest, 1)) dB. Sharp hits may be drums, plucks or consonants; "
                    + "these are not isolated drum measurements.",
                listen: "Loop a busy passage. Is the kick short and percussive, or does it ring into the bass? "
                    + "Does the snare sound dry, roomy or deliberately softened?")
        case .vocals:
            return Finding(
                lens: lens,
                title: m.midSideFraction > 0.14 ? "Explore the edges of the lead" : "Look for a central anchor",
                kind: "LISTENING HYPOTHESIS",
                evidence: "\(percent(m.midSideFraction)) of the 500 Hz–2.5 kHz mid/side energy is in the difference signal. "
                    + "Panned instruments, doubles and effects can all contribute. "
                    + "EAR cannot establish vocal presence or take count from this measurement.",
                listen: "Listen for independent consonants, breaths and pitch movement around the lead. "
                    + "Identical timing with repeating tails suggests an effect; different articulation can suggest a real double. "
                    + "Instrumental track? Apply this to its lead instrument.")
        case .delay:
            let timing = study.tempo.map {
                "At \(decimal($0, 0)) BPM, an eighth note is \(decimal(30000 / $0, 0)) ms and a dotted eighth is \(decimal(45000 / $0, 0)) ms."
            } ?? "The pulse is unclear. Set or tap a tempo to calculate delay times."
            return Finding(
                lens: lens,
                title: "Follow the repeats",
                kind: "TEMPO-BASED EXPERIMENT",
                evidence: timing + " These are timing candidates to audition, not detected echoes. "
                    + "Repeated drums can resemble delay in a mixed waveform.",
                listen: "Loop the end of a phrase. Follow the first clear repeat and count its distance from the original. "
                    + "Listen for darker repeats, left/right movement and feedback that lasts into the next line.")
        case .space:
            let decay = m.tailSeconds.map { "Selected falling-energy windows take about \(decimal($0, 2)) s to drop 12 dB. " }
                ?? "There are too few clean falling-energy windows for a useful decay estimate. "
            return Finding(
                lens: lens,
                title: "Find the space after the sound",
                kind: "LISTENING HYPOTHESIS",
                evidence: decay + "This describes the mix envelope, not a measured reverb time. "
                    + "Sustained notes, noise and overlapping hits can mask or imitate a tail.",
                listen: "Find an exposed stop. A short cluster of reflections can suggest a room; a smooth dense tail can suggest a plate or hall. "
                    + "Listen for a small dry gap before the ambience starts.")
        case .stereo:
            let title = m.channels == 1 ? "A mono source"
                : m.correlation < 0 ? "A strong difference signal"
                : m.sideFraction > 0.20 ? "A wide stereo field" : "A focused stereo image"
            let balance = abs(m.balance) < 0.08 ? "Average left/right energy is balanced."
                : "Average energy leans \(m.balance > 0 ? "right" : "left")."
            return Finding(
                lens: lens,
                title: title,
                kind: "MEASURED",
                evidence: "Stereo correlation: \(decimal(m.correlation, 2)). Side energy: \(percent(m.sideFraction)). \(balance) "
                    + "Side means L−R information, not a separated instrument. Negative correlation can indicate cancellation when summed.",
                listen: "Use the Mono audition button. Which layers shrink or disappear? "
                    + "Keep the emotional center stable while checking whether the width still serves the track in mono.")
        case .arrangement:
            let strongest = m.moments.dropFirst().max { abs($0.change) < abs($1.change) }
            let change = strongest.map {
                "The largest measured section-level change is near \(clock($0.start)): \(decimal($0.change, 1)) dB against the preceding window. "
            } ?? "This clip is too short to map several sections. "
            return Finding(
                lens: lens,
                title: "Trace the changes in energy",
                kind: "MEASURED → INTERPRETATION",
                evidence: change + "Windows reflect energy changes; they are not automatic verse/chorus labels.",
                listen: "Jump between the moments. What enters or leaves: hats, bass, doubles, reverb or silence? "
                    + "A lift can come from contrast, not simply a louder master.")
        case .bass:
            return Finding(
                lens: lens,
                title: m.bands[0] > 0.45 ? "Low frequencies carry the weight" : "Listen to the kick–bass handoff",
                kind: "MEASURED → INTERPRETATION",
                evidence: "20–160 Hz contributes \(percent(m.bands[0])) of the measured spectral energy; "
                    + "\(percent(m.lowSideFraction)) of low-band mid/side energy is on the sides. "
                    + "This does not separate kick from bass or prove sidechain compression.",
                listen: "Listen for the bass dipping when the kick hits, or a bass note starting just after it. "
                    + "Compare timing, note length and register before reaching for more processing.")
        case .dynamics:
            let levels: String
            if let lufs = m.integratedLoudness, let truePeak = m.truePeak {
                let range = m.loudnessRange.map { " • range \(decimal($0, 1)) LU" } ?? ""
                levels = "Integrated loudness \(decimal(lufs, 1)) LUFS\(range) • true peak \(decimal(truePeak, 1)) dBTP • "
                    + "crest \(decimal(m.crest, 1)) dB. A smaller crest or range can come from limiting, compression, clipping or sustained sources. "
                    + "These values do not reveal compressor settings."
            } else {
                levels = "Sample peak \(decimal(m.peak, 1)) dBFS • RMS \(decimal(m.rms, 1)) dBFS • crest \(decimal(m.crest, 1)) dB. "
                    + "A smaller crest can come from limiting, compression, clipping or sustained sources. "
                    + "Re-measure this study for LUFS and true peak. These values do not reveal compressor settings."
            }
            let dense = m.loudnessRange.map { $0 < 5 } ?? (m.crest < 9)
            return Finding(
                lens: lens,
                title: dense ? "A dense amplitude envelope" : "Transient headroom remains",
                kind: "MEASURED → INTERPRETATION",
                evidence: levels,
                listen: "Do loud hits push the rest of the mix down? Does it recover before the next beat? "
                    + "Compare a sparse section with the busiest one to distinguish arrangement density from audible pumping.")
        case .texture:
            return Finding(
                lens: lens,
                title: "Separate grit from brightness",
                kind: "LISTENING HYPOTHESIS",
                evidence: "\(percent(m.nearFullScale)) of samples reach ±0.999; high-band spectral energy is \(percent(m.bands[3] + m.bands[4])). "
                    + "Neither establishes distortion. Saturation may remain after a track is turned down, "
                    + "and cymbals can create similar high-frequency energy.",
                listen: "Listen to held vowels and bass notes. Does the grain follow note level? Is the texture on one instrument or the whole mix? "
                    + "Crackle, aliasing, clipping and intentional saturation are different causes.")
        }
    }
}

extension Study {
    public var shareText: String {
        var header = "EAR — \(title)\n\(clock(metrics.duration)) • \(source)\n"
        var facts: [String] = []
        if let tempo { facts.append("\(decimal(tempo, 0)) BPM") }
        if let key = metrics.key { facts.append("\(key.name) (\(key.camelot))") }
        if let lufs = metrics.integratedLoudness { facts.append("\(decimal(lufs, 1)) LUFS") }
        if let truePeak = metrics.truePeak { facts.append("\(decimal(truePeak, 1)) dBTP") }
        if !facts.isEmpty { header += facts.joined(separator: " • ") + "\n" }
        let findings = Lens.allCases.map { lens in
            let f = Finding.make(lens, study: self)
            return "\(lens.rawValue.uppercased()) — \(f.title)\n\(f.kind)\n\(f.evidence)\nListen: \(f.listen)"
        }.joined(separator: "\n\n")
        return header + "\n" + findings + "\n\nMY NOTES\n\(notes)\n\n"
            + "EAR measures the stereo mix. Production causes remain hypotheses; it does not identify exact plugins, isolate stems or count vocal takes."
    }
}
