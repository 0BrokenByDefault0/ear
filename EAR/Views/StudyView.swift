import SwiftUI
import EARKit

struct StudyView: View {
    @Environment(EarStore.self) private var store
    @State private var editTempo = false
    @State private var editNotes = false
    @State private var renaming = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let study = store.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(study)
                        if !study.metrics.isCurrent { remeasureBanner(study) }
                        glance(study)
                        if let lufs = study.metrics.integratedLoudness { LoudnessCard(study: study, integrated: lufs) }
                        SpectrumCard(metrics: study.metrics)
                        if study.metrics.channels == 2 { StereoCard(metrics: study.metrics) }
                        moments(study)
                        lenses(study)
                        notes(study)
                        Text("EAR measures the finished stereo mix. It cannot identify exact plug-ins, isolate stems or count vocal takes.")
                            .font(.caption).foregroundStyle(Ink.secondary).lineSpacing(3)
                    }
                    .padding(.top, 8)
                    .page()
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) { TransportView().padding(.horizontal, 16).padding(.bottom, 6) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { store.close() }.accessibilityIdentifier("closeStudy")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: StudyCardExport(study: study), preview: SharePreview("\(study.title) — EAR study card")) {
                            Label("Share card", systemImage: "photo")
                        }
                        .accessibilityIdentifier("shareCard")
                        Menu {
                            ShareLink(item: study.shareText) { Label("Share full report", systemImage: "doc.text") }
                            Button("Rename", systemImage: "pencil") { renaming = true }
                            Button("Re-measure", systemImage: "arrow.triangle.2.circlepath") { store.remeasure(study) }
                            Divider()
                            Button("Delete study", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: { Label("More", systemImage: "ellipsis") }
                        .accessibilityIdentifier("studyMenu")
                    }
                }
                .sheet(isPresented: $editTempo) {
                    NavigationStack { TempoView(studyID: study.id) }.presentationDetents([.medium, .large]).presentationBackground(Ink.background)
                }
                .sheet(isPresented: $editNotes) {
                    NavigationStack { NotesView(studyID: study.id, initial: study.notes) }.presentationBackground(Ink.background)
                }
                .sheet(isPresented: $renaming) {
                    NavigationStack { RenameView(study: study) }.presentationDetents([.medium]).presentationBackground(Ink.background)
                }
                .confirmationDialog("Delete this study and its imported audio copy?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete study", role: .destructive) { store.delete(study) }
                }
            } else {
                ContentUnavailableView("Choose a study", systemImage: "waveform")
            }
        }
        .background { ZStack { Ink.background.ignoresSafeArea(); Atmosphere() } }
        .foregroundStyle(Ink.primary)
        .navigationTitle("Study").navigationBarTitleDisplayMode(.inline)
        .modifier(EarErrorAlert(active: !editTempo && !editNotes && !renaming))
    }

    private func header(_ study: Study) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(study.isDemo ? "An original study" : "A closer listen")
            Text(study.title).font(Ink.display(44)).lineLimit(3).minimumScaleFactor(0.6).accessibilityIdentifier("studyTitle")
                .accessibilityAddTraits(.isHeader)
            Text(study.source).font(.caption).foregroundStyle(Ink.secondary)
            StudyPlayhead(study: study).padding(.top, 14)
        }
    }

    private func remeasureBanner(_ study: Study) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles").foregroundStyle(Ink.warm).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("New measurements available").font(.subheadline.weight(.semibold))
                Text("Re-measure to add LUFS loudness, true peak, key and a detailed spectrum. Notes and progress are kept.")
                    .font(.caption).foregroundStyle(Ink.secondary).lineSpacing(2)
                Button("Re-measure now") { store.remeasure(study) }.buttonStyle(.glass).controlSize(.small).padding(.top, 4)
                    .accessibilityIdentifier("remeasure")
            }
        }
        .card()
    }

    private func glance(_ study: Study) -> some View {
        let m = study.metrics
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader("At a glance")
            LazyVGrid(columns: columns, spacing: 12) {
                Button { editTempo = true } label: {
                    StatTile(label: "Tempo", value: study.tempo.map { decimal($0, 0) } ?? "—", unit: "BPM",
                             detail: study.tempoOverride == nil ? "Candidate · tap to adjust" : "Set by you", tint: Ink.accent, symbol: "metronome")
                }
                .buttonStyle(.plain).accessibilityIdentifier("editTempo")
                StatTile(label: "Key", value: m.key?.shortName ?? "—", unit: m.key?.camelot,
                         detail: m.key.map { "\($0.name) · \($0.strength.lowercased())" } ?? (m.isCurrent ? "No clear tonal centre" : "Re-measure to estimate"),
                         symbol: "music.note")
                StatTile(label: "Loudness", value: m.integratedLoudness.map { decimal($0, 1) } ?? decimal(m.rms, 1),
                         unit: m.integratedLoudness == nil ? "dBFS RMS" : "LUFS",
                         detail: m.loudnessRange.map { "Range \(decimal($0, 1)) LU" } ?? "Integrated", symbol: "speaker.wave.2")
                StatTile(label: m.truePeak == nil ? "Sample peak" : "True peak", value: decimal(m.truePeak ?? m.peak, 1),
                         unit: m.truePeak == nil ? "dBFS" : "dBTP", detail: peakDetail(m),
                         tint: (m.truePeak ?? m.peak) > -1 ? Ink.warm : Ink.primary, symbol: "waveform.badge.exclamationmark")
            }
            HStack(spacing: 6) {
                Chip(text: clock(m.duration), symbol: "clock")
                Chip(text: m.channels == 1 ? "Mono" : "Stereo", symbol: m.channels == 1 ? "circle" : "circle.lefthalf.filled")
                Chip(text: "\(decimal(m.sampleRate / 1000, 1)) kHz")
                Chip(text: "Crest \(decimal(m.crest, 1)) dB")
            }
        }
    }

    private func peakDetail(_ m: AudioMetrics) -> String {
        let value = m.truePeak ?? m.peak
        if value > -0.1 { return "At or over full scale" }
        if value > -1 { return "Little headroom for encoding" }
        return "\(decimal(-value, 1)) dB of headroom"
    }

    private func moments(_ study: Study) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Moments", subtitle: "Sections follow changes in level. Tap one to loop it.") {
                if store.loop != nil || store.loopStart != nil {
                    Button("Clear loop") { store.clearLoop() }.font(.caption).frame(minHeight: 44)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(study.metrics.moments) { moment in
                        Button { store.select(moment) } label: { MomentCard(moment: moment, active: store.loop?.id == moment.id) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func lenses(_ study: Study) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Production lenses", subtitle: "Measurements start the conversation. Your ears test the explanation.") { EmptyView() }
                .padding(.bottom, 8)
            ForEach(Lens.allCases) { lens in
                NavigationLink { FindingView(lens: lens, studyID: study.id) } label: {
                    LensRow(lens: lens, title: Finding.make(lens, study: study).title,
                            done: Experiment.catalog(lens, daw: .studio, tempo: nil).contains { study.completed.contains($0.id) })
                }
                .buttonStyle(.plain)
                if lens != Lens.allCases.last { Rule() }
            }
        }
    }

    private func notes(_ study: Study) -> some View {
        Button { editNotes = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Eyebrow("Your discoveries"); Spacer(); Image(systemName: "square.and.pencil").foregroundStyle(Ink.accent) }
                Text(study.notes.isEmpty ? "What do you want to borrow, bend or try?" : study.notes)
                    .font(.subheadline).foregroundStyle(study.notes.isEmpty ? Ink.secondary : Ink.primary)
                    .multilineTextAlignment(.leading).lineSpacing(3)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("editNotes")
    }
}

