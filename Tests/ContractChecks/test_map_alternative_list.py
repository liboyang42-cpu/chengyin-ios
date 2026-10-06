"""Run the reviewed map source contracts, including lexical negative controls.
These checks do not compile or run Swift, XCUITest, MapKit, or VoiceOver.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MapAlternativeListContracts(unittest.TestCase):
    def run_checker(self, root):
        return subprocess.run([sys.executable, str(ROOT/'tools/check_map_alternative_list.py'),
                               '--root', str(root), '--base', str(ROOT)],
                              capture_output=True, text=True)

    def test_reviewed_source_contracts_all_pass(self):
        result = self.run_checker(ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: 38 map alternative-list source contracts', result.stdout)

    def check_mutant(self, before, after, expected):
        source = (ROOT/'App/QuestifyDensityMap.swift').read_text()
        self.assertEqual(source.count(before), 1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'App').mkdir()
            (root/'App/QuestifyDensityMap.swift').write_text(source.replace(before, after))
            result = self.run_checker(root)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.strip().splitlines()[-1], 'AssertionError: ' + expected)

    def test_retained_toggle_cannot_bypass_one_shot_consumption(self):
        self.check_mutant('toggleGate.consume(toggleRequest) else { return }',
                          'true else { return }',
                          'Toggle consumes a captured current-lifetime request')

    def test_departure_must_retire_the_visible_lifecycle(self):
        self.check_mutant('toggleGate.disappear()', 'toggleGate.invalidate()',
                          'Close and disappearance invalidate requests')
