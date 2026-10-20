import XCTest
@testable import QuestifyCore

final class Wave3HandoffVerificationRegistryTests: XCTestCase {
    func testAllThirteenWave3LanesAreRegisteredWithExactPRsAndCommits() {
        let allLanes = Wave3HandoffVerificationRegistry.allLanes
        XCTAssertEqual(allLanes.count, 13)
        XCTAssertEqual(
            allLanes.map(\.lane),
            [.i00, .i01, .i02, .i03, .i04, .i05, .i06, .i07, .i08, .i09, .i10, .i11, .bk]
        )
        XCTAssertTrue(Wave3HandoffVerificationRegistry.isCompleteAndFailClosed)

        let expectedPRAndCommit: [Wave3HandoffVerificationRegistry.LaneID: (Int, String)] = [
            .i00: (43, "54b2fdc"),
            .i01: (38, "028e23e"),
            .i02: (41, "010caae"),
            .i03: (42, "1a0270b"),
            .i04: (37, "ba58993"),
            .i05: (44, "6b09cac8"),
            .i06: (35, "79af21a"),
            .i07: (48, "5647c1ac"),
            .i08: (50, "f0a84989"),
            .i09: (55, "44a302e7"),
            .i10: (49, "511693b5"),
            .i11: (43, "54b2fdc"),
            .bk: (52, "1123f654")
        ]

        for (lane, expected) in expectedPRAndCommit {
            guard let record = Wave3HandoffVerificationRegistry.record(for: lane) else {
                XCTFail("Missing Wave-3 record for \(lane.rawValue)")
                continue
            }
            XCTAssertEqual(record.mergedPRNumber, expected.0, "PR mismatch for \(lane.rawValue)")
            XCTAssertEqual(record.commitHash, expected.1, "Commit mismatch for \(lane.rawValue)")
            XCTAssertTrue(record.productionGateDefaultOff, "Lane \(lane.rawValue) must default to OFF")
            XCTAssertTrue(record.handoffDocPath.hasPrefix("docs/handoff/ios-"))
        }
    }

    func testPrimaryCoreAndAppSymbolsAreCatalogedForEveryWave3Lane() {
        let i01 = Wave3HandoffVerificationRegistry.record(for: .i01)
        XCTAssertEqual(i01?.coreSymbols.contains("PlayArrivalAccuracy"), true)
        XCTAssertEqual(i01?.appSymbols.contains("RuntimePlayDeviceProvider"), true)
        XCTAssertEqual(i01?.appSymbols.contains("PlayDeviceTaskViews"), true)

        let i05 = Wave3HandoffVerificationRegistry.record(for: .i05)
        XCTAssertEqual(i05?.coreSymbols.contains("SquareWorkspacePrivacy"), true)
        XCTAssertEqual(i05?.coreSymbols.contains("TopicLikeDirection"), true)
        XCTAssertEqual(i05?.coreSymbols.contains("TopicLikeHostController"), true)

        let i08 = Wave3HandoffVerificationRegistry.record(for: .i08)
        XCTAssertEqual(i08?.coreSymbols.contains("NPCChatLogDeletion"), true)
        XCTAssertEqual(i08?.coreSymbols.contains("NPCChatDataCoordinator"), true)
        XCTAssertEqual(i08?.appSymbols.contains("NPCChatDataView"), true)

        let i10 = Wave3HandoffVerificationRegistry.record(for: .i10)
        XCTAssertEqual(i10?.coreSymbols.contains("NativePerformanceSignposts"), true)
        XCTAssertEqual(i10?.appSymbols.contains("WalkingNavigationView"), true)
        XCTAssertEqual(i10?.appSymbols.contains("PlayRouteMapView"), true)

        let i11 = Wave3HandoffVerificationRegistry.record(for: .i11)
        XCTAssertEqual(i11?.coreSymbols.contains("RoamReceivedStampReadRoute"), true)
        XCTAssertEqual(i11?.coreSymbols.contains("RoamReceivedStampPresentation"), true)
        XCTAssertEqual(i11?.appSymbols.contains("RoamReceivedStampSectionView"), true)

        let bk = Wave3HandoffVerificationRegistry.record(for: .bk)
        XCTAssertEqual(bk?.coreSymbols.contains("TopicUnlikeController"), true)
        XCTAssertEqual(bk?.coreSymbols.contains("ProfileFavoriteRemoval"), true)
        XCTAssertEqual(bk?.coreSymbols.contains("SocialActionContracts"), true)
    }

    func testBackendPrerequisitesAndFailClosedGatesStayDisabledByDefault() {
        let i00Role = Wave3HandoffVerificationRegistry.prerequisite(.iosI00UserInfoRole)
        XCTAssertEqual(i00Role?.relatedLane, .i00)
        XCTAssertEqual(i00Role?.status, .draftFailClosedOff)
        XCTAssertEqual(i00Role?.defaultEnabledInProduction, false)

        let bkGPS = Wave3HandoffVerificationRegistry.prerequisite(.bkGPS)
        XCTAssertEqual(bkGPS?.relatedLane, .i01)
        XCTAssertEqual(bkGPS?.status, .contractFrozenSourceReady)
        XCTAssertEqual(bkGPS?.defaultEnabledInProduction, false)

        let bkSchedule = Wave3HandoffVerificationRegistry.prerequisite(.bkSchedule)
        XCTAssertEqual(bkSchedule?.relatedLane, .i09)
        XCTAssertEqual(bkSchedule?.status, .contractFrozenSourceReady)
        XCTAssertEqual(bkSchedule?.defaultEnabledInProduction, false)

        let aiDelete = Wave3HandoffVerificationRegistry.prerequisite(.aiDeleteDefaultOff)
        XCTAssertEqual(aiDelete?.relatedLane, .i08)
        XCTAssertEqual(aiDelete?.status, .draftFailClosedOff)
        XCTAssertEqual(aiDelete?.defaultEnabledInProduction, false)

        let topicLikeGate = Wave3HandoffVerificationRegistry.prerequisite(.topicLikeGrantDefaultOff)
        XCTAssertEqual(topicLikeGate?.relatedLane, .i05)
        XCTAssertEqual(topicLikeGate?.status, .clientGateDefaultOff)
        XCTAssertEqual(topicLikeGate?.defaultEnabledInProduction, false)
    }

    func testI00AndI11ShareBaselineCardPRWhileKeepingDistinctSymbolBoundaries() {
        guard let i00 = Wave3HandoffVerificationRegistry.record(for: .i00),
              let i11 = Wave3HandoffVerificationRegistry.record(for: .i11) else {
            XCTFail("Expected both I00 and I11 records")
            return
        }
        XCTAssertEqual(i00.mergedPRNumber, i11.mergedPRNumber)
        XCTAssertEqual(i00.commitHash, i11.commitHash)
        XCTAssertEqual(i00.handoffDocPath, "docs/handoff/ios-I00-I11-20261019.md")
        XCTAssertEqual(i11.handoffDocPath, "docs/handoff/ios-I00-I11-20261019.md")
        XCTAssertTrue(Set(i00.coreSymbols).isDisjoint(with: Set(i11.coreSymbols)))
        XCTAssertEqual(i00.backendPrerequisites, [.iosI00UserInfoRole])
        XCTAssertEqual(i11.backendPrerequisites, [.bkExisting])
    }
}