/// The waveform and clock. Kept separate so only this view redraws as the playhead moves.
struct StudyPlayhead: View {
    @Environment(EarStore.self) private var store
    let study: Study
    var body: some View {
        VStack(spacing: 10) {
            WaveformScrubber(study: study, position: store.position, loop: store.loop.map { $0.start...$0.end }) { store.seek($0) }
                .frame(height: 84)
            HStack {
                Text(clock(store.position)).monospacedDigit()
                Spacer()
                Text(clock(study.metrics.duration)).monospacedDigit()
            }
            .font(Ink.mono).foregroundStyle(Ink.secondary)
        }
    }
}

struct MomentCard: View {
    let moment: Moment
    let active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(clock(moment.start)).font(.system(.caption, design: .monospaced)).foregroundStyle(Ink.accent)
                Spacer()
                if moment.id > 0, abs(moment.change) > 0.05 {
                    Text("\(moment.change > 0 ? "+" : "")\(decimal(moment.change, 1)) dB").font(.caption2.monospacedDigit()).foregroundStyle(Ink.secondary)
                }
            }
            Text(moment.label).font(.subheadline.weight(.medium)).foregroundStyle(Ink.primary)
            Label(active ? "Looping" : "Listen & loop", systemImage: active ? "repeat" : "play.fill")
                .font(.caption2).foregroundStyle(active ? Ink.accent : Ink.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding(14)
        .background(active ? Ink.accent.opacity(0.14) : Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(active ? Ink.accent.opacity(0.6) : Ink.line, lineWidth: active ? 1 : 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(moment.label) at \(clock(moment.start))")
        .accessibilityValue(active ? "Looping" : "")
        .accessibilityHint("Plays and loops this section")
    }
}

struct LoudnessCard: View {
    let study: Study
    let integrated: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Loudness", subtitle: "ITU-R BS.1770 · short-term loudness over time") {
                Text("\(decimal(integrated, 1)) LUFS").font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(Ink.warm)
            }
            if let timeline = study.metrics.loudnessTimeline, timeline.count > 1 {
                LoudnessTimeline(values: timeline, integrated: integrated).frame(height: 90)
                    .accessibilityElement().accessibilityLabel("Loudness over time")
                    .accessibilityValue("Peaks at \(decimal(study.metrics.shortTermMax ?? integrated, 1)) LUFS short-term")
            }
            VStack(spacing: 10) {
                Eyebrow("On streaming services")
                ForEach(LoudnessTarget.references) { target in
                    let change = target.adjustment(for: integrated)
                    HStack {
                        Text(target.name).font(.subheadline)
                        Text("\(decimal(target.lufs, 0)) LUFS").font(.caption).foregroundStyle(Ink.secondary)
                        Spacer()
                        Text(abs(change) < 0.5 ? "About the same" : change < 0 ? "Turned down \(decimal(-change, 1)) dB" : "Up to \(decimal(change, 1)) dB quieter")
                            .font(.caption.monospacedDigit()).foregroundStyle(change < -0.5 ? Ink.warm : Ink.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Reference targets for typical normalization. Services set and change their own policies; a louder master is turned down, not made louder.")
                .font(.caption2).foregroundStyle(Ink.secondary).lineSpacing(2)
        }
        .card()
    }
}

struct SpectrumCard: View {
    let metrics: AudioMetrics
    private let names = ["Sub & low", "Body", "Mid", "Presence", "Air"]
    private let ranges = ["20–160 Hz", "160–500 Hz", "0.5–2.5 kHz", "2.5–8 kHz", "8 kHz +"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("The shape of the sound", subtitle: "Frequency balance across the whole mix")
            if let spectrum = metrics.spectrum {
                VStack(spacing: 6) {
                    SpectrumCurve(values: spectrum).frame(height: 110)
                    HStack {
                        ForEach(["31", "125", "500", "2k", "8k", "16k"], id: \.self) { label in
                            Text(label).frame(maxWidth: .infinity)
                        }
                    }
                    .font(.caption2.monospacedDigit()).foregroundStyle(Ink.secondary)
                }
                .accessibilityElement().accessibilityLabel("Third-octave spectrum")
                .accessibilityValue(names.indices.map { "\(names[$0]) \(percent(metrics.bands[$0]))" }.joined(separator: ", "))
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<min(5, metrics.bands.count), id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(percent(metrics.bands[i])).font(.caption.monospacedDigit().weight(.medium))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Ink.accent.opacity(0.85), Ink.accent.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(4, sqrt(metrics.bands[i]) * 60)).frame(height: 60, alignment: .bottom)
                        Text(names[i]).font(.caption2).foregroundStyle(Ink.primary).lineLimit(1).minimumScaleFactor(0.8)
                        Text(ranges[i]).font(.caption2).foregroundStyle(Ink.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(names[i]), \(ranges[i]), \(percent(metrics.bands[i])) of spectral energy")
                }
            }
        }
        .card()
    }
}

struct StereoCard: View {
    let metrics: AudioMetrics
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Stereo image", subtitle: "Correlation and side energy of the whole mix") {
                Text(decimal(metrics.correlation, 2)).font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            CorrelationMeter(value: metrics.correlation)
            HStack(spacing: 10) {
                StatTile(label: "Side energy", value: percent(metrics.sideFraction), detail: "L−R share of the mix")
                StatTile(label: "Low-end width", value: percent(metrics.lowSideFraction), detail: "Side share below 160 Hz",
                         tint: metrics.lowSideFraction > 0.25 ? Ink.warm : Ink.primary)
            }
        }
        .card()
    }
}
