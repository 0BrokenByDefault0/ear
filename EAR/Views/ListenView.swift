import SwiftUI
import EARKit

struct ListenView: View {
    @Environment(EarStore.self) private var store
    @Binding var importing: Bool
    var active: Bool
    var openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("EAR").font(.system(.subheadline, design: .monospaced).weight(.semibold)).tracking(6)
                    .foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
                Eyebrow("The art inside the audio").padding(.top, 22)
                Text("Listen deeper.").font(Ink.display(50)).foregroundStyle(Ink.primary).padding(.top, 10)
                Text("Bring a song you love. Measure what's there, hear why it works, then practise it in your own session.")
                    .font(.subheadline).lineSpacing(3).foregroundStyle(Ink.secondary).padding(.top, 6)
                Orbit(animate: active, amplitude: store.recording ? store.microphoneLevel : 0)
                    .frame(height: 220)
                if store.recording { recordingControls } else { startControls }
                if !store.studies.isEmpty { recent }
                features.padding(.top, 30)
            }
            .page(maxWidth: 640)
        }
        .scrollIndicators(.hidden)
        .background { ZStack { Ink.background.ignoresSafeArea(); Atmosphere() } }
        .foregroundStyle(Ink.primary)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "slider.horizontal.3", action: openSettings).disabled(!store.canStartStudy)
            }
        }
    }

    private var startControls: some View {
        VStack(spacing: 12) {
            Button { importing = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus").font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Study a song").fontWeight(.semibold)
                        Text("Choose one audio file from Files").font(.caption).opacity(0.75)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.doc")
                }
                .frame(minHeight: 44).padding(.horizontal, 6).contentShape(Rectangle())
            }
            .buttonStyle(.glassProminent).controlSize(.large).tint(Ink.primary).foregroundStyle(Ink.background)
            .accessibilityIdentifier("importAudio").disabled(!store.canStartStudy)

            HStack(spacing: 12) {
                Button { Task { await store.startRecording() } } label: {
                    Label(store.requestingMicrophone ? "Requesting…" : "Capture", systemImage: "mic").frame(maxWidth: .infinity, minHeight: 36)
                }
                .accessibilityIdentifier("captureAudio")
                Button { store.demo() } label: {
                    Label("Try Afterglow", systemImage: "play.circle").frame(maxWidth: .infinity, minHeight: 36)
                }
                .accessibilityIdentifier("demoStudy")
            }
            .buttonStyle(.glass).controlSize(.regular).disabled(!store.canStartStudy)

            Text(AudioAnalyzer.supportedFormats).font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 6)
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Ink.alert).frame(width: 8, height: 8)
                Text("Listening · \(clock(Double(store.recordingSeconds))) / 0:30").font(.system(.callout, design: .monospaced)).monospacedDigit()
            }
            ProgressView(value: Double(store.recordingSeconds), total: 30).tint(Ink.alert).frame(maxWidth: 260)
            Text("Play music from another device. A file gives cleaner results.").font(.caption).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Discard", role: .cancel) { store.stopRecording(keep: false) }.buttonStyle(.glass)
                Button("Finish & study", systemImage: "stop.fill") { store.stopRecording(keep: true) }.buttonStyle(.glassProminent)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Continue listening")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.studies.prefix(6)) { study in
                        Button { store.open(study) } label: { RecentCard(study: study) }
                            .buttonStyle(.plain).disabled(!store.canStartStudy)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .padding(.top, 34)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule().padding(.bottom, 22)
            HStack(alignment: .top, spacing: 18) {
                feature("01 / Measure", "Hear the choices.", "Loudness, key, tempo, width and space — measured on your device.")
                feature("02 / Practise", "Make it your own.", "36 short experiments for Studio Pro and Logic Pro.")
            }
        }
    }

    private func feature(_ eyebrow: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(eyebrow)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).lineSpacing(3).foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecentCard: View {
    let study: Study
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Waveform(values: study.metrics.waveform, barWidth: 1.5).frame(height: 34)
            Text(study.title).font(Ink.display(22, relativeTo: .title3)).foregroundStyle(Ink.primary).lineLimit(1)
            HStack(spacing: 6) { ForEach(study.chips.prefix(2), id: \.self) { Chip(text: $0) } }
        }
        .frame(width: 210, alignment: .leading)
        .card(padding: 16, radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue \(study.title)")
        .accessibilityHint(study.chips.joined(separator: ", "))
    }
}
