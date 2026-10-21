import XCTest
@testable import QuestifyCore

final class TeamMeetingHandshakePresentationTests: XCTestCase {

    // MARK: - Helpers

    private func makeEligibility(
        formation: String = "CONFIRMED",
        status: TeamStatus = .full
    ) throws -> TeamMeetingEligibility {
        try TeamMeetingEligibility(
            teamId: "team-101",
            meetingId: "meet-202",
            selfMemberId: "member-self",
            peerMemberId: "member-peer",
            formation: formation,
            teamStatus: status
        )
    }

    private func makeSelfChallenge(
        issuer: String = "member-self",
        receiver: String = "member-peer",
        nonce: String = "nonce-abcdefghijklmnopqrstu",
        expiresAtMillis: Int64 = 1_793_505_660_000
    ) throws -> TeamMeetingChallenge {
        try TeamMeetingChallenge(
            meetingId: "meet-202",
            teamId: "team-101",
            issuerMemberId: issuer,
            receiverMemberId: receiver,
            purpose: TeamMeetingChallenge.purpose,
            nonce: nonce,
            keyVersion: "kv1",
            signature: "signature-opaque-token-01",
            issuedAtMillis: 1_793_505_600_000,
            expiresAtMillis: expiresAtMillis
        )
    }

    // MARK: - U05–U07 Tests

    func testMeetingEligibilityConfirmedOnlyAndRealNameStrictlyScoped() throws {
        XCTAssertEqual(
            TeamMeetingHandshakePresentation.evaluateEligibility(
                teamId: "team-101",
                meetingId: "meet-202",
                selfMemberId: "member-self",
                peerMemberId: "member-peer",
                formation: "PENDING",
                teamStatus: .full
            ),
            .teamNotConfirmed
        )
        XCTAssertEqual(
            TeamMeetingHandshakePresentation.evaluateEligibility(
                teamId: "team-101",
                meetingId: "meet-202",
                selfMemberId: "member-self",
                peerMemberId: "member-peer",
                formation: "CONFIRMED",
                teamStatus: .recruiting
            ),
            .teamNotConfirmed
        )
        XCTAssertEqual(
            TeamMeetingHandshakePresentation.evaluateEligibility(
                teamId: "team-101",
                meetingId: "meet-202",
                selfMemberId: "member-same",
                peerMemberId: "member-same",
                formation: "CONFIRMED",
                teamStatus: .full
            ),
            .invalidBinding
        )

        let eligibility = try makeEligibility(formation: "CONFIRMED", status: .inProgress)
        XCTAssertEqual(
            TeamMeetingHandshakePresentation.evaluateEligibility(
                teamId: "team-101",
                meetingId: "meet-202",
                selfMemberId: "member-self",
                peerMemberId: "member-peer",
                formation: "CONFIRMED",
                teamStatus: .inProgress
            ),
            .eligible(eligibility)
        )
        XCTAssertTrue(TeamMeetingHandshakePresentation.isRealNameStrictlyScoped())

        var meeting = TeamFirstMeeting(eligibility: eligibility, realNameVerified: false)
        let step1 = TeamMeetingHandshakePresentation.presentMeeting(meeting)
        XCTAssertEqual(step1.phase, .realNameRequired)
        XCTAssertTrue(step1.requiresRealNameCheck)
        XCTAssertFalse(step1.canBeginHandshake)
        XCTAssertTrue(step1.noInterestMatching)
        XCTAssertTrue(step1.realNameScopedOnlyToStrangerMeeting)

        try meeting.realNameConfirmedByServer()
        let step2 = TeamMeetingHandshakePresentation.presentMeeting(meeting)
        XCTAssertEqual(step2.phase, .readyToMeet)
        XCTAssertFalse(step2.requiresRealNameCheck)
        XCTAssertTrue(step2.canBeginHandshake)
        XCTAssertFalse(step2.isTerminal)

        meeting.cancel()
        let cancelledCard = TeamMeetingHandshakePresentation.presentMeeting(meeting)
        XCTAssertEqual(cancelledCard.phase, .cancelled)
        XCTAssertTrue(cancelledCard.isTerminal)
    }

