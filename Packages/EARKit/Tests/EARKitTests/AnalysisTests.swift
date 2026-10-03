import Foundation
import Testing
@testable import EARKit

@Suite struct AnalysisTests {
    @Test func demoTrackProducesACompleteReport() throws {
        let result = try Signals.demo()
        #expect(abs(result.duration - 30) < 0.01)
        #expect(result.channels == 2)
        #expect(result.crest.isFinite && result.bands.count == 5)
        #expect(abs(result.bands.reduce(0, +) - 1) < 0.001)
        #expect(result.waveform.count <= 420 && result.moments.count >= 5)
        #expect(result.analysisVersion == AudioMetrics.currentVersion)
        #expect(result.spectrum?.count == AnalysisEngine.thirdCentres.count)
        #expect(result.spectrum?.max() == 0)
        #expect(result.loudnessTimeline?.isEmpty == false)
        let lufs = try #require(result.integratedLoudness)
        #expect((-30 ... -5).contains(lufs))
        let truePeak = try #require(result.truePeak)
        #expect(truePeak >= result.peak - 0.001)
        if let bpm = result.bpm {
            // 96 BPM, or a half/double-time reading of it.
            #expect([48.0, 96, 192].contains { abs(bpm - $0) < 1.5 }, "Tempo candidate \(bpm)")
        }
    }

    @Test func centredSineIsMonoCompatibleAndLowHeavy() throws {
        let centred = try Signals.analyze(seconds: 4, Signals.sine(100, amplitude: 0.4))
        #expect(centred.correlation > 0.999 && centred.sideFraction < 0.00001)
        #expect(centred.bands[0] > 0.95 && centred.bpm == nil)
        #expect(abs(centred.peak - (-7.96)) < 0.1 && abs(centred.crest - 3.01) < 0.1)
    }

    @Test func antiphaseSignalIsAllSide() throws {
        let inverted = try Signals.analyze(seconds: 4) { _, t in
            let v = Float(sin(2 * .pi * 100 * t) * 0.4); return (v, -v)
        }
        #expect(inverted.correlation < -0.999 && inverted.sideFraction > 0.999)
        #expect(inverted.bands[0] > 0.95, "Spectrum must preserve antiphase source energy")
    }

    @Test func silenceIsRejected() {
        #expect(throws: EarError.self) { try Signals.analyze(seconds: 4) { _, _ in (0, 0) } }
    }

    @Test func invalidSamplesAreRejected() {
        #expect(throws: EarError.self) { try Signals.analyze(seconds: 4) { i, _ in i == 1000 ? (.nan, 0) : (0.1, 0.1) } }
    }

    @Test func surroundAndOddRatesAreRejected() {
        #expect(throws: EarError.self) { _ = try AnalysisEngine(sampleRate: 48000, channels: 6) }
        #expect(throws: EarError.self) { _ = try AnalysisEngine(sampleRate: 4000, channels: 2) }
    }

    @Test func sectionsCoverTheWholeClipWithoutSlivers() throws {
        let metrics = try Signals.analyze(seconds: 37) { _, t in
            let v = Float(sin(2 * .pi * 220 * t) * (t > 20 ? 0.5 : 0.1)); return (v, v)
        }
        let moments = metrics.moments
        #expect(moments.first?.start == 0)
        #expect(abs((moments.last?.end ?? 0) - metrics.duration) < 0.02)
        for (a, b) in zip(moments, moments.dropFirst()) { #expect(abs(a.end - b.start) < 0.02) }
        let shortest = moments.map { $0.end - $0.start }.min() ?? 0
        #expect(shortest >= 2, "A remainder shorter than half a section must merge into the previous one")
        #expect(moments.contains { $0.label == "Energy lift" })
    }

    @Test func tempoFromRegularPulse() {
        let envelope = (0..<1200).map { $0 % 50 == 0 ? 1.0 : 0.01 }
        let pulse = AnalysisEngine.estimateTempo(envelope, frameRate: 100)
        #expect(pulse.bpm == 120 || pulse.bpm == 60, "120 BPM pulse must yield the pulse or half-time candidate")
    }

    @Test func tempoResolvesBetweenWholeFrameLags() throws {
        // 123 BPM is 48.78 envelope frames per beat: whole-frame lags alone give 122.4 or 125.
        let period = 100 * 60 / 123.0
        let beats = Set((0..<40).map { Int((Double($0) * period).rounded()) })
        let envelope = (0..<1950).map { beats.contains($0) ? 1.0 : 0.01 }
        let bpm = try #require(AnalysisEngine.estimateTempo(envelope, frameRate: 100).bpm)
        #expect(abs(bpm - 123) < 0.8, "Interpolated tempo \(bpm)")
    }

    @Test func decayNeedsSeveralCleanTails() {
        #expect(AnalysisEngine.estimateTail([Double](repeating: 0.1, count: 500), frameRate: 100) == nil)
    }
}

@Suite struct LoudnessTests {
    @Test func kWeightingMatchesPublishedCoefficientsAt48kHz() {
        let (shelf, pass) = KWeighting(sampleRate: 48000).coefficients
        #expect(abs(shelf.b0 - 1.53512485958697) < 1e-6)
        #expect(abs(shelf.b1 - -2.69169618940638) < 1e-6)
        #expect(abs(shelf.b2 - 1.19839281085285) < 1e-6)
        #expect(abs(shelf.a1 - -1.69065929318241) < 1e-6)
        #expect(abs(shelf.a2 - 0.73248077421585) < 1e-6)
        #expect(abs(pass.a1 - -1.99004745483398) < 1e-6)
        #expect(abs(pass.a2 - 0.99007225036621) < 1e-6)
    }

