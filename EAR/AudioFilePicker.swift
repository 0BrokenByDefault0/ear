import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The provider prepares a local copy before returning it; originals stay untouched.
struct AudioFilePicker: UIViewControllerRepresentable {
    var completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Some providers label valid audio as generic data. Decode the selection to validate it.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--import-ui-check") {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fixture = folder.appendingPathComponent("EAR Import Check.caf")
            if !FileManager.default.fileExists(atPath: fixture.path) { try? AudioFiles.demo(at: fixture) }
            try? Data("Not an audio recording".utf8).write(to: folder.appendingPathComponent("EAR Invalid Check.txt"))
            picker.directoryURL = folder
        }
        #endif
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }

    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var completion: ((URL?) -> Void)?
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        private func finish(_ url: URL?) {
            let callback = completion; completion = nil
            callback?(url)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
    }
}
