import SwiftUI
import XCTest
@testable import Questify
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#if canImport(QuestifyApp)
@testable import QuestifyApp
#endif

@MainActor
final class ExplorationPrivateToolsAndCapsuleSectionViewTests: XCTestCase {

    func testDefaultReadySnapshotCoversAllFiveW209PrivateTools() {
        let snapshot = ExplorationPrivateToolsSnapshot.defaultReady
        XCTAssertEqual(snapshot.tools.count, 5)
        XCTAssertTrue(snapshot.hasAllFiveTools)
        XCTAssertTrue(snapshot.isCatalogBilingualComplete)
        XCTAssertTrue(snapshot.isAccountFenceActive)
        XCTAssertTrue(snapshot.allCompliant)
        XCTAssertEqual(
            snapshot.tools.map(\.id),
            [
                "TimeCapsule",
                "ExplorationGoals",
                "ExplorationExport",
                "ExplorationAnniversary",
                "MonthlyRecap"
            ]
        )
        XCTAssertEqual(
            snapshot.tools.map { $0.kind.miniProgramSlug },
            [
                "capsule",
                "exploration-goals",
                "exploration-export",
                "exploration-anniversary",
                "monthly-recap"
            ]
        )
    }

    func testNonCompliantToolOrIncompleteCatalogSurfacesWarningState() {
        let brokenTool = ExplorationPrivateToolRow(
            kind: .timeCapsule,
            title: "TimeCapsule",
            routeSummary: "subpackageRoam/capsule",
            isAccountScopedReadReady: true,
            isLiveWriteDormant: false
        )
        let warningSnapshot = ExplorationPrivateToolsSnapshot(
            tools: [brokenTool],
            catalogTableName: "RoamPrivateTools.xcstrings",
            isCatalogBilingualComplete: false,
            isAccountFenceActive: false
        )
        let view = ExplorationPrivateToolsAndCapsuleSectionView(snapshot: warningSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.hasAllFiveTools)
        XCTAssertFalse(view.snapshot.allCompliant)
        XCTAssertFalse(view.snapshot.tools[0].isCompliant)
        XCTAssertFalse(view.snapshot.isCatalogBilingualComplete)
    }

    func testMainActorViewBodyInstantiationWithDefaultAndCustomSnapshots() {
        let defaultView = ExplorationPrivateToolsAndCapsuleSectionView()
        _ = defaultView.body
        XCTAssertTrue(defaultView.snapshot.allCompliant)
        XCTAssertEqual(defaultView.snapshot.catalogTableName, "RoamPrivateTools.xcstrings")
    }
}
