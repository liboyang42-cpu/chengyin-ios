import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent, expiring deployment/account grant. Existing friend or IM grants never enable this flow.
public struct NativeBlacklistApproval: Equatable {
    public let issuanceID: UUID
    public let endpoint: OperationEndpointApproval
    public let expiresAt: Date
    public static let listPath = "api/native/blacklist/list"
    public static let currentPath = "api/native/blacklist/current"
    public static let receiptPath = "api/native/blacklist/receipt"
    public static let unblockPath = "api/native/blacklist/unblock"
    public static let settlePath = "api/native/blacklist/settle"
    public static let readPaths: Set<String> = [listPath, currentPath, receiptPath]
    public init(endpoint: OperationEndpointApproval, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard Self.readPaths.isSubset(of: endpoint.paths), endpoint.paths.isSubset(of: Self.readPaths.union([Self.unblockPath, Self.settlePath])),
              expiresAt.timeIntervalSince1970.isFinite else { throw NativeBlacklistFailure.invalid }
        self.endpoint = endpoint; self.expiresAt = expiresAt; self.issuanceID = issuanceID
    }
}
@MainActor public final class NativeBlacklistService: NativeBlacklistServing {
    private let context: RuntimeDependencyContext
    private let approval: NativeBlacklistApproval
    private let currentApproval: () -> NativeBlacklistApproval?
    private let currentContext: () -> RuntimeDependencyContext?
    private let transport: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    public var viewerID: Int64 { Int64(context.session.accountID) }
    public var isCurrent: Bool {
        guard !retired, currentContext() == context, currentApproval() == approval, Date() < approval.expiresAt else { retired = true; return false }
        return true
    }
    public var canWrite: Bool { isCurrent && approval.endpoint.paths.contains(NativeBlacklistApproval.unblockPath) }
    public var canSettle: Bool { isCurrent && approval.endpoint.paths.contains(NativeBlacklistApproval.settlePath) }
    public init(context: RuntimeDependencyContext, approval: NativeBlacklistApproval, currentApproval: @escaping () -> NativeBlacklistApproval?,
                transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        guard context.market == .china, context.baseURL == approval.endpoint.baseURL,
              context.session.namespace == approval.endpoint.namespace, context.session.accountID == approval.endpoint.accountID,
              Date() < approval.expiresAt else { throw NativeBlacklistFailure.unavailable }
        self.context = context; self.approval = approval; self.currentApproval = currentApproval; self.transport = transport
        currentContext = current; self.onUnauthorized = onUnauthorized
    }
    public func page(cursor: Int64) async throws -> NativeBlacklistPage {
        let value: NativeBlacklistPage = try await exchange(NativeBlacklistApproval.listPath, fields: ["cursor": String(cursor)])
        guard value.valid(viewer: viewerID, cursor: cursor) else { throw NativeBlacklistFailure.invalid }; return value
    }
    public func current(peerID: Int64) async throws -> NativeBlacklistCurrent {
        let value: NativeBlacklistCurrent = try await exchange(NativeBlacklistApproval.currentPath, fields: ["peer_id": String(peerID)])
        guard value.valid(viewer: viewerID, peer: peerID) else { throw NativeBlacklistFailure.invalid }; return value
    }
    public func unblock(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
        guard canWrite else { throw NativeBlacklistFailure.notSent }; return try await send(command, path: NativeBlacklistApproval.unblockPath)
    }
    public func settle(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
        guard canSettle else { throw NativeBlacklistFailure.notSent }; return try await send(command, path: NativeBlacklistApproval.settlePath)
    }
    private func send(_ command: NativeBlacklistCommand, path: String) async throws -> NativeBlacklistReceipt {
        let value: NativeBlacklistReceipt = try await exchange(path, body: command.body())
        guard value.matches(command, viewer: viewerID), value.outcome != "UNKNOWN" else { throw NativeBlacklistFailure.unknown }; return value
    }
    public func receipt(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
        let value: NativeBlacklistReceipt = try await exchange(NativeBlacklistApproval.receiptPath,
            fields: ["peer_id": String(command.peerID), "expected_block_id": String(command.expectedBlockID), "request_id": command.requestID.uuidString.lowercased()])
        guard value.matches(command, viewer: viewerID) else { throw NativeBlacklistFailure.unknown }; return value
    }
    private func exchange<T: Decodable>(_ path: String, fields: [String: String] = [:], body: Data? = nil) async throws -> T {
        guard isCurrent, !Task.isCancelled, approval.endpoint.paths.contains(path) else { throw NativeBlacklistFailure.notSent }
        guard var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw NativeBlacklistFailure.notSent }
        if body == nil { parts.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw NativeBlacklistFailure.notSent }
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false; request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        if body != nil { request.setValue(path == NativeBlacklistApproval.settlePath ? "SELF_CONFIRMED_SETTLE" : "SELF_CONFIRMED_UNBLOCK", forHTTPHeaderField: "X-Audit-Log-Reason") }
        guard NativeBlacklistTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeBlacklistFailure.notSent }
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch NativeBlacklistFailure.notSent { throw NativeBlacklistFailure.notSent }
        catch { throw NativeBlacklistFailure.unknown }
        guard isCurrent, !Task.isCancelled else { throw NativeBlacklistFailure.unknown }
        let header = try? JSONDecoder().decode(Header.self, from: response.0)
        if (response.1 == 401 || (200..<300).contains(response.1)) && header?.code == 401 {
            retired = true; onUnauthorized(context); throw NativeBlacklistFailure.unauthorized
        }
        guard (200..<300).contains(response.1), header?.code == 200,
              let value = try? JSONDecoder().decode(Payload<T>.self, from: response.0) else { throw NativeBlacklistFailure.unknown }
        return value.data
    }
    private struct Header: Decodable { let code: Int }
    private struct Payload<T: Decodable>: Decodable { let data: T }
}
public enum NativeBlacklistTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeBlacklistApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              now < approval.expiresAt, !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json", let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard let path = approval.endpoint.paths.first(where: { context.baseURL.appendingPathComponent($0) == origin.url }) else { return false }
        if NativeBlacklistApproval.readPaths.contains(path) {
            guard request.httpMethod == "GET", request.httpBody == nil, request.value(forHTTPHeaderField: "X-Audit-Log-Reason") == nil else { return false }
            let items = parts.queryItems ?? []
            guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ $0.value != nil }) else { return false }
            let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
            if path == NativeBlacklistApproval.listPath { return Set(fields.keys) == ["cursor"] && Int64(fields["cursor"] ?? "").map { $0 >= 0 } == true }
            guard let peer = Int64(fields["peer_id"] ?? ""), peer > 0, peer != Int64(context.session.accountID) else { return false }
            if path == NativeBlacklistApproval.currentPath { return Set(fields.keys) == ["peer_id"] }
            return Set(fields.keys) == ["peer_id", "expected_block_id", "request_id"] && Int64(fields["expected_block_id"] ?? "").map { $0 > 0 } == true && UUID(uuidString: fields["request_id"] ?? "") != nil
        }
        guard [NativeBlacklistApproval.unblockPath, NativeBlacklistApproval.settlePath].contains(path), request.httpMethod == "POST", parts.query == nil,
              request.value(forHTTPHeaderField: "X-Audit-Log-Reason") == (path == NativeBlacklistApproval.settlePath ? "SELF_CONFIRMED_SETTLE" : "SELF_CONFIRMED_UNBLOCK"),
              let body = request.httpBody, body.count <= 1024, let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(fields.keys) == ["peer_id", "expected_block_id", "request_id"], let peer = integer(fields["peer_id"]), peer > 0,
              peer != Int64(context.session.accountID), integer(fields["expected_block_id"]).map({ $0 > 0 }) == true,
              let id = fields["request_id"] as? String, UUID(uuidString: id) != nil else { return false }
        let canonical = NativeBlacklistCommand(requestID: UUID(uuidString: id)!, peerID: peer, expectedBlockID: integer(fields["expected_block_id"])!)
        return (try? canonical.body()) == body // Reject duplicate JSON fields and alternative numeric encodings.
    }
    private static func integer(_ value: Any?) -> Int64? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), !["f", "d"].contains(String(cString: value.objCType)) else { return nil }
        return Int64(value.stringValue)
    }
}
@MainActor public final class NativeBlacklistDispatchTransport: HTTPTransport {
    private let dispatch: (URLRequest) async throws -> (Data, Int)
    public init(_ dispatch: @escaping (URLRequest) async throws -> (Data, Int)) { self.dispatch = dispatch }
    public func send(_ request: URLRequest) async throws -> (Data, Int) { try await dispatch(request) }
}
