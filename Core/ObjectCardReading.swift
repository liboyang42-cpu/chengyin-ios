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
    private let service: ObjectCardService?
    private let currentSession: () -> ObjectCardSession?
    private let onUnauthorized: (ObjectCardSession) -> Void
    private var snapshot: ObjectCardSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var scope: UUID {
        let current = currentSession()
        if current != snapshot { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: ObjectCardService?, currentSession: @escaping () -> ObjectCardSession?,
                onUnauthorized: @escaping (ObjectCardSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func list(category: ObjectCardCategory) async throws -> ObjectCardCollection {
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        let captured = scope
        do {
            let result = try await service.list(category: category, token: session.token)
            try Task.checkCancellation()
            guard currentSession() == session, scope == captured else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, currentSession() == session, scope == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
