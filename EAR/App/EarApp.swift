import SwiftUI
import AVFoundation
import EARKit

@main struct EarApp: App {
    @State private var store = EarStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Ink.accent)
                .onChange(of: phase) { _, value in
                    if value == .background { store.suspendAudio(reason: "background") }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                    if let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                       type == AVAudioSession.InterruptionType.began.rawValue { store.suspendAudio(reason: "interruption") }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
                    store.mediaServicesReset()
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                    if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                       reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { store.suspendAudio(reason: "output disconnected") }
                }
        }
    }
}

enum AppTab: Hashable { case listen, notebook, lab }

struct RootView: View {
    private enum Sheet: String, Identifiable { case study, settings; var id: String { rawValue } }
    @Environment(EarStore.self) private var store
    @AppStorage("ear.onboarded") private var onboarded = false
    @State private var tab = AppTab.listen
    @State private var sheet: Sheet?
    @State private var pickingFile = false
    @State private var pendingImport: (url: URL, ownedCopy: Bool)?

    private var importing: Binding<Bool> {
        Binding(get: { pickingFile }, set: { show in
            if show {
                guard store.canStartStudy, sheet == nil else { return }
                store.pause()
            }
            pickingFile = show
        })
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Listen", systemImage: "waveform", value: AppTab.listen) {
                NavigationStack {
                    ListenView(importing: importing, active: tab == .listen && sheet == nil && !pickingFile, openSettings: { sheet = .settings })
                }
            }
            Tab("Notebook", systemImage: "square.stack", value: AppTab.notebook) {
                NavigationStack { NotebookView(importing: importing) }
            }
            Tab("Lab", systemImage: "flask", value: AppTab.lab) {
                NavigationStack { LabView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: pickingFile) { _, show in
            guard show else { return }
            AudioPicker.shared.present { outcome in
                pickingFile = false
                switch outcome {
                case .picked(let url): queueImport(url, ownedCopy: true)
                case .cancelled: break
                case .failed(let message): store.error = message
                }
            }
        }
        .sheet(item: $sheet, onDismiss: didDismiss) { item in
            switch item {
            case .study:
                NavigationStack { StudyView() }.environment(store).presentationBackground(Ink.background)
            case .settings:
                NavigationStack { SettingsView() }.environment(store).presentationBackground(Ink.background)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
        }
        .onChange(of: store.showStudy) { _, show in
            if show { sheet = .study }
            else if sheet == .study { sheet = nil }
        }
        .onOpenURL { url in if url.isFileURL { queueImport(url, ownedCopy: false) } }
        .modifier(EarErrorAlert(active: sheet == nil && !pickingFile && onboarded))
        .sensoryFeedback(.success, trigger: store.justFinished)
        .overlay { if store.busy { AnalysisOverlay() } }
    }

    /// - Parameter ownedCopy: true when the file is EAR's own temporary copy from the picker, which is removed after import.
    private func queueImport(_ url: URL, ownedCopy: Bool) {
        pendingImport = (url, ownedCopy)
        // External "Open in EAR" URLs may arrive while a study or settings sheet still needs to dismiss.
        if sheet != nil { sheet = nil; store.showStudy = false }
        else { didDismiss() }
    }

    private func didDismiss() {
        if store.showStudy { store.close() }
        guard let pending = pendingImport else { return }
        pendingImport = nil
        store.importFile(pending.url, removeSourceAfterImport: pending.ownedCopy)
    }
}

/// Full-screen progress while a study is analysed.
struct AnalysisOverlay: View {
    @Environment(EarStore.self) private var store
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.72)).ignoresSafeArea()
            VStack(spacing: 20) {
                Orbit(animate: true, amplitude: 0.15).frame(width: 180, height: 120)
                VStack(spacing: 8) {
                    Text(store.status).font(.headline).multilineTextAlignment(.center)
                    Text("Measuring loudness, key, tempo, tone and space.").font(.subheadline).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
                }
                if store.progress > 0 {
                    ProgressView(value: store.progress).tint(Ink.accent).frame(maxWidth: 220)
                    Text(percent(store.progress)).font(Ink.mono).foregroundStyle(Ink.secondary).monospacedDigit()
                } else {
                    ProgressView().tint(Ink.accent)
                }
                Button("Cancel") { store.cancelAnalysis() }.buttonStyle(.glass).accessibilityIdentifier("cancelAnalysis")
            }
            .padding(28).frame(maxWidth: 340)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Ink.line, lineWidth: 0.5))
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
