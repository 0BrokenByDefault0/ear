# EAR

**Hear how records are made.** EAR is a native iOS 26 listening instrument for producers and curious listeners. Bring a song you love: EAR measures it on your device, explains what those measurements can and cannot tell you, and turns them into short experiments for Studio Pro or Logic Pro.

No account, no upload, no cloud model.

## Features

**Measure honestly**
- **Loudness** — integrated and short-term LUFS (ITU-R BS.1770-4), loudness range (EBU Tech 3342), a loudness-over-time graph, and how Spotify, YouTube, Apple Music and broadcast normalization would treat the master.
- **True peak** — 4× oversampled inter-sample peak in dBTP, with a headroom note.
- **Key** — a tonal-centre candidate from chroma profile matching, shown with its Camelot code and a confidence label.
- **Tempo** — an onset-autocorrelation candidate with sub-frame interpolation. Tap, halve or double it; your setting drives every delay time.
- **Tone and space** — third-octave spectrum, five broad bands, mid/side balance, stereo correlation, low-end width, transient density and envelope decay.
- Each finding is labelled as **measured**, **interpretation** or **listening hypothesis**.

**Listen closely**
- Sample-accurate phrase loops on AVAudioEngine. Tap a detected section, or mark your own start and end.
- A true (L+R)/2 mono fold-down to hear what survives on a phone speaker.
- A scrubbable waveform with section markers. The transport stays with you inside every lens and experiment.

**Practise**
- Nine production lenses, each with a listening guide and four experiments (36 in all): drums, vocal layers, delay, reverb, stereo, arrangement, low end, dynamics and texture.
- Steps use your DAW's routing, plug-in names and menu paths. Each experiment ends with a listening check and what to do if it fails.
- A delay-time calculator, and Lab progress tracked across all your studies.

**Keep what you learn**
- A notebook with search (titles, keys and notes), sorting, rename, and notes for each study.
- Share a full text report, or a designed 1080 × 1350 study card image.
- **Afterglow**, an original generated instrumental, lets you try everything immediately.

## Privacy

EAR makes no network requests, except when you open a reference manual link. Audio and notebook data live in the app's `Documents/Studies` folder, which is visible in Files under *On My iPhone → EAR*. Mono audition files are kept in Caches and can be regenerated. Imports never modify the original file.

## Honest limits

EAR analyses the finished stereo mix. It cannot recover exact plug-ins, vocal take counts, reverb models or compressor settings. Delay times come from the tempo, not from detected echoes. Sections follow level changes; they are not verse/chorus labels. Key and tempo are candidates; tempo can read half or double time.

## Project layout

```
EAR/                     SwiftUI app (synchronized folder: new files are picked up automatically)
  App/                   App entry, EarStore state, PlaybackEngine (AVAudioEngine)
  Design/                Theme tokens, shared components, visualisations
  Views/                 Screens
  Resources/             Info.plist, assets, font and licences
Packages/EARKit/         Platform-independent core: builds and tests on Linux and macOS
  Sources/EARKit/
    Analysis/            Streaming analysis engine, FFT, BS.1770 loudness, true peak, key
    Knowledge/           Findings, experiments, guides (content in Resources/Knowledge.json)
    Audio/               Demo track; AVFoundation import, decode and mono fold-down (Apple only)
    Notebook.swift       Versioned notebook format with last-good backup and recovery
  Tests/EARKitTests/     Swift Testing suite
EARUITests/              XCUITest journeys, which also produce App Store screenshots
marketing/               App Store copy, keywords and privacy policy
```

## Build

Open `EAR.xcodeproj` in Xcode 26 or later and run the **EAR** scheme. Bundle ID `com.aeon.ear`; minimum iOS 26.0. There are no third-party dependencies.

Run the core tests without a simulator, on macOS or Linux:

```sh
cd Packages/EARKit && swift test
```

The version is set once, as `MARKETING_VERSION` in the project. The app and CI read it from the built bundle.

## Notebook format

`notebook.json` is a versioned envelope: `{ "version": 2, "studies": [...], "labTried": [...] }`.

- **Older files.** EAR 1.x files, which were a bare array of studies, still open. They are upgraded on the next save, and the old file is kept as the backup.
- **Newer files.** A file written by a newer EAR is refused rather than overwritten.
- **Adding measurements.** New measurements are optional fields, so older studies keep decoding. Bump `AudioMetrics.currentVersion` when measurements change; studies below it offer **Re-measure**, which keeps notes, tempo and progress.
- **Recovery.** Every save validates the data and keeps the previous good index as `notebook.json.backup`. A damaged index is preserved beside it, and EAR says so.

## Teaching content

The guides and experiments live in `Packages/EARKit/Sources/EARKit/Resources/Knowledge.json`. Text can use these tokens, filled in per DAW:

| Token | Filled with |
|---|---|
| `{route}`, `{routing}` | Send/return routing instructions |
| `{return}` | The return channel name |
| `{delay}`, `{reverb}` | Stock plug-in names |
| `{kickSidechain}`, `{vocalSidechain}` | Sidechain routing |
| `{tempo}`, `{eighth}` | A tempo-derived timing sentence |

A field can also be `{"Studio Pro": "...", "Logic Pro": "..."}`. `KnowledgeTests.contentMatchesEAR12Exactly` pins every render to the EAR 1.2 wording, so update that fixture when content changes on purpose.

## Continuous integration

`.github/workflows/ios.yml` runs on pushes to `main`, `codex/**` and `claude/**`, and on pull requests. Each stage has a hard time limit and no automatic retries.

| Job | Runs |
|---|---|
| `kit-linux`, `kit-macos` | EARKit tests. The macOS run also covers AVFoundation import, decode, cancellation and mono fold-down. |
| `ipa` | A Release arm64 device build, packaged as an **unsigned** IPA with `BuildManifest.json`. It checks that EARKit resources ship and that test fixtures do not. Signing is required before installation. |
| `ui` | XCUITest journeys on a fresh iOS 26 simulator: onboarding; the full import pipeline and persistence; invalid-file recovery; picker present, cancel and reopen; demo study, playback, mono, phrase loops, tempo editing, lens and experiment, completion, notes, end-of-track replay; Lab search and progress. |

Screenshots from the UI run are uploaded as workflow artifacts. Simulator checks do not establish physical-device acceptance.

UI tests import files through a debug-only `--import-fixture` launch argument. That exercises the same copy, analysis and save path as the Files picker. The picker itself is checked for present, cancel and reopen only. On the CI simulator, a file tapped in the document browser is never returned to any app: a minimal control app containing nothing but a `fileImporter` failed the same way. Choosing a file in Files therefore has to be checked on a device.

EAR presents the document browser from UIKit (`AudioPicker`) with single selection and `asCopy: true`. The system downloads and copies the chosen file into EAR's inbox before handing it over, and EAR removes that copy after import.

## References

- [ITU-R BS.1770-4: loudness and true-peak measurement](https://www.itu.int/rec/R-REC-BS.1770)
- [EBU Tech 3342: loudness range](https://tech.ebu.ch/publications/tech3342)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple: AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [Fender Studio Pro manual](https://s1manual.presonus.com/) · [Logic Pro user guide](https://support.apple.com/guide/logicpro/welcome/mac)

The production exercises are original teaching content; parameter values are audition starts, not claims about any artist's session. Aeon Nocturne and its licence and attribution files are included from the owner's Aeon project.
