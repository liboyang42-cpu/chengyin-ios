import XCTest
@testable import QuestifyCore

final class ThreeDocumentMasterCrosswalkContractTests: XCTestCase {
    private let validFormalSHA = "50e2cf9be15999e35f566463db61908690f7c149"
    private let alternateFormalSHA = "1e72f9916c438d3fee4b7e087e002f16aeb3feaf"

    func testDocument1HandoffCrosswalkCoversAllWavesAndCloudCI() {
        let defaultContract = ThreeDocumentMasterCrosswalkContract()
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave1AlignmentTracks, ["B", "C", "D", "E", "F", "G", "H"])
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave2ParityLanes.count, 21)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave2ParityLanes.first, "w2-01")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave2ParityLanes.last, "w2-21")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave3HandoffLanes.count, 13)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave3HandoffLanes.first, "I00")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.wave3HandoffLanes.last, "BK")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.cloudCIRunners, ["macos-26", "ubuntu-24.04"])

        // Default initialization must not pre-fill mappedItems as 100% complete without evidence
        XCTAssertTrue(defaultContract.document1Section.mappedItems.isEmpty)
        XCTAssertFalse(defaultContract.document1Section.isComplete)
        XCTAssertFalse(defaultContract.isHundredPercentCovered)
    }

    func testDocument2RolloutChecklistPhasesSwitchesAndBackendPrerequisites() {
        let defaultContract = ThreeDocumentMasterCrosswalkContract()
        XCTAssertEqual(
            ThreeDocumentMasterCrosswalkContract.rolloutPhases,
            ["Phase 0", "Phase 1", "Phase 2", "Phase 3", "Phase 4", "Phase 5"]
        )
        XCTAssertEqual(
            ThreeDocumentMasterCrosswalkContract.backendPrerequisites,
            ["IOS-I00-1", "BK-GPS", "BK-SCHEDULE"]
        )
        let switchIDs = defaultContract.failClosedSwitches.map(\.id)
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
        XCTAssertTrue(defaultContract.areAllSwitchesFailClosed)
        XCTAssertFalse(defaultContract.document2Section.isComplete)
    }

    func testDocument3UnifiedTicketsCoversWorkPackagesDecisionsAndMapVisualSpecs() {
        let defaultContract = ThreeDocumentMasterCrosswalkContract()
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.workPackages.count, 19)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.workPackages.first, "W02")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.workPackages.last, "W20")

        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.unifiedDecisions, [
            "U01", "U02", "U03", "U04", "U05", "U06", "U07", "U08"
        ])

        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.mapVisualSpecs.count, 41)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.mapVisualSpecs.first, "MV01")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.mapVisualSpecs.last, "MV41")
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.clientTrackingWorkPackageSubIDs.count, 127)
        XCTAssertEqual(ThreeDocumentMasterCrosswalkContract.clientTracking176EnumerationIDs.count, 176)
        XCTAssertFalse(defaultContract.document3Section.isComplete)
    }

    func testCompleteCrosswalkHasZeroUnmappedItemsAndDetectsMissingMappings() {
        // Default unverified contract must NOT report 100% coverage
        let unverified = ThreeDocumentMasterCrosswalkContract()
        XCTAssertFalse(unverified.isHundredPercentCovered)
        XCTAssertFalse(unverified.allUnmappedItems.isEmpty)

        // Supplying complete canonical mappings for all 3 documents passes section coverage
        let complete = ThreeDocumentMasterCrosswalkContract(
            document1Section: MasterDocumentCrosswalkSection(
                document: .handoff20261020,
                expectedItems: ThreeDocumentMasterCrosswalkContract.canonicalDocument1ExpectedItems,
                mappedItems: ThreeDocumentMasterCrosswalkContract.canonicalDocument1ExpectedItems
            ),
            document2Section: MasterDocumentCrosswalkSection(
                document: .rolloutChecklist,
                expectedItems: ThreeDocumentMasterCrosswalkContract.canonicalDocument2ExpectedItems,
                mappedItems: ThreeDocumentMasterCrosswalkContract.canonicalDocument2ExpectedItems
            ),
            document3Section: MasterDocumentCrosswalkSection(
                document: .unifiedImplementationTickets,
                expectedItems: ThreeDocumentMasterCrosswalkContract.canonicalDocument3ExpectedItems,
                mappedItems: ThreeDocumentMasterCrosswalkContract.canonicalDocument3ExpectedItems
            )
        )
        XCTAssertTrue(complete.isHundredPercentCovered)
        XCTAssertTrue(complete.allUnmappedItems.isEmpty)

        // Shrinking expectedItems on a section must be rejected by isHundredPercentCovered
        let shrunkDoc3 = MasterDocumentCrosswalkSection(
            document: .unifiedImplementationTickets,
            expectedItems: ["W02", "U01", "MV01"],
            mappedItems: ["W02", "U01", "MV01"]
        )
        let shrunk = ThreeDocumentMasterCrosswalkContract(
            document1Section: complete.document1Section,
            document2Section: complete.document2Section,
            document3Section: shrunkDoc3
        )
        XCTAssertFalse(shrunk.isHundredPercentCovered)
    }

    func testClientTrackingFourLayerLedgerDefaultsToPendingAndRejectsDuplicatesUnknownIDsOrMissingSHA() {
        let defaultLedger = ThreeDocumentMasterCrosswalkContract.clientTrackingFourLayerLedger
        XCTAssertEqual(defaultLedger.count, 176)
        XCTAssertTrue(defaultLedger.allSatisfy {
            $0.codeStatus == .pending
                && $0.wiringStatus == .pending
                && $0.testStatus == .notRun
                && $0.deploymentStatus == .notRun
                && !$0.isEndToEndVerified
        })
        XCTAssertFalse(ThreeDocumentMasterCrosswalkContract.evaluateEndToEndDeploymentVerified())

        let verifiedLedger = ThreeDocumentMasterCrosswalkContract.clientTracking176EnumerationIDs.map { id in
            ReformRequirementFourLayerLedgerEntry(
                requirementID: id,
                codeStatus: .passed,
                wiringStatus: .passed,
                testStatus: .passed,
                deploymentStatus: .passed,
                verifiedCommitSHA: validFormalSHA,
                evidenceSymbolOrPath: "docs/handoff/issue-61-response-20261020.md#\(id)"
            )
        }
        XCTAssertTrue(
            ThreeDocumentMasterCrosswalkContract.evaluateEndToEndDeploymentVerified(
                ledger: verifiedLedger,
                expectedCommitSHA: validFormalSHA
            )
        )

        // Copying the same passed record 176 times must be rejected
        let repeated176 = Array(repeating: verifiedLedger[0], count: 176)
        XCTAssertFalse(
            ThreeDocumentMasterCrosswalkContract.evaluateEndToEndDeploymentVerified(
                ledger: repeated176,
                expectedCommitSHA: validFormalSHA
            )
        )

        // Unknown requirement ID must be rejected
        var unknownIDLedger = verifiedLedger
        unknownIDLedger[0] = ReformRequirementFourLayerLedgerEntry(
            requirementID: "W99.99",
            codeStatus: .passed,
            wiringStatus: .passed,
            testStatus: .passed,
            deploymentStatus: .passed,
            verifiedCommitSHA: validFormalSHA,
            evidenceSymbolOrPath: "docs/evidence"
        )
        XCTAssertFalse(
            ThreeDocumentMasterCrosswalkContract.evaluateEndToEndDeploymentVerified(
                ledger: unknownIDLedger,
                expectedCommitSHA: validFormalSHA
            )
        )

        // Missing or mixed SHA across the 176 entries must be rejected
        var missingSHALedger = verifiedLedger
        missingSHALedger[5] = ReformRequirementFourLayerLedgerEntry(
            requirementID: verifiedLedger[5].requirementID,
            codeStatus: .passed,
            wiringStatus: .passed,
            testStatus: .passed,
            deploymentStatus: .passed,
            verifiedCommitSHA: "",
            evidenceSymbolOrPath: "docs/evidence"
        )
        XCTAssertFalse(missingSHALedger[5].isEndToEndVerified)
        XCTAssertFalse(
            ThreeDocumentMasterCrosswalkContract.evaluateEndToEndDeploymentVerified(
                ledger: missingSHALedger,
                expectedCommitSHA: validFormalSHA
            )
        )

        var mixedSHALedger = verifiedLedger
        mixedSHALedger[5] = ReformRequirementFourLayerLedgerEntry(
            requirementID: verifiedLedger[5].requirementID,
            codeStatus: .passed,
            wiringStatus: .passed,
            testStatus: .passed,
            deploymentStatus: .passed,
            verifiedCommitSHA: alternateFormalSHA,
            evidenceSymbolOrPath: "docs/evidence"
        )
        XCTAssertFalse(
            ThreeDocumentMasterCrosswalkContract.evaluateEndToEndDeploymentVerified(
                ledger: mixedSHALedger,
                expectedCommitSHA: validFormalSHA
            )
        )
    }
}
