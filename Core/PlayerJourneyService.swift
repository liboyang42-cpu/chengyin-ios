import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PlayerJourneyFailure: Error, Equatable {
    public let code: Int?
    public let message: String?
}
/// Exact read-only POST contracts; no automatic registration/payment/cancellation writes.
public struct PlayerJourneyService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let readsEnabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, readsEnabled: Bool = false) {
        self.configuration = configuration; self.transport = transport; self.readsEnabled = readsEnabled
    }
    public func participations(token: String) async throws -> [ParticipationRecord] {
        let rows: [ParticipationRecord] = try await read("api/registration/my-joined", token: token)
        guard Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
        return rows
    }
    public func detail(id: Int, token: String) async throws -> ParticipationDetail {
        guard id > 0 else { throw APIError.invalidRequest }
        let result: ParticipationDetail = try await read("api/registration/info", fields: ["id": String(id)], token: token)
        guard result.id == id else { throw APIError.malformedResponse }
        return result
    }
    public func completed(token: String) async throws -> [CompletedPlayRecord] {
        try await read("api/play/my-completed", token: token)
    }
    public func memberTemplate(id: MemberPlayTemplateID, token: String) async throws -> MemberTemplateDetail {
        let result: MemberTemplateDetail = try await read("api/template/myinfo", fields: ["id": String(id.rawValue)], token: token)
        guard result.id == id else { throw APIError.malformedResponse }
        return result
    }
    private func read<Value: Decodable>(_ path: String, fields: [String: String]? = nil, token: String) async throws -> Value {
        guard readsEnabled else { throw APIError.notConfigured }
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path),
            fields: fields ?? [:], token: token, includesBody: fields != nil)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let raw: PlayWireValue
        do { raw = try JSONDecoder().decode(PlayWireValue.self, from: data) }
        catch { throw APIError.malformedResponse }
        let code = raw["code"].tolerantInteger
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw PlayerJourneyFailure(code: code, message: ParticipationRecord.text(raw["msg"])) }
        do { return try raw["data"].decoded(Value.self) }
        catch { throw APIError.malformedResponse }
    }
}
public struct PlayerJourneySession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let namespace: String
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, namespace: String, token: String) throws {
        guard accountID > 0, !namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.namespace = namespace; self.token = token
    }
}
@MainActor public protocol PlayerJourneyReading: AnyObject {
    var scope: UUID { get }
    var isAuthenticated: Bool { get }
    var isConfigured: Bool { get }
    func participations() async throws -> [ParticipationRecord]
    func detail(id: Int) async throws -> ParticipationDetail
    func completed() async throws -> [CompletedPlayRecord]
}
@MainActor public final class PlayerJourneySessionReader: PlayerJourneyReading, MemberTemplateReading {
    private let service: PlayerJourneyService?
    private let currentSession: () -> PlayerJourneySession?
    private let onUnauthorized: (PlayerJourneySession) -> Void
    private var previous: PlayerJourneySession?
    private var stamp = UUID()
    public var scope: UUID { if previous != currentSession() { previous = currentSession(); stamp = UUID() }; return stamp }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isConfigured: Bool { service?.readsEnabled == true }
    public init(service: PlayerJourneyService?, currentSession: @escaping () -> PlayerJourneySession?, onUnauthorized: @escaping (PlayerJourneySession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func participations() async throws -> [ParticipationRecord] { try await read { try await $0.participations(token: $1) } }
    public func detail(id: Int) async throws -> ParticipationDetail { try await read { try await $0.detail(id: id, token: $1) } }
    public func completed() async throws -> [CompletedPlayRecord] { try await read { try await $0.completed(token: $1) } }
    public func memberTemplate(id: MemberPlayTemplateID) async throws -> MemberTemplateDetail {
        try await read { try await $0.memberTemplate(id: id, token: $1) }
    }
    private func read<Value>(_ operation: (PlayerJourneyService, String) async throws -> Value) async throws -> Value {
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        let captured = scope
        do {
            try Task.checkCancellation()
            let result = try await operation(service, session.token)
            guard !Task.isCancelled, currentSession() == session, captured == scope else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, currentSession() == session, captured == scope else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
