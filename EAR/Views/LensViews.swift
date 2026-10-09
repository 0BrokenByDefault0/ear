import SwiftUI
import EARKit

struct FindingView: View {
    @Environment(EarStore.self) private var store
    let lens: Lens
    let studyID: UUID

    var body: some View {
        if let study = store.studies.first(where: { $0.id == studyID }) {
            let finding = Finding.make(lens, study: study)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: lens.symbol).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Ink.accent)
                        .frame(width: 64, height: 64).background(Ink.accent.opacity(0.08), in: Circle()).padding(.top, 12)
                    Text(finding.title).font(Ink.display(40)).accessibilityAddTraits(.isHeader)
                    Chip(text: finding.kind, tint: finding.kind == "MEASURED" ? Ink.accent : Ink.warm)
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("What the audio supports")
                        Text(finding.evidence).font(.body).lineSpacing(5)
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("Listen for this")
                        Text(finding.listen).font(.body).lineSpacing(5).foregroundStyle(Ink.secondary)
                    }
                    NavigationLink { ExperimentView(lens: lens, studyID: studyID) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Eyebrow("Take it into your DAW")
                                Text("Try the experiment").font(.headline)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("tryExperiment")
                    NavigationLink { LensGuideView(lens: lens, studyID: studyID) } label: {
                        Label("Explore the guide & 4 experiments", systemImage: "book").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
                .page(maxWidth: 680)
            }
            .background(Ink.background)
            .foregroundStyle(Ink.primary)
            .navigationTitle(lens.rawValue).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { TransportView().padding(.horizontal, 16).padding(.bottom, 6) }
        }
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
                Eyebrow("Train your ear").padding(.top, 12)
                Text(lens.rawValue).font(Ink.display(44)).accessibilityAddTraits(.isHeader)
                Text(guide.principle).font(.body).lineSpacing(5)
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow("Three things to follow")
                    ForEach(Array(guide.cues.enumerated()), id: \.offset) { index, cue in
                        HStack(alignment: .top, spacing: 16) {
                            Text("0\(index + 1)").font(.system(.subheadline, design: .monospaced)).foregroundStyle(Ink.accent)
                            Text(cue).lineSpacing(4)
                        }
                    }
                }
                .card()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Avoid the wrong conclusion", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.warm)
                    Text(guide.trap).font(.subheadline).lineSpacing(4).foregroundStyle(Ink.secondary)
                }
                .card()
                if lens == .delay { DelayTimingView(initialTempo: study?.tempo) }
                SectionHeader("Put it into practice")
                VStack(spacing: 10) {
                    ForEach(Experiment.catalog(lens, daw: DAW(rawValue: dawName) ?? .studio, tempo: study?.tempo)) { experiment in
                        NavigationLink { ExperimentView(lens: lens, studyID: studyID, experimentID: experiment.id) } label: {
                            ExperimentCard(experiment: experiment, daw: DAW(rawValue: dawName) ?? .studio,
                                           tried: store.isCompleted(experiment.id, in: studyID))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .page()
        }
        .background(Ink.background)
        .foregroundStyle(Ink.primary)
        .navigationTitle("Listening guide").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if studyID != nil && studyID == store.currentID { TransportView().padding(.horizontal, 16).padding(.bottom, 6) }
        }
    }
}

struct DelayTimingView: View {
    let initialTempo: Double?
    @State private var bpm = 90.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Delay time calculator")
            Stepper(value: $bpm, in: 40...240, step: 1) {
                Text("\(decimal(bpm, 0)) BPM").font(Ink.number)
            }
            .accessibilityIdentifier("delayTempo")
            ForEach(NoteTime.all) { note in
                HStack {
                    Text(note.name)
                    Spacer()
                    Text("\(decimal(note.milliseconds(at: bpm) ?? 0, 1)) ms").monospacedDigit().foregroundStyle(Ink.accent)
                }
                .font(.subheadline)
                if note.id != NoteTime.all.last?.id { Rule() }
            }
            Text("Quarter-note BPM. These are timing options to audition, not detected echoes. Changing this calculator does not change your study tempo.")
                .font(.caption).foregroundStyle(Ink.secondary).lineSpacing(3)
        }
        .card()
        .onAppear { if let initialTempo, initialTempo.isFinite, (40...240).contains(initialTempo) { bpm = initialTempo } }
    }
}

