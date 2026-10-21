import XCTest
@testable import QuestifyCore

final class AppSessionCompositionAndFixtureShortCircuitAuditTests: XCTestCase {
    func testAllFixtureFlagsRequireSessionNilShortCircuit() {
        for flag in AppSessionCompositionAndFixtureShortCircuitAudit.knownShortCircuitFixtureFlags {
            let shortCircuited = AppSessionCompositionAndFixtureShortCircuitAudit.audit(
                launchArguments: [flag],
                sessionIsNil: true
            )
            XCTAssertTrue(shortCircuited.isCompliant, "Expected compliant short-circuit for \(flag)")
            XCTAssertTrue(shortCircuited.isFixtureShortCircuited)
            XCTAssertEqual(shortCircuited.activeFixtureFlags, [flag])

            let leakedLiveSession = AppSessionCompositionAndFixtureShortCircuitAudit.audit(
                launchArguments: [flag],
                sessionIsNil: false
            )
            XCTAssertFalse(leakedLiveSession.isCompliant)
            XCTAssertEqual(
                leakedLiveSession.violations,
                [.fixtureLaunchDidNotShortCircuitSessionToNil(activeFlags: [flag])]
            )
        }
    }

    func testContentDraftContextFenceMatchesExactAccountEpochRoleAndRealm() {
        let initialFence = AppSessionFenceSnapshot(
            accountID: "acct-9001",
            sessionEpoch: 4,
            canonicalRole: "MERCHANT",
            sessionRealm: "cn-prod"
        )
        XCTAssertTrue(initialFence.isValid)
        XCTAssertTrue(initialFence.matches(initialFence))

        let differentAccount = AppSessionFenceSnapshot(
            accountID: "acct-9002",
            sessionEpoch: 4,
            canonicalRole: "MERCHANT",
            sessionRealm: "cn-prod"
        )
        let differentEpoch = AppSessionFenceSnapshot(
            accountID: "acct-9001",
            sessionEpoch: 5,
            canonicalRole: "MERCHANT",
            sessionRealm: "cn-prod"
        )
        let differentRole = AppSessionFenceSnapshot(
            accountID: "acct-9001",
            sessionEpoch: 4,
            canonicalRole: "USER",
            sessionRealm: "cn-prod"
        )
        let differentRealm = AppSessionFenceSnapshot(
            accountID: "acct-9001",
            sessionEpoch: 4,
            canonicalRole: "MERCHANT",
            sessionRealm: "us-prod"
        )

        for mismatched in [differentAccount, differentEpoch, differentRole, differentRealm, nil] {
            XCTAssertFalse(initialFence.matches(mismatched))
        }
    }

    func testStaleOrCrossAccountReaderApplicationIsFlaggedAsViolation() {
        let captured = AppSessionFenceSnapshot(
            accountID: "acct-101",
            sessionEpoch: 1,
            canonicalRole: "USER",
            sessionRealm: "cn-shanghai"
        )
        let rotated = AppSessionFenceSnapshot(
            accountID: "acct-202",
            sessionEpoch: 2,
            canonicalRole: "USER",
            sessionRealm: "cn-shanghai"
        )

        let droppedLateReadReport = AppSessionCompositionAndFixtureShortCircuitAudit.audit(
            launchArguments: [],
            sessionIsNil: false,
            userInfoAccountID: "acct-202",
            userInfoServerRole: "USER",
            capturedReaderFence: captured,
            activeSessionFence: rotated,
            didApplyReaderOutput: false
        )
        XCTAssertTrue(droppedLateReadReport.isCompliant)
        XCTAssertFalse(droppedLateReadReport.contextFenceMatched)

        let appliedLateReadReport = AppSessionCompositionAndFixtureShortCircuitAudit.audit(
            launchArguments: [],
            sessionIsNil: false,
            userInfoAccountID: "acct-202",
            userInfoServerRole: "USER",
            capturedReaderFence: captured,
            activeSessionFence: rotated,
            didApplyReaderOutput: true
        )
        XCTAssertFalse(appliedLateReadReport.isCompliant)
        XCTAssertEqual(appliedLateReadReport.violations, [.staleOrCrossAccountReaderAccepted])
    }

    func testAccountSessionGateFailClosedSessionAdmissionVerdicts() {
        XCTAssertEqual(
            AppSessionCompositionAndFixtureShortCircuitAudit.evaluateSessionAdmission(
                accountID: "acct-1",
                serverRole: "player"
            ),
            .admitted(canonicalRole: "USER")
        )
        XCTAssertEqual(
            AppSessionCompositionAndFixtureShortCircuitAudit.evaluateSessionAdmission(
                accountID: "acct-2",
                serverRole: "MERCHANT"
            ),
            .admitted(canonicalRole: "MERCHANT")
        )
        XCTAssertEqual(
            AppSessionCompositionAndFixtureShortCircuitAudit.evaluateSessionAdmission(
                accountID: "acct-3",
                serverRole: "club"
            ),
            .admitted(canonicalRole: "CLUB_ADMIN")
        )

        for missing in [nil, "", "   "] as [String?] {
            XCTAssertEqual(
                AppSessionCompositionAndFixtureShortCircuitAudit.evaluateSessionAdmission(
                    accountID: "acct-1",
                    serverRole: missing
                ),
                .rejectedMissingRole
            )
        }

        XCTAssertEqual(
            AppSessionCompositionAndFixtureShortCircuitAudit.evaluateSessionAdmission(
                accountID: "acct-1",
                serverRole: "SUPER_ROOT"
            ),
            .rejectedUnrecognizedRole("SUPER_ROOT")
        )

        let unblockedBadSessionReport = AppSessionCompositionAndFixtureShortCircuitAudit.audit(
            launchArguments: [],
            sessionIsNil: false,
            userInfoAccountID: "acct-1",
            userInfoServerRole: ""
        )
        XCTAssertFalse(unblockedBadSessionReport.isCompliant)
        XCTAssertEqual(
            unblockedBadSessionReport.violations,
            [.sessionAdmissionFailed(.rejectedMissingRole)]
        )
    }
}
