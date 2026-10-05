"""Wiring evidence only: does not execute Swift, Apple UI or backend behavior."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

class CompletionRulesWiring(unittest.TestCase):
    def test_detail_and_full_payload_share_complete_rule_field(self):
        source = (ROOT / 'Core/ProjectEditContract.swift').read_text()
        carry = source.split('public static let topicCarryOver = ')[1].split('\n')[0]
        self.assertIn('"completeRuleJson"', carry)
        self.assertIn('for key in topicCarryOver { if let value = topic[key]', source)
        self.assertLess(source.index('if scope == .whitelist'), source.index('rules.serialized'))
        self.assertIn('.forProduct(draft.product)', source)
    def test_existing_model_and_review_are_connected(self):
        model = (ROOT / 'App/ProjectEditView.swift').read_text()
        self.assertIn('ProjectEditCompletionRulesForm(rules: model.completionRules', model)
        self.assertIn('guard self.fullEdit, !self.completionRules.wrappedValue.readOnly', model)
        self.assertIn('self.draft.completionRules = value', model)
        self.assertIn('ProjectEditCompletionRulesSummary(draft: confirmation.draft)', (ROOT / 'App/ProjectEditDetailForms.swift').read_text())
    def test_local_codable_is_optional_and_dispatch_unchanged(self):
        self.assertIn('public var completionRules: ProjectEditCompletionRules?', (ROOT / 'Core/ProjectEditDraft.swift').read_text())
        rules = (ROOT / 'Core/ProjectEditCompletionRules.swift').read_text()
        for forbidden in ['URLSession', 'URLRequest', 'transport.send', 'nodeId', 'api/topic/']:
            self.assertNotIn(forbidden, rules)
        self.assertIn('guard source == original', rules)
        self.assertIn('if readOnly { return source }', rules)
    def test_s_order_is_view_only_and_wire_keeps_positions(self):
        rules = (ROOT / 'Core/ProjectEditCompletionRules.swift').read_text()
        self.assertIn('[0, 1, 2, 5, 4, 3, 6, 7, 8]', rules)
        self.assertIn('.array(cells.map', rules)
        self.assertNotIn('displayOrder.map', rules)
        self.assertIn('result.removeValue(forKey: "bingo")', rules)
    def test_all_completion_copy_is_bilingual(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        keys = [key for key in catalog if key.startswith('projectEdit.completion.')]
        self.assertEqual(len(keys), 30)
        for key in keys:
            self.assertEqual(set(catalog[key]['localizations']), {'en', 'zh-Hans'})
