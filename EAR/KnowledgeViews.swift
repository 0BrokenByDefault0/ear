import SwiftUI

struct LabView: View {
    @AppStorage("ear.daw") private var dawName = DAW.studio.rawValue
    @AppStorage("ear.lab.tried") private var tried = ""
    @State private var search = ""
    @State private var topic: Lens?
    private var daw: DAW { DAW(rawValue: dawName) ?? .studio }
    private var experiments: [Experiment] {
        Lens.allCases.filter { topic == nil || $0 == topic }.flatMap { Experiment.catalog($0, daw: daw, tempo: nil) }.filter { $0.matches(search) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Eyebrow("Learn by making").padding(.top, 22)
                Text("The listening lab.").font(Ink.display(42))
                Text("36 experiments. Nine ways into a sound. Learn the mechanism, try a move, then trust the listening check.").font(.subheadline).foregroundStyle(Ink.secondary).lineSpacing(4)
                Picker("Your DAW", selection: $dawName) { ForEach(DAW.allCases) { Text($0.rawValue).tag($0.rawValue) } }.pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        topicButton(nil)
                        ForEach(Lens.allCases) { topicButton($0) }
                    }.padding(.vertical, 4)
                }
                Text("\(experiments.count) experiments · \(Set(tried.split(separator: "\n")).count) tried in Lab")
                    .font(.caption).foregroundStyle(Ink.secondary).accessibilityIdentifier("labResults")
                if experiments.isEmpty {
                    ContentUnavailableView("No matching experiments", systemImage: "magnifyingglass", description: Text("Try a sound or technique: sibilance, 808, sidechain, ghost notes, reverb or mono."))
                    Button("Clear search and filters") { search = ""; topic = nil }.buttonStyle(.glass)
                }
                ForEach(Lens.allCases.filter { lens in experiments.contains { $0.lens == lens } }) { lens in
                    Rule()
                    NavigationLink { LensGuideView(lens: lens, studyID: nil) } label: {
                        HStack { Eyebrow(lens.rawValue); Spacer(); Text("Listening guide").font(.caption); Image(systemName: "arrow.up.right").font(.caption) }.frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(Ink.accent)
                    ForEach(experiments.filter { $0.lens == lens }) { experiment in
                        NavigationLink { ExperimentView(lens: lens, studyID: nil, experimentID: experiment.id) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: tried.split(separator: "\n").contains(Substring(experiment.id)) ? "checkmark.circle.fill" : lens.symbol)
                                    .foregroundStyle(Ink.accent).frame(width: 26).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(experiment.title).font(.headline).foregroundStyle(Ink.primary)
                                    Text(experiment.purpose).font(.subheadline).foregroundStyle(Ink.secondary).lineSpacing(3)
                                    Text("\(experiment.minutes) MIN · \(daw.rawValue.uppercased())").font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.accent)
                                }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(18).background(Ink.surface, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).accessibilityIdentifier("lab.\(experiment.id)")
                            .accessibilityValue(tried.split(separator: "\n").contains(Substring(experiment.id)) ? "Tried" : "Not tried")
                    }
                }
                Text("Exercises are original practice designs. They do not identify a reference artist’s equipment or recover a processing chain from a mix.").font(.caption).foregroundStyle(Ink.secondary).lineSpacing(4).padding(.vertical, 10)
            }.padding(.horizontal, 24).padding(.bottom, 28).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(Ink.background).foregroundStyle(Ink.primary)
            .navigationTitle("Lab").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sounds, problems or techniques")
    }
    private func topicButton(_ lens: Lens?) -> some View {
        Button { topic = lens } label: {
            Text(lens?.rawValue ?? "All topics").font(.subheadline).padding(.horizontal, 15).frame(minHeight: 44)
                .foregroundStyle(topic == lens ? Ink.background : Ink.primary)
                .background(topic == lens ? Ink.accent : Ink.surface, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(topic == lens ? .isSelected : [])
    }
}

struct LensGuideView: View {
    @Environment(EarStore.self) private var store
    @AppStorage("ear.daw") private var dawName = DAW.studio.rawValue
    let lens: Lens
    let studyID: UUID?
    private var study: Study? { store.studies.first { $0.id == studyID } }
    var body: some View {
        let guide = ProductionGuide.make(lens)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow("Train your ear").padding(.top, 20)
                Text(lens.rawValue).font(Ink.display(42))
                Text(guide.principle).font(.body).lineSpacing(5)
                Rule()
                Eyebrow("Three things to follow")
                ForEach(Array(guide.cues.enumerated()), id: \.offset) { index, cue in
                    HStack(alignment: .top, spacing: 16) {
                        Text("0\(index + 1)").font(.system(.subheadline, design: .monospaced)).foregroundStyle(Ink.accent)
                        Text(cue).lineSpacing(4)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Avoid the wrong conclusion")
                    Text(guide.trap).font(.subheadline).lineSpacing(4).foregroundStyle(Ink.secondary)
                }.padding(20).background(Ink.surface, in: RoundedRectangle(cornerRadius: 20))
                if lens == .delay { DelayTimingView(initialTempo: study?.tempo) }
                Rule()
                Eyebrow("Put it into practice")
                ForEach(Experiment.catalog(lens, daw: DAW(rawValue: dawName) ?? .studio, tempo: study?.tempo)) { experiment in
                    NavigationLink { ExperimentView(lens: lens, studyID: studyID, experimentID: experiment.id) } label: {
                        HStack { VStack(alignment: .leading, spacing: 8) { Text(experiment.title).font(.headline); Text("\(experiment.minutes) minutes").font(.caption).foregroundStyle(Ink.secondary) }; Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Ink.accent) }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 25).padding(.bottom, 30).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(Ink.background).foregroundStyle(Ink.primary).navigationTitle("Listening guide").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if studyID != nil && studyID == store.currentID { TransportView().padding(.horizontal, 18).padding(.bottom, 8) }
            }
    }
}

struct DelayTimingView: View {
    let initialTempo: Double?
    @State private var bpm = 90.0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Delay time calculator")
            Stepper("\(decimal(bpm, 0)) BPM", value: $bpm, in: 40...240, step: 1).accessibilityIdentifier("delayTempo")
            ForEach(NoteTime.all) { note in
                HStack { Text(note.name); Spacer(); Text("\(decimal(note.milliseconds(at: bpm) ?? 0, 1)) ms").monospacedDigit() }.font(.subheadline)
            }
            Text("Quarter-note BPM. These are timing options to audition, not detected echoes or prescribed compressor releases. Changing this calculator does not change your study tempo.").font(.caption).foregroundStyle(Ink.secondary).lineSpacing(3)
        }.padding(20).background(Ink.surface, in: RoundedRectangle(cornerRadius: 20))
            .onAppear { if let initialTempo, initialTempo.isFinite, (40...240).contains(initialTempo) { bpm = initialTempo } }
    }
}
