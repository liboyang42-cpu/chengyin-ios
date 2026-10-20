import XCTest
@testable import QuestifyCore

final class StoryWalkingNavigationHostBridgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 4_000_000)

    private func stop(_ id: Int, mission: Int = 8) throws -> WalkingTargetReference {
        try .init(kind: .storyNode, id: id, missionID: mission)
    }

    private func readback(_ revision: Int, stop id: Int?, finished: Bool = false, mission: Int = 8) throws -> StoryRouteStateReadback {
        try .init(missionID: mission, revision: revision, currentStop: id.map { try stop($0, mission: mission) }, finished: finished)
    }

    private func entrance(label: String, reviewedBy: String?, closed: Bool) throws -> PlaceNavigationEntrance {
        let coordinate = try MapCoordinateObservation(latitude: 31.23, longitude: 121.47, datum: .gcj02, source: .backend)
        return PlaceNavigationEntrance(
            label: label,
            floor: "1F",
            approachNote: nil,
            coordinate: coordinate,
            source: "merchant-verified",
            reviewedBy: reviewedBy,
            updatedAt: now,
            temporarilyClosed: closed,
            accessibleAlternative: closed ? "Use South Gate" : nil
        )
    }

    private func fix(accuracy: Double = 10, age: TimeInterval = 0) throws -> RoamDeviceFix {
        try .init(
            coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.4)!,
            accuracyMeters: accuracy,
            measuredAt: now.addingTimeInterval(-age),
            datum: .wgs84
        )
    }

    private var samplePolicy: PersonalFogSamplePolicy {
        try! .init(maxAccuracyMeters: 50, maxAge: 30, maxBatch: 2)
    }

    func testAuthorityReadbackCoordinatesWalkingStopTransitionsAndVerificationHold() throws {
        var bridge = try StoryWalkingNavigationHostBridge(missionID: 8)
        let stop1 = try stop(1)
        let stop2 = try stop(2)

        let first = try bridge.ingestAuthorityReadback(readback(1, stop: 1))
        XCTAssertEqual(first, .startedStop(stop1))
        XCTAssertEqual(bridge.activeWalkingStop, stop1)
        XCTAssertEqual(bridge.stopTransitionCount, 1)

        let repeatSame = try bridge.ingestAuthorityReadback(readback(2, stop: 1))
        XCTAssertEqual(repeatSame, .unchanged(stop1))
        XCTAssertEqual(bridge.stopTransitionCount, 1)

        XCTAssertTrue(bridge.recordWalkingArrival(for: stop1))
        XCTAssertNil(bridge.activeWalkingStop)
        XCTAssertTrue(bridge.canOpenVerification(for: stop1))

        XCTAssertTrue(bridge.recordVerificationSubmitted(for: stop1))
        XCTAssertFalse(bridge.canOpenVerification(for: stop1))

        // Authority still reports stop 1 while verification is under evaluation: hold verification.
        let hold = try bridge.ingestAuthorityReadback(readback(3, stop: 1))
        XCTAssertEqual(hold, .holdingVerification(stop1))
        XCTAssertNil(bridge.activeWalkingStop)

        // Authority advances to stop 2: transition walking target to stop 2.
        let advance = try bridge.ingestAuthorityReadback(readback(4, stop: 2))
        XCTAssertEqual(advance, .advancedStop(from: stop1, to: stop2))
        XCTAssertEqual(bridge.activeWalkingStop, stop2)
        XCTAssertEqual(bridge.stopTransitionCount, 2)

        let complete = try bridge.ingestAuthorityReadback(readback(5, stop: nil, finished: true))
        XCTAssertEqual(complete, .completedMission)
        XCTAssertNil(bridge.activeWalkingStop)
        XCTAssertEqual(bridge.phase, .finished)
    }

    func testArrivalForMismatchedStopDoesNotOpenVerificationOrClearWalkingTarget() throws {
        var bridge = try StoryWalkingNavigationHostBridge(missionID: 8)
        let stop1 = try stop(1)
        let stop2 = try stop(2)

        try bridge.ingestAuthorityReadback(readback(1, stop: 1))
        XCTAssertFalse(bridge.recordWalkingArrival(for: stop2))
        XCTAssertFalse(bridge.recordVerificationSubmitted(for: stop1))
        XCTAssertEqual(bridge.activeWalkingStop, stop1)
        XCTAssertFalse(bridge.canOpenVerification(for: stop1))
    }

    func testNavigableEntranceSelectionSkipsClosedAndUnreviewedEntrances() throws {
        var bridge = try StoryWalkingNavigationHostBridge(missionID: 8)
        let unreviewed = try entrance(label: "North Gate", reviewedBy: nil, closed: false)
        let closed = try entrance(label: "East Gate", reviewedBy: "ops-1", closed: true)
        let valid = try entrance(label: "South Gate", reviewedBy: "ops-1", closed: false)

        try bridge.ingestAuthorityReadback(readback(1, stop: 1), entrances: [unreviewed, closed, valid])
        XCTAssertEqual(bridge.activeEntrance, valid)

        let cleared = try bridge.ingestAuthorityReadback(readback(2, stop: nil))
        XCTAssertEqual(cleared, .clearedStop)
        XCTAssertNil(bridge.activeEntrance)
    }

    func testFogCoordinatorProjectsConfirmedAndPredictedTilesWhileKeepingRevealSyncDisabled() throws {
        var coordinator = try PersonalFogRoamHostCoordinator(ownerScope: "acct-1", samplePolicy: samplePolicy)
        XCTAssertFalse(coordinator.overlayProjection.revealSyncEnabled)

        let afterPage = try coordinator.ingestServerTilePage(owner: "acct-1", cells: ["wtw3sk", "wtw3sj"], nextCursor: 4)
        XCTAssertEqual(afterPage.confirmedTileCodes, ["wtw3sj", "wtw3sk"])
        XCTAssertTrue(afterPage.pendingPredictedTileCodes.isEmpty)
        XCTAssertEqual(afterPage.readCursor, 4)

        let afterPrediction = try coordinator.recordForegroundFix(tileCode: "wtw3sm", fix: try fix(), now: now)
        XCTAssertEqual(afterPrediction.confirmedTileCodes, ["wtw3sj", "wtw3sk"])
        XCTAssertEqual(afterPrediction.pendingPredictedTileCodes, ["wtw3sm"])
        XCTAssertEqual(afterPrediction.visibleRevealedTileCodes, ["wtw3sj", "wtw3sk", "wtw3sm"])

        XCTAssertThrowsError(try coordinator.attemptRevealSyncBatch()) { error in
            XCTAssertEqual(error as? PersonalFogFailure, .featureDisabled)
        }
    }

    func testFogCoordinatorBatchVerdictPromotesAcceptedAndRollsBackRejectedPredictions() throws {
        var coordinator = try PersonalFogRoamHostCoordinator(ownerScope: "acct-1", samplePolicy: samplePolicy)
        try coordinator.recordForegroundFix(tileCode: "wtw3sj", fix: try fix(), now: now)
        try coordinator.recordForegroundFix(tileCode: "wtw3sk", fix: try fix(), now: now)

        let batchKey = UUID()
        let batch = try XCTUnwrap(coordinator.prepareContractBatch(key: batchKey))
        XCTAssertEqual(batch.cells.map(\.code), ["wtw3sj", "wtw3sk"])

        let afterVerdict = try coordinator.applyBatchVerdict(
            key: batchKey,
            acceptedCodes: ["wtw3sj"],
            rejectedCodes: ["wtw3sk"]
        )
        XCTAssertEqual(afterVerdict.confirmedTileCodes, ["wtw3sj"])
        XCTAssertTrue(afterVerdict.pendingPredictedTileCodes.isEmpty)
        XCTAssertEqual(afterVerdict.rolledBackTileCodes, ["wtw3sk"])
        XCTAssertEqual(afterVerdict.visibleRevealedTileCodes, ["wtw3sj"])
    }

    func testFogCoordinatorEnforcesOwnerIsolationAndSampleQualification() throws {
        var coordinator = try PersonalFogRoamHostCoordinator(ownerScope: "acct-1", samplePolicy: samplePolicy)
        XCTAssertThrowsError(try coordinator.ingestServerTilePage(owner: "acct-2", cells: ["wtw3sj"], nextCursor: 1)) { error in
            XCTAssertEqual(error as? PersonalFogFailure, .ownerMismatch)
        }
        XCTAssertThrowsError(try coordinator.recordForegroundFix(tileCode: "wtw3sj", fix: try fix(accuracy: 95), now: now)) { error in
            XCTAssertEqual(error as? PersonalFogFailure, .unqualifiedSample)
        }
        XCTAssertTrue(coordinator.overlayProjection.visibleRevealedTileCodes.isEmpty)
    }
}
