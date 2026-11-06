import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Separate read-only deployment grant. Board visibility/login never issues it.
@available(macOS 14.0, *) @MainActor @Observable public final class CityPlayerRulesApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    @ObservationIgnored private var expiry: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, regionID: String, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, ["player", "merchant", "club"].contains(context.role), context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), CityReadRoute.validID(regionID),
              expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86_400 else { throw CityPlayerRulesError.disabled }
        self.context = context; self.regionID = regionID; self.expiresAt = expiresAt
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(max(0, min(expiresAt.timeIntervalSinceNow, 86_400)) * 1_000_000_000)); try Task.checkCancellation() } catch { return }
            self?.revoke()
        }
    }
    deinit { expiry?.cancel() }
    public func revoke() { revoked = true; expiry?.cancel(); expiry = nil }
    public func matches(_ live: RuntimeDependencyContext) -> Bool { !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, live) }
}
public struct CityPlayerRulesRoute {
    public let regionID: String
    private let values: [String: String]
    public init(read: CityReadSnapshot) throws {
        guard read.board.valid, read.board.lifecycle == "FROZEN", read.membership != .joined || read.participation?.valid == true else { throw APIError.invalidRequest }
        let b = read.board; regionID = b.regionId
        var query = ["gameId": b.gameId, "regionId": b.regionId, "boardId": b.boardId, "seasonId": b.seasonId, "rulesReleaseId": b.rulesReleaseId,
                     "rulesHash": b.rulesHash, "revision": String(b.revision), "membership": read.membership.rawValue]
        if read.membership == .joined, let own = read.participation { query["participationId"] = own.participationId; query["membershipVersion"] = String(own.membershipVersion) }
        values = query
    }
    public func request(baseURL: URL, token: String) throws -> URLRequest {
        let configuration = try APIConfiguration(baseURL: baseURL)
        guard AuthRequestBuilder.isValidToken(token), var parts = URLComponents(url: configuration.baseURL.appendingPathComponent("api/city-game/player-rules"), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        parts.queryItems = values.keys.sorted().map { .init(name: $0, value: values[$0]) }
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json", let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil, parts.user == nil, parts.password == nil,
              let items = parts.queryItems, items.count == Set(items.map(\.name)).count else { return nil }
        var query: [String: String] = [:]
        for item in items { guard let value = item.value else { return nil }; query[item.name] = value }
        var keys: Set<String> = ["gameId", "regionId", "boardId", "seasonId", "rulesReleaseId", "rulesHash", "revision", "membership"]
        if query["membership"] == "JOINED" { keys.formUnion(["participationId", "membershipVersion"]) }
        guard Set(query.keys) == keys, ["gameId", "regionId", "boardId", "seasonId", "rulesReleaseId"].allSatisfy({ CityReadRoute.validID(query[$0] ?? "") }),
              query["rulesHash"]?.range(of: "\\A[a-f0-9]{64}\\z", options: .regularExpression) != nil,
              Self.number(query["revision"]), CityMembership(rawValue: query["membership"] ?? "") != nil,
              query["membership"] != "JOINED" || (CityReadRoute.validID(query["participationId"] ?? "") && Self.number(query["membershipVersion"])) else { return nil }
        regionID = query["regionId"]!; values = query
        guard let canonical = try? self.request(baseURL: baseURL, token: "synthetic-token"), canonical.url?.absoluteString == url.absoluteString else { return nil }
    }
    private static func number(_ text: String?) -> Bool { guard let text, let value = Int64(text), String(value) == text else { return false }; return (0...9_007_199_254_740_991).contains(value) }
}
@available(macOS 14.0, *) @MainActor public final class CityPlayerRulesTransport: HTTPTransport {
    private let approval: CityPlayerRulesApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> CityPlayerRulesApproval?
    public init(approval: CityPlayerRulesApproval, underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> CityPlayerRulesApproval?) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected
    }
    public func isCurrent() -> Bool { guard let live = current(), approval.matches(live), let selected = selected(live) else { return false }; return selected.revision == approval.revision && selected.matches(live) }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent(), request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              let route = CityPlayerRulesRoute(request: request, baseURL: approval.context.baseURL), route.regionID == approval.regionID else { throw CityPlayerRulesError.disabled }
        let result = try await underlying.send(request)
        try Task.checkCancellation(); guard isCurrent() else { throw CityPlayerRulesError.disabled }; return result
    }
}
@available(macOS 14.0, *) @MainActor public final class CityPlayerRulesClient {
    private let approval: CityPlayerRulesApproval
    public let transport: CityPlayerRulesTransport
    public let read: CityReadSnapshot
    public init(approval: CityPlayerRulesApproval, transport: CityPlayerRulesTransport, read: CityReadSnapshot) { self.approval = approval; self.transport = transport; self.read = read }
    public var current: Bool { transport.isCurrent() && approval.regionID == read.board.regionId }
    private struct Envelope: Decodable { let code: Int; let errorCode: String?; let data: CityPlayerRulesSnapshot? }
    public func load() async throws -> CityPlayerRulesSnapshot {
        guard current else { throw CityPlayerRulesError.disabled }
        let request = try CityPlayerRulesRoute(read: read).request(baseURL: approval.context.baseURL, token: approval.context.session.token)
        let (data, status) = try await transport.send(request)
        guard data.count <= 65_536 else { throw CityPlayerRulesError.malformed }
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw CityPlayerRulesError.accessWithdrawn }
        if status == 409 { throw CityPlayerRulesError.changed }
        if status == 404 { throw CityPlayerRulesError.notPublished }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if envelope.code == 401 { throw APIError.unauthorized }
        if envelope.code == 403 { throw CityPlayerRulesError.accessWithdrawn }
        if envelope.code == 409 { throw CityPlayerRulesError.changed }
        if envelope.code == 404 { throw CityPlayerRulesError.notPublished }
        guard status == 200, envelope.code == 200 else { throw CityPlayerRulesError.server(status, envelope.errorCode ?? "UNAVAILABLE") }
        guard current, let value = envelope.data, value.valid(read: read) else { throw CityPlayerRulesError.malformed }
        return value
    }
}
