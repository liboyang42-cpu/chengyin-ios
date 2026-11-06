import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NativeFriendChannelInviteApproval: Equatable {
    public let endpoint: OperationEndpointApproval
    public let mode: NativeFriendChannelInviteMode
    public let issuanceID: UUID
    public let expiresAt: Date
    public static let prefix = "api/friend/channel-invite/"
    public static let reads: Set<String> = Set(["picker", "batch", "landing", "mine", "notice", "receipt"].map { prefix + $0 })
    public static let writes: Set<String> = [prefix + "command"]
    public init(endpoint: OperationEndpointApproval, mode: NativeFriendChannelInviteMode, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard mode.valid, Self.reads.isSubset(of: endpoint.paths), endpoint.paths.isSubset(of: Self.reads.union(Self.writes)), expiresAt.timeIntervalSince1970.isFinite else { throw NativeFriendFailure.invalid }
        self.endpoint = endpoint; self.mode = mode; self.expiresAt = expiresAt; self.issuanceID = issuanceID
    }
}
@MainActor public final class NativeFriendChannelInviteService {
    public let mode: NativeFriendChannelInviteMode
    public let viewerID: Int64
    private let context: RuntimeDependencyContext
    private let approval: NativeFriendChannelInviteApproval
    private let current: () -> Bool
    private let transport: any HTTPTransport
    private let unauthorized: () -> Void
    private var retired = false
    public var isCurrent: Bool { guard !retired, current(), Date() < approval.expiresAt else { retired = true; return false }; return true }
    public var canWrite: Bool { isCurrent && NativeFriendChannelInviteApproval.writes.isSubset(of: approval.endpoint.paths) }
    public init(context: RuntimeDependencyContext, approval: NativeFriendChannelInviteApproval, transport: any HTTPTransport,
                current: @escaping () -> Bool, unauthorized: @escaping () -> Void) throws {
        guard context.market == .china, approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace,
              approval.endpoint.accountID == context.session.accountID, current(), Date() < approval.expiresAt else { throw NativeFriendFailure.unavailable }
        self.context = context; self.approval = approval; self.transport = transport; self.current = current; self.unauthorized = unauthorized
        mode = approval.mode; viewerID = Int64(context.session.accountID)
    }
    public func picker(channel: Int64, section: NativeFriendDirectorySection, cursor: String?) async throws -> NativeFriendChannelInvitePicker {
        var fields = ["channel_id": String(channel), "section": section.rawValue]; if let cursor { fields["cursor"] = cursor }
        let p: NativeFriendChannelInvitePicker = try await exchange("picker", fields: fields)
        let d = p.directory
        guard d.viewerID == viewerID, p.channelID == String(channel), [1, 3].contains(p.guildKind), Self.id(p.guildID) != nil, !p.name.isEmpty, d.section == section,
              d.groupID == nil, !d.starredOnly, (0...500).contains(d.total), d.items.count <= 50, p.items.count == d.items.count,
              d.revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              NativeFriendMetadataValidation.validGroups(d.groups, viewerID: viewerID),
              d.hasMore == (d.nextCursor != nil), d.nextCursor.map(NativeFriendDirectoryService.validCursor) ?? true,
              d.items.allSatisfy({ $0.peerID > 0 && $0.peerID != viewerID && $0.state == .friend && $0.version > 0 && NativeFriendMetadataValidation.validRemark($0.friendRemark) }),
              Set(d.items.map(\.peerID)).count == d.items.count else { throw NativeFriendFailure.invalid }
        return p
    }
    public func batch(channel: Int64, request: String) async throws -> NativeFriendChannelInviteBatch {
        let value: NativeFriendChannelInviteBatch = try await exchange("batch", fields: ["channel_id": String(channel), "request_id": request])
        try valid(value); guard value.channelID == String(channel), value.requestID == request else { throw NativeFriendFailure.invalid }; return value
    }
    public func notice(invite: Int64) async throws -> NativeFriendChannelInviteBatch {
        let value: NativeFriendChannelInviteBatch = try await exchange("notice", fields: ["invite_id": String(invite)]); try valid(value)
        guard value.items.contains(where: { $0.inviteID == String(invite) }) else { throw NativeFriendFailure.invalid }; return value
    }
    private func valid(_ b: NativeFriendChannelInviteBatch) throws {
        guard b.viewerID == viewerID, [1, 3].contains(b.guildKind), Self.id(b.channelID) != nil, !b.name.isEmpty, b.name.utf16.count <= 200, UUID(uuidString: b.requestID) != nil, (1...10).contains(b.invited),
              b.items.count == b.invited, b.joined >= 0, b.pending >= 0, b.closed >= 0, b.joined + b.pending + b.closed == b.invited,
              Set(b.items.map(\.id)).count == b.items.count, b.items.allSatisfy({ Self.id($0.inviteID) != nil && Self.id($0.peerID) == $0.friend.peerID && $0.friend.peerID != viewerID && $0.friend.state == .friend && $0.friend.version > 0 && NativeFriendMetadataValidation.validRemark($0.friend.friendRemark) && ["JOINED", "INVITED", "PENDING_REVIEW", "REQUEST_ENDED", "INVITE_ENDED"].contains($0.state) &&
                  (b.guildKind != 3 || $0.parentMember != nil) && (b.targetChannel != true || ($0.parentMember != nil && $0.channelAccess != nil && $0.channelAccepted != nil && ($0.channelAccepted == true) == ($0.state == "JOINED"))) }) else { throw NativeFriendFailure.invalid }
    }
    public func landing(invite: Int64) async throws -> NativeFriendChannelInviteLanding {
        let p: NativeFriendChannelInviteLanding = try await exchange("landing", fields: ["invite_id": String(invite)])
        guard p.viewerID == viewerID, p.inviteID == String(invite), [1, 3].contains(p.guildKind), Self.id(p.guildID) != nil, p.rules.count <= 50,
              Set(p.rules.map(\.key)).count == p.rules.count,
              p.rules.allSatisfy({ !$0.title.isEmpty && !$0.body.isEmpty && $0.body.utf16.count <= 4000 && $0.key.range(of: "^[a-zA-Z0-9_-]{1,48}$", options: .regularExpression) != nil && $0.hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }),
              ["NOT_MEMBER", "ALREADY_MEMBER", "SCREENING_REQUIRED", "PENDING_REVIEW", "SOURCE_CHANGED", "EXPIRED", "REJECTED", "WITHDRAWN", "ACCESS_ENDED", "UNKNOWN", "JOIN_PAUSED", "INVITE_REVOKED", "INVITE_EXPIRED", "INVITE_EXHAUSTED"].contains(p.joinState) else { throw NativeFriendFailure.invalid }
        if p.isTargetChannel {
            guard Self.id(p.channelID ?? "") != nil, p.parentMember != nil, p.channelAccess != nil, p.channelAccepted != nil, p.inviteAvailable != nil, p.parentInviteAvailable != nil, p.channelReady != nil, p.joiningPaused != nil,
                  p.channelAccess != true || p.parentMember == true,
                  p.channelReady != true || (p.channelAccess == true && p.inviteAvailable == true && p.joiningPaused == false && p.channelAccepted == false && p.joinState == "ALREADY_MEMBER"),
                  p.channelName == nil || (p.channelAccess == true && !(p.channelName?.isEmpty ?? true)),
                  p.parentApplication.map({ Self.id($0.id) != nil && (0...5).contains($0.status) }) ?? true else { throw NativeFriendFailure.invalid }
        } else if p.admissionScope != nil && p.admissionScope != "SPACE" { throw NativeFriendFailure.invalid }
        return p
    }
    public func mine(before: String = "0") async throws -> NativeFriendChannelInviteMine {
        let p: NativeFriendChannelInviteMine = try await exchange("mine", fields: ["before": before])
        guard p.viewerID == viewerID, p.items.count <= 50, Set(p.items.map(\.id)).count == p.items.count,
              p.items.allSatisfy({ Self.id($0.inviteID) != nil && Self.id($0.channelID) != nil && UUID(uuidString: $0.requestID) != nil }),
              p.nextBefore == "0" || (Self.id(p.nextBefore) != nil && p.items.last?.inviteID == p.nextBefore) else { throw NativeFriendFailure.invalid }; return p
    }
    public func write(_ command: NativeFriendChannelInviteCommand) async throws -> NativeFriendChannelInviteReceipt {
        try command.validate(); guard canWrite else { throw NativeFriendFailure.notSent }
        let value: NativeFriendChannelInviteReceipt = try await exchange("command", body: JSONEncoder().encode(command))
        try valid(value, command: command); guard ["APPLIED", "REJECTED"].contains(value.outcome) else { throw NativeFriendFailure.unknown }; return value
    }
    public func recover(_ command: NativeFriendChannelInviteCommand) async throws -> NativeFriendChannelInviteReceipt {
        try command.validate()
        let value: NativeFriendChannelInviteReceipt = try await exchange("receipt", fields: ["request_id": command.requestID]); try valid(value, command: command); return value
    }
    public func receipt(request: String) async throws -> NativeFriendChannelInviteReceipt {
        let value: NativeFriendChannelInviteReceipt = try await exchange("receipt", fields: ["request_id": request])
        guard value.viewerID == viewerID, value.requestID == request, validOutcome(value) else { throw NativeFriendFailure.invalid }; return value
    }
    private func valid(_ r: NativeFriendChannelInviteReceipt, command: NativeFriendChannelInviteCommand) throws {
        guard r.viewerID == viewerID, r.requestID == command.requestID, validOutcome(r),
              r.outcome == "UNKNOWN" || (r.action == command.action && r.objectID == String(command.objectID) && r.payloadHash == command.proof) else { throw NativeFriendFailure.unknown }
    }
    private func validOutcome(_ r: NativeFriendChannelInviteReceipt) -> Bool {
        if r.outcome == "UNKNOWN" { return r.action == nil && r.objectID == nil && r.payloadHash == nil && r.errorCode == nil }
        guard let action = r.action, ["CREATE", "SUBMIT", "PARENT_SUBMIT", "ACCEPT_CHANNEL", "ACCEPT_RULES", "REVOKE"].contains(action),
              Self.id(r.objectID ?? "") != nil, r.payloadHash?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return false }
        return (r.outcome == "APPLIED" && r.errorCode == nil) || (r.outcome == "REJECTED" && r.errorCode == "FRIEND_INVITE_REJECTED")
    }
    nonisolated public static func id(_ raw: String) -> Int64? { guard let n = Int64(raw), n > 0, String(n) == raw else { return nil }; return n }
    private func exchange<T: Decodable>(_ suffix: String, fields: [String: String] = [:], body: Data? = nil) async throws -> T {
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.notSent }
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(NativeFriendChannelInviteApproval.prefix + suffix), resolvingAgainstBaseURL: false)!
        if body == nil { parts.queryItems = fields.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw NativeFriendFailure.invalid }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard NativeFriendChannelInviteTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
        let (data, status) = try await transport.send(request)
        guard isCurrent, !Task.isCancelled, data.count <= 524_288 else { throw NativeFriendFailure.unknown }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        if status == 401 || header?.code == 401 { unauthorized(); retired = true }
        // An HTTP/proxy error is not an original transactional rejection and cannot erase a dispatched intent.
        guard (200..<300).contains(status), let header else { throw NativeFriendFailure.unknown }
        guard header.code == 200 else { throw NativeFriendFailure.rejected(header.code) }
        return try JSONDecoder().decode(Payload<T>.self, from: data).data
    }
    private struct Header: Decodable { let code: Int }
    private struct Payload<T: Decodable>: Decodable { let data: T }
}
public enum NativeFriendChannelInviteTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendChannelInviteApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              now < approval.expiresAt, let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard let path = approval.endpoint.paths.first(where: { context.baseURL.appendingPathComponent($0) == origin.url }) else { return false }
        if path == NativeFriendChannelInviteApproval.prefix + "command" {
            guard request.httpMethod == "POST", parts.query == nil, let body = request.httpBody, body.count <= 32_768,
                  let command = try? JSONDecoder().decode(NativeFriendChannelInviteCommand.self, from: body), (try? command.validate()) != nil,
                  (try? JSONSerialization.jsonObject(with: body) as? NSDictionary) == (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? NSDictionary) else { return false }
            switch approval.mode {
            case .channel(let id): return command.action == "CREATE" ? command.objectID == id : command.action == "REVOKE"
            case .invite(let id, let joined): return joined ? command.action == "REVOKE" : command.objectID == id && ["SUBMIT", "PARENT_SUBMIT", "ACCEPT_CHANNEL", "ACCEPT_RULES"].contains(command.action)
            case .mine: return command.action == "REVOKE"
            }
        }
        guard request.httpMethod == "GET", request.httpBody == nil, let items = parts.queryItems,
              items.allSatisfy({ $0.value != nil }), Set(items.map(\.name)).count == items.count else { return false }
        let f = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) }); let suffix = String(path.dropFirst(NativeFriendChannelInviteApproval.prefix.count))
        if suffix == "receipt" { return Set(f.keys) == ["request_id"] && UUID(uuidString: f["request_id"] ?? "") != nil }
        if suffix == "mine" { return approval.mode == .mine && Set(f.keys) == ["before"] && (f["before"] == "0" || NativeFriendChannelInviteService.id(f["before"] ?? "") != nil) }
        if suffix == "picker" {
            guard case .channel(let id) = approval.mode else { return false }
            return Set(f.keys).isSubset(of: ["channel_id", "section", "cursor"]) && f["channel_id"] == String(id) && NativeFriendDirectorySection(rawValue: f["section"] ?? "") != nil && (f["cursor"].map(NativeFriendDirectoryService.validCursor) ?? true)
        }
        if suffix == "batch" {
            guard Set(f.keys) == ["channel_id", "request_id"], NativeFriendChannelInviteService.id(f["channel_id"] ?? "") != nil, UUID(uuidString: f["request_id"] ?? "") != nil else { return false }
            if case .channel(let id) = approval.mode { return f["channel_id"] == String(id) }; return approval.mode == .mine
        }
        if suffix == "landing", case .invite(let id, false) = approval.mode { return Set(f.keys) == ["invite_id"] && f["invite_id"] == String(id) }
        if suffix == "notice", case .invite(let id, true) = approval.mode { return Set(f.keys) == ["invite_id"] && f["invite_id"] == String(id) }
        return false
    }
}
