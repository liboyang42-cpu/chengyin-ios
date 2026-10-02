import Foundation

public struct MerchantEvidenceSelection: Equatable, Identifiable {
    public let id: UUID
    public let bytes: Data
    public let filename: String
    public let mimeType: String
    /// The 20 MiB ceiling is a native memory budget, not a claimed source/backend limit.
    public init(bytes: Data, filename: String, mimeType: String, id: UUID = UUID()) throws {
        guard !bytes.isEmpty, bytes.count <= 20 * 1024 * 1024,
              filename.range(of: #"^[A-Za-z0-9._-]+\.(?:jpe?g|png|gif)$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.invalid }
        let valid: Bool
        switch mimeType {
        case "image/png": valid = bytes.starts(with: [137,80,78,71,13,10,26,10]) && filename.hasSuffix(".png")
        case "image/jpeg": valid = bytes.starts(with: [0xff,0xd8,0xff]) && (filename.hasSuffix(".jpg") || filename.hasSuffix(".jpeg"))
        case "image/gif": valid = (bytes.starts(with: Data("GIF87a".utf8)) || bytes.starts(with: Data("GIF89a".utf8))) && filename.hasSuffix(".gif")
        default: valid = false
        }
        guard valid else { throw MerchantBusinessFailure.invalid }
        self.id = id; self.bytes = bytes; self.filename = filename; self.mimeType = mimeType
    }
    public static func importing(_ bytes: Data) throws -> Self {
        if bytes.starts(with: [137,80,78,71,13,10,26,10]) { return try .init(bytes: bytes, filename: "evidence.png", mimeType: "image/png") }
        if bytes.starts(with: [0xff,0xd8,0xff]) { return try .init(bytes: bytes, filename: "evidence.jpg", mimeType: "image/jpeg") }
        return try .init(bytes: bytes, filename: "evidence.gif", mimeType: "image/gif")
    }
}
@MainActor public protocol MerchantEvidenceSelecting {
    func choose() async throws -> MerchantEvidenceSelection?
}
@MainActor public final class MerchantEvidenceSelectionCoordinator {
    public private(set) var selected: MerchantEvidenceSelection?
    public private(set) var isSelecting = false
    private var revision = 0
    public init() {}
    public func clear() { revision += 1; selected = nil; isSelecting = false }
    public func select(using picker: any MerchantEvidenceSelecting) async throws {
        guard !isSelecting else { return }
        revision += 1; let stamp = revision; isSelecting = true
        defer { if stamp == revision { isSelecting = false } }
        let choice = try await picker.choose()
        guard stamp == revision, !Task.isCancelled else { return }; selected = choice
    }
}
