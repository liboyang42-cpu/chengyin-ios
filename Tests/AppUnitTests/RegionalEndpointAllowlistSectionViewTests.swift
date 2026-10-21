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
final class RegionalEndpointAllowlistSectionViewTests: XCTestCase {
    func testDefaultSnapshotBlocksAllSixSensitivePathsAndRejectsLegacyHost() {
        let snapshot = RegionalEndpointAllowlistSnapshot(activeRegion: .cn)

        XCTAssertEqual(snapshot.activeRegion, .cn)
        XCTAssertTrue(snapshot.crossRegionIsolationEnforced)
        XCTAssertTrue(snapshot.rejectsForbiddenLegacyHost)
        XCTAssertTrue(snapshot.isPostureCompliant)
        XCTAssertEqual(RegionalEndpointAllowlistSnapshot.forbiddenLegacyHost, "47.103.124.64")
        XCTAssertTrue(snapshot.legacyHostRejectionNoticeText.contains("47.103.124.64"))

        let paths = snapshot.rows.map(\.endpointPath)
        XCTAssertEqual(
            paths,
            [
                "/api/asset/withdraw",
                "/api/pay/create",
                "/api/npc/chat/delete",
                "/api/topic/like",
                "/api/user/sms/send",
                "/api/merchant/decor/save"
            ]
        )
        XCTAssertTrue(snapshot.rows.allSatisfy(\.isFailClosedInAllRegions))
        for row in snapshot.rows {
            XCTAssertEqual(row.disposition(for: .cn), .failClosedBlocked)
            XCTAssertEqual(row.disposition(for: .us), .failClosedBlocked)
        }
    }

    func testUSMarketIsolationAndNonCompliantPostureDetection() {
        var rows = RegionalEndpointAllowlistSnapshot.defaultFailClosedRows()
        rows[0] = RegionalEndpointGateRow(
            id: "asset-withdraw",
            endpointPath: "/api/asset/withdraw",
            featureCategory: "资产提现",
            cnDisposition: .allowedByReviewedGrant,
            usDisposition: .failClosedBlocked,
            rationaleText: "测试覆盖"
        )
        let modifiedSnapshot = RegionalEndpointAllowlistSnapshot(
            activeRegion: .us,
            crossRegionIsolationEnforced: true,
            rejectsForbiddenLegacyHost: true,
            rows: rows
        )

        XCTAssertEqual(modifiedSnapshot.activeRegion, .us)
        XCTAssertFalse(modifiedSnapshot.rows[0].isFailClosedInAllRegions)
        XCTAssertFalse(modifiedSnapshot.isPostureCompliant)
    }

    func testSectionViewInstantiationAndRowSelectionCallback() throws {
        let snapshot = RegionalEndpointAllowlistSnapshot(activeRegion: .us)
        var selectedRow: RegionalEndpointGateRow?

        let view = RegionalEndpointAllowlistSectionView(
            snapshot: snapshot,
            onSelectRow: { row in
                selectedRow = row
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let firstRow = try XCTUnwrap(snapshot.rows.first)
        view.onSelectRow?(firstRow)
        XCTAssertEqual(selectedRow, firstRow)
    }
}
