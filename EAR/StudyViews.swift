import SwiftUI

struct StudyView: View {
    @Environment(EarStore.self) private var store
    @State private var editTempo = false
    @State private var editNotes = false
    var body: some View {
        Group {
            if let study = store.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow("A closer listen").padding(.top, 20)
                        Text(study.title).font(Ink.display(42)).padding(.top, 12).accessibilityIdentifier("studyTitle")
                        Text(study.source).font(.caption).foregroundStyle(Ink.secondary).padding(.top, 8)
                        Waveform(values: study.metrics.waveform, progress: store.position / study.metrics.duration).frame(height: 76).padding(.vertical, 28)
                        HStack(alignment: .top) {
                            Button { editTempo = true } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 5) { Text(study.tempo.map { decimal($0, 0) } ?? "—").font(.system(.title3, design: .monospaced)); Image(systemName: "pencil").font(.caption2) }
                                    Text(study.tempoOverride == nil ? "BPM candidate" : "BPM · set by you").font(.caption)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain).foregroundStyle(Ink.accent).accessibilityIdentifier("editTempo")
                            Metric(value: clock(study.metrics.duration), label: "Duration")
                            Metric(value: study.metrics.channels == 1 ? "MONO" : "STEREO", label: "Source")
                        }
                        Rule().padding(.vertical, 24)
                        HStack { Eyebrow("The shape of the sound"); Spacer(); Text("RELATIVE ENERGY").font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.secondary) }
                        SpectrumView(bands: study.metrics.bands).padding(.top, 20)
                        Text("Frequency balance across the complete mix.").font(.caption2).foregroundStyle(Ink.secondary).padding(.top, 12)
                        Rule().padding(.vertical, 24)
                        HStack { Eyebrow("Moments"); Spacer(); if store.loop != nil || store.loopStart != nil { Button("Clear loop") { store.clearLoop() }.font(.caption).frame(minHeight: 44) } }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(study.metrics.moments) { moment in
                                    Button { store.select(moment) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(clock(moment.start)).font(.system(.caption, design: .monospaced)).foregroundStyle(Ink.accent)
                                            Text(moment.label).font(.subheadline).foregroundStyle(Ink.primary)
                                            Text("Tap to listen & loop").font(.caption2).foregroundStyle(Ink.secondary)
                                        }.padding(16).background(store.loop?.id == moment.id ? Ink.accent.opacity(0.12) : Ink.surface, in: RoundedRectangle(cornerRadius: 16))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.padding(.top, 16)
                        Text("Sections follow changes in level; musical roles are yours to identify.").font(.caption2).foregroundStyle(Ink.secondary).padding(.top, 12)
                        Rule().padding(.vertical, 24)
                        Eyebrow("Production lenses").padding(.bottom, 10)
                        Text("Measurements start the conversation. Your ears test the explanation.").font(.subheadline).foregroundStyle(Ink.secondary).lineSpacing(3).padding(.bottom, 14)
                        ForEach(Lens.allCases) { lens in
                            NavigationLink { FindingView(lens: lens, studyID: study.id) } label: {
                                LensRow(lens: lens, title: Finding.make(lens, study: study).title)
                            }.buttonStyle(.plain)
                            Rule()
                        }
                        Button { editNotes = true } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Eyebrow("Your discoveries"); Spacer(); Image(systemName: "square.and.pencil").foregroundStyle(Ink.accent) }
                                Text(study.notes.isEmpty ? "What do you want to borrow, bend or try?" : study.notes).font(.subheadline).foregroundStyle(Ink.secondary).multilineTextAlignment(.leading)
                            }.padding(.vertical, 25).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("editNotes")
                    }.padding(.horizontal, 25).padding(.bottom, 20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom) { TransportView().padding(.horizontal, 18).padding(.bottom, 8) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { store.pause(); store.showStudy = false }.accessibilityIdentifier("closeStudy") }
                    ToolbarItem(placement: .topBarTrailing) { ShareLink(item: study.shareText) { Label("Share study", systemImage: "square.and.arrow.up") } }
                }
                .sheet(isPresented: $editTempo) { NavigationStack { TempoView(studyID: study.id) }.presentationDetents([.medium, .large]).presentationBackground(Ink.background) }
                .sheet(isPresented: $editNotes) { NavigationStack { NotesView(studyID: study.id, initial: study.notes) }.presentationBackground(Ink.background) }
            } else { ContentUnavailableView("Choose a study", systemImage: "waveform") }
        }.background(Ink.background).foregroundStyle(Ink.primary).navigationTitle("Study").navigationBarTitleDisplayMode(.inline)
            .modifier(EarErrorAlert(active: !editTempo && !editNotes))
    }
}

