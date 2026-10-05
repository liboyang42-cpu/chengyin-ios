import XCTest
@testable import QuestifyCore

final class PlayTaskSummaryPresentationTests: XCTestCase {
    private func snapshot(_ raw: String) throws -> PlaySnapshot {
        try .init(scope: .activity(41), result: JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8)))
    }
    func testKnownZeroOfOneIsARealZero() throws {
        let value = PlayTaskSummaryPresentation(snapshot: try snapshot(PlayExperienceSyntheticFixtures.classic))
        XCTAssertEqual(value.completed, 0); XCTAssertEqual(value.total, 1); XCTAssertEqual(value.fraction, 0)
        XCTAssertEqual(value.currentNodeID, 701)
    }
    func testMissingTotalNeverUsesVisibleNodeCount() throws {
        let value = PlayTaskSummaryPresentation(snapshot: try snapshot(#"{"playable":true,"doneCount":0,"nodes":[{"nodeId":1,"done":false}]}"#))
        XCTAssertNil(value.total); XCTAssertNil(value.fraction); XCTAssertEqual(value.currentNodeID, 1)
    }
    func testMissingDoneNeverInventsZero() throws {
        let value = PlayTaskSummaryPresentation(snapshot: try snapshot(#"{"total":2,"playable":true,"nodes":[{"nodeId":1,"done":false}]}"#))
        XCTAssertNil(value.completed); XCTAssertNil(value.fraction)
    }
    func testZeroAndInconsistentTotalsRemainPhaseOnly() throws {
        for raw in [#"{"total":0,"doneCount":0,"nodes":[]}"#, #"{"total":1,"doneCount":2,"nodes":[{"nodeId":1}]}"#] {
            XCTAssertNil(PlayTaskSummaryPresentation(snapshot: try snapshot(raw)).fraction)
        }
    }
    func testServerCompletedSnapshotHasNoCurrentTask() throws {
        let snap = try snapshot(PlayExperienceSyntheticFixtures.complete)
        let value = PlayTaskSummaryPresentation(snapshot: snap)
        XCTAssertEqual(value.fraction, 1); XCTAssertNil(value.currentNodeID)
        XCTAssertEqual(PlayTaskStatusPresentation(node: snap.visibleNodes[0], snapshot: snap), .completed)
    }
    func testMultipleAvailableTasksAreNotArbitrarilyOrderedAsCurrent() throws {
        let value = PlayTaskSummaryPresentation(snapshot: try snapshot(#"{"playable":true,"nodes":[{"nodeId":1,"done":false},{"nodeId":2,"done":false}]}"#))
        XCTAssertNil(value.currentNodeID)
    }
    func testUnknownAndLockedNodesCannotBecomeCurrent() throws {
        for node in [#"{"nodeId":1}"#, #"{"nodeId":1,"done":false,"locked":true}"#] {
            let snap = try snapshot("{\"playable\":true,\"nodes\":[\(node)]}")
            XCTAssertNil(PlayTaskSummaryPresentation(snapshot: snap).currentNodeID)
            XCTAssertNotEqual(PlayTaskStatusPresentation(node: snap.visibleNodes[0], snapshot: snap), .completed)
        }
    }
    func testPhotoEvidenceAwaitingMerchantVerificationIsNotComplete() throws {
        let snap = try snapshot(PlayExperienceSyntheticFixtures.mode2)
        XCTAssertEqual(PlayTaskStatusPresentation(node: snap.visibleNodes[0], snapshot: snap), .awaitingVerification)
        XCTAssertEqual(PlayTaskSummaryPresentation(snapshot: snap).fraction, 0)
    }
    func testUnavailableSessionDoesNotPresentCurrentTask() throws {
        let snap = try snapshot(#"{"playable":false,"nodes":[{"nodeId":1,"done":false}]}"#)
        XCTAssertNil(PlayTaskSummaryPresentation(snapshot: snap).currentNodeID)
        XCTAssertEqual(PlayTaskStatusPresentation(node: snap.visibleNodes[0], snapshot: snap), .unknown)
    }
    func testBranchUsesOnlyAuthoritativelyVisibleNodes() throws {
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(PlayExperienceSyntheticFixtures.branch.utf8))
        let authority = try JSONDecoder().decode(PlayRouteState.self, from: Data(PlayExperienceSyntheticFixtures.route.utf8))
        let snap = try PlaySnapshot(scope: .activity(41), result: result, authority: authority)
        XCTAssertEqual(PlayTaskSummaryPresentation(snapshot: snap).currentNodeID, 701)
        XCTAssertFalse(snap.visibleNodes.contains { $0.id == 702 })
    }
}
