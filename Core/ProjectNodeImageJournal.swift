import Foundation

/// Local per-draft upload attempts. No selected image bytes or credentials are persisted.
/// Unknown legacy uploads have no server reconciliation route and are never retried automatically.
@MainActor public final class ProjectNodeImageJournal {
    public struct Entry: Equatable {
        public let attemptID: UUID
        public let target: ProjectNodeImageTarget
        public let selectedDigest: String
        public let receipt: ProjectNodeUploadedImage?
        public let applied: Bool
    }
    public struct Snapshot: Equatable {
        public let ownerKey: String
        public let draftBucket: String
        public let entries: [Entry]
        fileprivate let raw: Data?
    }
    private struct StoredEntry: Codable {
        let attemptID: UUID, target: ProjectNodeImageTarget, selectedDigest: String
        var reference: String?
        var applied: Bool
    }
    private struct Envelope: Codable {
        let version: Int, ownerKey: String, draftBucket: String
        let entries: [StoredEntry]
    }
    private let storage: any ProjectEditDataStorage
    // Received-but-unstored facts survive a presentation closing within this AppSession.
    // This cache is explicitly not durable process-restart recovery.
    private var received: [String: [UUID: ProjectNodeUploadedImage]] = [:]
    public init(storage: any ProjectEditDataStorage) { self.storage = storage }
    private func key(owner: String, draft: String) -> String {
        "project-node-image.v1." + Data((owner + ":" + draft).utf8).base64EncodedString()
    }
    public func read(session: ProjectEditSession, identity: ProjectEditDraftIdentity) throws -> Snapshot {
        let bytes = try storage.read(key(owner: session.ownerKey, draft: identity.bucket))
        guard let bytes else { return .init(ownerKey: session.ownerKey, draftBucket: identity.bucket, entries: [], raw: nil) }
        guard bytes.count <= 4 * 1024 * 1024 else { throw ProjectNodeImageFailure.persistenceUnavailable }
        _ = try ApprovedTopicReleaseWire.envelope(bytes)
        let value = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard value.version == 1, value.ownerKey.utf8.elementsEqual(session.ownerKey.utf8),
              value.draftBucket.utf8.elementsEqual(identity.bucket.utf8), value.entries.count <= 256 else { throw ProjectNodeImageFailure.persistenceUnavailable }
        var ids = Set<UUID>()
        let entries = try value.entries.map { saved -> Entry in
            guard ids.insert(saved.attemptID).inserted, Data(saved.target.ownerKey.utf8) == Data(value.ownerKey.utf8),
                  Data(saved.target.draftBucket.utf8) == Data(value.draftBucket.utf8), ApprovedTopicReleasePreparation.validHash(saved.selectedDigest),
                  ApprovedTopicReleasePreparation.validHash(saved.target.originalDraftHash), !saved.target.chapterID.isEmpty,
                  !saved.target.nodeID.isEmpty, saved.reference != nil || !saved.applied else { throw ProjectNodeImageFailure.persistenceUnavailable }
            let receipt = try saved.reference.map { try ProjectNodeUploadedImage.restore(attemptID: saved.attemptID, targetID: saved.target.id, ownerKey: value.ownerKey, reference: $0) }
            return .init(attemptID: saved.attemptID, target: saved.target, selectedDigest: saved.selectedDigest, receipt: receipt, applied: saved.applied)
        }
        return .init(ownerKey: value.ownerKey, draftBucket: value.draftBucket, entries: entries, raw: bytes)
    }
    private func replace(_ expected: Snapshot, entries: [Entry], session: ProjectEditSession,
                         identity: ProjectEditDraftIdentity) throws -> Snapshot {
        guard Data(expected.ownerKey.utf8) == Data(session.ownerKey.utf8), Data(expected.draftBucket.utf8) == Data(identity.bucket.utf8),
              try read(session: session, identity: identity) == expected else { throw ProjectNodeImageFailure.changedContext }
        let stored = entries.map { StoredEntry(attemptID: $0.attemptID, target: $0.target, selectedDigest: $0.selectedDigest, reference: $0.receipt?.reference, applied: $0.applied) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Envelope(version: 1, ownerKey: expected.ownerKey, draftBucket: expected.draftBucket, entries: stored))
        guard bytes.count <= 4 * 1024 * 1024 else { throw ProjectNodeImageFailure.persistenceUnavailable }
        try storage.write(bytes, key: key(owner: expected.ownerKey, draft: expected.draftBucket))
        let saved = try read(session: session, identity: identity)
        guard saved.raw == bytes else { throw ProjectNodeImageFailure.persistenceUnavailable }; return saved
    }
    public func begin(target: ProjectNodeImageTarget, digest: String, expected: Snapshot,
                      session: ProjectEditSession, identity: ProjectEditDraftIdentity, id: UUID = UUID()) throws -> Snapshot {
        guard Data(target.ownerKey.utf8) == Data(expected.ownerKey.utf8), Data(target.draftBucket.utf8) == Data(expected.draftBucket.utf8),
              expected.entries.count < 256, !expected.entries.contains(where: { $0.attemptID == id }),
              ApprovedTopicReleasePreparation.validHash(digest) else { throw ProjectNodeImageFailure.persistenceUnavailable }
        let entry = Entry(attemptID: id, target: target, selectedDigest: digest, receipt: nil, applied: false)
        return try replace(expected, entries: expected.entries + [entry], session: session, identity: identity)
    }
    public func remember(_ receipt: ProjectNodeUploadedImage, identity: ProjectEditDraftIdentity) {
        received[key(owner: receipt.ownerKey, draft: identity.bucket), default: [:]][receipt.attemptID] = receipt
    }
    public func unstored(session: ProjectEditSession, identity: ProjectEditDraftIdentity) -> [ProjectNodeUploadedImage] {
        Array(received[key(owner: session.ownerKey, draft: identity.bucket), default: [:]].values)
            .sorted { $0.attemptID.uuidString < $1.attemptID.uuidString }
    }
    public func record(_ receipt: ProjectNodeUploadedImage, expected: Snapshot, session: ProjectEditSession,
                       identity: ProjectEditDraftIdentity) throws -> Snapshot {
        guard Data(receipt.ownerKey.utf8) == Data(expected.ownerKey.utf8),
              let i = expected.entries.firstIndex(where: { $0.attemptID == receipt.attemptID }),
              expected.entries[i].target.id == receipt.targetID,
              expected.entries[i].receipt == nil || expected.entries[i].receipt == receipt else { throw ProjectNodeImageFailure.changedContext }
        var entries = expected.entries; let old = entries[i]
        entries[i] = .init(attemptID: old.attemptID, target: old.target, selectedDigest: old.selectedDigest, receipt: receipt, applied: old.applied)
        let saved = try replace(expected, entries: entries, session: session, identity: identity)
        received[key(owner: receipt.ownerKey, draft: identity.bucket)]?.removeValue(forKey: receipt.attemptID)
        return saved
    }
    public func markApplied(attemptID: UUID, expected: Snapshot, session: ProjectEditSession,
                            identity: ProjectEditDraftIdentity) throws -> Snapshot {
        guard let i = expected.entries.firstIndex(where: { $0.attemptID == attemptID }), expected.entries[i].receipt != nil else { throw ProjectNodeImageFailure.changedContext }
        var entries = expected.entries; let old = entries[i]
        entries[i] = .init(attemptID: old.attemptID, target: old.target, selectedDigest: old.selectedDigest, receipt: old.receipt, applied: true)
        return try replace(expected, entries: entries, session: session, identity: identity)
    }
}
