import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only canned, non-network test transports should implement this marker.
public protocol ClubCommunityOfflineTransport: HTTPTransport {}
/// Explicit composition-root grant; never supplied by shipped construction or UI state.
public enum ClubCommunityMutationGrant: Equatable { case disabled, reviewedInjection }
public struct ClubCommunityService {
    private let baseURL: URL
    private let transport: any HTTPTransport
    public let allowsInjectedWrites: Bool
    public init(baseURL: URL, transport: any HTTPTransport) {
        self.baseURL = baseURL; self.transport = transport; allowsInjectedWrites = false
    }
    /// Concrete dormant HTTP adapter: any injected HTTPTransport can execute exact writes
    /// only after a separately supplied composition-root grant. Default remains OFF.
    public init(dormantBaseURL: URL, transport: any HTTPTransport, grant: ClubCommunityMutationGrant = .disabled) {
        baseURL = dormantBaseURL; self.transport = transport; allowsInjectedWrites = grant == .reviewedInjection
    }
    public init(offlineBaseURL: URL, transport: any ClubCommunityOfflineTransport) {
        baseURL = offlineBaseURL; self.transport = transport; allowsInjectedWrites = true
    }
    func request(suffix: String, fields: [String: Any], session: ClubCommunitySession) throws -> URLRequest {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil else { throw ClubCommunityFailure.invalid }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/club/post/" + suffix))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = session.token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return request
    }
    public func read(_ operation: ClubCommunityRead, session: ClubCommunitySession, check: () throws -> Void) async throws -> ClubCommunitySnapshot {
        guard operation.fields.values.allSatisfy({ (($0 as? Int) ?? 0) > 0 }) else { throw ClubCommunityFailure.invalid }
        if case .feed = operation, !session.identity.isSignedIn { throw ClubCommunityFailure.forbidden }
        if case let .posts(clubID, beforeID, limit) = operation {
            guard clubID > 0, (1...50).contains(limit), beforeID.map({ $0 > 0 }) ?? true else { throw ClubCommunityFailure.invalid }
        }
        if case let .feed(limit) = operation, !(1...50).contains(limit) { throw ClubCommunityFailure.invalid }
        // c6 returns the full visible list; page > 1 cannot identify a continuation.
        if case let .comments(_, page) = operation, page != 1 { throw ClubCommunityFailure.invalid }
        let request = try request(suffix: operation.suffix, fields: operation.fields, session: session)
        try check(); let (data, status) = try await transport.send(request); try check()
        let value = try Self.decode(data, status: status)
        switch operation {
        case let .posts(clubID, beforeID, limit):
            let page = try ClubCommunityPostPage(clubID: clubID, beforeID: beforeID, limit: limit, rows: CCWire.rows(value))
            return try page.snapshot()
        case .feed:
            guard let object = value as? [String: Any], let count = object["clubCount"] as? Int else { throw ClubCommunityFailure.invalid }
            guard count >= 0 else { throw ClubCommunityFailure.invalid }
            let items = try CCWire.rows(object).map { try ClubCommunityFeedItem(row: $0, clubID: nil) }
            guard Set(items.map(\.id)).count == items.count else { throw ClubCommunityFailure.invalid }
            return try ClubCommunityPostPage.snapshot(items: items, page: nil, clubCount: count)
        case let .comments(postID, _):
            let comments = try CCWire.rows(value).map(ClubCommunityComment.init)
            guard comments.allSatisfy({ $0.postID == nil || $0.postID == postID }) else { throw ClubCommunityFailure.stale }
            return .init(posts: [], comments: comments, history: [], clubCount: nil)
        case .history:
            guard let rows = value as? [[String: Any]] else { throw ClubCommunityFailure.invalid }
            return .init(posts: [], comments: [], history: try rows.map(ClubCommunityRevision.init), clubCount: nil)
        }
    }
    static func decode(_ data: Data, status: Int) throws -> Any {
        guard (200..<300).contains(status), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = object["code"] as? Int else { throw ClubCommunityFailure.invalid }
        guard code == 200 else { throw ClubCommunityFailure.rejected(code) }
        return object["data"] ?? NSNull()
    }
    func submit(_ review: ClubCommunityReview, session: ClubCommunitySession, check: () throws -> Void) async throws {
        guard allowsInjectedWrites else { throw ClubCommunityFailure.unavailable }
        guard session.identity == review.evidence.identity else { throw ClubCommunityFailure.stale }
        let request = try request(suffix: review.operation.suffix, fields: review.fields(), session: session)
        try Task.checkCancellation(); try check()
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) } catch { throw ClubCommunityFailure.unknown }
        do { try Task.checkCancellation(); try check() } catch { throw ClubCommunityFailure.unknown }
        do { _ = try Self.decode(data, status: status) }
        catch let error as ClubCommunityFailure {
            if case .rejected = error { throw error }; throw ClubCommunityFailure.unknown
        } catch { throw ClubCommunityFailure.unknown }
    }
}

