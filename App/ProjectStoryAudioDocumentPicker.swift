import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor protocol ProjectStoryAudioSelecting: AnyObject {
    func select() async throws -> ProjectStorySelectedAudio?
    func cancel()
}

/// Explicitly selected mp3/m4a/aac documents only. Existing coordinated document reading owns
/// provider access; this adapter neither requests microphone access nor runs an audio decoder.
@MainActor final class ProjectStoryAudioDocumentPicker: NSObject, ProjectStoryAudioSelecting, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private let selectionAllowed: () -> Bool
    private let present: (UIViewController) -> Bool
    private let dismiss: () -> Void
    private let reader: any ProjectStoryAudioSelectedDocumentReading
    private var pending: CheckedContinuation<ProjectStorySelectedAudio?, Error>?
    private var activePicker: UIDocumentPickerViewController?
    private var reading: Task<Void, Never>?
    private var generation = UUID()
    init(selectionAllowed: @escaping () -> Bool = { false }, present: @escaping (UIViewController) -> Bool,
         dismiss: @escaping () -> Void, reader: any ProjectStoryAudioSelectedDocumentReading = AppleProjectStoryAudioSelectedDocumentReader()) {
        self.selectionAllowed = selectionAllowed; self.present = present; self.dismiss = dismiss; self.reader = reader
        super.init()
    }
    func select() async throws -> ProjectStorySelectedAudio? {
        guard selectionAllowed() else { throw TemplateAudioDocumentFailure.notConfigured }
        guard pending == nil else { throw TemplateAudioDocumentFailure.selectionInProgress }
        try Task.checkCancellation()
        let types = TemplateAudioDocumentMetadata.Format.allCases.compactMap { UTType(filenameExtension: $0.rawValue) }
        guard types.count == TemplateAudioDocumentMetadata.Format.allCases.count else { throw TemplateAudioDocumentFailure.notConfigured }
        let id = UUID(); generation = id
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                guard !Task.isCancelled else { finish(.success(nil)); return }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
                picker.allowsMultipleSelection = false; picker.delegate = self; activePicker = picker
                guard selectionAllowed(), present(picker) else { finish(.failure(TemplateAudioDocumentFailure.notConfigured)); return }
                picker.presentationController?.delegate = self
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel(original: id) } })
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard controller === activePicker, pending != nil, reading == nil else { return }
        guard selectionAllowed() else { finish(.failure(TemplateAudioDocumentFailure.notConfigured)); return }
        guard urls.count == 1, let url = urls.first else { finish(.failure(TemplateAudioDocumentFailure.invalidSelectionCount)); return }
        let id = generation, reader = reader
        reading = Task { [weak self] in
            do {
                let selected = try await reader.read(selectedURL: url)
                guard let self, self.generation == id, self.pending != nil else { return }
                guard !Task.isCancelled, self.selectionAllowed() else { self.finish(.success(nil)); return }
                self.finish(.success(selected))
            } catch {
                guard let self, self.generation == id, self.pending != nil else { return }
                if Task.isCancelled || error is CancellationError { self.finish(.success(nil)) }
                else { self.finish(.failure(error)) }
            }
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard controller === activePicker else { return }; cancel()
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Once selection handed us a URL, provider reading belongs to the parent action.
        // The document surface going away must not cancel that successful selection.
        guard presentationController.presentedViewController === activePicker, reading == nil else { return }; cancel()
    }
    private func cancel(original: UUID) { guard generation == original else { return }; cancel() }
    func cancel() { guard pending != nil else { return }; finish(.success(nil)) }
    private func finish(_ result: Result<ProjectStorySelectedAudio?, Error>) {
        let continuation = pending; pending = nil; generation = UUID()
        reading?.cancel(); reading = nil; activePicker?.delegate = nil; activePicker = nil
        dismiss(); continuation?.resume(with: result)
    }
    deinit { reading?.cancel() }
}

@MainActor extension RetainedImagePickerHost {
    func makeStoryAudioPicker(selectionAllowed: @escaping () -> Bool) -> ProjectStoryAudioDocumentPicker {
        weak var presented: UIViewController?
        return .init(selectionAllowed: selectionAllowed, present: { [weak self] picker in
            guard selectionAllowed(), let controller = self?.controller,
                  controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil else { return false }
            presented = picker; controller.present(picker, animated: true); return true
        }, dismiss: { presented?.dismiss(animated: true); presented = nil })
    }
}
