import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NativeFriendChannelSourceApproval: Equatable {
    public let endpoint: OperationEndpointApproval
    public let channelID: Int64
    public let issuanceID: UUID
    public let expiresAt: Date
    public var path: String { "api/channels/\(channelID)/members" }
    public init(endpoint: OperationEndpointApproval, channelID: Int64, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard channelID > 0, endpoint.paths == ["api/channels/\(channelID)/members"], expiresAt.timeIntervalSince1970.isFinite else { throw NativeFriendFailure.invalid }
        self.endpoint = endpoint; self.channelID = channelID; self.expiresAt = expiresAt; self.issuanceID = issuanceID
    }
}
public struct NativeFriendChannelMember: Decodable, Equatable, Identifiable {
    public var id: String { memberID }
    public let memberID: String
    public let nickname: String
    public let friendRemark: String?
    public let state: NativeFriendRelation
    public let version: Int64
    public let actionAvailable: Bool
    public var displayName: String { friendRemark.flatMap { $0.isEmpty ? nil : $0 } ?? nickname }
    enum CodingKeys: String, CodingKey {
        case memberID = "member_id", nickname, friendRemark = "friend_remark", state = "relation_state", version = "relation_version", actionAvailable = "friend_action_available"
    }
}
@MainActor @Observable public final class NativeFriendChannelSourceFlow {
    public let friend: NativeFriendFlow
    private let context: RuntimeDependencyContext
    private let approval: NativeFriendChannelSourceApproval
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let unauthorized: () -> Void
    private var active = false
    private var retired = false
    private var generation: UInt64 = 0
    private var rows: [NativeFriendChannelMember] = []
    private var rawName = ""
    private var cursor: String?
    private var more = false
    public private(set) var busy = false
    public private(set) var unavailable = false
    @ObservationIgnored private var authorityTask: Task<Void, Never>?
    public var isCurrent: Bool { active && !retired && current() && Date() < approval.expiresAt }
    public var members: [NativeFriendChannelMember] { isCurrent ? rows : [] }
    public var channelName: String { isCurrent ? rawName : "" }
    public var canReadMore: Bool { isCurrent && !busy && more && cursor != nil }
    public init(context: RuntimeDependencyContext, approval: NativeFriendChannelSourceApproval, friend: NativeFriendFlow,
                transport: any HTTPTransport, current: @escaping () -> Bool, unauthorized: @escaping () -> Void) throws {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace,
              approval.endpoint.accountID == context.session.accountID, current(), Date() < approval.expiresAt else { throw NativeFriendFailure.unavailable }
        self.context = context; self.approval = approval; self.friend = friend; self.transport = transport; self.current = current; self.unauthorized = unauthorized
        authorityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self else { return }
                if self.active && !self.isCurrent { self.deactivate(); return }
            }
        }
    }
    deinit { authorityTask?.cancel() }
    public func activate() async { active = true; await refresh() }
    public func refresh() async { guard isCurrent else { return }; await friend.load(); if isCurrent { await reload() } }
    public func reload(more requestedMore: Bool = false) async {
        guard isCurrent, !busy, !requestedMore || canReadMore else { return }
        generation &+= 1; let stamp = generation; busy = true; unavailable = false
        let requestedCursor = requestedMore ? cursor : nil
        if !requestedMore { rows = []; rawName = ""; cursor = nil; more = false }
        defer { if generation == stamp { busy = false } }
        do {
            var parts = URLComponents(url: context.baseURL.appendingPathComponent(approval.path), resolvingAgainstBaseURL: false)!
            parts.queryItems = [.init(name: "limit", value: "50"), .init(name: "with", value: "relation")]
            if let requestedCursor { parts.queryItems?.append(.init(name: "cursor", value: requestedCursor)) }
            guard let url = parts.url else { throw NativeFriendFailure.invalid }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.httpMethod = "GET"; request.httpShouldHandleCookies = false
            request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard NativeFriendChannelSourceTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
            let (data, status) = try await transport.send(request)
            guard isCurrent, generation == stamp, !Task.isCancelled, data.count <= 262_144 else { throw NativeFriendFailure.unknown }
            let header = try? JSONDecoder().decode(Header.self, from: data)
            let code = (200..<300).contains(status) ? header?.code ?? status : status
            if code == 401 { retired = true; unauthorized() }
            if code == 403 || code == 404 { retired = true }
            guard (200..<300).contains(status), header?.code == 200 else { throw NativeFriendFailure.unavailable }
            let page = try JSONDecoder().decode(Envelope.self, from: data).data
            guard page.viewerID == Int64(context.session.accountID), page.sourceType == 1, page.sourceID == String(approval.channelID), !page.sourceName.isEmpty, page.sourceName.utf8.count <= 2048,
                  page.relationAvailable == 1, page.onlineAvailable == 0, [0,1].contains(page.hasMore), page.list.count <= 50,
                  Set(page.list.map(\.id)).count == page.list.count,
                  page.list.allSatisfy({ row in
                      guard let id = Int64(row.memberID), id > 0, String(id) == row.memberID, row.version >= 0 else { return false }
                      return (row.state == .none || row.version > 0) && (id != context.session.accountID || !row.actionAvailable) &&
                          (row.friendRemark == nil || row.state == .friend)
                  }), page.nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 512 }) ?? true,
                  page.hasMore == 0 || (page.nextCursor != nil && page.nextCursor != requestedCursor && !page.list.isEmpty) else { throw NativeFriendFailure.invalid }
            if requestedMore { guard Set(rows.map(\.id)).isDisjoint(with: page.list.map(\.id)) else { throw NativeFriendFailure.invalid }; rows += page.list }
            else { rows = page.list }
            rawName = page.sourceName; cursor = page.nextCursor; more = page.hasMore == 1
        } catch { if generation == stamp { rows = []; rawName = ""; cursor = nil; more = false; unavailable = true } }
    }
    public func prepareRequest(_ row: NativeFriendChannelMember, message: String) {
        guard isCurrent, rows.contains(row), row.actionAvailable, row.state == .none,
              let peer = Int64(row.memberID), let source = try? NativeFriendChannelSource(channelID: approval.channelID) else { return }
        friend.reviewRequest(peerID: peer, message: message, source: source)
    }
    public func prepareAccept(_ row: NativeFriendChannelMember) async {
        guard isCurrent, rows.contains(row), row.actionAvailable, row.state == .pendingIncoming, let peer = Int64(row.memberID) else { return }
        await friend.reviewIncomingFromChannel(peerID: peer, expectedVersion: row.version)
    }
    public func confirm() async { guard isCurrent else { return }; await friend.confirmReview(); if isCurrent { await reload() } }
    public func recover() async { guard isCurrent else { return }; await friend.recover(); if isCurrent { await reload() } }
    public func deactivate() { authorityTask?.cancel(); authorityTask = nil; active = false; retired = true; generation &+= 1; busy = false; rows = []; rawName = ""; cursor = nil; more = false; friend.invalidate() }
    private struct Header: Decodable { let code: Int }
    private struct Envelope: Decodable { let data: Page }
    private struct Page: Decodable {
        let list: [NativeFriendChannelMember]
        let viewerID: Int64
        let nextCursor: String?
        let hasMore, relationAvailable, onlineAvailable, sourceType: Int
        let sourceID, sourceName: String
        enum CodingKeys: String, CodingKey {
            case list, viewerID = "viewer_id", nextCursor = "next_cursor", hasMore = "has_more", relationAvailable = "relation_available", onlineAvailable = "online_available"
            case sourceType = "source_type", sourceID = "source_id", sourceName = "source_name"
        }
    }
}
public enum NativeFriendChannelSourceTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendChannelSourceApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              now < approval.expiresAt, let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard origin.url == context.baseURL.appendingPathComponent(approval.path), let query = parts.queryItems,
              Set(query.map(\.name)).count == query.count, query.allSatisfy({ $0.value != nil }) else { return false }
        let fields = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value!) })
        return (Set(fields.keys) == ["with","limit"] || Set(fields.keys) == ["with","limit","cursor"]) && fields["with"] == "relation" && fields["limit"] == "50" &&
            (fields["cursor"].map { !$0.isEmpty && $0.utf8.count <= 512 } ?? true)
    }
}
