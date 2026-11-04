import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent grant: existing friendship/metadata/IM approvals cannot enable removal.
public struct NativeFriendRemovalApproval: Equatable {
    public let issuanceID: UUID
    public let endpoint: OperationEndpointApproval
    public let expiresAt: Date
    public static let readPaths: Set<String> = ["api/friend/relationship", "api/friend/removal/receipt"]
    public static let removePath = "api/friend/remove"
    public static let settlePath = "api/friend/removal/settle"
    public init(endpoint: OperationEndpointApproval, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard Self.readPaths.isSubset(of: endpoint.paths), endpoint.paths.isSubset(of: Self.readPaths.union([Self.removePath])),
              expiresAt.timeIntervalSince1970.isFinite else { throw NativeFriendFailure.invalid }
        self.issuanceID = issuanceID; self.endpoint = endpoint; self.expiresAt = expiresAt
    }
}

@MainActor public final class NativeFriendRemovalService: NativeFriendRemovalServing {
    private let context: RuntimeDependencyContext
    private let approval: NativeFriendRemovalApproval
    private let currentApproval: () -> NativeFriendRemovalApproval?
    private let current: () -> RuntimeDependencyContext?
    private let transport: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    public var viewerID: Int64 { Int64(context.session.accountID) }
    public var isCurrent: Bool {
        guard !retired, current() == context, currentApproval() == approval, Date() < approval.expiresAt else { retired = true; return false }
        return true
    }
    public var canWrite: Bool { isCurrent && approval.endpoint.paths.contains(NativeFriendRemovalApproval.removePath) }
    // No formal F-05 settlement/cancellation writer exists. Retain protocol compatibility, never grant it.
    public var canSettle: Bool { false }
    public init(context: RuntimeDependencyContext, approval: NativeFriendRemovalApproval,
                currentApproval: @escaping () -> NativeFriendRemovalApproval?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              Date() < approval.expiresAt else { throw NativeFriendFailure.unavailable }
        self.context = context; self.approval = approval; self.currentApproval = currentApproval
        self.transport = transport; self.current = current; self.onUnauthorized = onUnauthorized
    }
    public func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
        let value: NativeFriendRelationship = try await exchange("api/friend/relationship", fields: ["peer_id": String(peerID)], body: nil)
        guard value.viewerID == viewerID, value.peerID == peerID, value.version >= 0,
              value.conversationID.map({ $0 > 0 }) ?? true else { throw NativeFriendFailure.invalid }
        return value
    }
    public func remove(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
        guard canWrite else { throw NativeFriendFailure.notSent }
        return try await send(command, path: NativeFriendRemovalApproval.removePath)
    }
    public func settle(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
        throw NativeFriendFailure.notSent
    }
    private func send(_ command: NativeFriendRemovalCommand, path: String) async throws -> NativeFriendRemovalReceipt {
        let value: NativeFriendRemovalReceipt = try await exchange(path, fields: [:], body: command.body())
        guard value.matches(command, viewerID: viewerID), value.outcome != "UNKNOWN" else { throw NativeFriendFailure.unknown }
        return value
    }
    public func receipt(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
        let value: NativeFriendRemovalReceipt = try await exchange("api/friend/removal/receipt",
            fields: ["peer_id": String(command.peerID), "expected_version": String(command.expectedVersion), "request_id": command.requestID.uuidString], body: nil)
        guard value.matches(command, viewerID: viewerID) else { throw NativeFriendFailure.unknown }; return value
    }
    private func exchange<T: Decodable>(_ path: String, fields: [String: String], body: Data?) async throws -> T {
        guard isCurrent, !Task.isCancelled, approval.endpoint.paths.contains(path) else { throw NativeFriendFailure.notSent }
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if body == nil && !fields.isEmpty { parts.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw NativeFriendFailure.notSent }
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false; request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        guard NativeFriendRemovalTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch NativeFriendFailure.notSent { throw NativeFriendFailure.notSent }
        catch { throw NativeFriendFailure.unknown }
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.unknown }
        guard response.0.count <= 262_144 else { throw NativeFriendFailure.unknown }
        let header = try? JSONDecoder().decode(Header.self, from: response.0)
        if (response.1 == 401 && header?.code == 401) || ((200..<300).contains(response.1) && header?.code == 401) {
            retired = true; onUnauthorized(context); throw NativeFriendFailure.rejected(401)
        }
        let code = header?.code
        let commandRefusal = path == NativeFriendRemovalApproval.removePath && body != nil &&
            (code == 404 || code == 409) && ((200..<300).contains(response.1) || response.1 == code)
        guard ((200..<300).contains(response.1) && code == 200) || commandRefusal,
              let payload = try? JSONDecoder().decode(Payload<T>.self, from: response.0) else { throw NativeFriendFailure.unknown }
        if commandRefusal {
            guard let refusal = payload.data as? NativeFriendRemovalReceipt, refusal.outcome == "REJECTED" else { throw NativeFriendFailure.unknown }
        }
        // send() still requires the exact actor/peer/version/UUID/hash and a terminal receipt.
        // Error-only 404/409 responses cannot clear an uncertain original command.
        return payload.data
    }
    private struct Header: Decodable { let code: Int }
    private struct Payload<T: Decodable>: Decodable { let data: T }
}

public enum NativeFriendRemovalTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendRemovalApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              now < approval.expiresAt, !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard let path = approval.endpoint.paths.first(where: { context.baseURL.appendingPathComponent($0) == origin.url }) else { return false }
        if NativeFriendRemovalApproval.readPaths.contains(path) {
            guard request.httpMethod == "GET", request.httpBody == nil else { return false }
            let items = parts.queryItems ?? []
            guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ $0.value != nil }) else { return false }
            let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
            guard let peer = Int64(fields["peer_id"] ?? ""), peer > 0, peer != Int64(context.session.accountID) else { return false }
            if path == "api/friend/relationship" { return Set(fields.keys) == ["peer_id"] }
            return Set(fields.keys) == ["peer_id", "expected_version", "request_id"] && validVersion(Int64(fields["expected_version"] ?? "")) && UUID(uuidString: fields["request_id"] ?? "") != nil
        }
        guard path == NativeFriendRemovalApproval.removePath, request.httpMethod == "POST", parts.query == nil,
              let body = request.httpBody, body.count <= 1024, let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(fields.keys) == ["peer_id", "expected_version", "request_id"], let peer = integer(fields["peer_id"]), peer > 0,
              peer != Int64(context.session.accountID), validVersion(integer(fields["expected_version"])),
              let id = fields["request_id"] as? String, UUID(uuidString: id) != nil else { return false }
        return true
    }
    private static func validVersion(_ value: Int64?) -> Bool { value.map { $0 > 0 && $0 < Int64.max } ?? false }
    private static func integer(_ value: Any?) -> Int64? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), !["f", "d"].contains(String(cString: value.objCType)) else { return nil }
        return value.int64Value
    }
}
