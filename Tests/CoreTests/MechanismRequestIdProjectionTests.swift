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
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
