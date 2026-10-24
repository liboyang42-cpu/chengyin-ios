import XCTest
@testable import QuestifyCore

final class OathFlashbackProjectionTests: XCTestCase {
    func testFirstJourneySelectSimulateFreezeExplicitChoiceSwearRecoverOriginal() throws {
        var oaths = OathFlashbackProjection()
        var play = MechanismPlay()
        try oaths.putFrozen(&play, oaths: [MechanismOathRow(
            key: "keep_silent", label: "守口",
            effects: [MechanismEffect(op: "ADD_CONDITION", text: "keep_silent")])],
                            flashbacks: [MechanismFlashbackRow(
                                id: "alley", label: "巷口", restoreKeys: ["clue.page"],
                                password: MechanismUntrusted.text("author-set-cipher"), snapshot: [:])])
        play.playerChoice = MechanismChoice(mechanism: "oathFlashback", action: "SWEAR", oathKey: "keep_silent")
        let simulated = try oaths.simulate(play, originalRequestID: "oath-1")
        XCTAssertTrue(simulated.simulated)
        XCTAssertNil(play.state.statusConditions)
        let applied = try oaths.apply(&play, originalRequestID: "oath-1")
        XCTAssertEqual(applied.requestId, "oath-1")
        XCTAssertEqual(applied.active, true)
        let duplicate = try oaths.apply(&play, originalRequestID: "oath-1")
        XCTAssertEqual(duplicate.replay, true)
        var crashed = MechanismRequestIdProjection()
        _ = try crashed.markUnknown("oath-1")
        var recover = play
        recover.originalAction = nil
        let unknown = try crashed.recoverUnknown(&recover, originalRequestID: "oath-1")
        XCTAssertEqual(unknown.status, MechanismStatus.unknown.rawValue)
        recover.originalAction = play.originalAction
        let restored = try crashed.recoverUnknown(&recover, originalRequestID: "oath-1")
        XCTAssertEqual(restored.replay, true)
        XCTAssertEqual(restored.oathKey, "keep_silent")
    }
    func testFlashbackPasswordComesFromFrozenAuthorConfigNotAGlobalConstant() throws {
        var oaths = OathFlashbackProjection()
        var play = MechanismPlay()
        play.state.variables["clue.page"] = 7
        try oaths.putFrozen(&play, oaths: nil, flashbacks: [MechanismFlashbackRow(
            id: "alley", label: "巷口", restoreKeys: ["clue.page"],
            password: MechanismUntrusted.text("author-set-cipher"), snapshot: [:])])
        XCTAssertEqual(play.frozen.flashbacks.first?.password, "author-set-cipher")
        XCTAssertEqual(play.frozen.flashbacks.first?.snapshot["clue.page"], 7)
        play.state.variables["clue.page"] = 1
        play.playerChoice = MechanismChoice(mechanism: "oathFlashback", action: "FLASHBACK",
                                            flashbackId: "alley", password: nil)
        XCTAssertThrowsError(try oaths.apply(&play, originalRequestID: "fb-miss")) { error in
            XCTAssertEqual(error as? MechanismFailure, .passwordMismatch)
        }
        play.playerChoice = MechanismChoice(mechanism: "oathFlashback", action: "FLASHBACK",
                                            flashbackId: "alley", password: "author-set-cipher")
        let restored = try oaths.apply(&play, originalRequestID: "fb-1")
        XCTAssertEqual(restored.restored?["clue.page"], 7)
        XCTAssertEqual(play.state.variables["clue.page"], 7)
        XCTAssertEqual(restored.passwordChecked, true)
        XCTAssertEqual(waiting { try oaths.commitPack232() },
                       .waitingSource(capability: MechanismSourceInventory.pack232))
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueSwearApplies() throws {
        var oaths = OathFlashbackProjection()
        var unseen = MechanismFirstJourney.seededPlay()
        unseen.originalAction = nil
        unseen.playerChoice = nil
        let recovered = try oaths.recoverOriginal(&unseen, originalRequestID: "c03-oath-never")
        XCTAssertEqual(recovered.requestId, "c03-oath-never")
        XCTAssertEqual(recovered.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertEqual(recovered.replay, false)
        XCTAssertNil(oaths.binder.existing("c03-oath-never"))
        unseen.playerChoice = MechanismChoice(mechanism: "oathFlashback", action: "SWEAR",
                                              oathKey: "keep_silent")
        let applied = try oaths.apply(&unseen, originalRequestID: "c03-oath-never")
        XCTAssertEqual(applied.requestId, "c03-oath-never")
        XCTAssertEqual(applied.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(applied.active, true)
        XCTAssertEqual(applied.replay, false)
        XCTAssertEqual(applied.mintedNewRequest, false)
        XCTAssertEqual(oaths.binder.existing("c03-oath-never")?.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(oaths.binder.existing("c03-oath-never")?.requestId, "c03-oath-never")
        let replay = try oaths.apply(&unseen, originalRequestID: "c03-oath-never")
        XCTAssertEqual(replay.replay, true)
        XCTAssertEqual(replay.requestId, "c03-oath-never")
        XCTAssertEqual(oaths.binder.existing("c03-oath-never")?.status, MechanismStatus.applied.rawValue)
    }
    func testUntrustedEmptyPasswordStaysNone() {
        XCTAssertNil(MechanismUntrusted.text(""))
        let row = MechanismFlashbackRow(id: "alley", label: "巷口", restoreKeys: ["clue.page"],
                                        password: MechanismUntrusted.text(""), snapshot: [:])
        XCTAssertNil(row.password)
    }
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
