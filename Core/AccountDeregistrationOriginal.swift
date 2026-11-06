import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact independent approval. A source/legal notice existing in the bundle never grants a write.
public struct AccountDeregistrationOriginalApproval: Equatable {
    public let endpoint: OperationEndpointApproval
    public let writes: Bool
    public let legalApproved: Bool
    public let issuanceID: UUID
    public init(endpoint: OperationEndpointApproval, writes: Bool = false, legalApproved: Bool = false, issuanceID: UUID) throws {
        guard endpoint.paths == AccountDeregistrationOriginalClient.readPaths.union(writes ? AccountDeregistrationOriginalClient.writePaths : []),
              !writes || legalApproved else { throw APIError.invalidConfiguration }
        self.endpoint = endpoint; self.writes = writes; self.legalApproved = legalApproved; self.issuanceID = issuanceID
    }
    public func matches(_ c: RuntimeDependencyContext) -> Bool {
        c.market == .china && endpoint.baseURL.absoluteString.utf8.elementsEqual(c.baseURL.absoluteString.utf8)
            && endpoint.namespace.utf8.elementsEqual(c.session.namespace.utf8) && endpoint.accountID == c.session.accountID
    }
}
public struct AccountDeregistrationOriginalReceipt: Decodable, Equatable {
    public let receiptVersion: Int, actorId: Int, requestId: String, outcome: String
    public let applicationId: Int?, appliedAt: Int64?, executeAfterAtAcceptance: Int64?, recordedAt: Int64?
    public let reason: String?
    public let impactAtConfirmation: AccountDeregistrationImpact?
    public var accepted: Bool { outcome == "ACCEPTED" }
    public var settled: Bool { ["ACCEPTED", "REJECTED", "EXISTING_APPLICATION"].contains(outcome) }
    public func validate(request: String, actor: Int) throws {
        guard receiptVersion == 1, actorId == actor, requestId.utf8.elementsEqual(request.utf8) else { throw ComplianceFailure.readbackMismatch }
        if accepted {
            guard (applicationId ?? 0) > 0, (appliedAt ?? 0) > 0, (executeAfterAtAcceptance ?? 0) > 0, (recordedAt ?? 0) > 0 else { throw ComplianceFailure.malformed }
        } else {
            guard applicationId == nil, appliedAt == nil, executeAfterAtAcceptance == nil,
                  (outcome == "UNKNOWN" ? recordedAt == nil : (settled && (recordedAt ?? 0) > 0)) else { throw ComplianceFailure.malformed }
        }
    }
}
@MainActor public final class AccountDeregistrationOriginalClient {
    public static let base = "api/user/deregister/"
    public static let readPaths: Set<String> = [base + "status", base + "result"]
    public static let writePaths: Set<String> = [base + "precheck", base + "apply", "api/compliance/consents", "api/compliance/consents/latest"]
    public let context: RuntimeDependencyContext, approval: AccountDeregistrationOriginalApproval
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?, stillApproved: () -> Bool, unauthorized: () -> Void
    private var sent = Set<String>()
    public init(context: RuntimeDependencyContext, approval: AccountDeregistrationOriginalApproval, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, stillApproved: @escaping () -> Bool, onUnauthorized: @escaping () -> Void) {
        self.context = context; self.approval = approval; self.transport = transport; self.current = current
        self.stillApproved = stillApproved; unauthorized = onUnauthorized
    }
    public func matches(_ session: ComplianceSession) -> Bool {
        ContentDraftContextFence.matches(current(), context) && stillApproved() && approval.matches(context) && session.accountID == context.session.accountID
            && session.epoch == context.session.epoch && session.namespace.utf8.elementsEqual(context.session.namespace.utf8) && session.market == "CN"
            && current()?.session.role.utf8.elementsEqual(context.session.role.utf8) == true
            && context.role.utf8.elementsEqual(context.session.role.utf8)
    }
    public static func validUUID(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private func send<T: Decodable>(_ request: URLRequest, session: ComplianceSession, as: T.Type) async throws -> T {
        guard matches(session), Self.accepts(request, context: context, approval: approval) else { throw ComplianceFailure.unavailable }
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        // An old/cancelled/revoked response cannot invalidate a live replacement session.
        try Task.checkCancellation()
        guard matches(session) else { throw ComplianceFailure.staleSession }
        if status == 401 { unauthorized(); throw APIError.unauthorized }
        if status == 403 { throw MerchantBusinessFailure.denied }
        guard data.count <= 2 * 1024 * 1024, let raw = String(data: data, encoding: .utf8), (try? ContentDraftJSON.parse(raw)) != nil else { throw ComplianceFailure.malformed }
        let e = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if e.code == 401 { unauthorized(); throw APIError.unauthorized }
        if e.code == 403 { throw MerchantBusinessFailure.denied }
        guard (200..<300).contains(status), e.code == 200, let value = e.data else { throw ComplianceFailure.unresolved }
        try Task.checkCancellation(); guard matches(session) else { throw ComplianceFailure.staleSession }; return value
    }
    private func request(_ path: String, method: String = "GET", query: [String: String] = [:], body: [String: Any]? = nil) throws -> URLRequest {
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw ComplianceFailure.invalidInput }
        var r = URLRequest(url: url); r.httpMethod = method; r.httpShouldHandleCookies = false
        r.cachePolicy = .reloadIgnoringLocalCacheData; r.timeoutInterval = 20
        r.setValue(context.session.token, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }; return r
    }
    public func status(session: ComplianceSession) async throws -> ComplianceDeregistration { try await send(request(Self.base + "status"), session: session, as: ComplianceDeregistration.self) }
    public func precheck(session: ComplianceSession) async throws -> ComplianceDeregistration { try await send(request(Self.base + "precheck", method: "POST"), session: session, as: ComplianceDeregistration.self) }
    public func consent(requestID: String, session: ComplianceSession, expectedDocumentVersion: String? = nil) async throws -> ComplianceConsent {
        guard Self.validUUID(requestID), let version = expectedDocumentVersion,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ComplianceFailure.invalidInput }
        var fields = try ComplianceSubject.cancellation.fields(); fields["eventType"] = "AGREE"; fields["requestId"] = requestID
        let ack = try await send(request("api/compliance/consents", method: "POST", body: fields), session: session, as: AccountDeregistrationConsentACK.self)
        // Only this POST can confirm this intent. Latest consent is never an original receipt.
        return try ack.confirm(requestID: requestID, displayedVersion: version)
    }
    public func result(_ intent: CompliancePendingOperation, session: ComplianceSession) async throws -> AccountDeregistrationOriginalReceipt {
        guard intent.operation == "deregister", intent.scope == session.journalScope, intent.deregistrationOriginalVersion == 1,
              intent.deregistrationRealm?.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true, Self.validUUID(intent.requestID) else { throw ComplianceFailure.unresolved }
        let receipt = try await send(request(Self.base + "result", query: ["requestId": intent.requestID]), session: session, as: AccountDeregistrationOriginalReceipt.self)
        try receipt.validate(request: intent.requestID, actor: session.accountID)
        if let revision = intent.deregistrationImpactRevision, receipt.accepted {
            guard let impact = receipt.impactAtConfirmation, impact.valid(for: session.accountID), impact.revision.utf8.elementsEqual(revision.utf8) else { throw ComplianceFailure.readbackMismatch }
        }
        return receipt
    }
    public func apply(code: String, intent: CompliancePendingOperation, session: ComplianceSession) async throws {
        guard matches(session), approval.writes, approval.legalApproved, intent.scope == session.journalScope,
              intent.deregistrationOriginalVersion == 1, intent.deregistrationRealm?.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true,
              Self.validUUID(intent.requestID), !sent.contains(intent.requestID) else { throw ComplianceFailure.unavailable }
        guard let revision = intent.deregistrationImpactRevision, AccountDeregistrationImpact.validRevision(revision) else { throw ComplianceFailure.invalidInput }
        let code = try AuthChannelInput.code(code)
        var r = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent(Self.base + "apply"),
            fields: ["smscode": code, "requestId": intent.requestID, "impactRevision": revision], token: context.session.token)
        r.httpShouldHandleCookies = false; r.setValue("1", forHTTPHeaderField: "X-Account-Deregistration-Original")
        sent.insert(intent.requestID)
        _ = try await send(r, session: session, as: MerchantBusinessValue.self) // Response is not a receipt read.
    }
    public static func accepts(_ r: URLRequest, context: RuntimeDependencyContext, approval: AccountDeregistrationOriginalApproval) -> Bool {
        guard approval.matches(context), !r.httpShouldHandleCookies, r.httpBodyStream == nil,
              r.value(forHTTPHeaderField: "Authorization") == context.session.token, r.value(forHTTPHeaderField: "Accept") == "application/json",
              r.value(forHTTPHeaderField: "Cookie") == nil, r.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = r.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil else { return false }
        if r.httpMethod == "GET", r.httpBody == nil {
            if url == context.baseURL.appendingPathComponent(base + "status") { return true }
            guard let query = parts.queryItems, query.count == 1, query[0].name == "requestId", let value = query[0].value, validUUID(value) else { return false }
            parts.query = nil; return parts.url == context.baseURL.appendingPathComponent(base + "result")
        }
        guard approval.writes, approval.legalApproved, r.httpMethod == "POST" else { return false }
        if url == context.baseURL.appendingPathComponent(base + "precheck") { return r.httpBody == nil }
        if url == context.baseURL.appendingPathComponent(base + "apply") {
            guard r.value(forHTTPHeaderField: "X-Account-Deregistration-Original") == "1", let fields = form(r), Set(fields.keys) == ["smscode", "requestId", "impactRevision"],
                  let revision = fields["impactRevision"], AccountDeregistrationImpact.validRevision(revision),
                  let code = fields["smscode"], (try? AuthChannelInput.code(code)) == code,
                  let id = fields["requestId"], validUUID(id) else { return false }; return true
        }
        guard r.value(forHTTPHeaderField: "Content-Type") == "application/json", let data = r.httpBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              object["docType"] == "account_cancellation_notice", object["scene"] == "account_cancel",
              let canonical = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys), canonical == data else { return false }
        if url == context.baseURL.appendingPathComponent("api/compliance/consents/latest") { return Set(object.keys) == ["docType", "scene"] }
        return url == context.baseURL.appendingPathComponent("api/compliance/consents") && Set(object.keys) == ["docType", "scene", "eventType", "requestId"]
            && object["eventType"] == "AGREE" && object["requestId"].map(validUUID) == true
    }
    private static func form(_ r: URLRequest) -> [String: String]? {
        let prefix = "multipart/form-data; boundary="
        guard let type = r.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix), let data = r.httpBody, data.count < 4096,
              let raw = String(data: data, encoding: .utf8), let url = r.url else { return nil }
        let boundary = String(type.dropFirst(prefix.count)), end = "--\(boundary)--\r\n"
        guard raw.hasSuffix(end) else { return nil }
        let chunks = String(raw.dropLast(end.count)).components(separatedBy: "--\(boundary)\r\n")
        guard chunks.first == "" else { return nil }; var fields: [String: String] = [:]
        for chunk in chunks.dropFirst() {
            let heading = "Content-Disposition: form-data; name=\""
            guard chunk.hasPrefix(heading), chunk.hasSuffix("\r\n"), let split = chunk.range(of: "\"\r\n\r\n") else { return nil }
            let key = String(chunk[chunk.index(chunk.startIndex, offsetBy: heading.count)..<split.lowerBound])
            guard fields[key] == nil else { return nil }; fields[key] = String(chunk[split.upperBound...].dropLast(2))
        }
        guard let expected = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields, token: r.value(forHTTPHeaderField: "Authorization"), boundary: boundary), expected.httpBody == data else { return nil }; return fields
    }
}
