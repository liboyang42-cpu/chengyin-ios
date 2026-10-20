@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class DeepLinkToMiniProgramPathTranslatorSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesBidirectionalRouteAndQueryPreservationChecks() {
        let view = DeepLinkToMiniProgramPathTranslatorSectionView(snapshot: .defaultReady)
        _ = view.body

        XCTAssertTrue(view.snapshot.isReady)
        XCTAssertFalse(view.snapshot.hasQueryParameterLoss)
        XCTAssertEqual(view.snapshot.droppedQueryParameterCount, 0)
        XCTAssertTrue(view.snapshot.rejectsUnknownSchemeOrHost)
        XCTAssertEqual(
            view.snapshot.rows.map(\.routeID),
            [
                "play-project-detail",
                "roam-stamp-album",
                "badge-wall-focus",
                "growth-leaderboard"
            ]
        )
        XCTAssertTrue(view.statusHeadline.contains("Universal Link"))
    }

    func testQueryParameterLossTriggersWarningState() {
        let lossySnapshot = MiniProgramPathTranslatorSnapshot(
            droppedQueryParameterCount: 2,
            rejectsUnknownSchemeOrHost: true
        )
        let view = DeepLinkToMiniProgramPathTranslatorSectionView(snapshot: lossySnapshot)
        _ = view.body

        XCTAssertTrue(view.snapshot.hasQueryParameterLoss)
        XCTAssertFalse(view.snapshot.isReady)
        XCTAssertTrue(view.statusHeadline.contains("查询参数丢失告警"))
    }

    func testDisabledUnknownHostGuardOrNonRoundtripRowFailsReadiness() {
        let unguardedSnapshot = MiniProgramPathTranslatorSnapshot(
            droppedQueryParameterCount: 0,
            rejectsUnknownSchemeOrHost: false
        )
        let unguardedView = DeepLinkToMiniProgramPathTranslatorSectionView(snapshot: unguardedSnapshot)
        _ = unguardedView.body

        XCTAssertFalse(unguardedView.snapshot.isReady)
        XCTAssertTrue(unguardedView.statusHeadline.contains("白名单拦截"))

        var brokenRows = MiniProgramPathTranslatorSnapshot.defaultRows
        brokenRows[0] = MiniProgramRouteMappingRow(
            routeID: "play-project-detail",
            miniProgramPath: "/pages/play/detail/index",
            universalLinkPath: "/play/detail",
            preservesQueryParametersLosslessly: true,
            supportsBidirectionalRoundtrip: false
        )
        let brokenRoundtripView = DeepLinkToMiniProgramPathTranslatorSectionView(
            snapshot: MiniProgramPathTranslatorSnapshot(rows: brokenRows)
        )
        _ = brokenRoundtripView.body

        XCTAssertFalse(brokenRoundtripView.snapshot.isReady)
        XCTAssertFalse(brokenRoundtripView.snapshot.rows[0].isCompliant)
    }
}
