import Foundation

public struct ProjectEditSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    /// Exact deployment/bundle scope supplied from RegionalSessionStorageScope.service.
    public let storageNamespace: String
    public init(accountID: Int, epoch: UInt64, storageNamespace: String) throws {
        guard accountID > 0, !storageNamespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectEditError.changedSession }
        self.accountID = accountID; self.epoch = epoch; self.storageNamespace = storageNamespace
    }
    public var ownerKey: String { "\(storageNamespace.utf8.count):\(storageNamespace):\(accountID)" }
}
public struct ProjectEditDraftIdentity: Codable, Equatable {
    public let topicID: Int?
    public let draftUUID: String?
    public init(topicID: Int) throws {
        guard topicID > 0 else { throw ProjectEditError.invalidContract }; self.topicID = topicID; draftUUID = nil
    }
    public init(draftUUID: String = UUID().uuidString) throws {
        guard UUID(uuidString: draftUUID) != nil else { throw ProjectEditError.invalidContract }; topicID = nil; self.draftUUID = draftUUID
    }
    public var bucket: String { topicID.map { "topic:\($0)" } ?? "new:\(draftUUID ?? "")" }
}
public struct ProjectEditEnvelope: Codable, Equatable {
    public let version: Int
    public let accountID: Int
    public let namespace: String
    public let identity: ProjectEditDraftIdentity
    public let baseRevision: String
    public let savedAt: Date
    public let draft: ProjectEditDraft
    public init(session: ProjectEditSession, identity: ProjectEditDraftIdentity, draft: ProjectEditDraft, now: Date = Date()) {
        version = 1; accountID = session.accountID; namespace = session.storageNamespace; self.identity = identity
        baseRevision = draft.baseRevision; savedAt = now; self.draft = draft
    }
}
public enum ProjectEditRestore {
    case missing, unavailable, memberMismatch, incompatible
    case revisionConflict(ProjectEditEnvelope), ready(ProjectEditEnvelope)
}
@MainActor public protocol ProjectEditDataStorage: AnyObject {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}
/// No UserDefaults/plaintext fallback. Persist full envelopes atomically through secure storage.
@MainActor public final class ProjectEditLocalStore {
    private let storage: any ProjectEditDataStorage
    public init(storage: any ProjectEditDataStorage) { self.storage = storage }
    private func key(_ session: ProjectEditSession, _ bucket: String) -> String {
        "project-editor.v1." + Data((session.ownerKey + ":" + bucket).utf8).base64EncodedString()
    }
    public func save(_ draft: ProjectEditDraft, session: ProjectEditSession, identity: ProjectEditDraftIdentity) throws {
        let envelope = ProjectEditEnvelope(session: session, identity: identity, draft: draft)
        try storage.write(JSONEncoder().encode(envelope), key: key(session, identity.bucket))
        if identity.topicID == nil {
            try storage.write(JSONEncoder().encode(identity), key: key(session, "active:\(draft.product.rawValue):\(draft.owner.rawValue)"))
        }
    }
    public func activeIdentity(session: ProjectEditSession, product: ProjectEditProduct, owner: ProjectEditOwner) throws -> ProjectEditDraftIdentity? {
        guard let data = try storage.read(key(session, "active:\(product.rawValue):\(owner.rawValue)")) else { return nil }
        let value = try JSONDecoder().decode(ProjectEditDraftIdentity.self, from: data)
        guard value.topicID == nil, value.draftUUID.flatMap(UUID.init(uuidString:)) != nil else { throw ProjectEditError.invalidContract }
        return value
    }
    public func load(session: ProjectEditSession, identity: ProjectEditDraftIdentity, baseline: ProjectEditDraft) -> ProjectEditRestore {
        let data: Data?
        do { data = try storage.read(key(session, identity.bucket)) } catch { return .unavailable }
        guard let data else { return .missing }
        guard let envelope = try? JSONDecoder().decode(ProjectEditEnvelope.self, from: data), envelope.version == 1 else { return .incompatible }
        guard envelope.accountID == session.accountID, envelope.namespace == session.storageNamespace else { return .memberMismatch }
        guard envelope.identity == identity, envelope.draft.product == baseline.product, envelope.draft.owner == baseline.owner else { return .incompatible }
        // Existing edits need a known equal revision. Empty revision never authorizes overwrite.
        if identity.topicID != nil && (baseline.baseRevision.isEmpty || envelope.baseRevision.isEmpty || envelope.baseRevision != baseline.baseRevision) {
            return .revisionConflict(envelope)
        }
        return .ready(envelope)
    }
    public func remove(session: ProjectEditSession, identity: ProjectEditDraftIdentity) throws {
        try storage.remove(key(session, identity.bucket))
        // Active pointer may remain; load returns missing. Never delete another draft's pointer.
    }
    public func pending(session: ProjectEditSession, identity: ProjectEditDraftIdentity) throws -> ProjectEditPending? {
        guard let data = try storage.read(key(session, "pending:" + identity.bucket)) else { return nil }
        let value = try JSONDecoder().decode(ProjectEditPending.self, from: data)
        guard value.ownerKey == session.ownerKey, value.identity == identity else { throw ProjectEditError.invalidContract }
        return value
    }
    public func savePending(_ value: ProjectEditPending, session: ProjectEditSession) throws {
        guard value.ownerKey == session.ownerKey else { throw ProjectEditError.changedSession }
        try storage.write(JSONEncoder().encode(value), key: key(session, "pending:" + value.identity.bucket))
    }
    public func clearPending(session: ProjectEditSession, identity: ProjectEditDraftIdentity) throws {
        try storage.remove(key(session, "pending:" + identity.bucket))
    }
}
public struct ProjectEditPending: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let identity: ProjectEditDraftIdentity
    public let payload: [String: ProjectEditJSON]
    public var dispatchStarted: Bool? = nil
    public var baseline: ProjectEditSnapshot? = nil
    public var completedTopicID: Int? = nil
    /// Optional for backwards-compatible decoding of existing local intents.
    public var serverAcknowledged: Bool? = nil
}
