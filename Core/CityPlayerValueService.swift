import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityPlayerValueOperation: String, CaseIterable, Sendable { case services, visit, begin, feedback }

/// A separate explicit value-domain grant. Existing CITY read approval alone never authorizes entry/feedback writes.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityPlayerValueApproval {
    public let mapApproval: CityValueBoundedMapApproval
    public let capture: CityValueBoundedCapture
    public let operations: Set<CityPlayerValueOperation>
    public let revision = UUID()
    public private(set) var revoked = false
    public var readApproval: CityPlayerReadApproval { mapApproval.readApproval }
    public init(mapApproval: CityValueBoundedMapApproval, capture: CityValueBoundedCapture, operations: Set<CityPlayerValueOperation>) throws {
        guard mapApproval.matches(mapApproval.readApproval.context), capture.board.regionId == mapApproval.readApproval.regionID,
              !operations.isEmpty else { throw APIError.invalidConfiguration }
        _ = try CityPlayerValueMapPage(read:capture,query:capture.query,watermark:capture.watermark,page:capture.page)
        self.mapApproval = mapApproval; self.capture = capture; self.operations = operations
    }
    public func revoke() { revoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool { !revoked && mapApproval.matches(current) }

}

public enum CityPlayerValueRoute: Equatable {
    case services(CityPlayerValueScope, page: CityPlayerValueMapPage)
    case visit(String)
    case begin(requestID: String, scope: CityPlayerValueScope, page: CityPlayerValueMapPage, pointID: String, poiID: Int64)
    case feedback(visitID: String, CityPlayerValueFeedback)
    public var operation: CityPlayerValueOperation {
        switch self { case .services: return .services; case .visit: return .visit; case .begin: return .begin; case .feedback: return .feedback }
    }
    func matches(_ scope: CityPlayerValueScope) -> Bool {
        switch self {
        case .services(let value, _): return value == scope
        case .begin(_, let value, _, _, _): return value == scope
        case .visit, .feedback: return true // Server rechecks actor ownership; payload is rechecked against board on readback.
        }
    }
    func matches(page: CityPlayerValueMapPage?) -> Bool {
        switch self {
        case .services(_, let value): return page == value
        case .begin(_, _, let value, let pointID, _): return page == value && value.availablePointIDs.contains(pointID)
        default: return true
        }
    }
    static func validCursor(_ value: String) -> Bool {
        value.range(of: #"\Av2\.[1-9][0-9]{0,18}\.[0-9]{1,5}\.[0-9a-f]{64}\z"#, options: .regularExpression) != nil
    }
    public func request(baseURL: URL, token: String) throws -> URLRequest {
        let config = try APIConfiguration(baseURL: baseURL)
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var path: String, fields: [String: String] = [:], body: [String: Any]?
        switch self {
        case .services(let scope, let page): path = "api/city-value/visits/services"; fields = scope.fields.merging(page.fields) { _, new in new }
        case .visit(let id):
            guard CityReadRoute.validID(id) else { throw APIError.invalidRequest }; path = "api/city-value/visits/" + id
        case .begin(let id, let scope, let page, let point, let poi):
            guard CityReadRoute.validID(id), page.availablePointIDs.contains(point), (1...9_007_199_254_740_991).contains(poi) else { throw APIError.invalidRequest }
            path = "api/city-value/visits"; body = ["requestId": id, "page": scope.fields.merging(page.fields) { _, new in new }, "pointId": point, "poiId": poi]
        case .feedback(let id, let feedback):
            guard CityReadRoute.validID(id), feedback.valid else { throw APIError.invalidRequest }
            path = "api/city-value/visits/feedback"; body = feedback.fields; body?["visitId"] = id
        }
        guard var url = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        if !fields.isEmpty { url.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) } }
        guard let target = url.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: target); request.httpMethod = body == nil ? "GET" : "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) }
        return request
    }
    /// Exact, canonical request parser. Adjacent routes, extra fields, duplicates and reordered/body mutations fail closed.
    public init?(request: URLRequest, baseURL: URL, scope: CityPlayerValueScope, mapPage: CityPlayerValueMapPage? = nil) {
        guard let url = request.url, url.fragment == nil, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] { guard fields[item.name] == nil, let value = item.value else { return nil }; fields[item.name] = value }
        func exact(_ path: String) -> Bool { url.path == baseURL.appendingPathComponent(path).path }
        var candidate: Self?
        let scopeKeys: Set<String> = ["regionId", "boardId", "seasonId", "rulesReleaseId"]
        if request.httpMethod == "GET", request.httpBody == nil {
            if exact("api/city-value/visits/services"), let mapPage,
               fields == scope.fields.merging(mapPage.fields, uniquingKeysWith: { _, new in new }) { candidate = .services(scope, page: mapPage) }
            else if fields.isEmpty, CityReadRoute.validID(url.lastPathComponent), exact("api/city-value/visits/" + url.lastPathComponent),
                    !["services", "feedback"].contains(url.lastPathComponent) { candidate = .visit(url.lastPathComponent) }
        } else if request.httpMethod == "POST", fields.isEmpty, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let bytes = request.httpBody, bytes.count <= 4096, let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] {
            if exact("api/city-value/visits"), Set(object.keys) == ["requestId", "page", "pointId", "poiId"], let mapPage,
               let id = object["requestId"] as? String, let point = object["pointId"] as? String,
               let pageFields = object["page"] as? [String: String], pageFields == scope.fields.merging(mapPage.fields, uniquingKeysWith: { _, new in new }),
               let poi = object["poiId"] as? Int64 { candidate = .begin(requestID: id, scope: scope, page: mapPage, pointID: point, poiID: poi) }
            else if exact("api/city-value/visits/feedback"), let id = object["visitId"] as? String, let kind = object["kind"] as? String {
                if Set(object.keys) == ["visitId", "kind", "rating"], kind == "SERVICE_RATING", let rating = object["rating"] as? Int { candidate = .feedback(visitID: id, .rating(rating)) }
                else if Set(object.keys) == ["visitId", "kind", "reasonCode"], let raw = object["reasonCode"] as? String, let reason = CityPlayerValueFeedback.Reason(rawValue: raw) {
                    if kind == "SKIP" { candidate = .feedback(visitID: id, .skip(reason)) }; if kind == "EXIT" { candidate = .feedback(visitID: id, .exit(reason)) }
                }
            }
        }
        guard let candidate, candidate.matches(scope), candidate.matches(page: mapPage), let canonical = try? candidate.request(baseURL: baseURL, token: "synthetic-route-validation"),
              canonical.url?.absoluteString == url.absoluteString, canonical.httpBody == request.httpBody else { return nil }
        self = candidate
    }
}

