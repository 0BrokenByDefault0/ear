import SwiftUI
import EARKit

/// Three-page introduction shown once, and again from Settings.
struct OnboardingView: View {
    var finish: () -> Void
    @State private var page = 0

    private struct Page {
        let eyebrow: String, title: String, body: String, points: [(String, String)]
    }

    private let pages = [
        Page(eyebrow: "Welcome to EAR", title: "Hear how records are made.",
             body: "Bring a song you love. EAR measures it on your device and turns the numbers into things to listen for.",
             points: [("waveform", "Import from Files, capture with the mic, or start with Afterglow"),
                      ("lock", "No account, no upload, no cloud model")]),
        Page(eyebrow: "Measure honestly", title: "Numbers you can trust.",
             body: "Every reading is labelled as a measurement, an interpretation or a hypothesis for your ears to test.",
             points: [("speaker.wave.2", "LUFS loudness, range and true peak"),
                      ("music.note", "Key with Camelot code, tempo you can tap"),
                      ("circle.lefthalf.filled", "Spectrum, stereo width and mono checks")]),
        Page(eyebrow: "Practise in your DAW", title: "Then make it your own.",
             body: "Loop a phrase, audition in mono, and take one of 36 short experiments into Studio Pro or Logic Pro.",
             points: [("repeat", "Sample-accurate phrase loops"),
                      ("flask", "Step-by-step experiments with a listening check"),
                      ("square.and.pencil", "A notebook for what you discover")]),
    ]

    var body: some View {
        ZStack {
            Ink.background.ignoresSafeArea()
            Atmosphere()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: finish).foregroundStyle(Ink.secondary).accessibilityIdentifier("skipOnboarding")
                }
                .padding(.horizontal, 24).padding(.top, 8)
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        content(pages[index], index: index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule().fill(index == page ? Ink.accent : Ink.line).frame(width: index == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)
                .accessibilityHidden(true)
                .padding(.bottom, 22)
                Button {
                    if page < pages.count - 1 { withAnimation { page += 1 } } else { finish() }
                } label: {
                    Text(page < pages.count - 1 ? "Continue" : "Start listening").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent).tint(Ink.primary).foregroundStyle(Ink.background).controlSize(.large)
                .padding(.horizontal, 24).padding(.bottom, 20)
                .accessibilityIdentifier("onboardingContinue")
            }
            .frame(maxWidth: 560)
        }
        .foregroundStyle(Ink.primary)
        .preferredColorScheme(.dark)
    }

    private func content(_ page: Page, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Orbit(animate: index == self.page, amplitude: Double(index) * 0.12).frame(height: 230)
                Eyebrow(page.eyebrow, color: Ink.accent)
                Text(page.title).font(Ink.display(44)).fixedSize(horizontal: false, vertical: true)
                Text(page.body).font(.body).foregroundStyle(Ink.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(page.points, id: \.1) { point in
                        HStack(spacing: 14) {
                            Image(systemName: point.0).foregroundStyle(Ink.accent).frame(width: 30)
                            Text(point.1).font(.subheadline)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 28)
        }
        .scrollIndicators(.hidden)
    }
}
