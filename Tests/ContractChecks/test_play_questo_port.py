"""Source checks for the Questo B1/B2 iOS port. They do not compile Swift or call a backend;
behaviour tests are Tests/CoreTests/PlayQuestoTests.swift."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PlayQuestoPortChecks(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()

    def test_help_service_is_default_off_and_keeps_skip_on_its_own_route(self):
        s = self.read('Core/PlayQuestoHelp.swift')
        self.assertIn('enabled: Bool = false', s)
        self.assertIn('guard enabled else { throw PlayExperienceError.disabled }', s)
        self.assertIn('body["action"] = .string("HELP")', s)
        self.assertIn('"/skip"', s)
        self.assertNotIn('.string("SKIP")', s)

    def test_unknown_write_keeps_request_id_and_is_never_failure(self):
        s = self.read('Core/PlayQuestoHelp.swift')
        self.assertIn('case .unknown: return .unknown(requestID: requestID)', s)
        self.assertIn('catch { return .unknown }', s)
        self.assertIn('if let existing = ids[intent] { return existing }', s)

    def test_no_invented_run_counter_or_local_pricing(self):
        # GET /api/play/help sends no remaining-free-uses count; the panel must not draw one.
        for name in ['Core/PlayQuestoHelp.swift', 'App/PlayQuestoHelpViews.swift']:
            s = self.read(name)
            self.assertNotRegex(s, r'remainingFree|freeRemaining|runFreeUses')
        self.assertIn('legacyFreeQuota', self.read('Core/PlayQuestoHelp.swift'))

    def test_not_scored_never_renders_zero(self):
        s = self.read('Core/PlayQuestoHelp.swift')
        self.assertIn('public var showsScore: Bool { scoreState == .scored && netScore != nil }', s)

    def test_accusation_early_close_is_not_success_and_unknown_is_confirming(self):
        s = self.read('Core/PlayQuestoGameplay.swift')
        self.assertIn('case "CORRECT": ending = early ? .closedEarly : .solved', s)
        self.assertIn('public var celebrates: Bool { ending == .solved }', s)
        self.assertIn('default: ending = .confirming', s)

    def test_option_images_never_use_raw_media_refs_or_insecure_urls(self):
        s = self.read('Core/PlayQuestoGameplay.swift')
        self.assertIn('components.scheme == "https"', s)
        self.assertIn('!value.hasPrefix("//")', s)

    def test_compatibility_undeclared_is_not_supported(self):
        s = self.read('Core/PlayQuestoArrival.swift')
        self.assertIn('case .some(true) where source == "DECLARED": verdict = .supported', s)
        a = self.read('Core/PlayAdvancedRuntime.swift')
        self.assertIn('declaration: PlayClientCapabilityDeclaration? = nil', a)
        self.assertIn('"hangman": ["SUBMIT_HANGMAN"]', a)

    def test_mirror_flips_only_the_question_text(self):
        v = self.read('App/PlayQuestoGameplayViews.swift')
        self.assertEqual(len(re.findall(r'scaleEffect\(x: transform\.mirrorsText', v)), 1)

    def test_every_key_used_is_bilingual(self):
        catalog = json.loads(self.read('Resources/PlayQuesto.xcstrings'))['strings']
        used = set()
        for name in ['App/PlayQuestoHelpViews.swift', 'App/PlayQuestoGameplayViews.swift']:
            s = self.read(name)
            used |= {'playQuesto.' + k for k in re.findall(r'questoText\("([^"]+)"\)', s)}
            used |= {m + ' %lld' for m in re.findall(r'Text\("(playQuesto\.[A-Za-z.]+) \\\(', s)}
        self.assertTrue(used)
        for key in used:
            self.assertIn(key, catalog)
            self.assertEqual(set(catalog[key]['localizations']), {'en', 'zh-Hans'}, key)


if __name__ == '__main__':
    unittest.main()
