import Foundation

/// A bounded copy of one explicitly selected document. Extension and measured byte count
/// are its only inspection evidence: this type does not promise decoding or playback.
public struct ProjectStorySelectedAudio: Equatable, Sendable {
    public let id: UUID
    public let bytes: Data
    public let filename: String
    public let metadata: TemplateAudioDocumentMetadata
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.bytes == rhs.bytes && lhs.filename.utf8.elementsEqual(rhs.filename.utf8) && lhs.metadata == rhs.metadata
    }
    init(bytes: Data, filename: String, metadata: TemplateAudioDocumentMetadata, id: UUID = UUID()) throws {
        guard !bytes.isEmpty, bytes.count == metadata.byteCount,
              bytes.count <= TemplateAudioDocumentInspection.maximumBytes,
              Self.validFilename(filename, format: metadata.format) else { throw TemplateAudioDocumentFailure.unreadable }
        self.id = id; self.bytes = bytes; self.filename = filename; self.metadata = metadata
    }
    static func validFilename(_ value: String, format: TemplateAudioDocumentMetadata.Format) -> Bool {
        !value.isEmpty && value.utf16.count <= 255 &&
            value.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 && $0 != "/" && $0 != "\\" } &&
            (try? TemplateAudioDocumentInspection.format(fileExtension: (value as NSString).pathExtension)) == format
    }
}

/// Reuses the metadata inspector's real measured limit while retaining only the checked chunks
/// for this explicit upload review. The existing metadata-only inspector stays unchanged.
public enum ProjectStoryAudioCapture {
    public static func read(filename: String, reportedByteCount: Int?, checkCancellation: () throws -> Void,
                            readChunk: (Int) throws -> Data) throws -> ProjectStorySelectedAudio {
        let fileExtension = (filename as NSString).pathExtension
        let format = try TemplateAudioDocumentInspection.format(fileExtension: fileExtension)
        guard ProjectStorySelectedAudio.validFilename(filename, format: format) else { throw TemplateAudioDocumentFailure.unreadable }
        var copied = Data()
        let metadata = try TemplateAudioDocumentInspection.inspect(fileExtension: fileExtension, reportedByteCount: reportedByteCount,
            checkCancellation: checkCancellation, readChunk: { requested in
                let chunk = try readChunk(requested)
                guard chunk.count <= requested else { throw TemplateAudioDocumentFailure.invalidReader }
                guard copied.count <= TemplateAudioDocumentInspection.maximumBytes - chunk.count else { throw TemplateAudioDocumentFailure.tooLarge }
                try checkCancellation(); copied.append(chunk); return chunk
            })
        try checkCancellation()
        return try .init(bytes: copied, filename: filename, metadata: metadata)
    }
}
