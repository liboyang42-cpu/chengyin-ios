import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityOrientationTaskCapability: String, Hashable { case receiptRead, answer }

/// Caller-issued, short-lived capability for exactly one existing run. Never decoded from
/// a server payload, launch URL or defaults. Read and answer approvals have separate issuances.
public struct CityOrientationTaskApproval: Equatable {
    public let context: RuntimeDependencyContext
    public let scope: PlaySessionScope
    public let sessionID: Int
    public let capability: CityOrientationTaskCapability
    public let issuanceID: UUID
    public let expiresAt: Date
    public init(context: RuntimeDependencyContext, scope: PlaySessionScope, sessionID: Int,
                capability: CityOrientationTaskCapability, issuanceID: UUID = UUID(), expiresAt: Date) throws {
        guard context.market == .china, context.baseURL.scheme == "https", scope.isValid, sessionID > 0,
              context.role == context.session.role, expiresAt > Date() else { throw APIError.invalidConfiguration }
        self.context = context; self.scope = scope; self.sessionID = sessionID; self.capability = capability
        self.issuanceID = issuanceID; self.expiresAt = expiresAt
    }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        context == current && context.role == context.session.role && now < expiresAt
    }
}

/// Exact composition route. Unknown fields, duplicate query keys, coercible/noncanonical
/// numbers, extra query/body, cookies, other runs and old endpoint aliases are not accepted.
public struct CityOrientationTaskRoute {
    public let capability: CityOrientationTaskCapability
    public let sessionID: Int
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpBodyStream == nil, request.httpShouldHandleCookies == false,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        var origin = parts; origin.query = nil
        if origin.url?.absoluteString == baseURL.appendingPathComponent("api/play/city-orientation/receipt").absoluteString {
            guard request.httpMethod == "GET", request.httpBody == nil,
                  let query = parts.queryItems, query.count == 3, Set(query.map(\.name)) == ["sessionId", "nodeId", "requestId"],
                  query.allSatisfy({ $0.value != nil }) else { return nil }
            let fields = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value!) })
            guard let run = Int(fields["sessionId"] ?? ""), run > 0, String(run) == fields["sessionId"],
                  let node = Int(fields["nodeId"] ?? ""), node > 0, String(node) == fields["nodeId"],
                  UUID(uuidString: fields["requestId"] ?? "") != nil else { return nil }
            capability = .receiptRead; sessionID = run
        } else if origin.url?.absoluteString == baseURL.appendingPathComponent("api/play/city-orientation/answer").absoluteString {
            guard request.httpMethod == "POST", parts.query == nil,
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let body = request.httpBody, body.count <= 4096,
                  let command = try? JSONDecoder().decode(CityOrientationTaskCommand.self, from: body),
                  (try? command.validate()) != nil else { return nil }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard (try? encoder.encode(command)) == body else { return nil }
            capability = .answer; sessionID = command.sessionId
        } else { return nil }
    }
    public func approved(request: URLRequest, context: RuntimeDependencyContext,
                         receipt: CityOrientationTaskApproval?, answer: CityOrientationTaskApproval?, now: Date = Date()) -> Bool {
        guard let receipt, receipt.capability == .receiptRead, receipt.sessionID == sessionID,
              receipt.matches(context, now: now), request.value(forHTTPHeaderField: "Authorization") == context.session.token else { return false }
        if capability == .receiptRead { return true }
        guard let answer, answer.capability == .answer, answer.sessionID == sessionID, answer.scope == receipt.scope,
              answer.matches(context, now: now) else { return false }
        return true
    }
}

