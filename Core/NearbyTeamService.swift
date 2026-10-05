import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NearbyTeamSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let region: String
    public let namespace: String
    public let role: String
    public init(accountID: Int, epoch: UInt64, region: String, namespace: String, role: String) { self.accountID = accountID; self.epoch = epoch; self.region = region; self.namespace = namespace; self.role = role }
    public var valid: Bool { accountID > 0 && ["CN", "US"].contains(region) && !namespace.isEmpty && role == "player" }
}
/// A request description, not an executable live-network grant. Never embeds credentials.
public struct NearbyTeamRequest: Equatable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let body: Data?
    public let mutation: Bool
    public static func nearby(_ context: NearbyQueryContext) throws -> Self {
        guard context.valid else { throw NearbyTeamFailure.invalidRequest }
        return .init(method: "GET", path: "/api/team/nearby", query: ["lat": String(context.latitude), "lng": String(context.longitude), "radius": String(context.radius)], body: nil, mutation: false)
    }
    public static func applications(_ team: NearbyTeamID) throws -> Self { guard team.rawValue > 0 else { throw NearbyTeamFailure.invalidRequest }; return try post("applications", body: ["teamId": team.rawValue], mutation: false) }
    public static func myApplications() -> Self { .init(method: "POST", path: "/api/team/my-applications", query: [:], body: nil, mutation: false) }
    public static func action(_ action: NearbyTeamAction) throws -> Self {
        guard action.teamID.rawValue > 0 else { throw NearbyTeamFailure.invalidRequest }
        switch action {
        case .apply(let team), .withdraw(let team): return try post(action.operation, body: ["teamId": team.rawValue], mutation: true)
        case .handle(let team, let applicant, let approved):
            guard applicant.rawValue > 0 else { throw NearbyTeamFailure.invalidRequest }
            return try post("handle", body: ["teamId": team.rawValue, "memberId": applicant.rawValue, "approved": approved], mutation: true)
        }
    }
    private static func post(_ operation: String, body: [String: Any], mutation: Bool) throws -> Self {
        .init(method: "POST", path: "/api/team/\(operation)", query: [:], body: try JSONSerialization.data(withJSONObject: body, options: .sortedKeys), mutation: mutation)
    }
}
public struct NearbyTeamResponse { public let status: Int; public let data: Data; public init(status: Int = 200, data: Data) { self.status = status; self.data = data } }
/// Implementers may provide independently authorized read-only transport. Mutations never use it.
@MainActor public protocol NearbyTeamReadTransport: AnyObject { func sendRead(_ request: NearbyTeamRequest, session: NearbyTeamSession) async throws -> NearbyTeamResponse }
public enum NearbyWriteResult: Equatable { case simulated(expiry: NearbyServerTime?), acknowledged(expiry: NearbyServerTime?), rejected(errorCode: String, message: String), notSent, unknown }
@MainActor public final class NearbyTeamService {
    private let readTransport: (any NearbyTeamReadTransport)?
    private let fake: NearbyTeamFakeTransport?
    private let liveReadGrant: Bool
    private let writeAdapter: (any NearbyTeamWriting)?
    public var synthetic: Bool { fake != nil }
    public var canSubmit: Bool { synthetic || writeAdapter?.configured == true }
    public var configured: Bool { fake != nil || (liveReadGrant && readTransport != nil) }
    public init(readTransport: (any NearbyTeamReadTransport)? = nil, liveReadGrant: Bool = false, writeAdapter: (any NearbyTeamWriting)? = nil) { self.readTransport = readTransport; self.liveReadGrant = liveReadGrant; self.writeAdapter = writeAdapter; fake = nil }
    public init(fake: NearbyTeamFakeTransport) { self.fake = fake; readTransport = nil; liveReadGrant = false; writeAdapter = nil }
    public func nearby(_ context: NearbyQueryContext, session: NearbyTeamSession) async throws -> [NearbyTeam] { try await list(try .nearby(context), session: session) }
    public func applications(_ team: NearbyTeamID, session: NearbyTeamSession) async throws -> [NearbyApplicant] { try await list(try .applications(team), session: session) }
    public func myApplications(session: NearbyTeamSession) async throws -> [NearbyMyApplication] { try await list(.myApplications(), session: session) }
    private func list<T: Decodable>(_ request: NearbyTeamRequest, session: NearbyTeamSession) async throws -> [T] {
        guard session.valid else { throw NearbyTeamFailure.unauthorized }; try Task.checkCancellation()
        let response: NearbyTeamResponse
        if let fake { response = try await fake.send(request, session: session) }
        else { guard liveReadGrant, let readTransport, !request.mutation else { throw NearbyTeamFailure.unconfigured }; response = try await readTransport.sendRead(request, session: session) }
        try Task.checkCancellation(); try Self.validate(response)
        do { return try JSONDecoder().decode(NearbyEnvelope<[T]>.self, from: response.data).data } catch { throw NearbyTeamFailure.contract }
    }
    public func submit(_ action: NearbyTeamAction, session: NearbyTeamSession, review: NearbyTeamReview? = nil) async -> NearbyWriteResult {
        guard session.valid else { return .notSent }
        if let fake {
            let request: NearbyTeamRequest
            do { request = try .action(action); try Task.checkCancellation() } catch { return .notSent }
            do { return Self.decodeWrite(try await fake.send(request, session: session), action: action, synthetic: true) }
            catch { return .unknown }
        }
        guard let writeAdapter, let review, review.action == action, review.session == session else { return .notSent }
        return await writeAdapter.submit(review)
    }
    /// Only code==200 in a successful HTTP envelope acknowledges a server operation.
    /// It is not a simulated result, new roster, attendance, receipt ID, or eligibility grant.
    static func decodeWrite(_ response: NearbyTeamResponse, action: NearbyTeamAction, synthetic: Bool) -> NearbyWriteResult {
        do {
            try Self.validate(response)
            var expiry: NearbyServerTime?
            if case .apply = action,
               let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
               let data = root["data"] as? [String: Any], let value = data["applyExpireTime"], !(value is NSNull) {
                let raw = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
                expiry = try? JSONDecoder().decode(NearbyServerTime.self, from: raw)
            }
            return synthetic ? .simulated(expiry: expiry) : .acknowledged(expiry: expiry)
        } catch NearbyTeamFailure.rejected(let code, let message) { return .rejected(errorCode: code, message: message) }
        catch { return .unknown }
    }
    private static func validate(_ response: NearbyTeamResponse) throws {
        let header = try? JSONDecoder().decode(NearbyHeader.self, from: response.data)
        if response.status == 401 || header?.code == 401 { throw NearbyTeamFailure.unauthorized }
        guard (200..<300).contains(response.status) else { throw NearbyTeamFailure.transport }
        guard let header else { throw NearbyTeamFailure.contract }
        guard header.code == 200 else { throw NearbyTeamFailure.rejected(errorCode: header.errorCode, message: header.msg) }
    }
}
private struct NearbyEnvelope<T: Decodable>: Decodable { let data: T }
private struct NearbyHeader: Decodable {
    let code: Int; let errorCode: String; let msg: String
    enum CodingKeys: String, CodingKey { case code, errorCode, msg }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); guard let code = c.nearbyInt(.code) else { throw NearbyTeamFailure.contract }; self.code = code; errorCode = c.nearbyText(.errorCode); msg = c.nearbyText(.msg) }
}
/// Fixtures are queued raw envelopes, exercising the same request and response parser as dormant adapters.
@MainActor public final class NearbyTeamFakeTransport {
    public enum Step { case response(NearbyTeamResponse), failure, suspended }
    public private(set) var requests: [NearbyTeamRequest] = []
    public private(set) var sessions: [NearbyTeamSession] = []
    public var fallbackResponses: [String: NearbyTeamResponse] = [:]
    private var steps: [Step]
    private var continuation: CheckedContinuation<NearbyTeamResponse, Error>?
    public init(steps: [Step] = []) { self.steps = steps }
    public func enqueue(_ step: Step) { steps.append(step) }
    public func resume(_ response: NearbyTeamResponse) { continuation?.resume(returning: response); continuation = nil }
    func send(_ request: NearbyTeamRequest, session: NearbyTeamSession) async throws -> NearbyTeamResponse {
        requests.append(request); sessions.append(session)
        guard !steps.isEmpty else { if let response = fallbackResponses[request.path] { return response }; throw NearbyTeamFailure.transport }
        switch steps.removeFirst() { case .response(let response): return response; case .failure: throw NearbyTeamFailure.transport; case .suspended: return try await withCheckedThrowingContinuation { continuation = $0 } }
    }
}
