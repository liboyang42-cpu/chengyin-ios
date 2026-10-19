import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program pages/talent/list `loadImUnread`: POST /api/im/unread-total, no
/// fields, `data` is the server total (muted and group rows already excluded by
/// ImServiceImpl.unreadTotal). Failure is silent in the source: no badge.
public struct IMUnreadTotalService {
    public static let path = "api/im/unread-total"
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let enabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabledPaths: Set<String>) {
        self.configuration = configuration; self.transport = transport; enabled = enabledPaths.contains(Self.path)
    }
    public var isConfigured: Bool { enabled }
    public func total(token: String) async throws -> Int {
        guard enabled else { throw APIError.notConfigured }
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(Self.path), fields: [:], token: token)
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status) }
        return try Self.decode(data)
    }
    public static func decode(_ data: Data) throws -> Int {
        struct Envelope: Decodable { let code: Int; let data: Int? }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw APIError.malformedResponse }
        guard envelope.code == 200 else { throw MessagingReadFailure(code: envelope.code) }
        // Source falls back `res.data || 0`; a negative total is not a count.
        let total = envelope.data ?? 0
        guard total >= 0 else { throw APIError.malformedResponse }
        return total
    }
}

@MainActor public protocol IMUnreadTotalReading: AnyObject {
    var identity: MessagingReadIdentity? { get }
    var isConfigured: Bool { get }
    func unreadTotal() async throws -> Int
}

@MainActor public final class IMUnreadTotalReader: IMUnreadTotalReading {
    private let service: IMUnreadTotalService?
    private let session: () -> IMSafetySession?
    public init(service: IMUnreadTotalService?, session: @escaping () -> IMSafetySession?) {
        self.service = service; self.session = session
    }
    public var identity: MessagingReadIdentity? { session()?.identity }
    public var isConfigured: Bool { service?.isConfigured == true }
    public func unreadTotal() async throws -> Int {
        guard let service, service.isConfigured else { throw APIError.notConfigured }
        guard let snapshot = session() else { throw APIError.unauthorized }
        let total = try await snapshot.withToken { try await service.total(token: $0) }
        guard session() == snapshot, !Task.isCancelled else { throw CancellationError() }
        return total
    }
}
