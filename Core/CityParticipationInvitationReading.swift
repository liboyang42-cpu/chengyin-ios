import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CityParticipationInvitation: Decodable, Equatable {
    public let binding: CityParticipationState.Binding
    public let teamId: String
    public let version: Int64
    public let memberCount: Int
}
@MainActor public final class CityParticipationInvitationGrant {
    public let scope: CityParticipationCommandScope
    public let regionID: String
    public let code: String
    public private(set) var isRevoked = false
    public init(scope: CityParticipationCommandScope, regionID: String, code: String) {
        self.scope = scope; self.regionID = regionID; self.code = code
    }
    public func revoke() { isRevoked = true }
}
/// Exact original GET invite contract. Possession reveals public binding/count/version only, not membership authority.
@MainActor public final class CityParticipationInvitationReader {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentScope: () -> CityParticipationCommandScope?
    private let grant: () -> CityParticipationInvitationGrant?
    private let grantForRequest: ((CityParticipationCommandScope, String, String) -> CityParticipationInvitationGrant?)?
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                currentScope: @escaping () -> CityParticipationCommandScope?,
                grant: @escaping () -> CityParticipationInvitationGrant? = { nil },
                grantForRequest: ((CityParticipationCommandScope, String, String) -> CityParticipationInvitationGrant?)? = nil) {
        self.configuration = configuration; self.transport = transport; self.currentScope = currentScope; self.grant = grant
        self.grantForRequest = grantForRequest
    }
    static func uuid(_ text: String) -> Bool {
        text.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z"#, options: .regularExpression) != nil
    }
    public func read(scope: CityParticipationCommandScope, regionID: String, code: String) async throws -> CityParticipationInvitation {
        guard CityParticipationCommand.id(regionID), Self.uuid(code) else { throw CityParticipationCommandFailure.invalid }
        // A contextual provider is authoritative when supplied; nil cannot fall back to broader old approval.
        func issuedGrant() -> CityParticipationInvitationGrant? {
            if let grantForRequest { return grantForRequest(scope, regionID, code) }
            return grant()
        }
        guard let issued = issuedGrant(), !issued.isRevoked, issued.scope == scope, issued.regionID == regionID, issued.code == code else {
            throw CityParticipationCommandFailure.disabled
        }
        func check() throws {
            try Task.checkCancellation()
            guard currentScope() == scope, configuration.baseURL == scope.session.baseURL else { throw CityParticipationCommandFailure.staleSession }
            guard issuedGrant() === issued, !issued.isRevoked else { throw CityParticipationCommandFailure.disabled }
        }
        try check()
        var parts = URLComponents(url: configuration.baseURL.appendingPathComponent("api/city-game/team-participation/invite"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "regionId", value: regionID), URLQueryItem(name: "code", value: code)]
        guard let url = parts?.url else { throw CityParticipationCommandFailure.invalid }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue(scope.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: (Data, Int)
        do { response = try await transport.send(request) } catch { try check(); throw CityParticipationCommandFailure.unverified }
        try check()
        guard response.1 == 200, response.0.count <= 1_048_576,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: response.0), envelope.code == 200,
              envelope.errorCode == nil || envelope.errorCode == "" else { throw CityParticipationCommandFailure.unverified }
        let result = envelope.data, binding = result.binding, rules = binding.rules
        guard binding.regionId == regionID, binding.releaseId > 0, binding.revision > 0,
              [binding.boardId, binding.seasonId, binding.rulesReleaseId, rules.roundId].allSatisfy(CityParticipationCommand.id),
              binding.contentHash.utf8.count == 64, binding.contentHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              Self.uuid(result.teamId), result.version > 0, result.memberCount >= 1, result.memberCount <= rules.maxMembers,
              rules.mode == "CITY_TEAM", rules.minMembers >= 1, rules.maxMembers >= rules.minMembers, rules.maxMembers <= 200,
              rules.joinPolicy == "INVITE_CODE", rules.rosterPolicy == "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM",
              rules.replacementPolicy == "FORBIDDEN_AFTER_LOCK", rules.reentryPolicy == "RESUME_ORIGINAL_SESSION",
              rules.roundPolicy == "FIXED_PUBLISHED_ROUND" else { throw CityParticipationCommandFailure.unverified }
        try check(); return result
    }
    private struct Envelope: Decodable { let code: Int; let errorCode: String?; let data: CityParticipationInvitation }
}
