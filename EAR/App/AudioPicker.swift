import UIKit
import UniformTypeIdentifiers

/// Presents the system document browser from UIKit and hands back one local copy of the chosen file.
///
/// SwiftUI's `fileImporter` opens files in place and, with multiple selection, can fail to return
/// anything at all when the provider does not finish preparing the item ("tapping Open does
/// nothing"). Importing as a copy makes the system download and copy the file into EAR's
/// temporary inbox before the callback, so the import never depends on a security-scoped
/// reference to someone else's storage.
@MainActor final class AudioPicker: NSObject, UIDocumentPickerDelegate {
    enum Outcome {
        case picked(URL)
        case cancelled
        case failed(String)
    }

    static let shared = AudioPicker()
    private var completion: ((Outcome) -> Void)?

    /// Audio, plus generic data: some providers tag audio files that way. Content is validated on import.
    static let types: [UTType] = [UTType.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        + [UTType("org.xiph.flac")].compactMap { $0 } + [UTType.data]

    func present(completion: @escaping (Outcome) -> Void) {
        guard self.completion == nil else { return }
        guard let presenter = Self.topViewController() else {
            completion(.failed("EAR could not open Files right now. Try again in a moment."))
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        self.completion = completion
        earTrace("Presenting document picker")
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        earTrace("Document picker returned \(urls.count) item(s)")
        if let url = urls.first {
            earTrace("Picked \(url.lastPathComponent)")
            finish(.picked(url))
        } else {
            finish(.failed("Files could not prepare that item. If it is stored in iCloud or another app, download it in the Files app first, then try again."))
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        earTrace("Document picker cancelled")
        finish(.cancelled)
    }

    private func finish(_ outcome: Outcome) {
        let completion = self.completion
        self.completion = nil
        completion?(outcome)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
