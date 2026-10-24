import XCTest
@testable import QuestifyCore

final class OracleBountyProjectionTests: XCTestCase {
    func testFirstJourneySelectSimulateFreezeExplicitChoiceConsultRecoverOriginal() throws {
        var oracle = OracleBountyProjection()
        var play = MechanismPlay()
        oracle.putFrozen(&play, oracles: [MechanismOracleRow(
            id: "street_lamp", label: "路灯", revelation: "巡夜人换班了",
            effects: [MechanismEffect(op: "ADD_CONDITION", text: "noticed")])],
                         bounties: [MechanismBountyRow(
                            id: "night_watch", label: "巡夜赏", varName: "counter.hunt", ticks: 1, segments: 4)])
        play.playerChoice = MechanismChoice(mechanism: "oracleBounty", action: "CONSULT", oracleId: "street_lamp")
        let simulated = try oracle.simulate(play, originalRequestID: "oracle-1")
        XCTAssertTrue(simulated.simulated)
        XCTAssertNil(play.state.statusConditions)
        let applied = try oracle.apply(&play, originalRequestID: "oracle-1")
        XCTAssertEqual(applied.requestId, "oracle-1")
        XCTAssertEqual(applied.revelation, "巡夜人换班了")
        XCTAssertEqual(play.state.statusConditions?.contains("noticed"), true)
        let duplicate = try oracle.apply(&play, originalRequestID: "oracle-1")
        XCTAssertEqual(duplicate.replay, true)
        var crashed = MechanismRequestIdProjection()
        _ = try crashed.markUnknown("oracle-1")
        var recover = play
        recover.originalAction = nil
        let unknown = try crashed.recoverUnknown(&recover, originalRequestID: "oracle-1")
        XCTAssertEqual(unknown.status, MechanismStatus.unknown.rawValue)
        recover.originalAction = play.originalAction
        let restored = try crashed.recoverUnknown(&recover, originalRequestID: "oracle-1")
        XCTAssertEqual(restored.replay, true)
        XCTAssertEqual(restored.oracleId, "street_lamp")
    }
    func testClaimTicksAuthorClockAndDoesNotInventDice() throws {
        var oracle = OracleBountyProjection()
        var play = MechanismFirstJourney.seededPlay()
        play.playerChoice = MechanismChoice(mechanism: "oracleBounty", action: "CLAIM", bountyId: "night_watch")
        let claimed = try oracle.apply(&play, originalRequestID: "bounty-1")
        XCTAssertEqual(claimed.value, 1)
        XCTAssertEqual(claimed.claimed, false)
        XCTAssertEqual(play.state.variables["counter.hunt"], 1)
        XCTAssertEqual(waiting { try oracle.inventOracleDice() }, .diceInvented)
        XCTAssertEqual(waiting { try oracle.commitUnpushedIosSHA() },
                       .waitingSource(capability: MechanismSourceInventory.unpushedIosSHA))
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueConsultApplies() throws {
        var oracle = OracleBountyProjection()
        var unseen = MechanismFirstJourney.seededPlay()
        unseen.originalAction = nil
        unseen.playerChoice = nil
        let recovered = try oracle.recoverOriginal(&unseen, originalRequestID: "c03-oracle-never")
        XCTAssertEqual(recovered.requestId, "c03-oracle-never")
        XCTAssertEqual(recovered.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertEqual(recovered.replay, false)
        XCTAssertNil(oracle.binder.existing("c03-oracle-never"))
        unseen.playerChoice = MechanismChoice(mechanism: "oracleBounty", action: "CONSULT",
                                              oracleId: "street_lamp")
        let applied = try oracle.apply(&unseen, originalRequestID: "c03-oracle-never")
        XCTAssertEqual(applied.requestId, "c03-oracle-never")
        XCTAssertEqual(applied.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(applied.revelation, "巡夜人换班了")
        XCTAssertEqual(applied.replay, false)
        XCTAssertEqual(applied.mintedNewRequest, false)
        XCTAssertEqual(oracle.binder.existing("c03-oracle-never")?.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(oracle.binder.existing("c03-oracle-never")?.requestId, "c03-oracle-never")
        let replay = try oracle.apply(&unseen, originalRequestID: "c03-oracle-never")
        XCTAssertEqual(replay.replay, true)
        XCTAssertEqual(replay.requestId, "c03-oracle-never")
        XCTAssertEqual(oracle.binder.existing("c03-oracle-never")?.status, MechanismStatus.applied.rawValue)
    }
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