    func testHandshakeOffersDynamicQROnlyWithNFCPermanentlyOffAndActiveChallengePayload() throws {
        let eligibility = try makeEligibility()
        var meeting = TeamFirstMeeting(eligibility: eligibility, realNameVerified: true)
        try meeting.beginHandshake()

        let baseNow = Date(timeIntervalSince1970: 1_793_505_610)
        let challenge = try makeSelfChallenge()
        let capabilities = ReformWorldCapabilities.syntheticFixture([.teamFirstMeeting, .meetingNFC])

        let activeCard = TeamMeetingHandshakePresentation.presentMeeting(
            meeting,
            myChallenge: challenge,
            capabilities: capabilities,
            deviceReportsNFC: true,
            deviceNow: baseNow,
            serverOffset: 0
        )
        XCTAssertEqual(activeCard.availableHandshakes, [.dynamicQR])
        XCTAssertTrue(activeCard.qrAlwaysOffered)
        XCTAssertFalse(activeCard.nfcOffered)
        XCTAssertTrue(activeCard.canScanPeerCode)
        XCTAssertFalse(activeCard.isChallengeExpired)
        XCTAssertEqual(
            activeCard.activeChallengePayload,
            "meet-202.member-self.nonce-abcdefghijklmnopqrstu.kv1.signature-opaque-token-01"
        )

        // Server offset moves estimated time past expiry even when deviceNow looks early.
        let expiredCard = TeamMeetingHandshakePresentation.presentMeeting(
            meeting,
            myChallenge: challenge,
            capabilities: capabilities,
            deviceReportsNFC: true,
            deviceNow: baseNow,
            serverOffset: 120
        )
        XCTAssertTrue(expiredCard.isChallengeExpired)
        XCTAssertNil(expiredCard.activeChallengePayload)

        // Challenge issued by peer instead of self is never rendered as own QR payload.
        let peerIssued = try makeSelfChallenge(issuer: "member-peer", receiver: "member-self")
        let wrongIssuerCard = TeamMeetingHandshakePresentation.presentMeeting(
            meeting,
            myChallenge: peerIssued,
            capabilities: capabilities,
            deviceReportsNFC: true,
            deviceNow: baseNow,
            serverOffset: 0
        )
        XCTAssertTrue(wrongIssuerCard.isChallengeExpired)
        XCTAssertNil(wrongIssuerCard.activeChallengePayload)
    }

    // MARK: - U02 & U04 Tests

    func testFriendMultiInviteReviewInvalidationOnSelectionChange() throws {
        var batch = try FriendMultiInvite(contextId: "team-101", maximum: 3)
        let f1 = try FriendInviteTarget(friendId: "friend-1", displayName: "阿明")
        let f2 = try FriendInviteTarget(friendId: "friend-2", displayName: "小陆")

        try batch.toggle(f1)
        try batch.toggle(f2)

        let selectingCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertEqual(selectingCard.phase, .selecting)
        XCTAssertEqual(selectingCard.selectionCounterText, "2 / 3")
        XCTAssertFalse(selectingCard.isReviewValid)
        XCTAssertFalse(selectingCard.canSendReviewed)

        _ = try batch.review()
        let reviewedCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertEqual(reviewedCard.phase, .reviewed)
        XCTAssertTrue(reviewedCard.isReviewValid)
        XCTAssertTrue(reviewedCard.canSendReviewed)

        // Any selection change invalidates the review and returns to `.selecting`.
        try batch.toggle(f2)
        let invalidatedCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertEqual(invalidatedCard.phase, .selecting)
        XCTAssertEqual(invalidatedCard.selectionCounterText, "1 / 3")
        XCTAssertFalse(invalidatedCard.isReviewValid)
        XCTAssertFalse(invalidatedCard.canSendReviewed)
    }

    func testFriendMultiInvitePartialFailureRetriesOnlyFailedAndAwaitsUnknownReadback() throws {
        var batch = try FriendMultiInvite(contextId: "team-101", maximum: 5)
        for id in ["f1", "f2", "f3", "f4"] {
            try batch.toggle(FriendInviteTarget(friendId: id, displayName: "好友-\(id)"))
        }
        _ = try batch.review()
        let dispatches = try batch.beginSend()
        let requestMap = Dictionary(uniqueKeysWithValues: dispatches.map { ($0.friendId, $0.requestId) })

        try batch.record(friendId: "f1", requestId: requestMap["f1"]!, .sent(inviteId: "inv-1"))
        try batch.record(friendId: "f2", requestId: requestMap["f2"]!, .rejected(reasonCode: "ALREADY_IN_TEAM"))
        try batch.record(friendId: "f3", requestId: requestMap["f3"]!, .failed)
        try batch.record(friendId: "f4", requestId: requestMap["f4"]!, .unknown)
        batch.finishRound()

        let pendingUnknownCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertEqual(pendingUnknownCard.phase, .finished)
        XCTAssertTrue(pendingUnknownCard.requiresUnknownReadbackFirst)
        XCTAssertFalse(pendingUnknownCard.canRetryFailedNow)
        XCTAssertEqual(pendingUnknownCard.unknownRecipientIds, ["f4"])
        XCTAssertEqual(pendingUnknownCard.retryableRecipientIds, ["f3"])

        // Resolve f4 as sent via server readback; now failed-only retry is unlocked.
        try batch.resolveUnknown(friendId: "f4", inviteId: "inv-4")
        batch.markRevoked(friendId: "f1")

        let readyToRetryCard = TeamMeetingHandshakePresentation.presentInviteBatch(batch)
        XCTAssertFalse(readyToRetryCard.requiresUnknownReadbackFirst)
        XCTAssertTrue(readyToRetryCard.canRetryFailedNow)
        XCTAssertEqual(readyToRetryCard.retryableRecipientIds, ["f3"])
        XCTAssertEqual(readyToRetryCard.summary, .init(sent: 1, rejected: 1, retryable: 1, unknown: 0, revoked: 1))

        let f3Row = try XCTUnwrap(readyToRetryCard.recipientRows.first(where: { $0.friendId == "f3" }))
        XCTAssertEqual(f3Row.stableRequestId, requestMap["f3"])
        XCTAssertTrue(f3Row.isRetryable)

        let f1Row = try XCTUnwrap(readyToRetryCard.recipientRows.first(where: { $0.friendId == "f1" }))
        XCTAssertEqual(f1Row.delivery, .revoked)
        XCTAssertFalse(f1Row.isRetryable)
    }

