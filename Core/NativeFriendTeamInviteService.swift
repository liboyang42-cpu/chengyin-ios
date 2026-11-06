import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NativeFriendTeamInviteApproval: Equatable {
    public static let prefix = "api/friend/team-invite/"
    public static let receipt = "api/team/original-request"
    public static let paths: Set<String> = [prefix + "picker", prefix + "landing", prefix + "mine", receipt]
    public let endpoint: OperationEndpointApproval
    public let mode: NativeFriendTeamInviteMode
    public let allowWrites: Bool
    public let issuanceID: UUID
    public let expiresAt: Date
    public init(endpoint: OperationEndpointApproval, mode: NativeFriendTeamInviteMode, allowWrites: Bool = false, expiresAt: Date, issuanceID: UUID = UUID()) throws {
        guard mode.valid, endpoint.paths == Self.paths, expiresAt.timeIntervalSince1970.isFinite else { throw NativeFriendFailure.invalid }
        self.endpoint = endpoint; self.mode = mode; self.allowWrites = allowWrites; self.expiresAt = expiresAt; self.issuanceID = issuanceID
    }
}
@MainActor public final class NativeFriendTeamInviteService {
    public let mode: NativeFriendTeamInviteMode
    public let viewerID: Int64
    private let context: RuntimeDependencyContext
    private let approval: NativeFriendTeamInviteApproval
    private let current: () -> Bool
    private let transport: any HTTPTransport
    private let unauthorized: () -> Void
    private var retired = false
    public var isCurrent: Bool { guard !retired, current(), Date() < approval.expiresAt else { retired = true; return false }; return true }
    public var canWrite: Bool { isCurrent && approval.allowWrites }
    public init(context: RuntimeDependencyContext, approval: NativeFriendTeamInviteApproval, transport: any HTTPTransport, current: @escaping () -> Bool, unauthorized: @escaping () -> Void) throws {
        guard context.market == .china, context.role == "player", approval.endpoint.baseURL == context.baseURL,
              approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              current(), Date() < approval.expiresAt else { throw NativeFriendFailure.unavailable }
        self.context = context; self.approval = approval; self.transport = transport; self.current = current; self.unauthorized = unauthorized
        mode = approval.mode; viewerID = Int64(context.session.accountID)
    }
    public func picker(team: Int64, section: NativeFriendDirectorySection, cursor: String?) async throws -> NativeFriendTeamInvitePicker {
        var fields = ["team_id": String(team), "section": section.rawValue]; if let cursor { fields["cursor"] = cursor }
        let p: NativeFriendTeamInvitePicker = try await exchange(NativeFriendTeamInviteApproval.prefix + "picker", fields: fields)
        let d = p.directory
        guard d.viewerID == viewerID, p.teamID == String(team), !p.name.isEmpty, d.section == section, d.groupID == nil, !d.starredOnly,
              (0...500).contains(d.total), d.items.count <= 50, p.items.count == d.items.count,
              d.revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              NativeFriendMetadataValidation.validGroups(d.groups, viewerID: viewerID), d.hasMore == (d.nextCursor != nil),
              d.nextCursor.map(NativeFriendDirectoryService.validCursor) ?? true,
              d.items.allSatisfy({ $0.peerID > 0 && $0.peerID != viewerID && $0.state == .friend && $0.version > 0 && NativeFriendMetadataValidation.validRemark($0.friendRemark) }),
              Set(d.items.map(\.peerID)).count == d.items.count else { throw NativeFriendFailure.invalid }; return p
    }
    public func landing(offer: String) async throws -> NativeFriendTeamOffer {
        let r: NativeFriendTeamOffer = try await exchange(NativeFriendTeamInviteApproval.prefix + "landing", fields: ["offer_id": offer]); try valid(r)
        guard r.offerID == offer else { throw NativeFriendFailure.invalid }; return r
    }
    public func mine(before: String = "0") async throws -> NativeFriendTeamInviteMine {
        let r: NativeFriendTeamInviteMine = try await exchange(NativeFriendTeamInviteApproval.prefix + "mine", fields: ["before": before])
        guard r.viewerID == viewerID, r.items.count <= 50, Set(r.items.map(\.id)).count == r.items.count,
              r.nextBefore == "0" || NativeFriendChannelInviteService.id(r.nextBefore) != nil else { throw NativeFriendFailure.invalid }
        try r.items.forEach(valid); return r
    }
    private func valid(_ r: NativeFriendTeamOffer) throws {
        guard r.viewerID == viewerID, UUID(uuidString: r.offerID)?.uuidString.lowercased() == r.offerID,
              NativeFriendChannelInviteService.id(r.teamID) != nil, !r.name.isEmpty, r.name.utf16.count <= 200, [1, 2].contains(r.joinMode),
              ["WAITING_CONFIRM", "PENDING_REVIEW", "JOINED", "DECLINED", "REJECTED", "WITHDRAWN", "REVOKED", "EXPIRED", "ACCESS_ENDED", "UNKNOWN"].contains(r.state),
              !r.canAct || r.state == "WAITING_CONFIRM" else { throw NativeFriendFailure.invalid }
        if r.recipient {
            guard let inviter = r.inviter, inviter.peerID > 0, inviter.peerID != viewerID, inviter.state == .friend, inviter.version > 0,
                  NativeFriendMetadataValidation.validRemark(inviter.friendRemark) else { throw NativeFriendFailure.invalid }
        } else if r.inviter != nil { throw NativeFriendFailure.invalid }
    }
    public func write(_ c: NativeFriendTeamInviteCommand) async throws -> NativeFriendTeamInviteReceipt {
        try c.validate(); guard canWrite else { throw NativeFriendFailure.notSent }
        let r: NativeFriendTeamInviteReceipt = try await exchange(NativeFriendTeamInviteApproval.receipt, body: c.raw); try valid(r, c); return r
    }
    public func recover(_ c: NativeFriendTeamInviteCommand) async throws -> NativeFriendTeamInviteReceipt {
        try c.validate(); let r: NativeFriendTeamInviteReceipt = try await exchange(NativeFriendTeamInviteApproval.receipt, fields: ["requestId": c.requestID]); try valid(r, c); return r
    }
    private func valid(_ r: NativeFriendTeamInviteReceipt, _ c: NativeFriendTeamInviteCommand) throws {
        guard r.contract == "ORIGINAL_TEAM_REQUEST_V1", r.requestId == c.requestID, ["UNKNOWN", "APPLIED", "REJECTED"].contains(r.outcome) else { throw NativeFriendFailure.unknown }
        if r.outcome == "UNKNOWN" {
            guard r.friendOffer == nil else { throw NativeFriendFailure.unknown }; return
        }
        guard r.action == c.action, r.teamId == c.teamID, r.targetKey == "friend-offer:\(c.teamID)", r.requestFingerprint == c.fingerprint,
              r.outcome != "REJECTED" || !(r.errorCode?.isEmpty ?? true) else { throw NativeFriendFailure.unknown }
        // A terminal receipt may predate the optional result projection. Never invent offer IDs for it.
        if let result = r.friendOffer {
            guard r.outcome == "APPLIED" else { throw NativeFriendFailure.unknown }
            if c.action == "FRIEND_OFFER" {
                guard result.offerID == nil, let offers = result.offers, let peers = c.body.peers,
                      offers.count == peers.count, Set(offers.map(\.peerID)) == Set(peers.map { String($0.id) }),
                      Set(offers.map(\.offerID)).count == offers.count,
                      offers.allSatisfy({ UUID(uuidString: $0.offerID)?.uuidString.lowercased() == $0.offerID }) else { throw NativeFriendFailure.unknown }
            } else {
                guard result.offers == nil, result.offerID == c.body.offerId else { throw NativeFriendFailure.unknown }
            }
        }
    }
    private func exchange<T: Decodable>(_ path: String, fields: [String: String] = [:], body: Data? = nil) async throws -> T {
        guard isCurrent, !Task.isCancelled else { throw NativeFriendFailure.notSent }
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if body == nil { parts.queryItems = fields.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw NativeFriendFailure.invalid }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard NativeFriendTeamInviteTransportPolicy.accepts(request, context: context, approval: approval) else { throw NativeFriendFailure.notSent }
        let (data, status) = try await transport.send(request)
        guard isCurrent, !Task.isCancelled, data.count <= 524_288 else { throw NativeFriendFailure.unknown }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        if status == 401 || header?.code == 401 { unauthorized(); retired = true }
        guard (200..<300).contains(status), header?.code == 200 else { throw NativeFriendFailure.unknown }
        return try JSONDecoder().decode(Payload<T>.self, from: data).data
    }
    private struct Header: Decodable { let code: Int }
    private struct Payload<T: Decodable>: Decodable { let data: T }
}
public enum NativeFriendTeamInviteTransportPolicy {
    public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext, approval: NativeFriendTeamInviteApproval, now: Date = Date()) -> Bool {
        guard context.market == .china, context.role == "player", !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              approval.endpoint.baseURL == context.baseURL, approval.endpoint.namespace == context.session.namespace, approval.endpoint.accountID == context.session.accountID,
              now < approval.expiresAt, let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        var origin = parts; origin.query = nil
        guard let path = approval.endpoint.paths.first(where: { context.baseURL.appendingPathComponent($0) == origin.url }) else { return false }
        if request.httpMethod == "POST" {
            guard path == NativeFriendTeamInviteApproval.receipt, parts.query == nil, approval.allowWrites, let raw = request.httpBody,
                  let c = try? NativeFriendTeamInviteCommand.fromRaw(raw) else { return false }
            switch approval.mode {
            case .team(let team): return c.action == "FRIEND_OFFER" && c.teamID == team
            case .offer(let id): return c.body.offerId == id && ["FRIEND_CONFIRM", "FRIEND_DECLINE", "FRIEND_REVOKE"].contains(c.action)
            case .mine: return c.action == "FRIEND_REVOKE"
            }
        }
        guard request.httpMethod == "GET", request.httpBody == nil, let items = parts.queryItems, items.allSatisfy({ $0.value != nil }), Set(items.map(\.name)).count == items.count else { return false }
        let f = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        if path == NativeFriendTeamInviteApproval.receipt { return Set(f.keys) == ["requestId"] && UUID(uuidString: f["requestId"] ?? "")?.uuidString.lowercased() == f["requestId"] }
        if path == NativeFriendTeamInviteApproval.prefix + "mine" { return Set(f.keys) == ["before"] && (f["before"] == "0" || NativeFriendChannelInviteService.id(f["before"] ?? "") != nil) }
        if path == NativeFriendTeamInviteApproval.prefix + "landing" {
            guard Set(f.keys) == ["offer_id"], let id = f["offer_id"], UUID(uuidString: id)?.uuidString.lowercased() == id else { return false }
            if case .offer(let scoped) = approval.mode { return scoped == id }; return approval.mode == .mine
        }
        if path == NativeFriendTeamInviteApproval.prefix + "picker", case .team(let team) = approval.mode {
            return Set(f.keys).isSubset(of: ["team_id", "section", "cursor"]) && f["team_id"] == String(team) && NativeFriendDirectorySection(rawValue: f["section"] ?? "") != nil && (f["cursor"].map(NativeFriendDirectoryService.validCursor) ?? true)
        }
        return false
    }
}
