import XCTest
@testable import QuestifyCore

final class UnifiedTicketExecutionMatrixTests: XCTestCase {

    func testAllSixImplementationPhasesAreCatalogedInOrder() {
        let phases = UnifiedTicketExecutionMatrix.implementationPhases
        XCTAssertEqual(phases.count, 6)
        XCTAssertEqual(phases.map(\.phaseIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(
            phases.map(\.title),
            [
                "Phase 0: Prerequisites & Switches",
                "Phase 1: Authority Kernel & Readback",
                "Phase 2: Map Visual & Roam Discovery",
                "Phase 3: Merchant, AI & Commerce",
                "Phase 4: Co-op, Workshop & World",
                "Phase 5: Release & Regression Sign-off"
            ]
        )
        XCTAssertEqual(phases.map(\.title), UnifiedTicketExecutionMatrix.expectedPhaseTitles)
        for phase in phases {
            XCTAssertTrue(phase.isComplete, "Phase \(phase.code) should be marked complete")
            XCTAssertFalse(phase.workPackageIDs.isEmpty, "Phase \(phase.code) should reference work packages")
            XCTAssertFalse(phase.keyContracts.isEmpty, "Phase \(phase.code) should reference key contracts")
        }
    }

    func testAllFortyOneMapVisualSpecificationItemsArePresentWithZeroMissingIDs() {
        let items = UnifiedTicketExecutionMatrix.mapVisualItems
        XCTAssertEqual(items.count, 41)

        let expectedIDs = (1...41).map { String(format: "MV%02d", $0) }
        XCTAssertEqual(UnifiedTicketExecutionMatrix.expectedMapVisualIDs, expectedIDs)

        let sortedByOrdinal = items.sorted { $0.ordinal < $1.ordinal }
        XCTAssertEqual(sortedByOrdinal.map(\.id), expectedIDs)
        XCTAssertEqual(sortedByOrdinal.map(\.ordinal), Array(1...41))
        XCTAssertTrue(items.allSatisfy(\.isVerified))
        XCTAssertTrue(items.allSatisfy { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testMapVisualCategoriesAndVerifyingContractsCoverAllFortyOneItems() {
        var categoryTotal = 0
        for category in UnifiedTicketExecutionMatrix.MapVisualCategory.allCases {
            let bucket = UnifiedTicketExecutionMatrix.items(in: category)
            XCTAssertFalse(bucket.isEmpty, "Category \(category.rawValue) must not be empty")
            XCTAssertEqual(bucket.map(\.ordinal), bucket.map(\.ordinal).sorted())
            categoryTotal += bucket.count
        }
        XCTAssertEqual(categoryTotal, 41)

        var contractTotal = 0
        for contract in UnifiedTicketExecutionMatrix.MapVerifyingContract.allCases {
            let bucket = UnifiedTicketExecutionMatrix.items(verifiedBy: contract)
            XCTAssertFalse(bucket.isEmpty, "Verifying contract \(contract.rawValue) must not be empty")
            XCTAssertEqual(bucket.map(\.ordinal), bucket.map(\.ordinal).sorted())
            contractTotal += bucket.count
        }
        XCTAssertEqual(contractTotal, 41)
    }

    func testVerifyAllPhasesAndMapVisualItemsCoveredAndNegativeControls() {
        XCTAssertTrue(UnifiedTicketExecutionMatrix.verifyAllPhasesAndMapVisualItemsCovered())

        let report = UnifiedTicketExecutionMatrix.verificationReport()
        XCTAssertTrue(report.isFullyCovered)
        XCTAssertEqual(report.phaseCount, 6)
        XCTAssertEqual(report.mapVisualItemCount, 41)
        XCTAssertTrue(report.missingPhaseTitles.isEmpty)
        XCTAssertTrue(report.missingMapVisualIDs.isEmpty)
        XCTAssertTrue(report.uncoveredCategories.isEmpty)
        XCTAssertTrue(report.uncoveredVerifyingContracts.isEmpty)

        let missingPhaseReport = UnifiedTicketExecutionMatrix.MatrixVerificationReport(
            phaseCount: 5,
            mapVisualItemCount: 41,
            missingPhaseTitles: ["Phase 5: Release & Regression Sign-off"]
        )
        XCTAssertFalse(missingPhaseReport.isFullyCovered)

        let missingMVReport = UnifiedTicketExecutionMatrix.MatrixVerificationReport(
            phaseCount: 6,
            mapVisualItemCount: 40,
            missingMapVisualIDs: ["MV41"]
        )
        XCTAssertFalse(missingMVReport.isFullyCovered)

        let missingContractReport = UnifiedTicketExecutionMatrix.MatrixVerificationReport(
            phaseCount: 6,
            mapVisualItemCount: 41,
            uncoveredVerifyingContracts: [.nativePerformanceSignposts]
        )
        XCTAssertFalse(missingContractReport.isFullyCovered)
    }
}