struct ExperimentCard: View {
    let experiment: Experiment
    let daw: DAW
    let tried: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tried ? "checkmark.circle.fill" : experiment.lens.symbol)
                .font(.system(size: 18, weight: tried ? .regular : .light))
                .foregroundStyle(Ink.accent).frame(width: 28).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(experiment.title).font(.headline).foregroundStyle(Ink.primary).multilineTextAlignment(.leading)
                Text(experiment.purpose).font(.subheadline).foregroundStyle(Ink.secondary).lineSpacing(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Chip(text: "\(experiment.minutes) min", symbol: "timer", tint: Ink.accent)
                    Chip(text: daw.rawValue)
                    if tried { Chip(text: "Tried", tint: Ink.accent) }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.secondary).padding(.top, 4)
        }
        .card(padding: 16, radius: 20)
        .contentShape(Rectangle())
    }
}

struct ExperimentView: View {
    @Environment(EarStore.self) private var store
    @AppStorage("ear.daw") private var dawName = DAW.studio.rawValue
    @State private var checked = Set<Int>()
    let lens: Lens
    let studyID: UUID?
    var experimentID: String?

    private var study: Study? { store.studies.first { $0.id == studyID } }
    private var daw: DAW { DAW(rawValue: dawName) ?? .studio }
    private var experiment: Experiment {
        Experiment.catalog(lens, daw: daw, tempo: study?.tempo).first { $0.id == (experimentID ?? lens.rawValue) }
            ?? Experiment.make(lens, daw: daw, tempo: study?.tempo)
    }

    var body: some View {
        let experiment = self.experiment
        let completed = store.isCompleted(experiment.id, in: studyID)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 6) {
                    Chip(text: "\(experiment.minutes) min", symbol: "timer", tint: Ink.accent)
                    Chip(text: lens.rawValue, symbol: lens.symbol)
                }
                .padding(.top, 12)
                Text(experiment.title).font(Ink.display(40)).accessibilityAddTraits(.isHeader)
                Text(experiment.purpose).font(.body).lineSpacing(4).foregroundStyle(Ink.secondary)
                Picker("DAW", selection: $dawName) { ForEach(DAW.allCases) { Text($0.rawValue).tag($0.rawValue) } }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow("Steps")
                        Spacer()
                        Text("\(checked.count) of \(experiment.steps.count)").font(.caption.monospacedDigit()).foregroundStyle(Ink.secondary)
                    }
                    ProgressView(value: Double(checked.count), total: Double(max(1, experiment.steps.count))).tint(Ink.accent)
                }
                VStack(spacing: 0) {
                    ForEach(Array(experiment.steps.enumerated()), id: \.offset) { i, step in
                        Button {
                            if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    Circle().strokeBorder(checked.contains(i) ? Ink.accent : Ink.line, lineWidth: 1)
                                        .background(Circle().fill(checked.contains(i) ? Ink.accent : .clear))
                                    if checked.contains(i) { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Ink.background) }
                                    else { Text("\(i + 1)").font(.system(.caption, design: .monospaced)).foregroundStyle(Ink.accent) }
                                }
                                .frame(width: 28, height: 28)
                                Text(step).font(.body).lineSpacing(5).multilineTextAlignment(.leading)
                                    .foregroundStyle(checked.contains(i) ? Ink.secondary : Ink.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: checked.contains(i))
                        .accessibilityLabel("Step \(i + 1), \(checked.contains(i) ? "done" : "not done"). \(step)")
                        if i < experiment.steps.count - 1 { Rule() }
                    }
                }
                .card(padding: 16)
                VStack(alignment: .leading, spacing: 12) {
                    Label("The listening check", systemImage: "ear").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.accent)
                    Text(experiment.check).font(.body).lineSpacing(5)
                }
                .card()
                Text("Use your own tracks or stems. Values are audition starts, not recovered settings from the reference.")
                    .font(.caption).foregroundStyle(Ink.secondary).lineSpacing(3)
                Button { store.toggleCompleted(experiment.id, in: studyID) } label: {
                    Label(completed ? "Experiment tried" : "Mark as tried", systemImage: completed ? "checkmark.circle.fill" : "checkmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .sensoryFeedback(.success, trigger: completed) { _, new in new }
                .accessibilityIdentifier("completeExperiment")
                ShareLink(item: experiment.text(daw: daw)) {
                    Label("Share experiment", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 35)
                }
                .buttonStyle(.glass)
            }
            .page(maxWidth: 680)
        }
        .background(Ink.background)
        .foregroundStyle(Ink.primary)
        .navigationTitle("Experiment").navigationBarTitleDisplayMode(.inline)
        .onChange(of: dawName) { _, _ in checked.removeAll() }
        .safeAreaInset(edge: .bottom) {
            if studyID != nil && studyID == store.currentID { TransportView().padding(.horizontal, 16).padding(.bottom, 6) }
        }
    }
}
