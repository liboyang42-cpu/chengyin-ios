import XCTest
@testable import QuestifyCore

final class TradeBargainProjectionTests: XCTestCase {
    func testFirstJourneySelectSimulateFreezeExplicitChoiceAcceptRecoverOriginal() throws {
        var trade = TradeBargainProjection()
        var play = MechanismPlay()
        trade.putFrozen(&play, themeEnabled: true, bargain: MechanismBargainRow(
            label: "惊动了巡夜人", bonus: 2,
            effects: [MechanismEffect(op: "TICK_CLOCK", varName: "counter.alarm", value: 1, max: 4)]))
        play.playerChoice = MechanismChoice(mechanism: "tradeBargain", action: "ACCEPT")
        let simulated = try trade.simulate(play, originalRequestID: "bargain-1")
        XCTAssertTrue(simulated.simulated)
        XCTAssertNil(play.state.variables["counter.alarm"])
        XCTAssertNil(simulated.total)
        let applied = try trade.apply(&play, originalRequestID: "bargain-1")
        XCTAssertEqual(applied.requestId, "bargain-1")
        XCTAssertEqual(applied.accepted, true)
        XCTAssertEqual(applied.bonus, 2)
        XCTAssertNil(applied.total)
        XCTAssertEqual(play.state.variables["counter.alarm"], 1)
        let duplicate = try trade.apply(&play, originalRequestID: "bargain-1")
        XCTAssertEqual(duplicate.replay, true)
        XCTAssertEqual(play.state.variables["counter.alarm"], 1)
        var crashed = MechanismRequestIdProjection()
        _ = try crashed.markUnknown("bargain-1")
        var recover = play
        recover.originalAction = nil
        let unknown = try crashed.recoverUnknown(&recover, originalRequestID: "bargain-1")
        XCTAssertEqual(unknown.status, MechanismStatus.unknown.rawValue)
        recover.originalAction = play.originalAction
        let restored = try crashed.recoverUnknown(&recover, originalRequestID: "bargain-1")
        XCTAssertEqual(restored.replay, true)
        XCTAssertEqual(restored.accepted, true)
    }
    func testDeclineDoesNotWriteCostsAndDoesNotInventDice() throws {
        var trade = TradeBargainProjection()
        var play = MechanismFirstJourney.seededPlay()
        play.playerChoice = MechanismChoice(mechanism: "tradeBargain", action: "DECLINE")
        let declined = try trade.apply(&play, originalRequestID: "bargain-2")
        XCTAssertEqual(declined.accepted, false)
        XCTAssertNil(play.state.variables["counter.alarm"])
        XCTAssertNil(declined.total)
        XCTAssertEqual(waiting { try trade.rollLocalDice() },
                       .waitingSource(capability: MechanismSourceInventory.unpushedIosSHA))
        XCTAssertEqual(waiting { try trade.inventDice() }, .diceInvented)
    }
    func testInjectedServerReceiptIsNotALocalDice() throws {
        var trade = TradeBargainProjection()
        var play = MechanismFirstJourney.seededPlay()
        play.playerChoice = MechanismChoice(mechanism: "tradeBargain", action: "ACCEPT")
        play.serverCheckReceipt = MechanismCheckReceipt(total: 13, success: true, bargainBonus: 2)
        let dealt = try trade.apply(&play, originalRequestID: "bargain-3")
        XCTAssertEqual(dealt.total, 13)
        XCTAssertEqual(dealt.success, true)
        XCTAssertEqual(dealt.bonus, 2)
    }
    private func waiting(_ body: () throws -> Never) -> MechanismFailure? {
        do { try body(); return nil } catch let error as MechanismFailure { return error } catch { return nil }
    }
}
