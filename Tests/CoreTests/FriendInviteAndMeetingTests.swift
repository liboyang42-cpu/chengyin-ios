import XCTest
@testable import QuestifyCore

final class FriendInviteAndMeetingTests: XCTestCase {
    private func friend(_ id: String) throws -> FriendInviteTarget { try FriendInviteTarget(friendId: id, displayName: "Friend " + id) }

    func testSelectionLimitReviewAndChangeInvalidation() throws {
        var batch = try FriendMultiInvite(contextId: "team-1", maximum: 2)
        try batch.toggle(friend("f1")); try batch.toggle(friend("f2"))
        XCTAssertThrowsError(try batch.toggle(friend("f3"))) { XCTAssertEqual($0 as? FriendInviteIssue, .overLimit) }
        XCTAssertThrowsError(try batch.beginSend()) { XCTAssertEqual($0 as? FriendInviteIssue, .notReviewed) }
        let review = try batch.review()
        XCTAssertEqual(review.count, 2); XCTAssertEqual(review.names, ["Friend f1", "Friend f2"])
        try batch.toggle(friend("f2")) // any change returns to selecting
        XCTAssertThrowsError(try batch.beginSend())
        XCTAssertEqual(try batch.review().count, 1)
    }

    func testPartialFailureRetriesOnlyFailedWithStableRequestIds() throws {
        var batch = try FriendMultiInvite(contextId: "team-1", maximum: 5)
        for id in ["f1", "f2", "f3", "f4"] { try batch.toggle(friend(id)) }
        _ = try batch.review()
        let first = try batch.beginSend()
        XCTAssertEqual(first.map(\.friendId), ["f1", "f2", "f3", "f4"])
        let ids = Dictionary(uniqueKeysWithValues: first.map { ($0.friendId, $0.requestId) })
        try batch.record(friendId: "f1", requestId: ids["f1"]!, .sent(inviteId: "inv-1"))
        try batch.record(friendId: "f2", requestId: ids["f2"]!, .rejected(reasonCode: "BLOCKED"))
        try batch.record(friendId: "f3", requestId: ids["f3"]!, .failed)
        try batch.record(friendId: "f4", requestId: ids["f4"]!, .unknown)
        XCTAssertThrowsError(try batch.record(friendId: "f1", requestId: "wrong-request", .failed))
        batch.finishRound()
        XCTAssertEqual(batch.summary, .init(sent: 1, rejected: 1, retryable: 1, unknown: 1, revoked: 0))
        let retry = try batch.beginSend()
        XCTAssertEqual(retry.map(\.friendId), ["f3"]); XCTAssertEqual(retry.first?.requestId, ids["f3"])
        try batch.resolveUnknown(friendId: "f4", inviteId: "inv-4")
        batch.markRevoked(friendId: "f1")
        try batch.record(friendId: "f1", requestId: ids["f1"]!, .sent(inviteId: "inv-1")) // late sent after revoke
        batch.finishRound()
        XCTAssertEqual(batch.summary, .init(sent: 1, rejected: 1, retryable: 1, unknown: 0, revoked: 1))
    }

    private func eligibility(formation: String = "CONFIRMED", status: TeamStatus = .full) throws -> TeamMeetingEligibility {
        try TeamMeetingEligibility(teamId: "team-1", meetingId: "meet-1", selfMemberId: "m-self", peerMemberId: "m-peer", formation: formation, teamStatus: status)
    }
    private func challenge(nonce: String = "nonce-abcdefghijklmnopqrstu", issuer: String = "m-peer", expires: Int64 = 1_793_505_660_000) throws -> TeamMeetingChallenge {
        try TeamMeetingChallenge(meetingId: "meet-1", teamId: "team-1", issuerMemberId: issuer, receiverMemberId: "m-self", purpose: TeamMeetingChallenge.purpose, nonce: nonce, keyVersion: "k1", signature: "signature-opaque-0001", issuedAtMillis: 1_793_505_600_000, expiresAtMillis: expires)
    }
    private let now = Date(timeIntervalSince1970: 1_793_505_610)

