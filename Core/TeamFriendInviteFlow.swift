import Foundation

/// Reform plan v9 U02 (multi-select friend invites) and U04 (revoke wins) as a dormant
/// client flow for one team. The mini-program only shares an invite code; per-friend sending
/// is new App scope with no reviewed endpoint, so there is no production sender. The flow is
/// closed unless `ReformWorldCapabilities.friendMultiInvite` is on, which only DEBUG fixtures can do.
/// The maximum batch size and every delivery outcome are server facts from the sender port.
@MainActor public protocol TeamFriendInviteSending: AnyObject {
    /// Friends the server allows this member to invite into this team, plus the server batch limit.
    func invitableFriends(teamID: Int) async throws -> (friends: [FriendInviteTarget], maximum: Int)
    /// One recipient per call; the same `requestId` is reused on every retry for that recipient.
    func send(teamID: Int, friendId: String, requestId: String) async -> FriendMultiInvite.Delivery
    /// Readback for a lost response. Returns the invite id, or nil when the server has none.
    func readback(teamID: Int, requestId: String) async throws -> String?
    /// Returns the server version of the revoked record, or nil when the outcome is unknown.
    func revoke(teamID: Int, inviteId: String) async -> Int64?
}

@MainActor public final class TeamFriendInviteFlow {
    public enum Phase: Equatable { case closed, loading, failed, ready }
    public let teamID: Int
    public private(set) var phase: Phase = .closed
    public private(set) var friends: [FriendInviteTarget] = []
    public private(set) var batch: FriendMultiInvite?
    public private(set) var reviewed: (count: Int, names: [String])?
    public private(set) var issue: FriendInviteIssue?
    public private(set) var busy = false
    /// U04 per-invite terminal state; a revoke can never be replaced by a late success.
    public private(set) var revokeStates: [String: RevokeWinsState] = [:]
    /// Revokes whose response was lost. The invite is not shown as revoked until the server says so.
    public private(set) var revokeUnknown: Set<String> = []
    private let sender: (any TeamFriendInviteSending)?
    private let capabilities: ReformWorldCapabilities
    private var generation: UInt64 = 0

    /// `detail` must be a fresh server read. Only a joined member of a recruiting team may invite.
    public static func eligible(_ detail: TeamDetail?) -> Bool {
        guard let detail else { return false }
        return detail.joined == true && detail.team.status == .recruiting
    }

    public init(teamID: Int, sender: (any TeamFriendInviteSending)?, capabilities: ReformWorldCapabilities = .disabled) {
        self.teamID = teamID; self.sender = sender; self.capabilities = capabilities
    }

    public var available: Bool { capabilities.allows(.friendMultiInvite) && sender != nil && teamID > 0 }

    public func open() async {
        guard available, let sender, !busy else { phase = .closed; return }
        generation &+= 1; let stamp = generation
        phase = .loading; issue = nil; busy = true
        defer { if generation == stamp { busy = false } }
        do {
            let result = try await sender.invitableFriends(teamID: teamID)
            guard generation == stamp, !Task.isCancelled else { return }
            guard Set(result.friends.map(\.friendId)).count == result.friends.count else { throw FriendInviteIssue.invalid }
            batch = try FriendMultiInvite(contextId: "team-\(teamID)", maximum: result.maximum)
            friends = result.friends; reviewed = nil; phase = .ready
        } catch {
            guard generation == stamp else { return }
            friends = []; batch = nil; phase = .failed
        }
    }

    public func isSelected(_ friend: FriendInviteTarget) -> Bool { batch?.selected.contains(friend) == true }

    public func toggle(_ friend: FriendInviteTarget) {
        guard !busy, var value = batch, friends.contains(friend) else { return }
        do { try value.toggle(friend); batch = value; reviewed = nil; issue = nil }
        catch { issue = error as? FriendInviteIssue }
    }

    /// Explicit review: exact count and names. Any later toggle invalidates it.
    public func review() {
        guard !busy, var value = batch else { return }
        do { reviewed = try value.review(); batch = value; issue = nil }
        catch { issue = error as? FriendInviteIssue }
    }

    /// Sends to reviewed recipients that are not sent, rejected or unknown. Retries reuse request ids.
    public func send() async {
        guard available, let sender, !busy, var value = batch, reviewed != nil else { return }
        let due: [(friendId: String, requestId: String)]
        do { due = try value.beginSend() } catch { issue = error as? FriendInviteIssue; return }
        generation &+= 1; let stamp = generation
        batch = value; busy = true
        defer { if generation == stamp { busy = false } }
        for item in due {
            let delivery = await sender.send(teamID: teamID, friendId: item.friendId, requestId: item.requestId)
            guard generation == stamp, var current = batch else { return }
            try? current.record(friendId: item.friendId, requestId: item.requestId, delivery)
            batch = current
            if case .sent(let inviteId) = delivery, var state = revokeStates[item.friendId] ?? (try? RevokeWinsState(subjectId: inviteId)) {
                if let event = try? RevokeWinsEvent(subjectId: state.subjectId, kind: .offered, serverVersion: nil, source: .lateResponse) { try? state.apply(event) }
                revokeStates[item.friendId] = state
            }
        }
        guard generation == stamp, var current = batch else { return }
        current.finishRound(); batch = current
    }

    /// Lost responses are read back before anything else; only a confirmed absence becomes retryable.
    public func readBackUnknown() async {
        guard available, let sender, !busy, var value = batch else { return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        for (friendId, delivery) in value.deliveries where delivery == .unknown {
            guard let requestId = value.requestIds[friendId] else { continue }
            let found: String?
            do { found = try await sender.readback(teamID: teamID, requestId: requestId) }
            catch { continue } // A failed readback keeps the recipient unknown.
            guard generation == stamp else { return }
            try? value.resolveUnknown(friendId: friendId, inviteId: found)
        }
        guard generation == stamp else { return }
        batch = value
    }

    /// U04: once the server confirms a revoke the invite stays revoked, whatever arrives later.
    public func revoke(friendId: String) async {
        guard available, let sender, !busy, var value = batch,
              case .sent(let inviteId) = value.deliveries[friendId] ?? .notSent else { return }
        generation &+= 1; let stamp = generation; busy = true
        defer { if generation == stamp { busy = false } }
        guard let version = await sender.revoke(teamID: teamID, inviteId: inviteId) else { revokeUnknown.insert(friendId); return }
        revokeUnknown.remove(friendId)
        guard generation == stamp else { return }
        var state = revokeStates[friendId] ?? (try? RevokeWinsState(subjectId: inviteId))
        if let event = try? RevokeWinsEvent(subjectId: inviteId, kind: .revoked, serverVersion: version, source: .serverReadback) { try? state?.apply(event) }
        revokeStates[friendId] = state
        value.markRevoked(friendId: friendId); batch = value
    }

    /// A server push or readback for a sent invite. Funnelled through the revoke-wins ledger.
    public func apply(friendId: String, kind: RevokeWinsEvent.Kind, serverVersion: Int64, source: RevokeWinsEvent.Source) {
        guard var state = revokeStates[friendId],
              let event = try? RevokeWinsEvent(subjectId: state.subjectId, kind: kind, serverVersion: serverVersion, source: source) else { return }
        _ = try? state.apply(event)
        revokeStates[friendId] = state
        if state.display == .revoked, var value = batch { value.markRevoked(friendId: friendId); batch = value }
    }

    public func close() { generation &+= 1; busy = false; phase = .closed; reviewed = nil; issue = nil }
}