    func testRevokeWinsLedgerTerminalRevocationPrecedenceAndNotificationGate() throws {
        let events: [RevokeWinsEvent] = [
            try RevokeWinsEvent(subjectId: "inv-9", kind: .offered, serverVersion: 1, source: .serverReadback),
            try RevokeWinsEvent(subjectId: "inv-9", kind: .accepted, serverVersion: 4, source: .serverReadback),
            // Revoke with an older serverVersion still wins over a prior accepted state.
            try RevokeWinsEvent(subjectId: "inv-9", kind: .revoked, serverVersion: 3, source: .lateResponse),
            // A subsequent higher-version accept or restored cache cannot resurrect a revoked invite.
            try RevokeWinsEvent(subjectId: "inv-9", kind: .accepted, serverVersion: 6, source: .serverPush),
            try RevokeWinsEvent(subjectId: "inv-9", kind: .offered, serverVersion: nil, source: .restoredCache)
        ]

        let badge = try TeamMeetingHandshakePresentation.evaluateRevokeLedger(
            subjectId: "inv-9",
            events: events
        )
        XCTAssertEqual(badge.subjectId, "inv-9")
        XCTAssertEqual(badge.display, .revoked)
        XCTAssertEqual(badge.version, 4)
        XCTAssertTrue(badge.isRevokeFinal)
        XCTAssertEqual(badge.statusText, "已撤回（终态）")
        XCTAssertEqual(badge.pendingToast, .revoked)
    }

    // MARK: - U03 Tests

    func testBeijingDeadlineDualZoneBannerFormattingAndServerOffsetHint() throws {
        // 2026-11-01 12:00:00 Asia/Shanghai = 2026-11-01T04:00:00Z = 1_793_505_600_000 ms.
        let deadline = try BeijingDeadline(
            epochMilliseconds: 1_793_505_600_000,
            beijingCivil: "2026-11-01T12:00:00"
        )
        let posixLocale = Locale(identifier: "en_US_POSIX")
        let shanghaiZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let newYorkZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        // Device clock skewed 1 hour ahead, corrected by serverOffset = -3600s -> 60s remaining.
        let skewedDeviceNow = deadline.instant.addingTimeInterval(3600 - 60)

        let shanghaiBanner = TeamMeetingHandshakePresentation.presentDeadlineBanner(
            deadline,
            phoneZone: shanghaiZone,
            locale: posixLocale,
            deviceNow: skewedDeviceNow,
            serverOffset: -3600
        )
        XCTAssertFalse(shanghaiBanner.showsDualZone)
        XCTAssertNil(shanghaiBanner.governingBeijingTimeText)
        XCTAssertEqual(shanghaiBanner.hint, .open(remainingSeconds: 60))
        XCTAssertEqual(shanghaiBanner.advisoryStatusText, "距离截止还有 60 秒")
        XCTAssertTrue(shanghaiBanner.allowsSubmission)

        let newYorkBanner = TeamMeetingHandshakePresentation.presentDeadlineBanner(
            deadline,
            phoneZone: newYorkZone,
            locale: posixLocale,
            deviceNow: deadline.instant.addingTimeInterval(1),
            serverOffset: 0
        )
        XCTAssertTrue(newYorkBanner.showsDualZone)
        XCTAssertNotNil(newYorkBanner.governingBeijingTimeText)
        XCTAssertTrue(newYorkBanner.headlineText.contains("北京时间"))
        XCTAssertEqual(newYorkBanner.hint, .boundary)
        XCTAssertEqual(newYorkBanner.advisoryStatusText, "临近截止时间，提交结果以服务端为准")
        XCTAssertTrue(newYorkBanner.allowsSubmission)

        let closedBanner = TeamMeetingHandshakePresentation.presentDeadlineBanner(
            deadline,
            phoneZone: newYorkZone,
            locale: posixLocale,
            deviceNow: deadline.instant.addingTimeInterval(30),
            serverOffset: 0
        )
        XCTAssertEqual(closedBanner.hint, .likelyClosed)
        XCTAssertEqual(closedBanner.advisoryStatusText, "已过截止时间（仍可提交由服务端裁定）")
        XCTAssertTrue(closedBanner.allowsSubmission)
    }
}
