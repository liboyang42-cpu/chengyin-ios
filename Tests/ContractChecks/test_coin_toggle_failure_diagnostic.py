"""Diagnostic-only source checks; no claim that the unresolved switch failure is repaired."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CoinToggleFailureDiagnosticChecks(unittest.TestCase):
    def test_failed_value_assertion_never_retries_or_accepts_the_unchanged_switch(self):
        s = (ROOT / 'Tests/AppUITests/TemplateCompositionFlowTests.swift').read_text()
        helper = s.split('private func disableCoin(')[1].split('func testOpening')[0]
        self.assertEqual(helper.count('tapFixtureNativeSwitch(coin, in: app)'), 1)
        self.assertIn('NSPredicate(format: "value == %@", "0")', helper)
        self.assertIn('let outcome = XCTWaiter.wait(for: [disabled], timeout: 5)', helper)
        self.assertIn('if outcome != .completed', helper)
        self.assertIn('XCTAssertEqual(outcome, .completed, app.debugDescription)', helper)
        self.assertNotIn('coin.tap()', helper)
        self.assertIn('Coin toggle before diagnostic inspection', helper)
        self.assertIn('attachment.lifetime = .keepAlways', helper)

    def test_probe_is_debug_and_requires_all_explicit_synthetic_flags(self):
        s = (ROOT / 'App/TemplateAdvancedGameConfigurationView.swift').read_text()
        section = s.split('#if DEBUG')[2].split('#endif')[0]
        for flag in ['--ui-template-authoring', '--template-author-compound', '--template-author-toggle-probe']:
            self.assertIn('arguments.contains("' + flag + '")', section)
        self.assertIn('inputProbeSnapshot = model.gameInputProbe(game)', section)
        self.assertNotIn('setGameEnabled', section)

    def test_observation_does_not_create_an_extra_model_publication_or_relax_can_edit(self):
        s = (ROOT / 'App/TemplateAuthoringView.swift').read_text()
        fields = s.split('// Bounded, non-observable input facts.')[1].split('#endif')[0]
        self.assertNotIn('@Published', fields)
        self.assertIn('private var gameInputEvents: [String] = []', fields)
        setter = s.split('func setGameEnabled(')[1].split('func restore()')[0]
        self.assertIn('gameInputEvents.suffix(3)', setter)
        self.assertIn('guard canEdit else { return }', setter)
        self.assertIn('draft.advanced.setGameEnabled(game, enabled)', setter)


if __name__ == '__main__':
    unittest.main()
