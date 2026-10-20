@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class BackendRolloutAllowlistSwitchboardSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllSixFailClosedRuntimeSwitches() {
        let snapshot = RolloutSwitchboardSnapshot.defaultReady

        XCTAssertTrue(snapshot.isAllSafe)
        XCTAssertEqual(snapshot.unguardedWarningCount, 0)
        XCTAssertEqual(snapshot.rows.count, 6)

        for switchID in RolloutSwitchRow.SwitchID.allCases {
            let row = snapshot.row(for: switchID)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.isSafe, true)
            XCTAssertEqual(row?.defaultOffEnforced, true)
            XCTAssertEqual(row?.safetyState, .failClosedOff)
            XCTAssertFalse(row?.prerequisiteTicketCode.isEmpty ?? true)
        }
    }

    func testUnguardedSwitchTriggersWarningState() {
        let unguardedRows = RolloutSwitchboardSnapshot.defaultFailClosedSwitches(
            unguardedSwitchIDs: [.paymentsAndWalletWithdraw, .reformWorldAndSceneAIGates]
        )
        let degradedSnapshot = RolloutSwitchboardSnapshot(rows: unguardedRows)

        XCTAssertFalse(degradedSnapshot.isAllSafe)
        XCTAssertEqual(degradedSnapshot.unguardedWarningCount, 2)

        let paymentRow = degradedSnapshot.row(for: .paymentsAndWalletWithdraw)
        XCTAssertEqual(paymentRow?.safetyState, .unguardedViolation)
        XCTAssertEqual(paymentRow?.defaultOffEnforced, false)
        XCTAssertEqual(paymentRow?.isSafe, false)

        let reformRow = degradedSnapshot.row(for: .reformWorldAndSceneAIGates)
        XCTAssertEqual(reformRow?.safetyState, .unguardedViolation)
        XCTAssertEqual(reformRow?.isSafe, false)
    }

    func testMainActorViewBodyInstantiationAndRowSelectionCallback() throws {
        let snapshot = RolloutSwitchboardSnapshot.defaultReady
        var selectedRow: RolloutSwitchRow?

        let view = BackendRolloutAllowlistSwitchboardSectionView(
            snapshot: snapshot,
            onSelectRow: { row in
                selectedRow = row
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let firstRow = try XCTUnwrap(snapshot.row(for: .authSMSAndOAuth))
        view.onSelectRow?(firstRow)
        XCTAssertEqual(selectedRow, firstRow)
    }
}
