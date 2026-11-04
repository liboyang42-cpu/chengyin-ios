import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// P44 has its own default-closed read issuance. Friend metadata/channel/IM grants are not substitutes.
public struct NativeFriendProgressApproval: Equatable {
    public let issuanceID: UUID
    public let endpoint: OperationEndpointApproval
    public let expiresAt: Date
    public static let path = "api/friend/progress"
    public init(endpoint: OperationEndpointApproval, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard endpoint.paths == [Self.path], expiresAt.timeIntervalSince1970.isFinite else { throw NativeChannelProgressError.invalid }
        self.endpoint = endpoint; self.expiresAt = expiresAt; self.issuanceID = issuanceID
    }
}

@MainActor public final class NativeFriendProgressService: NativeFriendProgressIndexProviding {
    private let context: RuntimeDependencyContext
    private let approval: NativeFriendProgressApproval
    private let friend: NativeFriendItem
    private let captured: NativeFriendProgressAuthority
    private let current: () -> RuntimeDependencyContext?
    private let currentApproval: () -> NativeFriendProgressApproval?
    private let relationshipCurrent: () -> Bool
    private let transport: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    private var generation: UInt64 = 0
    public var authority: NativeFriendProgressAuthority? {
        guard !retired, current() == context, currentApproval() == approval, relationshipCurrent(), Date() < approval.expiresAt else {
            retired = true; return nil
        }
        return captured
    }
    public init(context: RuntimeDependencyContext, approval: NativeFriendProgressApproval, friend: NativeFriendItem,
                currentApproval: @escaping () -> NativeFriendProgressApproval?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, relationshipCurrent: @escaping () -> Bool,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        guard context.market == .china, friend.state == .friend, friend.peerID > 0, friend.version > 0,
              friend.peerID != Int64(context.session.accountID), relationshipCurrent(),
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace,
              approval.endpoint.accountID == context.session.accountID, Date() < approval.expiresAt else { throw NativeChannelProgressError.closed }
        self.context = context; self.approval = approval; self.friend = friend; self.currentApproval = currentApproval
        self.transport = transport; self.current = current; self.relationshipCurrent = relationshipCurrent; self.onUnauthorized = onUnauthorized
        let identity = try NativeChannelProgressIdentity(actorID: Int64(context.session.accountID), namespace: context.session.namespace,
            origin: context.baseURL, sessionEpoch: String(context.session.epoch))
        captured = try NativeFriendProgressAuthority(identity: identity, friendID: friend.peerID,
            relationshipVersion: String(friend.version), authorizationVersion: approval.issuanceID.uuidString)
    }
    public func retireOperations() { generation &+= 1 }
    public func friendProgressIndex() async throws -> NativeFriendProgressProjection {
        guard authority == captured, !Task.isCancelled else { throw NativeChannelProgressError.closed }
        generation &+= 1; let stamp = generation
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(NativeFriendProgressApproval.path), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "peer_id", value: String(friend.peerID)), URLQueryItem(name: "expected_friend_version", value: String(friend.version))]
        guard let url = parts.url else { throw NativeChannelProgressError.invalid }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard NativeFriendProgressTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeChannelProgressError.closed }
        let (bytes, status) = try await transport.send(request)
        guard authority == captured, generation == stamp, !Task.isCancelled else { throw NativeChannelProgressError.closed }
        guard bytes.count <= 262_144 else { throw NativeChannelProgressError.malformed }
        let header = try? JSONDecoder().decode(Header.self, from: bytes)
        let code = (200..<300).contains(status) ? (header?.code ?? status) : status
        if code == 401 { retired = true; onUnauthorized(context); throw NativeChannelProgressError.server(status: 401, code: header?.msg) }
        if code == 403 || code == 404 || code == 409 { retired = true; throw NativeChannelProgressError.server(status: 403, code: header?.msg) }
        guard (200..<300).contains(status), header?.code == 200 else { throw NativeChannelProgressError.server(status: code, code: header?.msg) }
        // Decoder omission is not a privacy filter. Reject any new/detail field before constructing the card.
        guard let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let raw = envelope["data"] as? [String: Any],
              Set(raw.keys).isSubset(of: ["viewer_id", "peer_id", "friend_version", "visible", "items"]) else { throw NativeChannelProgressError.malformed }
        let value = try JSONDecoder().decode(Payload.self, from: bytes).data
        guard value.viewerID == Int64(context.session.accountID), value.peerID == friend.peerID, value.friendVersion == friend.version else { throw NativeChannelProgressError.malformed }
        if !value.visible { guard value.items == nil, raw["items"] == nil else { throw NativeChannelProgressError.malformed }; return .hidden }
        guard let rows = value.items, let rawItems = raw["items"] as? [[String: Any]], rows.count <= 50, rows.count == rawItems.count,
              Set(rows.map(\.id)).count == rows.count else { throw NativeChannelProgressError.malformed }
        for item in rawItems {
            guard Set(item.keys) == ["id", "title", "topicID", "activityID", "meter"], let meter = item["meter"] as? [String: Any],
                  Set(meter.keys) == ["visible", "subjectId", "topicId", "activityId", "required", "done", "percent", "completed", "asOf", "revision", "visibility"],
                  let visibility = meter["visibility"] as? [String: Any], Set(visibility.keys) == ["aggregate", "detail"],
                  visibility["aggregate"] as? String == "FRIEND", visibility["detail"] as? String == "SELF" else { throw NativeChannelProgressError.malformed }
        }
        return .visible(try rows.map { row in
            guard row.meter.subjectId == friend.peerID, row.meter.required.map({ $0 > 0 }) == true,
                  row.meter.done.map({ $0 >= 0 }) == true, row.meter.completed != nil,
                  row.meter.percent.map({ (0...100).contains($0) }) == true,
                  row.meter.revision?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  row.meter.asOf?.isEmpty == false, row.meter.currentNodeId == nil, row.meter.completedNodeIds == nil else { throw NativeChannelProgressError.malformed }
            return try NativeFriendProgressItem(id: row.id, title: row.title, topicID: row.topicID, activityID: row.activityID, meter: row.meter)
        })
    }
    private struct Header: Decodable { let code: Int; let msg: String? }
    private struct Payload: Decodable { let data: Projection }
    private struct Projection: Decodable {
        let viewerID: Int64; let peerID: Int64; let friendVersion: Int64; let visible: Bool; let items: [Item]?
        enum CodingKeys: String, CodingKey { case viewerID = "viewer_id", peerID = "peer_id", friendVersion = "friend_version", visible, items }
    }
    private struct Item: Decodable { let id: String; let title: String; let topicID: Int64; let activityID: Int64; let meter: NativeChannelProgressMeter }
}
public enum NativeFriendProgressTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendProgressApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json", request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace,
              approval.endpoint.accountID == context.session.accountID, now < approval.expiresAt,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard origin.url == context.baseURL.appendingPathComponent(NativeFriendProgressApproval.path) else { return false }
        let items = parts.queryItems ?? []
        guard items.count == 2, Set(items.map(\.name)) == ["peer_id", "expected_friend_version"], items.allSatisfy({ $0.value != nil }) else { return false }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        guard let peer = Int64(fields["peer_id"] ?? ""), peer > 0, peer != Int64(context.session.accountID),
              let version = Int64(fields["expected_friend_version"] ?? ""), version > 0 else { return false }
        return true
    }
}
