"""Affected clear intent checks; not a live save or Swift runtime test."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantCoopCapacityClearContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_clear_requires_loaded_nonempty_to_current_empty_and_explicit_wire_pair(self):
        source = self.read('Core/MerchantOperationsContracts.swift').split('public struct MerchantCoopSettings:', 1)[1].split('public struct MerchantStorefront:', 1)[0]
        self.assertIn('!loadedCapacity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', source)
        self.assertIn('&& capacity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', source)
        self.assertIn('else if clearsCapacity { fields["capacity"] = NSNull(); fields["params"] = ["clearCapacity": true] }', source)
        self.assertIn('loadedCapacity = capacity', source)
        comparison = source.split('public static func ==', 1)[1].split('/// Only a definite acknowledgement', 1)[0]
        self.assertNotIn('loadedCapacity', comparison)
        for field in ['capacity', 'availableTime', 'chargeType', 'demand', 'suitActivityTypes', 'coopOpen']:
            self.assertIn('lhs.' + field + ' == rhs.' + field, comparison)
        self.assertIn('if let suitActivityTypes { fields["suitActivityTypes"] = suitActivityTypes }', source)
        self.assertIn('if let coopOpen { fields["coopOpen"] = coopOpen }', source)

    def test_only_definite_cooperation_success_consumes_intent(self):
        source = self.read('Core/MerchantOperationsReading.swift')
        self.assertEqual(source.count('acknowledgeCapacityEdit()'), 1)
        before, after = source.split('accepted.acknowledgeCapacityEdit()', 1)
        self.assertIn('else if case .cooperation(var accepted) = value.draft', before)
        self.assertLess(before.rindex('try await reader.saveReviewed'), before.rindex('else if case .cooperation'))
        self.assertIn('baseline = saved; draft = saved; document = .draft(saved)', after)
        self.assertIn('guard latest == .draft(value.baseline)', before)
        self.assertIn('issue = isLocked ? .key("merchant.operations.unknownOutcome")', after)

    def test_editor_and_frozen_review_both_disclose_clear(self):
        source = self.read('App/MerchantOperationsEditor.swift')
        self.assertIn('if value.clearsCapacity { Text("merchant.coopCapacityClear.draftHint")', source)
        self.assertIn('if case .cooperation(let value) = confirmation.draft, value.clearsCapacity', source)
        self.assertIn('merchant.coopCapacityClear.review', source)
        self.assertIn('Button("merchant.operations.reviewDraft") { model.prepare() }', source)

    def test_bilingual_fragment_is_absent_or_exactly_merged(self):
        fragment = json.loads(self.read('Resources/MerchantCoopCapacityClearLocalizations.fragment.json')); self.assertEqual(len(fragment), 2)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']; present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']: self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()
