import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Marker for the injected offline DEBUG harness transport. Never a production capability.
public protocol PlayStoreDayOfflineTransport: HTTPTransport {}

public struct PlayStoreDaySession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
public enum PlayStoreDayFailure: Error, Equatable {
    case unavailable, staleSession, signedOut, malformed, failed
    case rejected(String?)
}
/// Source request(): 2xx code 200 confirmed; 5xx/408/no response unknown (readback only); else definite rejection.
public enum PlayStoreDayWriteOutcome: Equatable {
    case confirmed(message: String?, data: PlayWireValue)
    case rejected(String?)
    case unknown
}

/// Store-day page endpoints exactly as pages/play/merchant: GET api/play/nodes, POST api/play/checkin,
/// api/play/photo, api/play/answer (form) and POST api/compliance/consents(/latest) (JSON).
@MainActor public final class PlayStoreDayService {
    public enum Execution: Equatable { case disabled, injectedOfflineHarness }
    public static let nodesPath = "api/play/nodes"
    public static let checkinPath = "api/play/checkin"
    public static let photoPath = "api/play/photo"
    public static let answerPath = "api/play/answer"
    public static let consentLatestPath = "api/compliance/consents/latest"
    public static let consentWritePath = "api/compliance/consents"
    private let configuration: APIConfiguration?
    private let transport: any HTTPTransport
    private let market: RegionalMarket
    private let gates: MerchantCityNPCParityGates
    private let execution: Execution
    private let readsEnabled: Bool
    private let currentSession: () -> PlayStoreDaySession?
    private let onUnauthorized: (PlayStoreDaySession) -> Void
    public init(configuration: APIConfiguration?, transport: any HTTPTransport, market: RegionalMarket,
                gates: MerchantCityNPCParityGates = .disabled, execution: Execution = .disabled, readsEnabled: Bool = false,
                currentSession: @escaping () -> PlayStoreDaySession?, onUnauthorized: @escaping (PlayStoreDaySession) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport; self.market = market; self.gates = gates
        self.execution = execution; self.readsEnabled = readsEnabled; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    private var offline: Bool { execution == .injectedOfflineHarness && transport is any PlayStoreDayOfflineTransport }
    public var isConfigured: Bool { configuration != nil }
    public var permitsReads: Bool { configuration != nil && (readsEnabled || offline) }
    public var permitsProofWrites: Bool {
        guard configuration != nil else { return false }
        if offline { return true }
        return gates.storeDayProofWrites && [Self.checkinPath, Self.photoPath, Self.answerPath].allSatisfy { gates.allows($0, market: market) }
    }
    public var permitsConsentWrites: Bool {
        guard configuration != nil else { return false }
        if offline { return true }
        return gates.storeDayConsentWrites && gates.allows(Self.consentWritePath, market: market)
    }
    public var session: PlayStoreDaySession? { currentSession() }

    // MARK: Reads
    /// Authoritative row for one node; nil when the current nodes response no longer lists it.
    public func node(scope: PlaySessionScope, nodeID: Int) async throws -> PlayStoreDayNode? {
        guard permitsReads else { throw PlayStoreDayFailure.unavailable }
        guard scope.isValid, nodeID > 0, let session = currentSession() else { throw PlayStoreDayFailure.staleSession }
        let request = try makeRequest(Self.nodesPath, query: scope.fields, session: session)
        let (bytes, status) = try await transport.send(request)
        try ensure(session)
        if status == 401 { onUnauthorized(session); throw PlayStoreDayFailure.signedOut }
        guard (200..<300).contains(status) else { throw PlayStoreDayFailure.failed }
        let envelope = try decodeEnvelope(bytes)
        if envelope.code == 401 { onUnauthorized(session); throw PlayStoreDayFailure.signedOut }
        guard envelope.code == 200 else { throw PlayStoreDayFailure.rejected(envelope.message) }
        let rows = envelope.data["nodes"].array ?? envelope.data.array ?? []
        return rows.first { $0["nodeId"].tolerantInteger == nodeID }.flatMap(PlayStoreDayNode.init(row:))
    }
    public func latestConsent(merchantID: Int) async throws -> ComplianceConsent? {
        guard permitsReads else { throw PlayStoreDayFailure.unavailable }
        guard merchantID > 0, let session = currentSession() else { throw PlayStoreDayFailure.staleSession }
        let request = try makeJSONRequest(Self.consentLatestPath, body: PlayStoreDayConsent.subject(merchantID: merchantID).fields(), session: session)
        let (bytes, status) = try await transport.send(request)
        try ensure(session)
        if status == 401 { onUnauthorized(session); throw PlayStoreDayFailure.signedOut }
        guard (200..<300).contains(status) else { throw PlayStoreDayFailure.failed }
        let envelope = try decodeEnvelope(bytes)
        guard envelope.code == 200 else { throw PlayStoreDayFailure.rejected(envelope.message) }
        guard let object = envelope.data.object, !object.isEmpty, object["eventType"]?.text != nil else { return nil }
        do { return try envelope.data.decoded(ComplianceConsent.self) } catch { throw PlayStoreDayFailure.malformed }
    }

    // MARK: Writes (dispatched only when permitted; never retried here)
    public func checkin(scope: PlaySessionScope, code: String) async -> PlayStoreDayWriteOutcome {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected(nil) }
        // Source merchant page sends session + code only; the code resolves the node server-side.
        return await proofWrite(Self.checkinPath, scope: scope, fields: ["code": trimmed])
    }
    public func photo(scope: PlaySessionScope, nodeID: Int, pictureURL: String) async -> PlayStoreDayWriteOutcome {
        guard nodeID > 0, let url = URL(string: pictureURL), url.scheme == "https", url.host?.isEmpty == false else { return .rejected(nil) }
        return await proofWrite(Self.photoPath, scope: scope, fields: ["nodeId": String(nodeID), "picUrl": pictureURL])
    }
    public func answer(scope: PlaySessionScope, nodeID: Int, answer: String) async -> PlayStoreDayWriteOutcome {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nodeID > 0, !trimmed.isEmpty else { return .rejected(nil) }
        return await proofWrite(Self.answerPath, scope: scope, fields: ["nodeId": String(nodeID), "answer": trimmed])
    }
    public func consent(merchantID: Int, event: ComplianceEvent, requestID: String) async -> PlayStoreDayWriteOutcome {
        guard permitsConsentWrites, merchantID > 0, !requestID.isEmpty, requestID.count <= 64,
              let session = currentSession(), var body = try? PlayStoreDayConsent.subject(merchantID: merchantID).fields() else { return .rejected(nil) }
        body["eventType"] = event.rawValue; body["requestId"] = requestID
        guard let request = try? makeJSONRequest(Self.consentWritePath, body: body, session: session) else { return .rejected(nil) }
        return await dispatch(request, session: session)
    }
    private func proofWrite(_ path: String, scope: PlaySessionScope, fields: [String: String]) async -> PlayStoreDayWriteOutcome {
        guard permitsProofWrites, scope.isValid, let session = currentSession(), let configuration else { return .rejected(nil) }
        let all = scope.fields.merging(fields) { _, new in new }
        guard let request = try? AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: all, token: session.token) else { return .rejected(nil) }
        return await dispatch(request, session: session)
    }
    private func dispatch(_ request: URLRequest, session: PlayStoreDaySession) async -> PlayStoreDayWriteOutcome {
        let response: (Data, Int)
        do { response = try await transport.send(request) } catch { return .unknown }
        let (bytes, status) = response
        guard currentSession() == session else { return .unknown }
        if status == 401 { onUnauthorized(session); return .rejected(nil) }
        if status >= 500 || status == 408 { return .unknown }
        guard (200..<300).contains(status), let envelope = try? decodeEnvelope(bytes) else { return (200..<300).contains(status) ? .unknown : .rejected(nil) }
        return envelope.code == 200 ? .confirmed(message: envelope.message, data: envelope.data) : .rejected(envelope.message)
    }

    // MARK: Plumbing
    private struct Envelope { let code: Int; let message: String?; let data: PlayWireValue }
    private func decodeEnvelope(_ bytes: Data) throws -> Envelope {
        guard let root = try? JSONDecoder().decode(PlayWireValue.self, from: bytes), let code = root["code"].tolerantInteger else { throw PlayStoreDayFailure.malformed }
        return Envelope(code: code, message: root["msg"].text, data: root["data"])
    }
    private func ensure(_ session: PlayStoreDaySession) throws {
        guard !Task.isCancelled, currentSession() == session else { throw PlayStoreDayFailure.staleSession }
    }
    private func makeRequest(_ path: String, query: [String: String], session: PlayStoreDaySession) throws -> URLRequest {
        guard let configuration, var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw PlayStoreDayFailure.unavailable }
        components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        guard let url = components.url else { throw PlayStoreDayFailure.malformed }
        var request = URLRequest(url: url); request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue(session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    /// Compliance endpoints are @RequestBody: JSON with an explicit Content-Type.
    private func makeJSONRequest(_ path: String, body: [String: Any], session: PlayStoreDaySession) throws -> URLRequest {
        guard let configuration else { throw PlayStoreDayFailure.unavailable }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path)); request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue(session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        return request
    }
}
