import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityMerchantValueOperation: String, CaseIterable, Sendable { case merchantAccess, report, result, events, benefit }

/// Separate merchant-report grant. GET report/events persist server snapshots; CITY read alone grants nothing.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityMerchantValueApproval {
    public let readApproval: CityPlayerReadApproval
    public let operations: Set<CityMerchantValueOperation>
    public let revision = UUID()
    public private(set) var revoked = false
    public init(readApproval: CityPlayerReadApproval, operations: Set<CityMerchantValueOperation>) throws {
        guard readApproval.matches(readApproval.context), !operations.isEmpty else { throw APIError.invalidConfiguration }
        self.readApproval = readApproval; self.operations = operations
    }
    public func revoke() { revoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool { !revoked && readApproval.matches(current) }
}

public enum CityMerchantValueRoute: Equatable {
    case merchantAccess
    case report(CityMerchantValueScope, CityMerchantValueWindow, requestID: String)
    case result(CityMerchantValueScope, Int64)
    case events(CityMerchantValueScope, CityMerchantValueWindow, cursor: String)
    case benefit(CityMerchantValueScope, CityMerchantValueWindow, snapshotID: Int64, eventID: Int64)
    public var operation: CityMerchantValueOperation {
        switch self { case .merchantAccess: return .merchantAccess; case .report: return .report; case .result: return .result; case .events: return .events; case .benefit: return .benefit }
    }
    func matches(_ scope: CityMerchantValueScope) -> Bool {
        switch self {
        case .report(let value, _, _), .result(let value, _), .events(let value, _, _), .benefit(let value, _, _, _): return value == scope
        case .merchantAccess: return true // Server rechecks actor ownership; payload is rechecked against board on readback.
        }
    }
    static func validCursor(_ value: String) -> Bool {
        value.range(of: #"\Av2\.[1-9][0-9]{0,18}\.[0-9]{1,5}\.[0-9a-f]{64}\z"#, options: .regularExpression) != nil
    }
    public func request(baseURL: URL, token: String) throws -> URLRequest {
        let config = try APIConfiguration(baseURL: baseURL)
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var path: String, fields: [String: String] = [:]
        let body: [String: Any]? = nil
        switch self {
        case .merchantAccess: path = "api/merchant/access/me"
        case .report(let scope, let window, let id):
            guard CityReadRoute.validID(id) else { throw APIError.invalidRequest }
            path = "api/merchant/city-value/report"; fields = scope.fields.merging(window.fields) { _, new in new }; fields["requestId"] = id
        case .result(let scope, let id):
            guard id > 0 else { throw APIError.invalidRequest }; path = "api/merchant/city-value/result/\(id)"
            fields = ["regionId": scope.regionId, "rulesReleaseId": scope.rulesReleaseId]
        case .benefit(let scope, let window, let snapshot, let event):
            guard snapshot > 0, event > 0 else { throw APIError.invalidRequest }
            path = "api/merchant/city-value/event/\(event)/benefit"
            fields = scope.fields.merging(window.fields) { _, new in new }; fields["snapshotId"] = String(snapshot)
        case .events(let scope, let window, let cursor):
            guard cursor.isEmpty || Self.validCursor(cursor) else { throw APIError.invalidRequest }
            path = "api/merchant/city-value/events"; fields = scope.fields.merging(window.fields) { _, new in new }; fields["cursor"] = cursor
        }
        guard var url = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        if !fields.isEmpty { url.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) } }
        guard let target = url.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: target); request.httpMethod = body == nil && operation != .merchantAccess ? "GET" : "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) }
        return request
    }
    /// Exact, canonical request parser. Adjacent routes, extra fields, duplicates and reordered/body mutations fail closed.
    public init?(request: URLRequest, baseURL: URL, scope: CityMerchantValueScope) {
        guard let url = request.url, url.fragment == nil, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] { guard fields[item.name] == nil, let value = item.value else { return nil }; fields[item.name] = value }
        func exact(_ path: String) -> Bool { url.path == baseURL.appendingPathComponent(path).path }
        var candidate: Self?
        let scopeKeys: Set<String> = ["regionId", "boardId", "seasonId", "rulesReleaseId"]
        if request.httpMethod == "POST", request.httpBody == nil, fields.isEmpty, exact("api/merchant/access/me"), request.value(forHTTPHeaderField: "Content-Type") == nil { candidate = .merchantAccess }
        else if request.httpMethod == "GET", request.httpBody == nil {
            if exact("api/merchant/city-value/report"), Set(fields.keys) == scopeKeys.union(["from", "to", "requestId"]),
                    let value = try? CityMerchantValueScope(fields: fields), let window = try? CityMerchantValueWindow(from: fields["from"]!, to: fields["to"]!) { candidate = .report(value, window, requestID: fields["requestId"]!) }
            else if exact("api/merchant/city-value/events"), Set(fields.keys) == scopeKeys.union(["from", "to", "cursor"]),
                    let value = try? CityMerchantValueScope(fields: fields), let window = try? CityMerchantValueWindow(from: fields["from"]!, to: fields["to"]!) { candidate = .events(value, window, cursor: fields["cursor"]!) }
            else if Set(fields.keys) == scopeKeys.union(["from", "to", "snapshotId"]),
                    let value = try? CityMerchantValueScope(fields: fields), let window = try? CityMerchantValueWindow(from: fields["from"]!, to: fields["to"]!),
                    let snapshot = Int64(fields["snapshotId"]!), snapshot > 0,
                    let event = Int64(url.deletingLastPathComponent().lastPathComponent), event > 0,
                    exact("api/merchant/city-value/event/\(event)/benefit") { candidate = .benefit(value, window, snapshotID: snapshot, eventID: event) }
            else if Set(fields.keys) == ["regionId", "rulesReleaseId"], fields["regionId"] == scope.regionId, fields["rulesReleaseId"] == scope.rulesReleaseId,
                    let id = Int64(url.lastPathComponent), id > 0, exact("api/merchant/city-value/result/\(id)") { candidate = .result(scope, id) }
        }
        guard let candidate, candidate.matches(scope), let canonical = try? candidate.request(baseURL: baseURL, token: "synthetic-route-validation"),
              canonical.url?.absoluteString == url.absoluteString, canonical.httpBody == request.httpBody else { return nil }
        self = candidate
    }
}

