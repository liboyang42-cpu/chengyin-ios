import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProfileFavoriteRemovalSession: Equatable {
    public let identity: SocialAccountIdentity
    public let namespace: String
    public let collectionScope: UUID
    public let market: RegionalMarket
    fileprivate let token: String
    public init(identity: SocialAccountIdentity, namespace: String, collectionScope: UUID, market: RegionalMarket, token: String) throws {
        guard let id = identity.accountID, id > 0, !namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.identity = identity; self.namespace = namespace; self.collectionScope = collectionScope; self.market = market; self.token = token
    }
}
/// An exact operation grant, never a consequence of having a read service or another social grant.
public struct ProfileFavoriteRemovalApproval: Equatable {
    public static let paths: Set<String> = ["api/creativesquare/info", "api/creativesquare/bookmark"]
    public let endpoint: OperationEndpointApproval
    public let identity: SocialAccountIdentity
    public let postID: Int
    public let expiresAt: Date
    public init(endpoint: OperationEndpointApproval, identity: SocialAccountIdentity, postID: Int, expiresAt: Date) throws {
        guard endpoint.paths == Self.paths, endpoint.accountID == identity.accountID, postID > 0,
              expiresAt.timeIntervalSince1970.isFinite else { throw APIError.invalidConfiguration }
        self.endpoint = endpoint; self.identity = identity; self.postID = postID; self.expiresAt = expiresAt
    }
}
public enum ProfileFavoriteRemovalFailure: Error { case disabled, stale, response, pending }
fileprivate struct ProfileFavoriteRemovalIntent: Equatable {
    let id: UUID
    let postID: Int
    let session: ProfileFavoriteRemovalSession
}
public struct ProfileFavoriteRemovalReview: Equatable, Identifiable {
    public let id = UUID()
    public let postID: Int
    fileprivate let intent: ProfileFavoriteRemovalIntent
    fileprivate init(_ intent: ProfileFavoriteRemovalIntent) { self.intent = intent; postID = intent.postID }
}

/// Shared only by controllers owned by the same app session. If local cleanup
/// cannot be verified after a known remote result, retirement/replacement must
/// not lose the target while its durable storage is temporarily unreadable.
@MainActor @Observable public final class ProfileFavoriteRemovalPendingState {
    private var retained: [String: OperationPendingRecord] = [:]
    public init() {}
    private func key(_ owner: String, _ target: String) -> String { "\(owner.utf8.count):\(owner)\(target)" }
    func pending(owner: String, target: String) -> OperationPendingRecord? { retained[key(owner, target)] }
    func hold(_ record: OperationPendingRecord) { retained[key(record.ownerKey, record.targetKey)] = record }
    func clear(owner: String, target: String) { retained[key(owner, target)] = nil }
}

