import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TeamSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let viewerRevision: UInt64
    public let region: String
    public let role: String
    public let storageNamespace: String
    let token: String
    public var ownerKey: String { "\(region)-\(Data(storageNamespace.utf8).base64EncodedString())-\(accountID)" }
    public init(account: Account, epoch: UInt64, region: String, storageNamespace: String, token: String, viewerRevision: UInt64 = 0) throws {
        guard account.id > 0, ["CN", "US"].contains(region), !storageNamespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw TeamFailure.invalidRequest }
        accountID = account.id; self.epoch = epoch; self.viewerRevision = viewerRevision; self.region = region; role = account.effectiveRole; self.storageNamespace = storageNamespace; self.token = token
    }
}
public enum TeamServiceAuthority: Equatable { case unconfigured, readOnly, approved, synthetic }
public enum TeamWriteOutcome: Equatable { case simulated(operationID: UUID, teamID: Int), acknowledged(operationID: UUID, teamID: Int), rejected, notSent, unknown }
@MainActor public protocol TeamServing: AnyObject {
    var authority: TeamServiceAuthority { get }
    func myTeams(session: TeamSession) async throws -> [OwnedTeam]
    func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail
    func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext
    func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome
    func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome?
}
/// Authenticated, read-only allowlist. Both source reads are POST with JSON, never form/GET.
/// Supply transport/configuration only after independent regional backend verification.
@MainActor public final class TeamReadOnlyService: TeamServing {
    private let configuration: APIConfiguration?
    private let transport: (any HTTPTransport)?
    private let readApproval: OperationEndpointApproval?
    private let currentSession: (() -> TeamSession?)?
    private let requiresIDMembership: Bool
    private let creationLoader: ((Int, TeamSession) async throws -> TeamCreationContext)?
    public var authority: TeamServiceAuthority { configuration == nil || transport == nil ? .unconfigured : .readOnly }
    public init(configuration: APIConfiguration? = nil, transport: (any HTTPTransport)? = nil,
                readApproval: OperationEndpointApproval? = nil, currentSession: (() -> TeamSession?)? = nil,
                requiresIDMembership: Bool = false,
                creationLoader: ((Int, TeamSession) async throws -> TeamCreationContext)? = nil) {
        self.configuration = configuration; self.transport = transport; self.readApproval = readApproval
        self.currentSession = currentSession; self.creationLoader = creationLoader
        self.requiresIDMembership = requiresIDMembership
    }
    private func check(_ session: TeamSession) throws {
        try Task.checkCancellation()
        if let currentSession, currentSession() != session { throw TeamFailure.stale }
    }
    public func myTeams(session: TeamSession) async throws -> [OwnedTeam] {
        let result: [OwnedTeam] = try await read(path: "api/team/my", body: [:], session: session)
        guard Set(result.map(\.id)).count == result.count else { throw TeamFailure.invalidContract }
        return result
    }
    public func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail {
        guard lookup.isValid else { throw TeamFailure.invalidRequest }
        let body: [String: Any]
        switch lookup { case .id(let id): body = ["teamId": id]; case .invitation(let code): body = ["inviteCode": code.trimmingCharacters(in: .whitespacesAndNewlines)] }
        let detail: TeamDetail = try await read(path: "api/team/info", body: body, session: session)
        if case .id(let id) = lookup {
            guard detail.team.id == id else { throw TeamFailure.invalidContract }
            // Normal-root ID reads must carry the source's fresh membership projection.
            // Invitation reads intentionally permit nonmembers; this is not join authority.
            if requiresIDMembership, detail.joined != true { throw TeamFailure.invalidContract }
        }
        if case .invitation(let code) = lookup, let returnedCode = detail.team.inviteCode, returnedCode != code.trimmingCharacters(in: .whitespacesAndNewlines) { throw TeamFailure.invalidContract }
        return detail
    }
    public func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext {
        guard let creationLoader, ownerID > 0 else { throw TeamFailure.notConfigured }
        try check(session)
        let context = try await creationLoader(ownerID, session); try check(session)
        guard context.ownerID == ownerID, context.eligible else { throw TeamFailure.invalidContract }
        return context
    }
    public func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome { .notSent }
    public func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome? { nil }
    private func read<T: Decodable>(path: String, body: [String: Any], session: TeamSession) async throws -> T {
        guard let configuration, let transport else { throw TeamFailure.notConfigured }
        guard ["api/team/my", "api/team/info"].contains(path) else { throw TeamFailure.invalidRequest }
        if let readApproval, !readApproval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: path) { throw TeamFailure.notConfigured }
        try check(session)
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(session.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        try check(session); let (data, status) = try await transport.send(request); try check(session)
        let header = try? JSONDecoder().decode(Header.self, from: data)
        if status == 401 || header?.code == 401 { throw TeamFailure.unauthorized }
        guard (200..<300).contains(status) else { throw TeamFailure.unavailable }
        guard let code = header?.code else { throw TeamFailure.invalidContract }
        guard code == 200 else { throw TeamFailure.rejected(code) }
        do { return try JSONDecoder().decode(Envelope<T>.self, from: data).data }
        catch { throw TeamFailure.invalidContract }
    }
    private struct Header: Decodable {
        let code: Int?
        enum CodingKeys: String, CodingKey { case code }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? c.decode(Int.self, forKey: .code) { code = number }
            else if let text = try? c.decode(String.self, forKey: .code) { code = Int(text) }
            else { code = nil }
        }
    }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
}
