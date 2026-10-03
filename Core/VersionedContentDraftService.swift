import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ContentDraftRoute: String, CaseIterable, Hashable { case save, restore, list, delete
    public var path: String { "api/content-draft/" + rawValue }
}
/// Explicit, expiring route review. Authentication or a merchant UI selection cannot create this grant.
/// Resolved merchant owner must come from a reviewed PROJECT_MANAGE authority mapping, never from input text.
public struct ContentDraftRouteGrant {
    public let context: RuntimeDependencyContext
    public let ownerMemberID: Int64
    public let scope: ContentDraftOwnerScope
    public let routes: Set<ContentDraftRoute>
    public let expiresAt: Date
    public init(context: RuntimeDependencyContext, ownerMemberID: Int64, scope: ContentDraftOwnerScope,
                routes: Set<ContentDraftRoute>, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, !context.role.isEmpty, ownerMemberID > 0,
              scope == .merchant || ownerMemberID == Int64(context.session.accountID),
              expiresAt.timeIntervalSince1970.isFinite else { throw ContentDraftIssue.invalid }
        self.context = context; self.ownerMemberID = ownerMemberID; self.scope = scope
        self.routes = routes; self.expiresAt = expiresAt
    }
}
/// One irrevocable session lifetime. The host MUST revoke on logout and every account, role, token,
/// market or realm transition, including an intermediate A→B→A. Never reuse a revoked lease.
@MainActor public final class ContentDraftSessionLease {
    public let context: RuntimeDependencyContext
    private let current: () -> RuntimeDependencyContext?
    private var revoked = false
    public init(context: RuntimeDependencyContext, current: @escaping () -> RuntimeDependencyContext?) {
        self.context = context; self.current = current
    }
    public func revoke() { revoked = true }
    public var isCurrent: Bool {
        if !ContentDraftContextFence.matches(current(), context) { revoked = true }
        return !revoked
    }
    public func check() throws {
        guard isCurrent else { throw ContentDraftIssue.staleSession }
        try Task.checkCancellation()
    }
}

