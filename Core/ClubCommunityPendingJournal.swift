import Foundation

public enum ClubCommunityPendingJournalFailure: Error, Equatable {
    case invalidTarget
    case locked
    case corrupt
    case persistenceFailed
}

/// Minimal scope-isolated target for a Club community write operation.
/// Deliberately excludes tokens, post/comment text, image URLs/bytes, nicknames, and login epoch
/// so an unresolved `UNKNOWN` write remains locked across app restarts and new login epochs
/// for the same `(namespace, accountID, clubID, postID, commentID)` target.
public struct ClubCommunityPendingTarget: Codable, Equatable, Hashable, Sendable {
    public let namespace: String
    public let accountID: Int
    public let clubID: Int
    public let postID: Int
    public let commentID: Int

    public init(
        namespace: String = "default",
        accountID: Int,
        clubID: Int,
        postID: Int = 0,
        commentID: Int = 0
    ) throws {
        let trimmedNamespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNamespace.isEmpty,
              trimmedNamespace.utf8.count <= 4096,
              accountID > 0,
              clubID > 0,
              postID >= 0,
              commentID >= 0,
              (commentID == 0 || postID > 0) else {
            throw ClubCommunityPendingJournalFailure.invalidTarget
        }
        self.namespace = trimmedNamespace
        self.accountID = accountID
        self.clubID = clubID
        self.postID = postID
        self.commentID = commentID
    }

    public init(evidence: ClubCommunityEvidence, namespace: String = "default") throws {
        try self.init(
            namespace: namespace,
            accountID: evidence.identity.accountID ?? 0,
            clubID: evidence.clubID,
            postID: evidence.post?.id ?? 0,
            commentID: evidence.comment?.id ?? 0
        )
    }

    public var lockKey: String {
        "\(accountID):\(clubID):\(postID):\(commentID)"
    }

    public var storageKey: String {
        let parts = [
            namespace,
            String(accountID),
            String(clubID),
            String(postID),
            String(commentID)
        ]
        let payload = parts.map { "\($0.utf8.count):\($0)" }.joined()
        return "questify.club.community.pending.v1." + Data(payload.utf8).base64EncodedString()
    }
}

/// Minimal durable pending-operation record.
/// Contains only schema version, target identity, operation UUID, canonical operation kind tag, and phase.
/// Never stores tokens, post/comment body text, or image references/bytes.
public struct ClubCommunityPendingRecord: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Equatable, Sendable {
        case sending
        case unknownLocked
    }

    public static let allowedOperationKinds: Set<String> = [
        "create", "edit", "pin", "delete", "report",
        "like", "comment", "deleteComment", "reportComment"
    ]

    public let version: Int
    public let target: ClubCommunityPendingTarget
    public let operationID: UUID
    public let operationKind: String
    public let phase: Phase

    public init(
        version: Int = 1,
        target: ClubCommunityPendingTarget,
        operationID: UUID,
        operationKind: String,
        phase: Phase
    ) throws {
        guard version == 1,
              Self.allowedOperationKinds.contains(operationKind) else {
            throw ClubCommunityPendingJournalFailure.corrupt
        }
        self.version = version
        self.target = target
        self.operationID = operationID
        self.operationKind = operationKind
        self.phase = phase
    }
}

/// Authoritative resolution required to release a persisted pending lock.
/// Never accepts post/comment list snapshots, title/content matching, or count deltas.
public enum ClubCommunityAuthoritativeResolution: Equatable, Sendable {
    case acknowledged(operationID: UUID)
    case rejected(operationID: UUID, code: Int)

    public var operationID: UUID {
        switch self {
        case .acknowledged(let id), .rejected(let id, _):
            return id
        }
    }
}

@MainActor
public protocol ClubCommunityPendingJournal: AnyObject {
    func record(for target: ClubCommunityPendingTarget) throws -> ClubCommunityPendingRecord?
    func recordBeforeSend(_ record: ClubCommunityPendingRecord) throws
    func markUnknown(target: ClubCommunityPendingTarget, operationID: UUID) throws
    func releaseAfterAuthoritativeOutcome(
        target: ClubCommunityPendingTarget,
        resolution: ClubCommunityAuthoritativeResolution
    ) throws
}

/// Durable journal backed by synchronous key-value storage (such as `UserDefaults` or custom store closures).
/// Verifies every write by immediate readback; any write/readback failure throws `.persistenceFailed`
/// so the caller refuses to dispatch the network write.
@MainActor
public final class ClubCommunityStoredPendingJournal: ClubCommunityPendingJournal {
    private let readBytes: (String) throws -> Data?
    private let writeBytes: (Data?, String) throws -> Void

