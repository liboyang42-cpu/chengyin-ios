#if canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
import XCTest
@testable import Questify

@MainActor
final class CrashResilienceAndMetricKitDiagnosticsSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllFourMetricKitCategoriesWithin250msBudget() {
        let snapshot = CrashResilienceDiagnosticsSnapshot.defaultReady

        XCTAssertTrue(snapshot.isAllReady)
        XCTAssertTrue(snapshot.isMainThreadHangWithinBudget)
        XCTAssertEqual(snapshot.violationCount, 0)
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertLessThanOrEqual(
            snapshot.maxObservedMainThreadHangMilliseconds,
            CrashResilienceDiagnosticsSnapshot.mainThreadHangBudgetMilliseconds
        )

        XCTAssertEqual(snapshot.row(for: .crash)?.status, .ready)
        XCTAssertEqual(snapshot.row(for: .hang)?.status, .ready)
        XCTAssertEqual(snapshot.row(for: .cpuException)?.status, .ready)
        XCTAssertEqual(snapshot.row(for: .diskWriteException)?.status, .ready)
    }

    func testHangThresholdViolationOver250msTriggersAlertState() {
        let degradedSnapshot = CrashResilienceDiagnosticsSnapshot(
            maxObservedMainThreadHangMilliseconds: 310,
            crashFreeSessionVerified: true,
            cpuExceptionBudgetVerified: true,
            diskWriteBudgetVerified: false
        )

        XCTAssertFalse(degradedSnapshot.isMainThreadHangWithinBudget)
        XCTAssertFalse(degradedSnapshot.isAllReady)
        XCTAssertEqual(degradedSnapshot.violationCount, 2)
        XCTAssertEqual(degradedSnapshot.row(for: .hang)?.status, .thresholdViolated)
        XCTAssertEqual(degradedSnapshot.row(for: .hang)?.observedSummaryText.contains("310ms"), true)
        XCTAssertEqual(degradedSnapshot.row(for: .diskWriteException)?.status, .thresholdViolated)
    }

    func testMainActorViewBodyInstantiationAndRowSelectionCallback() throws {
        let snapshot = CrashResilienceDiagnosticsSnapshot.defaultReady
        var selectedRow: CrashResilienceMetricRow?

        let view = CrashResilienceAndMetricKitDiagnosticsSectionView(
            snapshot: snapshot,
            onSelectRow: { row in
                selectedRow = row
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let hangRow = try XCTUnwrap(snapshot.row(for: .hang))
        view.onSelectRow?(hangRow)
        XCTAssertEqual(selectedRow, hangRow)
    }
}
