"""Source wiring checks, not executed Swift or Apple evidence."""
import json
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class MerchantStoreHoursChecks(unittest.TestCase):
    def test_optional_explicit_replacement_only(self):
        source=(ROOT/'Core/MerchantOperationsContracts.swift').read_text()
        self.assertIn('public let businessTime: String?',source)
        self.assertIn('if let businessTimeReplacement { fields["businessTime"] = businessTimeReplacement }',source)
        legacy=source.split('public var legacyFields:',1)[1].split('\n}',1)[0]
        self.assertNotIn('businessTime',legacy)
        self.assertIn('value.benefitsBlocker ?? value.hoursBlocker',(ROOT/'Core/MerchantOperationsDraft.swift').read_text())
    def test_clock_has_no_timezone_and_rejects_equal_times(self):
        source=(ROOT/'Core/MerchantStoreHours.swift').read_text()
        for item in ['startMinutes != endMinutes','(endMinutes < startMinutes) == wireValue.contains("次日")','days.sorted()','days.isSubset(of: Set(0...6))']:
            self.assertIn(item,source)
        self.assertNotIn('Calendar.',source)
    def test_editor_is_normal_entry_and_explicit_draft(self):
        self.assertIn('MerchantStoreHoursEditor(model: model)',(ROOT/'App/MerchantOperationsEditor.swift').read_text())
        source=(ROOT/'App/MerchantStoreHoursEditor.swift').read_text()
        for item in ['profile.businessTimeReplacement = wire','profile.businessTimeReplacement = nil','model.coordinator.confirmation == nil','!model.coordinator.isLocked']:
            self.assertIn(item,source)
    def test_localizations_match(self):
        fragment=json.loads((ROOT/'docs/merchant-operations-localizations.json').read_text())
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        for name in ['businessTime','hoursInvalid','hoursPreserved','hoursOvernight','hoursUseDraft','hoursEdit','hoursRestore']:
            key='merchant.operations.'+name
            for lang,value in fragment[key].items(): self.assertEqual(catalog[key]['localizations'][lang]['stringUnit']['value'],value)
