# EAR

A native iOS 26+ listening instrument in the Aeon family. Import a song, investigate its production choices, and take a practical experiment into Studio Pro or Logic Pro.

## Included

- Security-scoped Files import and Open in EAR for unprotected audio supported by AVFoundation (WAV, AIFF, CAF, MP3, M4A/AAC and compatible FLAC).
- On-device microphone capture, limited to 30 seconds; the room and speaker affect those results.
- Streaming audio analysis with bounded PCM memory, cancellation, meaningful errors, 3-second/15-minute duration limits, stereo/mono validation, and a 500 MB import limit.
- Spectrum, sample peak/RMS/crest, stereo correlation, mid/side energy, level-based moments, onset tempo candidates, transient density and qualified envelope-decay candidates.
- Nine production lenses: drums, vocal layers, delay, reverb, stereo, arrangement, low end, dynamics and texture.
- Playback, scrubbing, section loops, true mono-sum audition, tempo tap/half/double, persistent notes and completed experiments, report/experiment sharing.
- An original generated instrumental study, Afterglow; it contains no vocals and is never represented as a commercial reference.
- Aeon Nocturne typography, atmospheric linework, native Liquid Glass navigation/controls, Dynamic Type and VoiceOver labels.

## What the report means

EAR 1.0 uses deterministic signal analysis and an authored, measurement-aware teaching layer. There is no cloud AI, track-recognition service or source-separation model. Observations are explicitly separated into measurements, interpretations and listening hypotheses. It cannot recover exact plugins, vocal take counts, reverb types or compressor settings from a mix. Delay values are derived from the selected tempo, not detected echo taps. Level windows are not semantic verse/chorus detection. RMS is not LUFS; sample peak is not true peak. The user can correct tempo before using experiments.

No network requests are made by the app, except when the user opens an external reference manual. Audio and JSON notebook data live in the app’s Documents/Studies directory. Imports preserve the original. There are no keys or accounts to configure. Protected streaming downloads and streaming URLs are unsupported.

Stufo’s current version exposes no deep-link contract. EAR shares portable experiment notes and includes matching Studio Pro instruction; it does not claim a working app-to-app handoff.

## Build and delivery

Open `EAR.xcodeproj` in Xcode 26 or later. Bundle ID: `com.aeon.ear`; minimum iOS: 26.0. No third-party runtime dependencies.

The push-triggered workflow compiles a Release arm64 device app, packages an **unsigned** IPA and uploads it before validation. Signing is required before installation. Each build/validation stage has a hard 600-second ceiling and no retry loop. Source SHA and run number are embedded in `BuildManifest.json`.

After the IPA, the workflow verifies known audio signals (silence, centered/inverted stereo, spectrum, pulse, peak/RMS/crest, mono cancellation), then runs a native UI journey covering study generation, playback, mono audition, tempo editing, an experiment and persistence. Screenshots are saved as workflow artifacts. Simulator checks do not establish physical-device acceptance.

The Xcode project is deterministic: `python3 scripts/project.py`. The icon source is `scripts/icon.svg`.

## Technical references

- [Apple: Liquid Glass custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple: AVAudioFile](https://developer.apple.com/documentation/avfaudio/avaudiofile)
- [Apple: Stereo Delay](https://support.apple.com/en-am/guide/logicpro/lgcef18b892f/mac)
- [Fender Studio Pro manual](https://s1manual.presonus.com/)

The production exercises are original teaching content. Parameter values are audition starts, not claims about a reference artist’s session. Aeon Nocturne and its complete license/attribution files are included from the owner’s Aeon project.
