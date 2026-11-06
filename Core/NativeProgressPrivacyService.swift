import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public final class NativeProgressPrivacyService {
    public let target: NativeProgressPrivacyTarget
    public var actorID: Int64 { Int64(context.session.accountID) }
    private let context: RuntimeDependencyContext
    private let approval: NativeProgressPrivacyApproval
    private let current: () -> RuntimeDependencyContext?
    private let currentApproval: () -> NativeProgressPrivacyApproval?
    private let channelCurrent: () -> Bool
    private let transport: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    public var isCurrent: Bool {
        guard !retired, current() == context, currentApproval() == approval, channelCurrent(), Date() < approval.expiresAt else { retired = true; return false }
        return true
    }
    public var canWrite: Bool { isCurrent && approval.allowsWrite }
    public init(context: RuntimeDependencyContext, approval: NativeProgressPrivacyApproval, target: NativeProgressPrivacyTarget,
                transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                currentApproval: @escaping () -> NativeProgressPrivacyApproval?, channelCurrent: @escaping () -> Bool,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) throws {
        guard context.market == .china, approval.target == target, approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              target.kind != .user || target.id == Int64(context.session.accountID), Date() < approval.expiresAt, channelCurrent() else { throw NativeProgressPrivacyFailure.closed }
        self.context = context; self.approval = approval; self.target = target; self.transport = transport
        self.current = current; self.currentApproval = currentApproval; self.channelCurrent = channelCurrent; self.onUnauthorized = onUnauthorized
    }
    public func read() async throws -> NativeProgressPrivacySnapshot {
        let value: NativeProgressPrivacySnapshot = try await send(path: target.path, method: "GET")
        try value.validate(actor: actorID, target: target); return value
    }
    public func write(_ command: NativeProgressPrivacyCommand) async throws -> NativeProgressPrivacyReceipt {
        guard canWrite, command.target == target else { throw NativeFriendFailure.notSent }
        return try await send(path: target.path, method: "POST", body: command.body())
    }
    /// Same-account proof can be recovered from USER settings after the original channel grant is revoked.
    public func receipt(_ requestID: UUID) async throws -> NativeProgressPrivacyReceipt {
        try await send(path: NativeProgressPrivacyApproval.receiptPath, method: "GET", requestID: requestID)
    }
    private func send<T: Decodable>(path: String, method: String, body: Data? = nil, requestID: UUID? = nil) async throws -> T {
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.notSent }
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let requestID { parts.queryItems = [URLQueryItem(name: "request_id", value: requestID.uuidString)] }
        guard let url = parts.url else { throw NativeFriendFailure.notSent }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method; request.httpBody = body; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard NativeProgressPrivacyTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
        let (bytes, status) = try await transport.send(request)
        guard isCurrent, !Task.isCancelled else { throw NativeProgressPrivacyFailure.unknown }
        guard bytes.count <= 32_768 else { throw NativeProgressPrivacyFailure.malformed }
        let header = try? JSONDecoder().decode(Header.self, from: bytes)
        let code = (200..<300).contains(status) ? header?.code ?? status : status
        if code == 401 { retired = true; onUnauthorized(context) }
        if code == 403 || code == 404 { retired = true }
        guard (200..<300).contains(status), header?.code == 200 else { throw NativeProgressPrivacyFailure.server(code) }
        return try JSONDecoder().decode(Envelope<T>.self, from: bytes).data
    }
    private struct Header: Decodable { let code: Int }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
}
public enum NativeProgressPrivacyTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeProgressPrivacyApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              now < approval.expiresAt, approval.target.kind != .user || approval.target.id == Int64(context.session.accountID),
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        if origin.url == context.baseURL.appendingPathComponent(NativeProgressPrivacyApproval.receiptPath) {
            let items = parts.queryItems ?? []
            return request.httpMethod == "GET" && request.httpBody == nil && items.count == 1 && items[0].name == "request_id" && items[0].value.flatMap(UUID.init(uuidString:)) != nil
        }
        guard origin.url == context.baseURL.appendingPathComponent(approval.target.path), parts.query == nil else { return false }
        if request.httpMethod == "GET" { return request.httpBody == nil }
        guard request.httpMethod == "POST", approval.allowsWrite, let body = request.httpBody, body.count <= 2_048,
              let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(fields.keys) == ["request_id", "aggregate_scope", approval.target.kind == .user ? "expected_updated_at" : "expected_revision"],
              let requestID = fields["request_id"] as? String, UUID(uuidString: requestID)?.uuidString == requestID,
              let aggregate = fields["aggregate_scope"] as? String, NativeProgressPrivacyScope(rawValue: aggregate) != nil else { return false }
        if approval.target.kind == .user { return fields["expected_updated_at"] is NSNull || (fields["expected_updated_at"] as? String).map(NativeProgressPrivacyValidation.timestamp) == true }
        guard let value = fields["expected_revision"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
              value.doubleValue.rounded() == value.doubleValue, value.int64Value >= 0, value.int64Value < Int64(Int32.max) else { return false }
        return true
    }
}
