import SwiftUI
import XCTest
#if canImport(Questify)
@testable import Questify
#elseif canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor final class UnifiedTicketExecutionMatrixSectionViewTests: XCTestCase {
    func testStandardProjectionCoversAllSixPhasesFortyOneMapVisualItemsEightDecisionsAndNineteenWorkPackages() {
        let projection = UnifiedTicketExecutionMatrixProjection.standard

        // Phase 0..Phase 5 (6 phases)
        XCTAssertEqual(projection.phaseCount, 6)
        XCTAssertEqual(projection.completedPhaseCount, 6)
        XCTAssertEqual(projection.phases.map(\.phaseIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertTrue(projection.phases.allSatisfy(\.isFullyCovered))
        XCTAssertTrue(projection.phases.allSatisfy { $0.sourceDocument.contains("落地清单.md") && $0.sourceDocument.contains("工单-统一实施版.md") })

        // MV01..MV41 (41 items across 7 groups, exact non-overlapping sequence)
        XCTAssertEqual(projection.mapVisualTotalItems, 41)
        XCTAssertEqual(projection.mapVisualCoveredItems, 41)
        let flattenedMV = projection.mapVisualGroups.flatMap(\.itemIDs)
        XCTAssertEqual(flattenedMV.count, 41)
        XCTAssertEqual(flattenedMV, MapVisualGroupSummaryRow.allItemIDs)
        XCTAssertEqual(flattenedMV.first, "MV01")
        XCTAssertEqual(flattenedMV.last, "MV41")
        XCTAssertTrue(projection.mapVisualGroups.allSatisfy(\.isFullyCovered))

        // U01..U08 (8 items)
        XCTAssertEqual(projection.unifiedDecisionCount, 8)
        XCTAssertEqual(projection.coveredDecisionCount, 8)
        XCTAssertEqual(
            projection.unifiedDecisions.map(\.id),
            ["U01", "U02", "U03", "U04", "U05", "U06", "U07", "U08"]
        )

        // W02..W20 (19 items)
        XCTAssertEqual(projection.workPackageCount, 19)
        XCTAssertEqual(projection.coveredWorkPackageCount, 19)
        let expectedWorkPackages = (2...20).map { String(format: "W%02d", $0) }
        XCTAssertEqual(projection.workPackages.map(\.id), expectedWorkPackages)

        XCTAssertTrue(projection.isComplete)
    }

    func testUnifiedTicketExecutionMatrixSectionViewInstantiatesAndRendersCustomAndStandardProjections() {
        let standardView = UnifiedTicketExecutionMatrixSectionView()
        _ = standardView.body
        XCTAssertTrue(standardView.projection.isComplete)

        var partialPhases = TicketPhaseSummaryRow.defaultPhases
        partialPhases[5] = TicketPhaseSummaryRow(
            id: "phase-5",
            phaseIndex: 5,
            title: "Phase 5 — Resident CITY Actions, Delta Stream & Host Matrix",
            completedCount: 6,
            totalCount: 7,
            badgeText: "IN_PROGRESS"
        )
        let partialProjection = UnifiedTicketExecutionMatrixProjection(phases: partialPhases)
        XCTAssertEqual(partialProjection.completedPhaseCount, 5)
        XCTAssertFalse(partialProjection.isComplete)

        let customView = UnifiedTicketExecutionMatrixSectionView(projection: partialProjection)
        _ = customView.body
    }
}