/// Dedicated composition boundary. It cannot send ROAM completion, redemption, points, goals or unrelated HTTP calls.
@available(macOS 14.0, *)
@MainActor public final class CityMerchantValueScopedTransport: HTTPTransport {
    private let underlying: any HTTPTransport
    private let approval: CityMerchantValueApproval
    private let scope: CityMerchantValueScope
    private let current: () -> Bool
    public init(underlying: any HTTPTransport, approval: CityMerchantValueApproval, scope: CityMerchantValueScope, current: @escaping () -> Bool) {
        self.underlying = underlying; self.approval = approval; self.scope = scope; self.current = current
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let context = approval.readApproval.context
        func valid() -> Bool { current() && approval.matches(context) && approval.readApproval.regionID == scope.regionId }
        guard valid(), let route = CityMerchantValueRoute(request: request, baseURL: context.baseURL, scope: scope), approval.operations.contains(route.operation),
              request.value(forHTTPHeaderField: "Authorization") == context.session.token else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let reply = try await underlying.send(request)
            try Task.checkCancellation(); guard valid() else { throw CancellationError() }; return reply
        } catch { guard valid(), !Task.isCancelled else { throw CancellationError() }; throw error }
    }
}

@available(macOS 14.0, *)
@MainActor public final class CityMerchantValueService {
    private let approval: CityMerchantValueApproval
    private let transport: any HTTPTransport
    private let current: () -> Bool
    private let unauthorized: () -> Void
    public let scope: CityMerchantValueScope
    public var isCurrent: Bool { current() && approval.matches(approval.readApproval.context) }
    public func allows(_ operation: CityMerchantValueOperation) -> Bool { isCurrent && approval.operations.contains(operation) }
    public init(approval: CityMerchantValueApproval, scope: CityMerchantValueScope, transport: any HTTPTransport,
                current: @escaping () -> Bool, unauthorized: @escaping () -> Void = {}) {
        self.approval = approval; self.scope = scope; self.transport = transport; self.current = current; self.unauthorized = unauthorized
    }
    public func merchantAccess() async throws -> MerchantBusinessAccess {
        let value = try await send(.merchantAccess, as: MerchantBusinessValue.self)
        guard let object = value.object else { throw APIError.malformedResponse }
        return try MerchantBusinessAccess(object)
    }
    func send<T: Decodable>(_ route: CityMerchantValueRoute, as type: T.Type) async throws -> T {
        guard allows(route.operation), route.matches(scope) else { throw APIError.notConfigured }
        let context = approval.readApproval.context
        let request = try route.request(baseURL: context.baseURL, token: context.session.token)
        let reply: (Data, Int)
        do { reply = try await transport.send(request) }
        catch {
            guard isCurrent, !Task.isCancelled else { throw CancellationError() }
            if error as? APIError == .unauthorized || error as? APIError == .httpStatus(401) { unauthorized() }
            throw error
        }
        let (data, http) = reply
        guard isCurrent, !Task.isCancelled else { throw CancellationError() }
        if http == 401 { unauthorized(); throw APIError.unauthorized }
        guard data.count <= 2 * 1024 * 1024 else { throw APIError.malformedResponse }
        let header = try JSONDecoder().decode(CityMerchantValueResponseHeader.self, from: data)
        if header.code == 401 { unauthorized(); throw APIError.unauthorized }
        if http == 403 || header.code == 403 { throw CityMerchantValueFailure.noPermission }
        guard http == 200, header.code == 200 else { throw CityMerchantValueFailure.rejected(header.errorCode ?? "UNAVAILABLE") }
        let envelope = try JSONDecoder().decode(CityMerchantValueEnvelope<T>.self, from: data)
        guard let value = envelope.data else { throw APIError.malformedResponse }
        return value
    }
}
private struct CityMerchantValueResponseHeader: Decodable { let code: Int; let errorCode: String? }
private struct CityMerchantValueEnvelope<T: Decodable>: Decodable { let code: Int; let data: T?; let errorCode: String? }
public enum CityMerchantValueFailure: Error, Equatable { case rejected(String), stale, noPermission }