struct SpectrumView: View {
    var bands: [Double]
    private let names = ["SUB / LOW", "BODY", "MID", "PRESENCE", "AIR"]
    private let ranges = ["20–160", "160–500", "500–2.5k", "2.5k–8k", "8k+"]
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(0..<min(5, bands.count), id: \.self) { i in
                VStack(spacing: 8) {
                    Text(percent(bands[i])).font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.secondary)
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Ink.accent.opacity(0.8), Ink.accent.opacity(0.12)], startPoint: .top, endPoint: .bottom)).frame(height: max(4, sqrt(bands[i]) * 100)).frame(height: 100, alignment: .bottom)
                    Text(names[i]).font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.primary)
                    Text(ranges[i]).font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.secondary)
                }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel("\(names[i]), \(ranges[i]) hertz, \(percent(bands[i])) spectral energy")
            }
        }
    }
}

struct TransportView: View {
    @Environment(EarStore.self) private var store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    var body: some View {
        if let study = store.current {
            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    Button { store.seek(max(0, store.position - 5)) } label: { Image(systemName: "gobackward.5").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Back five seconds")
                    Button { store.togglePlayback() } label: { Image(systemName: store.playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 46, height: 44).contentShape(Rectangle()) }.disabled(store.preparingMono).accessibilityLabel(store.playing ? "Pause" : "Play").accessibilityIdentifier("transportPlay")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(clock(scrubbing ? scrubPosition : store.position)) / \(clock(study.metrics.duration))").font(.system(.caption, design: .monospaced)).monospacedDigit()
                        Text(store.loopStart.map { "Start marked · \(clock($0))" } ?? (store.loop == nil ? "Listen for the details" : "Looping · \(store.loop?.label ?? "")")).font(.caption2).foregroundStyle(Ink.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.toggleMono() } label: {
                        Group { if store.preparingMono { ProgressView() } else { Text(store.mono ? "MONO" : "L / R").font(.system(.caption2, design: .monospaced)).foregroundStyle(store.mono ? Ink.accent : Ink.primary) } }.frame(width: 48, height: 44).contentShape(Rectangle())
                    }.disabled(study.metrics.channels == 1 || store.preparingMono).accessibilityLabel(store.mono ? "Switch to stereo" : "Audition in mono").accessibilityIdentifier("monoAudition")
                }.buttonStyle(.plain)
                HStack(spacing: 4) {
                    Slider(value: Binding(get: { scrubbing ? scrubPosition : store.position }, set: {
                        scrubPosition = $0
                        if !scrubbing { store.seek($0) }
                    }), in: 0...max(1, study.metrics.duration), onEditingChanged: { editing in
                        if editing { scrubPosition = store.position }
                        else { store.seek(scrubPosition) }
                        scrubbing = editing
                    }).accessibilityLabel("Playback position").accessibilityValue(clock(scrubbing ? scrubPosition : store.position)).accessibilityIdentifier("playbackPosition")
                    Menu {
                        Button("Set loop start here", systemImage: "a.circle") { store.markLoopStart() }
                        Button("Set loop end here", systemImage: "b.circle") { store.markLoopEnd() }.disabled(store.loopStart == nil)
                        if store.loop != nil || store.loopStart != nil { Button("Clear loop", systemImage: "xmark.circle") { store.clearLoop() } }
                    } label: {
                        Image(systemName: "repeat").foregroundStyle(store.loop != nil || store.loopStart != nil ? Ink.accent : Ink.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Phrase loop").accessibilityIdentifier("phraseLoop")
                }.padding(.leading, 12)
            }.padding(.horizontal, 10).padding(.vertical, 8)
                .background { if reduceTransparency { RoundedRectangle(cornerRadius: 26).fill(Ink.surface) } }
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .foregroundStyle(Ink.primary)
        }
    }
}

struct FindingView: View {
    @Environment(EarStore.self) private var store
    let lens: Lens
    let studyID: UUID
    var body: some View {
        if let study = store.studies.first(where: { $0.id == studyID }) {
            let finding = Finding.make(lens, study: study)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: lens.symbol).font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Ink.accent).padding(.top, 20)
                    Text(finding.title).font(Ink.display(40))
                    Eyebrow(finding.kind)
                    Rule()
                    VStack(alignment: .leading, spacing: 12) { Eyebrow("What the audio supports"); Text(finding.evidence).font(.body).lineSpacing(5) }
                    VStack(alignment: .leading, spacing: 12) { Eyebrow("Listen for this"); Text(finding.listen).font(.body).lineSpacing(5).foregroundStyle(Ink.secondary) }
                    Rule()
                    NavigationLink { ExperimentView(lens: lens, studyID: studyID) } label: {
                        HStack { VStack(alignment: .leading, spacing: 8) { Eyebrow("Take it into your DAW"); Text("Try the experiment").font(.headline) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(.vertical, 8)
                    }.buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("tryExperiment")
                    NavigationLink { LensGuideView(lens: lens, studyID: studyID) } label: {
                        Label("Explore the guide & 4 experiments", systemImage: "book").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.glass)
                }.padding(.horizontal, 26).padding(.bottom, 30).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(Ink.background).foregroundStyle(Ink.primary).navigationTitle(lens.rawValue).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) { TransportView().padding(.horizontal, 18).padding(.bottom, 8) }
        }
    }
}

