import SwiftUI

/// Minimal control app for CI: a single SwiftUI fileImporter with nothing else around it.
/// If this cannot pick a file on the CI simulator, the problem is the environment, not EAR.
@main struct PickerControlApp: App {
    @State private var picking = false
    @State private var result = "Nothing picked"
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Button("Pick") { picking = true }.accessibilityIdentifier("pick")
                Text(result).accessibilityIdentifier("result")
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.audio], allowsMultipleSelection: false) { outcome in
                switch outcome {
                case .success(let urls): result = "Picked \(urls.first?.lastPathComponent ?? "nothing")"
                case .failure(let error): result = "Failed \(error.localizedDescription)"
                }
            }
        }
    }
}
