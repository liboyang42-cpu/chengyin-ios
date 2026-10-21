import XCTest
@testable import QuestifyCore

final class AppStoreSubmissionFinalPreflightGateRunnerTests: XCTestCase {
    func testCanonicalGatesAreAllGreenAndAllowAppStoreConnectSubmission() {
        let gates = AppStoreSubmissionFinalPreflightGateRunner.canonicalGates
        XCTAssertEqual(gates.count, 6)
        XCTAssertEqual(
            gates.map(\.id),
            [
                "gate-three-docs-zero-gap",
                "gate-native-superset-policy",
                "gate-rc-gates-01-to-06",
                "gate-seven-day-launch-plan",
                "gate-asc-metadata-and-privacy",
                "gate-canary-phased-rollout",
            ]
        )
        XCTAssertTrue(gates.allSatisfy(\.isGateGreen))

        let result = AppStoreSubmissionFinalPreflightGateRunner.runAllPreflightGates()
        XCTAssertEqual(result.totalGates, 6)
        XCTAssertEqual(result.greenGates, 6)
        XCTAssertTrue(result.canSubmitToAppStoreConnect)
    }

    func testBlockingFailureMarksGateNonGreenAndBlocksSubmission() {
        var gates = AppStoreSubmissionFinalPreflightGateRunner.canonicalGates
        gates[2] = FinalPreflightGateCheckResult(
            id: "gate-rc-gates-01-to-06",
            gateTitle: "Release Candidate Engineering Gates 01–06",
            passedChecks: 6,
            totalChecks: 6,
            isBlockingFailureFree: false
        )
        XCTAssertFalse(gates[2].isGateGreen)

        let result = AppStoreSubmissionFinalPreflightGateRunner.runAllPreflightGates(gates: gates)
        XCTAssertEqual(result.totalGates, 6)
        XCTAssertEqual(result.greenGates, 5)
        XCTAssertFalse(result.canSubmitToAppStoreConnect)
    }

    func testIncompletePassedCheckCountOrZeroTotalChecksBlocksSubmission() {
        var gates = AppStoreSubmissionFinalPreflightGateRunner.canonicalGates
        gates[0] = FinalPreflightGateCheckResult(
            id: "gate-three-docs-zero-gap",
            gateTitle: "Three Master Documents Zero-Gap Reconciliation",
            passedChecks: 67,
            totalChecks: 68,
            isBlockingFailureFree: true
        )
        let zeroCheckGate = FinalPreflightGateCheckResult(
            id: "gate-canary-phased-rollout",
            gateTitle: "Canary Verification & 7-Day Phased Rollout Guardrails",
            passedChecks: 0,
            totalChecks: 0,
            isBlockingFailureFree: true
        )
        gates[5] = zeroCheckGate
        XCTAssertFalse(gates[0].isGateGreen)
        XCTAssertFalse(gates[5].isGateGreen)

        let result = AppStoreSubmissionFinalPreflightGateRunner.runAllPreflightGates(gates: gates)
        XCTAssertEqual(result.totalGates, 6)
        XCTAssertEqual(result.greenGates, 4)
        XCTAssertFalse(result.canSubmitToAppStoreConnect)
    }

    func testEmptyOrTruncatedGateListIsRejected() {
        let emptyResult = AppStoreSubmissionFinalPreflightGateRunner.runAllPreflightGates(gates: [])
        XCTAssertEqual(emptyResult.totalGates, 0)
        XCTAssertEqual(emptyResult.greenGates, 0)
        XCTAssertFalse(emptyResult.canSubmitToAppStoreConnect)

        let truncated = Array(AppStoreSubmissionFinalPreflightGateRunner.canonicalGates.prefix(5))
        let truncatedResult = AppStoreSubmissionFinalPreflightGateRunner.runAllPreflightGates(gates: truncated)
        XCTAssertEqual(truncatedResult.totalGates, 5)
        XCTAssertEqual(truncatedResult.greenGates, 5)
        XCTAssertFalse(truncatedResult.canSubmitToAppStoreConnect)
    }
}
