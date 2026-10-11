"""Focused supplementary source checks; not native Swift or simulator acceptance."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplateRuleStepsChecks(unittest.TestCase):
    def test_existing_optional_wire_field_is_strictly_decoded_without_new_schema(self):
        model = read('Core/MerchantOperationsContracts.swift').split('public struct MerchantNodeTemplate:')[1].split('public struct MerchantCityNodeRecord:')[0]
        self.assertIn('ruleSteps = .init(sourceText: try c.decodeIfPresent(String.self, forKey: .ruleInstructions))', model)
        self.assertIn('if let rules = ruleSteps.wireValue { fields["ruleInstructions"] = rules }', model)
        for token in ['fields["ruleSteps"]', 'fields["merchantGuide"]', 'fields["clearRuleInstructions"]']:
            self.assertNotIn(token, model)

    def test_untouched_source_is_preserved_and_explicit_clear_is_not_dropped(self):
        rules = read('Core/MerchantOperationsContracts.swift').split('public struct MerchantTemplateRuleSteps:')[1].split('public struct MerchantNodeTemplate:')[0]
        self.assertIn('guard isEdited else { return sourceText }', rules)
        self.assertIn('.filter { !$0.isEmpty }.joined(separator: "\\n")', rules)
        self.assertIn('isEdited && wireValue == ""', rules)
        self.assertNotIn('.prefix(', rules)
        self.assertIn('returned.ruleSteps = .init(sourceText: draft.ruleSteps.wireValue ?? baseline.ruleSteps.wireValue)', read('Core/MerchantOperationsSyntheticFixtures.swift'))

    def test_step_boundaries_match_mini_without_truncating_legacy_rules(self):
        source = read('Core/MerchantOperationsContracts.swift')
        for token in ['maximumSteps = 12', 'maximumStepLength = 60', 'guard isEdited else { return nil }',
                      'guard rows.count > 1, rows.indices.contains(index)', 'guard canAdd else { return }',
                      '$0.utf16.count > Self.maximumStepLength', '$0.rangeOfCharacter(from: .newlines)',
                      'if let blocker = ruleSteps.blocker { return blocker }']:
            self.assertIn(token, source)

    def test_editor_and_review_are_integrated_and_edit_through_existing_coordinator(self):
        app = read('App/MerchantOperationsEditor.swift')
        for token in ['MerchantTemplateRuleStepsFields(model: model)', 'ForEach(rules.rows.indices, id: \\.self)',
                      'action(&value.ruleSteps); model.edit(.template(value))', '$0.add()', '$0.remove(at: index)',
                      '$0.update(at: index, text: text)', '.disabled(!rules.canAdd)',
                      'MerchantTemplateRuleStepsReview(rules: template.ruleSteps)',
                      'if rules.isClearing', 'Text(verbatim: text)']:
            self.assertIn(token, app)
        self.assertIn('confirmation.draft', app)

    def test_localization_includes_interpolated_accessibility_labels_and_player_warning(self):
        fragment = json.loads(read('Resources/MerchantTemplateRuleStepsLocalizations.fragment.json'))
        source = read('Core/MerchantOperationsContracts.swift') + read('App/MerchantOperationsEditor.swift')
        source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', source)
        keys = set(re.findall(r'"(merchant\.ruleSteps\.[A-Za-z]+)"', source))
        keys.update(['merchant.ruleSteps.step %lld', 'merchant.ruleSteps.removeStep %lld'])
        self.assertEqual(set(fragment), keys)
        self.assertEqual(len(fragment), 14)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        self.assertIn('staff-only answers', fragment['merchant.ruleSteps.playerVisible']['localizations']['en']['stringUnit']['value'])
        self.assertIn('clear the existing', fragment['merchant.ruleSteps.clearReview']['localizations']['en']['stringUnit']['value'])

    def test_existing_write_gate_and_authoritative_readback_are_retained(self):
        reader = read('Core/MerchantOperationsReading.swift')
        for token in ['guard reader.canSave', 'reader.saveTemplateReviewed(template, baseline: baseline)',
                      'baseline = .template(returned); draft = .template(returned)', 'let approval, let journal']:
            self.assertIn(token, reader)
        self.assertIn('guard !localOnlyReview else { throw MerchantOperationsFailure.liveWritesDisabled }', read('Core/MerchantOperationsDraft.swift'))
        fields = read('Core/MerchantTemplateAssistContracts.swift').split('public enum MerchantTemplateAssistField:')[1].split('public struct MerchantTemplateAssistEdits:')[0]
        self.assertNotIn('ruleInstructions', fields); self.assertNotIn('ruleSteps', fields)

    def test_authored_core_tests_cover_boundaries_clear_cancel_no_replay_and_real_adapter(self):
        core = read('Tests/CoreTests/MerchantTemplateRuleStepsTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 15)
        for token in ['RuleStepsTransport: HTTPTransport', 'coordinator.cancelConfirmation()', 'coordinator.discardChanges()',
                      'XCTAssertEqual(saves.count, 1)', 'source.ruleSteps.wireValue, canonicalText',
                      '"/prod-api/api/template/myinfo"', 'editedText: "", canonicalText: ""',
                      'XCTAssertTrue(transport.requests.isEmpty)', 'String(repeating: "🧩", count: 31)']:
            self.assertIn(token, core)

    def test_authored_ui_tests_cover_edit_remove_reload_cancel_discard_and_explicit_clear(self):
        ui = read('Tests/AppUITests/MerchantTemplateRuleStepsFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 2)
        for token in ['merchant.ruleSteps.remove.1', 'merchant.ruleSteps.review.clear', 'merchant.operations.confirm.cancel',
                      'app.alerts.buttons["merchant.operations.keepEditing"].tap()', 'app.alerts.buttons["merchant.operations.discardReload"].tap()', 'XCTAssertEqual(text.label, "Find the sign\\nRead the clue")']:
            self.assertIn(token, ui)
        self.assertIn('app.alerts.buttons["merchant.operations.keepEditing"].waitForExistence(timeout: 5)', ui)
        self.assertIn('app.alerts.buttons["merchant.operations.discardReload"].waitForExistence(timeout: 5)', ui)


if __name__ == '__main__': unittest.main()
