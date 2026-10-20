#if canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
import XCTest
@testable import Questify

@MainActor
final class TeamMeetingHandshakeSectionViewTests: XCTestCase {
    func testMeetingCardSectionPresentationAndCallbacks() throws {
        let eligibility = try TeamMeetingEligibility(
            teamId: "team-101",
            meetingId: "meet-202",
            selfMemberId: "member-a",
            peerMemberId: "member-b",
            formation: "CONFIRMED",
            teamStatus: .full
        )
        var meeting = TeamFirstMeeting(eligibility: eligibility, realNameVerified: true)
        let readyCard = TeamMeetingHandshakePresentation.presentMeeting(
            meeting,
            capabilities: .disabled,
            deviceReportsNFC: true
        )

        XCTAssertTrue(readyCard.noInterestMatching)
        XCTAssertTrue(readyCard.realNameScopedOnlyToStrangerMeeting)
        XCTAssertTrue(readyCard.qrAlwaysOffered)
        XCTAssertFalse(readyCard.nfcOffered)
        XCTAssertTrue(readyCard.canBeginHandshake)
        XCTAssertFalse(readyCard.canScanPeerCode)

        var handshakeBegan = false
        let readyView = TeamMeetingHandshakeSectionView(
            meetingCard: readyCard,
            onBeginHandshake: { handshakeBegan = true }
        )
        XCTAssertEqual(readyView.meetingCard, readyCard)
        readyView.onBeginHandshake?()
        XCTAssertTrue(handshakeBegan)

        try meeting.beginHandshake()
        let issuedMillis: Int64 = 1_792_369_800_000
        let expiresMillis: Int64 = 1_792_369_860_000
        let challenge = try TeamMeetingChallenge(
            meetingId: "meet-202",
            teamId: "team-101",
            issuerMemberId: "member-a",
            receiverMemberId: "member-b",
            purpose: TeamMeetingChallenge.purpose,
            nonce: "nonce_1234567890123456789012",
            keyVersion: "kv-1",
            signature: "sig_1234567890123456",
            issuedAtMillis: issuedMillis,
            expiresAtMillis: expiresMillis
        )
        let handshakingCard = TeamMeetingHandshakePresentation.presentMeeting(
            meeting,
            myChallenge: challenge,
            capabilities: .disabled,
            deviceReportsNFC: true,
            deviceNow: Date(timeIntervalSince1970: Double(issuedMillis) / 1000 + 10),
            serverOffset: 0
        )

        XCTAssertTrue(handshakingCard.canScanPeerCode)
        XCTAssertFalse(handshakingCard.isChallengeExpired)
        XCTAssertNotNil(handshakingCard.activeChallengePayload)

        var scannedCode = false
        let handshakingView = TeamMeetingHandshakeSectionView(
            meetingCard: handshakingCard,
            onScanPeerQRCode: { scannedCode = true }
        )
        _ = handshakingView.body
        handshakingView.onScanPeerQRCode?()
        XCTAssertTrue(scannedCode)
    }