/// Dedicated composition boundary. It cannot send ROAM completion, redemption, points, goals or unrelated HTTP calls.
@available(macOS 14.0, *)
@MainActor public final class CityPlayerValueScopedTransport: HTTPTransport {
    private let underlying: any HTTPTransport
    private let approval: CityPlayerValueApproval
    private let scope: CityPlayerValueScope
    private let mapPage: CityPlayerValueMapPage?
    private let current: () -> Bool
    public init(underlying: any HTTPTransport, approval: CityPlayerValueApproval, scope: CityPlayerValueScope, mapPage: CityPlayerValueMapPage? = nil, current: @escaping () -> Bool) {
        self.underlying = underlying; self.approval = approval; self.scope = scope; self.mapPage = mapPage; self.current = current
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let context = approval.readApproval.context
        func valid() -> Bool { current() && approval.matches(context) && approval.readApproval.regionID == scope.regionId }
        guard valid(), let route = CityPlayerValueRoute(request: request, baseURL: context.baseURL, scope: scope, mapPage: mapPage), approval.operations.contains(route.operation),
              request.value(forHTTPHeaderField: "Authorization") == context.session.token else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let reply = try await underlying.send(request)
            try Task.checkCancellation(); guard valid() else { throw CancellationError() }; return reply
        } catch { guard valid(), !Task.isCancelled else { throw CancellationError() }; throw error }
    }
}

@available(macOS 14.0, *)
@MainActor public final class CityPlayerValueService {
    private let approval: CityPlayerValueApproval?
    private let transport: any HTTPTransport
    private let current: () -> Bool
    private let unauthorized: () -> Void
    public let scope: CityPlayerValueScope
    public let mapPage: CityPlayerValueMapPage?
    public var isCurrent: Bool { guard let approval else { return false }; return current() && approval.matches(approval.readApproval.context) }
    public func allows(_ operation: CityPlayerValueOperation) -> Bool { isCurrent && approval?.operations.contains(operation) == true }
    public init(approval: CityPlayerValueApproval? = nil, capture: CityValueBoundedCapture, transport: any HTTPTransport,
                currentApproval: @escaping () -> CityPlayerValueApproval?, currentMapApproval: @escaping () -> CityValueBoundedMapApproval?, currentCapture: @escaping () -> CityValueBoundedCapture?,
                currentContext: @escaping () -> RuntimeDependencyContext?, unauthorized: @escaping () -> Void = {}) throws {
        let scope = try CityPlayerValueScope(board:capture.board)
        let page = try CityPlayerValueMapPage(read:capture,query:capture.query,watermark:capture.watermark,page:capture.page)
        self.approval = approval; self.scope = scope; mapPage = page; self.unauthorized = unauthorized
        let check = { @MainActor in
            guard let approval, let context = currentContext() else { return false }
            return currentApproval() === approval && currentMapApproval() === approval.mapApproval && currentCapture() == capture && approval.capture == capture && approval.matches(context)
        }
        current = check
        if let approval { self.transport = CityPlayerValueScopedTransport(underlying:transport,approval:approval,scope:scope,mapPage:page,current:check) }
        else { self.transport = transport }
    }
    func send<T: Decodable>(_ route: CityPlayerValueRoute, as type: T.Type) async throws -> T {
        guard let approval, allows(route.operation), route.matches(scope), route.matches(page: mapPage) else { throw APIError.notConfigured }
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
        let header = try JSONDecoder().decode(CityPlayerValueResponseHeader.self, from: data)
        if header.code == 401 { unauthorized(); throw APIError.unauthorized }
        if http == 403 || header.code == 403 { throw CityPlayerValueFailure.noPermission }
        guard http == 200, header.code == 200 else { throw CityPlayerValueFailure.rejected(header.errorCode ?? "UNAVAILABLE") }
        let envelope = try JSONDecoder().decode(CityPlayerValueEnvelope<T>.self, from: data)
        guard let value = envelope.data else { throw APIError.malformedResponse }
        return value
    }
}
private struct CityPlayerValueResponseHeader: Decodable { let code: Int; let errorCode: String? }
private struct CityPlayerValueEnvelope<T: Decodable>: Decodable { let code: Int; let data: T?; let errorCode: String? }
public enum CityPlayerValueFailure: Error, Equatable { case rejected(String), stale, noPermission }
