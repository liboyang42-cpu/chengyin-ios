@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class SQLiteAndJSONJournalCorruptionRecoverySectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesAllFourLocalStores() {
        let snapshot = JournalCorruptionRecoverySnapshot.defaultReady

        XCTAssertTrue(snapshot.isAllHealthy)
        XCTAssertEqual(snapshot.warningCount, 0)
        XCTAssertEqual(snapshot.rows.count, 4)

        for kind in DurableStoreRecoveryRow.StoreKind.allCases {
            let row = snapshot.row(for: kind)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.isHealthy, true)
            XCTAssertEqual(row?.atomicWriteRenameVerified, true)
            XCTAssertEqual(row?.corruptPayloadQuarantined, false)
            XCTAssertEqual(row?.schemaVersion, 1)
        }
    }

    func testCorruptStoreQuarantineTriggersWarningState() {
        let degradedSnapshot = JournalCorruptionRecoverySnapshot(
            runJournalHealthy: false,
            offlineOutboxHealthy: true,
            walkingCheckpointHealthy: true,
            roamTileCacheHealthy: false
        )

        XCTAssertFalse(degradedSnapshot.isAllHealthy)
        XCTAssertEqual(degradedSnapshot.warningCount, 2)

        let runJournalRow = degradedSnapshot.row(for: .runAuthorityJournal)
        XCTAssertEqual(runJournalRow?.status, .quarantinedWarning)
        XCTAssertEqual(runJournalRow?.corruptPayloadQuarantined, true)
        XCTAssertEqual(runJournalRow?.isHealthy, false)

        let roamCacheRow = degradedSnapshot.row(for: .roamTileAndDraftCache)
        XCTAssertEqual(roamCacheRow?.status, .quarantinedWarning)
        XCTAssertEqual(roamCacheRow?.isHealthy, false)
    }

    func testMainActorViewBodyInstantiationAndRowSelectionCallback() throws {
        let snapshot = JournalCorruptionRecoverySnapshot.defaultReady
        var selectedRow: DurableStoreRecoveryRow?

        let view = SQLiteAndJSONJournalCorruptionRecoverySectionView(
            snapshot: snapshot,
            onSelectRow: { row in
                selectedRow = row
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let firstRow = try XCTUnwrap(snapshot.row(for: .runAuthorityJournal))
        view.onSelectRow?(firstRow)
        XCTAssertEqual(selectedRow, firstRow)
    }
}
