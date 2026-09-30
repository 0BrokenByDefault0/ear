import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Open the provider's selection; AudioFiles makes EAR's coordinated private copy.
struct AudioFilePicker: UIViewControllerRepresentable {
    var completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Audio and generic provider data are distinct filters; explicitly accept both.
        // Decode the selection to validate it instead of trusting its extension.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, .data], asCopy: false)
        earTrace("File picker created")
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--import-ui-check") {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fixture = folder.appendingPathComponent("EAR Import Check.caf")
            if !FileManager.default.fileExists(atPath: fixture.path) { try? AudioFiles.demo(at: fixture) }
            if let type = try? fixture.resourceValues(forKeys: [.contentTypeKey]).contentType {
                earTrace("Fixture type=\(type.identifier); audio=\(type.conforms(to: .audio)); data=\(type.conforms(to: .data))")
            }
            try? Data("Not an audio recording".utf8).write(to: folder.appendingPathComponent("EAR Invalid Check.txt"))
            picker.directoryURL = folder
        }
        #endif
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.completion = completion
    }

    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        private func finish(_ url: URL?) {
            earTrace("File picker returned selection=\(url != nil)")
            completion(url)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
    }
}
