import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Only a decoded, bounded image thumbnail. This does not certify the complete media,
/// sanitize upload bytes, approve server registration, or provide a publication grant.
struct SquarePostLocalMediaImagePreview {
    let evidence: SquarePostLocalMediaByteEvidence
    let bytes: Data
    let thumbnail: UIImage
}

/// Owns one provider read, including cancellation before Progress is returned. A late
/// callback cannot resume the continuation twice or resurrect a cancelled selection.
private final class SquarePostLocalMediaReadOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var progress: Progress?
    private var terminal: Result<Data, Error>?
    private var cancelled = false
    func install(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if let terminal { lock.unlock(); continuation.resume(with: terminal) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func install(_ progress: Progress) {
        lock.lock(); let shouldCancel = cancelled
        if terminal == nil { self.progress = progress }; lock.unlock()
        if shouldCancel { progress.cancel() }
    }
    func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard terminal == nil else { lock.unlock(); return }
        terminal = result; let waiting = continuation; continuation = nil; progress = nil
        lock.unlock(); waiting?.resume(with: result)
    }
    func cancel() {
        lock.lock(); cancelled = true; let progress = progress; lock.unlock()
        finish(.failure(CancellationError())); progress?.cancel()
    }
}

@MainActor enum SquarePostLocalMediaInspector {
    // Match the existing upload service. A provider may supply a genuine JPEG/PNG
    // representation; unsupported original bytes are never transcoded here.
    static let imageTypes: [UTType] = [.jpeg, .png]
    static func imageType(in provider: NSItemProvider) -> UTType? {
        imageTypes.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }
    }
    static func loadImage(provider: NSItemProvider, type: UTType,
                          maximumBytes: Int, inspection: SquarePostLocalMediaByteInspection) async throws -> SquarePostLocalMediaImagePreview {
        guard maximumBytes > 0, imageTypes.contains(type) else { throw SquarePostLocalMediaIssue.invalidPolicy }
        let operation = SquarePostLocalMediaReadOperation()
        let bytes = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                operation.install(continuation)
                let progress = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    do {
                        try operation.checkCancellation()
                        guard error == nil, let url, url.isFileURL else { throw SquarePostLocalMediaIssue.inspectionFailed }
                        // Consume inside the provider callback: its temporary URL expires on return.
                        // The retained registry value is immutable owned Data, never this URL.
                        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
                        var owned = Data()
                        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                            try operation.checkCancellation()
                            guard chunk.count <= maximumBytes - owned.count else { throw SquarePostLocalMediaIssue.byteLimit }
                            owned.append(chunk)
                        }
                        try operation.checkCancellation()
                        guard !owned.isEmpty else { throw SquarePostLocalMediaIssue.noBytes }
                        operation.finish(.success(owned))
                    } catch { operation.finish(.failure(error)) }
                }
                operation.install(progress)
            }
        }, onCancel: { operation.cancel() })
        try Task.checkCancellation()
        return try decodeImage(bytes, expectedType: type, maximumBytes: maximumBytes, inspection: inspection)
    }
    static func decodeImage(_ bytes: Data, expectedType: UTType, maximumBytes: Int,
                            inspection: SquarePostLocalMediaByteInspection) throws -> SquarePostLocalMediaImagePreview {
        guard !bytes.isEmpty, maximumBytes > 0, bytes.count <= maximumBytes else { throw SquarePostLocalMediaIssue.byteLimit }
        guard imageTypes.contains(expectedType),
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let actualIdentifier = CGImageSourceGetType(source),
              let actualType = UTType(actualIdentifier as String), actualType == expectedType,
              let mime = actualType.preferredMIMEType,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, !width.multipliedReportingOverflow(by: height).overflow else {
            throw SquarePostLocalMediaIssue.invalidMetadata
        }
        // 512 is a UI thumbnail render size, not a source dimension/business limit.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SquarePostLocalMediaIssue.inspectionFailed
        }
        var stream = inspection
        try stream.append(bytes)
        let description = SquarePostLocalMediaDescription(reference: stream.token.reference, kind: .image,
            mimeType: mime, reportedByteCount: Int64(bytes.count), width: width, height: height, durationMilliseconds: nil)
        return try .init(evidence: stream.finish(description), bytes: bytes, thumbnail: UIImage(cgImage: pixels))
    }
}
