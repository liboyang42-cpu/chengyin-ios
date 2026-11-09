"""Source checks for the qx-u4 iOS polish kit. They do not compile Swift; behaviour tests for the
gesture maths are Tests/CoreTests/QuestoGestureMathTests.swift."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
KIT = 'App/QuestoInteractionKit.swift'


class QuestoPolishKitChecks(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()

    def test_sheet_sizes_match_the_brief(self):
        s = self.read('Core/QuestoGestureMath.swift')
        for fraction in ['return 0.3', 'return 0.6', 'return 0.8']:
            self.assertIn(fraction, s)
        self.assertIn('public static let resistance = 0.25', s)

    def test_questo_sheets_use_the_shared_interactive_sheet(self):
        for name in ['App/PlayQuestoHelpViews.swift', 'App/PlayQuestoGameplayViews.swift']:
            s = self.read(name)
            self.assertIn('.questoSheet([.half, .full])', s)
            self.assertNotIn('presentationDetents([.medium, .large])', s)
        kit = self.read(KIT)
        self.assertIn('.presentationContentInteraction(.scrolls)', kit)
        self.assertIn('.presentationDragIndicator(.visible)', kit)

    def test_every_animation_respects_reduce_motion(self):
        for name in [KIT, 'App/PlayQuestoHelpViews.swift', 'App/TemplateAuthoringPublishResultPresentation.swift']:
            s = self.read(name)
            self.assertIn('@QuestifyReduceMotion private var reduceMotion', s)
            for line in s.splitlines():
                if 'withAnimation(' in line or '.animation(' in line:
                    self.assertIn('reduceMotion', line, f'{name}: {line.strip()}')

    def test_motion_uses_transitions_not_keyframes(self):
        for name in [KIT, 'App/PlayQuestoHelpViews.swift']:
            s = self.read(name)
            self.assertNotRegex(s, r'keyframeAnimator|phaseAnimator|repeatForever')

    def test_help_morph_never_marks_unknown_results_done(self):
        s = self.read('App/PlayQuestoHelpViews.swift')
        self.assertIn('if revealed[layer.level] != nil { return .done }', s)
        # Unknown (pending) rows keep 继续核对 and never enter the morph.
        self.assertLess(s.index('if pending.contains(layer.level) {'), s.index('QuestoMorphControl(phase: morphPhase(layer))'))

    def test_kit_keys_are_bilingual(self):
        catalog = json.loads(self.read('Resources/PlayQuesto.xcstrings'))['strings']
        s = self.read(KIT)
        used = {'playQuesto.' + k for k in re.findall(r'questoText\("([^"]+)"\)', s)}
        used.add('playQuesto.onboarding.progress %lld %lld')
        self.assertTrue(used)
        for key in used:
            self.assertIn(key, catalog)
            self.assertEqual(set(catalog[key]['localizations']), {'en', 'zh-Hans'}, key)


if __name__ == '__main__':
    unittest.main()