/// All transport is injected. Empty approvals keep every production action disabled.
/// Unknown writes retain a durable lock across view dismissal and reauthentication.
@MainActor @Observable public final class ProfileFavoriteRemovalController {
    public enum Phase: Equatable { case idle, loading, reviewed, working, removed, failed, unknown }
    public enum RecoveryAvailability: Equatable { case unavailable, unreadable, pending([Int]) }
    public private(set) var phase: Phase = .idle
    public private(set) var review: ProfileFavoriteRemovalReview?
    public var presentationID: UUID? { intent?.id }
    public var postID: Int? { intent?.postID }
    public var isBusy: Bool { phase == .loading || phase == .working }
    private var intent: ProfileFavoriteRemovalIntent?
    private var journalRevision: UInt64 = 0
    private let configuration: APIConfiguration
    private let approvals: [ProfileFavoriteRemovalApproval]
    private let transport: any HTTPTransport
    private let journal: any OperationPendingJournal
    private let pendingState: ProfileFavoriteRemovalPendingState
    private let current: () -> ProfileFavoriteRemovalSession?
    private let onUnauthorized: () -> Void
    private let now: () -> Date
    public init(configuration: APIConfiguration, approvals: [ProfileFavoriteRemovalApproval] = [],
                transport: any HTTPTransport, journal: any OperationPendingJournal,
                current: @escaping () -> ProfileFavoriteRemovalSession?,
                onUnauthorized: @escaping () -> Void = {}, pendingState: ProfileFavoriteRemovalPendingState? = nil,
                now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.approvals = approvals; self.transport = transport
        self.journal = journal; self.current = current; self.onUnauthorized = onUnauthorized; self.now = now
        self.pendingState = pendingState ?? ProfileFavoriteRemovalPendingState()
    }
    private func approved(_ postID: Int, session: ProfileFavoriteRemovalSession) -> Bool {
        session.market == .china && approvals.filter {
            $0.postID == postID && $0.identity == session.identity && now() < $0.expiresAt &&
            $0.endpoint.allows(configuration: configuration, namespace: session.namespace,
                accountID: session.identity.accountID ?? 0, path: "api/creativesquare/bookmark")
        }.count == 1
    }
    public func isAvailable(post: SquarePost, collectionScope: UUID) -> Bool {
        post.generation == .legacySquare && isAvailable(postID: post.id, collectionScope: collectionScope)
    }
    public func isAvailable(postID: Int, collectionScope: UUID) -> Bool {
        guard let session = current(), session.collectionScope == collectionScope else { return false }
        return approved(postID, session: session)
    }
    /// A removed post may already be absent from the saved list. Recover only exact
    /// currently approved targets whose durable records exist; never infer from rows.
    public func recoveryAvailability(collectionScope: UUID) -> RecoveryAvailability {
        _ = journalRevision // Register observation even when there are currently no pending rows.
        guard let session = current(), session.collectionScope == collectionScope else { return .unavailable }
        do {
            let ids = Set(approvals.map(\.postID)).sorted().filter { approved($0, session: session) }
            let pendingIDs = try ids.filter { id in
                try pending(.init(id: UUID(), postID: id, session: session)) != nil
            }
            guard current() == session else { return .unavailable }
            return .pending(pendingIDs)
        } catch { return .unreadable }
    }
    /// Opens the existing uncertain command for a read-only check, without creating
    /// a review or command ID and without depending on a still-visible saved row.
    public func beginRecovery(postID: Int, collectionScope: UUID) -> UUID? {
        guard !isBusy, let session = current(), session.collectionScope == collectionScope,
              approved(postID, session: session) else { return nil }
        let next = ProfileFavoriteRemovalIntent(id: UUID(), postID: postID, session: session)
        guard (try? pending(next)) != nil, current() == session else { return nil }
        intent = next; review = nil; phase = .unknown
        return next.id
    }
    public func begin(post: SquarePost, collectionScope: UUID) -> UUID? {
        guard !isBusy, isAvailable(post: post, collectionScope: collectionScope), let session = current(),
              session.collectionScope == collectionScope, approved(post.id, session: session) else { return nil }
        let next = ProfileFavoriteRemovalIntent(id: UUID(), postID: post.id, session: session)
        intent = next; review = nil; phase = .loading; return next.id
    }
    public func retire(_ id: UUID) {
        guard intent?.id == id else { return }; intent = nil; review = nil; phase = .idle
    }
    private func fence(_ value: ProfileFavoriteRemovalIntent) throws {
        try Task.checkCancellation()
        guard intent == value, current() == value.session, approved(value.postID, session: value.session) else { throw ProfileFavoriteRemovalFailure.stale }
    }
    private func owner(_ value: ProfileFavoriteRemovalIntent) -> String {
        // Session epoch/token deliberately excluded from the durable unresolved-write owner.
        let parts = ["profile-favorite-removal-v1", configuration.baseURL.absoluteString, value.session.namespace,
                     String(value.session.identity.accountID ?? 0)]
        return parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
    private func target(_ value: ProfileFavoriteRemovalIntent) -> String { "legacy-saved-post|\(value.postID)" }
    private func pending(_ value: ProfileFavoriteRemovalIntent) throws -> OperationPendingRecord? {
        let durable = try journal.pending(ownerKey: owner(value), targetKey: target(value))
        return durable ?? pendingState.pending(owner: owner(value), target: target(value))
    }
    private func request(_ path: String, fields: [String: String], intent value: ProfileFavoriteRemovalIntent) throws -> URLRequest {
        try fence(value)
        guard ProfileFavoriteRemovalApproval.paths.contains(path) else { throw ProfileFavoriteRemovalFailure.disabled }
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: value.session.token)
    }
    private func envelope(_ data: Data, status: Int) throws -> SocialValue {
        let value = try? JSONDecoder().decode(SocialValue.self, from: data)
        if status == 401 || value?["code"].integer == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status), let value, value["code"].integer == 200 else {
            throw ProfileFavoriteRemovalFailure.response
        }
        return value
    }
    private func expireIfCurrent(_ error: Error, intent value: ProfileFavoriteRemovalIntent) {
        guard error as? APIError == .unauthorized, intent == value, current() == value.session else { return }
        onUnauthorized()
    }
    /// Exact current target state, not absence from a truncated saved-items page.
    private func bookmarked(_ value: ProfileFavoriteRemovalIntent) async throws -> Bool {
        let request = try request("api/creativesquare/info", fields: ["id": String(value.postID)], intent: value)
        let (data, status) = try await transport.send(request)
        try fence(value)
        let row = try envelope(data, status: status)["data"]
        guard row["id"].integer == value.postID, let marked = row["isBookmarked"].integer, marked == 0 || marked == 1 else {
            throw ProfileFavoriteRemovalFailure.response
        }
        return marked == 1
    }
    /// The remote target is already verified unbookmarked. A throwing clear can
    /// still have deleted its local row; a successful nil reread proves cleanup.
    /// Otherwise quarantine it locally and retain any durable row, without ever
    /// rewriting a record that a newer presentation may have resolved.
    private func clearResolved(_ record: OperationPendingRecord) throws {
        defer { journalRevision &+= 1 }
        pendingState.hold(record)
        do { try journal.clear(record) } catch { /* Inspect the actual local result below. */ }
        guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else {
            throw ProfileFavoriteRemovalFailure.pending
        }
        pendingState.clear(owner: record.ownerKey, target: record.targetKey)
    }
    public func prepare(_ id: UUID) async {
        guard let value = intent, value.id == id, phase == .loading else { return }
        do {
            try fence(value)
            if try pending(value) != nil { phase = .unknown; return }
            let marked = try await bookmarked(value); try fence(value)
            if marked { review = .init(value); phase = .reviewed }
            else { phase = .removed }
        } catch {
            expireIfCurrent(error, intent: value)
            if intent == value { phase = .failed }
        }
    }
    public func retryPreparation(_ id: UUID) async {
        guard intent?.id == id, phase == .failed else { return }
        phase = .loading; await prepare(id)
    }
    public func confirm(_ proposed: ProfileFavoriteRemovalReview) async {
        guard review == proposed, intent == proposed.intent, phase == .reviewed else { return }
        let value = proposed.intent
        phase = .working; review = nil // Consume before the first suspension.
        var record: OperationPendingRecord?
        var dispatched = false
        do {
            try fence(value)
            guard try pending(value) == nil else { throw ProfileFavoriteRemovalFailure.pending }
            let marked = try await bookmarked(value); try fence(value)
            if !marked { phase = .removed; return }
            guard try pending(value) == nil else { throw ProfileFavoriteRemovalFailure.pending }
            let prepared = OperationPendingRecord(ownerKey: owner(value), targetKey: target(value))
            let write = try request("api/creativesquare/bookmark", fields: ["id": String(value.postID), "bookmark": "0", "request_id": proposed.id.uuidString], intent: value)
            try journal.write(prepared); record = prepared; journalRevision &+= 1
            try fence(value)
            dispatched = true
            let (data, status) = try await transport.send(write)
            try fence(value); _ = try envelope(data, status: status)
            let stillMarked = try await bookmarked(value)
            guard !stillMarked else { throw ProfileFavoriteRemovalFailure.pending }
            try fence(value)
            try clearResolved(prepared)
            phase = .removed
        } catch {
            if !dispatched, let record {
                defer { journalRevision &+= 1 }
                do { try journal.clear(record) }
                catch { if intent == value { phase = .unknown }; return }
            }
            expireIfCurrent(error, intent: value)
            if intent == value { phase = dispatched ? .unknown : .failed }
        }
    }
    /// A pending write can be observed, never automatically submitted a second time.
    public func reconcile(_ id: UUID) async {
        guard let value = intent, value.id == id, phase == .unknown else { return }
        phase = .working
        do {
            try fence(value)
            guard let record = try pending(value) else { throw ProfileFavoriteRemovalFailure.pending }
            let stillMarked = try await bookmarked(value)
            guard !stillMarked else { throw ProfileFavoriteRemovalFailure.pending }
            try fence(value); try clearResolved(record); phase = .removed
        } catch {
            expireIfCurrent(error, intent: value)
            if intent == value { phase = .unknown }
        }
    }
}
