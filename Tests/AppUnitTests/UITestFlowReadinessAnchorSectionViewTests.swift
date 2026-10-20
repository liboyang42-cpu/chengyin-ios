import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class UITestFlowReadinessAnchorSectionViewTests: XCTestCase {
    func testDefaultAllFiveSurfacesAreWiredAndAnchored() {
        let snapshot = UITestFlowReadinessSnapshot.defaultAllFiveSurfaces
        XCTAssertTrue(snapshot.coversAllFiveSurfaces)
        XCTAssertTrue(snapshot.isFullyAnchored)
        XCTAssertEqual(snapshot.anchoredCount, 5)
        XCTAssertEqual(snapshot.rows.map(\.id), [
            "projectEditor",
            "profileSelfEdit",
            "roamFinishedHistory",
            "couponRuntimeJourney",
            "mapCoreEntry"
        ])
        XCTAssertEqual(snapshot.summaryText, "已锚定离线 UI 旅程 5/5")

        let view = UITestFlowReadinessAnchorSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot, snapshot)
    }

    func testUnanchoredSurfaceReducesAnchoredCountAndMarksNotFullyAnchored() {
        let customRows: [UIFlowReadinessAnchorRow] = [
            UIFlowReadinessAnchorRow(
                surface: .projectEditor,
                title: "projectEditor",
                launchArgument: "--uitesting-project-editor",
                rootAccessibilityID: "project.editor.root",
                testSuiteName: "ProjectEditorFlowTests",
                state: .wiredAndAnchored
            ),
            UIFlowReadinessAnchorRow(
                surface: .mapCoreEntry,
                title: "mapCoreEntry",
                launchArgument: "--uitesting-map-core-entry",
                rootAccessibilityID: "map.coreEntry.hub",
                testSuiteName: "MapCoreEntryFlowTests",
                state: .missingAccessibilityAnchor
            )
        ]
        let snapshot = UITestFlowReadinessSnapshot(rows: customRows)
        XCTAssertFalse(snapshot.coversAllFiveSurfaces)
        XCTAssertFalse(snapshot.isFullyAnchored)
        XCTAssertEqual(snapshot.anchoredCount, 1)
        XCTAssertEqual(customRows.map(\.badgeText), ["ANCHORED", "NO_ANCHOR"])

        let view = UITestFlowReadinessAnchorSectionView(snapshot: snapshot)
        _ = view.body
        XCTAssertEqual(view.snapshot.summaryText, "已锚定离线 UI 旅程 1/5")
    }
}
