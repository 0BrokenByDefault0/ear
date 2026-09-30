import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

@main struct EarApp: App {
    @State private var store = EarStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).preferredColorScheme(.dark).tint(Ink.accent)
                .onChange(of: phase) { _, value in
                    if value == .background { store.suspendAudio(reason: "background") }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                    if let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                       type == AVAudioSession.InterruptionType.began.rawValue { store.suspendAudio(reason: "interruption") }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
                    store.suspendAudio(reason: "media services reset")
                    if let study = store.current { store.open(study) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                    if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                       reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { store.suspendAudio(reason: "output disconnected") }
                }
        }
    }
}

struct RootView: View {
    private enum Sheet: String, Identifiable { case files, study, settings; var id: String { rawValue } }
    @Environment(EarStore.self) private var store
    @State private var tab = 0
    @State private var sheet: Sheet?
    @State private var pendingImport: URL?
    @State private var pendingAccess = false
    @State private var pendingIsCopy = false
    private var importing: Binding<Bool> {
        Binding(get: { sheet == .files }, set: { if $0 && store.canStartStudy { store.pause(); sheet = .files } })
    }
    var body: some View {
        TabView(selection: $tab) {
            Tab("Listen", systemImage: "waveform", value: 0) {
                NavigationStack {
                    ListenView(importing: importing, active: tab == 0 && sheet == nil)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { Text("EAR").font(.system(.subheadline, design: .monospaced)).tracking(5).foregroundStyle(Ink.primary) }
                            ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "slider.horizontal.3") { sheet = .settings }.disabled(!store.canStartStudy) }
                        }
                }
            }
            Tab("Notebook", systemImage: "square.stack", value: 1) { NavigationStack { NotebookView(importing: importing) } }
            Tab("Lab", systemImage: "sparkles", value: 2) { NavigationStack { LabView() } }
        }
        .sheet(item: $sheet, onDismiss: didDismiss) { item in
            switch item {
            case .files:
                AudioFilePicker { url in
                    if let url { queueImport(url, isPickerCopy: true) } else { sheet = nil }
                }.ignoresSafeArea()
            case .study:
                NavigationStack { StudyView() }.environment(store).presentationBackground(Ink.background)
            case .settings:
                NavigationStack { SettingsView() }.presentationBackground(Ink.background)
            }
        }
        .onChange(of: store.showStudy) { _, show in
            if show { sheet = .study }
            else if sheet == .study { sheet = nil }
        }
        .onOpenURL { url in if url.isFileURL { queueImport(url) } }
        .modifier(EarErrorAlert(active: sheet == nil))
        .overlay {
            if store.busy {
                VStack(spacing: 22) {
                    if store.progress == 0 { ProgressView().tint(Ink.accent) }
                    else { ProgressView(value: store.progress).tint(Ink.accent) }
                    Text(store.status).font(.headline)
                    Text("Reading rhythm, tone, space and movement.").font(.subheadline).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
                    Button("Cancel") { store.cancelAnalysis() }.buttonStyle(.glass)
                }.padding(28).frame(maxWidth: 330).background(Ink.surface, in: RoundedRectangle(cornerRadius: 28))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.75)).accessibilityAddTraits(.isModal)
            }
        }
    }

    private func queueImport(_ url: URL, isPickerCopy: Bool = false) {
        if pendingAccess { pendingImport?.stopAccessingSecurityScopedResource() }
        if pendingIsCopy, let previous = pendingImport { try? FileManager.default.removeItem(at: previous) }
        pendingImport = url
        pendingIsCopy = isPickerCopy
        pendingAccess = url.startAccessingSecurityScopedResource()
        // Wait for the picker (or an existing study) to finish dismissing before presenting results.
        if sheet != nil { sheet = nil; store.showStudy = false }
        else { didDismiss() }
    }

    private func didDismiss() {
        store.pause(); store.showStudy = false
        guard let url = pendingImport else { return }
        store.importFile(url, removeSourceAfterImport: pendingIsCopy)
        if pendingAccess { url.stopAccessingSecurityScopedResource() }
        pendingImport = nil; pendingAccess = false; pendingIsCopy = false
    }
}

