"""Bounded source contracts; native locale behavior is separately authored in XCTest."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class PlayTimedDisplayLocalizationChecks(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_explicit_locale_precision_and_units(self):
        source = self.read('App/PlayTimedDisplayLocalization.swift')
        for token in ['precision == .tenths ? "%.1f" : "%.2f", locale: locale',
                      'value.formatted(.number.locale(locale))',
                      'table: "PlayTimedDisplayLocalization", locale: locale',
                      'guard value.isFinite else { return "—" }',
                      '"±" + milliseconds(value, locale: locale)']:
            self.assertIn(token, source)
        self.assertNotIn('Locale.current', source)
        for token in ['URLSession', 'requestReview', 'ProcessInfo', 'Date()', 'UserDefaults']:
            self.assertNotIn(token, source)

    def test_bilingual_catalog_is_exact_and_translated(self):
        strings = json.loads(self.read('Resources/PlayTimedDisplayLocalization.xcstrings'))['strings']
        self.assertEqual(set(strings), {'seconds', 'milliseconds'})
        for key, en, zh in [('seconds', 's', '秒'), ('milliseconds', 'ms', '毫秒')]:
            for language, value in [('en', en), ('zh-Hans', zh)]:
                self.assertEqual(strings[key]['localizations'][language]['stringUnit'],
                                 {'state': 'translated', 'value': value})

    def test_standalone_stopwatch_entire_display_and_hidden_guard(self):
        source = self.read('App/PlayDeviceTaskViews.swift').split('struct PlayStopwatchView:', 1)[1]
        for token in ['@Environment(\\.locale) private var locale',
                      'seconds(machine.target, locale: locale)',
                      'machine.visibleElapsed(now:',
                      'number($0, locale: locale)', '?? "—.—"',
                      'count(result.stars, locale: locale)',
                      'seconds(result.difference, locale: locale)',
                      'count(machine.rounds, locale: locale)',
                      'seconds(best, locale: locale)']:
            self.assertIn(token, source)
        self.assertNotIn('String(format:', source)
        self.assertIn('PlayStopwatchView()', self.read('App/PlayExperienceView.swift'))

    def test_four_ack_gated_timed_screens_use_display_formatter(self):
        source = self.read('App/PlayKitTimedChallengeView.swift')
        for token in ['@Environment(\\.locale) private var locale',
                      'seconds(seconds, locale: locale)', 'tolerance(tolerance, locale: locale)',
                      'count(attempts, locale: locale)', 'count(cap, locale: locale)',
                      'seconds(Double(elapsed) / 1000, locale: locale)',
                      'precision: .tenths, locale: locale)',
                      'round(current: reaction.roundsMilliseconds.count, total: reaction.rounds, locale: locale)',
                      'milliseconds(goal, locale: locale)', 'count(index + 1, locale: locale)',
                      'milliseconds(ms, locale: locale)']:
            self.assertIn(token, source)
        self.assertNotIn('String(format:', source)
        self.assertIn('PlayKitTimedChallengeView(', self.read('App/PlayKitScreen.swift'))

    def test_hidden_clock_ack_payload_and_lifetime_remain_separate(self):
        source = self.read('App/PlayKitTimedChallengeView.swift')
        for token in ['if kind == .stopwatch && timing.phase == .running && elapsed >= 1000 { return "—.—" }',
                      'kind == .stopwatch && running && elapsed >= 1000 ? "playkit.stopwatch.hidden"',
                      'requestReview("START_CHALLENGE", ["game": .string(kind.rawValue)])',
                      'guard mounted, active, scenePhase == .active else { return }',
                      'timing.beginAfterAcknowledgement(now:',
                      'case .countdown: requestReview("SUBMIT_COUNTDOWN", [:], {})',
                      '["stoppedMs": .int(timing.elapsedMilliseconds)]',
                      '["text": .string(input), "elapsedMs": .int(timing.elapsedMilliseconds)]',
                      '["times": .array(reaction.roundsMilliseconds.map(PlayWireValue.int))]',
                      '.onDisappear { mounted = false; interrupt() }']:
            self.assertIn(token, source)
        tail = source.split('private func start()', 1)[1]
        self.assertNotIn('PlayTimedDisplayLocalization', tail)

    def test_authored_native_boundaries_remain_present(self):
        source = self.read('Tests/AppUnitTests/PlayTimedDisplayLocalizationTests.swift')
        for token in ['Locale(identifier: "en_US")', 'Locale(identifier: "zh-Hans_CN")',
                      'Locale(identifier: "de_DE")', 'Double.nan',
                      'XCTAssertNil(delayed.visibleElapsed(now: 101))',
                      'XCTAssertEqual(timing.elapsedMilliseconds, 1250)',
                      'XCTAssertEqual(machine, before)', 'XCTAssertEqual(reaction, before)']:
            self.assertIn(token, source)

if __name__ == '__main__':
    unittest.main()
