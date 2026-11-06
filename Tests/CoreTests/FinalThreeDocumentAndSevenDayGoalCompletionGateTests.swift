import XCTest
@testable import QuestifyCore

final class FinalThreeDocumentAndSevenDayGoalCompletionGateTests: XCTestCase {
    func testCanonicalEntriesPassFullGoalCompletionGate() {
        let entries = FinalThreeDocumentAndSevenDayGoalCompletionGate.canonicalEntries
        XCTAssertEqual(entries.count, 4)
        // Seven-day entry is fail-closed until SHA-bound evidence + external sign-off exist.
        XCTAssertEqual(entries.filter(\.isCompliant).count, 3)
        XCTAssertFalse(entries[3].isCompliant)
        XCTAssertEqual(
            entries.map(\.documentOrPlanName),
            [
                "交接文档_20261020.md",
                "落地清单.md",
                "工单-统一实施版.md",
                "SevenDayLaunchCriticalPathMilestoneContract"
            ]
        )

        let result = FinalThreeDocumentAndSevenDayGoalCompletionGate.evaluate()
        XCTAssertEqual(result.totalEntries, 4)
        XCTAssertEqual(result.completedEntries, 3)
        XCTAssertFalse(result.isGoal100PercentComplete)
    }

    func testIncompleteDocumentScopeFailsGoalCompletionGate() {
        var entries = FinalThreeDocumentAndSevenDayGoalCompletionGate.canonicalEntries
        entries[0] = GoalDocumentCompletionEntry(
            id: "handover_20261020",
            documentOrPlanName: "交接文档_20261020.md",
            scopeCoverageSummary: "Wave-1..Wave-3 + I00..I11 + BK",
            isDocumentScopeComplete: false,
            strictMiniProgramAPIAndCopyParity: true,
            nativeSupersetPreserved: true
        )

        XCTAssertFalse(entries[0].isCompliant)
        let result = FinalThreeDocumentAndSevenDayGoalCompletionGate.evaluate(entries: entries)
        XCTAssertEqual(result.totalEntries, 4)
        XCTAssertEqual(result.completedEntries, 2)
        XCTAssertFalse(result.isGoal100PercentComplete)
    }

    func testDowngradedNativeSupersetOrBrokenAPIParityFailsGoalCompletionGate() {
        var entries = FinalThreeDocumentAndSevenDayGoalCompletionGate.canonicalEntries
        entries[1] = GoalDocumentCompletionEntry(
            id: "landing_checklist",
            documentOrPlanName: "落地清单.md",
            scopeCoverageSummary: "w2-01..w2-21 + 99 Mini-Program Pages",
            isDocumentScopeComplete: true,
            strictMiniProgramAPIAndCopyParity: false,
            nativeSupersetPreserved: true
        )
        entries[2] = GoalDocumentCompletionEntry(
            id: "unified_work_orders_v9",
            documentOrPlanName: "工单-统一实施版.md",
            scopeCoverageSummary: "Reform v9 W02..W20 + U01..U08 + MV01..MV41",
            isDocumentScopeComplete: true,
            strictMiniProgramAPIAndCopyParity: true,
            nativeSupersetPreserved: false
        )

        XCTAssertFalse(entries[1].isCompliant)
        XCTAssertFalse(entries[2].isCompliant)
        let result = FinalThreeDocumentAndSevenDayGoalCompletionGate.evaluate(entries: entries)
        XCTAssertEqual(result.totalEntries, 4)
        XCTAssertEqual(result.completedEntries, 1)
        XCTAssertFalse(result.isGoal100PercentComplete)
    }

    func testEmptyEntriesAreRejected() {
        let result = FinalThreeDocumentAndSevenDayGoalCompletionGate.evaluate(entries: [])
        XCTAssertEqual(result.totalEntries, 0)
        XCTAssertEqual(result.completedEntries, 0)
        XCTAssertFalse(result.isGoal100PercentComplete)
    }
}
