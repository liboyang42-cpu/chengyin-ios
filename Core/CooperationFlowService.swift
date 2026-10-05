import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CoopFlowRead: Equatable {
    case invitations, pool, applications, receivedApplications, registrations
    case finance, myBusiness, templates, perks(inviteID: Int), reviewSummary(memberID: Int), credit(memberID: Int?)
    case complaintTopics, relations, clubs(name: String?), nearby(longitude: Double, latitude: Double)
    case depositStatus(inviteID: Int)
    case merchants(name: String?), ownedTopics(kind: CoopFlowTargetKind, scope: String?, page: Int)
    public var path: String {
        switch self {
        case .invitations: return "api/coop/list"; case .pool: return "api/coop/pool/list"
        case .applications: return "api/coop/pool/mine"; case .receivedApplications: return "api/coop/pool/received"
        case .registrations: return "api/coop/candidates/received"
        case .finance: return "api/coop/finance"; case .myBusiness: return "api/coop/mybiz"
        case .templates: return "api/coop/perk-template/list"; case .perks: return "api/coop/perks/list"
        case .reviewSummary: return "api/coop/review/summary"; case .credit: return "api/coop/credit"
        case .complaintTopics: return "api/coop/complaint/topics"; case .relations: return "api/merchant/relation-home"
        case .clubs: return "api/merchant/clubs"; case .nearby: return "api/merchant/nearby"
        case .depositStatus: return "api/coop/deposit/status"
        case .merchants: return "api/club/merchants"
        case .ownedTopics: return "api/topic/list"
        }
    }
    public var expectsArray: Bool { switch self { case .applications, .receivedApplications, .templates, .perks, .complaintTopics, .clubs, .merchants, .nearby: return true; default: return false } }
    public func body() throws -> CoopFlowJSON {
        switch self {
        case .perks(let id), .depositStatus(let id): guard id > 0 else { throw APIError.invalidRequest }; return .object(["inviteId": .id(id)])
        case .reviewSummary(let id): guard id > 0 else { throw APIError.invalidRequest }; return .object(["toId": .id(id)])
        case .credit(let id): if let id { guard id > 0 else { throw APIError.invalidRequest }; return .object(["memberId": .id(id)]) }; return .object([:])
        case .ownedTopics(let kind, let scope, let page):
            guard page > 0, scope == nil || scope == "MERCHANT" else { throw APIError.invalidRequest }
            var fields: [String: CoopFlowJSON] = ["is_my": .string("1"), "invite_target": .string(kind.wire), "pageNum": .string(String(page)), "pageSize": .string("20")]
            if let scope { fields["scope"] = .string(scope) }
            return .object(fields)
        case .clubs(let name), .merchants(let name): return .object(name.map { ["name": .string($0)] } ?? [:])
        case .relations: return .object(["limit": .id(10)])
        case .nearby(let lng, let lat):
            guard lng.isFinite, lat.isFinite, (-180...180).contains(lng), (-90...90).contains(lat) else { throw APIError.invalidRequest }
            return .object(["longitude": .string(String(lng)), "latitude": .string(String(lat)), "radius": .string("5000"), "limit": .string("30")])
        default: return .object([:])
        }
    }
}
public struct CoopFlowSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
public struct CoopFlowService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    /// Not enabled by any shipped UI or configuration. Protected effects have no production execution route.
    private let dormantWritesEnabled: Bool
    private let protectedDispatch: CoopFlowProtectedDispatch?
    var dispatchScope: String { configuration.baseURL.absoluteString }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, dormantWritesEnabled: Bool = false,
                protectedDispatch: CoopFlowProtectedDispatch? = nil) {
        self.configuration = configuration; self.transport = transport; self.dormantWritesEnabled = dormantWritesEnabled
        self.protectedDispatch = protectedDispatch
    }
    public func read(_ resource: CoopFlowRead, session: CoopFlowSession) async throws -> CoopFlowJSON {
        let body = try resource.body()
        var request = try makeRequest(path: resource.path, body: body, session: session)
        let isForm: Bool
        switch resource { case .nearby, .ownedTopics: isForm = true; default: isForm = false }
        if isForm {
            // These source endpoints use multipart; recipient directories require JSON.
            let boundary = "CoopNative-" + UUID().uuidString
            guard case .object(let fields) = body else { throw APIError.invalidRequest }
            let parts = fields.sorted { $0.key < $1.key }.map { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.key)\"\r\n\r\n\($0.value.text ?? "")\r\n" }.joined()
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data((parts + "--\(boundary)--\r\n").utf8)
        }
        let value = try await send(request)
        if resource.expectsArray { guard value.rows != nil else { throw CoopFlowFailure.malformed } }
        else { guard case .object = value else { throw CoopFlowFailure.malformed } }
        switch resource {
        case .finance: guard value["topics"].rows != nil else { throw CoopFlowFailure.malformed }
        case .myBusiness: guard value["settlements"].rows != nil else { throw CoopFlowFailure.malformed }
        case .invitations: guard value["sent"].rows != nil, value["received"].rows != nil else { throw CoopFlowFailure.malformed }
        case .pool, .registrations, .ownedTopics: guard value["rows"].rows != nil else { throw CoopFlowFailure.malformed }
        case .relations: _ = try CoopRelationDiscovery(value)
        default: break
        }
        return value
    }
    public func settlement(source: CoopFlowSettlement.Source, id: Int, session: CoopFlowSession) async throws -> CoopFlowSettlement {
        guard id > 0 else { throw APIError.invalidRequest }
        let value = try await read(source == .finance ? .finance : .myBusiness, session: session)
        guard let rows = value[source == .finance ? "topics" : "settlements"].rows else { throw CoopFlowFailure.malformed }
        let matches = rows.filter { $0[source == .finance ? "topicId" : "id"].integer == id }
        guard !matches.isEmpty else { throw CoopFlowFailure.unavailable }
        guard matches.count == 1 else { throw CoopFlowFailure.conflict }
        return CoopFlowSettlement(source: source, record: matches[0])
    }
    func permitsDispatch(_ operation: CoopFlowMutation) -> Bool {
        guard dormantWritesEnabled else { return false }
        guard operation.requiresSeparateEnablement else { return true }
        return transport is any CoopFlowOfflineHTTPTransport &&
            protectedDispatch?.permits(operation, endpoint: configuration.baseURL) == true
    }
    func perform(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON {
        guard permitsDispatch(operation) else { throw CoopFlowFailure.disabled }
        let result = try await send(makeRequest(path: operation.path, body: operation.body(), session: session))
        switch operation {
        case .contact: guard case .number = result["conversationId"], (result["conversationId"].integer ?? 0) > 0 else { throw CoopFlowFailure.ambiguous }
        case .complaint, .enrollOffer: guard case .object = result else { throw CoopFlowFailure.ambiguous }
        case .createTemplate: guard (result["id"].integer ?? 0) > 0 else { throw CoopFlowFailure.ambiguous }
        case .attachPerks: guard let count = result["count"].integer, count >= 0 else { throw CoopFlowFailure.ambiguous }
        default: break
        }
        return result
    }
    private func makeRequest(path: String, body: CoopFlowJSON, session: CoopFlowSession) throws -> URLRequest {
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: session.token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body.canonical(); return request
    }
    private func send(_ request: URLRequest) async throws -> CoopFlowJSON {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard let envelope = try? JSONDecoder().decode(CoopFlowJSON.self, from: data) else { throw CoopFlowFailure.malformed }
        let code = envelope["code"].integer
        if status == 401 || code == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status), code == 200 else { throw CoopFlowFailure.server(code ?? status, envelope["msg"].text) }
        return envelope["data"]
    }
}
@MainActor public protocol CoopFlowReading: AnyObject {
    var session: CoopFlowSession? { get }
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON
    func read(_ resource: CoopFlowRead, isCurrent: @escaping () -> Bool) async throws -> CoopFlowJSON
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement
}
extension CoopFlowReading {
    public func read(_ resource: CoopFlowRead, isCurrent: @escaping () -> Bool) async throws -> CoopFlowJSON {
        guard isCurrent() else { throw CoopFlowFailure.stale }
        let value = try await read(resource)
        guard !Task.isCancelled, isCurrent() else { throw CoopFlowFailure.stale }
        return value
    }
}
@MainActor public final class CoopFlowSessionReader: CoopFlowReading {
    private let service: CoopFlowService?
    private let current: () -> CoopFlowSession?
    private let unauthorized: (CoopFlowSession) -> Void
    public var session: CoopFlowSession? { current() }
    public init(service: CoopFlowService?, current: @escaping () -> CoopFlowSession?, unauthorized: @escaping (CoopFlowSession) -> Void = { _ in }) {
        self.service = service; self.current = current; self.unauthorized = unauthorized
    }
    public func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON { try await fenced { try await $0.read(resource, session: $1) } }
    public func read(_ resource: CoopFlowRead, isCurrent: @escaping () -> Bool) async throws -> CoopFlowJSON {
        try await fenced(isCurrent: isCurrent) { try await $0.read(resource, session: $1) }
    }
    public func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement {
        try await fenced { try await $0.settlement(source: source, id: id, session: $1) }
    }
    private func fenced<T>(isCurrent: () -> Bool = { true }, _ operation: (CoopFlowService, CoopFlowSession) async throws -> T) async throws -> T {
        guard isCurrent() else { throw CoopFlowFailure.stale }
        guard let session else { throw APIError.unauthorized }; guard let service else { throw APIError.notConfigured }
        do {
            let result = try await operation(service, session)
            try Task.checkCancellation(); guard isCurrent(), current() == session else { throw CoopFlowFailure.stale }; return result
        } catch {
            guard isCurrent(), current() == session, !Task.isCancelled else { throw CoopFlowFailure.stale }
            if error as? APIError == .unauthorized { unauthorized(session) }; throw error
        }
    }
}
