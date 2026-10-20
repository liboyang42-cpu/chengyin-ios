@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class ZeroRegressionLegacyServerIsolationSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesAllFourIsolationLayersAndRedactedHostLabel() {
        let snapshot = LegacyServerIsolationSnapshot.defaultReady

        XCTAssertTrue(snapshot.isFullyIsolated)
        XCTAssertEqual(snapshot.breachCount, 0)
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(
            LegacyServerIsolationSnapshot.redactedLegacyHostLabel,
            "Legacy Aliyun Mini-Program Host (47.103.x.x)"
        )
        XCTAssertTrue(
            snapshot.summaryHeadlineText.contains("Legacy Aliyun Mini-Program Host (47.103.x.x)")
        )

        for layer in LegacyIsolationLayerRow.Layer.allCases {
            let row = snapshot.row(for: layer)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.isIsolated, true)
            XCTAssertEqual(row?.status, .isolated)
        }
    }

    func testIsolationBreachOnAnyLayerTriggersWarningState() {
        let breachedSnapshot = LegacyServerIsolationSnapshot(
            baseXCConfigIsolated: true,
            runtimeAllowlistIsolated: false,
            staticSourceScannerGreen: false,
            ciMockTransportEnforced: true
        )

        XCTAssertFalse(breachedSnapshot.isFullyIsolated)
        XCTAssertEqual(breachedSnapshot.breachCount, 2)
        XCTAssertEqual(breachedSnapshot.row(for: .baseXCConfigNonRoutableDefault)?.status, .isolated)
        XCTAssertEqual(breachedSnapshot.row(for: .runtimeAllowlistHostFence)?.status, .breachWarning)
        XCTAssertEqual(breachedSnapshot.row(for: .staticSourceScannerGuard)?.status, .breachWarning)
        XCTAssertEqual(breachedSnapshot.row(for: .ciOfflineMockTransportOnly)?.status, .isolated)
    }

    func testMainActorViewBodyInstantiationAndRowSelectionCallback() throws {
        let snapshot = LegacyServerIsolationSnapshot.defaultReady
        var selectedRow: LegacyIsolationLayerRow?

        let view = ZeroRegressionLegacyServerIsolationSectionView(
            snapshot: snapshot,
            onSelectRow: { row in
                selectedRow = row
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let firstRow = try XCTUnwrap(snapshot.row(for: .baseXCConfigNonRoutableDefault))
        view.onSelectRow?(firstRow)
        XCTAssertEqual(selectedRow, firstRow)
    }
}
