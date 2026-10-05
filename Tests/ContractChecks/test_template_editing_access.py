"""Native local-editor controls; these contracts do not execute Apple UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TemplateEditingAccessChecks(unittest.TestCase):
    def test_done_controls_only_release_their_own_focus(self):
        sensor = (ROOT / 'App/TemplateSensorDraftConfigurationView.swift').read_text()
        preference = (ROOT / 'App/TemplatePreferenceDraftEditor.swift').read_text()
        for source, binding, action, identifier in [
            (sensor, '.focused($focusedParameter, equals: parameter.rawValue)',
             'Button("action.done") { focusedParameter = nil }', 'sensorDraft.keyboardDone'),
            (preference, '.focused($sourceFocused)',
             'Button("action.done") { sourceFocused = false }', 'templateAuthor.preference.keyboardDone')]:
            self.assertIn(binding, source)
            self.assertIn(action, source)
            self.assertIn('ToolbarItemGroup(placement: .keyboard)', source)
            self.assertIn(identifier, source)
            for forbidden in ['UIApplication.shared', 'resignFirstResponder', '.send(', 'URLSession', 'AVAudioSession']:
                self.assertNotIn(forbidden, source)
        self.assertIn('if focusedParameter == parameter.rawValue', sensor)
        self.assertIn('if sourceFocused', preference)

    def test_preference_reveal_targets_outer_form_gutter_without_relaxing_visibility(self):
        source = (ROOT / 'Tests/AppUITests/TemplatePreferenceDraftEditorFlowTests.swift').read_text()
        helper = source.split('private func revealSource(')[1].split('private func check(')[0]
        for token in ['app.collectionViews.firstMatch', 'bounds.contains(frame) && source.isHittable',
                      'frame.minX - 12', 'guard x < frame.minX', 'app.navigationBars.firstMatch',
                      'app.keyboards.firstMatch.frame.minY - 8', 'XCTFail(']:
            self.assertIn(token, helper)
        self.assertIn('revealFixtureElement(element, in: app', source)
        self.assertIn('actual.map { Array($0.utf8) }', source)
        self.assertIn('assertBytes(current.replacingOccurrences(of: insertion, with: ""), equal: original)', source)

    def test_real_done_taps_keep_exact_raw_and_unavailable_actions_assertions(self):
        sensor = (ROOT / 'Tests/AppUITests/TemplateSensorDraftFlowTests.swift').read_text()
        preference = (ROOT / 'Tests/AppUITests/TemplatePreferenceDraftEditorFlowTests.swift').read_text()
        for source in [sensor, preference]:
            self.assertIn('done.tap()', source)
            self.assertIn('done.isEnabled && done.isHittable', source)
            self.assertIn('object: app.keyboards.firstMatch', source)
            self.assertIn('templateAuthor.reviewDraft', source)
            self.assertIn('templateAuthor.reviewPublish', source)
            self.assertIn('XCTAssertFalse(button.isEnabled', source)
        self.assertIn('XCTAssertEqual(Array(original.utf8), Array(raw.utf8)', sensor)
        self.assertIn('XCTAssertEqual(input.value as? String, current', sensor)
        self.assertIn('assertBytes(source.value as? String, equal: current)', preference)


if __name__ == '__main__': unittest.main()