struct ListenView: View {
    @Environment(EarStore.self) private var store
    @Binding var importing: Bool
    var active: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("The art inside the audio").padding(.top, 24)
                Text("Listen deeper.").font(Ink.display(48)).foregroundStyle(Ink.primary).padding(.top, 12)
                Text("Turn the sounds you love into\nthings you can make.").font(.subheadline).lineSpacing(4).foregroundStyle(Ink.secondary).padding(.top, 6)
                Orbit(animate: active, amplitude: store.recording ? store.microphoneLevel : 0).frame(height: 224)
                if store.recording {
                    recordingControls
                } else {
                    Button { importing = true } label: {
                        HStack { Image(systemName: "plus"); Text("Pick a file").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.up.doc") }.frame(minHeight: 32).padding(.horizontal, 8)
                    }.buttonStyle(.glassProminent).controlSize(.large).tint(Ink.primary).foregroundStyle(Ink.background).accessibilityIdentifier("importAudio").disabled(!store.canStartStudy)
                    HStack(spacing: 12) {
                        Button { Task { await store.startRecording() } } label: { Label(store.requestingMicrophone ? "Requesting…" : "Capture", systemImage: "mic").frame(maxWidth: .infinity, minHeight: 44) }.accessibilityIdentifier("captureAudio")
                        Button { store.demo() } label: { Label("Try a study", systemImage: "play.circle").frame(maxWidth: .infinity, minHeight: 30) }.accessibilityIdentifier("demoStudy")
                    }.buttonStyle(.glass).controlSize(.regular).padding(.top, 12).disabled(!store.canStartStudy)
                    Text("WAV · AIFF · MP3 · M4A · AAC · FLAC · CAF").font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 17)
                    Text("Files, iCloud Drive or a 30-second capture").font(.caption2).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.top, 6)
                }
                Rule().padding(.top, 30).padding(.bottom, 22)
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) { Eyebrow("01 / Unpack"); Text("Hear the choices.").font(.subheadline); Text("Rhythm, layers, space\nand the details between.").font(.caption).lineSpacing(3).foregroundStyle(Ink.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) { Eyebrow("02 / Recreate"); Text("Make it your own.").font(.subheadline); Text("Small experiments.\nA better-trained ear.").font(.caption).lineSpacing(3).foregroundStyle(Ink.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let recent = store.studies.first {
                    Rule().padding(.vertical, 24)
                    Button { store.open(recent) } label: {
                        HStack { VStack(alignment: .leading, spacing: 7) { Eyebrow("Continue listening"); Text(recent.title).font(Ink.display(25)).foregroundStyle(Ink.primary) }; Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Ink.accent) }.frame(minHeight: 50)
                    }.buttonStyle(.plain).disabled(!store.canStartStudy)
                }
            }.padding(.horizontal, 26).padding(.bottom, 28).frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }.background(Ink.background).foregroundStyle(Ink.primary)
    }
    private var recordingControls: some View {
        VStack(spacing: 14) {
            HStack { Circle().fill(.red).frame(width: 7, height: 7); Text("Listening · \(clock(Double(store.recordingSeconds))) / 0:30").font(.system(.callout, design: .monospaced)) }
            Text("Play music from another device. A file gives cleaner results.").font(.caption).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Discard", role: .cancel) { store.stopRecording(keep: false) }.buttonStyle(.glass)
                Button("Finish & study", systemImage: "stop.fill") { store.stopRecording(keep: true) }.buttonStyle(.glassProminent)
            }.controlSize(.large)
        }.frame(maxWidth: .infinity)
    }
}

struct NotebookView: View {
    @Environment(EarStore.self) private var store
    @Binding var importing: Bool
    @State private var search = ""
    @State private var deletion: Study?
    private var filtered: [Study] { store.studies.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your listening\nnotebook.").font(Ink.display(41)).padding(.top, 16)
                Text("Keep the sounds. Remember the discoveries.").font(.subheadline).foregroundStyle(Ink.secondary)
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "A place for discoveries" : "No matching studies", systemImage: "waveform", description: Text(search.isEmpty ? "Import a song or try Afterglow to start your first study." : "Try a different title or note."))
                    if search.isEmpty { Button("Bring a song") { importing = true }.buttonStyle(.glassProminent).disabled(!store.canStartStudy) }
                }
                ForEach(filtered) { study in
                    Rule()
                    Button { store.open(study) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(study.title).font(Ink.display(28)).foregroundStyle(Ink.primary); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Ink.accent) }
                            Waveform(values: study.metrics.waveform, progress: 0.32).frame(height: 32)
                            HStack { Text(clock(study.metrics.duration)); Text("·"); Text(study.created, style: .date); Spacer(); Text("\(study.completed.count) tried") }.font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.secondary)
                        }.padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!store.canStartStudy).contextMenu { Button("Delete study", role: .destructive) { deletion = study }.disabled(!store.canStartStudy) }
                }
            }.padding(26).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(Ink.background).foregroundStyle(Ink.primary)
            .navigationTitle("Notebook").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Titles and notes")
            .toolbar { Button("Import audio", systemImage: "plus") { importing = true }.disabled(!store.canStartStudy) }
            .confirmationDialog("Delete this study and its imported audio copy?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Delete study", role: .destructive) { if let deletion { store.delete(deletion) }; deletion = nil }
            }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ear.daw") private var daw = DAW.studio.rawValue
    var body: some View {
        Form {
            Section("Your studio") { Picker("DAW", selection: $daw) { ForEach(DAW.allCases) { Text($0.rawValue).tag($0.rawValue) } } }
            Section("How EAR listens") {
                Text("EAR decodes your audio on this device. It measures spectrum, stereo relationships, amplitude envelopes and candidate tempo. A production report connects those measurements to listening questions and experiments.")
                Text("It cannot identify exact plugins, count vocal takes, separate stems or prove a processing chain. Tempo may be half or double time. RMS is not LUFS; sample peak is not true peak.")
            }
            Section("Your audio stays yours") {
                Text("No account, upload, analytics or cloud model. Imported audio and notes are saved in EAR on your device. Delete a study in Notebook to remove its imported copy. Your original file is left intact.")
                Text("Use unprotected audio files, 3 seconds to 15 minutes, up to 500 MB. Streaming-service links and protected downloads cannot be analyzed. Microphone captures include the room and speaker sound.")
            }
            Section("Reference manuals") {
                Link("Fender Studio Pro manual", destination: URL(string: "https://s1manual.presonus.com/")!)
                Link("Logic Pro user guide", destination: URL(string: "https://support.apple.com/guide/logicpro/welcome/mac")!)
            }
            Section { Text("EAR 1.2 · An Aeon-family listening instrument").font(.caption).foregroundStyle(Ink.secondary) }
        }.scrollContentBackground(.hidden).background(Ink.background).navigationTitle("Your studio").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .modifier(EarErrorAlert())
    }
}
