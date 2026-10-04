"""Source shape checks only; runtime behavior is covered by authored Swift tests."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class SortTerminalResultChecks(unittest.TestCase):
    def test_readout_uses_typed_server_projection(self):
        core = (ROOT/'Core/PlayKitScreenContracts.swift').read_text()
        block = core.split('public var reasoningResultKey: String? {', 1)[1].split('public var feedback:', 1)[0]
        for token in ['attempts > 0', 'segment["passed"].bool', 'segment["finished"].bool', 'if kind == .sort', 'if finished', 'return nil']:
            self.assertIn(token, block)
        self.assertLess(block.index('guard let finished'), block.index('if passed'))
        self.assertIn('return finished ? "playkit.result.passed" : nil', block)
        self.assertNotIn('maxAttempts', block)
        self.assertNotIn('answerOrder', block)
        view = (ROOT/'App/PlayKitReasoningForms.swift').read_text()
        self.assertIn('PlayKitScreenProjection(kind: kind, segment: segment).reasoningResultKey', view)
        self.assertIn('.disabled(!enabled || !valid)', view)
    def test_terminal_copy_is_bilingual_and_not_retry(self):
        strings = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        item = strings['playkit.reasoning.finishedNotPassed']['localizations']
        self.assertEqual(set(item), {'en', 'zh-Hans'})
        self.assertIn('No more attempts', item['en']['stringUnit']['value'])
        self.assertIn('不能再重试', item['zh-Hans']['stringUnit']['value'])
    def test_authoritative_session_and_completion_gates_remain(self):
        screen = (ROOT/'App/PlayKitScreen.swift').read_text()
        self.assertIn('model.canInteract && !projection.complete && review == nil', screen)
        self.assertIn('if !model.isCurrent', screen)
        self.assertIn('model.state?.version != item.version', screen)
if __name__ == '__main__': unittest.main()
