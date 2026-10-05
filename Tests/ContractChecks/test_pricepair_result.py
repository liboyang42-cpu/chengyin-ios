"""Readback source wiring assertions; not Swift execution or Apple UI acceptance."""
import json
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class PricePairResultChecks(unittest.TestCase):
    def test_readback_is_server_only_and_fail_closed(self):
        code = (ROOT/'Core/PlayKitScreenContracts.swift').read_text().split('public struct PlayKitPricePairResult:', 1)[1]
        for required in ['segment["attempts"].integer, attempts > 0', 'segment["finished"].bool', 'segment["passed"].bool', 'segment["lastPickId"].text', 'Set(ids).count == ids.count', 'ids.contains(lastPick)', '!passed || finished', 'if finished {', 'segment["answerId"].text, ids.contains(reported)', 'passed ? reported == lastPick : reported != lastPick']:
            self.assertIn(required, code)
        for forbidden in ['maxTries', 'maxAttempts', 'score', 'random', 'correct]', 'selected']:
            self.assertNotIn(forbidden, code)
    def test_live_pricepair_form_uses_uncached_current_scope_readback(self):
        code = (ROOT/'App/PlayKitQuestionForms.swift').read_text().split('@ViewBuilder var pricePairForm:',1)[1].split('@ViewBuilder var hiddenObjectForm:',1)[0]
        for required in ['model.isCurrent', '["stale", "disabled"].contains(model.phase)', 'PlayKitPricePairResult(segment: raw)', 'result.lastPickID == option.id', 'result.answerID == option.id', 'playkit.pricePair.currentChoice', '.accessibilityValue', 'result.finished ? "playkit.pricePair.ended"', 'submitButton("SUBMIT_PRICE_PAIR", payload: ["pickId": .string(selected.first ?? "")]']:
            self.assertIn(required, code)
        self.assertNotIn('@State', code)
        self.assertNotIn('selected =', code)
        screen=(ROOT/'App/PlayKitScreen.swift').read_text()
        self.assertIn('case .pricePair: pricePairForm',screen)
        self.assertIn('ChapterInlineKitSelection.segment(kind, in: state)',screen)
        runtime=(ROOT/'Core/PlayAdvancedRuntime.swift').read_text()
        for required in ['state.activityID == activityID', 'state.topicID == topicID', 'state.nodeID == nodeID', 'currentSession() == session']:
            self.assertIn(required,runtime)
    def test_user_visible_copy_is_bilingual_and_distinct(self):
        fragment=json.loads((ROOT/'Resources/PlayKitPricePairLocalizations.fragment.json').read_text())['strings']
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        for suffix in ['lastCorrect','lastIncorrect','currentChoice','revealedAnswer','ended','retry']:
            key='playkit.pricePair.'+suffix
            self.assertEqual(fragment[key],catalog[key])
            for lang in ['en','zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][lang]['stringUnit']['value'])