/// Both the native adapter and the final composition dispatch recheck the exact issuance.
/// No network owner, fallback transport, broad play capability or automatic retry is created.
@MainActor public final class CityOrientationTaskApprovedTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let scope: PlaySessionScope
    private let sessionID: Int
    private let receipt: CityOrientationTaskApproval?
    private let answer: CityOrientationTaskApproval?
    private let current: () -> RuntimeDependencyContext?
    private let selected: (CityOrientationTaskCapability) -> CityOrientationTaskApproval?
    private let approvalRevision: UInt64
    private let currentApprovalRevision: () -> UInt64
    private let underlying: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var authenticationRetired = false
    public init(context: RuntimeDependencyContext, scope: PlaySessionScope, sessionID: Int,
                receipt: CityOrientationTaskApproval?, answer: CityOrientationTaskApproval?,
                underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                selected: @escaping (CityOrientationTaskCapability) -> CityOrientationTaskApproval?,
                approvalRevision: UInt64, currentApprovalRevision: @escaping () -> UInt64,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.context = context; self.scope = scope; self.sessionID = sessionID; self.receipt = receipt; self.answer = answer
        self.underlying = underlying; self.current = current; self.selected = selected
        self.approvalRevision = approvalRevision; self.currentApprovalRevision = currentApprovalRevision
        self.onUnauthorized = onUnauthorized
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        func valid() -> Bool {
            guard !authenticationRetired, current() == context, currentApprovalRevision() == approvalRevision,
                  let route = CityOrientationTaskRoute(request: request, baseURL: context.baseURL),
                  route.sessionID == sessionID, receipt?.scope == scope, selected(.receiptRead) == receipt,
                  route.capability == .receiptRead || selected(.answer) == answer else { return false }
            return route.approved(request: request, context: context, receipt: receipt, answer: answer)
        }
        try Task.checkCancellation(); guard valid() else { throw PlayExperienceError.disabled }
        let result = try await underlying.send(request)
        if CityOrientationTaskService.isAuthenticationFailure(result) {
            // Retire only this captured port. The host callback checks current credential
            // identity separately; an old reply must not revoke a newer registry issuance.
            if !authenticationRetired { authenticationRetired = true; onUnauthorized(context) }
            throw PlayExperienceError.unauthorized
        }
        try Task.checkCancellation(); guard valid() else { throw PlayExperienceError.staleSession }
        return result
    }
}

/// Forwarding port only; the host's composition dispatcher remains the network owner.
@MainActor public final class CityOrientationTaskDispatchTransport: HTTPTransport {
    private let forward: (URLRequest) async throws -> (Data, Int)
    public init(forward: @escaping (URLRequest) async throws -> (Data, Int)) { self.forward = forward }
    public func send(_ request: URLRequest) async throws -> (Data, Int) { try await forward(request) }
}


/// Actual host approval lifecycle, initially empty. Every issue/revoke changes a monotonic
/// revision, including revoke→restore of the exact same issuance. Old requests cannot revive.
@available(macOS 14.0, *) @MainActor @Observable public final class CityOrientationTaskApprovalRegistry {
    public private(set) var revision: UInt64 = 0
    private struct Key: Hashable {
        let realm: String; let namespace: String; let account: Int; let role: String
        let run: Int; let capability: CityOrientationTaskCapability
    }
    private var values: [Key: CityOrientationTaskApproval] = [:]
    public init() { }
    private func key(_ context: RuntimeDependencyContext, run: Int, capability: CityOrientationTaskCapability) -> Key {
        .init(realm:context.baseURL.absoluteString,namespace:context.session.namespace,account:context.session.accountID,
              role:context.role,run:run,capability:capability)
    }
    public func approval(context: RuntimeDependencyContext, sessionID: Int, capability: CityOrientationTaskCapability) -> CityOrientationTaskApproval? {
        guard let value = values[key(context,run:sessionID,capability:capability)], value.matches(context) else { return nil }
        return value
    }
    /// Only reviewed host composition may issue a capability; no server/login/user-default route calls this.
    public func issue(_ approval: CityOrientationTaskApproval) {
        precondition(revision < UInt64.max); revision += 1
        values[key(approval.context,run:approval.sessionID,capability:approval.capability)] = approval
    }
    public func revoke(context: RuntimeDependencyContext, sessionID: Int, capability: CityOrientationTaskCapability) {
        precondition(revision < UInt64.max); revision += 1
        values.removeValue(forKey:key(context,run:sessionID,capability:capability))
    }
    public func revokeAll() { precondition(revision < UInt64.max); revision += 1; values.removeAll() }
}
