import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Concrete dormant HTTP adapter. Host must inject endpoint, existing token/session access,
/// journal and explicit grants. No production transport or endpoint is constructed here.
@MainActor public final class AccountComplianceService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let journal: any ComplianceJournaling
    private let current: () -> ComplianceSession?
    private let token: () -> String?
    private let readsEnabled: Bool
    private let writesEnabled: Bool
    private let legalApproved: (ComplianceSubject, ComplianceSession) -> Bool
    private let authoritativeMerchantID: () -> Int?
    private let npcChatDataReadApproval: () -> OperationEndpointApproval?
    private var busy = false
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                journal: any ComplianceJournaling, current: @escaping () -> ComplianceSession?,
                token: @escaping () -> String?, readsEnabled: Bool = false, writesEnabled: Bool = false,
                legalApproved: @escaping (ComplianceSubject, ComplianceSession) -> Bool = { _, _ in false },
                authoritativeMerchantID: @escaping () -> Int? = { nil },
                npcChatDataReadApproval: @escaping () -> OperationEndpointApproval? = { nil }) {
        self.configuration = configuration; self.transport = transport; self.journal = journal
        self.current = current; self.token = token; self.readsEnabled = readsEnabled
        self.writesEnabled = writesEnabled; self.legalApproved = legalApproved; self.authoritativeMerchantID = authoritativeMerchantID
        self.npcChatDataReadApproval = npcChatDataReadApproval
    }
    /// Separate, exact read acceptance. Chat/model grants and the existing generic
    /// compliance read/write booleans cannot authorize this private-text endpoint.
    public func canReadNPCChatData(session: ComplianceSession) -> Bool {
        guard session.valid, current() == session, let credential = token(), AuthRequestBuilder.isValidToken(credential),
              let approval = npcChatDataReadApproval() else { return false }
        return approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: NPCChatData.path)
    }
    public func readNPCChatData(session: ComplianceSession) async throws -> NPCChatData {
        guard canReadNPCChatData(session: session), let credential = token(), let approval = npcChatDataReadApproval() else {
            throw NPCChatDataFailure.unavailable
        }
        // Identity comes only from the existing Authorization header. No body,
        // user ID, merchant ID, query filter, model context or new token is sent.
        var outgoing = try request("/" + NPCChatData.path, method: "GET", session: session)
        outgoing.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        outgoing.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard outgoing.value(forHTTPHeaderField: "Authorization") == credential, current() == session,
              npcChatDataReadApproval() == approval, canReadNPCChatData(session: session) else { throw NPCChatDataFailure.staleSession }
        let (bytes, status) = try await transport.send(outgoing)
        try Task.checkCancellation()
        guard current() == session, token() == credential, npcChatDataReadApproval() == approval,
              canReadNPCChatData(session: session) else { throw NPCChatDataFailure.staleSession }
        guard status != 401 else { throw NPCChatDataFailure.signedOut }
        guard (200..<300).contains(status) else { throw NPCChatDataFailure.failed }
        return try NPCChatData.decode(bytes, expectedAccountID: session.accountID)
    }
    public func check(_ session: ComplianceSession) throws {
        guard session.valid, current() == session else { throw ComplianceFailure.staleSession }
        try Task.checkCancellation()
    }
    public func unresolved(_ operation: String, session: ComplianceSession) throws -> CompliancePendingOperation? {
        try check(session); return try journal.pending(scope: session.journalScope, operation: operation)
    }
    private func request(_ path: String, method: String = "POST", body: [String: Any]? = nil,
                         form: [String: String]? = nil, session: ComplianceSession) throws -> URLRequest {
        try check(session)
        guard let token = token(), AuthRequestBuilder.isValidToken(token) else { throw ComplianceFailure.staleSession }
        let url = configuration.baseURL.appendingPathComponent(String(path.dropFirst()))
        if let form { return try AuthRequestBuilder.makeFormRequest(url: url, fields: form, token: token) }
        var request = URLRequest(url: url); request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func send(_ request: URLRequest, session: ComplianceSession) async throws -> Any? {
        try check(session)
        let (data, status) = try await transport.send(request)
        try check(session)
        // HTTP failures are uncertain for mutations. Only a valid business rejection is definite.
        guard (200..<300).contains(status), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = root["code"] as? Int else { throw ComplianceFailure.malformed }
        let message = (root["msg"] as? String) ?? String(code)
        guard code == 200 else { throw ComplianceFailure.rejected(message) }
        return root["data"]
    }
    private func decode<T: Decodable>(_ data: Any?, as type: T.Type) throws -> T {
        guard let data, !(data is NSNull) else { throw ComplianceFailure.malformed }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed))
    }
    private func read(_ path: String, method: String = "POST", body: [String: Any]? = nil, session: ComplianceSession) async throws -> Any? {
        guard readsEnabled else { throw ComplianceFailure.unavailable }
        return try await send(request(path, method: method, body: body, session: session), session: session)
    }
    private func checkScope(_ subject: ComplianceSubject) throws {
        if let id = subject.scopeID, authoritativeMerchantID() != id { throw ComplianceFailure.staleSession }
    }
    public func latest(_ subject: ComplianceSubject, session: ComplianceSession) async throws -> ComplianceConsent? {
        try checkScope(subject)
        let data = try await read("/api/compliance/consents/latest", body: subject.fields(), session: session)
        try checkScope(subject)
        guard let object = data as? [String: Any], !object.isEmpty else { return nil }
        return try decode(object, as: ComplianceConsent.self)
    }
    private func start(_ operation: String, requestID: String, session: ComplianceSession) throws {
        try check(session)
        guard readsEnabled, writesEnabled else { throw ComplianceFailure.unavailable }
        guard !busy else { throw ComplianceFailure.busy }
        guard !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, requestID.count <= 64 else { throw ComplianceFailure.invalidInput }
        try journal.begin(.init(scope: session.journalScope, operation: operation, requestID: requestID, epoch: session.epoch)); busy = true
    }
    private func write(_ request: URLRequest, operation: String, session: ComplianceSession) async throws -> Any? {
        do { return try await send(request, session: session) }
        catch ComplianceFailure.rejected(let message) {
            try journal.resolve(scope: session.journalScope, operation: operation)
            throw ComplianceFailure.rejected(message)
        }
    }
    public func consent(_ subject: ComplianceSubject, event: ComplianceEvent, requestID: String, session: ComplianceSession) async throws -> ComplianceConsent {
        try checkScope(subject)
        if event == .agree, !legalApproved(subject, session) { throw ComplianceFailure.unavailable }
        var fields = try subject.fields(); fields["eventType"] = event.rawValue; fields["requestId"] = requestID
        let request = try request("/api/compliance/consents", body: fields, session: session)
        try start(subject.operation, requestID: requestID, session: session); defer { busy = false }
        _ = try await write(request, operation: subject.operation, session: session)
        guard let result = try await latest(subject, session: session), result.matches(subject, event: event) else { throw ComplianceFailure.readbackMismatch }
        try journal.resolve(scope: session.journalScope, operation: subject.operation)
        return result
    }
    /// Reconcile truth without retrying the mutation; exact scene/scope/event required.
    public func reconcileConsent(_ subject: ComplianceSubject, event: ComplianceEvent, session: ComplianceSession) async throws -> ComplianceConsent {
        guard let record = try await latest(subject, session: session), record.matches(subject, event: event) else { throw ComplianceFailure.readbackMismatch }
        try journal.resolve(scope: session.journalScope, operation: subject.operation); return record
    }
    public func marketing(session: ComplianceSession) async throws -> [ComplianceMarketingConsent] {
        let rows = try decode(await read("/api/merchant/crm/marketing-consents", method: "GET", session: session), as: [ComplianceMarketingConsent].self)
        guard rows.allSatisfy(\.valid) else { throw ComplianceFailure.malformed }; return rows
    }
    public func setMarketing(_ row: ComplianceMarketingConsent, channel: ComplianceMarketingChannel, optedIn: Bool, requestID: String, session: ComplianceSession) async throws -> [ComplianceMarketingConsent] {
        guard row.valid else { throw ComplianceFailure.invalidInput }
        let operation = "marketing|\(row.id)|\(channel.rawValue)"
        let request = try request("/api/merchant/crm/marketing-consents", body: ["merchantRowId": row.merchantRowId, "merchantOwnerMemberId": row.merchantOwnerMemberId, "channel": channel.rawValue, "optedIn": optedIn, "requestId": requestID], session: session)
        try start(operation, requestID: requestID, session: session); defer { busy = false }
        _ = try await write(request, operation: operation, session: session)
        let rows = try await marketing(session: session)
        guard rows.contains(where: { $0.id == row.id && $0.value(channel) == optedIn }) else { throw ComplianceFailure.readbackMismatch }
        try journal.resolve(scope: session.journalScope, operation: operation); return rows
    }
    public func status(session: ComplianceSession) async throws -> ComplianceDeregistration { try decode(await read("/api/user/deregister/status", method: "GET", session: session), as: ComplianceDeregistration.self) }
    public func precheck(session: ComplianceSession) async throws -> ComplianceDeregistration { try decode(await read("/api/user/deregister/precheck", session: session), as: ComplianceDeregistration.self) }
    public func apply(smscode: String, requestID: String, session: ComplianceSession) async throws -> ComplianceDeregistration {
        guard legalApproved(.cancellation, session) else { throw ComplianceFailure.unavailable }
        let request = try request("/api/user/deregister/apply", form: ["smscode": AuthChannelInput.code(smscode), "requestId": requestID], session: session)
        try start("deregister", requestID: requestID, session: session); defer { busy = false }
        let result = try decode(await write(request, operation: "deregister", session: session), as: ComplianceDeregistration.self)
        // Accepted applications retain the original epoch until fresh authentication and status read.
        if result.blocked { try journal.resolve(scope: session.journalScope, operation: "deregister") }
        return result
    }
    public func cancel(session: ComplianceSession) async throws -> ComplianceDeregistration {
        let pending = try unresolved("deregister", session: session)
        if let pending, pending.epoch == session.epoch { throw ComplianceFailure.staleSession }
        let before = try await status(session: session)
        guard before.pending else { throw ComplianceFailure.invalidInput }
        let request = try request("/api/user/deregister/cancel", session: session)
        try start("deregisterCancel", requestID: UUID().uuidString, session: session); defer { busy = false }
        let result = try decode(await write(request, operation: "deregisterCancel", session: session), as: ComplianceDeregistration.self)
        guard result.status == "NORMAL" else { throw ComplianceFailure.readbackMismatch }
        let confirmed = try await status(session: session)
        guard confirmed.status == "NORMAL" else { throw ComplianceFailure.readbackMismatch }
        try journal.resolve(scope: session.journalScope, operation: "deregisterCancel")
        try journal.resolve(scope: session.journalScope, operation: "deregister")
        return confirmed
    }
}
