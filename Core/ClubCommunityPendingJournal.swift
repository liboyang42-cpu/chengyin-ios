import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    public let requestID: String?
    public let postVersion: Int?

    public init(
        version: Int = 1,
        target: ClubCommunityPendingTarget,
        operationID: UUID,
        operationKind: String,
        phase: Phase,
        requestID: String? = nil,
        postVersion: Int? = nil
    ) throws {
        let normalizedRequestID: String?
        if let rawRequestID = requestID {
            let trimmed = rawRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.utf8.count <= 128 else {
                throw ClubCommunityPendingJournalFailure.corrupt
            }
            normalizedRequestID = trimmed
        } else {
            normalizedRequestID = nil
        }
        if let postVersion {
            guard postVersion >= 0 else {
                throw ClubCommunityPendingJournalFailure.corrupt
            }
        }
        guard version == 1,
              Self.allowedOperationKinds.contains(operationKind) else {
            throw ClubCommunityPendingJournalFailure.corrupt
        }
        self.version = version
        self.target = target
        self.operationID = operationID
        self.operationKind = operationKind
        self.phase = phase
        self.requestID = normalizedRequestID
        self.postVersion = postVersion
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
              ClubCommunityPendingRecord.allowedOperationKinds.contains(decoded.operationKind),
              (decoded.requestID == nil || (!decoded.requestID!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && decoded.requestID!.utf8.count <= 128)),
              (decoded.postVersion == nil || decoded.postVersion! >= 0) else {
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
            phase: .unknownLocked,
            requestID: existing.requestID,
            postVersion: existing.postVersion
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

/// Authoritative same-request query result for a persisted pending operation.
/// Never guesses from list/comment snapshots, title/content matching, or count deltas.
public enum ClubCommunityPendingQueryResult: Equatable, Sendable {
    case stillPending
    case resolved(ClubCommunityAuthoritativeResolution)
}

@MainActor
public protocol ClubCommunityPendingOutcomeQuerying {
    var allowsAuthoritativeQueries: Bool { get }
    func queryOutcome(
        for record: ClubCommunityPendingRecord,
        session: ClubCommunitySession,
        check: () throws -> Void
    ) async throws -> ClubCommunityPendingQueryResult
}

/// Default fail-closed same-request outcome query when no authoritative receipt endpoint is enabled.
public struct ClubCommunityDormantPendingOutcomeQuery: ClubCommunityPendingOutcomeQuerying {
    public init() {}
    public var allowsAuthoritativeQueries: Bool { false }
    public func queryOutcome(
        for record: ClubCommunityPendingRecord,
        session: ClubCommunitySession,
        check: () throws -> Void
    ) async throws -> ClubCommunityPendingQueryResult {
        throw ClubCommunityFailure.unavailable
    }
}

/// Same-request authoritative outcome query adapter over `POST api/club/post/operation/receipt`.
/// Verifies exact `operationID`, `requestID` (when recorded), `clubID`, `postID`, and `commentID`.
public struct ClubCommunityHTTPPendingOutcomeQuery: ClubCommunityPendingOutcomeQuerying {
    private let baseURL: URL
    private let transport: any HTTPTransport
    public let allowsAuthoritativeQueries: Bool

    public init(baseURL: URL, transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
        self.allowsAuthoritativeQueries = false
    }

    public init(dormantBaseURL: URL, transport: any HTTPTransport, enabled: Bool = false) {
        self.baseURL = dormantBaseURL
        self.transport = transport
        self.allowsAuthoritativeQueries = enabled
    }

    public init(offlineBaseURL: URL, transport: any ClubCommunityOfflineTransport) {
        self.baseURL = offlineBaseURL
        self.transport = transport
        self.allowsAuthoritativeQueries = true
    }

    public func queryOutcome(
        for record: ClubCommunityPendingRecord,
        session: ClubCommunitySession,
        check: () throws -> Void
    ) async throws -> ClubCommunityPendingQueryResult {
        guard allowsAuthoritativeQueries else { throw ClubCommunityFailure.unavailable }
        guard session.identity.isSignedIn,
              session.identity.accountID == record.target.accountID else {
            throw ClubCommunityFailure.stale
        }
        guard baseURL.scheme == "https",
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil else {
            throw ClubCommunityFailure.invalid
        }
        let canonicalRequestID = record.requestID ?? record.operationID.uuidString
        var fields: [String: Any] = [
            "clubId": record.target.clubID,
            "postId": record.target.postID,
            "commentId": record.target.commentID,
            "operationId": record.operationID.uuidString,
            "operationKind": record.operationKind,
            "requestId": canonicalRequestID
        ]
        if let postVersion = record.postVersion {
            fields["version"] = postVersion
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/club/post/operation/receipt"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = session.token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])

        try check()
        let (data, status) = try await transport.send(request)
        try check()

        let rawPayload = try ClubCommunityService.decode(data, status: status)
        guard let payload = rawPayload as? [String: Any],
              let returnedOperationIDRaw = payload["operationId"] as? String,
              let returnedOperationID = UUID(uuidString: returnedOperationIDRaw),
              returnedOperationID == record.operationID else {
            throw ClubCommunityFailure.invalid
        }
        let returnedClubID = (payload["clubId"] as? Int) ?? record.target.clubID
        let returnedPostID = (payload["postId"] as? Int) ?? record.target.postID
        let returnedCommentID = (payload["commentId"] as? Int) ?? record.target.commentID
        guard returnedClubID == record.target.clubID,
              returnedPostID == record.target.postID,
              returnedCommentID == record.target.commentID else {
            throw ClubCommunityFailure.stale
        }
        if let returnedRequestID = payload["requestId"] as? String {
            guard returnedRequestID == canonicalRequestID else {
                throw ClubCommunityFailure.stale
            }
        } else if record.requestID != nil {
            throw ClubCommunityFailure.stale
        }
        guard let statusText = (payload["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            throw ClubCommunityFailure.invalid
        }
        switch statusText {
        case "PENDING":
            return .stillPending
        case "ACKNOWLEDGED":
            return .resolved(.acknowledged(operationID: record.operationID))
        case "REJECTED":
            guard let rejectedCode = payload["rejectedCode"] as? Int, rejectedCode > 0 else {
                throw ClubCommunityFailure.invalid
            }
            return .resolved(.rejected(operationID: record.operationID, code: rejectedCode))
        default:
            throw ClubCommunityFailure.invalid
        }
    }
}
