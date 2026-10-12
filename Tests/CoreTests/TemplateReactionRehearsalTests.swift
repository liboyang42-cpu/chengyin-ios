import XCTest
@testable import QuestifyCore

final class TemplateReactionRehearsalTests: XCTestCase {
    private func make(rounds: Int = 3, goal: Double = 320) throws -> TemplateReactionRehearsal {
        var draft = TemplateAdvancedDraft(); draft.set("reaction", "rounds", .number(Double(rounds))); draft.set("reaction", "goalMs", .number(goal))
        return try XCTUnwrap(TemplateReactionRehearsal(draft, mode: .currentConfiguration))
    }
    private func accepted(_ item: inout TemplateReactionRehearsal, start: Double, ms: Double) {
        item.arm(at: start, delayUnit: 0); item.signal(at: start + 1400); item.tap(at: start + 1400 + ms)
    }
    func testCurrentValuesDoNotEnableOrMutateOriginal() throws {
        let original = TemplateAdvancedDraft(), item = try XCTUnwrap(TemplateReactionRehearsal(original, mode: .currentConfiguration))
        XCTAssertEqual(item.draft, original); XCTAssertFalse(item.draft.enabled("reaction")); XCTAssertEqual(item.kicker, "变绿就点")
        XCTAssertEqual(item.rounds, 3); XCTAssertEqual(item.goalMs, 320); XCTAssertTrue(item.filledFields.isEmpty)
    }
    func testSourceExampleOnlyFillsPristineKickerInCopy() throws {
        let original = TemplateAdvancedDraft(), item = try XCTUnwrap(TemplateReactionRehearsal(original, mode: .sourceExample))
        XCTAssertEqual(item.kicker, "屏幕一变色就点"); XCTAssertEqual(item.filledFields, ["kicker"])
        XCTAssertTrue(item.draft.enabled("reaction")); XCTAssertFalse(original.enabled("reaction")); XCTAssertEqual(original.text("reaction", "kicker"), "")
    }
    func testCustomAndWhitespaceKickersAreNotSeeded() throws {
        for text in ["My title", "   ", "\u{FEFF}", "\u{0085}", "\u{200B}"] {
            var draft = TemplateAdvancedDraft(); draft.set("reaction", "kicker", .string(text))
            let item = try XCTUnwrap(TemplateReactionRehearsal(draft, mode: .sourceExample))
            XCTAssertEqual(item.draft.text("reaction", "kicker"), text); XCTAssertTrue(item.filledFields.isEmpty)
        }
    }
    func testMissingKickerStaysMissingAndUsesSourceFallback() throws {
        var draft = TemplateAdvancedDraft(), fields = try XCTUnwrap(TemplateAdvancedDraft.defaults["reaction"]?.object)
        fields.removeValue(forKey: "kicker"); draft.value["reaction"] = .object(fields)
        let item = try XCTUnwrap(TemplateReactionRehearsal(draft, mode: .sourceExample))
        XCTAssertNil(item.draft.value["reaction"]?.object?["kicker"]); XCTAssertEqual(item.kicker, "变绿就点"); XCTAssertTrue(item.filledFields.isEmpty)
    }
    func testUnknownAndSiblingFieldsStayExact() throws {
        var draft = TemplateAdvancedDraft(); draft.set("reaction", "future", .object(["value": .string("retain")]))
        draft.set("coinFlip", "kicker", .string("keep coin")); let before = draft
        var item = try XCTUnwrap(TemplateReactionRehearsal(draft, mode: .currentConfiguration)); accepted(&item, start: 0, ms: 240); item.reset()
        XCTAssertEqual(item.draft, before); XCTAssertEqual(draft, before)
    }
    func testRangesAndIntegerRoundIntersectionFailClosed() {
        for (field, value) in [("rounds", 0.0), ("rounds", 11), ("rounds", 1.5), ("goalMs", 119), ("goalMs", 2001), ("goalMs", 3000), ("goalMs", Double.nan)] {
            var draft = TemplateAdvancedDraft(); draft.set("reaction", field, .number(value)); XCTAssertNil(TemplateReactionRehearsal(draft, mode: .sourceExample))
        }
    }
    func testNumericStringsAcceptedButMissingOrBlankNumbersRejected() throws {
        var draft = TemplateAdvancedDraft(); draft.set("reaction", "rounds", .string("2")); draft.set("reaction", "goalMs", .string("120"))
        XCTAssertEqual(TemplateReactionRehearsal(draft, mode: .currentConfiguration)?.rounds, 2)
        for field in ["rounds", "goalMs"] {
            var copy = draft; copy.set("reaction", field, .string(" ")); XCTAssertNil(TemplateReactionRehearsal(copy, mode: .currentConfiguration))
            var fields = try XCTUnwrap(draft.value["reaction"]?.object); fields.removeValue(forKey: field); copy.value["reaction"] = .object(fields)
            XCTAssertNil(TemplateReactionRehearsal(copy, mode: .sourceExample))
        }
    }
    func testUTF16TitleBoundaryAndWrongType() {
        var draft = TemplateAdvancedDraft(); draft.set("reaction", "kicker", .string(String(repeating: "🟢", count: 16)))
        XCTAssertNotNil(TemplateReactionRehearsal(draft, mode: .currentConfiguration)); draft.set("reaction", "kicker", .string(String(repeating: "🟢", count: 17)))
        XCTAssertNil(TemplateReactionRehearsal(draft, mode: .currentConfiguration)); draft.set("reaction", "kicker", .array([])); XCTAssertNil(TemplateReactionRehearsal(draft, mode: .currentConfiguration))
    }
    func testDeterministicDelayEndpointsAndRounding() {
        XCTAssertEqual(TemplateReactionRehearsal.waitMilliseconds(unit: 0), 1400); XCTAssertEqual(TemplateReactionRehearsal.waitMilliseconds(unit: 0.5), 2800)
        XCTAssertEqual(TemplateReactionRehearsal.waitMilliseconds(unit: 1), 4200); XCTAssertEqual(TemplateReactionRehearsal.waitMilliseconds(unit: 0.0002), 1401)
        for value in [-0.1, 1.1, Double.nan, Double.infinity] { XCTAssertNil(TemplateReactionRehearsal.waitMilliseconds(unit: value)) }
    }
    func testSignalCannotStartBeforeDeadline() throws {
        var item = try make(); item.arm(at: 100, delayUnit: 0); item.signal(at: 1499)
        XCTAssertEqual(item.phase, .waiting); XCTAssertEqual(item.waitUntil, 1500); item.signal(at: 1500); XCTAssertEqual(item.phase, .signal)
    }
    func testLateSignalAnchorsAtCallbackNotDeadline() throws {
        var item = try make(rounds: 1); item.arm(at: 0, delayUnit: 0); item.signal(at: 10000); item.tap(at: 10120)
        XCTAssertEqual(item.times, [120]); XCTAssertEqual(item.matched, true)
    }
    func testWaitingTapIsEarlyEvenAfterNominalDeadline() throws {
        var item = try make(); item.arm(at: 0, delayUnit: 0); item.tap(at: 5000)
        XCTAssertEqual(item.phase, .early); XCTAssertEqual(item.earlyReason, .beforeSignal); XCTAssertTrue(item.times.isEmpty)
        item.signal(at: 5100); XCTAssertEqual(item.phase, .early)
    }
    func test119Rejected120AcceptedAndEarlyDoesNotConsumeRound() throws {
        var item = try make(rounds: 1, goal: 120); accepted(&item, start: 0, ms: 119)
        XCTAssertEqual(item.phase, .early); XCTAssertEqual(item.earlyReason, .belowHumanMinimum); XCTAssertEqual(item.round, 1)
        accepted(&item, start: 2000, ms: 120); XCTAssertEqual(item.times, [120]); XCTAssertEqual(item.matched, true)
    }
    func testUnlimitedEarlyRetriesRetainPriorAcceptedReading() throws {
        var item = try make(rounds: 2); accepted(&item, start: 0, ms: 300)
        for i in 1...20 { let now = Double(i) * 2000; item.arm(at: now, delayUnit: 0); item.tap(at: now + 1) }
        XCTAssertEqual(item.times, [300]); XCTAssertEqual(item.round, 2)
        accepted(&item, start: 42000, ms: 250); XCTAssertEqual(item.times, [300, 250]); XCTAssertEqual(item.matched, true)
    }
    func testConfiguredOneThreeAndTenRoundsTakeBestOnlyWhenFinished() throws {
        for count in [1, 3, 10] {
            var item = try make(rounds: count)
            for index in 0..<count { accepted(&item, start: Double(index) * 3000, ms: index == 0 ? 320 : 700)
                XCTAssertEqual(item.matched, index == count - 1 ? true : nil)
            }
            XCTAssertEqual(item.times.count, count); XCTAssertEqual(item.bestMs, 320); XCTAssertEqual(item.phase, .finished)
        }
    }
    func testGoalIsInclusiveAndSlowerMissesLocally() throws {
        var item = try make(rounds: 1); accepted(&item, start: 0, ms: 320); XCTAssertEqual(item.matched, true)
        item.reset(); accepted(&item, start: 0, ms: 321); XCTAssertEqual(item.matched, false)
    }
    func testDoneIgnoresTapSignalAndArmUntilReset() throws {
        var item = try make(rounds: 1); accepted(&item, start: 0, ms: 200); let before = item
        item.tap(at: 2000); item.signal(at: 3000); item.arm(at: 4000, delayUnit: 1); XCTAssertEqual(item, before)
        item.reset(); XCTAssertEqual(item.phase, .idle); XCTAssertTrue(item.times.isEmpty); XCTAssertNil(item.bestMs); XCTAssertNil(item.matched)
    }
    func testBackwardNonfiniteAndInvalidDelayAbortWithoutReading() throws {
        for value in [-1, Double.nan, Double.infinity] { var item = try make(); item.arm(at: value, delayUnit: 0); XCTAssertEqual(item.phase, .aborted) }
        var item = try make(); item.arm(at: 100, delayUnit: 0); item.signal(at: 99); XCTAssertEqual(item.phase, .aborted); XCTAssertTrue(item.times.isEmpty)
        item.reset(); item.arm(at: 0, delayUnit: Double.nan); XCTAssertEqual(item.phase, .aborted)
    }
    func testClockRollbackAfterSignalRequiresResetAndPreservesConfig() throws {
        var item = try make(), original = item.draft; item.arm(at: 0, delayUnit: 0); item.signal(at: 1400); item.tap(at: 1399)
        XCTAssertEqual(item.phase, .aborted); XCTAssertFalse(item.canTap); item.arm(at: 2000, delayUnit: 0); XCTAssertEqual(item.phase, .aborted)
        item.reset(); item.arm(at: 0, delayUnit: 0); XCTAssertEqual(item.phase, .waiting); XCTAssertEqual(item.draft, original)
    }
    func testMaximumGoalAndNoReadingBeforeAllRounds() throws {
        var item = try make(rounds: 2, goal: 2000); accepted(&item, start: 0, ms: 2000)
        XCTAssertNil(item.matched); accepted(&item, start: 4000, ms: 2100); XCTAssertEqual(item.matched, true); XCTAssertEqual(item.bestMs, 2000)
    }
}
