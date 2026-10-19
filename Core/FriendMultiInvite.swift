import Foundation

/// Reform plan v9 decision U02: in-app multi-select friend invites covering
/// selection, count and recipient review, sending, partial failure, retry and
/// return. A multi-select design is not proof that any invite was delivered.
/// The mini-program's existing team invite is a share link / invite code
/// (`/api/team/info`, `/api/team/join`), so per-friend sending is new App scope.
/// Client contract only: no batch-invite endpoint is reviewed; the maximum batch
/// size is a server fact injected by the caller and has no default.
public enum FriendInviteIssue: Error, Equatable { case invalid, overLimit, emptySelection, notReviewed, changedSinceReview, busy }

public struct FriendInviteTarget: Equatable, Hashable, Identifiable, Sendable {
    public let friendId: String
    public let displayName: String
    public var id: String { friendId }
    public init(friendId: String, displayName: String) throws {
        guard ReformWire.id(friendId), ReformWire.label(displayName, limit: 64) else { throw FriendInviteIssue.invalid }
        self.friendId = friendId; self.displayName = displayName
    }
}

public struct FriendMultiInvite: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case selecting, reviewed, sending, finished }
    public enum Delivery: Equatable, Sendable {
        case notSent
        case sent(inviteId: String)
        /// Rejected by the server (blocked, already in team, ineligible …). Not retried automatically.
        case rejected(reasonCode: String)
        /// Transport failure before any response; safe to retry with the same requestId.
        case failed
        /// Response lost after dispatch; must be read back before retry.
        case unknown
        /// Revoked by the sender after sending (U04: revoke wins over late "sent").
        case revoked
    }
    /// Invite purpose, e.g. a specific team; one batch never mixes targets.
    public let contextId: String
    public let maximum: Int
    public private(set) var phase: Phase = .selecting
    public private(set) var selected: [FriendInviteTarget] = []
    public private(set) var deliveries: [String: Delivery] = [:]
    /// Stable per-recipient request ids, kept across retries.
    public private(set) var requestIds: [String: String] = [:]
    private var reviewedIds: [String] = []

    public init(contextId: String, maximum: Int) throws {
        guard ReformWire.id(contextId), (1...200).contains(maximum) else { throw FriendInviteIssue.invalid }
        self.contextId = contextId; self.maximum = maximum
    }

    public mutating func toggle(_ target: FriendInviteTarget) throws {
        guard phase == .selecting || phase == .reviewed else { throw FriendInviteIssue.busy }
        if let index = selected.firstIndex(of: target) { selected.remove(at: index) }
        else { guard selected.count < maximum else { throw FriendInviteIssue.overLimit }; selected.append(target) }
        phase = .selecting
    }

    /// Review step: the user sees the exact count and names. Any later change invalidates it.
    public mutating func review() throws -> (count: Int, names: [String]) {
        guard phase == .selecting else { throw FriendInviteIssue.busy }
        guard !selected.isEmpty else { throw FriendInviteIssue.emptySelection }
        reviewedIds = selected.map(\.friendId)
        for target in selected where requestIds[target.friendId] == nil { requestIds[target.friendId] = UUID().uuidString }
        phase = .reviewed
        return (selected.count, selected.map(\.displayName))
    }

    /// Recipients to dispatch now: reviewed, and not yet sent / rejected / unknown.
    public mutating func beginSend() throws -> [(friendId: String, requestId: String)] {
        guard phase == .reviewed || phase == .finished else { throw FriendInviteIssue.notReviewed }
        guard reviewedIds == selected.map(\.friendId) else { throw FriendInviteIssue.changedSinceReview }
        let due = reviewedIds.filter { id in
            switch deliveries[id] ?? .notSent { case .notSent, .failed: return true; default: return false }
        }
        phase = .sending
        return due.compactMap { id in requestIds[id].map { (friendId: id, requestId: $0) } }
    }

    public mutating func record(friendId: String, requestId: String, _ delivery: Delivery) throws {
        guard phase == .sending, requestIds[friendId] == requestId else { throw FriendInviteIssue.invalid }
        if deliveries[friendId] == .revoked { return }
        if case .sent(let inviteId) = delivery { guard ReformWire.id(inviteId) else { throw FriendInviteIssue.invalid } }
        if case .rejected(let code) = delivery { guard ReformWire.label(code, limit: 64) else { throw FriendInviteIssue.invalid } }
        deliveries[friendId] = delivery
    }

    /// A readback for an `unknown` recipient. nil = the server has no invite for that requestId.
    public mutating func resolveUnknown(friendId: String, inviteId: String?) throws {
        guard deliveries[friendId] == .unknown else { throw FriendInviteIssue.invalid }
        if let inviteId { guard ReformWire.id(inviteId) else { throw FriendInviteIssue.invalid }; deliveries[friendId] = .sent(inviteId: inviteId) }
        else { deliveries[friendId] = .failed }
    }

    public mutating func markRevoked(friendId: String) { if deliveries[friendId] != nil { deliveries[friendId] = .revoked } }

    public mutating func finishRound() { if phase == .sending { phase = .finished } }

    public struct Summary: Equatable, Sendable { public let sent, rejected, retryable, unknown, revoked: Int }
    /// What the return screen states. "sent" counts only server-acknowledged invites.
    public var summary: Summary {
        var sent = 0, rejected = 0, retryable = 0, unknown = 0, revoked = 0
        for id in reviewedIds {
            switch deliveries[id] ?? .notSent {
            case .sent: sent += 1
            case .rejected: rejected += 1
            case .failed, .notSent: retryable += 1
            case .unknown: unknown += 1
            case .revoked: revoked += 1
            }
        }
        return Summary(sent: sent, rejected: rejected, retryable: retryable, unknown: unknown, revoked: revoked)
    }
}
