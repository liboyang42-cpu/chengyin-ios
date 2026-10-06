import Foundation
import Darwin

protocol ProjectStoryAudioSelectedDocumentReading: Sendable {
    func read(selectedURL: URL) async throws -> ProjectStorySelectedAudio
}

/// The existing coordinator owns security scope, provider cancellation and the exact coordinated
/// URL. A copied body is released on failure/cancel; no path or file handle escapes the accessor.
struct AppleProjectStoryAudioSelectedDocumentReader: ProjectStoryAudioSelectedDocumentReading {
    private let coordination: any TemplateAudioDocumentReadCoordinating
    init(coordination: any TemplateAudioDocumentReadCoordinating = AppleTemplateAudioDocumentReadCoordinator()) {
        self.coordination = coordination
    }
    func read(selectedURL: URL) async throws -> ProjectStorySelectedAudio {
        let capture = ProjectStoryAudioCopiedBody()
        defer { capture.clear() }
        let metadata = try await coordination.coordinateRead(selectedURL: selectedURL) { coordinatedURL, checkCancellation in
            try checkCancellation()
            guard coordinatedURL.isFileURL else { throw TemplateAudioDocumentFailure.unreadable }
            let format = try TemplateAudioDocumentInspection.format(fileExtension: coordinatedURL.pathExtension)
            guard ProjectStorySelectedAudio.validFilename(coordinatedURL.lastPathComponent, format: format) else { throw TemplateAudioDocumentFailure.unreadable }
            let descriptor = coordinatedURL.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }; return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            }
            guard descriptor >= 0 else { throw TemplateAudioDocumentFailure.unreadable }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var initial = stat()
            guard fstat(handle.fileDescriptor, &initial) == 0,
                  (initial.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), initial.st_size >= 0,
                  initial.st_size <= Int64(TemplateAudioDocumentInspection.maximumBytes) else {
                if initial.st_size > Int64(TemplateAudioDocumentInspection.maximumBytes) { throw TemplateAudioDocumentFailure.tooLarge }
                throw TemplateAudioDocumentFailure.unreadable
            }
            let selected = try ProjectStoryAudioCapture.read(filename: coordinatedURL.lastPathComponent,
                reportedByteCount: Int(initial.st_size), checkCancellation: checkCancellation,
                readChunk: { try handle.read(upToCount: $0) ?? Data() })
            var final = stat()
            guard fstat(handle.fileDescriptor, &final) == 0, initial.st_size == final.st_size,
                  initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
                  initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec else { throw TemplateAudioDocumentFailure.changedDuringRead }
            try checkCancellation(); capture.store(selected)
            return selected.metadata
        }
        try Task.checkCancellation()
        guard let selected = capture.take(), selected.metadata == metadata else { throw TemplateAudioDocumentFailure.unreadable }
        return selected
    }
}

/// A coordination callback can finish after its awaiting task has been cancelled. A terminal
/// clear rejects that late store as well as releasing any already retained copied bytes.
private final class ProjectStoryAudioCopiedBody: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ProjectStorySelectedAudio?
    private var closed = false
    func store(_ next: ProjectStorySelectedAudio) { lock.lock(); defer { lock.unlock() }; if !closed { value = next } }
    func take() -> ProjectStorySelectedAudio? { lock.lock(); defer { lock.unlock() }; let result = value; value = nil; closed = true; return result }
    func clear() { lock.lock(); defer { lock.unlock() }; closed = true; value = nil }
}
