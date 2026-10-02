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
        let request = try request(suffix: operation.suffix, fields: operation.fields, session: session)
        try check(); let (data, status) = try await transport.send(request); try check()
        let value = try Self.decode(data, status: status)
        switch operation {
        case let .posts(clubID, _):
            let posts = try CCWire.rows(value).map(ClubCommunityPost.init)
            guard posts.allSatisfy({ $0.clubID == nil || $0.clubID == clubID }) else { throw ClubCommunityFailure.stale }
            return .init(posts: posts.filter(\.hasContent), comments: [], history: [], clubCount: nil)
        case .feed:
            guard let object = value as? [String: Any], let count = object["clubCount"] as? Int else { throw ClubCommunityFailure.invalid }
            return .init(posts: try CCWire.rows(object).map(ClubCommunityPost.init).filter(\.hasContent), comments: [], history: [], clubCount: count)
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
        try check()
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) } catch { throw ClubCommunityFailure.unknown }
        do { try check() } catch { throw ClubCommunityFailure.unknown }
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
    private var locks: Set<String> = []
    private var consumed: Set<UUID> = []
    private var generation: UInt64 = 0
    public private(set) var review: ClubCommunityReview?
    public private(set) var outcome: ClubCommunityOutcome = .idle
    public var permitsInjectedWrites: Bool { service.allowsInjectedWrites }
    public init(service: ClubCommunityService, currentSession: @escaping () throws -> ClubCommunitySession, refreshEvidence: @escaping (ClubCommunityEvidence) async throws -> ClubCommunityEvidence) {
        self.service = service; self.currentSession = currentSession; self.refreshEvidence = refreshEvidence
    }
    public func prepare(_ operation: ClubCommunityOperation, evidence: ClubCommunityEvidence) async throws -> ClubCommunityReview {
        guard permitsInjectedWrites else { throw ClubCommunityFailure.unavailable }
        generation &+= 1; let ticket = generation
        let session = try currentSession()
        guard session.identity == evidence.identity else { throw ClubCommunityFailure.stale }
        let fresh = try await refreshEvidence(evidence)
        guard ticket == generation, try currentSession() == session, fresh.identity == session.identity, fresh.clubID == evidence.clubID,
              fresh.post == evidence.post, fresh.comment == evidence.comment,
              Date().timeIntervalSince(fresh.observedAt) >= 0, Date().timeIntervalSince(fresh.observedAt) < 60 else { throw ClubCommunityFailure.stale }
        let result = try ClubCommunityReview(operation: operation, evidence: fresh)
        guard !locks.contains(result.lockKey) else { throw ClubCommunityFailure.locked }
        review = result; outcome = .reviewing; return result
    }
    public func cancel() { generation &+= 1; review = nil; if outcome == .reviewing { outcome = .idle } }
    public func confirm(_ candidate: ClubCommunityReview) async throws {
        guard candidate == review, !consumed.contains(candidate.id), !locks.contains(candidate.lockKey) else { throw ClubCommunityFailure.locked }
        let session = try currentSession()
        guard session.identity == candidate.evidence.identity else { throw ClubCommunityFailure.stale }
        let fresh = try await refreshEvidence(candidate.evidence)
        guard candidate == review, !consumed.contains(candidate.id), try currentSession() == session, fresh.identity == candidate.evidence.identity,
              fresh.clubID == candidate.evidence.clubID, fresh.post == candidate.evidence.post, fresh.comment == candidate.evidence.comment,
              fresh.joined == candidate.evidence.joined, fresh.owner == candidate.evidence.owner, fresh.administrator == candidate.evidence.administrator,
              Date().timeIntervalSince(fresh.observedAt) >= 0, Date().timeIntervalSince(fresh.observedAt) < 60,
              fresh.allows(candidate.operation), !locks.contains(candidate.lockKey) else { throw ClubCommunityFailure.stale }
        consumed.insert(candidate.id); locks.insert(candidate.lockKey); outcome = .sending; review = nil
        do {
            try await service.submit(candidate, session: session) {
                guard try self.currentSession() == session else { throw ClubCommunityFailure.stale }
            }
            locks.remove(candidate.lockKey)
            switch candidate.operation { case .report, .reportComment: outcome = .moderationQueued; default: outcome = .acknowledgedRefreshRequired }
        } catch let error as ClubCommunityFailure {
            if case .rejected = error { locks.remove(candidate.lockKey); outcome = .rejected }
            else if error == .unavailable || error == .stale { locks.remove(candidate.lockKey); outcome = .rejected }
            else { outcome = .unknownLocked }
            throw error
        } catch { outcome = .unknownLocked; throw ClubCommunityFailure.unknown }
    }
    /// No reset/retry API: unknown legacy writes cannot be reconciled by guessed receipts,
    /// title matching, a changed count, a new epoch, or new request IDs.
    public func isLocked(_ evidence: ClubCommunityEvidence) -> Bool {
        let key = "\(evidence.identity.accountID ?? 0):\(evidence.clubID):\(evidence.post?.id ?? 0):\(evidence.comment?.id ?? 0)"
        return locks.contains(key)
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
