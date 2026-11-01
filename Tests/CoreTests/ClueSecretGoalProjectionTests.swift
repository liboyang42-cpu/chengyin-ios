import XCTest
@testable import QuestifyCore

final class ClueSecretGoalProjectionTests: XCTestCase {
    func testFirstJourneySelectSimulateFreezeExplicitChoiceGainClueRecoverOriginal() throws {
        var clues = ClueSecretGoalProjection()
        var play = MechanismPlay()
        try clues.putFrozen(&play, clues: [MechanismClueRow(varName: "clue.page", label: "账页")],
                            secretGoals: [MechanismSecretGoalRow(
                                key: "find_ledger", label: "找到账本",
                                when: MechanismCondition(op: "EQ", varName: "clue.page", value: 1))])
        play.playerChoice = MechanismChoice(mechanism: "clueSecretGoal", action: "GAIN_CLUE", varName: "clue.page")
        let simulated = try clues.simulate(play, originalRequestID: "clue-1")
        XCTAssertTrue(simulated.simulated)
        XCTAssertNil(play.state.variables["clue.page"])
        let applied = try clues.apply(&play, originalRequestID: "clue-1")
        XCTAssertEqual(applied.requestId, "clue-1")
        XCTAssertEqual(applied.value, 1)
        let duplicate = try clues.apply(&play, originalRequestID: "clue-1")
        XCTAssertEqual(duplicate.replay, true)
        XCTAssertEqual(play.state.variables["clue.page"], 1)
        var crashed = MechanismRequestIdProjection()
        _ = try crashed.markUnknown("clue-1")
        var recover = play
        recover.originalAction = nil
        recover.state.variables["clue.page"] = 9
        let unknown = try crashed.recoverUnknown(&recover, originalRequestID: "clue-1")
        XCTAssertEqual(unknown.status, MechanismStatus.unknown.rawValue)
        XCTAssertNotEqual(unknown.value, 9)
        recover.originalAction = play.originalAction
        let restored = try crashed.recoverUnknown(&recover, originalRequestID: "clue-1")
        XCTAssertEqual(restored.replay, true)
        XCTAssertEqual(restored.value, 1)
    }
    func testSecretGoalReportsWhenWithoutInventingRewards() throws {
        var clues = ClueSecretGoalProjection()
        var play = MechanismFirstJourney.seededPlay()
        play.playerChoice = MechanismChoice(mechanism: "clueSecretGoal", action: "CHECK_GOAL",
                                            goalKey: "find_ledger")
        let miss = try clues.apply(&play, originalRequestID: "goal-miss")
        XCTAssertEqual(miss.met, false)
        play.state.variables["clue.page"] = 1
        play.originalRequestID = "goal-hit"
        clues = ClueSecretGoalProjection()
        let hit = try clues.apply(&play, originalRequestID: "goal-hit")
        XCTAssertEqual(hit.met, true)
        XCTAssertNil(hit.bonus)
        XCTAssertNil(hit.total)
    }
    func testUnconfirmedEconomyFieldsAreOpenDecisionsNotInventedNumbers() throws {
        var clues = ClueSecretGoalProjection()
        XCTAssertThrowsError(try clues.select(clues: nil, secretGoals: nil,
                                              untrusted: ["factionReward": .int(10)])) { error in
            XCTAssertEqual(error as? MechanismFailure, .openDecision(.faction))
        }
        XCTAssertThrowsError(try clues.select(clues: nil, secretGoals: nil,
                                              untrusted: ["territory": .object(["hp": .int(5)])])) { error in
            XCTAssertEqual(error as? MechanismFailure, .openDecision(.territory))
        }
        XCTAssertThrowsError(try clues.select(clues: nil, secretGoals: nil,
                                              untrusted: ["reward": .int(100)])) { error in
            XCTAssertEqual(error as? MechanismFailure, .openDecision(.secretGoalEconomy))
        }
        XCTAssertNil(MechanismOpenDecision.secretGoalEconomy.inventedNumber)
        XCTAssertEqual(waiting { try clues.commitPack232() },
                       .waitingSource(capability: MechanismSourceInventory.pack232))
        var state = MechanismPlayState()
        state.variables["clue.h_page"] = 1
        try state.apply(MechanismEffect(op: "SET", varName: "clue.h_page", value: 0))
        XCTAssertEqual(state.variables["clue.h_page"], 1)
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueGainClueApplies() throws {
        var clues = ClueSecretGoalProjection()
        var unseen = MechanismFirstJourney.seededPlay()
        unseen.originalAction = nil
        unseen.playerChoice = nil
        let recovered = try clues.recoverOriginal(&unseen, originalRequestID: "c03-clue-never")
        XCTAssertEqual(recovered.requestId, "c03-clue-never")
        XCTAssertEqual(recovered.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertEqual(recovered.replay, false)
        XCTAssertNil(clues.binder.existing("c03-clue-never"))
        unseen.playerChoice = MechanismChoice(mechanism: "clueSecretGoal", action: "GAIN_CLUE",
                                              varName: "clue.page")
        let applied = try clues.apply(&unseen, originalRequestID: "c03-clue-never")
        XCTAssertEqual(applied.requestId, "c03-clue-never")
        XCTAssertEqual(applied.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(applied.value, 1)
        XCTAssertEqual(applied.replay, false)
        XCTAssertEqual(applied.mintedNewRequest, false)
        XCTAssertEqual(clues.binder.existing("c03-clue-never")?.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(clues.binder.existing("c03-clue-never")?.requestId, "c03-clue-never")
        let replay = try clues.apply(&unseen, originalRequestID: "c03-clue-never")
        XCTAssertEqual(replay.replay, true)
        XCTAssertEqual(replay.requestId, "c03-clue-never")
        XCTAssertEqual(clues.binder.existing("c03-clue-never")?.status, MechanismStatus.applied.rawValue)
    }
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
