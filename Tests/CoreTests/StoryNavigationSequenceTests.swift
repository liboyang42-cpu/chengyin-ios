import XCTest
@testable import QuestifyCore

final class StoryNavigationSequenceTests: XCTestCase {
    private func stop(_ id: Int, mission: Int = 8) throws -> WalkingTargetReference { try .init(kind: .storyNode, id: id, missionID: mission) }
    private func readback(_ revision: Int, stop id: Int?, finished: Bool = false) throws -> StoryRouteStateReadback {
        try .init(missionID: 8, revision: revision, currentStop: id.map { try stop($0) }, finished: finished)
    }
    func testReadbackOnlyCarriesOneStoryStopForThisMission() throws {
        XCTAssertThrowsError(try StoryRouteStateReadback(missionID: 8, revision: 1, currentStop: try .init(kind: .cityNode, id: 1), finished: false))
        XCTAssertThrowsError(try StoryRouteStateReadback(missionID: 8, revision: 1, currentStop: try stop(1, mission: 9), finished: false))
        XCTAssertThrowsError(try StoryRouteStateReadback(missionID: 8, revision: 1, currentStop: try stop(1), finished: true))
    }
    func testStationsAdvanceOnlyThroughAuthority() throws {
        var sequence = try StoryNavigationSequence(missionID: 8)
        XCTAssertNil(sequence.navigableStop)
        try sequence.apply(readback(1, stop: 1))
        XCTAssertEqual(sequence.navigableStop, try stop(1))
        sequence.reachedNearDestination(try stop(1))
        XCTAssertEqual(sequence.phase, .verificationAvailable(try stop(1)))
        XCTAssertNil(sequence.navigableStop)
        sequence.submittedVerification(try stop(1))
        XCTAssertEqual(sequence.phase, .verificationSubmitted(try stop(1)))
        // Authority still says stop 1: no client-side advance.
        try sequence.apply(readback(2, stop: 1))
        XCTAssertEqual(sequence.phase, .verificationSubmitted(try stop(1)))
        try sequence.apply(readback(3, stop: 2))
        XCTAssertEqual(sequence.navigableStop, try stop(2))
        try sequence.apply(readback(4, stop: nil, finished: true))
        XCTAssertEqual(sequence.phase, .finished)
    }
    func testStaleOrForeignReadbacksIgnored() throws {
        var sequence = try StoryNavigationSequence(missionID: 8)
        try sequence.apply(readback(5, stop: 3))
        XCTAssertThrowsError(try sequence.apply(readback(4, stop: 2))) { XCTAssertEqual($0 as? StoryNavigationFailure, .staleReadback) }
        XCTAssertThrowsError(try sequence.apply(readback(5, stop: 2)))
        XCTAssertThrowsError(try sequence.apply(StoryRouteStateReadback(missionID: 9, revision: 6, currentStop: nil, finished: false))) {
            XCTAssertEqual($0 as? StoryNavigationFailure, .wrongMission)
        }
        XCTAssertEqual(sequence.navigableStop, try stop(3))
    }
    func testArrivalForAnotherStopOrNoStopDoesNothing() throws {
        var sequence = try StoryNavigationSequence(missionID: 8)
        try sequence.apply(readback(1, stop: 1))
        sequence.reachedNearDestination(try stop(2))
        sequence.submittedVerification(try stop(1))
        XCTAssertEqual(sequence.phase, .navigating(try stop(1)))
        try sequence.apply(readback(2, stop: nil))
        XCTAssertEqual(sequence.phase, .noNavigableStop)
        XCTAssertThrowsError(try StoryNavigationSequence(missionID: 0))
    }
}
