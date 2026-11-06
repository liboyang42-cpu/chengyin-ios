import Foundation
import UniformTypeIdentifiers

/// A user-selected system document only; no directory enumeration, URL fetch, execution or implicit upload.
@MainActor enum IMFilePicker {
    static var types: [UTType] { IMFileSelection.extensions.compactMap { UTType(filenameExtension: $0) } }
    static func read(_ url: URL) throws -> IMFileSelection {
        guard url.isFileURL else { throw IMFileFailure.invalid }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
              size > 0, size <= IMFileSelection.maximumBytes else { throw IMFileFailure.invalid }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var bytes = Data()
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard bytes.count + chunk.count <= IMFileSelection.maximumBytes else { throw IMFileFailure.invalid }
            bytes.append(chunk)
        }
        guard bytes.count == size else { throw IMFileFailure.invalid }
        return try IMFileSelection(name: url.lastPathComponent, bytes: bytes)
    }
}
