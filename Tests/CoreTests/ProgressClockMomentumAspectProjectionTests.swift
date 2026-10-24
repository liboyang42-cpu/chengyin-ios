import XCTest
@testable import QuestifyCore

final class ProgressClockMomentumAspectProjectionTests: XCTestCase {
    func testFirstJourneySelectSimulateFreezeExplicitChoiceTickClockRecoverOriginal() throws {
        var clocks = ProgressClockMomentumAspectProjection()
        var play = MechanismPlay()
        clocks.putFrozen(&play, clocks: [MechanismClockRow(varName: "counter.alarm", label: "警报", segments: 4)],
                         momentum: MechanismMomentumRow(enabled: true, max: 6, maxSpend: 3),
                         aspects: [MechanismAspectRow(key: "night_owl", label: "夜猫子")])
        XCTAssertTrue(play.frozen.progressClockEnabled)
        play.playerChoice = MechanismChoice(mechanism: "progressClock", action: "TICK_CLOCK", varName: "counter.alarm")
        let simulated = try clocks.simulate(play, originalRequestID: "clock-1")
        XCTAssertTrue(simulated.simulated)
        XCTAssertEqual(simulated.value, 1)
        XCTAssertNil(play.state.variables["counter.alarm"])
        let applied = try clocks.apply(&play, originalRequestID: "clock-1")
        XCTAssertEqual(applied.requestId, "clock-1")
        XCTAssertEqual(applied.value, 1)
        XCTAssertEqual(play.state.variables["counter.alarm"], 1)
        let duplicate = try clocks.apply(&play, originalRequestID: "clock-1")
        XCTAssertEqual(duplicate.replay, true)
        XCTAssertEqual(play.state.variables["counter.alarm"], 1)
        var crashed = MechanismRequestIdProjection()
        _ = try crashed.markUnknown("clock-1")
        var recover = play
        recover.originalAction = nil
        recover.state.variables["counter.alarm"] = 4
        let unknown = try crashed.recoverUnknown(&recover, originalRequestID: "clock-1")
        XCTAssertEqual(unknown.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(unknown.requestId, "clock-1")
        recover.originalAction = play.originalAction
        let restored = try crashed.recoverUnknown(&recover, originalRequestID: "clock-1")
        XCTAssertEqual(restored.value, 1)
        XCTAssertEqual(restored.replay, true)
    }
    func testSpendMomentumAndInvokeAspectUseFrozenAuthorConfig() throws {
        var clocks = ProgressClockMomentumAspectProjection()
        var play = MechanismFirstJourney.seededPlay()
        play.playerChoice = MechanismChoice(mechanism: "progressClock", action: "SPEND_MOMENTUM", spend: 1)
        play.originalRequestID = "mom-1"
        let spent = try clocks.apply(&play, originalRequestID: "mom-1")
        XCTAssertEqual(spent.value, 1)
        XCTAssertEqual(play.momentum, 1)
        var aspectPlay = MechanismFirstJourney.seededPlay()
        clocks = ProgressClockMomentumAspectProjection()
        aspectPlay.playerChoice = MechanismChoice(mechanism: "progressClock", action: "INVOKE_ASPECT", key: "night_owl")
        let aspect = try clocks.apply(&aspectPlay, originalRequestID: "asp-1")
        XCTAssertEqual(aspect.active, true)
        XCTAssertEqual(aspectPlay.state.statusConditions?.contains("night_owl"), true)
    }
    func testMissingExplicitChoiceDoesNotDefaultApply() {
        var clocks = ProgressClockMomentumAspectProjection()
        var play = MechanismFirstJourney.seededPlay()
        XCTAssertThrowsError(try clocks.apply(&play, originalRequestID: "clock-x")) { error in
            XCTAssertEqual(error as? MechanismFailure, .explicitChoiceRequired)
        }
        XCTAssertNil(play.state.variables["counter.alarm"])
    }
    func testWaitingSourceV12Docx() {
        var clocks = ProgressClockMomentumAspectProjection()
        XCTAssertEqual(waiting { try clocks.commitV12Docx() },
                       .waitingSource(capability: MechanismSourceInventory.v12Docx))
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueTickApplies() throws {
        var clocks = ProgressClockMomentumAspectProjection()
        var unseen = MechanismFirstJourney.seededPlay()
        unseen.originalAction = nil
        unseen.playerChoice = nil
        let recovered = try clocks.recoverOriginal(&unseen, originalRequestID: "c03-clock-never")
        XCTAssertEqual(recovered.requestId, "c03-clock-never")
        XCTAssertEqual(recovered.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertEqual(recovered.replay, false)
        XCTAssertNil(clocks.binder.existing("c03-clock-never"))
        unseen.playerChoice = MechanismChoice(mechanism: "progressClock", action: "TICK_CLOCK",
                                              varName: "counter.alarm")
        let applied = try clocks.apply(&unseen, originalRequestID: "c03-clock-never")
        XCTAssertEqual(applied.requestId, "c03-clock-never")
        XCTAssertEqual(applied.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(applied.value, 1)
        XCTAssertEqual(applied.replay, false)
        XCTAssertEqual(applied.mintedNewRequest, false)
        XCTAssertEqual(clocks.binder.existing("c03-clock-never")?.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(clocks.binder.existing("c03-clock-never")?.requestId, "c03-clock-never")
        let replay = try clocks.apply(&unseen, originalRequestID: "c03-clock-never")
        XCTAssertEqual(replay.replay, true)
        XCTAssertEqual(replay.requestId, "c03-clock-never")
        XCTAssertEqual(clocks.binder.existing("c03-clock-never")?.status, MechanismStatus.applied.rawValue)
    }
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
