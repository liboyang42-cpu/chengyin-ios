#if DEBUG
import Foundation

/// Offline fixtures for the dormant U02 / U05–U07 team flows. Every person, id, limit and
/// outcome is synthetic and exists only to exercise the client state machines.
@MainActor public final class TeamSyntheticFriendInviteSender: TeamFriendInviteSending {
    public enum Scenario: String { case content, partial, unknown, readFailure }
    public let scenario: Scenario
    /// Synthetic limit standing in for a server fact; not a product value.
    public var maximum = 3
    public private(set) var sentRequests: [String: String] = [:]
    public private(set) var sendCount = 0
    public var revokeVersion: Int64? = 7
    public init(scenario: Scenario = .content) { self.scenario = scenario }
    public func invitableFriends(teamID: Int) async throws -> (friends: [FriendInviteTarget], maximum: Int) {
        if scenario == .readFailure { throw FriendInviteIssue.invalid }
        let friends = try ["sf-1": "Synthetic friend A", "sf-2": "Synthetic friend B", "sf-3": "Synthetic friend C", "sf-4": "Synthetic friend D"]
            .sorted { $0.key < $1.key }.map { try FriendInviteTarget(friendId: $0.key, displayName: $0.value) }
        return (friends, maximum)
    }
    public func send(teamID: Int, friendId: String, requestId: String) async -> FriendMultiInvite.Delivery {
        sendCount += 1
        if let existing = sentRequests[requestId] { return .sent(inviteId: existing) }
        switch (scenario, friendId) {
        case (.partial, "sf-2"): return .rejected(reasonCode: "SYNTHETIC_ALREADY_IN_TEAM")
        case (.partial, "sf-3") where sendCount <= 3: return .failed
        case (.unknown, "sf-1"): sentRequests[requestId] = "si-\(friendId)"; return .unknown
        default: sentRequests[requestId] = "si-\(friendId)"; return .sent(inviteId: "si-\(friendId)")
        }
    }
    public func readback(teamID: Int, requestId: String) async throws -> String? { sentRequests[requestId] }
    public func revoke(teamID: Int, inviteId: String) async -> Int64? { revokeVersion }
}

@MainActor public final class TeamSyntheticMeetingService: TeamMeetingServing {
    public enum Scenario: String { case content, realNameRequired, notEligible, rejectFirst, lostConfirmation }
    public let scenario: Scenario
    public var realName: Bool
    public private(set) var confirmations: [String] = []
    private var decided: [String: Bool] = [:]
    public init(scenario: Scenario = .content) { self.scenario = scenario; realName = scenario != .realNameRequired }
    public static let meetingId = "synthetic-meeting-1"
    public static let selfMember = "901", peerMember = "902"
    public func eligibility(teamID: Int) async throws -> TeamMeetingEligibility? {
        if scenario == .notEligible { return nil }
        return try TeamMeetingEligibility(teamId: "\(teamID)", meetingId: Self.meetingId, selfMemberId: Self.selfMember,
                                          peerMemberId: Self.peerMember, formation: "CONFIRMED", teamStatus: .full)
    }
    public func realNameVerified(meetingId: String) async throws -> Bool { realName }
    public func issueChallenge(meetingId: String) async throws -> TeamMeetingChallenge {
        try Self.challenge(teamID: 4101, issuer: Self.selfMember, receiver: Self.peerMember, nonce: "SyntheticOwnNonce000000001")
    }
    public func serverClockOffset() async throws -> TimeInterval { 0 }
    public func confirm(_ fields: [String: String]) async -> Bool? {
        guard let requestId = fields["requestId"] else { return false }
        confirmations.append(requestId)
        switch scenario {
        case .rejectFirst where confirmations.count == 1: decided[requestId] = false; return false
        case .lostConfirmation: decided[requestId] = true; return nil
        default: decided[requestId] = true; return true
        }
    }
    public func confirmationReadback(meetingId: String, requestId: String) async throws -> Bool? { decided[requestId] }
    public func cancel(meetingId: String) async -> Bool { true }
    /// The peer's code as a fixture "scan" would decode it.
    public static func peerChallenge(teamID: Int = 4101, nonce: String = "SyntheticPeerNonce00000001", now: Date = Date(), lifetime: Int64 = 60_000) throws -> TeamMeetingChallenge {
        try challenge(teamID: teamID, issuer: peerMember, receiver: selfMember, nonce: nonce, now: now, lifetime: lifetime)
    }
    static func challenge(teamID: Int, issuer: String, receiver: String, nonce: String, now: Date = Date(), lifetime: Int64 = 60_000) throws -> TeamMeetingChallenge {
        let issued = Int64(now.timeIntervalSince1970 * 1000)
        return try TeamMeetingChallenge(meetingId: meetingId, teamId: "\(teamID)", issuerMemberId: issuer, receiverMemberId: receiver,
                                        purpose: TeamMeetingChallenge.purpose, nonce: nonce, keyVersion: "synthetic-k1",
                                        signature: "SyntheticOpaqueSignature", issuedAtMillis: issued, expiresAtMillis: issued + lifetime)
    }
}
#endif
