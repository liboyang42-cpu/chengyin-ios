import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact deployment/account grants; production composition supplies none. Reads and writes are separate.
public struct NativeFriendApproval: Equatable {
    /// Retain only for one grant issuance. Reapproval after withdrawal must create a new UUID, even with identical endpoints/expiry.
    public let issuanceID: UUID
    public let endpoint: OperationEndpointApproval
    public let expiresAt: Date
    public static let readPaths: Set<String> = ["api/friend/list", "api/friend/requests", "api/friend/relationship", "api/friend/receipt"]
    public static let writePaths: Set<String> = ["api/friend/request", "api/friend/accept", "api/friend/reject", "api/friend/cancel"]
    public init(endpoint: OperationEndpointApproval, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard !endpoint.paths.isEmpty, endpoint.paths.isSubset(of: Self.readPaths.union(Self.writePaths)),
              expiresAt.timeIntervalSince1970.isFinite else { throw APIError.invalidConfiguration }
        self.issuanceID = issuanceID; self.endpoint = endpoint; self.expiresAt = expiresAt
    }
}

@MainActor public final class NativeFriendService: NativeFriendServing {
    private let context: RuntimeDependencyContext
    private let current: () -> RuntimeDependencyContext?
    private let approval: NativeFriendApproval
    private let currentApproval: () -> NativeFriendApproval?
    private let transport: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var approvalRetired = false
    public var viewerID: Int64 { Int64(context.session.accountID) }
    public var isCurrent: Bool { current() == context && validApproval }
    public var canWrite: Bool { isCurrent && NativeFriendApproval.writePaths.isSubset(of: approval.endpoint.paths) }
    private var validApproval: Bool {
        guard !approvalRetired, let fresh = currentApproval(), fresh == approval, Date() < approval.expiresAt else {
            approvalRetired = true; return false
        }
        return true
    }
    public init(context: RuntimeDependencyContext, approval: NativeFriendApproval,
                currentApproval: @escaping () -> NativeFriendApproval?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.accountID == context.session.accountID,
              approval.endpoint.namespace == context.session.namespace,
              NativeFriendApproval.readPaths.isSubset(of: approval.endpoint.paths), Date() < approval.expiresAt else {
            throw NativeFriendFailure.unavailable
        }
        self.context = context; self.approval = approval; self.currentApproval = currentApproval
        self.transport = transport; self.current = current; self.onUnauthorized = onUnauthorized
    }
    public func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
        let page: NativeFriendPage = try await read(requests ? "requests" : "list", fields: ["cursor": String(cursor), "limit": "50"])
        let rows = page.incoming + page.outgoing + page.friends
        guard page.viewerID == viewerID, rows.count <= 50, Set(rows.map(\.peerID)).count == rows.count,
              rows.allSatisfy({ $0.peerID > 0 && $0.peerID != viewerID && $0.version > 0 }),
              page.incoming.allSatisfy({ $0.state == .pendingIncoming }), page.outgoing.allSatisfy({ $0.state == .pendingOutgoing }),
              page.friends.allSatisfy({ $0.state == .friend }),
              (!page.hasMore || (page.nextCursor ?? 0) > cursor) else { throw NativeFriendFailure.invalid }
        if let groups=page.groups {
            guard !requests,NativeFriendMetadataValidation.validGroups(groups,viewerID:viewerID) else { throw NativeFriendFailure.invalid }
            for item in page.friends {
                guard item.groupID == nil || groups.list.contains(where: { $0.isDefault == 0 && $0.id == item.groupID }) else { throw NativeFriendFailure.invalid }
            }
        } else if page.friends.contains(where: { $0.groupID != nil }) { throw NativeFriendFailure.invalid }
        try validateReviews(page, cursor: 0)
        return page
    }
    public func reviewPage(cursor: Int64) async throws -> NativeFriendPage {
        let result: NativeFriendPage = try await read("requests", fields: ["cursor": "0", "limit": "50", "review_cursor": String(cursor)])
        guard result.viewerID == viewerID else { throw NativeFriendFailure.invalid }
        try validateReviews(result, cursor: cursor); return result
    }
    private func validateReviews(_ page: NativeFriendPage, cursor: Int64) throws {
        let rows = page.reviews ?? []
        guard rows.count <= 50, Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ $0.id > cursor && $0.peerID > 0 && $0.peerID != viewerID && $0.version > 0 && UUID(uuidString: $0.requestID) != nil }),
              page.reviewHasMore != true || (page.reviewNextCursor ?? 0) > cursor else { throw NativeFriendFailure.invalid }
    }
    public func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
        let result: NativeFriendRelationship = try await read("relationship", fields: ["peer_id": String(peerID)])
        try validate(result, peerID: peerID); return result
    }
    public func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt {
        try command.validateOriginalIntent()
        guard isCurrent, canWrite, command.peerID > 0, command.peerID != viewerID,
              UUID(uuidString: command.requestID) != nil,
              command.action != .request || (command.expectedVersion == nil && !command.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && command.message.unicodeScalars.count <= 60),
              command.reviewID == nil || (command.action == .cancel && (command.reviewID ?? 0) > 0),
              command.action == .request || (command.message.isEmpty && (command.expectedVersion ?? 0) > 0) else { throw NativeFriendFailure.notSent }
        var fields: [String: Any] = ["peer_id": command.peerID, "request_id": command.requestID, "msg": command.message]
        if let source = command.source { fields["source_type"] = source.type; fields["source_id"] = source.id; if source.type == 4 { fields["source_generation"] = source.generation } }
        if let version = command.expectedVersion { fields["expected_version"] = version }
        if let review = command.reviewID { fields["review_id"] = review }
        let body: Data
        do { body = try JSONSerialization.data(withJSONObject: fields) } catch { throw NativeFriendFailure.notSent }
        let result: NativeFriendReceipt = try await exchange(command.action.rawValue, fields: [:], body: body)
        try validate(result, peerID: command.peerID, action: command.action, requestID: command.requestID)
        guard result.outcome != "UNKNOWN", result.payloadHash == command.originalIntentProof, command.reviewID == nil || result.review?.id == command.reviewID else { throw NativeFriendFailure.unknown }; return result
    }
    public func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
        let result: NativeFriendReceipt = try await read("receipt", fields: ["peer_id": String(peerID), "action": action.rawValue, "request_id": requestID])
        try validate(result, peerID: peerID, action: action, requestID: requestID); return result
    }
    private func validate(_ result: NativeFriendRelationship, peerID: Int64) throws {
        guard result.viewerID == viewerID, result.peerID == peerID, result.version >= 0,
              result.conversationID.map({ $0 > 0 }) ?? true else { throw NativeFriendFailure.invalid }
    }
    private func validate(_ result: NativeFriendReceipt, peerID: Int64, action: NativeFriendAction, requestID: String) throws {
        guard result.viewerID == viewerID, result.peerID == peerID, result.action == action,
              result.requestID.caseInsensitiveCompare(requestID) == .orderedSame, ["APPLIED", "UNKNOWN", "PENDING_REVIEW", "REJECTED", "CANCELLED", "EXPIRED", "INVALIDATED"].contains(result.outcome) else { throw NativeFriendFailure.invalid }
        if result.outcome != "UNKNOWN" {
            guard result.payloadHash?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw NativeFriendFailure.invalid }
            guard let relationship = result.relationship else { throw NativeFriendFailure.invalid }
            try validate(relationship, peerID: peerID)
            if let review = result.review {
                guard review.id > 0, review.peerID == peerID, review.version > 0, UUID(uuidString: review.requestID) != nil,
                      action != .request || (review.requestID.caseInsensitiveCompare(requestID) == .orderedSame && review.state.rawValue == result.outcome),
                      action == .request || (action == .cancel && review.state == .cancelled) else { throw NativeFriendFailure.invalid }
            } else if result.outcome != "APPLIED" { throw NativeFriendFailure.invalid }
        }
    }
    private func read<T: Decodable>(_ suffix: String, fields: [String: String]) async throws -> T {
        try await exchange(suffix, fields: fields, body: nil)
    }
    private func exchange<T: Decodable>(_ suffix: String, fields: [String: String], body: Data?) async throws -> T {
        guard isCurrent, approval.endpoint.paths.contains("api/friend/" + suffix), !Task.isCancelled else { throw NativeFriendFailure.notSent }
        var parts = URLComponents(url: context.baseURL.appendingPathComponent("api/friend/" + suffix), resolvingAgainstBaseURL: false)!
        if body == nil { parts.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw NativeFriendFailure.notSent }
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false; request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        guard NativeFriendTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch NativeFriendFailure.notSent { throw NativeFriendFailure.notSent } // Trusted composition proof: forwarding never started.
        catch { throw NativeFriendFailure.unknown }
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.unknown }
        guard data.count <= 1_048_576 else { throw NativeFriendFailure.unknown }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        // The existing /api/ authentication entry point rejects before controllers with HTTP401 + AjaxResult code401.
        // Only that matching pair is definite; other non-2xx responses still cannot prove the write was absent.
        if status == 401, header?.code == 401 {
            approvalRetired = true; onUnauthorized(context); throw NativeFriendFailure.rejected(401)
        }
        guard (200..<300).contains(status), let envelope = header else { throw NativeFriendFailure.unknown }
        if envelope.code != 200 {
            if envelope.code == 409 && envelope.msg == "REQUEST_ID_CONFLICT" { throw NativeFriendFailure.unknown }
            if envelope.code == 401 { approvalRetired = true; onUnauthorized(context); throw NativeFriendFailure.rejected(401) }
            // 5xx may follow commit or a connection fault. Never infer that the write was absent.
            if [400, 401, 403, 404, 409, 429].contains(envelope.code) { throw NativeFriendFailure.rejected(envelope.code) }
            throw NativeFriendFailure.unknown
        }
        guard let payload = try? JSONDecoder().decode(Payload<T>.self, from: data) else { throw NativeFriendFailure.unknown }
        return payload.data
    }
    private struct Header: Decodable { let code: Int; let msg: String? }
    private struct Payload<T: Decodable>: Decodable { let data: T }
}