    public init(
        read: @escaping (String) throws -> Data?,
        write: @escaping (Data?, String) throws -> Void
    ) {
        self.readBytes = read
        self.writeBytes = write
    }

    public convenience init(defaults: UserDefaults) {
        self.init(
            read: { key in
                guard let raw = defaults.object(forKey: key) else { return nil }
                guard let data = raw as? Data else {
                    throw ClubCommunityPendingJournalFailure.corrupt
                }
                return data
            },
            write: { data, key in
                if let data {
                    defaults.set(data, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        )
    }

    public func record(for target: ClubCommunityPendingTarget) throws -> ClubCommunityPendingRecord? {
        let key = target.storageKey
        let raw: Data?
        do {
            raw = try readBytes(key)
        } catch let error as ClubCommunityPendingJournalFailure {
            throw error
        } catch {
            throw ClubCommunityPendingJournalFailure.persistenceFailed
        }
        guard let bytes = raw else { return nil }
        guard bytes.count <= 4096,
              let decoded = try? JSONDecoder().decode(ClubCommunityPendingRecord.self, from: bytes),
              decoded.version == 1,
              decoded.target == target,
              ClubCommunityPendingRecord.allowedOperationKinds.contains(decoded.operationKind) else {
            throw ClubCommunityPendingJournalFailure.corrupt
        }
        return decoded
    }

    public func recordBeforeSend(_ candidate: ClubCommunityPendingRecord) throws {
        guard candidate.version == 1,
              candidate.phase == .sending,
              ClubCommunityPendingRecord.allowedOperationKinds.contains(candidate.operationKind) else {
            throw ClubCommunityPendingJournalFailure.corrupt
        }
        if let existing = try self.record(for: candidate.target) {
            if existing.operationID != candidate.operationID || existing.phase == .unknownLocked {
                throw ClubCommunityPendingJournalFailure.locked
            }
        }
        try persist(candidate)
    }

    public func markUnknown(target: ClubCommunityPendingTarget, operationID: UUID) throws {
        guard let existing = try record(for: target),
              existing.operationID == operationID else {
            throw ClubCommunityPendingJournalFailure.locked
        }
        let updated = try ClubCommunityPendingRecord(
            target: target,
            operationID: operationID,
            operationKind: existing.operationKind,
            phase: .unknownLocked
        )
        try persist(updated)
    }

    public func releaseAfterAuthoritativeOutcome(
        target: ClubCommunityPendingTarget,
        resolution: ClubCommunityAuthoritativeResolution
    ) throws {
        guard let existing = try record(for: target),
              existing.operationID == resolution.operationID else {
            throw ClubCommunityPendingJournalFailure.locked
        }
        let key = target.storageKey
        do {
            try writeBytes(nil, key)
            guard try readBytes(key) == nil else {
                throw ClubCommunityPendingJournalFailure.persistenceFailed
            }
        } catch let error as ClubCommunityPendingJournalFailure {
            throw error
        } catch {
            throw ClubCommunityPendingJournalFailure.persistenceFailed
        }
    }

    private func persist(_ value: ClubCommunityPendingRecord) throws {
        let key = value.target.storageKey
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes: Data
        do {
            bytes = try encoder.encode(value)
            try writeBytes(bytes, key)
            guard try readBytes(key) == bytes else {
                throw ClubCommunityPendingJournalFailure.persistenceFailed
            }
        } catch let error as ClubCommunityPendingJournalFailure {
            throw error
        } catch {
            throw ClubCommunityPendingJournalFailure.persistenceFailed
        }
    }
}

/// Default in-process journal used when a test does not inject shared cross-restart storage.
@MainActor
public final class ClubCommunityInMemoryPendingJournal: ClubCommunityPendingJournal {
    private var storage: [String: Data] = [:]
    private lazy var backing = ClubCommunityStoredPendingJournal(
        read: { [unowned self] key in self.storage[key] },
        write: { [unowned self] data, key in self.storage[key] = data }
    )

    public init() {}

    public func record(for target: ClubCommunityPendingTarget) throws -> ClubCommunityPendingRecord? {
        try backing.record(for: target)
    }

    public func recordBeforeSend(_ record: ClubCommunityPendingRecord) throws {
        try backing.recordBeforeSend(record)
    }

    public func markUnknown(target: ClubCommunityPendingTarget, operationID: UUID) throws {
        try backing.markUnknown(target: target, operationID: operationID)
    }

    public func releaseAfterAuthoritativeOutcome(
        target: ClubCommunityPendingTarget,
        resolution: ClubCommunityAuthoritativeResolution
    ) throws {
        try backing.releaseAfterAuthoritativeOutcome(target: target, resolution: resolution)
    }
}
