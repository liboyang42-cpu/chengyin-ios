import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Consumes the existing exact endpoint approval; never issues paths or channel RBAC.
/// Its presentation closure is a monotonic visit fence shared with the real provider.
@MainActor public final class NativeWebhookFinalForwardTransport: HTTPTransport {
    private let captured: RuntimeDependencyContext
    private let scope: NativeWebhookScope
    private let issued: OperationEndpointApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let approval: () -> OperationEndpointApproval?
    private let presentation: () -> Bool
    private var retired = false
    public init?(captured: RuntimeDependencyContext, scope: NativeWebhookScope,
                 issued: OperationEndpointApproval, underlying: any HTTPTransport,
                 current: @escaping () -> RuntimeDependencyContext?,
                 approval: @escaping () -> OperationEndpointApproval?, presentation: @escaping () -> Bool) {
        guard issued.baseURL.absoluteString.utf8.elementsEqual(captured.baseURL.absoluteString.utf8),
              issued.namespace.utf8.elementsEqual(captured.session.namespace.utf8),
              issued.accountID == captured.session.accountID,
              issued.paths.contains("api/im/webhook/context") else { return nil }
        self.captured = captured; self.scope = scope; self.issued = issued; self.underlying = underlying
        self.current = current; self.approval = approval; self.presentation = presentation
        guard isCurrent else { return nil }
    }
    public var isCurrent: Bool {
        guard !retired, presentation(), let runtime = current(),
              ContentDraftContextFence.matches(runtime, captured), runtime.session == captured.session,
              let live = approval(), Self.sameApproval(live, issued) else {
            retired = true; return false
        }
        return true
    }
    private static func sameApproval(_ lhs: OperationEndpointApproval, _ rhs: OperationEndpointApproval) -> Bool {
        lhs.baseURL.absoluteString.utf8.elementsEqual(rhs.baseURL.absoluteString.utf8)
            && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) && lhs.accountID == rhs.accountID
            && Set(lhs.paths.map { Data($0.utf8) }) == Set(rhs.paths.map { Data($0.utf8) })
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, accepts(request) else { throw NativeWebhookClientError.scopeChanged }
        let result = try await underlying.send(request)
        // Even bare late 401 must not reach the old provider's expiration callback.
        try Task.checkCancellation()
        guard isCurrent else { throw NativeWebhookClientError.scopeChanged }
        return result
    }
    private func accepts(_ request: URLRequest) -> Bool {
        guard let url = request.url, url.user == nil, url.password == nil, url.fragment == nil,
              request.httpShouldHandleCookies == false, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(captured.session.token.utf8) == true,
              AuthRequestBuilder.isValidToken(captured.session.token),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let method = request.httpMethod else { return false }
        let queryItems = parts.queryItems ?? []
        guard Set(queryItems.map(\.name)).count == queryItems.count,
              queryItems.allSatisfy({ $0.value != nil }) else { return false }
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value!) })
        parts.query = nil
        guard let withoutQuery = parts.url,
              let path = issued.paths.first(where: { path in
                  guard path.hasPrefix("api/im/webhook/"), !path.contains("%"), !path.contains("\\"),
                        !path.contains("//"), !path.contains("#"), !path.contains("?"),
                        !path.split(separator: "/").contains("."), !path.contains("..") else { return false }
                  return captured.baseURL.appendingPathComponent(path).absoluteString.utf8
                      .elementsEqual(withoutQuery.absoluteString.utf8)
              }) else { return false }
        let route = path.split(separator: "/").map(String.init)
        let tail = Array(route.dropFirst(3))
        func exact(_ required: Set<String>, optional: Set<String> = []) -> Bool {
            required.isSubset(of: Set(query.keys)) && Set(query.keys).isSubset(of: required.union(optional))
        }
        func page() -> Bool {
            guard let raw = query["limit"], let limit = Int(raw), (1...100).contains(limit), String(limit) == raw else { return false }
            // The original cursor is opaque; do not invent a length or syntax contract.
            return true
        }
        func id(_ raw: String) -> Bool { NativeWebhookID(rawValue: raw) != nil }
        if method == "GET" {
            guard request.httpBody == nil else { return false }
            if tail == ["context"] {
                return exact(["owner_id", "channel_id"]) && query["owner_id"] == scope.ownerID.rawValue
                    && query["channel_id"] == scope.channelID.rawValue
            }
            guard let family = tail.first, ["subscriptions", "endpoints"].contains(family) else { return false }
            if tail.count == 1 {
                return exact(["limit", "owner_type", "owner_id", "channel_id"], optional: ["cursor"])
                    && page() && query["owner_type"] == "CLUB" && query["owner_id"] == scope.ownerID.rawValue
                    && query["channel_id"] == scope.channelID.rawValue
            }
            guard tail.count >= 2, id(tail[1]) else { return false }
            if tail.count == 2 { return query.isEmpty }
            if tail.count == 3, family == "subscriptions", tail[2] == "deliveries" {
                return exact(["limit", "include_payload"], optional: ["cursor", "state"]) && page()
                    && ["0", "1"].contains(query["include_payload"] ?? "")
                    && (query["state"].map { NativeWebhookDeliveryState(rawValue: $0) != nil } ?? true)
            }
            if tail.count == 3, family == "endpoints", tail[2] == "logs" {
                return exact(["limit"], optional: ["cursor", "result"]) && page()
                    && (query["result"].map { NativeWebhookInboundState(rawValue: $0) != nil } ?? true)
            }
            return false
        }
        guard query.isEmpty, let body = request.httpBody, !body.isEmpty,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let family = tail.first, ["subscriptions", "endpoints"].contains(family) else { return false }
        if (method == "POST" && tail.count == 1) || (method == "PUT" && tail.count == 2 && id(tail[1])) {
            guard let change = try? JSONDecoder().decode(NativeWebhookChange.self, from: body),
                  (try? NativeWebhookHTTPService.encoded(change)) == body,
                  change.ownerType == "CLUB", change.ownerID == scope.ownerID.requestNumber,
                  change.channelID == scope.channelID.requestNumber else { return false }
            return method == "POST" ? change.revision == nil : (change.revision ?? 0) > 0
        }
        guard tail.count >= 2, id(tail[1]),
              let action = try? JSONDecoder().decode(NativeWebhookAction.self, from: body),
              (try? NativeWebhookHTTPService.encoded(action)) == body, (action.revision ?? 0) > 0 else { return false }
        if method == "DELETE", tail.count == 2 { return action.eventType == nil }
        guard method == "POST" else { return false }
        if tail.count == 3 {
            if tail[2] == (family == "subscriptions" ? "rotate-secret" : "rotate-token") { return action.eventType == nil }
            if family == "subscriptions", tail[2] == "test" { return action.eventType?.isEmpty == false }
        }
        return tail.count == 5 && family == "subscriptions" && tail[2] == "deliveries" && id(tail[3])
            && tail[4] == "retry" && action.eventType == nil
    }
}
