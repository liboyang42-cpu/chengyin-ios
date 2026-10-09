"""Portable live-source contracts for UI49 and UI78's sealed driver changes.

Only the two owned files and the exact shared helper dependency are checked.
Workspace-wide isolation history is not reinterpreted as a combined-repo gate.
"""
import collections
import math
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

from tools import remaining_editor_drivers_inverse as repair


ROOT = Path(__file__).resolve().parents[2]
AUDIO = 'Tests/AppUITests/ProjectStoryAudioRecoveryFlowTests.swift'
PERSISTENCE = 'Tests/AppUITests/ApprovedTopicReviewPersistenceFlowTests.swift'


def assertions(text):
    result = []
    for match in re.finditer(r'\bXCTAssert\w*\(', text):
        depth = 1
        index = match.end()
        quote = False
        escaped = False
        while depth:
            character = text[index]
            if quote:
                if escaped:
                    escaped = False
                elif character == '\\':
                    escaped = True
                elif character == '"':
                    quote = False
            elif character == '"':
                quote = True
            elif character == '(':
                depth += 1
            elif character == ')':
                depth -= 1
            index += 1
        result.append(text[match.start():index])
    return collections.Counter(result)


class RemainingEditorDriverTests(unittest.TestCase):
    def source_bytes(self, path):
        after = (ROOT / path).read_bytes()
        return repair.inverse(path, after), after

    def sources(self, path):
        return tuple(raw.decode('utf-8') for raw in self.source_bytes(path))

    def test_contract_owns_exactly_two_live_files(self):
        rows = repair.contract()['changes']
        self.assertEqual(repair.ROOT, ROOT)
        self.assertEqual(len(rows), 2)
        self.assertEqual({row['path'] for row in rows}, {AUDIO, PERSISTENCE})
        for row in rows:
            self.assertTrue((ROOT / row['path']).is_file(), row['path'])

    def test_exact_round_trip_to_sealed_current275_inventory(self):
        c = repair.contract()
        for row in c['changes']:
            path = row['path']
            with self.subTest(path=path):
                before, after = self.source_bytes(path)
                self.assertEqual(repair.digest(before), row['before_sha256'])
                self.assertEqual(repair.digest(after), row['after_sha256'])
                self.assertEqual(repair.digest(before), c['baseline_ui_sources'][Path(path).name])
                self.assertEqual(repair.forward(path, before), after)
                self.assertEqual(repair.inverse(path, after), before)
                for hunk in row['hunks']:
                    self.assertEqual(before.count(hunk['before'].encode()), 1)
                    self.assertEqual(after.count(hunk['after'].encode()), 1)

    def test_unknown_bytes_are_rejected(self):
        for row in repair.contract()['changes']:
            path = row['path']
            before, after = self.source_bytes(path)
            mutations = {
                'old-source': before,
                'newline': after + b'\n',
                'timeout': after.replace(b'timeout: 5', b'timeout: 50', 1),
                'crlf': after.replace(b'\n', b'\r\n'),
                'weakened-assertion': after.replace(b'XCTAssertTrue', b'XCTAssertFalse', 1),
                'changed-bound': re.sub(rb'maximumSwipes: \d+', b'maximumSwipes: 99', after, count=1),
                'changed-probe': after.replace(b'projectStarter.fixtureSnapshot', b'projectStarter.otherProbe', 1),
            }
            for number, hunk in enumerate(row['hunks']):
                replacement = hunk['after'].encode()
                mutations[f'missing-hunk-{number}'] = after.replace(replacement, b'', 1)
                mutations[f'duplicate-hunk-{number}'] = after.replace(replacement, replacement + replacement, 1)
                mutations[f'reverted-hunk-{number}'] = after.replace(replacement, hunk['before'].encode(), 1)
            for mode, unknown in mutations.items():
                with self.subTest(path=path, mode=mode):
                    self.assertNotEqual(unknown, after)
                    with self.assertRaises(ValueError):
                        repair.inverse(path, unknown)
            for unknown in (after, before + b'\n', before.replace(b'\n', b'\r\n')):
                with self.subTest(path=path, direction='forward'), self.assertRaises(ValueError):
                    repair.forward(path, unknown)

    def test_unknown_path_is_rejected_in_both_directions(self):
        for transform in (repair.inverse, repair.forward):
            with self.subTest(transform=transform.__name__), self.assertRaises(ValueError):
                transform('Tests/AppUITests/Unknown.swift', b'')

    def test_changed_contract_rejected(self):
        # An explicit TMPDIR must work; never silently fall back if it is invalid.
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            (root / 'tools/remaining_editor_drivers_contract.json').write_bytes(
                (ROOT / 'tools/remaining_editor_drivers_contract.json').read_bytes() + b'\n')
            with patch.object(repair, 'ROOT', root), self.assertRaises(ValueError):
                repair.contract()

    def test_every_original_assertion_is_retained(self):
        for path in (AUDIO, PERSISTENCE):
            before, after = self.sources(path)
            with self.subTest(path=path):
                delta = assertions(after) - assertions(before)
                self.assertEqual(assertions(before) - assertions(after), {})
                if path == AUDIO:
                    self.assertEqual(delta, {'XCTAssertTrue(revealProjectEditorNameInForm(in: app), app.debugDescription)': 2})
                else:
                    self.assertEqual(delta, {})

    def test_both_audio_launches_reveal_before_the_same_name_wait(self):
        before, after = self.sources(AUDIO)
        line = 'XCTAssertTrue(revealProjectEditorNameInForm(in: app), app.debugDescription)'
        wait = 'XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))'
        self.assertEqual(after.count(line), 2)
        self.assertEqual(after.count('app.launch()'), 2)
        self.assertEqual(after.count('app.launch()'), before.count('app.launch()'))
        self.assertEqual(after.count('assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")'), 2)
        self.assertEqual(after.count(line + '\n        ' + wait), 2)
        self.assertEqual(after.replace(line + '\n        ', ''), before)
        self.assertEqual(re.findall(r'timeout: \d+', before), re.findall(r'timeout: \d+', after))
        self.assertEqual(re.findall(r'maximumSwipes: \d+', before), re.findall(r'maximumSwipes: \d+', after))

    def test_audio_probe_and_upload_counters_are_unchanged(self):
        before, after = self.sources(AUDIO)
        marker = '    // UNMEASURED complete-method estimate:'
        self.assertEqual(before[:before.index(marker)], after[:after.index(marker)])
        for counter in ('storyAudioUploadCount', 'submissionCount'):
            self.assertEqual([line for line in before.splitlines() if counter in line],
                             [line for line in after.splitlines() if counter in line])
        self.assertIn('XCTAssertEqual(try snapshot(app)["storyAudioUploadCount"] as? Int, 1)', after)
        self.assertIn('XCTAssertNil(saved["storyAudioUploadCount"])', after)

    def test_persistence_reorders_only_existing_reveal_and_wait(self):
        before, after = self.sources(PERSISTENCE)
        prefix = '    private func tap('
        suffix = '    private struct Probe:'
        self.assertEqual(before[:before.index(prefix)], after[:after.index(prefix)])
        self.assertEqual(before[before.index(suffix):], after[after.index(suffix):])
        for name, end in [('tap', '    @discardableResult'), ('value', '    private struct Probe:')]:
            marker = 'private func ' + name + '('
            old = before[before.index(marker):before.index(end)]
            new = after[after.index(marker):after.index(end)]
            with self.subTest(helper=name):
                self.assertLess(old.index('waitForExistence'), old.index('revealFixtureElement'))
                self.assertLess(new.index('revealFixtureElement'), new.index('waitForExistence'))
                self.assertEqual(re.findall(r'timeout: (\d+)', new), ['5'])
                self.assertEqual(re.findall(r'maximumSwipes: (\d+)', new), ['70'])
                self.assertEqual(re.findall(r'timeout: \d+', old), re.findall(r'timeout: \d+', new))
                self.assertEqual(re.findall(r'maximumSwipes: \d+', old), re.findall(r'maximumSwipes: \d+', new))
                self.assertEqual(new.count('waitForExistence('), 1)
                self.assertEqual(new.count('revealFixtureElement('), 1)
        self.assertEqual(before.count('revealFixtureElement('), after.count('revealFixtureElement('))
        self.assertEqual(before.count('target.tap()'), after.count('target.tap()'))
        self.assertIn('if !fixed { XCTAssertTrue(revealFixtureElement(', after)
        self.assertIn('requiresHittable: false', after)

    def test_live_name_helper_retains_the_sealed_bound_and_geometry(self):
        c = repair.contract()
        helper = c['helper']
        raw = (ROOT / helper['path']).read_bytes()
        self.assertEqual(repair.digest(raw), helper['sha256'])
        self.assertEqual(helper['sha256'], c['protected_files'][helper['path']])
        source = raw.decode('utf-8')
        start = source.index('func ' + helper['function'] + '(')
        body = source[start:source.index('\n}\n', start) + 3]
        self.assertIn('for attempt in 0...10 {', body)
        self.assertIn('guard attempt < 10 else { return false }', body)
        self.assertIn('viewport.contains(frame), name.isHittable', body)
        self.assertIn('navigation.frame.maxY + 8', body)
        self.assertIn('min(save.frame.minY, review.frame.minY) - 24', body)
        self.assertIn('if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 4) }', body)
        self.assertEqual(body.count('.press(forDuration: 0.05,'), 1)
        for unexpected in ('waitForExistence(', 'sleep(', '.tap()', 'app.launch()'):
            self.assertNotIn(unexpected, body)
        self.assertEqual(c['cost']['maximum_gestures_per_call'], 10)
        self.assertEqual(c['cost']['maximum_viewport_evaluations_per_call'], 11)

    def test_complete_method_costs_include_both_new_reveal_calls(self):
        c = repair.contract()['cost']
        _, audio = self.sources(AUDIO)
        per_call = c['maximum_viewport_evaluations_per_call'] * (c['query_phase_seconds_assumption'] + c['gesture_and_settle_seconds_assumption']) + c['initial_ax_lookups_per_call'] * c['initial_ax_lookup_seconds_assumption']
        self.assertEqual(per_call, 37)
        self.assertEqual(c['unrounded_seconds_per_call'], per_call)
        self.assertEqual(c['rounding_quantum_seconds'], 10)
        self.assertEqual(math.ceil(per_call / c['rounding_quantum_seconds']) * c['rounding_quantum_seconds'], c['added_seconds_per_call'])
        self.assertEqual(c['added_seconds_per_call'], 40)
        self.assertEqual(c['audio_added_calls'], audio.count('revealProjectEditorNameInForm(in: app)'))
        self.assertEqual(c['audio_added_calls'] * c['added_seconds_per_call'], 80)
        self.assertEqual(c['audio_added_seconds'], 80)
        self.assertEqual(c['audio_prior_complete_method_seconds'], 900)
        self.assertEqual(c['audio_candidate_complete_method_seconds'], 980)
        self.assertEqual(c['audio_candidate_complete_method_seconds'], c['audio_prior_complete_method_seconds'] + c['audio_added_seconds'])
        self.assertEqual(c['persistence_added_seconds'], 0)
        self.assertEqual(c['persistence_wait_seconds'], 5)
        self.assertEqual(c['persistence_maximum_swipes'], 70)
        self.assertFalse(c['measured'])
        self.assertTrue(c['no_historical_floor_reduction'])

    def test_ui55_is_not_claimed_as_fixed_by_this_package(self):
        self.assertEqual(repair.contract()['ui55_status'],
                         'BLOCKED_ON_PRE_TAP_GEOMETRY_AND_FOREGROUND_ARRIVAL_EVIDENCE_NO_FIX_CLAIM')


if __name__ == '__main__':
    unittest.main(verbosity=2)
