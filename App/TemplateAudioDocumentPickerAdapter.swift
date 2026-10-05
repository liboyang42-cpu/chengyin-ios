import Foundation
import UIKit
import UniformTypeIdentifiers
import Darwin

/// An inspection dependency, deliberately distinct from image upload or merchant voice capture.
protocol TemplateAudioSelectedDocumentInspecting: Sendable {
    func inspect(selectedURL: URL) async throws -> TemplateAudioDocumentMetadata
}

struct AppleTemplateAudioSelectedDocumentInspector: TemplateAudioSelectedDocumentInspecting {
    private let coordination: any TemplateAudioDocumentReadCoordinating
    init(coordination: any TemplateAudioDocumentReadCoordinating = AppleTemplateAudioDocumentReadCoordinator()) {
        self.coordination = coordination
    }
    func inspect(selectedURL: URL) async throws -> TemplateAudioDocumentMetadata {
        try await coordination.coordinateRead(selectedURL: selectedURL) { coordinatedURL, checkCancellation in
            try Self.inspectCoordinated(coordinatedURL, checkCancellation: checkCancellation)
        }
    }

    private static func inspectCoordinated(_ coordinatedURL: URL,
                                          checkCancellation: () throws -> Void) throws -> TemplateAudioDocumentMetadata {
        try checkCancellation()
        guard coordinatedURL.isFileURL else { throw TemplateAudioDocumentFailure.unreadable }
        // The provider may move the item: only use the URL supplied by file coordination.
        _ = try TemplateAudioDocumentInspection.format(fileExtension: coordinatedURL.pathExtension)
        // Refuse a symlink at the final path and avoid blocking on a special file. fstat below
        // verifies the opened descriptor, rather than trusting a racy pre-open resource check.
        let descriptor = coordinatedURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw TemplateAudioDocumentFailure.unreadable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var initial = stat()
        guard fstat(handle.fileDescriptor, &initial) == 0,
              (initial.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), initial.st_size >= 0,
              initial.st_size <= Int64(TemplateAudioDocumentInspection.maximumBytes) else {
            if initial.st_size > Int64(TemplateAudioDocumentInspection.maximumBytes) {
                throw TemplateAudioDocumentFailure.tooLarge
            }
            throw TemplateAudioDocumentFailure.unreadable
        }
        let metadata = try TemplateAudioDocumentInspection.inspect(
            fileExtension: coordinatedURL.pathExtension, reportedByteCount: Int(initial.st_size),
            checkCancellation: checkCancellation,
            readChunk: { try handle.read(upToCount: $0) ?? Data() })
        var final = stat()
        guard fstat(handle.fileDescriptor, &final) == 0, initial.st_size == final.st_size,
              initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
              initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec else {
            throw TemplateAudioDocumentFailure.changedDuringRead
        }
        try checkCancellation()
        return metadata
    }
}

/// Unmounted and default-off. A future approved host may present the returned controller only
/// after explicit selection intent. Completion inspects metadata; it never changes a draft.
/// The host must fence account/editor/draft/slot identity separately on every completion.
@MainActor final class TemplateAudioDocumentPickerAdapter: NSObject, UIDocumentPickerDelegate {
    let selectionEnabled: Bool
    private let inspector: any TemplateAudioSelectedDocumentInspecting
    private var activePicker: UIDocumentPickerViewController?
    private var activeRequest: TemplateAudioDocumentRequest?
    private var completion: ((TemplateAudioDocumentSelectionResult) -> Void)?
    private var inspectionTask: Task<Void, Never>?
    private var generation = UUID()

    init(selectionEnabled: Bool = false,
         inspector: any TemplateAudioSelectedDocumentInspecting = AppleTemplateAudioSelectedDocumentInspector()) {
        self.selectionEnabled = selectionEnabled; self.inspector = inspector
        super.init()
    }

    func makePicker(request: TemplateAudioDocumentRequest,
                    completion: @escaping (TemplateAudioDocumentSelectionResult) -> Void) throws -> UIDocumentPickerViewController {
        guard selectionEnabled else { throw TemplateAudioDocumentFailure.notConfigured }
        guard activeRequest == nil else { throw TemplateAudioDocumentFailure.selectionInProgress }
        let types = TemplateAudioDocumentMetadata.Format.allCases.compactMap { UTType(filenameExtension: $0.rawValue) }
        guard types.count == TemplateAudioDocumentMetadata.Format.allCases.count else {
            throw TemplateAudioDocumentFailure.notConfigured
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        activePicker = picker; activeRequest = request; self.completion = completion
        generation = UUID()
        return picker
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard controller === activePicker, let request = activeRequest, inspectionTask == nil else { return }
        guard urls.count == 1, let selectedURL = urls.first else {
            finish(.failed(request, .invalidSelectionCount)); return
        }
        let run = generation
        let inspector = inspector
        inspectionTask = Task { [weak self] in
            do {
                let metadata = try await inspector.inspect(selectedURL: selectedURL)
                guard !Task.isCancelled, let self, self.generation == run, self.activeRequest == request else { return }
                self.finish(.inspected(request, metadata))
            } catch {
                guard let self, self.generation == run, self.activeRequest == request else { return }
                if Task.isCancelled || error is CancellationError { self.finish(.cancelled(request)) }
                else { self.finish(.failed(request, error as? TemplateAudioDocumentFailure ?? .unreadable)) }
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard controller === activePicker else { return }
        cancel()
    }

    /// Also call on parent dismissal, account/draft/method change or loss of edit permission.
    /// Repeated cancel and late success/failure callbacks are inert. Old references are untouched.
    func cancel() {
        guard let request = activeRequest else { return }
        finish(.cancelled(request))
    }

    private func finish(_ result: TemplateAudioDocumentSelectionResult) {
        let callback = completion
        generation = UUID()
        activePicker?.delegate = nil
        activePicker = nil; activeRequest = nil; completion = nil
        inspectionTask?.cancel(); inspectionTask = nil
        callback?(result)
    }

    deinit { inspectionTask?.cancel() }
}
