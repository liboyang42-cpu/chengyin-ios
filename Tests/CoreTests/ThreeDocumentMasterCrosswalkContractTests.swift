import XCTest
@testable import QuestifyCore

final class ThreeDocumentMasterCrosswalkContractTests: XCTestCase {
    func testDocument1HandoffCrosswalkCoversAllWavesAndCloudCI() {
        let contract = ThreeDocumentMasterCrosswalkContract()
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave1AlignmentTracks, ["B", "C", "D", "E", "F", "G", "H"])
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave2ParityLanes.count, 21)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave2ParityLanes.first, "w2-01")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave2ParityLanes.last, "w2-21")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave3HandoffLanes.count, 13)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave3HandoffLanes.first, "I00")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave3HandoffLanes.last, "BK")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.cloudCIRunners, ["macos-26", "ubuntu-24.04"])
        XCTAssertTrue(contract.document1Section.isComplete)
        XCTAssertTrue(contract.document1Section.unmappedItems.isEmpty)
    }

    func testDocument2RolloutChecklistPhasesSwitchesAndBackendPrerequisites() {
        let contract = ThreeDocumentMasterCrosswalkContract()
        XCTAssertEqual(
            ThreeDocumentMasterCrosswalkContract.rolloutPhases,
            ["Phase 0", "Phase 1", "Phase 2", "Phase 3", "Phase 4", "Phase 5"]
        )
        XCTAssertEqual(
            ThreeDocumentMasterCrosswalkContract.backendPrerequisites,
            ["IOS-I00-1", "BK-GPS", "BK-SCHEDULE"]
        )
        let switchIDs = contract.failClosedSwitches.map(\.id)
        XCTAssertEqual(switchIDs, [
            "AuthFeatureFlags",
            "TopicLike",
            "AI-DELETE",
            "MapLayerFeature",
            "SideQuestFeature",
            "PersonalFogFeature",
            "MerchantAICommerceGates",
            "SceneAIAvailability",
            "SponsoredRewardCapabilities",
            "CommerceClientPaymentRules",
            "ReformWorldCapabilities"
        ])
        XCTAssertTrue(contract.areAllSwitchesFailClosed)
        XCTAssertTrue(contract.document2Section.isComplete)
    }

    func testDocument3UnifiedTicketsCoversWorkPackagesDecisionsAndMapVisualSpecs() {
        let contract = ThreeDocumentMasterCrosswalkContract()
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.workPackages.count, 19)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.workPackages.first, "W02")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.workPackages.last, "W20")

        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.unifiedDecisions, [
            "U01", "U02", "U03", "U04", "U05", "U06", "U07", "U08"
        ])

        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.mapVisualSpecs.count, 41)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.mapVisualSpecs.first, "MV01")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.mapVisualSpecs.last, "MV41")
        XCTAssertTrue(contract.document3Section.isComplete)
    }

    func testCompleteCrosswalkHasZeroUnmappedItemsAndDetectsMissingMappings() {
        let complete = ThreeDocumentMasterCrosswalkContract()
        XCTAssertTrue(complete.isHundredPercentCovered)
        XCTAssertTrue(complete.allUnmappedItems.isEmpty)

        let incompleteDoc3 = MasterDocumentCrosswalkSection(
            document: .unifiedImplementationTickets,
            expectedItems: ["W02", "U01", "MV01", "MV41"],
            mappedItems: ["W02", "U01", "MV01"]
        )
        let partial = ThreeDocumentMasterCrosswalkContract(document3Section: incompleteDoc3)
        XCTAssertFalse(partial.isHundredPercentCovered)
        XCTAssertEqual(partial.allUnmappedItems, ["MV41"])
    }
}
