"""motion-1118 shared token mirror. Offline source guard only."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('check_native_motion_tokens', ROOT / 'tools/check_native_motion_tokens.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class NativeMotionTokenMirror(unittest.TestCase):
    def test_swift_tokens_mirror_shared_table(self):
        self.assertEqual(mod.problems(), [])

    def test_system_only_reduce_motion_readers_are_gone(self):
        # ClubOperationsViews.swift kept on the system-only reader: changing it broke ClubOperationsFlowTests in CI (motion-1118).
        for name in ('PlayObjectCardRevealView.swift', 'PlayKitSensorChallengeView.swift',
                     'PlayKitSpatialRevealView.swift', 'GrowthCenterComponents.swift'):
            source = (ROOT / 'App' / name).read_text()
            self.assertNotIn('@Environment(\\.accessibilityReduceMotion) private var reduceMotion', source, name)
            self.assertIn('@QuestifyReduceMotion private var reduceMotion', source, name)


if __name__ == '__main__':
    unittest.main()
