import XCTest
@testable import QuestifyCore

final class TemplateTimerRehearsalTests: XCTestCase {
    private func make(_ kind: TemplateTimerRehearsal.Kind = .stopwatch, seconds: Double = 10, tries: Int = 3, tolerance: Double = 250) throws -> TemplateTimerRehearsal {
        var draft = TemplateAdvancedDraft()
        draft.set(kind.rawValue, kind == .countdown ? "seconds" : "targetSeconds", .number(seconds))
        draft.set("countdown", "doneText", .string("My done")); draft.set("stopwatch", "tries", .number(Double(tries)))
        draft.set("stopwatch", "toleranceMs", .number(tolerance))
        return try XCTUnwrap(TemplateTimerRehearsal(draft, kind: kind, mode: .currentConfiguration))
    }
    func testCurrentConfigurationReadsValuesWithoutEnablingOrWriting() throws {
        let item = try make(); XCTAssertEqual(item.targetSeconds, 10); XCTAssertEqual(item.toleranceMs, 250); XCTAssertEqual(item.tries, 3)
        XCTAssertFalse(item.draft.enabled("stopwatch")); XCTAssertTrue(item.filledFields.isEmpty)
    }
    func testSourceExamplesMatchRealSourceAndKeepOriginalExact() throws {
        let original = TemplateAdvancedDraft(), before = original
        let countdown = try XCTUnwrap(TemplateTimerRehearsal(original, kind: .countdown, mode: .sourceExample))
        XCTAssertEqual(countdown.kicker, "一钟油"); XCTAssertEqual(countdown.doneText, "时间到。"); XCTAssertEqual(countdown.filledFields, ["doneText", "kicker"])
        let stopwatch = try XCTUnwrap(TemplateTimerRehearsal(original, kind: .stopwatch, mode: .sourceExample))
        XCTAssertEqual(stopwatch.kicker, "盲停在 10 秒"); XCTAssertEqual(stopwatch.filledFields, ["kicker"]); XCTAssertEqual(original, before)
    }
    func testCustomTextAndMissingRequiredFieldsAreNeverInvented() throws {
        var draft = TemplateAdvancedDraft(); draft.set("countdown", "doneText", .string("  Custom done  "))
        let item = try XCTUnwrap(TemplateTimerRehearsal(draft, kind: .countdown, mode: .sourceExample))
        XCTAssertEqual(item.doneText, "Custom done"); XCTAssertEqual(item.draft.text("countdown", "doneText"), "  Custom done  ")
        var fields = try XCTUnwrap(draft.value["countdown"]?.object); fields.removeValue(forKey: "seconds"); draft.value["countdown"] = .object(fields)
        XCTAssertNil(TemplateTimerRehearsal(draft, kind: .countdown, mode: .sourceExample))
    }
    func testInvalidRangesFractionalTriesAndEmptyCurrentDoneFailClosed() {
        let original = TemplateAdvancedDraft(); XCTAssertNil(TemplateTimerRehearsal(original, kind: .countdown, mode: .currentConfiguration))
        for (key, value) in [("targetSeconds", 2.0), ("toleranceMs", 5001.0), ("tries", 1.5), ("targetSeconds", Double.nan)] {
            var draft = original; draft.set("stopwatch", key, .number(value)); XCTAssertNil(TemplateTimerRehearsal(draft, kind: .stopwatch, mode: .currentConfiguration))
        }
    }
    func testCountdownUsesAbsoluteElapsedTimeAndDelayedTickFinishes() throws {
        var item = try make(.countdown, seconds: 5); item.start(at: 1000); item.tick(at: 4600)
        XCTAssertEqual(item.elapsedMs, 3600); XCTAssertEqual(item.remainingSeconds, 2)
        item.tick(at: 9000); XCTAssertEqual(item.phase, .finished); XCTAssertEqual(item.elapsedMs, 5000); XCTAssertEqual(item.progress, 1)
    }
    func testCountdownCeilingKeepsFractionalLastSecondVisible() throws {
        var item = try make(.countdown, seconds: 5); item.start(at: 0); item.tick(at: 4600)
        XCTAssertEqual(item.remainingSeconds, 1); XCTAssertEqual(item.phase, .running)
        item.tick(at: 4999); XCTAssertEqual(item.remainingSeconds, 1); item.tick(at: 5000); XCTAssertEqual(item.remainingSeconds, 0)
    }
    func testCountdownCannotPauseOrStop() throws {
        var item = try make(.countdown, seconds: 5); item.start(at: 0); item.pause(at: 1000); item.stop(at: 2000)
        XCTAssertEqual(item.phase, .running); XCTAssertFalse(item.canPauseResume); XCTAssertFalse(item.canStop); XCTAssertNil(item.result)
    }
    func testCountdownRestartAndResetPreserveCompletionCopy() throws {
        var item = try make(.countdown, seconds: 5); item.start(at: 0); item.tick(at: 5000); XCTAssertTrue(item.canStart)
        item.start(at: 6000); XCTAssertEqual(item.remainingSeconds, 5); item.reset(); XCTAssertEqual(item.phase, .ready); XCTAssertEqual(item.doneText, "My done")
    }
    func testStopwatchHidesAtExactlyOneSecond() throws {
        var item = try make(); item.start(at: 0); item.tick(at: 999); XCTAssertFalse(item.isMasked)
        item.tick(at: 1000); XCTAssertTrue(item.isMasked); item.pause(at: 1200); XCTAssertTrue(item.isMasked)
    }
    func testPauseResumeExcludesPausedDuration() throws {
        var item = try make(); item.start(at: 1000); item.pause(at: 2000); item.tick(at: 20000)
        XCTAssertEqual(item.elapsedMs, 1000); item.resume(at: 21000); item.tick(at: 22000); XCTAssertEqual(item.elapsedMs, 2000)
    }
    func testPausedStopIsIgnoredAndDoesNotConsumeTry() throws {
        var item = try make(); item.start(at: 0); item.pause(at: 1000); item.stop(at: 10000)
        XCTAssertEqual(item.phase, .paused); XCTAssertNil(item.result); XCTAssertEqual(item.misses, 0)
    }
    func testToleranceBoundaryUsesSourceInclusiveComparison() throws {
        var item = try make(tolerance: 250); item.start(at: 0); item.stop(at: 10250)
        XCTAssertEqual(item.result?.matched, true); XCTAssertEqual(item.result?.tier, .withinTolerance); XCTAssertEqual(item.result?.timing, .late)
    }
    func testExcellentTierCannotExceedHalfSmallTolerance() throws {
        var item = try make(tolerance: 50); item.start(at: 0); item.stop(at: 10020); XCTAssertEqual(item.result?.tier, .excellent)
        item.reset(); item.start(at: 0); item.stop(at: 10040); XCTAssertEqual(item.result?.tier, .withinTolerance)
    }
    func testDeviationWordingDistinguishesExactEarlyAndLate() throws {
        var item = try make(); item.start(at: 0); item.stop(at: 10004); XCTAssertEqual(item.result?.timing, .exact)
        item.reset(); item.start(at: 0); item.stop(at: 9900); XCTAssertEqual(item.result?.timing, .early)
        item.reset(); item.start(at: 0); item.stop(at: 10200); XCTAssertEqual(item.result?.timing, .late)
    }
    func testMissAllowanceBlocksRetryUntilExplicitReset() throws {
        var item = try make(tries: 2); item.start(at: 0); item.stop(at: 1000); XCTAssertEqual(item.triesRemaining, 1); XCTAssertTrue(item.canStart)
        item.start(at: 2000); XCTAssertEqual(item.round, 2); item.stop(at: 3000); XCTAssertEqual(item.triesRemaining, 0); XCTAssertFalse(item.canStart)
        item.reset(); XCTAssertEqual(item.triesRemaining, 2); XCTAssertTrue(item.canStart)
    }
    func testUnlimitedMissesStayRetryableButMatchedResultNeedsReset() throws {
        var item = try make(tries: 0)
        for base in [0.0, 2000.0, 4000.0] { item.start(at: base); item.stop(at: base + 1000); XCTAssertNil(item.triesRemaining); XCTAssertTrue(item.canStart) }
        item.start(at: 6000); item.stop(at: 16000); XCTAssertFalse(item.canStart); XCTAssertEqual(item.result?.matched, true)
    }
    func testTimeoutAbortsOnlyBeyondTargetPlusThirtySecondsWithoutMiss() throws {
        var item = try make(); item.start(at: 0); item.tick(at: 40000); XCTAssertEqual(item.phase, .running)
        item.tick(at: 40001); XCTAssertEqual(item.phase, .aborted); XCTAssertEqual(item.abortReason, .timeout); XCTAssertEqual(item.misses, 0); XCTAssertTrue(item.canStart)
    }
    func testNonfiniteAndBackwardClocksFailClosed() throws {
        var item = try make(); item.start(at: .nan); XCTAssertEqual(item.abortReason, .clock)
        item.reset(); item.start(at: 1000); item.tick(at: 1500); item.tick(at: 1499); XCTAssertEqual(item.abortReason, .clock)
        item.reset(); item.start(at: 1000); item.pause(at: 2000); item.resume(at: 1999); XCTAssertEqual(item.abortReason, .clock)
    }
    func testTicksOutsideRunningNeverAlterResetOrStoppedResult() throws {
        var item = try make(); item.start(at: 0); item.reset(); item.tick(at: 90000); XCTAssertEqual(item.phase, .ready); XCTAssertEqual(item.elapsedMs, 0)
        item.start(at: 0); item.stop(at: 10000); let result = item.result; item.tick(at: 90000); XCTAssertEqual(item.result, result)
    }
    func testUnknownSiblingsAndNumericStringsRemainRaw() throws {
        var draft = TemplateAdvancedDraft(); draft.set("stopwatch", "targetSeconds", .string("12.5")); draft.value["future"] = .object(["opaque": .bool(true)])
        let item = try XCTUnwrap(TemplateTimerRehearsal(draft, kind: .stopwatch, mode: .sourceExample))
        XCTAssertEqual(item.targetSeconds, 12.5); XCTAssertEqual(item.draft.value["future"], draft.value["future"]); XCTAssertEqual(item.draft.value["stopwatch"]?.object?["targetSeconds"], .string("12.5"))
    }
}
