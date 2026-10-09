import Foundation

public struct TemplateAuthoringSession: Equatable {
    public let accountID: Int
    public let namespace: String
    public let epoch: UInt64
    public let authorizationRevision: String
    public init(accountID: Int, namespace: String, epoch: UInt64, authorizationRevision: String) throws {
        guard accountID > 0, !namespace.isEmpty, !authorizationRevision.isEmpty else { throw TemplateAuthoringError.changedSession }
        self.accountID = accountID; self.namespace = namespace; self.epoch = epoch; self.authorizationRevision = authorizationRevision
    }
    public var ownerKey: String { "\(namespace.utf8.count):\(namespace):\(accountID)" }
}
public struct TemplateAuthoringIdentity: Codable, Equatable, Hashable {
    public let draftID: UUID
    public init(draftID: UUID = UUID()) { self.draftID = draftID }
}
public struct TemplateAuthoringEnvelope: Codable, Equatable {
    public let version: Int
    public let accountID: Int
    public let namespace: String
    public let identity: TemplateAuthoringIdentity
    public let draft: TemplateAuthoringDraft
    public let savedAt: Date
    public init(session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity, draft: TemplateAuthoringDraft) {
        version = 1; accountID = session.accountID; namespace = session.namespace; self.identity = identity; self.draft = draft; savedAt = Date()
    }
}
public struct TemplateAuthoringPending: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let identity: TemplateAuthoringIdentity
    public let request: TemplateAuthoringRequest
    public let createdAt: Date
    public var terminal: Bool = false
    public var acknowledged: Bool? = nil
    public var savedDraft: TemplateAuthoringSavedDraft? = nil
}
@MainActor public protocol TemplateAuthoringStorage: AnyObject {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}
public enum TemplateAuthoringRestore: Equatable {
    case missing, unavailable, incompatible, ownerMismatch
    case ready(TemplateAuthoringEnvelope)
}
@MainActor public final class TemplateAuthoringLocalStore {
    private let storage: any TemplateAuthoringStorage
    public init(storage: any TemplateAuthoringStorage) { self.storage = storage }
    private func key(_ session: TemplateAuthoringSession, _ suffix: String) -> String {
        "template-author.v1." + Data((session.ownerKey + ":" + suffix).utf8).base64EncodedString()
    }
    public func active(session: TemplateAuthoringSession) throws -> TemplateAuthoringIdentity? {
        guard let raw = try storage.read(key(session, "active")) else { return nil }
        return try JSONDecoder().decode(TemplateAuthoringIdentity.self, from: raw)
    }
    public func save(_ draft: TemplateAuthoringDraft, session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity) throws {
        let value = TemplateAuthoringEnvelope(session: session, identity: identity, draft: draft)
        try storage.write(JSONEncoder().encode(value), key: key(session, identity.draftID.uuidString))
        try storage.write(JSONEncoder().encode(identity), key: key(session, "active"))
    }
    public func load(session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity) -> TemplateAuthoringRestore {
        let raw: Data?
        do { raw = try storage.read(key(session, identity.draftID.uuidString)) } catch { return .unavailable }
        guard let raw else { return .missing }
        guard let value = try? JSONDecoder().decode(TemplateAuthoringEnvelope.self, from: raw), value.version == 1, value.identity == identity else { return .incompatible }
        guard value.accountID == session.accountID, value.namespace == session.namespace else { return .ownerMismatch }
        // Existing server drafts cannot be safely hydrated from public /info projections.
        guard value.draft.id == nil else { return .incompatible }
        return .ready(value)
    }
    public func pending(session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity) throws -> TemplateAuthoringPending? {
        guard let raw = try storage.read(key(session, "pending:" + identity.draftID.uuidString)) else { return nil }
        let value = try JSONDecoder().decode(TemplateAuthoringPending.self, from: raw)
        guard value.ownerKey == session.ownerKey, value.identity == identity,
              value.savedDraft == nil || value.savedDraft?.matches(value, session: session) == true else { throw TemplateAuthoringError.invalidContract }
        return value
    }
    public func savePending(_ value: TemplateAuthoringPending, session: TemplateAuthoringSession) throws {
        guard value.ownerKey == session.ownerKey else { throw TemplateAuthoringError.changedSession }
        guard value.savedDraft == nil || value.savedDraft?.matches(value, session: session) == true else { throw TemplateAuthoringError.invalidContract }
        // Receipt and terminal flag occupy one existing pending record, never two independent writes.
        try storage.write(JSONEncoder().encode(value), key: key(session, "pending:" + value.identity.draftID.uuidString))
        if value.savedDraft != nil {
            guard try pending(session: session, identity: value.identity) == value else { throw TemplateAuthoringError.storageUnavailable }
        }
    }
    public func clearPending(session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity) throws {
        try storage.remove(key(session, "pending:" + identity.draftID.uuidString))
    }
    public func shelfPending(session: TemplateAuthoringSession) throws -> TemplateOwnShelfPending? {
        guard let raw = try storage.read(key(session, "own-shelf-pending")) else { return nil }
        let value = try JSONDecoder().decode(TemplateOwnShelfPending.self, from: raw)
        guard value.ownerKey == session.ownerKey else { throw TemplateAuthoringError.invalidContract }
        return value
    }
    public func saveShelfPending(_ value: TemplateOwnShelfPending, session: TemplateAuthoringSession) throws {
        guard value.ownerKey == session.ownerKey else { throw TemplateAuthoringError.changedSession }
        try storage.write(JSONEncoder().encode(value), key: key(session, "own-shelf-pending"))
    }
    public func clearShelfPending(session: TemplateAuthoringSession) throws {
        try storage.remove(key(session, "own-shelf-pending"))
    }
    public func discard(session: TemplateAuthoringSession, identity: TemplateAuthoringIdentity) throws {
        guard try pending(session: session, identity: identity) == nil else { throw TemplateAuthoringError.uncertain }
        try storage.remove(key(session, identity.draftID.uuidString))
    }
}