    func testInviteBatchCardSectionPresentationFailedRetryAndUnknownReadbackGate() throws {
        var batch = try FriendMultiInvite(contextId: "team-101", maximum: 5)
        let friendA = try FriendInviteTarget(friendId: "friend-a", displayName: "Alice")
        let friendB = try FriendInviteTarget(friendId: "friend-b", displayName: "Bob")
        let friendC = try FriendInviteTarget(friendId: "friend-c", displayName: "Carol")

        try batch.toggle(friendA)
        try batch.toggle(friendB)
        try batch.toggle(friendC)
        _ = try batch.review()

        let reviewedCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertTrue(reviewedCard.isReviewValid)
        XCTAssertTrue(reviewedCard.canSendReviewed)
        XCTAssertEqual(reviewedCard.recipientRows.count, 3)
        XCTAssertTrue(reviewedCard.recipientRows.allSatisfy { $0.stableRequestId != nil })

        let dispatched = try batch.beginSend()
        let reqMap = Dictionary(uniqueKeysWithValues: dispatched)
        try batch.record(friendId: "friend-a", requestId: try XCTUnwrap(reqMap["friend-a"]), .sent(inviteId: "inv-1"))
        try batch.record(friendId: "friend-b", requestId: try XCTUnwrap(reqMap["friend-b"]), .failed)
        try batch.record(friendId: "friend-c", requestId: try XCTUnwrap(reqMap["friend-c"]), .unknown)
        batch.finishRound()

        let unknownGatedCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertTrue(unknownGatedCard.requiresUnknownReadbackFirst)
        XCTAssertFalse(unknownGatedCard.canRetryFailedNow)
        XCTAssertEqual(unknownGatedCard.unknownRecipientIds, ["friend-c"])
        XCTAssertEqual(unknownGatedCard.retryableRecipientIds, ["friend-b"])

        var readbackIds: [String] = []
        let gatedView = TeamMeetingHandshakeSectionView(
            inviteBatchCard: unknownGatedCard,
            onReadbackUnknownInvites: { readbackIds = $0 }
        )
        _ = gatedView.body
        gatedView.onReadbackUnknownInvites?(unknownGatedCard.unknownRecipientIds)
        XCTAssertEqual(readbackIds, ["friend-c"])

        try batch.resolveUnknown(friendId: "friend-c", inviteId: "inv-3")
        let retryReadyCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertFalse(retryReadyCard.requiresUnknownReadbackFirst)
        XCTAssertTrue(retryReadyCard.canRetryFailedNow)
        XCTAssertEqual(retryReadyCard.retryableRecipientIds, ["friend-b"])

        var retriedIds: [String] = []
        let retryView = TeamMeetingHandshakeSectionView(
            inviteBatchCard: retryReadyCard,
            onRetryFailedInvites: { retriedIds = $0 }
        )
        _ = retryView.body
        retryView.onRetryFailedInvites?(retryReadyCard.retryableRecipientIds)
        XCTAssertEqual(retriedIds, ["friend-b"])
    }

    func testRevokeLedgerBadgeAndDualZoneBeijingDeadlineBannerPresentation() throws {
        let events: [RevokeWinsEvent] = [
            try RevokeWinsEvent(subjectId: "inv-subject-1", kind: .offered, serverVersion: 1, source: .serverReadback),
            try RevokeWinsEvent(subjectId: "inv-subject-1", kind: .revoked, serverVersion: 2, source: .serverPush),
            try RevokeWinsEvent(subjectId: "inv-subject-1", kind: .accepted, serverVersion: 3, source: .lateResponse)
        ]
        let revokeBadge = try TeamMeetingHandshakePresentation.evaluateRevokeLedger(
            subjectId: "inv-subject-1",
            events: events
        )
        XCTAssertTrue(revokeBadge.isRevokeFinal)
        XCTAssertEqual(revokeBadge.display, .revoked)
        XCTAssertEqual(revokeBadge.pendingToast, .revoked)

        // 2026-10-19T08:30:00 in Asia/Shanghai (+08:00) == 1_792_369_800_000 ms
        let deadline = try BeijingDeadline(
            epochMilliseconds: 1_792_369_800_000,
            beijingCivil: "2026-10-19T08:30:00"
        )
        let tokyoZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let banner = TeamMeetingHandshakePresentation.presentDeadlineBanner(
            deadline,
            phoneZone: tokyoZone,
            deviceNow: Date(timeIntervalSince1970: 1_792_369_700),
            serverOffset: 0
        )

        XCTAssertTrue(banner.showsDualZone)
        XCTAssertNotNil(banner.governingBeijingTimeText)
        XCTAssertTrue(banner.allowsSubmission)

        let combinedView = TeamMeetingHandshakeSectionView(
            revokeBadge: revokeBadge,
            deadlineBanner: banner
        )
        XCTAssertEqual(combinedView.revokeBadge, revokeBadge)
        XCTAssertEqual(combinedView.deadlineBanner, banner)
        _ = combinedView.body
    }
}
