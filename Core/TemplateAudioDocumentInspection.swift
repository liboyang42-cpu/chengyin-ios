import Foundation

/// These are local selection purposes, never upload capabilities or permission grants.
public enum TemplateAudioDocumentPurpose: Equatable, Sendable {
    public enum Option: String, CaseIterable, Sendable { case a = "A", b = "B", c = "C", d = "D" }
    case questionAudio
    case optionAudio(Option)
    case narration
}

public struct TemplateAudioDocumentRequest: Equatable, Sendable {
    public let id: UUID
    public let purpose: TemplateAudioDocumentPurpose
    public init(purpose: TemplateAudioDocumentPurpose, id: UUID = UUID()) {
        self.id = id; self.purpose = purpose
    }
}

public enum TemplateAudioDocumentFailure: Error, Equatable, Sendable {
    case notConfigured, selectionInProgress, invalidSelectionCount, unsupportedExtension, empty, tooLarge
    case unreadable, coordinationFailed, changedDuringRead, invalidReader
}

/// This receipt proves only extension and bounded byte count. It is not an imported attachment,
/// playable audio, upload acknowledgement or reference. No path, filename or bytes are retained.
public struct TemplateAudioDocumentMetadata: Equatable, Sendable {
    public enum Format: String, CaseIterable, Sendable { case mp3, m4a, aac }
    public enum Evidence: Equatable, Sendable { case extensionAndByteCountOnly }
    public let format: Format
    public let byteCount: Int
    public let evidence: Evidence = .extensionAndByteCountOnly
    fileprivate init(format: Format, byteCount: Int) { self.format = format; self.byteCount = byteCount }
}

public enum TemplateAudioDocumentSelectionResult: Equatable, Sendable {
    case inspected(TemplateAudioDocumentRequest, TemplateAudioDocumentMetadata)
    case cancelled(TemplateAudioDocumentRequest)
    case failed(TemplateAudioDocumentRequest, TemplateAudioDocumentFailure)
}

/// Inspects one mp3/m4a/aac document under a 10 MiB single-file limit.
/// Unknown metadata size is still subject to the same measured-byte limit here.
public enum TemplateAudioDocumentInspection {
    public static let maximumBytes = 10 * 1024 * 1024
    public static let chunkBytes = 64 * 1024

    public static func format(fileExtension: String) throws -> TemplateAudioDocumentMetadata.Format {
        guard let format = TemplateAudioDocumentMetadata.Format(rawValue: fileExtension.lowercased()) else {
            throw TemplateAudioDocumentFailure.unsupportedExtension
        }
        return format
    }

    /// Consume bounded chunks and discard each immediately. The single extra byte detects files
    /// that exceed the cap even when provider metadata is absent, incorrect or changes mid-read.
    /// No audio decoder runs: a renamed non-audio file may produce this metadata-only receipt.
    public static func inspect(fileExtension: String, reportedByteCount: Int?,
                               checkCancellation: () throws -> Void = {},
                               readChunk: (Int) throws -> Data) throws -> TemplateAudioDocumentMetadata {
        let format = try format(fileExtension: fileExtension)
        try checkCancellation()
        if let count = reportedByteCount {
            guard count >= 0 else { throw TemplateAudioDocumentFailure.unreadable }
            guard count <= maximumBytes else { throw TemplateAudioDocumentFailure.tooLarge }
        }
        var total = 0
        while true {
            try checkCancellation()
            let requested = min(chunkBytes, maximumBytes - total + 1)
            let chunk = try readChunk(requested)
            guard chunk.count <= requested else { throw TemplateAudioDocumentFailure.invalidReader }
            try checkCancellation()
            if chunk.isEmpty { break }
            total += chunk.count
            guard total <= maximumBytes else { throw TemplateAudioDocumentFailure.tooLarge }
        }
        guard total > 0 else { throw TemplateAudioDocumentFailure.empty }
        if let reportedByteCount, total != reportedByteCount {
            throw TemplateAudioDocumentFailure.changedDuringRead
        }
        return TemplateAudioDocumentMetadata(format: format, byteCount: total)
    }
}
