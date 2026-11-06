import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ClubPublicRosterMember: Decodable, Equatable, Identifiable {
    public let memberId: Int
    fileprivate let clubId: Int?
    public let nickname: String?
    public let avatar: String?
    public let levelId: Int?
    public let joinTime: String?
    public var id: Int { memberId }
    // Only fixed58 public presentation fields. No phone, management state,
    // join-message, CRM annotation, member permission or raw dictionary escapes.
}
public struct ClubPublicRosterRank: Decodable, Equatable, Identifiable {
    public let memberId: Int
    fileprivate let clubId: Int?
    public let nickname: String?
    public let avatar: String?
    public let score: Double?
    public let mileage: Double?
    public let pace: Double?
    public let completionDuration: Double?
    public var id: Int { memberId }
    public func metric(_ mode: ClubPublicRosterMode) -> Double? {
        switch mode { case .composite: return score; case .mileage: return mileage; case .pace: return pace; case .duration: return completionDuration; case .members: return nil }
    }
}
public struct ClubPublicRosterSession: Equatable {
    public let identity: ClubReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.unauthorized }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
public struct ClubPublicRosterSnapshot: Equatable {
    public let club: ClubRecord
    public let identity: ClubReadIdentity
    public let approval: ClubPublicRosterApproval
    public let mode: ClubPublicRosterMode
    public let members: [ClubPublicRosterMember]
    public let ranks: [ClubPublicRosterRank]
    public var memberIDs: Set<Int> { Set(members.map(\.memberId) + ranks.map(\.memberId)) }
}

/// This is an independent read-only branch. Existing member directory/governance
/// readers and their permission gates are unchanged. No cache survives relaunch.
@MainActor public final class ClubPublicRosterReader {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentSession: () -> ClubPublicRosterSession?
    private let approval: () -> ClubPublicRosterApproval?
    private let onUnauthorized: (ClubPublicRosterSession) -> Void
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                currentSession: @escaping () -> ClubPublicRosterSession?,
                approval: @escaping () -> ClubPublicRosterApproval?,
                onUnauthorized: @escaping (ClubPublicRosterSession) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport; self.currentSession = currentSession
        self.approval = approval; self.onUnauthorized = onUnauthorized
    }
    public var identity: ClubReadIdentity? { currentSession()?.identity }
    public var authorization: ClubPublicRosterApproval? {
        guard let session = currentSession(), let grant = approval(), grant.identity == session.identity,
              grant.baseURL == configuration.baseURL else { return nil }
        return grant
    }
    public func isCurrent(_ snapshot: ClubPublicRosterSnapshot) -> Bool {
        identity == snapshot.identity && authorization == snapshot.approval
    }
    public func read(clubID: Int, mode: ClubPublicRosterMode, isCurrent: @escaping () -> Bool) async throws -> ClubPublicRosterSnapshot {
        guard clubID > 0, let session = currentSession(), let grant = authorization else { throw APIError.notConfigured }
        func check() throws {
            guard !Task.isCancelled, isCurrent(), currentSession() == session, authorization == grant else { throw CancellationError() }
        }
        do {
            try check()
            let detail = ClubService(configuration: configuration, transport: transport)
            let club = try await detail.detail(id: clubID, token: session.token)
            try check()
            guard ClubPublicRosterEligibility.mayRequest(club, identity: session.identity) else { throw ClubReadFailure.membershipRequired }
            let path = mode == .members ? "api/club/members" : "api/club/leaderboard"
            var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: session.token)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let body: [String: Any] = mode == .members ? ["clubId": clubID] : ["id": clubID, "sortBy": mode.rawValue]
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            try check()
            let (bytes, status) = try await transport.send(request)
            try check()
            guard bytes.count <= 4 * 1024 * 1024 else { throw APIError.malformedResponse }
            let envelope = try? JSONDecoder().decode(Status.self, from: bytes)
            if status == 401 || envelope?.code == 401 { throw ClubReadFailure.unauthorized(message: envelope?.msg) }
            if status == 403 || envelope?.code == 403 { throw ClubReadFailure.forbidden(message: envelope?.msg) }
            guard (200..<300).contains(status), let code = envelope?.code else { throw APIError.malformedResponse }
            guard code == 200 else { throw ClubReadFailure.rejected(code: code, message: envelope?.msg) }
            let members: [ClubPublicRosterMember]
            let ranks: [ClubPublicRosterRank]
            if mode == .members {
                members = try JSONDecoder().decode(Envelope<[ClubPublicRosterMember]>.self, from: bytes).data
                ranks = []
            } else {
                members = []
                ranks = try JSONDecoder().decode(Envelope<[ClubPublicRosterRank]>.self, from: bytes).data
            }
            let ids = members.map(\.memberId) + ranks.map(\.memberId)
            guard ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count,
                  members.allSatisfy({ $0.clubId == nil || $0.clubId == clubID }),
                  ranks.allSatisfy({ $0.clubId == nil || $0.clubId == clubID }),
                  ranks.allSatisfy({ row in row.metric(mode).map { $0.isFinite && $0 > 0 } == true }) else { throw APIError.malformedResponse }
            // Endpoint itself authoritatively checked status=1, visibility, public
            // policy (including supported-column fallback), and both ban guards.
            // Re-read detail to discard a known policy/identity change while reading.
            let current = try await detail.detail(id: clubID, token: session.token)
            try check()
            guard current.id == club.id, ClubPublicRosterEligibility.mayRequest(current, identity: session.identity) else { throw ClubReadFailure.membershipRequired }
            return .init(club: current, identity: session.identity, approval: grant, mode: mode, members: members, ranks: ranks)
        } catch {
            try check()
            if (error as? ClubReadFailure)?.isUnauthorized == true { onUnauthorized(session) }
            throw error
        }
    }
    private struct Status: Decodable { let code: Int; let msg: String? }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
}
