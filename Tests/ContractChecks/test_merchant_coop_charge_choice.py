"""Focused mandatory-choice contract checks; not runtime/UI execution."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

class MerchantCoopChargeChoiceContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_missing_and_unknown_have_distinct_blockers_without_a_default(self):
        source = self.read('Core/MerchantOperationsContracts.swift').split('public struct MerchantCoopSettings:', 1)[1].split('public struct MerchantStorefront:', 1)[0]
        self.assertIn('chargeType = c.merchantInteger(.chargeType)', source)
        self.assertIn('guard let chargeType else { return "merchant.coopChargeChoice.required" }', source)
        self.assertIn('if ![0, 1].contains(chargeType) { return "merchant.operations.chargeUnknown" }', source)
        self.assertNotIn('chargeType = 0', source); self.assertNotIn('chargeType) ?? 0', source)
    def test_existing_review_gate_and_picker_use_the_blocker_without_new_actions(self):
        self.assertIn('draft?.blocker == nil', self.read('Core/MerchantOperationsReading.swift'))
        self.assertIn('if blocker != nil { throw APIError.invalidRequest }', self.read('Core/MerchantOperationsDraft.swift'))
        editor = self.read('App/MerchantOperationsEditor.swift')
        self.assertIn('Text("merchant.operations.unspecified").tag(Int?.none)', editor)
        self.assertIn('.disabled(!coordinator.canReview)', editor)
        self.assertIn('if let blocker = draft.blocker', editor)
        fixture = self.read('Tests/CoreTests/MerchantOperationsTests.swift').split('func testCooperationCapacityIsOptionalNonnegativeInteger()', 1)[1].split('func testUnknownCooperationCharge', 1)[0]
        self.assertIn('#"{"chargeType":0}"#', fixture)
        self.assertIn('XCTAssertNil(value.fields["capacity"])', fixture)
    def test_fragment_is_bilingual_and_accepts_only_an_exact_full_merge(self):
        fragment = json.loads(self.read('Resources/MerchantCoopChargeChoiceLocalizations.fragment.json')); self.assertEqual(len(fragment), 1)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']; present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for lang in ['en', 'zh-Hans']: self.assertTrue(entry['localizations'][lang]['stringUnit']['value'].strip())
if __name__ == '__main__': unittest.main()