    @Test(arguments: [44100.0, 48000, 96000])
    func stereoSineAtMinus20dBFSReadsMinus20LUFS(rate: Double) throws {
        // A 1 kHz sine at −20 dBFS in both channels measures −20 LUFS (BS.1770 reference behaviour).
        let metrics = try Signals.analyze(rate: rate, seconds: 10, Signals.sine(1000, amplitude: 0.1))
        let lufs = try #require(metrics.integratedLoudness)
        #expect(abs(lufs - -20) < 0.1, "Measured \(lufs) LUFS at \(rate) Hz")
        #expect(try #require(metrics.loudnessRange) < 0.5)
        #expect(abs(try #require(metrics.shortTermMax) - -20) < 0.15)
    }

    @Test func monoChannelIsNotDoubled() throws {
        let metrics = try Signals.analyze(rate: 48000, channels: 1, seconds: 10, Signals.sine(1000, amplitude: 0.1))
        #expect(abs(try #require(metrics.integratedLoudness) - -23.01) < 0.1)
    }

    @Test func relativeGateIgnoresSilence() throws {
        // Half tone, half near-silence: gating keeps the integrated value at the tone's loudness.
        let metrics = try Signals.analyze(rate: 48000, seconds: 20) { _, t in
            let v = t < 10 ? Float(sin(2 * .pi * 1000 * t) * 0.1) : Float(sin(2 * .pi * 1000 * t) * 0.0001)
            return (v, v)
        }
        #expect(abs(try #require(metrics.integratedLoudness) - -20) < 0.2)
    }

    @Test func loudnessRangeSeesTwoLevels() throws {
        let metrics = try Signals.analyze(rate: 48000, seconds: 40) { _, t in
            let v = Float(sin(2 * .pi * 1000 * t) * (t < 20 ? 0.1 : 0.01)); return (v, v)
        }
        let range = try #require(metrics.loudnessRange)
        #expect(range > 17 && range < 21, "Range \(range) LU")
    }

    @Test func truePeakFindsTheInterSamplePeak() throws {
        // fs/4 at 45° phase: every sample sits at 0.707 of the waveform's real peak (−3 dB).
        let metrics = try Signals.analyze(rate: 48000, seconds: 4, Signals.sine(12000, amplitude: 0.5, phase: .pi / 4))
        #expect(abs(metrics.peak - -9.03) < 0.05)
        let truePeak = try #require(metrics.truePeak)
        #expect(abs(truePeak - -6.02) < 0.3, "True peak \(truePeak) dBTP")
    }

    @Test func truePeakMatchesSamplePeakForLowFrequencies() throws {
        let metrics = try Signals.analyze(rate: 48000, seconds: 4, Signals.sine(997, amplitude: 0.5))
        #expect(abs(try #require(metrics.truePeak) - metrics.peak) < 0.05)
    }

    @Test func normalizationReferences() {
        let spotify = LoudnessTarget.references.first { $0.name == "Spotify" }!
        #expect(spotify.adjustment(for: -8) == -6)
    }
}

@Suite struct KeyTests {
    @Test func cMajorProgression() throws {
        // C, F, G, C major triads.
        let metrics = try Signals.chords([[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]])
        let key = try #require(metrics.key)
        #expect(key.tonic == 0 && !key.minor, "Estimated \(key.name)")
        #expect(key.camelot == "8B")
    }

    @Test func aMinorProgression() throws {
        // Am, Dm, E, Am.
        let metrics = try Signals.chords([[57, 60, 64], [62, 65, 69], [64, 68, 71], [57, 60, 64]])
        let key = try #require(metrics.key)
        #expect(key.tonic == 9 && key.minor, "Estimated \(key.name)")
        #expect(key.camelot == "8A" && key.shortName == "Am")
    }

    @Test func camelotWheel() {
        #expect(KeyEstimate(tonic: 7, minor: false, confidence: 1).camelot == "9B")
        #expect(KeyEstimate(tonic: 5, minor: false, confidence: 1).camelot == "7B")
        #expect(KeyEstimate(tonic: 4, minor: true, confidence: 1).camelot == "9A")
        #expect(KeyEstimate(tonic: 1, minor: false, confidence: 1).camelot == "3B")
    }
}

@Suite struct FFTTests {
    @Test func impulseIsFlat() {
        let fft = FFT(size: 16)
        var re = [Double](repeating: 0, count: 16), im = re
        re[0] = 1
        fft.transform(&re, &im)
        #expect(re.allSatisfy { abs($0 - 1) < 1e-12 } && im.allSatisfy { abs($0) < 1e-12 })
    }

    @Test func sineLandsInItsBin() {
        let fft = FFT(size: 64)
        var re = (0..<64).map { cos(2 * .pi * 5 * Double($0) / 64) }, im = [Double](repeating: 0, count: 64)
        fft.transform(&re, &im)
        let power = (0..<32).map { re[$0] * re[$0] + im[$0] * im[$0] }
        #expect(power.firstIndex(of: power.max()!) == 5)
    }
}
