import Foundation

public enum ImageUploadJournalFailure: Error { case unavailable, corrupt, locked }
/// Only operational identity is persisted. Epoch, screen/draft UUIDs, tokens, image bytes,
/// uploaded URLs and user-authored descriptions are deliberately absent.
public struct ImageUploadTarget: Codable, Equatable {
    public let accountID: Int
    public let namespace: String
    public let realm: String
    public let kind: String
    public let entityID: Int
    public let field: String
    public let resourceID: Int?
    public init(accountID: Int, namespace: String, realm: String, kind: String, entityID: Int, field: String, resourceID: Int? = nil) throws {
        self.accountID = accountID; self.namespace = namespace; self.realm = realm
        self.kind = kind; self.entityID = entityID; self.field = field; self.resourceID = resourceID
        try validate()
    }
    private func validate() throws {
        guard accountID > 0, entityID > 0, !namespace.isEmpty, namespace.utf8.count <= 4096,
              let url = URL(string: realm), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              resourceID == nil || resourceID! > 0 else { throw ImageUploadJournalFailure.corrupt }
        switch kind {
        case "merchant": guard MerchantImageField(rawValue: field) != nil else { throw ImageUploadJournalFailure.corrupt }
        case "review": guard field == "images", resourceID != nil else { throw ImageUploadJournalFailure.corrupt }
        case "im": guard field == "image", resourceID == nil else { throw ImageUploadJournalFailure.corrupt }
        default: throw ImageUploadJournalFailure.corrupt
        }
    }
    public init(scope: RetainedImageScope) throws {
        guard let namespace = scope.namespace else { throw ImageUploadJournalFailure.unavailable }
        switch scope.destination {
        case .merchant(let id, let field):
            try self.init(accountID: scope.accountID, namespace: namespace, realm: scope.realm,
                kind: "merchant", entityID: id, field: field.rawValue, resourceID: scope.resourceID)
        case .publicReview(let id, let registration):
            try self.init(accountID: scope.accountID, namespace: namespace, realm: scope.realm,
                kind: "review", entityID: id, field: "images", resourceID: registration)
        }
    }
    fileprivate var key: String {
        let parts = [namespace, realm, String(accountID), kind, String(entityID), field, resourceID.map(String.init) ?? "new"]
        return "image-upload.v1." + Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
}
public struct ImageUploadJournalEntry: Codable, Equatable {
    public enum Phase: String, Codable {
        case pending, acknowledged, locallyApplied, rejected
        public var permitsNewSelection: Bool { self == .locallyApplied || self == .rejected }
    }
    public let version: Int
    public let target: ImageUploadTarget
    public let attemptID: UUID
    public let phase: Phase
}
@MainActor public protocol ImageUploadJournal {
    func entry(for target: ImageUploadTarget) throws -> ImageUploadJournalEntry?
    func begin(target: ImageUploadTarget, attemptID: UUID) throws
    func record(target: ImageUploadTarget, attemptID: UUID, phase: ImageUploadJournalEntry.Phase) throws
}
/// Synchronous, atomic durable write must finish before begin returns. Reads/writes are
/// verified; corruption and any storage failure block dispatch. No automatic recovery API.
@MainActor public final class StoredImageUploadJournal: ImageUploadJournal {
    private let read: (String) throws -> Data?
    private let write: (Data, String) throws -> Void
    public init(read: @escaping (String) throws -> Data?, write: @escaping (Data, String) throws -> Void) {
        self.read = read; self.write = write
    }
    public func entry(for target: ImageUploadTarget) throws -> ImageUploadJournalEntry? {
        guard let bytes = try read(target.key) else { return nil }
        guard bytes.count <= 16384, let value = try? JSONDecoder().decode(ImageUploadJournalEntry.self, from: bytes),
              value.version == 1, value.target == target else { throw ImageUploadJournalFailure.corrupt }
        return value
    }
    public func begin(target: ImageUploadTarget, attemptID: UUID) throws {
        if let value = try entry(for: target), !value.phase.permitsNewSelection { throw ImageUploadJournalFailure.locked }
        try persist(.init(version: 1, target: target, attemptID: attemptID, phase: .pending))
    }
    public func record(target: ImageUploadTarget, attemptID: UUID, phase: ImageUploadJournalEntry.Phase) throws {
        guard let value = try entry(for: target), value.attemptID == attemptID,
              (value.phase == .pending && (phase == .acknowledged || phase == .rejected)) ||
              (value.phase == .acknowledged && phase == .locallyApplied) else { throw ImageUploadJournalFailure.locked }
        try persist(.init(version: 1, target: target, attemptID: attemptID, phase: phase))
    }
    private func persist(_ value: ImageUploadJournalEntry) throws {
        let bytes = try JSONEncoder().encode(value)
        try write(bytes, value.target.key)
        guard try read(value.target.key) == bytes else { throw ImageUploadJournalFailure.unavailable }
    }
}
/// Production callers must inject durable storage; omission never silently means memory-only.
@MainActor public struct UnavailableImageUploadJournal: ImageUploadJournal {
    public init() {}
    public func entry(for target: ImageUploadTarget) throws -> ImageUploadJournalEntry? { throw ImageUploadJournalFailure.unavailable }
    public func begin(target: ImageUploadTarget, attemptID: UUID) throws { throw ImageUploadJournalFailure.unavailable }
    public func record(target: ImageUploadTarget, attemptID: UUID, phase: ImageUploadJournalEntry.Phase) throws { throw ImageUploadJournalFailure.unavailable }
}
