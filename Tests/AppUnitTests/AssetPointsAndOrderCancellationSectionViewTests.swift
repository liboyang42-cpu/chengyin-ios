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
final class AssetPointsAndOrderCancellationSectionViewTests: XCTestCase {
    func testDefaultConservationSnapshotShowsAuthoritativeBalanceAndConservedRows() {
        let snapshot = AssetPointsAndOrderCancellationSnapshot.defaultConservationSnapshot
        XCTAssertTrue(snapshot.isConservationCompliant)
        XCTAssertEqual(snapshot.authoritativeBalancePoints, 1280)
        XCTAssertEqual(snapshot.conservedCount, 1)
        XCTAssertEqual(snapshot.pendingReadbackCount, 1)
        XCTAssertEqual(snapshot.discrepancyCount, 0)
        XCTAssertEqual(snapshot.summaryText, "守恒确认 1 · 待回读 1 · 异常 0")

        let view = AssetPointsAndOrderCancellationSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot, snapshot)
    }

    func testUnconfirmedBalanceAndDiscrepancyRowAreSurfacedExplicitly() {
        let rows: [AssetPointsCancellationRow] = [
            AssetPointsCancellationRow(
                id: "ord-cancel-201",
                orderNumber: "CY202610200201",
                deductedPoints: 300,
                refundedPointsFromAuthority: 100,
                state: .discrepancyDetected,
                note: "退回积分与扣减积分不一致，需人工复核"
            )
        ]
        let snapshot = AssetPointsAndOrderCancellationSnapshot(
            ownerScope: "member-i04-check",
            authoritativeBalancePoints: nil,
            rows: rows
        )
        XCTAssertFalse(snapshot.isConservationCompliant)
        XCTAssertEqual(snapshot.balanceDisplayText, "—（待服务端权威回读）")
        XCTAssertEqual(snapshot.discrepancyCount, 1)
        XCTAssertEqual(rows.first?.badgeText, "MISMATCH")
        XCTAssertEqual(rows.first?.deltaSummaryText, "扣减 -300 · 权威退回 +100")

        let view = AssetPointsAndOrderCancellationSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot.summaryText, "守恒确认 0 · 待回读 0 · 异常 1")
    }
}
