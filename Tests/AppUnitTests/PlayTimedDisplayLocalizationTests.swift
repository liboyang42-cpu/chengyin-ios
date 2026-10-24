import Foundation
import XCTest
@testable import Questify

@MainActor final class PlayTimedDisplayLocalizationTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let chinese = Locale(identifier: "zh-Hans_CN")

    func testEnglishTargetsAndResultsKeepHundredthsAndSeconds() {
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(10, locale: english), "10.00 s")
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(0.25, locale: english), "0.25 s")
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(60, locale: english), "60.00 s")
    }

    func testChineseTargetsAndResultsUseTranslatedSeconds() {
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(10, locale: chinese), "10.00 秒")
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(0.25, locale: chinese), "0.25 秒")
    }

    func testCountdownAndTypeInRemainingTimeKeepTenths() {
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(9.75, precision: .tenths, locale: english), "9.8 s")
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(9.75, precision: .tenths, locale: chinese), "9.8 秒")
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(0, precision: .tenths, locale: chinese), "0.0 秒")
    }

    func testExplicitLocaleControlsDecimalSeparator() {
        XCTAssertEqual(PlayTimedDisplayLocalization.number(12.25, locale: Locale(identifier: "de_DE")), "12,25")
        XCTAssertEqual(PlayTimedDisplayLocalization.number(12.25, locale: english), "12.25")
        XCTAssertEqual(PlayTimedDisplayLocalization.number(12.25, precision: .tenths, locale: Locale(identifier: "de_DE")), "12,2")
    }

    func testMillisecondsAndToleranceHaveNoDecimalRounding() {
        XCTAssertEqual(PlayTimedDisplayLocalization.milliseconds(250, locale: english), "250 ms")
        XCTAssertEqual(PlayTimedDisplayLocalization.milliseconds(250, locale: chinese), "250 毫秒")
        XCTAssertEqual(PlayTimedDisplayLocalization.tolerance(50, locale: english), "±50 ms")
        XCTAssertEqual(PlayTimedDisplayLocalization.tolerance(50, locale: chinese), "±50 毫秒")
    }

    func testCountersAndReactionRoundsUseSelectedLocale() {
        XCTAssertEqual(PlayTimedDisplayLocalization.count(1234, locale: english), "1,234")
        XCTAssertEqual(PlayTimedDisplayLocalization.count(1234, locale: Locale(identifier: "de_DE")), "1.234")
        XCTAssertEqual(PlayTimedDisplayLocalization.round(current: 0, total: 3, locale: chinese), "0 / 3")
        XCTAssertEqual(PlayTimedDisplayLocalization.round(current: 3, total: 3, locale: english), "3 / 3")
    }

    func testLocaleSwitchDoesNotCacheThePreviousLanguage() {
        for _ in 0..<3 {
            XCTAssertEqual(PlayTimedDisplayLocalization.seconds(2.5, locale: chinese), "2.50 秒")
            XCTAssertEqual(PlayTimedDisplayLocalization.seconds(2.5, locale: english), "2.50 s")
            XCTAssertEqual(PlayTimedDisplayLocalization.milliseconds(125, locale: chinese), "125 毫秒")
            XCTAssertEqual(PlayTimedDisplayLocalization.milliseconds(125, locale: english), "125 ms")
        }
    }

    func testNonfiniteValuesDoNotBecomeAValidDisplayedTime() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(PlayTimedDisplayLocalization.number(value, locale: english), "—")
            XCTAssertEqual(PlayTimedDisplayLocalization.seconds(value, locale: chinese), "—")
        }
    }

    func testZeroAndSignedFiniteValuesAreNotClampedByDisplay() {
        XCTAssertEqual(PlayTimedDisplayLocalization.number(0, locale: english), "0.00")
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(-1.25, locale: english), "-1.25 s")
        XCTAssertEqual(PlayTimedDisplayLocalization.milliseconds(-125, locale: chinese), "-125 毫秒")
    }

    func testNeverAndDelayedStopwatchVisibilityRemainMachineOwned() throws {
        var hidden = PlayStopwatchMachine(reveal: .never)
        hidden.begin(now: 100)
        XCTAssertNil(hidden.visibleElapsed(now: 100.5))
        var delayed = PlayStopwatchMachine(reveal: .delay)
        delayed.begin(now: 100)
        let visible = try XCTUnwrap(delayed.visibleElapsed(now: 100.5))
        XCTAssertEqual(PlayTimedDisplayLocalization.number(visible, locale: chinese), "0.50")
        XCTAssertNil(delayed.visibleElapsed(now: 101))
        XCTAssertNil(delayed.visibleElapsed(now: 105))
        XCTAssertEqual(delayed.phase, .running)
    }

    func testDisplayingVerdictDoesNotChangeRoundsStarsOrBest() throws {
        var machine = PlayStopwatchMachine(target: 10, reveal: .always)
        machine.begin(now: 100)
        machine.stop(now: 110.25)
        let before = machine
        let result = try XCTUnwrap(machine.result)
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(result.difference, locale: chinese), "0.25 秒")
        XCTAssertEqual(PlayTimedDisplayLocalization.count(result.stars, locale: english), "1")
        XCTAssertEqual(PlayTimedDisplayLocalization.count(machine.rounds, locale: english), "1")
        XCTAssertEqual(machine, before)
        XCTAssertEqual(machine.bestDifference, 0.25)
    }

    func testFormattingMeasuredTimePreservesIntegerSubmissionEvidence() {
        var timing = PlayKitTimingRun()
        XCTAssertEqual(timing.phase, .idle)
        timing.beginAfterAcknowledgement(now: 100)
        timing.measure(now: 101.25)
        let before = timing
        XCTAssertEqual(timing.elapsedMilliseconds, 1250)
        XCTAssertEqual(PlayTimedDisplayLocalization.seconds(Double(timing.elapsedMilliseconds) / 1000, locale: chinese), "1.25 秒")
        XCTAssertEqual(timing, before)
        XCTAssertEqual(timing.elapsedMilliseconds, 1250)
        XCTAssertEqual(timing.phase, .measured)
    }

    func testReactionDisplayPreservesMeasuredRoundsAndInterruptionRules() {
        var reaction = PlayKitReactionRun(rounds: 1)
        reaction.beginAfterAcknowledgement(now: 100, randomUnit: 0)
        reaction.tick(now: 102)
        reaction.tap(now: 102.25)
        let before = reaction
        XCTAssertEqual(reaction.roundsMilliseconds, [250])
        XCTAssertEqual(PlayTimedDisplayLocalization.milliseconds(reaction.roundsMilliseconds[0], locale: chinese), "250 毫秒")
        XCTAssertEqual(reaction, before)
        XCTAssertEqual(reaction.phase, .measured)
        reaction.interrupt()
        XCTAssertEqual(reaction, before)
    }
}
