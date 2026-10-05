"""Timing assumptions for the new authored walking camera flow, not measurements."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WalkingCameraBudgetTests(unittest.TestCase):
    def test_new_bilingual_camera_flow_uses_explicit_unmeasured_estimate(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        name = 'WalkingNavigationFlowTests.testBilingualMaximumCameraActionsAreExplicitAndClearWithRoute'
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] == 'walkingCameraAcceptance']
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['method'], name)
        self.assertEqual(records[0]['seconds'], 180)
        self.assertIs(records[0]['measured'], False)
        self.assertTrue(records[0]['basis'])
        self.assertEqual(profile['estimated_method_seconds'][name], 180)
        self.assertNotIn(name, profile['method_seconds'])
        self.assertIn('func ' + name.split('.')[1] + '()', (ROOT / 'Tests/AppUITests/WalkingNavigationFlowTests.swift').read_text())
        self.assertEqual(profile['planning_budget']['deadline_seconds'], 1800)
        self.assertEqual(profile['planning_budget']['startup_reserve_seconds'], 300)
