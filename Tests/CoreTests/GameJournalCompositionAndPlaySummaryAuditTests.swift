import XCTest
@testable import QuestifyCore

final class GameJournalCompositionAndPlaySummaryAuditTests: XCTestCase {
    func testDefaultCanonicalSnapshotsAreCompliantAndJournalReady() {
        let result = GameJournalCompositionAndPlaySummaryAudit.audit()
        XCTAssertEqual(result.totalSlices, 3)
        XCTAssertEqual(result.compliantSlices, 3)
        XCTAssertTrue(result.allPreserveStandaloneStamps)
        XCTAssertTrue(result.isJournalReady)
        XCTAssertEqual(
            GameJournalCompositionAndPlaySummaryAudit.canonicalSnapshots.map(\.id),
            ["journal-roam-stamps", "journal-task-completions", "journal-merged-play-summary"]
        )
    }

    func testStandaloneLoadUserStampsRegressionIsDetected() {
        var slices = GameJournalCompositionAndPlaySummaryAudit.canonicalSnapshots
        slices[0] = GameJournalSourceSliceSnapshot(
            id: "journal-roam-stamps",
            userStampCount: 8,
            completedTaskCount: 0,
            deduplicatedEntryCount: 8,
            preservesStandaloneLoadUserStamps: false,
            sortedByTimestampDescending: true
        )
        let result = GameJournalCompositionAndPlaySummaryAudit.audit(snapshots: slices)
        XCTAssertFalse(result.allPreserveStandaloneStamps)
        XCTAssertFalse(result.isJournalReady)
        XCTAssertEqual(result.compliantSlices, 2)
    }

    func testUnsortedJournalEntriesFailComplianceCheck() {
        let unsorted = GameJournalSourceSliceSnapshot(
            id: "journal-unsorted",
            userStampCount: 4,
            completedTaskCount: 3,
            deduplicatedEntryCount: 6,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: false
        )
        XCTAssertFalse(unsorted.isCompliant)
        let result = GameJournalCompositionAndPlaySummaryAudit.audit(snapshots: [unsorted])
        XCTAssertFalse(result.isJournalReady)
        XCTAssertEqual(result.compliantSlices, 0)
    }

    func testDeduplicationBoundsCheckRejectsUnderOrOverCount() {
        let overCounted = GameJournalSourceSliceSnapshot(
            id: "journal-over",
            userStampCount: 4,
            completedTaskCount: 3,
            deduplicatedEntryCount: 8,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: true
        )
        XCTAssertFalse(overCounted.isCompliant)

        let underCounted = GameJournalSourceSliceSnapshot(
            id: "journal-under",
            userStampCount: 6,
            completedTaskCount: 2,
            deduplicatedEntryCount: 5,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: true
        )
        XCTAssertFalse(underCounted.isCompliant)

        let exactLowerBound = GameJournalSourceSliceSnapshot(
            id: "journal-lower-bound",
            userStampCount: 6,
            completedTaskCount: 2,
            deduplicatedEntryCount: 6,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: true
        )
        XCTAssertTrue(exactLowerBound.isCompliant)

        let exactUpperBound = GameJournalSourceSliceSnapshot(
            id: "journal-upper-bound",
            userStampCount: 6,
            completedTaskCount: 2,
            deduplicatedEntryCount: 8,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: true
        )
        XCTAssertTrue(exactUpperBound.isCompliant)
    }
}