/// Existing W02 endpoints only. There is no publish/review action, new server namespace or default grant.
@MainActor public final class ContentDraftService: ContentDraftServing {
    private let api: APIConfiguration
    private let transport: any HTTPTransport
    private let lease: ContentDraftSessionLease
    private let grant: ContentDraftRouteGrant?
    private let now: () -> Date
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                grant: ContentDraftRouteGrant? = nil, now: @escaping () -> Date = Date.init,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease; self.grant = grant
        self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ route: ContentDraftRoute, identity: ContentDraftIdentity? = nil) throws {
        try lease.check()
        guard let grant, ContentDraftContextFence.matches(grant.context, lease.context),
              api.baseURL.absoluteString.utf8.elementsEqual(lease.context.baseURL.absoluteString.utf8),
              grant.routes.contains(route), now() < grant.expiresAt else { throw ContentDraftIssue.disabled }
        if let identity {
            try identity.validate()
            guard identity.ownerMemberID == grant.ownerMemberID, identity.scope == grant.scope else { throw ContentDraftIssue.forbidden }
        }
        // The injected clock may synchronously observe a session transition; it must not
        // create a gap between the last authority check and dispatch/receipt handling.
        try lease.check()
    }
    public func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord {
        guard id > 0 else { throw ContentDraftIssue.invalid }
        try check(.restore, identity: identity)
        let value: ContentDraftRecord = try await request(.restore,
            fields: ["draft_id": String(id), "scope": identity.scope.rawValue], identity: identity)
        try value.validate(identity: identity)
        guard value.id == id, value.status == .draft else { throw ContentDraftIssue.malformed }
        return value
    }
    public func list(type: ContentDraftBusinessType? = nil) async throws -> [ContentDraftRecord] {
        try check(.list)
        guard let grant else { throw ContentDraftIssue.disabled }
        var fields = ["scope": grant.scope.rawValue]
        if let type { fields["business_type"] = type.rawValue }
        let values: [ContentDraftRecord] = try await request(.list, fields: fields)
        var seen = Set<Int64>()
        for value in values {
            let identity = try ContentDraftIdentity(ownerMemberID: grant.ownerMemberID,
                businessType: value.businessType, clientDraftKey: value.clientDraftKey, scope: grant.scope)
            try value.validate(identity: identity)
            guard value.status == .draft, type == nil || type == value.businessType,
                  seen.insert(value.id).inserted else { throw ContentDraftIssue.malformed }
        }
        return values
    }
    public func mutate(_ attempt: ContentDraftPreparedDispatch) async throws -> ContentDraftRecord {
        let mutation = attempt.mutation
        try mutation.validate()
        try check(attempt.route, identity: mutation.identity)
        let value: ContentDraftRecord = try await request(attempt.route, body: attempt.body,
            identity: mutation.identity, attempt: attempt)
        try mutation.validate(receipt: value); return value
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Code: Decodable { let code: Int }
    private func request<T: Decodable>(_ route: ContentDraftRoute, fields: [String: String] = [:],
                                      body: Data? = nil, identity: ContentDraftIdentity? = nil,
                                      attempt: ContentDraftPreparedDispatch? = nil) async throws -> T {
        try check(route, identity: identity)
        guard (route == .save || route == .delete) == (attempt != nil) else { throw ContentDraftIssue.storageUnavailable }
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(route.path),
            fields: [:], token: lease.context.session.token, includesBody: false)
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        else {
            // These controller parameters are forms, not a JSON body. Values are typed ASCII enums/IDs.
            var components = URLComponents()
            components.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        // Authorization/storage failure is pre-HTTP and must keep its typed issue.
        if let attempt { try await attempt.consume(request: request, lease: lease, transport: transport) }
        let result: (Data, Int)
        do {
            try check(route, identity: identity)
            try attempt?.checkDispatchLifetime()
            result = try await transport.send(request)
            // This check must precede decoding, error mapping AND unauthorized side effects.
            try check(route, identity: identity)
        } catch {
            try check(route, identity: identity)
            throw ContentDraftIssue.unavailable
        }
        let (data, status) = result
        guard data.count <= 1_048_576 else { throw ContentDraftIssue.malformed }
        let code: Int?
        if (200..<300).contains(status) {
            // Validate the WHOLE business envelope before interpreting code or known identity
            // fields. JSONDecoder alone may accept duplicate keys with ambiguous values.
            guard let responseText = String(data: data, encoding: .utf8),
                  case .object = try ContentDraftJSON.parse(responseText) else { throw ContentDraftIssue.malformed }
            code = try? JSONDecoder().decode(Code.self, from: data).code
        } else { code = nil } // HTTP-level errors do not depend on an AjaxResult body.
        if status == 401 || code == 401 {
            try check(route, identity: identity)
            onUnauthorized(lease.context)
            throw ContentDraftIssue.unauthorized
        }
        let failure = (200..<300).contains(status) ? code : status
        if let failure, failure != 200 {
            switch failure {
            case 400: throw ContentDraftIssue.rejected
            case 403: throw ContentDraftIssue.forbidden
            case 404: throw ContentDraftIssue.notFound
            case 409: throw ContentDraftIssue.conflict
            default: throw ContentDraftIssue.unavailable
            }
        }
        guard (200..<300).contains(status), code == 200,
              let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data), let value = envelope.data else {
            throw ContentDraftIssue.malformed
        }
        return value
    }
}

/// Internal, final, in-process recorder for synthetic execution. It never delegates to a
/// supplied HTTPTransport and contains no URLSession/network implementation. Supplying a
/// conforming fake transport instead does not bypass the system-journal dispatch requirement.
@MainActor final class ContentDraftRecordingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    var response: (Data, Int) = (Data(), 200)
    var lose = false
    var pausesResponse = false
    private var continuation: CheckedContinuation<Void, Never>?
    var isAwaitingResponse: Bool { continuation != nil }
    func resumeResponse() { pausesResponse = false; let pending = continuation; continuation = nil; pending?.resume() }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard continuation == nil else { throw ContentDraftIssue.busy }
        requests.append(request)
        if pausesResponse { await withCheckedContinuation { continuation = $0 } }
        if lose { lose = false; throw ContentDraftIssue.unavailable }
        return response
    }
}
