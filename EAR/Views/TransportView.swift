import SwiftUI
import EARKit

/// Floating Liquid Glass transport, available on the study and inside every lens and experiment.
struct TransportView: View {
    @Environment(EarStore.self) private var store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0

    var body: some View {
        if let study = store.current {
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Button { store.skip(-5) } label: {
                        Image(systemName: "gobackward.5").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back five seconds")

                    Button { store.togglePlayback() } label: {
                        Image(systemName: store.playing ? "pause.fill" : "play.fill").font(.title2)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 50, height: 50)
                            .background(Ink.primary.opacity(0.12), in: Circle())
                            .contentShape(Circle())
                    }
                    .disabled(store.preparingMono)
                    .accessibilityLabel(store.playing ? "Pause" : "Play")
                    .accessibilityIdentifier("transportPlay")
                    .sensoryFeedback(.selection, trigger: store.playing)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(clock(scrubbing ? scrubPosition : store.position)) / \(clock(study.metrics.duration))")
                            .font(.system(.caption, design: .monospaced)).monospacedDigit()
                        Text(status).font(.caption2).foregroundStyle(store.loop != nil ? Ink.accent : Ink.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Menu {
                        Button("Set loop start here", systemImage: "a.circle") { store.markLoopStart() }
                        Button("Set loop end here", systemImage: "b.circle") { store.markLoopEnd() }.disabled(store.loopStart == nil)
                        if store.loop != nil || store.loopStart != nil {
                            Button("Clear loop", systemImage: "xmark.circle") { store.clearLoop() }
                        }
                    } label: {
                        Image(systemName: "repeat")
                            .foregroundStyle(store.loop != nil || store.loopStart != nil ? Ink.accent : Ink.secondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Phrase loop").accessibilityIdentifier("phraseLoop")

                    Button { store.toggleMono() } label: {
                        Group {
                            if store.preparingMono { ProgressView() }
                            else {
                                Text(store.mono ? "MONO" : "L / R").font(.system(.caption2, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(store.mono ? Ink.background : Ink.primary)
                                    .padding(.horizontal, 7).padding(.vertical, 5)
                                    .background(store.mono ? Ink.accent : Color.clear, in: Capsule())
                            }
                        }
                        .frame(width: 52, height: 44).contentShape(Rectangle())
                    }
                    .disabled(study.metrics.channels == 1 || store.preparingMono)
                    .accessibilityLabel(store.mono ? "Switch to stereo" : "Audition in mono")
                    .accessibilityIdentifier("monoAudition")
                }
                .buttonStyle(.plain)

                Slider(value: Binding(get: { scrubbing ? scrubPosition : store.position }, set: {
                    scrubPosition = $0
                    if !scrubbing { store.seek($0) }
                }), in: 0...max(1, study.metrics.duration), onEditingChanged: { editing in
                    if editing { scrubPosition = store.position } else { store.seek(scrubPosition) }
                    scrubbing = editing
                })
                .tint(Ink.accent)
                .padding(.horizontal, 6)
                .accessibilityLabel("Playback position")
                .accessibilityValue(clock(scrubbing ? scrubPosition : store.position))
                .accessibilityIdentifier("playbackPosition")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background { if reduceTransparency { RoundedRectangle(cornerRadius: 28).fill(Ink.raised) } }
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .foregroundStyle(Ink.primary)
        }
    }

    private var status: String {
        if let start = store.loopStart { return "Start marked · \(clock(start))" }
        if let loop = store.loop { return "Looping · \(loop.label)" }
        if store.mono { return "Mono fold-down" }
        return "Listen for the details"
    }
}
