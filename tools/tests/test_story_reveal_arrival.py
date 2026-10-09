"""Portable live-source checks for the sealed two-helper story repair.

Historical bytes are recovered from the checked-in source by the exact inverse.
The isolated package's workspace-wide immutability check remains historical
evidence; it is not a claim about the subsequently combined repository.
"""
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

from tools import story_reveal_arrival_inverse as repair


ROOT = Path(__file__).resolve().parents[2]
MEDIA = 'Tests/AppUITests/ProjectStoryMediaGapFlowSupport.swift'
TEMPLATE = 'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift'


class StoryRepairTests(unittest.TestCase):
    def source_bytes(self, path):
        after = (ROOT / path).read_bytes()
        return repair.inverse(path, after), after

    def sources(self, path):
        return tuple(raw.decode('utf-8') for raw in self.source_bytes(path))

    def test_changed_contract_is_rejected(self):
        # An explicit TMPDIR must work; never silently fall back if it is invalid.
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            original = (ROOT / 'tools/story_reveal_arrival_contract.json').read_bytes()
            (root / 'tools/story_reveal_arrival_contract.json').write_bytes(original + b'\n')
            with patch.object(repair, 'ROOT', root), self.assertRaises(ValueError):
                repair.contract()

    def test_contract_owns_exactly_two_live_helpers(self):
        rows = repair.contract()['changes']
        self.assertEqual(repair.ROOT, ROOT)
        self.assertEqual(len(rows), 2)
        self.assertEqual({row['path'] for row in rows}, {MEDIA, TEMPLATE})
        for row in rows:
            self.assertTrue((ROOT / row['path']).is_file(), row['path'])

    def test_round_trip_retains_exact_current275_sources(self):
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
                self.assertEqual(after.count(row['replace_after'].encode()), 1)
                self.assertEqual(before.count(row['replace_before'].encode()), 1)

    def test_unknown_bytes_are_rejected(self):
        for row in repair.contract()['changes']:
            path = row['path']
            before, after = self.source_bytes(path)
            replacement = row['replace_after'].encode()
            mutations = {
                'old-source': before,
                'newline': after + b'\n',
                'timeout': after.replace(b'timeout: 5', b'timeout: 50', 1),
                'crlf': after.replace(b'\n', b'\r\n'),
                'missing-repair': after.replace(replacement, b'', 1),
                'duplicate-repair': after.replace(replacement, replacement + b'\n' + replacement, 1),
                'weakened-assertion': after.replace(b'XCTAssertTrue', b'XCTAssertFalse', 1),
                'changed-probe': after.replace(b'projectStarter.fixtureSnapshot', b'projectStarter.otherProbe', 1),
                'changed-counter': after.replace(b'submissionCount, 0', b'submissionCount, 1', 1),
            }
            for mode, mutated in mutations.items():
                with self.subTest(path=path, mode=mode):
                    self.assertNotEqual(mutated, after)
                    with self.assertRaises(ValueError):
                        repair.inverse(path, mutated)
            for mutated in (after, before + b'\n', before.replace(b'\n', b'\r\n')):
                with self.subTest(path=path, direction='forward'), self.assertRaises(ValueError):
                    repair.forward(path, mutated)

    def test_unknown_path_is_rejected_in_both_directions(self):
        for transform in (repair.inverse, repair.forward):
            with self.subTest(transform=transform.__name__), self.assertRaises(ValueError):
                transform('Tests/AppUITests/Unrelated.swift', b'')

    def test_all_original_assertion_statements_are_preserved(self):
        for path in (MEDIA, TEMPLATE):
            before, after = self.sources(path)
            with self.subTest(path=path):
                self.assertEqual([line for line in before.splitlines() if 'XCTAssert' in line],
                                 [line for line in after.splitlines() if 'XCTAssert' in line])

    def test_media_direction_is_the_only_change_to_journeys_and_probe(self):
        before, after = self.sources(MEDIA)
        old = '            tap("projectStoryMedia.gap." + anchor, app, top: true)'
        new = '            tap("projectStoryMedia.gap." + anchor, app)'
        self.assertEqual(before.count(old), 1)
        self.assertEqual(after.count(new), 1)
        self.assertEqual(after.replace(new, old, 1), before)
        self.assertNotIn(old, after)
        self.assertEqual(before[before.index('    func imageJourney'):],
                         after[after.index('    func imageJourney'):])
        self.assertEqual(before[:before.index('    private func insert')],
                         after[:after.index('    private func insert')])

    def test_template_successful_journey_and_probe_behavior_are_unchanged(self):
        before, after = self.sources(TEMPLATE)
        self.assertEqual(before[before.index('    func journey'):], after[after.index('    func journey'):])
        self.assertEqual(before[before.index('    private func tap'):before.index('    private func backToEditor')],
                         after[after.index('    private func tap'):after.index('    private func backToEditor')])
        self.assertEqual(after.count('tap("projectStoryMedia.gap." + anchor, app)'), 1)
        self.assertNotIn('tap("projectStoryMedia.gap." + anchor, app, top: true)', after)

    def test_same_single_five_second_arrival_wait_without_added_action_stage(self):
        before, after = self.sources(TEMPLATE)

        def back(source):
            return source[source.index('    private func backToEditor'):source.index('    private func open')]

        old, new = back(before), back(after)
        self.assertEqual(re.findall(r'timeout: (\d+)', old), ['5'])
        self.assertEqual(re.findall(r'timeout: (\d+)', new), ['5'])
        self.assertEqual(old.count('waitForExistence('), 1)
        self.assertEqual(old.count('XCTWaiter.wait('), 0)
        self.assertEqual(new.count('XCTWaiter.wait('), 1)
        self.assertEqual(new.count('waitForExistence('), 0)
        self.assertEqual(new.count('button.tap()'), 1)
        self.assertEqual(old.count('button.tap()'), new.count('button.tap()'))
        for extra_stage in ['revealFixtureElement', 'sleep(', 'while ', 'for attempt', 'launch(']:
            self.assertNotIn(extra_stage, new)
        self.assertIn('app.navigationBars["Route editor"].buttons["Edit"]', new)
        self.assertIn('exists == true AND hittable == true', new)
        self.assertIn('object: editorAction)], timeout: 5) == .completed', new)
        self.assertIn('XCTAssertTrue(arrived, diagnostic)', new)
        self.assertEqual(before[before.index('        var diagnostic'):before.index('    private func open')],
                         after[after.index('        var diagnostic'):after.index('    private func open')])

    def test_source_derived_template_wait_caps_and_floors_are_unchanged(self):
        cost = repair.contract()['cost']
        before, after = self.sources(TEMPLATE)
        self.assertEqual(before.count('backToEditor(app)'), cost['back_calls_per_template_journey'])
        self.assertEqual(after.count('backToEditor(app)'), 3)
        self.assertEqual(cost['back_wait_before_seconds'], 5)
        self.assertEqual(cost['back_wait_before_seconds'], cost['back_wait_after_seconds'])
        self.assertEqual(cost['back_wait_total_seconds'], 3 * 5)
        self.assertEqual(90 + 355 + 14 * 11 * 2 + 117 + 30, cost['template_end_seconds'])
        self.assertEqual(90 + 385 + 14 * 11 * 2 + 117, cost['template_first_middle_seconds'])
        for key in ('template_first_middle_seconds', 'template_end_seconds', 'media_seconds'):
            self.assertEqual(cost[key], 900, key)
        for key in ('new_launches', 'new_taps', 'new_reveal_calls', 'new_retry_stages', 'new_wait_stages'):
            self.assertEqual(cost[key], 0, key)
        for path, bound in ((TEMPLATE, 10), (MEDIA, 45)):
            old, new = self.sources(path)
            with self.subTest(path=path):
                self.assertIn(f'maximumSwipes: {bound}', new)
                self.assertEqual(re.findall(r'maximumSwipes: \d+', old), re.findall(r'maximumSwipes: \d+', new))
                self.assertEqual(re.findall(r'timeout: \d+', old), re.findall(r'timeout: \d+', new))
                for call in ('app.launch()', 'revealFixtureElement(', 'button.tap()', 'tap('):
                    self.assertEqual(old.count(call), new.count(call), call)
        self.assertFalse(cost['measured'])
        self.assertEqual(cost['added_predicate_properties_per_evaluation'], ['hittable'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