struct ExperimentView: View {
    @Environment(EarStore.self) private var store
    @AppStorage("ear.daw") private var dawName = DAW.studio.rawValue
    @AppStorage("ear.lab.tried") private var labTried = ""
    @State private var checked = Set<Int>()
    let lens: Lens
    let studyID: UUID?
    var experimentID: String? = nil
    private var study: Study? { store.studies.first { $0.id == studyID } }
    private var daw: DAW { DAW(rawValue: dawName) ?? .studio }
    private var experiment: Experiment {
        Experiment.catalog(lens, daw: daw, tempo: study?.tempo).first { $0.id == (experimentID ?? lens.rawValue) }
            ?? Experiment.make(lens, daw: daw, tempo: study?.tempo)
    }
    private var completed: Bool {
        study?.completed.contains(experiment.id) ?? labTried.split(separator: "\n").contains(Substring(experiment.id))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow("\(experiment.minutes) minutes / \(lens.rawValue)").padding(.top, 20)
                Text(experiment.title).font(Ink.display(41))
                Text(experiment.purpose).font(.body).lineSpacing(4).foregroundStyle(Ink.secondary)
                Picker("DAW", selection: $dawName) { ForEach(DAW.allCases) { Text($0.rawValue).tag($0.rawValue) } }.pickerStyle(.segmented)
                Text("Use your own tracks or stems. Values below are audition starts, not recovered settings from the reference.").font(.caption).foregroundStyle(Ink.secondary).lineSpacing(3)
                ForEach(Array(experiment.steps.enumerated()), id: \.offset) { i, step in
                    Rule()
                    Button {
                        if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                    } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Text(checked.contains(i) ? "✓" : String(format: "%02d", i + 1)).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Ink.accent).frame(width: 26, height: 28)
                            Text(step).font(.body).lineSpacing(5).multilineTextAlignment(.leading).foregroundStyle(checked.contains(i) ? Ink.secondary : Ink.primary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Step \(i + 1), \(checked.contains(i) ? "checked" : "unchecked"). \(step)")
                }
                Rule()
                VStack(alignment: .leading, spacing: 12) { Eyebrow("The listening check"); Text(experiment.check).font(.body).lineSpacing(5) }.padding(20).background(Ink.surface, in: RoundedRectangle(cornerRadius: 20))
                    Button {
                        if var value = study {
                            if completed { value.completed.removeAll { $0 == experiment.id } } else { value.completed.append(experiment.id) }
                            store.update(value)
                        } else {
                            var saved = Set(labTried.split(separator: "\n").map(String.init))
                            if completed { saved.remove(experiment.id) } else { saved.insert(experiment.id) }
                            labTried = saved.sorted().joined(separator: "\n")
                        }
                    } label: { Label(completed ? "Experiment tried" : "Mark as tried", systemImage: completed ? "checkmark.circle.fill" : "checkmark.circle").frame(maxWidth: .infinity, minHeight: 32) }.buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("completeExperiment")
                ShareLink(item: experiment.text(daw: daw)) { Label("Share experiment", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 35) }.buttonStyle(.glass)
            }.padding(.horizontal, 26).padding(.bottom, 30).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(Ink.background).foregroundStyle(Ink.primary).navigationTitle("Experiment").navigationBarTitleDisplayMode(.inline)
            .onChange(of: dawName) { _, _ in checked.removeAll() }
            .safeAreaInset(edge: .bottom) {
                if studyID != nil && studyID == store.currentID { TransportView().padding(.horizontal, 18).padding(.bottom, 8) }
            }
    }
}

