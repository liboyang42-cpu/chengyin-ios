import XCTest
@testable import QuestifyCore

final class UnifiedDecisionsU01ToU08ComplianceAuditTests: XCTestCase {
    func testAllEightUnifiedDecisionsU01ToU08AreRegisteredInCanonicalOrder() {
        let decisions = UnifiedDecisionsU01ToU08ComplianceAudit.decisions
        XCTAssertEqual(decisions.count, 8)
        XCTAssertEqual(
            decisions.map(\.decisionID.rawValue),
            ["U01", "U02", "U03", "U04", "U05", "U06", "U07", "U08"]
        )
        XCTAssertTrue(decisions.allSatisfy(\.isFailClosedByDefault))

        XCTAssertEqual(
            UnifiedDecisionsU01ToU08ComplianceAudit.canonicalOwnershipRoles.map(\.rawValue),
            ["CREATOR", "CLUB", "MERCHANT", "PLATFORM"]
        )
        XCTAssertEqual(
            UnifiedDecisionsU01ToU08ComplianceAudit.canonicalMediaPipeline.map(\.rawValue),
            ["select", "process", "upload", "review", "save", "read", "play"]
        )
    }

    func testDefaultCompliantPostureVerifiesAllEightDecisionsWithZeroViolations() {
        let report = UnifiedDecisionsU01ToU08ComplianceAudit.evaluateCompliance()
        XCTAssertTrue(report.isCompliant)
        XCTAssertEqual(report.verifiedDecisionIDs, UnifiedDecisionID.allCases)
        XCTAssertTrue(report.violations.isEmpty)
    }

    func testU01ToU04ViolationsAreDetectedDeterministically() {
        let report = UnifiedDecisionsU01ToU08ComplianceAudit.evaluateCompliance(
            ownershipRoles: [.creator, .merchant],
            mediaPipelineStages: [.select, .upload, .play],
            handshakeUsesQROnly: false,
            handshakeNFCEnabled: true,
            hasInterestMatchingGate: true,
            realNameRequiredOnlyForStrangerOfflineMeeting: false,
            recipientRequestIDs: ["u1": "shared-req", "u2": "shared-req"]
        )
        XCTAssertFalse(report.isCompliant)
        XCTAssertEqual(report.violations.count, 4)
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u01ContentOwnershipAndMediaPipeline))
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u02ConfirmedTeamQRHandshakeOnly))
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u03StrangerOfflineRealNameScope))
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u04IndependentRecipientInviteRequestIDs))
    }

    func testU05ToU08ViolationsFlagUnsafeRetryNonTerminalRevocationTimeZoneAndCashLedger() {
        let report = UnifiedDecisionsU01ToU08ComplianceAudit.evaluateCompliance(
            allowsRetryOnlyOnExplicitFailure: false,
            locksRetryOnUnknownOutcomeUntilReadback: false,
            revocationIsTerminal: false,
            governingCutoffTimeZone: "America/Los_Angeles",
            supportsCashOrPointsToCashInLedger: true,
            anyHighRiskSwitchEnabledByDefault: true
        )
        XCTAssertFalse(report.isCompliant)
        XCTAssertEqual(report.violations.count, 4)
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u05FailedOnlyRetryAndUnknownOutcomeLock))
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u06TerminalRevocationPrecedence))
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u07DualZoneBeijingGoverningCutoff))
        XCTAssertFalse(report.verifiedDecisionIDs.contains(.u08NonCashLedgerAndFailClosedSwitches))
    }
}
