import Foundation

public struct ProjectEditSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    /// Runtime-only monotonic viewer context; deliberately excluded from durable owner keys/envelopes.
    public let viewerRevision: UInt64
    public let configurationRevision: UInt64
    /// Exact deployment/bundle scope supplied from RegionalSessionStorageScope.service.
    public let storageNamespace: String
    public init(accountID: Int, epoch: UInt64, storageNamespace: String, viewerRevision: UInt64 = 0, configurationRevision: UInt64 = 0) throws {
        guard accountID > 0, !storageNamespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectEditError.changedSession }
        self.accountID = accountID; self.epoch = epoch; self.storageNamespace = storageNamespace; self.viewerRevision = viewerRevision; self.configurationRevision = configurationRevision
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
        version = draft.pendingMaterials == nil ? 1 : 2; accountID = session.accountID; namespace = session.storageNamespace; self.identity = identity
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
    /// Story-template adoption is deliberately narrower than ordinary save: it may
    /// replace only an already committed, exact local preimage. No active pointer is
    /// created, switched or rewritten. The existing general save semantics stay intact.
    public func canReplaceExistingStoryDraft(_ expected: ProjectEditDraft, session: ProjectEditSession, identity: ProjectEditDraftIdentity) -> Bool {
        (try? existingStoryPreimage(expected, session: session, identity: identity)) != nil
    }
    public func replaceExistingStoryDraft(_ draft: ProjectEditDraft, replacing expected: ProjectEditDraft,
                                          session: ProjectEditSession, identity: ProjectEditDraftIdentity) throws {
        guard draft.product == expected.product, draft.owner == expected.owner,
              draft.baseRevision.utf8.elementsEqual(expected.baseRevision.utf8) else { throw ProjectEditError.invalidContract }
        let envelopeKey = try existingStoryPreimage(expected, session: session, identity: identity)
        let bytes = try JSONEncoder().encode(ProjectEditEnvelope(session: session, identity: identity, draft: draft))
        // The secure storage provider atomically replaces this single item. A failed
        // item write leaves its old bytes intact. There is no second write or fallback.
        try storage.write(bytes, key: envelopeKey)
    }
    private func existingStoryPreimage(_ expected: ProjectEditDraft, session: ProjectEditSession,
                                       identity: ProjectEditDraftIdentity) throws -> String {
        guard expected.product == .city, expected.owner == .personal else { throw ProjectEditError.invalidContract }
        if identity.topicID == nil {
            let pointerKey = key(session, "active:\(expected.product.rawValue):\(expected.owner.rawValue)")
            guard let pointerData = try storage.read(pointerKey),
                  let rawPointer = try? ApprovedTopicReleaseWire.envelope(pointerData),
                  Set(rawPointer.keys).isSubset(of: ["topicID", "draftUUID"]),
                  let pointer = try? JSONDecoder().decode(ProjectEditDraftIdentity.self, from: pointerData),
                  pointer.topicID == nil, pointer.draftUUID.flatMap(UUID.init(uuidString:)) != nil,
                  pointer == identity else { throw ProjectEditError.persistenceUnavailable }
        }
        let envelopeKey = key(session, identity.bucket)
        guard let data = try storage.read(envelopeKey),
              let raw = try? ApprovedTopicReleaseWire.envelope(data),
              let stored = try? JSONDecoder().decode(ProjectEditEnvelope.self, from: data),
              let retained = try? JSONEncoder().encode(stored), let sourceText = String(data: data, encoding: .utf8),
              try ContentDraftJSON.parse(sourceText) == ContentDraftJSON.parse(String(decoding: retained, as: UTF8.self)),
              stored.version == (stored.draft.pendingMaterials == nil ? 1 : 2),
              stored.accountID == session.accountID, stored.namespace == session.storageNamespace,
              stored.identity == identity, stored.draft.product == expected.product, stored.draft.owner == expected.owner,
              stored.baseRevision.utf8.elementsEqual(expected.baseRevision.utf8),
              stored.draft.baseRevision.utf8.elementsEqual(expected.baseRevision.utf8),
              identity.topicID == nil || !expected.baseRevision.isEmpty,
              let originalDraft = raw["draft"],
              let original = ProjectEditPendingMaterials.exactData(originalDraft),
              let proposedPreimage = ProjectEditPendingMaterials.exactData(expected),
              try ContentDraftJSON.parse(String(decoding: original, as: UTF8.self)) == ContentDraftJSON.parse(String(decoding: proposedPreimage, as: UTF8.self)) else { throw ProjectEditError.persistenceUnavailable }
        return envelopeKey
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
        guard let envelope = try? JSONDecoder().decode(ProjectEditEnvelope.self, from: data),
              (envelope.version == 1 && envelope.draft.pendingMaterials == nil) ||
              (envelope.version == 2 && envelope.draft.pendingMaterials != nil) else { return .incompatible }
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
        guard value.ownerKey == session.ownerKey, value.identity == identity, value.hasConsistentAcknowledgment else { throw ProjectEditError.invalidContract }
        return value
    }
    public func savePending(_ value: ProjectEditPending, session: ProjectEditSession) throws {
        guard value.ownerKey == session.ownerKey, value.hasConsistentAcknowledgment else { throw ProjectEditError.changedSession }
        try storage.write(JSONEncoder().encode(value), key: key(session, "pending:" + value.identity.bucket))
    }
    /// Explicit continuation of an acknowledged existing-topic update only. Synchronous
    /// checks bracket the baseline write; an uncertain operation can never enter here.
    public func advanceAcknowledged(_ expected: ProjectEditPending, baseline: ProjectEditSnapshot, session: ProjectEditSession, isCurrent: () -> Bool) throws {
        guard isCurrent(), expected.serverAcknowledged == true, let topicID = expected.identity.topicID,
              expected.completedTopicID == topicID, baseline.topicID == topicID,
              expected.ownerKey == session.ownerKey, !baseline.draft.baseRevision.isEmpty,
              let current = try pending(session: session, identity: expected.identity),
              Self.exactPending(current, expected), try storedPendingMatches(expected, session: session) else { throw ProjectEditContinuationFailure.changedPending }
        try save(baseline.draft, session: session, identity: expected.identity)
        do {
            guard isCurrent(), let current = try pending(session: session, identity: expected.identity),
                  Self.exactPending(current, expected), try storedPendingMatches(expected, session: session), isCurrent() else { throw ProjectEditContinuationFailure.changedPending }
            try clearPending(session: session, identity: expected.identity)
        } catch { throw ProjectEditContinuationFailure.baselineSaved }
    }
    private func storedPendingMatches(_ expected: ProjectEditPending, session: ProjectEditSession) throws -> Bool {
        guard let data = try storage.read(key(session, "pending:" + expected.identity.bucket)) else { return false }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Preserve unknown future fields in the comparison instead of treating a lossy
        // Codable projection as permission to remove a newer-format completion record.
        let raw = try JSONDecoder().decode(ProjectEditJSON.self, from: data)
        let known = try JSONDecoder().decode(ProjectEditJSON.self, from: encoder.encode(expected))
        return try encoder.encode(raw) == encoder.encode(known)
    }
    public static func exactPending(_ lhs: ProjectEditPending, _ rhs: ProjectEditPending) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(lhs), let right = try? encoder.encode(rhs) else { return false }
        return left == right
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
    /// Submission-time evidence only. Optional preserves older local completion records.
    public var bundleAcknowledgment: ProjectEditBundleAcknowledgment? = nil
    public var hasConsistentAcknowledgment: Bool {
        guard let bundleAcknowledgment else { return true }
        guard serverAcknowledged == true, completedTopicID == bundleAcknowledgment.topicID,
              identity.topicID == nil || identity.topicID == bundleAcknowledgment.topicID,
              let path = try? ProjectEditStoryContract.path(payload: payload, baseline: baseline) else { return false }
        return path == ProjectEditStoryContract.createPath || path == ProjectEditStoryContract.updatePath
    }
}
