import SwiftUI
import EARKit

struct LabView: View {
    @Environment(EarStore.self) private var store
    @AppStorage("ear.daw") private var dawName = DAW.studio.rawValue
    @State private var search = ""
    @State private var topic: Lens?

    private var daw: DAW { DAW(rawValue: dawName) ?? .studio }
    private var experiments: [Experiment] {
        Lens.allCases.filter { topic == nil || $0 == topic }
            .flatMap { Experiment.catalog($0, daw: daw, tempo: nil) }
            .filter { $0.matches(search) }
    }

    var body: some View {
        let experiments = self.experiments
        let tried = store.everTried
        let total = Lens.allCases.count * 4
        let done = Experiment.all(daw: daw).filter { tried.contains($0.id) }.count
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Eyebrow("Learn by making").padding(.top, 12)
                Text("The listening lab.").font(Ink.display(44)).accessibilityAddTraits(.isHeader)
                Text("Nine ways into a sound. Learn the mechanism, try a move, then trust the listening check.")
                    .font(.subheadline).foregroundStyle(Ink.secondary).lineSpacing(3)
                progress(done: done, total: total)
                Picker("Your DAW", selection: $dawName) { ForEach(DAW.allCases) { Text($0.rawValue).tag($0.rawValue) } }.pickerStyle(.segmented)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        topicButton(nil)
                        ForEach(Lens.allCases) { topicButton($0) }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                Text("\(experiments.count) \(experiments.count == 1 ? "experiment" : "experiments")")
                    .font(.caption).foregroundStyle(Ink.secondary).accessibilityIdentifier("labResults")
                if experiments.isEmpty {
                    ContentUnavailableView("No matching experiments", systemImage: "magnifyingglass",
                                           description: Text("Try a sound or technique: sibilance, 808, sidechain, ghost notes, reverb or mono."))
                    Button("Clear search and filters") { search = ""; topic = nil }.buttonStyle(.glass).frame(maxWidth: .infinity)
                }
                ForEach(Lens.allCases.filter { lens in experiments.contains { $0.lens == lens } }) { lens in
                    NavigationLink { LensGuideView(lens: lens, studyID: nil) } label: {
                        HStack {
                            Image(systemName: lens.symbol).foregroundStyle(Ink.accent)
                            Eyebrow(lens.rawValue, color: Ink.primary)
                            Spacer()
                            Text("Listening guide").font(.caption)
                            Image(systemName: "arrow.up.right").font(.caption)
                        }
                        .frame(minHeight: 44).foregroundStyle(Ink.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    ForEach(experiments.filter { $0.lens == lens }) { experiment in
                        NavigationLink { ExperimentView(lens: lens, studyID: nil, experimentID: experiment.id) } label: {
                            ExperimentCard(experiment: experiment, daw: daw, tried: store.labTried.contains(experiment.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lab.\(experiment.id)")
                        .accessibilityValue(store.labTried.contains(experiment.id) ? "Tried" : "Not tried")
                    }
                }
                Text("Exercises are original practice designs. They do not identify a reference artist’s equipment or recover a processing chain from a mix.")
                    .font(.caption).foregroundStyle(Ink.secondary).lineSpacing(4).padding(.vertical, 10)
            }
            .page()
        }
        .scrollIndicators(.hidden)
        .background(Ink.background)
        .foregroundStyle(Ink.primary)
        .navigationTitle("Lab").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sounds, problems or techniques")
    }

    private func progress(done: Int, total: Int) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Ink.line, lineWidth: 5)
                Circle().trim(from: 0, to: Double(done) / Double(max(1, total)))
                    .stroke(Ink.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(done)").font(.system(.headline, design: .rounded).monospacedDigit())
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(done) of \(total) experiments tried").font(.subheadline.weight(.semibold))
                Text(done == 0 ? "Start with any lens. Each takes 5–12 minutes." : done == total ? "Every experiment tried. Revisit them with new songs." : "Progress from the Lab and your studies.")
                    .font(.caption).foregroundStyle(Ink.secondary)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private func topicButton(_ lens: Lens?) -> some View {
        Button { topic = lens } label: {
            Text(lens?.rawValue ?? "All topics").font(.subheadline).padding(.horizontal, 15).frame(minHeight: 40)
                .foregroundStyle(topic == lens ? Ink.background : Ink.primary)
                .background(topic == lens ? Ink.accent : Ink.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Ink.line, lineWidth: topic == lens ? 0 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(topic == lens ? .isSelected : [])
    }
}
