import XCTest
@testable import QuestifyCore

final class RouteCommunityDayProjectionTests: XCTestCase {
    func testFirstJourneySelectSimulateFreezeExplicitChoiceTakeSegmentRecoverOriginal() throws {
        var route = RouteCommunityDayProjection()
        var play = MechanismPlay()
        route.putFrozen(&play, segments: [
            MechanismSegmentRow(id: "market", label: "市集", communityDay: false,
                                effects: [MechanismEffect(op: "SET", varName: "clue.page", value: 1)])
        ], communityDay: MechanismCommunityDayRow(enabled: true, weekpart: "weekend"))
        play.playerChoice = MechanismChoice(mechanism: "routeCommunityDay", action: "TAKE_SEGMENT", segmentId: "market")
        let simulated = try route.simulate(play, originalRequestID: "route-1")
        XCTAssertTrue(simulated.simulated)
        XCTAssertNil(play.state.variables["clue.page"])
        let applied = try route.apply(&play, originalRequestID: "route-1")
        XCTAssertEqual(applied.requestId, "route-1")
        XCTAssertEqual(play.state.variables["clue.page"], 1)
        let duplicate = try route.apply(&play, originalRequestID: "route-1")
        XCTAssertEqual(duplicate.replay, true)
        XCTAssertEqual(play.state.variables["clue.page"], 1)
        var crashed = MechanismRequestIdProjection()
        _ = try crashed.markUnknown("route-1")
        var recover = play
        recover.originalAction = nil
        let unknown = try crashed.recoverUnknown(&recover, originalRequestID: "route-1")
        XCTAssertEqual(unknown.status, MechanismStatus.unknown.rawValue)
        recover.originalAction = play.originalAction
        let restored = try crashed.recoverUnknown(&recover, originalRequestID: "route-1")
        XCTAssertEqual(restored.replay, true)
        XCTAssertEqual(restored.segmentId, "market")
    }
    func testCommunityDayUsesServerWeekpartNotClientClock() throws {
        var route = RouteCommunityDayProjection()
        var play = MechanismFirstJourney.seededPlay()
        play.playerChoice = MechanismChoice(mechanism: "routeCommunityDay", action: "TAKE_SEGMENT",
                                            segmentId: "square")
        XCTAssertThrowsError(try route.apply(&play, originalRequestID: "day-miss")) { error in
            XCTAssertEqual(error as? MechanismFailure, .clientClockForbidden)
        }
        play.state.environment["weekpart"] = "weekend"
        play = MechanismFirstJourney.seededPlay()
        play.state.environment["weekpart"] = "weekend"
        play.playerChoice = MechanismChoice(mechanism: "routeCommunityDay", action: "TAKE_SEGMENT",
                                            segmentId: "square")
        route = RouteCommunityDayProjection()
        let taken = try route.apply(&play, originalRequestID: "day-1")
        XCTAssertEqual(taken.weekpart, "weekend")
        XCTAssertEqual(taken.communityDay, true)
        XCTAssertEqual(waiting { try route.succeedFromClientClock(Date()) }, .clientClockForbidden)
        XCTAssertEqual(waiting { try route.commitV12Docx() },
                       .waitingSource(capability: MechanismSourceInventory.v12Docx))
    }
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