/// Narrow forwarding port for the app's composition transport. It does not own a URLSession.
@MainActor public final class NativeFriendDispatchTransport: HTTPTransport {
    private let forward: (URLRequest) async throws -> (Data, Int)
    public init(forward: @escaping (URLRequest) async throws -> (Data, Int)) { self.forward = forward }
    public func send(_ request: URLRequest) async throws -> (Data, Int) { try await forward(request) }
}

public enum NativeFriendTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, request.httpShouldHandleCookies == false, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              now < approval.expiresAt, request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard let path = approval.endpoint.paths.first(where: { context.baseURL.appendingPathComponent($0) == origin.url }) else { return false }
        if NativeFriendApproval.readPaths.contains(path) {
            guard request.httpMethod == "GET", request.httpBody == nil else { return false }
            let query = parts.queryItems ?? []
            guard Set(query.map(\.name)).count == query.count, query.allSatisfy({ $0.value != nil }) else { return false }
            let fields = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value!) })
            if path.hasSuffix("/list") || path.hasSuffix("/requests") {
                let keys = Set(fields.keys)
                let allowed = keys == ["cursor", "limit"] || (path.hasSuffix("/requests") && keys == ["cursor", "limit", "review_cursor"] && (Int64(fields["review_cursor"] ?? "") ?? -1) >= 0)
                return allowed && (Int64(fields["cursor"] ?? "") ?? -1) >= 0 && (1...100).contains(Int(fields["limit"] ?? "") ?? 0)
            }
            guard let peer = Int64(fields["peer_id"] ?? ""), peer > 0, peer != context.session.accountID else { return false }
            if path.hasSuffix("/relationship") { return Set(fields.keys) == ["peer_id"] }
            return Set(fields.keys) == ["peer_id", "action", "request_id"] && NativeFriendAction(rawValue: fields["action"] ?? "") != nil && UUID(uuidString: fields["request_id"] ?? "") != nil
        }
        guard NativeFriendApproval.writePaths.contains(path), request.httpMethod == "POST", parts.query == nil,
              let body = request.httpBody, body.count <= 4096,
              let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(fields.keys).isSubset(of: ["peer_id", "request_id", "msg", "expected_version", "review_id", "source_type", "source_id", "source_generation"]),
              let peer = fields["peer_id"] as? NSNumber, CFGetTypeID(peer) != CFBooleanGetTypeID(),
              peer.doubleValue == Double(peer.int64Value), peer.int64Value > 0, peer.int64Value != context.session.accountID,
              let requestID = fields["request_id"] as? String, UUID(uuidString: requestID) != nil,
              let message = fields["msg"] as? String else { return false }
        if path.hasSuffix("/request") {
            var keys: Set<String> = ["peer_id", "request_id", "msg"]
            if fields["source_type"] != nil || fields["source_id"] != nil || fields["source_generation"] != nil {
                guard let type = fields["source_type"] as? NSNumber, CFGetTypeID(type) != CFBooleanGetTypeID(), [1.0, 2.0, 3.0, 4.0].contains(type.doubleValue),
                      let id = fields["source_id"] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(),
                      id.doubleValue == Double(id.int64Value), id.int64Value > 0 else { return false }
                keys.formUnion(["source_type", "source_id"])
                if type.intValue == 4 {
                    guard let generation = fields["source_generation"] as? String, ["legacySquare", "communityV1"].contains(generation) else { return false }
                    keys.insert("source_generation")
                } else if fields["source_generation"] != nil { return false }
            }
            return Set(fields.keys) == keys && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.unicodeScalars.count <= 60
        }
        var expected: Set<String> = ["peer_id", "request_id", "msg", "expected_version"]
        if let review = fields["review_id"] {
            guard path.hasSuffix("/cancel"), let id = review as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(), id.doubleValue == Double(id.int64Value), id.int64Value > 0 else { return false }
            expected.insert("review_id")
        }
        guard Set(fields.keys) == expected,
              let version = fields["expected_version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue == Double(version.int64Value), version.int64Value > 0 else { return false }
        return message.isEmpty
    }
}
