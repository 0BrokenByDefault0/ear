import SwiftUI
import EARKit

struct TempoView: View {
    @Environment(EarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let studyID: UUID
    @State private var bpm = 90.0
    @State private var taps: [Date] = []
    @State private var tapCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(decimal(bpm, 0)).font(Ink.display(72)).monospacedDigit().padding(.top, 12)
                    .contentTransition(.numericText(value: bpm))
                    .accessibilityLabel("\(decimal(bpm, 0)) beats per minute")
                Eyebrow("Beats per minute")
                Stepper("Fine adjustment", value: $bpm, in: 40...240, step: 1)
                HStack {
                    Button("½") { bpm = max(40, (bpm / 2).rounded()) }.accessibilityLabel("Half time")
                    Button {
                        let now = Date()
                        if let last = taps.last, now.timeIntervalSince(last) > 2 { taps = [] }
                        taps.append(now); taps = Array(taps.suffix(8)); tapCount += 1
                        if taps.count > 1 {
                            bpm = min(240, max(40, (60 * Double(taps.count - 1) / now.timeIntervalSince(taps[0])).rounded()))
                        }
                    } label: { Text("Tap the pulse").frame(maxWidth: .infinity, minHeight: 44) }
                    .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
                    Button("2×") { bpm = min(240, bpm * 2) }.accessibilityLabel("Double time")
                }
                .buttonStyle(.glass).controlSize(.large)
                Text("Tap at least four steady beats. Half-time and double-time readings are common; pick the pulse you would use in your session.")
                    .font(.caption).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
                if let study = store.studies.first(where: { $0.id == studyID }), study.tempoOverride != nil {
                    Button("Restore analysed tempo") {
                        var restored = study; restored.tempoOverride = nil
                        if store.update(restored) { dismiss() }
                    }
                    .buttonStyle(.glass).accessibilityIdentifier("restoreTempo")
                }
            }
            .padding(26)
        }
        .background(Ink.background).foregroundStyle(Ink.primary)
        .navigationTitle("Find the pulse").navigationBarTitleDisplayMode(.inline)
        .onAppear { bpm = (store.studies.first { $0.id == studyID }?.tempo ?? 90).rounded() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    if var study = store.studies.first(where: { $0.id == studyID }) {
                        study.tempoOverride = bpm
                        if store.update(study) { dismiss() }
                    }
                }
            }
        }
        .modifier(EarErrorAlert())
    }
}

struct NotesView: View {
    @Environment(EarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let studyID: UUID
    let initial: String
    @State private var notes = ""

    var body: some View {
        TextEditor(text: $notes)
            .padding(18).scrollContentBackground(.hidden).background(Ink.background).foregroundStyle(Ink.primary)
            .accessibilityIdentifier("notesEditor")
            .navigationTitle("Your discoveries").navigationBarTitleDisplayMode(.inline)
            .onAppear { notes = initial }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var study = store.studies.first(where: { $0.id == studyID }) {
                            study.notes = notes
                            if store.update(study) { dismiss() }
                        }
                    }
                }
            }
            .modifier(EarErrorAlert())
    }
}
