import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class AppStoreSubmissionFinalPreflightGateViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesAllSixTopLevelReleaseGates() {
        let snapshot = FinalPreflightGateRunnerSnapshot.defaultReady
        XCTAssertTrue(snapshot.isSubmissionReady)
        XCTAssertEqual(snapshot.rows.count, 6)
        XCTAssertEqual(snapshot.passedCount, 6)
        XCTAssertEqual(
            snapshot.rows.map(\.gateCode),
            ["FINAL-01", "FINAL-02", "FINAL-03", "FINAL-04", "FINAL-05", "FINAL-06"]
        )
        XCTAssertEqual(snapshot.targetMarket, "CN")
        XCTAssertTrue(snapshot.zeroSecretOrCredentialLeak)

        for row in snapshot.rows {
            XCTAssertTrue(row.isPassed)
            XCTAssertTrue(row.isFailClosed)
            XCTAssertEqual(row.statusBadgeText, "PASS • FAIL-CLOSED")
        }
    }

    func testBlockedGateOrSecretLeakSurfacesHoldSubmissionWarningState() {
        var modifiedRows = FinalPreflightGateRunnerSnapshot.defaultRows
        modifiedRows[2] = FinalPreflightGateRow(
            id: "final-gate-03-commerce-fail-closed",
            gateCode: "FINAL-03",
            title: "Commerce, Wallet, StoreKit 2 & Non-Cash Reward Policy",
            checkSummary: "Withdrawal gate enabled without approval",
            isPassed: false,
            isFailClosed: false
        )
        let blockedSnapshot = FinalPreflightGateRunnerSnapshot(
            rows: modifiedRows,
            targetMarket: "US",
            zeroSecretOrCredentialLeak: false
        )
        let view = AppStoreSubmissionFinalPreflightGateView(snapshot: blockedSnapshot)

        XCTAssertFalse(view.snapshot.isSubmissionReady)
        XCTAssertEqual(view.snapshot.passedCount, 5)
        XCTAssertEqual(
            view.statusBadgeText,
            "Final Preflight: BLOCKED (5/6 Gates Green)"
        )
        XCTAssertEqual(
            view.runnerSummaryText,
            "Target Market: US • Security Scan: SECRET LEAK DETECTED"
        )
        XCTAssertEqual(
            view.submissionDecisionBannerText,
            "Submission Verdict: HOLD — Resolve Blocked Preflight Gate Before Archive"
        )
        XCTAssertEqual(view.snapshot.rows[2].statusBadgeText, "BLOCKED • HOLD SUBMISSION")
    }

    func testMainActorViewBodyInstantiationAndDefaultPresentationStrings() {
        let view = AppStoreSubmissionFinalPreflightGateView()
        _ = view.body

        XCTAssertEqual(
            view.statusBadgeText,
            "Final Preflight: READY (6/6 Gates Green)"
        )
        XCTAssertEqual(
            view.runnerSummaryText,
            "Target Market: CN • Security Scan: Zero Secret Leaks"
        )
        XCTAssertEqual(
            view.submissionDecisionBannerText,
            "Submission Verdict: CLEARED FOR ARCHIVE PREFLIGHT (All 6 Top-Level Gates Fail-Closed & Verified)"
        )
    }
}