struct TempoView: View {
    @Environment(EarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let studyID: UUID
    @State private var bpm = 90.0
    @State private var taps: [Date] = []
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(decimal(bpm, 0)).font(Ink.display(65)).padding(.top, 15)
                Eyebrow("Beats per minute")
                Stepper("Fine adjustment", value: $bpm, in: 40...240, step: 1)
                HStack {
                    Button("½") { bpm = max(40, bpm / 2) }
                    Button("Tap the pulse") {
                        let now = Date()
                        if let last = taps.last, now.timeIntervalSince(last) > 2 { taps = [] }
                        taps.append(now); taps = Array(taps.suffix(8))
                        if taps.count > 1 { bpm = min(240, max(40, (60 * Double(taps.count - 1) / now.timeIntervalSince(taps[0])).rounded())) }
                    }.frame(maxWidth: .infinity)
                    Button("2×") { bpm = min(240, bpm * 2) }
                }.buttonStyle(.glass).controlSize(.large)
                Text("Tap at least four steady beats. Half-time and double-time are common; pick the pulse you would use in your session.").font(.caption).foregroundStyle(Ink.secondary)
                if let study = store.studies.first(where: { $0.id == studyID }), study.tempoOverride != nil {
                    Button("Restore analyzed tempo") {
                        var restored = study; restored.tempoOverride = nil
                        if store.update(restored) { dismiss() }
                    }.buttonStyle(.glass).accessibilityIdentifier("restoreTempo")
                }
            }.padding(26)
        }.background(Ink.background).foregroundStyle(Ink.primary).navigationTitle("Find the pulse").navigationBarTitleDisplayMode(.inline)
            .onAppear { bpm = store.studies.first { $0.id == studyID }?.tempo ?? 90 }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { if var study = store.studies.first(where: { $0.id == studyID }) { study.tempoOverride = bpm; if store.update(study) { dismiss() } } } }
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
        TextEditor(text: $notes).padding(18).scrollContentBackground(.hidden).background(Ink.background).foregroundStyle(Ink.primary).accessibilityIdentifier("notesEditor")
            .navigationTitle("Your discoveries").navigationBarTitleDisplayMode(.inline).onAppear { notes = initial }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if var study = store.studies.first(where: { $0.id == studyID }) { study.notes = notes; if store.update(study) { dismiss() } } } }
            }
            .modifier(EarErrorAlert())
    }
}
