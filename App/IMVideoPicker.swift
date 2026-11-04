import Foundation
import UniformTypeIdentifiers

/// A user-selected system document only; no directory enumeration, URL fetch, execution or implicit upload.
@MainActor enum IMVideoPicker {
    static var types: [UTType] { [.mpeg4Movie, .quickTimeMovie] }
    static func read(_ url: URL, policy: IMVideoPolicy) throws -> IMVideoSelection {
        try policy.validate()
        guard url.isFileURL else { throw IMVideoFailure.invalid }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
              size > 0, size <= policy.maximumSourceBytes else { throw IMVideoFailure.invalid }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var bytes = Data()
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard bytes.count + chunk.count <= policy.maximumSourceBytes else { throw IMVideoFailure.invalid }
            bytes.append(chunk)
        }
        guard bytes.count == size else { throw IMVideoFailure.invalid }
        return try IMVideoSelection(name: url.lastPathComponent, bytes: bytes, policy: policy)
    }
}
