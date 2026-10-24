import XCTest
@testable import QuestifyCore

final class MechanismRequestIdProjectionTests: XCTestCase {
    func testFirstJourneySelectSimulateFreezeExplicitChoiceApplyRecoverOriginal() throws {
        var binder = MechanismRequestIdProjection()
        var clocks = ProgressClockMomentumAspectProjection(binder: binder)
        var play = MechanismFirstJourney.seededPlay()
        XCTAssertTrue(play.frozen.progressClockEnabled)
        XCTAssertTrue(play.frozen.tradeBargainEnabled)
        XCTAssertTrue(play.frozen.oracleBountyEnabled)
        XCTAssertTrue(play.frozen.oathFlashbackEnabled)
        XCTAssertTrue(play.frozen.routeCommunityDayEnabled)
        XCTAssertTrue(play.frozen.clueSecretGoalEnabled)
        play.playerChoice = MechanismChoice(mechanism: "progressClock", action: "TICK_CLOCK",
                                            varName: "counter.alarm")
        let simulated = try clocks.simulate(play, originalRequestID: MechanismFirstJourney.requestID)
        XCTAssertTrue(simulated.simulated)
        XCTAssertEqual(simulated.value, 1)
        XCTAssertNil(play.state.variables["counter.alarm"])
        let applied = try clocks.apply(&play, originalRequestID: MechanismFirstJourney.requestID)
        XCTAssertEqual(applied.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(applied.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(applied.mintedNewRequest, false)
        XCTAssertEqual(applied.value, 1)
        XCTAssertEqual(play.state.variables["counter.alarm"], 1)
        binder = clocks.binder
        let readback = try binder.readback(MechanismFirstJourney.requestID)
        XCTAssertEqual(readback.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(readback.replay, true)
        XCTAssertEqual(readback.value, 1)
        let duplicate = try clocks.apply(&play, originalRequestID: MechanismFirstJourney.requestID)
        XCTAssertEqual(duplicate.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(duplicate.replay, true)
        XCTAssertEqual(play.state.variables["counter.alarm"], 1)
        let original = try XCTUnwrap(play.originalAction)
        XCTAssertEqual(original.actionId, MechanismFirstJourney.requestID)
        var crashed = MechanismRequestIdProjection()
        _ = try crashed.markUnknown(MechanismFirstJourney.requestID)
        var recover = MechanismFirstJourney.seededPlay()
        recover.state.variables["counter.alarm"] = 9
        let stillUnknown = try crashed.recoverUnknown(&recover, originalRequestID: MechanismFirstJourney.requestID)
        XCTAssertEqual(stillUnknown.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(stillUnknown.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(stillUnknown.mintedNewRequest, false)
        XCTAssertNotEqual(stillUnknown.status, MechanismStatus.applied.rawValue)
        recover.originalAction = original
        let restored = try crashed.recoverUnknown(&recover, originalRequestID: MechanismFirstJourney.requestID)
        XCTAssertEqual(restored.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(restored.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(restored.replay, true)
        XCTAssertEqual(restored.value, 1)
        recover.originalAction = MechanismOriginalAction(
            actionId: "retry:" + MechanismFirstJourney.requestID, receiptId: original.receiptId, result: original.result)
        XCTAssertThrowsError(try crashed.recoverUnknown(&recover, originalRequestID: MechanismFirstJourney.requestID)) { error in
            XCTAssertEqual(error as? MechanismFailure, .mintedNewRequest)
        }
    }
    func testUntrustedJSONNullStaysOptionalNone() {
        XCTAssertEqual(MechanismUntrusted.decode(NSNull()), .null)
        XCTAssertEqual(MechanismUntrusted.decode(nil), .null)
        XCTAssertNil(MechanismUntrusted.text(""))
        XCTAssertNil(MechanismUntrusted.text("   "))
        XCTAssertNil(MechanismUntrusted.text(MechanismJSON.null))
        XCTAssertNil(MechanismUntrusted.stringSet(nil))
        XCTAssertNil(MechanismOpenDecision.faction.inventedNumber)
        XCTAssertNil(MechanismOpenDecision.territory.inventedNumber)
        XCTAssertNil(MechanismOpenDecision.secretGoalEconomy.inventedNumber)
    }
    func testOtherRequestDoesNotRewriteOriginalClock() throws {
        var clocks = ProgressClockMomentumAspectProjection()
        var original = MechanismFirstJourney.seededPlay()
        original.playerChoice = MechanismChoice(mechanism: "progressClock", action: "TICK_CLOCK",
                                                varName: "counter.alarm")
        let applied = try clocks.apply(&original, originalRequestID: MechanismFirstJourney.requestID)
        XCTAssertEqual(applied.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(applied.value, 1)
        var steal = MechanismFirstJourney.seededPlay()
        steal.playerChoice = original.playerChoice
        steal.state.variables["counter.alarm"] = 1
        let replay = try clocks.apply(&steal, originalRequestID: MechanismFirstJourney.requestID)
        XCTAssertEqual(replay.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(replay.replay, true)
        XCTAssertEqual(replay.value, 1)
        XCTAssertEqual(steal.state.variables["counter.alarm"], 1)
        let otherID = "check:9:other:tick"
        var independent = MechanismFirstJourney.seededPlay()
        independent.playerChoice = original.playerChoice
        let other = try clocks.apply(&independent, originalRequestID: otherID)
        XCTAssertEqual(other.requestId, otherID)
        XCTAssertNotEqual(other.requestId, MechanismFirstJourney.requestID)
        let originalReadback = try clocks.binder.readback(MechanismFirstJourney.requestID)
        XCTAssertEqual(originalReadback.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(originalReadback.value, 1)
        XCTAssertEqual(clocks.binder.existing(MechanismFirstJourney.requestID)?.requestId,
                       MechanismFirstJourney.requestID)
        XCTAssertEqual(clocks.binder.existing(MechanismFirstJourney.requestID)?.status,
                       MechanismStatus.applied.rawValue)
    }
    func testInProcessRecoverKeepsOriginalAppliedAndUnknown() throws {
        var clocks = ProgressClockMomentumAspectProjection()
        var original = MechanismFirstJourney.seededPlay()
        original.playerChoice = MechanismChoice(mechanism: "progressClock", action: "TICK_CLOCK",
                                                varName: "counter.alarm")
        _ = try clocks.apply(&original, originalRequestID: MechanismFirstJourney.requestID)
        var recovered = MechanismRequestIdProjection()
        _ = try recovered.completeApplied(
            MechanismFirstJourney.requestID,
            result: try clocks.binder.readback(MechanismFirstJourney.requestID),
            action: try XCTUnwrap(original.originalAction))
        let replay = try recovered.readback(MechanismFirstJourney.requestID)
        XCTAssertEqual(replay.requestId, MechanismFirstJourney.requestID)
        XCTAssertEqual(replay.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(replay.replay, true)
        XCTAssertEqual(replay.mintedNewRequest, false)
        XCTAssertEqual(replay.value, 1)
        var unknownBinder = MechanismRequestIdProjection()
        let unknownID = MechanismFirstJourney.requestID + "-unk"
        _ = try unknownBinder.markUnknown(unknownID)
        var unknownPlay = MechanismFirstJourney.seededPlay()
        let unknown = try unknownBinder.recoverUnknown(&unknownPlay, originalRequestID: unknownID)
        XCTAssertEqual(unknown.requestId, unknownID)
        XCTAssertEqual(unknown.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(unknown.mintedNewRequest, false)
        XCTAssertNotEqual(unknown.requestId, "retry:" + unknownID)
        XCTAssertEqual(try recovered.readback(MechanismFirstJourney.requestID).status,
                       MechanismStatus.applied.rawValue)
    }
    func testMissingRequestIDIsRefusedNeverStoredAsEmptyString() {
        var binder = MechanismRequestIdProjection()
        XCTAssertThrowsError(try MechanismRequestIdProjection.requireRequestID(nil)) { error in
            XCTAssertEqual(error as? MechanismFailure, .missingOriginalRequestID)
        }
        XCTAssertThrowsError(try MechanismRequestIdProjection.requireRequestID("  ")) { error in
            XCTAssertEqual(error as? MechanismFailure, .missingOriginalRequestID)
        }
        XCTAssertThrowsError(try binder.bind("  ", mechanism: "progressClock", choice: "TICK_CLOCK")) { error in
            XCTAssertEqual(error as? MechanismFailure, .missingOriginalRequestID)
        }
        XCTAssertThrowsError(try binder.readback("")) { error in
            XCTAssertEqual(error as? MechanismFailure, .missingOriginalRequestID)
        }
        XCTAssertNil(binder.existing(""))
        XCTAssertNil(binder.existing(MechanismFirstJourney.requestID))
        XCTAssertNil(MechanismUntrusted.text(""))
    }
    func testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenOneShotApplies() throws {
        var clocks = ProgressClockMomentumAspectProjection()
        var unseen = MechanismFirstJourney.seededPlay()
        unseen.originalAction = nil
        var binder = clocks.binder
        XCTAssertEqual(try binder.markUnknown("c03-never-seen").status, MechanismStatus.unknown.rawValue)
        XCTAssertNil(binder.existing("c03-never-seen"))
        clocks.binder = binder
        let recovered = try clocks.recoverOriginal(&unseen, originalRequestID: "c03-never-seen")
        XCTAssertEqual(recovered.requestId, "c03-never-seen")
        XCTAssertEqual(recovered.status, MechanismStatus.unknown.rawValue)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertEqual(recovered.replay, false)
        XCTAssertNil(clocks.binder.existing("c03-never-seen"))
        unseen.playerChoice = MechanismChoice(mechanism: "progressClock", action: "TICK_CLOCK",
                                              varName: "counter.alarm")
        let applied = try clocks.apply(&unseen, originalRequestID: "c03-never-seen")
        XCTAssertEqual(applied.requestId, "c03-never-seen")
        XCTAssertEqual(applied.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(applied.replay, false)
        XCTAssertEqual(applied.mintedNewRequest, false)
        XCTAssertEqual(applied.value, 1)
        XCTAssertEqual(clocks.binder.existing("c03-never-seen")?.status, MechanismStatus.applied.rawValue)
        XCTAssertEqual(clocks.binder.existing("c03-never-seen")?.requestId, "c03-never-seen")
    }
    func testWaitingSourceUnsignedOriginalsAreNotRewritten() {
        var binder = MechanismRequestIdProjection()
        XCTAssertFalse(MechanismSourceInventory.v12DocxPresent)
        XCTAssertFalse(MechanismSourceInventory.pack232Present)
        XCTAssertFalse(MechanismSourceInventory.unpushedIosSHAPresent)
        XCTAssertEqual(waiting { try binder.commitUnsignedOriginal(capability: MechanismSourceInventory.v12Docx) },
                       .waitingSource(capability: MechanismSourceInventory.v12Docx))
        XCTAssertEqual(waiting { try binder.commitUnsignedOriginal(capability: MechanismSourceInventory.pack232) },
                       .waitingSource(capability: MechanismSourceInventory.pack232))
        XCTAssertEqual(waiting { try binder.commitUnsignedOriginal(capability: MechanismSourceInventory.unpushedIosSHA) },
                       .waitingSource(capability: MechanismSourceInventory.unpushedIosSHA))
        XCTAssertEqual(waiting { try binder.rewriteUnsignedSource() }, .unsignedSourceRewrite)
        XCTAssertEqual(waiting { try binder.inventLocalDice() }, .diceInvented)
    }
    func testRecoverFromRouteActionDoesNotBindNeverSeenId() throws {
        var binder = MechanismRequestIdProjection()
        XCTAssertNil(try binder.recoverFromRouteAction(sessionID: 0, memberID: 7, actionID: "check:1:alarm:tick", selectAction: { _, _, _ in
            RouteActionOriginalRow(actionID: "check:1:alarm:tick", responseJSON: "{}")
        }))
        do {
            _ = try binder.recoverFromRouteAction(sessionID: 30, memberID: 7, actionID: "check:1:alarm:tick", selectAction: nil)
            XCTFail("missing select must WAITING_SOURCE")
        } catch let error as MechanismFailure {
            XCTAssertEqual(error, .waitingSource(capability: MechanismRequestIdProjection.selectActionByAction))
        }
        XCTAssertNil(binder.existing("check:1:alarm:tick"))
        XCTAssertNil(try binder.recoverFromRouteAction(sessionID: 30, memberID: 7, actionID: "c03-route-missing", selectAction: { _, _, _ in nil }))
        XCTAssertNil(binder.existing("c03-route-missing"))
        let row = try binder.recoverFromRouteAction(sessionID: 30, memberID: 7, actionID: "check:1:alarm:tick", selectAction: { session, member, id in
            session == 30 && member == 7 && id == "check:1:alarm:tick"
                ? RouteActionOriginalRow(actionID: id, responseJSON: "{\"ok\":true}") : nil
        })
        XCTAssertEqual(row?.responseJSON, "{\"ok\":true}")
        XCTAssertNil(binder.existing("check:1:alarm:tick"))
    }
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
