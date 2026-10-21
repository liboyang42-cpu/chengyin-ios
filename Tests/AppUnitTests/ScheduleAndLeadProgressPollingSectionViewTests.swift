import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class ScheduleAndLeadProgressPollingSectionViewTests: XCTestCase {

    func testDefaultInstantiationAndFourVerifiedSchedulePollingRules() {
        let view = ScheduleAndLeadProgressPollingSectionView()
        _ = view.body

        XCTAssertEqual(view.snapshot.rows.count, 4)
        XCTAssertEqual(view.snapshot.verifiedRowCount, 4)
        XCTAssertEqual(view.snapshot.activePollingTasksCount, 0)
        XCTAssertTrue(view.snapshot.stopsOnTerminalState)
        XCTAssertTrue(view.snapshot.cancelsOnDisappearOrAccountSwitch)
        XCTAssertTrue(view.snapshot.isAuditReady)

        XCTAssertEqual(view.headerBadgeText, "SCHEDULE & POLLING VERIFIED (4/4)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Schedule & Lead Polling: 4/4 VERIFIED · Active Polls: 0 · Terminal-Stop: ON · Lifecycle-Cancel: ON"
        )
    }

    func testFourAuditRowTitlesAndLifecycleSummaries() {
        let view = ScheduleAndLeadProgressPollingSectionView()
        let titles = view.snapshot.rows.map(\.title)
        XCTAssertEqual(
            titles,
            [
                "BK-SCHEDULE Authoritative Dates Readback",
                "PlayLeadProgressPolling Single-Flight & Generation Fence",
                "Terminal Play State Immediate Polling Stop",
                "Scene Background, Disappear & Account-Switch Cancellation"
            ]
        )

        for row in view.snapshot.rows {
            XCTAssertEqual(row.statusBadgeText, "VERIFIED · FAIL-CLOSED")
            XCTAssertTrue(row.summaryLineText.contains(row.scopeCode))
            XCTAssertFalse(row.invariantSummary.isEmpty)
            XCTAssertFalse(row.lifecycleRuleSummary.isEmpty)
        }
    }

    func testAttentionSnapshotWhenTerminalStopOrRowUnverified() {
        var customRows = ScheduleAndLeadProgressPollingSnapshot.defaultRows
        customRows[2] = ScheduleLeadPollingAuditRow(
            id: "I09-terminal-stop-rule",
            scopeCode: "I09 · Terminal-Stop",
            title: "Terminal Play State Immediate Polling Stop",
            invariantSummary: "Runaway poll detected after terminal state",
            lifecycleRuleSummary: "Must cancel immediately on COMPLETED/EXPIRED",
            isVerified: false
        )
        let snapshot = ScheduleAndLeadProgressPollingSnapshot(
            rows: customRows,
            activePollingTasksCount: 1,
            stopsOnTerminalState: false,
            cancelsOnDisappearOrAccountSwitch: true
        )
        let view = ScheduleAndLeadProgressPollingSectionView(snapshot: snapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAuditReady)
        XCTAssertEqual(view.headerBadgeText, "POLLING AUDIT ATTENTION (3/4)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Schedule & Lead Polling: 3/4 VERIFIED · Active Polls: 1 · Terminal-Stop: OFF (UNSAFE) · Lifecycle-Cancel: ON"
        )
        XCTAssertEqual(view.snapshot.rows[2].statusBadgeText, "VIOLATION")
    }
}
