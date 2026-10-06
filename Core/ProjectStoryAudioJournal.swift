import Foundation

/// Local per-draft upload attempts. No selected document bytes or credentials are persisted.
/// Unknown legacy uploads have no server reconciliation route and are never retried automatically.
@MainActor public final class ProjectStoryAudioJournal {
    public struct Entry: Equatable {
        public let attemptID: UUID
        public let target: ProjectStoryAudioTarget
        public let selectedDigest: String
        public let receipt: ProjectStoryUploadedAudio?
        public let applied: Bool
    }
    public struct Snapshot: Equatable {
        public let ownerKey: String
        public let draftBucket: String
        public let entries: [Entry]
        fileprivate let raw: Data?
    }
    private struct StoredEntry: Codable {
        let attemptID: UUID, target: ProjectStoryAudioTarget, selectedDigest: String
        var reference: String?
        var filename: String?
        var format: String?
        var applied: Bool
    }
    private struct Envelope: Codable {
        let version: Int, ownerKey: String, draftBucket: String
        let entries: [StoredEntry]
    }
    private let storage: any ProjectEditDataStorage
    // Received-but-unstored facts survive a presentation closing within this AppSession.
    // This cache is explicitly not durable process-restart recovery.
    private var received: [String: [UUID: ProjectStoryUploadedAudio]] = [:]
    public init(storage: any ProjectEditDataStorage) { self.storage = storage }
    private func key(owner: String, draft: String) -> String {
        "project-story-audio.v1." + Data((owner + ":" + draft).utf8).base64EncodedString()
    }
    public func read(session: ProjectEditSession, identity: ProjectEditDraftIdentity) throws -> Snapshot {
        let bytes = try storage.read(key(owner: session.ownerKey, draft: identity.bucket))
        guard let bytes else { return .init(ownerKey: session.ownerKey, draftBucket: identity.bucket, entries: [], raw: nil) }
        guard bytes.count <= 4 * 1024 * 1024 else { throw ProjectStoryAudioFailure.persistenceUnavailable }
        _ = try ApprovedTopicReleaseWire.envelope(bytes)
        let value = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard value.version == 1, value.ownerKey.utf8.elementsEqual(session.ownerKey.utf8),
              value.draftBucket.utf8.elementsEqual(identity.bucket.utf8), value.entries.count <= 256 else { throw ProjectStoryAudioFailure.persistenceUnavailable }
        var ids = Set<UUID>()
        let entries = try value.entries.map { saved -> Entry in
            guard ids.insert(saved.attemptID).inserted, saved.target.ownerKey == value.ownerKey,
                  saved.target.draftBucket == value.draftBucket, ApprovedTopicReleasePreparation.validHash(saved.selectedDigest),
                  ApprovedTopicReleasePreparation.validHash(saved.target.originalDraftHash), !saved.target.chapterID.isEmpty,
                  !saved.target.blockID.isEmpty, saved.reference != nil || !saved.applied else { throw ProjectStoryAudioFailure.persistenceUnavailable }
            let receipt = try saved.reference.map { reference -> ProjectStoryUploadedAudio in
                guard let filename = saved.filename, let rawFormat = saved.format,
                      let format = TemplateAudioDocumentMetadata.Format(rawValue: rawFormat) else { throw ProjectStoryAudioFailure.persistenceUnavailable }
                return try .restore(attemptID: saved.attemptID, ownerKey: value.ownerKey, reference: reference, filename: filename, format: format)
            }
            guard receipt != nil || (saved.filename == nil && saved.format == nil) else { throw ProjectStoryAudioFailure.persistenceUnavailable }
            return .init(attemptID: saved.attemptID, target: saved.target, selectedDigest: saved.selectedDigest, receipt: receipt, applied: saved.applied)
        }
        return .init(ownerKey: value.ownerKey, draftBucket: value.draftBucket, entries: entries, raw: bytes)
    }
    private func replace(_ expected: Snapshot, entries: [Entry], session: ProjectEditSession,
                         identity: ProjectEditDraftIdentity) throws -> Snapshot {
        guard expected.ownerKey == session.ownerKey, expected.draftBucket == identity.bucket,
              try read(session: session, identity: identity) == expected else { throw ProjectStoryAudioFailure.changedContext }
        let stored = entries.map { StoredEntry(attemptID: $0.attemptID, target: $0.target, selectedDigest: $0.selectedDigest, reference: $0.receipt?.reference, filename: $0.receipt?.filename, format: $0.receipt?.format.rawValue, applied: $0.applied) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Envelope(version: 1, ownerKey: expected.ownerKey, draftBucket: expected.draftBucket, entries: stored))
        guard bytes.count <= 4 * 1024 * 1024 else { throw ProjectStoryAudioFailure.persistenceUnavailable }
        try storage.write(bytes, key: key(owner: expected.ownerKey, draft: expected.draftBucket))
        let saved = try read(session: session, identity: identity)
        guard saved.raw == bytes else { throw ProjectStoryAudioFailure.persistenceUnavailable }; return saved
    }
    public func begin(target: ProjectStoryAudioTarget, digest: String, expected: Snapshot,
                      session: ProjectEditSession, identity: ProjectEditDraftIdentity, id: UUID = UUID()) throws -> Snapshot {
        guard target.ownerKey == expected.ownerKey, target.draftBucket == expected.draftBucket,
              expected.entries.count < 256, !expected.entries.contains(where: { $0.attemptID == id }),
              ApprovedTopicReleasePreparation.validHash(digest) else { throw ProjectStoryAudioFailure.persistenceUnavailable }
        let entry = Entry(attemptID: id, target: target, selectedDigest: digest, receipt: nil, applied: false)
        return try replace(expected, entries: expected.entries + [entry], session: session, identity: identity)
    }
    public func remember(_ receipt: ProjectStoryUploadedAudio, identity: ProjectEditDraftIdentity) {
        received[key(owner: receipt.ownerKey, draft: identity.bucket), default: [:]][receipt.attemptID] = receipt
    }
    public func unstored(session: ProjectEditSession, identity: ProjectEditDraftIdentity) -> [ProjectStoryUploadedAudio] {
        Array(received[key(owner: session.ownerKey, draft: identity.bucket), default: [:]].values)
            .sorted { $0.attemptID.uuidString < $1.attemptID.uuidString }
    }
    public func record(_ receipt: ProjectStoryUploadedAudio, expected: Snapshot, session: ProjectEditSession,
                       identity: ProjectEditDraftIdentity) throws -> Snapshot {
        guard receipt.ownerKey == expected.ownerKey,
              let i = expected.entries.firstIndex(where: { $0.attemptID == receipt.attemptID }),
              expected.entries[i].receipt == nil || expected.entries[i].receipt == receipt else { throw ProjectStoryAudioFailure.changedContext }
        var entries = expected.entries; let old = entries[i]
        entries[i] = .init(attemptID: old.attemptID, target: old.target, selectedDigest: old.selectedDigest, receipt: receipt, applied: old.applied)
        let saved = try replace(expected, entries: entries, session: session, identity: identity)
        received[key(owner: receipt.ownerKey, draft: identity.bucket)]?.removeValue(forKey: receipt.attemptID)
        return saved
    }
    public func markApplied(attemptID: UUID, expected: Snapshot, session: ProjectEditSession,
                            identity: ProjectEditDraftIdentity) throws -> Snapshot {
        guard let i = expected.entries.firstIndex(where: { $0.attemptID == attemptID }), expected.entries[i].receipt != nil else { throw ProjectStoryAudioFailure.changedContext }
        var entries = expected.entries; let old = entries[i]
        entries[i] = .init(attemptID: old.attemptID, target: old.target, selectedDigest: old.selectedDigest, receipt: old.receipt, applied: true)
        return try replace(expected, entries: entries, session: session, identity: identity)
    }
}
