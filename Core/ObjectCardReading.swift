import Foundation

public struct ObjectCardService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    /// Source intentionally returns latest 40 in each category, not unlimited history.
    /// Owner is derived exclusively from JWT, never a caller-supplied user ID.
    public func list(category: ObjectCardCategory, token: String) async throws -> ObjectCardCollection {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent("api/object-card/list"),
            fields: [:], token: token, includesBody: false)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encodedCategory = category.rawValue.addingPercentEncoding(withAllowedCharacters: allowed) else { throw APIError.invalidRequest }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = false
        request.httpBody = Data("pageNum=1&pageSize=40&category=\(encodedCategory)".utf8)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw APIError.malformedResponse }
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        guard let value = envelope.data else { throw APIError.malformedResponse }
        return value
    }
    private struct Envelope: Decodable {
        let code: Int
        let data: ObjectCardCollection?
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? c.decode(Int.self, forKey: .code) { code = value }
            else if let value = Int(try c.decode(String.self, forKey: .code)) { code = value }
            else { throw APIError.malformedResponse }
            data = code == 200 ? try c.decode(ObjectCardCollection.self, forKey: .data) : nil
        }
    }
}
public struct ObjectCardSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol ObjectCardReading: AnyObject {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    func list(category: ObjectCardCategory) async throws -> ObjectCardCollection
}
@MainActor public final class ObjectCardSessionReader: ObjectCardReading {
    private let serviceProvider: () -> ObjectCardService?
    private let currentSession: () -> ObjectCardSession?
    private let currentContext: () -> RuntimeDependencyContext?
    private let requiresContext: Bool
    private var contextSnapshot: RuntimeDependencyContext?
    private let onUnauthorized: (ObjectCardSession) -> Void
    private var snapshot: ObjectCardSession?
    private var stamp = UUID()
    public var isConfigured: Bool { (!requiresContext || currentContext() != nil) && serviceProvider() != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var scope: UUID {
        let current = currentSession(), context = currentContext()
        if current != snapshot || context != contextSnapshot {
            snapshot = current; contextSnapshot = context; stamp = UUID()
        }
        return stamp
    }
    public init(service: ObjectCardService?, currentSession: @escaping () -> ObjectCardSession?,
                onUnauthorized: @escaping (ObjectCardSession) -> Void = { _ in }) {
        self.serviceProvider = { service }; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        self.currentContext = { nil }; self.requiresContext = false; contextSnapshot = nil
        snapshot = currentSession()
    }
    /// Resolve approval per request so a lazy reader first opened while signed out can
    /// later bind the current session without retaining a previous account's transport.
    public init(serviceProvider: @escaping () -> ObjectCardService?, currentSession: @escaping () -> ObjectCardSession?,
                currentContext: @escaping () -> RuntimeDependencyContext?,
                onUnauthorized: @escaping (ObjectCardSession) -> Void = { _ in }) {
        self.serviceProvider = serviceProvider; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        self.currentContext = currentContext; self.requiresContext = true; contextSnapshot = currentContext()
        snapshot = currentSession()
    }
    public func list(category: ObjectCardCategory) async throws -> ObjectCardCollection {
        guard let session = currentSession() else { throw APIError.unauthorized }
        let context = currentContext()
        guard !requiresContext || context != nil else { throw APIError.notConfigured }
        guard let service = serviceProvider() else { throw APIError.notConfigured }
        let captured = scope
        do {
            let result = try await service.list(category: category, token: session.token)
            // This MainActor fence is after the nonisolated service has decoded. A
            // transport-only check leaves a window for role/realm changes and old 401s.
            try Task.checkCancellation()
            guard currentContext() == context, currentSession() == session, scope == captured else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, currentContext() == context, currentSession() == session, scope == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
