import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityParticipationReadFailure: Error, Equatable {
    case disabled, invalidReference, staleSession, unverified, unavailable(status: Int)
}

/// Separate read scope, not a command reference, membership grant or gameplay session.
public struct CityParticipationReadScope: Equatable {
    public let session: CityOriginalReceiptSession
    public let regionID: String
    private let credential: String
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int,
                epoch: UInt64, token: String, regionID: String) throws {
        guard Self.isID(regionID) else { throw CityParticipationReadFailure.invalidReference }
        session = try .init(market: market, baseURL: baseURL, namespace: namespace, accountID: accountID, epoch: epoch, token: token)
        self.regionID = regionID; credential = token
    }
    fileprivate var token: String { credential }
    fileprivate static func isID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        func alnum(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b) }
        return !bytes.isEmpty && bytes.count <= 96 && alnum(bytes[0]) && bytes.allSatisfy { alnum($0) || $0 == 45 || $0 == 95 }
    }
}

/// Default issuer is nil. A later production host must verify deployment and read permission.
@MainActor public final class CityParticipationReadGrant {
    public let scope: CityParticipationReadScope
    public private(set) var isRevoked = false
    public init(scope: CityParticipationReadScope) { self.scope = scope }
    public func revoke() { isRevoked = true }
}

/// Exact r491 state projection. No points, action budget, navigation or writer authority.
public struct CityParticipationState: Decodable, Equatable {
    public let contract: String
    public let scope: String
    public let binding: Binding
    public let status: String
    public let writeApproved: Bool // Server observation only, never a client write grant.
    public let pointsStatus: String
    public let taskExecutionStatus: String
    public let actionBudgetStatus: String
    public let team: Team?
    public struct Binding: Decodable, Equatable {
        public let releaseId: Int64
        public let regionId: String
        public let boardId: String
        public let seasonId: String
        public let rulesReleaseId: String
        public let contentHash: String
        public let revision: Int64
        public let title: String
        public let rules: Rules
    }
    public struct Rules: Decodable, Equatable {
        public let mode: String
        public let minMembers: Int
        public let maxMembers: Int
        public let joinPolicy: String
        public let rosterPolicy: String
        public let replacementPolicy: String
        public let reentryPolicy: String
        public let roundPolicy: String
        public let roundId: String
    }
    public struct Team: Decodable, Equatable {
        public let teamId: String
        public let version: Int64
        public let state: String
        public let captain: Bool
        public let memberCount: Int
        public let presentCount: Int
        public let confirmedCount: Int
        public let present: Bool
        public let confirmed: Bool
        public let inviteCode: String?
        public let session: Session?
    }
    public struct Session: Decodable, Equatable {
        public let sessionId: String
        public let version: Int64
        public let state: String
    }
    fileprivate func validate(regionID: String) throws {
        func require(_ condition: Bool) throws { if !condition { throw CityParticipationReadFailure.unverified } }
        func uuid(_ value: String) -> Bool {
            value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil
        }
        let b = binding, r = b.rules
        try require(contract == "CITY_TEAM_PARTICIPATION_V1" && scope == "CITY" && b.regionId == regionID)
        try require(b.releaseId > 0 && b.revision > 0 && [b.boardId, b.seasonId, b.rulesReleaseId, r.roundId].allSatisfy(CityParticipationReadScope.isID))
        try require(b.contentHash.utf8.count == 64 && b.contentHash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
        try require(r.mode == "CITY_TEAM" && r.minMembers >= 1 && r.maxMembers >= r.minMembers && r.maxMembers <= 200)
        try require(r.joinPolicy == "INVITE_CODE" && r.rosterPolicy == "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM"
                    && r.replacementPolicy == "FORBIDDEN_AFTER_LOCK" && r.reentryPolicy == "RESUME_ORIGINAL_SESSION" && r.roundPolicy == "FIXED_PUBLISHED_ROUND")
        try require(pointsStatus == "UNAVAILABLE" && taskExecutionStatus == "UNAVAILABLE" && actionBudgetStatus == "UNAVAILABLE")
        guard let t = team else { try require(status == "NOT_JOINED"); return }
        try require(uuid(t.teamId) && t.version > 0 && ["FORMING", "LOCKED"].contains(t.state))
        try require(t.memberCount >= 1 && t.memberCount <= r.maxMembers && (0...t.memberCount).contains(t.presentCount) && (0...t.memberCount).contains(t.confirmedCount))
        try require(!t.present || t.presentCount > 0); try require(!t.confirmed || t.confirmedCount > 0)
        try require(status == (t.present && t.confirmed ? "JOINED" : "PENDING"))
        if let invite = t.inviteCode { try require(t.captain && t.state == "FORMING" && uuid(invite)) }
        if let s = t.session {
            try require(t.state == "LOCKED" && uuid(s.sessionId) && s.version > 0 && ["AWAITING_CONFIRMATION", "READY"].contains(s.state))
        } else { try require(t.state == "FORMING") }
        // Preserve the original frozen binding and session state. Do not infer currentness,
        // account eligibility, gameplay readiness or permissions from counts/READY/writeApproved.
    }
}

@MainActor public final class CityParticipationStateReader {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentScope: () -> CityParticipationReadScope?
    private let grant: () -> CityParticipationReadGrant?
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                currentScope: @escaping () -> CityParticipationReadScope?,
                grant: @escaping () -> CityParticipationReadGrant? = { nil }) {
        self.configuration = configuration; self.transport = transport; self.currentScope = currentScope; self.grant = grant
    }
    public func read(_ scope: CityParticipationReadScope) async throws -> CityParticipationState {
        guard let issued = grant(), !issued.isRevoked, issued.scope == scope else { throw CityParticipationReadFailure.disabled }
        func check() throws {
            try Task.checkCancellation()
            guard currentScope() == scope, configuration.baseURL == scope.session.baseURL else { throw CityParticipationReadFailure.staleSession }
            guard grant() === issued, !issued.isRevoked else { throw CityParticipationReadFailure.disabled }
        }
        try check()
        var url = URLComponents(url: configuration.baseURL.appendingPathComponent("api/city-game/team-participation/state"), resolvingAgainstBaseURL: false)
        url?.queryItems = [.init(name: "regionId", value: scope.regionID)]
        guard let target = url?.url else { throw CityParticipationReadFailure.invalidReference }
        var request = URLRequest(url: target)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue(scope.token, forHTTPHeaderField: "Authorization")
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch { try check(); throw CityParticipationReadFailure.unverified }
        try check()
        guard response.1 == 200 else { throw CityParticipationReadFailure.unavailable(status: response.1) }
        guard response.0.count <= 1_048_576, let header = try? JSONDecoder().decode(Header.self, from: response.0) else { throw CityParticipationReadFailure.unverified }
        guard header.code == 200 else { throw CityParticipationReadFailure.unavailable(status: header.code) }
        guard header.errorCode == nil || header.errorCode == "", let envelope = try? JSONDecoder().decode(Envelope.self, from: response.0) else { throw CityParticipationReadFailure.unverified }
        try envelope.data.validate(regionID: scope.regionID)
        try check()
        return envelope.data
    }
    private struct Header: Decodable { let code: Int; let errorCode: String? }
    private struct Envelope: Decodable { let data: CityParticipationState }
}