    func testMeetingRequiresServerConfirmedTeamAndRealNameOnlyHere() throws {
        XCTAssertThrowsError(try eligibility(formation: "PENDING")) { XCTAssertEqual($0 as? TeamMeetingIssue, .teamNotConfirmed) }
        XCTAssertThrowsError(try eligibility(status: .recruiting)) { XCTAssertEqual($0 as? TeamMeetingIssue, .teamNotConfirmed) }
        XCTAssertTrue(RealNameScope.requiresRealName(.strangerTeamMeeting))
        for flow in [RealNameScope.Flow.ordinaryPlay, .friendInvite, .mapRead, .teamJoin, .publish] { XCTAssertFalse(RealNameScope.requiresRealName(flow)) }
        var meeting = TeamFirstMeeting(eligibility: try eligibility(), realNameVerified: false)
        XCTAssertThrowsError(try meeting.beginHandshake()) { XCTAssertEqual($0 as? TeamMeetingIssue, .realNameRequired) }
        try meeting.realNameConfirmedByServer(); try meeting.beginHandshake()
        XCTAssertEqual(meeting.phase, .handshaking)
    }

    func testQRIsAlwaysOfferedAndNFCNeverWithoutVerification() {
        XCTAssertEqual(TeamMeetingHandshake.available(capabilities: .disabled, deviceReportsNFC: true), [.dynamicQR])
        XCTAssertEqual(TeamMeetingHandshake.available(capabilities: .syntheticFixture([.teamFirstMeeting, .meetingNFC]), deviceReportsNFC: true), [.dynamicQR])
    }

    func testChallengeBindingExpiryAndReplay() throws {
        var meeting = TeamFirstMeeting(eligibility: try eligibility(), realNameVerified: true)
        try meeting.beginHandshake()
        XCTAssertThrowsError(try meeting.scanned(challenge(issuer: "m-other"), deviceNow: now, serverOffset: 0)) { XCTAssertEqual($0 as? TeamMeetingIssue, .wrongBinding) }
        XCTAssertThrowsError(try meeting.scanned(challenge(), deviceNow: now.addingTimeInterval(3600), serverOffset: -3600 + 100)) { XCTAssertEqual($0 as? TeamMeetingIssue, .expired) }
        let body = try meeting.scanned(challenge(), deviceNow: now, serverOffset: 0, requestId: "meet-req-0001")
        XCTAssertEqual(body["purpose"], TeamMeetingChallenge.purpose); XCTAssertNil(body["latitude"])
        try meeting.serverDecision(requestId: "meet-req-0001", verified: false)
        XCTAssertEqual(meeting.phase, .handshaking)
        XCTAssertThrowsError(try meeting.scanned(challenge(), deviceNow: now, serverOffset: 0)) { XCTAssertEqual($0 as? TeamMeetingIssue, .replayed) }
        _ = try meeting.scanned(challenge(nonce: "nonce-zyxwvutsrqponmlkjihg"), deviceNow: now, serverOffset: 0, requestId: "meet-req-0002")
        try meeting.serverDecision(requestId: "meet-req-0002", verified: true)
        XCTAssertEqual(meeting.phase, .met)
    }

    func testCancelWinsOverLateVerification() throws {
        var meeting = TeamFirstMeeting(eligibility: try eligibility(), realNameVerified: true)
        try meeting.beginHandshake()
        _ = try meeting.scanned(challenge(), deviceNow: now, serverOffset: 0, requestId: "meet-req-0003")
        meeting.cancel()
        XCTAssertThrowsError(try meeting.serverDecision(requestId: "meet-req-0003", verified: true))
        XCTAssertEqual(meeting.phase, .cancelled)
        meeting.expire()
        XCTAssertEqual(meeting.phase, .cancelled)
    }
}
