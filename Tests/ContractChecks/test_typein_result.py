"""Source assertions only; Swift execution remains a separate gate."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class TypeInResultChecks(unittest.TestCase):
    def test_result_is_typed_server_readback_without_local_cap_judgment(self):
        core=(ROOT/'Core/PlayKitScreenContracts.swift').read_text()
        block=core.split('public var typeInResultKey: String? {',1)[1].split('public var feedback:',1)[0]
        for part in ['kind == .typeIn', 'segment["attempts"].integer, attempts > 0', 'segment["submitted"].bool', 'segment["passed"].bool', 'submitted ? "playkit.result.passed" : nil']:
            self.assertIn(part,block)
        for forbidden in ['segment["tries"]','elapsed','target','input']:
            self.assertNotIn(forbidden,block)
    def test_visible_typed_limit_and_result_use_existing_timed_screen(self):
        code=(ROOT/'App/PlayKitTimedChallengeView.swift').read_text()
        self.assertIn('segment["tries"].integer, cap > 0',code)
        self.assertIn('PlayKitScreenProjection(kind: kind, segment: segment).typeInResultKey',code)
        self.assertIn('Text(LocalizedStringKey(result))',code)
        self.assertIn('currentRevisionIdentity?() ?? revisionIdentity',code)
        self.assertIn('.disabled(!enabled',code)
