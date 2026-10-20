import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor
final class Wave3HandoffStatusSectionViewTests: XCTestCase {
    func testDefaultWave3HandoffLanesCoverAllThirteenItemsAndPRRange() {
        let view = Wave3HandoffStatusSectionView()
        let ids = view.laneRows.map(\.id)
        XCTAssertEqual(
            ids,
            ["I00", "I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08", "I09", "I10", "I11", "BK"]
        )
        XCTAssertEqual(view.laneRows.count, 13)
        XCTAssertEqual(view.mergedCount, 13)
        XCTAssertEqual(view.laneRows.first?.mergedPR, "#35")
        XCTAssertEqual(view.laneRows.last?.mergedPR, "#55")
        XCTAssertEqual(view.prRangeSummary, "#35..#55")
        _ = view.body
    }

    func testDefaultPrerequisiteGatesStayDisabledByDefault() {
        let view = Wave3HandoffStatusSectionView()
        XCTAssertEqual(view.prerequisiteGates.map(\.id), ["IOS-I00-1", "AI-DELETE", "TopicLike"])
        XCTAssertTrue(view.prerequisiteGates.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(
            view.prerequisiteGates.map(\.stateBadge),
            ["PENDING", "OFF", "OFF"]
        )
    }

    func testCustomLaneAndGateRowsRenderDeterministically() {
        let customLanes = [
            Wave3HandoffLaneRow(id: "I00", title: "Custom Baseline", mergedPR: "#35", statusSummary: "Ready", isMerged: true),
            Wave3HandoffLaneRow(id: "BK", title: "Custom Bookkeeping", mergedPR: "#55", statusSummary: "Pending", isMerged: false)
        ]
        let customGates = [
            Wave3HandoffGateRow(id: "AI-DELETE", title: "AI Delete Gate", stateBadge: "OFF", detail: "Disabled", isEnabled: false)
        ]
        let view = Wave3HandoffStatusSectionView(laneRows: customLanes, prerequisiteGates: customGates)
        XCTAssertEqual(view.mergedCount, 1)
        XCTAssertEqual(view.prRangeSummary, "#35..#55")
        XCTAssertEqual(view.prerequisiteGates.count, 1)
        _ = view.body
    }
}
