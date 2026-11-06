import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol PersonalLocationShareTransport: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
/// Ephemeral, no cookies, no disk cache, no redirects to another origin, no request logging.
@MainActor public final class PersonalLocationShareURLTransport: PersonalLocationShareTransport {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PersonalLocationShareFailure.invalidContract }
        return (data, http)
    }
}
@MainActor public final class PersonalLocationShareHTTPService: PersonalLocationShareServicing {
    private struct ErrorEnvelope: Decodable { let code: Int; let errorCode: String? }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T?; let errorCode: String? }
    public let scope: PersonalLocationShareScope
    public let isSynthetic = false
    private let baseURL: URL
    private let transport: any PersonalLocationShareTransport
    private let current: () -> PersonalLocationShareScope?
    private let token: () -> String?
    private let readApproval: () -> PersonalLocationShareEndpointApproval?
    private let writeApproval: () -> PersonalLocationShareEndpointApproval?
    private let isCurrentService: () -> Bool
    private let authorizationGeneration: () -> UInt64
    private let onAuthorizationFailure: (PersonalLocationShareFailure) -> Void
    public init(baseURL: URL, scope: PersonalLocationShareScope, transport: any PersonalLocationShareTransport,
                current: @escaping () -> PersonalLocationShareScope?, token: @escaping () -> String?,
                readApproval: @escaping () -> PersonalLocationShareEndpointApproval? = { nil },
                writeApproval: @escaping () -> PersonalLocationShareEndpointApproval? = { nil },
                isCurrentService: @escaping () -> Bool = { true },
                authorizationGeneration: @escaping () -> UInt64 = { 0 },
                onAuthorizationFailure: @escaping (PersonalLocationShareFailure) -> Void = { _ in }) {
        self.baseURL = baseURL; self.scope = scope; self.transport = transport; self.current = current; self.token = token
        self.readApproval = readApproval; self.writeApproval = writeApproval; self.onAuthorizationFailure = onAuthorizationFailure
        self.isCurrentService = isCurrentService; self.authorizationGeneration = authorizationGeneration
    }
    private func check(_ operation: PersonalLocationShareOperation) throws -> String {
        guard isCurrentService(), current() == scope, let token = token(), !token.isEmpty else { throw PersonalLocationShareFailure.staleSession }
        let approval = operation.isRead ? readApproval() : writeApproval()
        guard approval?.permits(operation, baseURL: baseURL) == true else {
            throw operation.isRead ? PersonalLocationShareFailure.unapprovedRead : PersonalLocationShareFailure.unapprovedWrite
        }
        return token
    }
    private func send<T: Decodable>(_ operation: PersonalLocationShareOperation, path: String,
                                    query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        let credential = try check(operation)
        let requestGeneration = authorizationGeneration() // Before constructing/using any transport request.
        guard baseURL.scheme == "https" else { throw PersonalLocationShareFailure.invalidContract }
        var parts = URLComponents(url: baseURL.appendingPathComponent("api/location-share/personal").appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { parts?.queryItems = query }
        guard let url = parts?.url else { throw PersonalLocationShareFailure.invalidContract }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = operation.isRead ? "GET" : "POST"
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try Task.checkCancellation()
        let result: (Data, HTTPURLResponse)
        do { result = try await transport.data(for: request) }
        catch {
            // URLSession may throw on cancellation instead of returning a response. The old request
            // still has to cross its identity/lease fence before its caller may handle that error.
            try validateResponseLease(credential: credential, generation: requestGeneration)
            throw error
        }
        try validateResponseLease(credential: credential, generation: requestGeneration)
        let (data, response) = result
        guard response.url == url else { throw PersonalLocationShareFailure.unknownOutcome }
        // Current terminal auth wins cancellation and malformed JSON; retired auth never reaches the callback.
        if response.statusCode == 401 || response.statusCode == 403 {
            let failure = PersonalLocationShareFailure.authorizationRejected(status: response.statusCode,
                errorCode: Self.machineError(data, status: response.statusCode))
            onAuthorizationFailure(failure) // MainActor synchronous stop/cache retirement, before any throw/await.
            throw failure
        }
        try Task.checkCancellation()
        guard try check(operation) == credential else { throw PersonalLocationShareFailure.staleSession }
        guard response.statusCode == 200 else {
            if let code = Self.machineError(data, status: response.statusCode) { throw PersonalLocationShareFailure.server(code) }
            throw PersonalLocationShareFailure.unknownOutcome
        }
        guard let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { throw PersonalLocationShareFailure.unknownOutcome }
        guard envelope.code == 200, let value = envelope.data else {
            if envelope.code == 401 || envelope.code == 403 {
                let failure = PersonalLocationShareFailure.authorizationRejected(status: envelope.code,
                    errorCode: Self.machineError(data, status: envelope.code))
                onAuthorizationFailure(failure); throw failure
            }
            throw PersonalLocationShareFailure.server(Self.machineError(data, status: envelope.code) ?? "REQUEST_REJECTED")
        }
        return value
    }
    private func validateResponseLease(credential: String, generation: UInt64) throws {
        guard isCurrentService(), current() == scope, token() == credential else { throw PersonalLocationShareFailure.staleSession }
        guard authorizationGeneration() == generation else { throw PersonalLocationShareFailure.retiredResponse }
    }
    private static func machineError(_ data: Data, status: Int) -> String? {
        // This is a parser/security bound, never a duration, precision or other business-policy default.
        guard (400...599).contains(status), data.count <= 65_536,
              let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data), envelope.code == status,
              let code = envelope.errorCode, code.range(of: "^[A-Z][A-Z0-9_]{0,63}$", options: .regularExpression) != nil else { return nil }
        return code // msg is never decoded, displayed, retained or logged.
    }
    private func validKey(_ value: String) throws { guard UUID(uuidString: value) != nil else { throw PersonalLocationShareFailure.invalidContract } }
    public func context(recipientId: Int64) async throws -> PersonalLocationShareContext {
        guard recipientId > 0, recipientId != scope.accountId else { throw PersonalLocationShareFailure.ineligible }
        return try await send(.context, path: "context", query: [.init(name: "recipientId", value: String(recipientId))])
    }
    public func create(_ request: PersonalLocationShareCreate) async throws -> PersonalLocationShareReceipt {
        try validKey(request.requestKey)
        return try await send(.create, path: "grants", body: JSONEncoder().encode(request))
    }
    public func requestStatus(requestKey: String) async throws -> PersonalLocationShareReceipt {
        try validKey(requestKey); return try await send(.requestStatus, path: "requests/\(requestKey)")
    }
    public func revoke(requestKey: String) async throws -> PersonalLocationShareReceipt {
        try validKey(requestKey); return try await send(.revoke, path: "requests/\(requestKey)/revoke", body: Data("{}".utf8))
    }
    public func owned() async throws -> PersonalLocationShareOwned { try await send(.owned, path: "owned") }
    public func received() async throws -> PersonalLocationShareSnapshot { try await send(.received, path: "received") }
    public func events(cursor: Int64) async throws -> PersonalLocationShareEventBatch {
        guard cursor >= 0 else { throw PersonalLocationShareFailure.invalidContract }
        return try await send(.events, path: "received/events", query: [.init(name: "cursor", value: String(cursor))])
    }
    public func publish(grantId: String, observation: PersonalLocationSharePublish, synthetic: Bool) async throws -> PersonalLocationSharePublished {
        guard !synthetic else { throw PersonalLocationShareFailure.syntheticTransportForbidden }
        try validKey(grantId)
        guard observation.valid else { throw PersonalLocationShareFailure.invalidContract }
        return try await send(.publish, path: "grants/\(grantId)/observations", body: JSONEncoder().encode(observation))
    }
}
