import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent read-only issuance. Production composition supplies no approval by default.
public struct NativeFriendDirectoryApproval: Equatable {
    public let issuanceID: UUID
    public let endpoint: OperationEndpointApproval
    public let expiresAt: Date
    public static let paths: Set<String> = ["api/friend/directory", "api/friend/directory/detail"]
    public init(endpoint: OperationEndpointApproval, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard endpoint.paths == Self.paths, expiresAt.timeIntervalSince1970.isFinite else { throw NativeFriendFailure.invalid }
        self.endpoint = endpoint; self.expiresAt = expiresAt; self.issuanceID = issuanceID
    }
}
@MainActor public final class NativeFriendDirectoryService: NativeFriendDirectoryServing {
    private let context: RuntimeDependencyContext
    private let approval: NativeFriendDirectoryApproval
    private let current: () -> RuntimeDependencyContext?
    private let currentApproval: () -> NativeFriendDirectoryApproval?
    private let transport: any HTTPTransport
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var retired = false
    public var viewerID: Int64 { Int64(context.session.accountID) }
    public var isCurrent: Bool {
        guard !retired, current() == context, currentApproval() == approval, Date() < approval.expiresAt else { retired = true; return false }
        return true
    }
    public init(context: RuntimeDependencyContext, approval: NativeFriendDirectoryApproval,
                currentApproval: @escaping () -> NativeFriendDirectoryApproval?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              Date() < approval.expiresAt else { throw NativeFriendFailure.unavailable }
        self.context = context; self.approval = approval; self.currentApproval = currentApproval; self.transport = transport
        self.current = current; self.onUnauthorized = onUnauthorized
    }
    public func page(filter: NativeFriendDirectoryFilter, cursor: String?) async throws -> NativeFriendDirectoryPage {
        var fields = ["section": filter.section.rawValue, "starred": filter.starredOnly ? "true" : "false", "limit": "50"]
        if let group = filter.groupID { fields["group_id"] = String(group) }
        if let cursor { fields["cursor"] = cursor }
        let value: NativeFriendDirectoryPage = try await read("api/friend/directory", fields: fields)
        guard value.viewerID == viewerID, value.section == filter.section, value.groupID == filter.groupID,
              value.starredOnly == filter.starredOnly, value.revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              (0...500).contains(value.total), value.items.count <= 50, value.items.count <= value.total,
              Set(value.items.map(\.peerID)).count == value.items.count,
              value.counts.keys.sorted() == ["all", "recent", "together"], value.counts.values.allSatisfy({ (0...500).contains($0) }),
              value.counts[filter.section.rawValue] == value.total,
              NativeFriendMetadataValidation.validGroups(value.groups,viewerID:viewerID),
              value.hasMore == (value.nextCursor != nil), value.nextCursor.map(Self.validCursor) ?? true,
              (value.counts["all"] ?? 0) >= (value.counts["recent"] ?? 0), (value.counts["all"] ?? 0) >= (value.counts["together"] ?? 0),
              !value.hasMore || value.items.count == 50,
              filter.groupID == nil || value.groups.list.contains(where: { $0.id == filter.groupID }) else { throw NativeFriendFailure.invalid }
        for item in value.items {
            try validate(item)
            guard item.groupID == nil || value.groups.list.contains(where: { $0.id == item.groupID }), !filter.starredOnly || item.starred == 1,
                  filter.groupID == nil || (filter.groupID == 0 ? item.groupID == nil : item.groupID == filter.groupID) else { throw NativeFriendFailure.invalid }
        }
        return value
    }
    public func detail(peerID: Int64) async throws -> NativeFriendDirectoryDetail {
        let value: NativeFriendDirectoryDetail = try await read("api/friend/directory/detail", fields: ["peer_id": String(peerID)])
        guard value.viewerID == viewerID, value.item.peerID == peerID, value.conversationID.map({ $0 > 0 }) ?? true else { throw NativeFriendFailure.invalid }
        try validate(value.item); return value
    }
    private func validate(_ value: NativeFriendItem) throws {
        guard value.peerID > 0, value.peerID != viewerID, value.state == .friend, value.version > 0,
              value.message.isEmpty, value.expiresAtMS == 0, value.starred == 0 || value.starred == 1,
              value.groupID.map({ $0 > 0 }) ?? true, NativeFriendMetadataValidation.validRemark(value.friendRemark) else { throw NativeFriendFailure.invalid }
    }
    nonisolated public static func validCursor(_ value: String) -> Bool {
        value.count <= 128 && value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }
    private func read<T: Decodable>(_ path: String, fields: [String: String]) async throws -> T {
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.notSent }
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        parts.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = parts.url else { throw NativeFriendFailure.invalid }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard NativeFriendDirectoryTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
        let response = try await transport.send(request)
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.staleSession }
        if response.1 == 401 { retired = true; onUnauthorized(context); throw NativeFriendFailure.staleSession }
        guard response.0.count <= 1024 * 1024 else { throw NativeFriendFailure.invalid }
        let header = try? JSONDecoder().decode(Header.self, from: response.0)
        let code = (200..<300).contains(response.1) ? header?.code : response.1
        if code == 401 { retired = true; onUnauthorized(context); throw NativeFriendFailure.staleSession }
        // A directory-level 404 can mean the viewer is no longer eligible. It is not a peer deletion.
        // A 503 may be a disabled deployment or a temporary outage: clear the snapshot, but allow a fresh read.
        let unavailableCodes = ["FRIEND_DIRECTORY_UNAVAILABLE", "FRIEND_METADATA_UNAVAILABLE", "FRIEND_DIRECTORY_BOUND_EXCEEDED", "FRIEND_UNAVAILABLE"]
        if code == 403 || (code == 503 && unavailableCodes.contains(header?.msg ?? "")) {
            throw NativeFriendDirectoryFailure.readUnavailable
        }
        if code == 409 && header?.msg == "DIRECTORY_CHANGED" { throw NativeFriendDirectoryFailure.changed }
        if code == 404 && header?.msg == "DIRECTORY_GROUP_NOT_FOUND" { throw NativeFriendDirectoryFailure.missingGroup }
        if code == 404 && header?.msg == "FRIEND_NOT_FOUND" {
            throw path.hasSuffix("/detail") ? NativeFriendDirectoryFailure.unavailablePeer : NativeFriendDirectoryFailure.readUnavailable
        }
        guard (200..<300).contains(response.1), let header else { throw NativeFriendFailure.unknown }
        guard header.code == 200 else { throw NativeFriendFailure.rejected(header.code) }
        return try JSONDecoder().decode(Payload<T>.self, from: response.0).data
    }
    private struct Header: Decodable { let code: Int; let msg: String? }
    private struct Payload<T: Decodable>: Decodable { let data: T }
}
public enum NativeFriendDirectoryTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendDirectoryApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, !request.httpShouldHandleCookies, request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json", request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace,
              approval.endpoint.accountID == context.session.accountID, now < approval.expiresAt,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard let path = approval.endpoint.paths.first(where: { context.baseURL.appendingPathComponent($0) == origin.url }) else { return false }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ $0.value != nil }) else { return false }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        if path.hasSuffix("/detail") {
            return Set(fields.keys) == ["peer_id"] && (Int64(fields["peer_id"] ?? "") ?? 0) > 0 && Int64(fields["peer_id"] ?? "") != Int64(context.session.accountID)
        }
        guard Set(fields.keys).isSubset(of: ["section", "starred", "limit", "group_id", "cursor"]),
              fields["section"].flatMap(NativeFriendDirectorySection.init(rawValue:)) != nil,
              ["true", "false"].contains(fields["starred"] ?? ""), fields["limit"] == "50" else { return false }
        if let group = fields["group_id"], Int64(group).map({ $0 >= 0 }) != true { return false }
        if let cursor = fields["cursor"], !NativeFriendDirectoryService.validCursor(cursor) { return false }
        return true
    }
}
