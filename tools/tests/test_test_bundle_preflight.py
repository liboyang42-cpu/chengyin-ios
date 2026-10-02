"""Ensure early compilation supplements rather than replaces runtime gates."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TestBundlePreflightTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        self.native = self.workflow.split('  native:\n', 1)[1].split('  secrets:\n', 1)[0]

    def test_preflight_uses_concrete_available_destination_and_both_schemes(self):
        self.assertIn('BUILD_TEST_SIMULATOR_ID=', self.native)
        self.assertIn("d.get('isAvailable')", self.native)
        self.assertIn('for scheme in Questify QuestifyAppUnitTests; do', self.native)
        self.assertIn('CODE_SIGNING_ALLOWED=NO build-for-testing', self.native)
        self.assertIn('platform=iOS Simulator,id=$BUILD_TEST_SIMULATOR_ID', self.native)

    def test_shared_test_compilation_happens_before_device_builds(self):
        self.assertLess(self.native.index('Compile UI and app-unit test bundles'),
                        self.native.index('Compile iOS device app (unsigned)'))
        self.assertNotIn('continue-on-error', self.native)
        self.assertNotIn('-skip-testing', self.native)

    def test_runtime_app_unit_and_all_ui_shards_are_still_required(self):
        self.assertIn('-only-testing:QuestifyAppUnitTests CODE_SIGNING_ALLOWED=NO test', self.workflow)
        self.assertIn('shard: [0, 1, 2, 3, 4, 5]', self.workflow)
        self.assertIn('python3 tools/run_ui_shard.py --shard ${{ matrix.shard }} --count 6', self.workflow)
        self.assertEqual(self.workflow.count('    needs: native'), 2)


if __name__ == '__main__':
    unittest.main()
