import SwiftUI
import EARKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ear.daw") private var daw = DAW.studio.rawValue
    @AppStorage("ear.onboarded") private var onboarded = true

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Picker("DAW", selection: $daw) { ForEach(DAW.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            } header: { Text("Your studio") } footer: { Text("Experiments use routing, plug-in names and menu paths for your DAW.") }

            Section("What EAR measures") {
                row("Loudness", "Integrated and short-term LUFS (ITU-R BS.1770-4), loudness range (EBU Tech 3342).")
                row("True peak", "4× oversampled inter-sample peak in dBTP.")
                row("Key", "A tonal-centre candidate from chroma profile matching, with its Camelot code.")
                row("Tempo", "An onset-autocorrelation candidate. Half and double time are common; tap to correct it.")
                row("Tone and space", "Third-octave spectrum, mid/side balance, correlation, transients and envelope decay.")
            }

            Section("What it cannot know") {
                Text("EAR cannot identify exact plug-ins, count vocal takes, separate stems or prove a processing chain. Findings are labelled as measurements, interpretations or listening hypotheses.")
                    .font(.subheadline).foregroundStyle(Ink.secondary)
            }

            Section {
                Label("No account, upload, analytics or cloud model.", systemImage: "lock")
                Label("Audio and notes stay on this device.", systemImage: "iphone")
                Label("Your original files are never changed.", systemImage: "doc.on.doc")
            } header: { Text("Your audio stays yours") } footer: {
                Text("Use unprotected audio, 3 seconds to 15 minutes, up to 500 MB. Streaming-service links and protected downloads cannot be analysed. Microphone captures include the room and speaker.")
            }

            Section("Reference manuals") {
                Link(destination: URL(string: "https://s1manual.presonus.com/")!) { Label("Studio Pro manual", systemImage: "book") }
                Link(destination: URL(string: "https://support.apple.com/guide/logicpro/welcome/mac")!) { Label("Logic Pro user guide", systemImage: "book") }
            }

            Section("About") {
                Button { onboarded = false; dismiss() } label: { Label("Show the introduction", systemImage: "sparkles") }
                NavigationLink { LicensesView() } label: { Label("Acknowledgements", systemImage: "text.book.closed") }
                LabeledContent("Version", value: version)
            }

            Section {
                VStack(spacing: 6) {
                    Text("EAR").font(.system(.headline, design: .monospaced)).tracking(6)
                    Text("A listening instrument in the Aeon family").font(.caption).foregroundStyle(Ink.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden).background(Ink.background)
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .modifier(EarErrorAlert())
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(Ink.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct LicensesView: View {
    private func text(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let value = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Aeon Nocturne").font(Ink.display(32))
                Text(text("README-Aeon-Nocturne", "txt")).font(.footnote)
                Rule()
                Text("GUST Font License").font(.headline)
                Text(text("GUST-FONT-LICENSE", "txt")).font(.system(.caption, design: .monospaced))
                Rule()
                Text("The LaTeX Project Public License 1.3c is included in the app bundle as LPPL-1.3c.tex.")
                    .font(.footnote).foregroundStyle(Ink.secondary)
                Text("Production exercises are original teaching content. The study track Afterglow is an original generated instrumental.")
                    .font(.footnote).foregroundStyle(Ink.secondary)
            }
            .page()
            .padding(.top, 12)
        }
        .background(Ink.background).foregroundStyle(Ink.primary)
        .navigationTitle("Acknowledgements").navigationBarTitleDisplayMode(.inline)
    }
}