public enum ClubCommunityOutcome: Equatable { case idle, reviewing, sending, acknowledgedRefreshRequired, moderationQueued, rejected, unknownLocked }
@MainActor
public final class ClubCommunityCoordinator {
    private let service: ClubCommunityService
    private let currentSession: () throws -> ClubCommunitySession
    private let refreshEvidence: (ClubCommunityEvidence) async throws -> ClubCommunityEvidence
    private let journal: any ClubCommunityPendingJournal
    private let namespace: () -> String
    private let outcomeQuery: any ClubCommunityPendingOutcomeQuerying
    private let resolveOriginalPublication: () -> ClubPostOriginalService?
    private var originalPublication: ClubPostOriginalService? { resolveOriginalPublication() }
    private let resolveOriginalComment: () -> ClubCommentOriginalService?
    private var originalComment: ClubCommentOriginalService? { resolveOriginalComment() }
    private var reviewUsesOriginalPublication = false
    private var locks: Set<String> = []
    private var consumed: Set<UUID> = []
    private var generation: UInt64 = 0
    public private(set) var review: ClubCommunityReview?
    public private(set) var outcome: ClubCommunityOutcome = .idle
    public var permitsInjectedWrites: Bool { service.allowsInjectedWrites || originalPublication?.allowsWrites == true || originalComment?.allowsWrites == true }
    private func usesOriginal(_ operation: ClubCommunityOperation) -> Bool {
        switch operation {
        case .create, .update: return originalPublication?.allowsWrites == true
        case .comment: return originalComment?.allowsWrites == true
        default: return false
        }
    }
    public var permitsAuthoritativeOutcomeQueries: Bool { outcomeQuery.allowsAuthoritativeQueries || originalPublication?.allowsAuthoritativeQueries == true || originalComment?.allowsAuthoritativeQueries == true }
    public init(
        service: ClubCommunityService,
        currentSession: @escaping () throws -> ClubCommunitySession,
        refreshEvidence: @escaping (ClubCommunityEvidence) async throws -> ClubCommunityEvidence,
        journal: (any ClubCommunityPendingJournal)? = nil,
        namespace: @escaping () -> String = { "default" },
        outcomeQuery: (any ClubCommunityPendingOutcomeQuerying)? = nil,
        originalPublication: ClubPostOriginalService? = nil,
        originalPublicationResolver: (() -> ClubPostOriginalService?)? = nil,
        originalComment: ClubCommentOriginalService? = nil,
        originalCommentResolver: (() -> ClubCommentOriginalService?)? = nil
    ) {
        self.service = service
        self.currentSession = currentSession
        self.refreshEvidence = refreshEvidence
        self.journal = journal ?? ClubCommunityInMemoryPendingJournal()
        self.namespace = namespace
        self.outcomeQuery = outcomeQuery ?? ClubCommunityDormantPendingOutcomeQuery()
        self.resolveOriginalPublication = originalPublicationResolver ?? { originalPublication }
        self.resolveOriginalComment = originalCommentResolver ?? { originalComment }
    }
    private func lockKey(for evidence: ClubCommunityEvidence) -> String {
        "\(evidence.identity.accountID ?? 0):\(evidence.clubID):\(evidence.post?.id ?? 0):\(evidence.comment?.id ?? 0)"
    }
    private func pendingTarget(for evidence: ClubCommunityEvidence) throws -> ClubCommunityPendingTarget {
        try ClubCommunityPendingTarget(evidence: evidence, namespace: namespace())
    }
    public func pendingRecord(for evidence: ClubCommunityEvidence) -> ClubCommunityPendingRecord? {
        guard recoverPendingLock(for: evidence),
              let target = try? pendingTarget(for: evidence) else { return nil }
        return try? journal.record(for: target)
    }
    /// Recovers any unresolved `sending` or `unknownLocked` journal record across restarts.
    /// Never pretends the operation succeeded or disambiguates by list/content guessing.
    @discardableResult
    public func recoverPendingLock(for evidence: ClubCommunityEvidence) -> Bool {
        let key = lockKey(for: evidence)
        if locks.contains(key) { return true }
        do {
            let target = try pendingTarget(for: evidence)
            if let existing = try journal.record(for: target) {
                locks.insert(key)
                if existing.phase == .sending {
                    try? journal.markUnknown(target: target, operationID: existing.operationID)
                }
                outcome = .unknownLocked
                return true
            }
            return false
        } catch {
            locks.insert(key)
            outcome = .unknownLocked
            return true
        }
    }
    /// Releases a recovered lock ONLY when an explicit authoritative resolution matching the exact
    /// persisted `operationID` is supplied (never from post/comment list reads or content matching).
    public func resolvePendingLock(
        for evidence: ClubCommunityEvidence,
        resolution: ClubCommunityAuthoritativeResolution
    ) throws {
        let target = try pendingTarget(for: evidence)
        let existing = try journal.record(for: target)
        try journal.releaseAfterAuthoritativeOutcome(target: target, resolution: resolution)
        locks.remove(lockKey(for: evidence))
        switch resolution {
        case .acknowledged:
            if existing?.operationKind == "report" || existing?.operationKind == "reportComment" {
                outcome = .moderationQueued
            } else {
                outcome = .acknowledgedRefreshRequired
            }
        case .rejected:
            outcome = .rejected
        }
    }
    /// Queries the authoritative same-request outcome for an unresolved pending operation on `evidence`.
    /// Never generates a new request ID, never re-submits the write, and never infers success from list reads.
    @discardableResult
    public func reconcilePendingOperation(for evidence: ClubCommunityEvidence) async throws -> ClubCommunityOutcome {
        let target: ClubCommunityPendingTarget
        let existing: ClubCommunityPendingRecord
        do {
            target = try pendingTarget(for: evidence)
            guard let record = try journal.record(for: target) else {
                throw ClubCommunityFailure.invalid
            }
            if record.phase == .sending {
                try journal.markUnknown(target: target, operationID: record.operationID)
                existing = try journal.record(for: target) ?? record
            } else {
                existing = record
            }
        } catch let error as ClubCommunityFailure {
            throw error
        } catch {
            locks.insert(lockKey(for: evidence))
            outcome = .unknownLocked
            throw ClubCommunityFailure.locked
        }
        locks.insert(lockKey(for: evidence))
        outcome = .unknownLocked
        // Historical edit/pin records did not retain the separately transmitted key.
        // Their local review UUID is not evidence of the server's original request ID.
        if ["edit", "pin"].contains(existing.operationKind), existing.requestID == nil {
            throw ClubCommunityFailure.locked
        }
        let session = try currentSession()
        guard session.identity.isSignedIn,
              session.identity.accountID == existing.target.accountID else {
            throw ClubCommunityFailure.stale
        }
        let ticket = generation
        func checkRecoveryContext() throws {
            try Task.checkCancellation()
            guard generation == ticket, try currentSession() == session,
                  try pendingTarget(for: evidence) == target else { throw ClubCommunityFailure.stale }
        }
        try checkRecoveryContext()
        let queryResult: ClubCommunityPendingQueryResult
        if existing.receiptNamespace == ClubCommentOriginalIdentity.namespace, existing.operationKind == "comment" {
            guard let originalComment else { throw ClubCommunityFailure.unavailable }
            queryResult = try await originalComment.queryOutcome(for: existing, session: session, check: checkRecoveryContext)
        } else if existing.receiptNamespace == ClubPostOriginalIdentity.namespace {
            guard let originalPublication else { throw ClubCommunityFailure.unavailable }
            queryResult = try await originalPublication.queryOutcome(for: existing, session: session, check: checkRecoveryContext)
        } else {
            queryResult = try await outcomeQuery.queryOutcome(for: existing, session: session, check: checkRecoveryContext)
        }
        // An adapter's final check cannot cover the coordinator's later actor resumption.
        // A cancelled/retired visit or changed account/deployment must not release its old lock.
        try checkRecoveryContext()
        guard try journal.record(for: target) == existing else { throw ClubCommunityFailure.locked }
        switch queryResult {
        case .stillPending:
            locks.insert(lockKey(for: evidence))
            outcome = .unknownLocked
            return .unknownLocked
        case .resolved(let resolution):
            guard resolution.operationID == existing.operationID else {
                throw ClubCommunityFailure.locked
            }
            do {
                try resolvePendingLock(for: evidence, resolution: resolution)
                return outcome
            } catch {
                locks.insert(lockKey(for: evidence))
                outcome = .unknownLocked
                throw ClubCommunityFailure.locked
            }
        }
    }
    public func prepare(_ operation: ClubCommunityOperation, evidence: ClubCommunityEvidence) async throws -> ClubCommunityReview {
        try Task.checkCancellation()
        guard service.allowsInjectedWrites || usesOriginal(operation) else { throw ClubCommunityFailure.unavailable }
        guard !recoverPendingLock(for: evidence) else { throw ClubCommunityFailure.locked }
        generation &+= 1; let ticket = generation
        let session = try currentSession()
        guard session.identity == evidence.identity else { throw ClubCommunityFailure.stale }
        let fresh = try await refreshEvidence(evidence)
        try Task.checkCancellation()
        guard ticket == generation, try currentSession() == session, fresh.identity == session.identity, fresh.clubID == evidence.clubID,
              fresh.post == evidence.post, fresh.comment == evidence.comment,
              Date().timeIntervalSince(fresh.observedAt) >= 0, Date().timeIntervalSince(fresh.observedAt) < 60 else { throw ClubCommunityFailure.stale }
        let result = try ClubCommunityReview(operation: operation, evidence: fresh)
        guard !recoverPendingLock(for: fresh), !locks.contains(result.lockKey) else { throw ClubCommunityFailure.locked }
        let original = usesOriginal(operation)
        guard service.allowsInjectedWrites || original else { throw ClubCommunityFailure.unavailable }
        if original, case .comment = operation { try ClubCommentOriginalService.validateContent(operation) }
        reviewUsesOriginalPublication = original
        review = result; outcome = .reviewing; return result
    }
    public func cancel() { generation &+= 1; review = nil; if outcome == .reviewing { outcome = .idle } }
    public func confirm(_ candidate: ClubCommunityReview) async throws {
        try Task.checkCancellation()
        guard candidate == review, !consumed.contains(candidate.id),
              !recoverPendingLock(for: candidate.evidence), !locks.contains(candidate.lockKey) else { throw ClubCommunityFailure.locked }
        let session = try currentSession()
        guard session.identity == candidate.evidence.identity else { throw ClubCommunityFailure.stale }
        let fresh = try await refreshEvidence(candidate.evidence)
        try Task.checkCancellation()
        guard candidate == review, !consumed.contains(candidate.id), try currentSession() == session, fresh.identity == candidate.evidence.identity,
              fresh.clubID == candidate.evidence.clubID, fresh.post == candidate.evidence.post, fresh.comment == candidate.evidence.comment,
              fresh.joined == candidate.evidence.joined, fresh.owner == candidate.evidence.owner, fresh.administrator == candidate.evidence.administrator,
              Date().timeIntervalSince(fresh.observedAt) >= 0, Date().timeIntervalSince(fresh.observedAt) < 60,
              fresh.allows(candidate.operation) else { throw ClubCommunityFailure.stale }
        guard !recoverPendingLock(for: fresh), !locks.contains(candidate.lockKey) else { throw ClubCommunityFailure.locked }
        let capturedOriginalPublication = originalPublication
        let capturedOriginalComment = originalComment
        let original: Bool
        switch candidate.operation {
        case .create, .update: original = capturedOriginalPublication?.allowsWrites == true
        case .comment: original = capturedOriginalComment?.allowsWrites == true
        default: original = false
        }
        guard original == reviewUsesOriginalPublication, service.allowsInjectedWrites || original else {
            throw ClubCommunityFailure.unavailable
        }
        if original, case .comment = candidate.operation { try ClubCommentOriginalService.validateContent(candidate.operation) }
        let target: ClubCommunityPendingTarget
        let pendingRecord: ClubCommunityPendingRecord
        do {
            target = try pendingTarget(for: fresh)
            pendingRecord = try ClubCommunityPendingRecord(
                target: target,
                operationID: candidate.id,
                operationKind: candidate.operation.labelKey,
                phase: .sending,
                requestID: (try candidate.fields()["requestId"] as? String) ?? (original ? candidate.id.uuidString : nil),
                postVersion: fresh.post?.version ?? (original ? 0 : nil),
                receiptNamespace: original ? ClubPostOriginalIdentity.namespace : nil
            )
            if original {
                if case .comment = candidate.operation { _ = try ClubCommentOriginalIdentity(pendingRecord) }
                else { _ = try ClubPostOriginalIdentity(pendingRecord) }
            }
            try journal.recordBeforeSend(pendingRecord)
        } catch ClubCommunityPendingJournalFailure.locked {
            locks.insert(candidate.lockKey)
            outcome = .unknownLocked
            throw ClubCommunityFailure.locked
        } catch {
            // Fail-closed: if minimal operation identity cannot be durably persisted, never send.
            throw ClubCommunityFailure.unavailable
        }
        consumed.insert(candidate.id); locks.insert(candidate.lockKey); outcome = .sending; review = nil
        do {
            func checkSubmission() throws {
                guard try self.currentSession() == session else { throw ClubCommunityFailure.stale }
            }
            if original, case .comment = candidate.operation, let capturedOriginalComment {
                try await capturedOriginalComment.submit(candidate, record: pendingRecord, session: session, check: checkSubmission)
            } else if original, let capturedOriginalPublication {
                try await capturedOriginalPublication.submit(candidate, record: pendingRecord, session: session, check: checkSubmission)
            } else {
                try await service.submit(candidate, session: session, check: checkSubmission)
            }
            try Task.checkCancellation()
            do {
                try journal.releaseAfterAuthoritativeOutcome(
                    target: target,
                    resolution: .acknowledged(operationID: candidate.id)
                )
                locks.remove(candidate.lockKey)
                switch candidate.operation { case .report, .reportComment: outcome = .moderationQueued; default: outcome = .acknowledgedRefreshRequired }
            } catch {
                outcome = .unknownLocked
                throw ClubCommunityFailure.unknown
            }
        } catch let error as ClubCommunityFailure {
            if case let .rejected(code) = error {
                try? journal.releaseAfterAuthoritativeOutcome(
                    target: target,
                    resolution: .rejected(operationID: candidate.id, code: code)
                )
                locks.remove(candidate.lockKey); outcome = .rejected
            } else if error == .unavailable || error == .stale {
                try? journal.releaseAfterAuthoritativeOutcome(
                    target: target,
                    resolution: .rejected(operationID: candidate.id, code: 0)
                )
                locks.remove(candidate.lockKey); outcome = .rejected
            } else {
                try? journal.markUnknown(target: target, operationID: candidate.id)
                outcome = .unknownLocked
            }
            throw error
        } catch {
            try? journal.markUnknown(target: target, operationID: candidate.id)
            outcome = .unknownLocked
            throw ClubCommunityFailure.unknown
        }
    }
    /// No reset/retry API: unknown legacy writes cannot be reconciled by guessed receipts,
    /// title matching, a changed count, a new epoch, or new request IDs.
    public func isLocked(_ evidence: ClubCommunityEvidence) -> Bool {
        recoverPendingLock(for: evidence)
    }
}

public protocol ClubCommunityImageUploading {
    var enabled: Bool { get }
    func uploadSynthetic(_ bytes: [Data]) async throws -> [String]
}
public struct ClubCommunityDisabledImages: ClubCommunityImageUploading {
    public init() {}
    public var enabled: Bool { false }
    public func uploadSynthetic(_ bytes: [Data]) async throws -> [String] { throw ClubCommunityFailure.unavailable }
}
/// Fixture-only seam. Never contains HTTP, OS permissions, camera or photo-library access.
public struct ClubCommunitySyntheticImages: ClubCommunityImageUploading {
    public init() {}
    public var enabled: Bool { true }
    public func uploadSynthetic(_ bytes: [Data]) async throws -> [String] {
        guard (1...9).contains(bytes.count), bytes.allSatisfy({ !$0.isEmpty }) else { throw ClubCommunityFailure.invalid }
        return bytes.indices.map { "https://fixture.invalid/club-image-\($0).jpg" }
    }
}
