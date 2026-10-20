import XCTest
@testable import QuestifyCore

final class ClubAndTeamCoopGovernanceAuditTests: XCTestCase {
    func testAllFourGovernancePillarsAndFallbackKeysArePresentAndCompliant() {
        let audit = ClubAndTeamCoopGovernanceAudit()
        XCTAssertTrue(audit.isAllCompliant)
        XCTAssertEqual(audit.pillars.map(\.pillar), [
            .w2_12_teamAndClubEntry,
            .w2_14_15_16_clubGovernanceOps,
            .i09_seriesScheduleAndLeadPolling,
            .h_w16_u02_u07_teamHandshakeAndSafety
        ])
        XCTAssertEqual(audit.pillars[0].fallbackOrFixtureKey, "social.incompleteLink")
        XCTAssertTrue(audit.pillars[0].coveredComponents.contains("TeamPagePresentation"))
        XCTAssertTrue(audit.pillars[0].coveredComponents.contains("ClubTabPresentation"))

        XCTAssertTrue(audit.pillars[1].coveredComponents.contains("ClubGovernanceCoordinator"))
        XCTAssertTrue(audit.pillars[1].coveredComponents.contains("ClubEnrollmentReader"))
        XCTAssertTrue(audit.pillars[1].coveredComponents.contains("ClubOpsJoinNotifyPresentation"))
        XCTAssertTrue(audit.pillars[1].coveredComponents.contains("ClubOpsSettlementPresentation"))

        XCTAssertEqual(audit.pillars[2].fallbackOrFixtureKey, "BK-SCHEDULE")
        XCTAssertTrue(audit.pillars[2].coveredComponents.contains("ClubSeriesScheduleReadback"))
        XCTAssertTrue(audit.pillars[2].coveredComponents.contains("PlayLeadProgressPolling"))

        XCTAssertEqual(audit.pillars[3].fallbackOrFixtureKey, "Asia/Shanghai")
        XCTAssertTrue(audit.pillars[3].coveredComponents.contains("TeamMeetingHandshakePresentation"))
    }

    func testConfirmedTeamQROnlyHandshakeWithNFCDisabledAndStrangerRealNameScope() {
        XCTAssertFalse(ClubAndTeamCoopGovernanceAudit.nfcHandshakeEnabled)
        XCTAssertTrue(ClubAndTeamCoopGovernanceAudit.canStartMeetingHandshake(teamConfirmed: true, usingNFC: false))
        XCTAssertFalse(ClubAndTeamCoopGovernanceAudit.canStartMeetingHandshake(teamConfirmed: false, usingNFC: false))
        XCTAssertFalse(ClubAndTeamCoopGovernanceAudit.canStartMeetingHandshake(teamConfirmed: true, usingNFC: true))

        XCTAssertTrue(
            ClubAndTeamCoopGovernanceAudit.requiresRealNameVerification(
                isOfflineStrangerMeeting: true,
                isConfirmedFriendTeam: false
            )
        )
        XCTAssertFalse(
            ClubAndTeamCoopGovernanceAudit.requiresRealNameVerification(
                isOfflineStrangerMeeting: true,
                isConfirmedFriendTeam: true
            )
        )
        XCTAssertFalse(
            ClubAndTeamCoopGovernanceAudit.requiresRealNameVerification(
                isOfflineStrangerMeeting: false,
                isConfirmedFriendTeam: false
            )
        )
    }

    func testPerRecipientInviteRequestIDsAndTerminalRevocationPrecedence() {
        let requestIDs = ClubAndTeamCoopGovernanceAudit.perRecipientInviteRequestIDs(
            batchSeed: "invite-batch-20261020",
            recipientAccountIDs: [101, 202, 101, 0, -5]
        )
        XCTAssertEqual(requestIDs.count, 2)
        XCTAssertEqual(requestIDs[101], "invite-batch-20261020-recipient-101")
        XCTAssertEqual(requestIDs[202], "invite-batch-20261020-recipient-202")
        XCTAssertNotEqual(requestIDs[101], requestIDs[202])

        // Terminal revocation always wins over late acceptance readbacks.
        XCTAssertEqual(
            ClubAndTeamCoopGovernanceAudit.resolveInviteState(current: .revoked, incoming: .accepted),
            .revoked
        )
        XCTAssertEqual(
            ClubAndTeamCoopGovernanceAudit.resolveInviteState(current: .accepted, incoming: .revoked),
            .revoked
        )
        XCTAssertEqual(
            ClubAndTeamCoopGovernanceAudit.resolveInviteState(current: .expired, incoming: .accepted),
            .expired
        )
        XCTAssertEqual(
            ClubAndTeamCoopGovernanceAudit.resolveInviteState(current: .pending, incoming: .accepted),
            .accepted
        )
    }

    func testBeijingGoverningTimeCutoffAndDualZoneDisplay() throws {
        let cutoff = Date(timeIntervalSince1970: 1_760_004_000)
        let shanghaiZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let newYorkZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        let sameZone = ClubAndTeamCoopGovernanceAudit.formatBeijingGoverningCutoff(
            cutoff: cutoff,
            viewerTimeZone: shanghaiZone
        )
        XCTAssertFalse(sameZone.requiresDualZoneDisplay)
        XCTAssertTrue(sameZone.beijingText.contains("(北京时间)"))

        let crossZone = ClubAndTeamCoopGovernanceAudit.formatBeijingGoverningCutoff(
            cutoff: cutoff,
            viewerTimeZone: newYorkZone
        )
        XCTAssertTrue(crossZone.requiresDualZoneDisplay)
        XCTAssertNotEqual(crossZone.beijingText, crossZone.viewerText)
        XCTAssertTrue(crossZone.viewerText.contains("(America/New_York)"))

        XCTAssertFalse(ClubAndTeamCoopGovernanceAudit.isCutoffPassed(cutoff: cutoff, serverNow: cutoff.addingTimeInterval(-1)))
        XCTAssertTrue(ClubAndTeamCoopGovernanceAudit.isCutoffPassed(cutoff: cutoff, serverNow: cutoff))
        XCTAssertTrue(ClubAndTeamCoopGovernanceAudit.isCutoffPassed(cutoff: cutoff, serverNow: cutoff.addingTimeInterval(60)))
    }
}
