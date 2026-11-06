import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the three original owner-only GETs. No local upload, GPS, session recovery or settlement.
@MainActor @Observable public final class RoamPassportHistoryReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              approval.accountID == context.session.accountID,
              approval.paths == RoamPassportHistoryReadRoute.paths else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

public enum RoamPassportHistoryReadRoute: Equatable {
    case history(before: String?), record(sessionID: String), summary
    public static let prefix = "api/roam/passport/"
    public static let paths: Set<String> = [prefix + "history", prefix + "record", prefix + "summary"]
    public var path: String {
        switch self { case .history: return Self.prefix + "history"; case .record: return Self.prefix + "record"; case .summary: return Self.prefix + "summary" }
    }
    public func request(baseURL: URL, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token),
              var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        switch self {
        case .history(let before):
            if let before, !RoamPassportHistoryContract.isSessionID(before) { throw APIError.invalidRequest }
            parts.queryItems = (before.map { [URLQueryItem(name: "before", value: $0)] } ?? []) + [URLQueryItem(name: "limit", value: "30")]
        case .record(let id):
            guard RoamPassportHistoryContract.isSessionID(id) else { throw APIError.invalidRequest }
            parts.queryItems = [URLQueryItem(name: "sessionId", value: id)]
        case .summary: break
        }
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json", let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil else { return nil }
        let query = parts.queryItems ?? []
        let route: Self
        if parts.path == baseURL.appendingPathComponent(Self.prefix + "history").path {
            guard query.count == 1 || query.count == 2, query.last == URLQueryItem(name: "limit", value: "30") else { return nil }
            if query.count == 2 {
                guard query[0].name == "before", let before = query[0].value, RoamPassportHistoryContract.isSessionID(before) else { return nil }
                route = .history(before: before)
            } else { route = .history(before: nil) }
        } else if parts.path == baseURL.appendingPathComponent(Self.prefix + "record").path {
            guard query.count == 1, query[0].name == "sessionId", let id = query[0].value,
                  RoamPassportHistoryContract.isSessionID(id) else { return nil }
            route = .record(sessionID: id)
        } else if parts.path == baseURL.appendingPathComponent(Self.prefix + "summary").path {
            guard parts.query == nil else { return nil }; route = .summary
        } else { return nil }
        guard let expected = try? route.request(baseURL: baseURL, token: "synthetic"),
              expected.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true else { return nil }
        self = route
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard (200..<300).contains(response.1) else { return }
        guard let code = try? JSONDecoder().decode(RoamPassportHistoryStatus.self, from: response.0).code else { throw APIError.malformedResponse }
        guard code == 200 else { return }
        _ = try decode(response.0)
    }
    fileprivate func decode(_ data: Data) throws -> RoamPassportHistoryResponse {
        do {
            switch self {
            case .history(let before):
                let value = try JSONDecoder().decode(RoamPassportHistoryEnvelope<RoamPassportHistoryPage>.self, from: data).data
                try value.validate(before: before); return .history(value)
            case .record(let id):
                let value = try JSONDecoder().decode(RoamPassportHistoryEnvelope<RoamPassportHistoryFact>.self, from: data).data
                guard value.sessionID == id else { throw APIError.malformedResponse }; return .record(value)
            case .summary:
                return .summary(try JSONDecoder().decode(RoamPassportHistoryEnvelope<RoamPassportServerSummary>.self, from: data).data)
            }
        } catch { throw APIError.malformedResponse }
    }
}
private struct RoamPassportHistoryStatus: Decodable { let code: Int }
private struct RoamPassportHistoryEnvelope<Value: Decodable>: Decodable { let data: Value }
fileprivate enum RoamPassportHistoryResponse {
    case history(RoamPassportHistoryPage), record(RoamPassportHistoryFact), summary(RoamPassportServerSummary)
}
public struct RoamPassportHistoryService {
    public let deployment: URL
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) { deployment = configuration.baseURL; self.transport = transport }
    fileprivate func read(_ route: RoamPassportHistoryReadRoute, token: String) async throws -> RoamPassportHistoryResponse {
        let request = try route.request(baseURL: deployment, token: token)
        try Task.checkCancellation()
        let response = try await transport.send(request)
        try Task.checkCancellation()
        if response.1 == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(response.1) else { throw APIError.httpStatus(response.1) }
        guard let code = try? JSONDecoder().decode(RoamPassportHistoryStatus.self, from: response.0).code else { throw APIError.malformedResponse }
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.businessCode(code) }
        return try route.decode(response.0)
    }
}
@MainActor public protocol RoamPassportHistoryReading: AnyObject {
    var identity: RoamExperienceIdentity? { get }
    var scope: UUID { get }
    var isConfigured: Bool { get }
    func page(before: String?) async throws -> RoamPassportHistoryPage
    func record(sessionID: String) async throws -> RoamPassportHistoryFact
    func summary() async throws -> RoamPassportServerSummary
}
@MainActor public final class RoamPassportHistoryReader: RoamPassportHistoryReading {
    private let service: RoamPassportHistoryService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> RoamPassportHistoryReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedContext: RuntimeDependencyContext?
    private var observedViewer: UInt64?
    private var observedAccess: UUID?
    private var stamp = UUID()
    public init(service: RoamPassportHistoryService?, current: @escaping () -> RuntimeDependencyContext?,
                viewerRevision: @escaping () -> UInt64, access: @escaping (RuntimeDependencyContext) -> RoamPassportHistoryReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.service = service; self.current = current; self.viewerRevision = viewerRevision
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var identity: RoamExperienceIdentity? {
        guard let context = current(), let scope = try? RoamHistoryScope(market: context.market.rawValue,
            deployment: context.baseURL, accountID: context.session.accountID, namespace: context.session.namespace) else { return nil }
        return .init(scope: scope, epoch: context.session.epoch)
    }
    public var isConfigured: Bool {
        guard let context = current(), let service, synchronize() != nil else { return false }
        return service.deployment.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8)
    }
    public var scope: UUID { _ = synchronize(); return stamp }
    private func synchronize() -> RoamPassportHistoryReadAccess? {
        let context = current(), viewer = viewerRevision()
        let selected = context.flatMap { value in selectAccess(value).flatMap { $0.matches(value) ? $0 : nil } }
        let same: Bool
        if let old = observedContext, let context { same = ContentDraftContextFence.matches(old, context) }
        else { same = observedContext == nil && context == nil }
        if !same || viewer != observedViewer || selected?.revision != observedAccess {
            observedContext = context; observedViewer = viewer; observedAccess = selected?.revision; stamp = UUID()
        }
        return selected
    }
    private func read(_ route: RoamPassportHistoryReadRoute) async throws -> RoamPassportHistoryResponse {
        try Task.checkCancellation()
        guard let context = current() else { throw APIError.unauthorized }
        guard let selected = synchronize(), let service,
              service.deployment.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) else { throw APIError.notConfigured }
        let capturedScope = stamp, viewer = viewerRevision()
        func valid() -> Bool {
            guard !Task.isCancelled, let fresh = current(), ContentDraftContextFence.matches(context, fresh), viewerRevision() == viewer else { return false }
            return synchronize() === selected && stamp == capturedScope
        }
        guard valid() else { throw CancellationError() }
        do {
            let result = try await service.read(route, token: context.session.token)
            guard valid() else { throw CancellationError() }; return result
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(context) }
            throw error
        }
    }
    public func page(before: String?) async throws -> RoamPassportHistoryPage {
        guard case .history(let value) = try await read(.history(before: before)) else { throw APIError.malformedResponse }; return value
    }
    public func record(sessionID: String) async throws -> RoamPassportHistoryFact {
        guard case .record(let value) = try await read(.record(sessionID: sessionID)) else { throw APIError.malformedResponse }; return value
    }
    public func summary() async throws -> RoamPassportServerSummary {
        guard case .summary(let value) = try await read(.summary) else { throw APIError.malformedResponse }; return value
    }
}
