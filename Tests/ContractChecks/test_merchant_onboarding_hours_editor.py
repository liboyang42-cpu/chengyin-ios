"""Focused onboarding-hours wiring checks; no Swift runtime/Apple acceptance claim."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantOnboardingHoursEditorContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_existing_store_clock_parser_and_validator_are_reused(self):
        source = self.read('Core/MerchantOnboardingContracts.swift').split('public struct MerchantOnboardingHours:', 1)[1].split('public struct MerchantOnboardingImage:', 1)[0]
        self.assertIn('MerchantStoreHours(wireValue: wireValue)', source)
        self.assertIn('public var blocker: String? { storeHours.blocker }', source)
        self.assertIn('try storeHours.wireValue()', source)
        shared = self.read('Core/MerchantStoreHours.swift')
        self.assertIn('startMinutes != endMinutes', shared)
        self.assertIn('(overnight ? "次日" : "")', shared)

    def test_sheet_captures_current_draft_once_instead_of_defaulting_each_open(self):
        source = self.read('App/MerchantOnboardingView.swift')
        self.assertIn('hoursEditor = MerchantOnboardingHoursSession(model: model)', source)
        self.assertIn('showHours = hoursEditor != nil', source)
        self.assertIn('MerchantOnboardingHoursEditor(editor: hoursEditor)', source)
        self.assertNotIn('private struct MerchantOnboardingHoursView', source)
        editor = self.read('App/MerchantOnboardingHoursEditor.swift')
        self.assertIn('MerchantOnboardingHours(wireValue: model.draft.businessTime)', editor)
        self.assertIn('initialHours == hours ? originalValue : formatted', editor)
        self.assertIn('(!hasUnknownValue || edited)', editor)

    def test_apply_checks_identity_revision_original_draft_and_write_lock(self):
        source = self.read('App/MerchantOnboardingHoursEditor.swift')
        for token in ['!consumed', 'model.identity == identity', 'model.coordinator.identity == identity',
                      'model.revision == revision', 'model.draft == original', '!model.isBusy',
                      '!model.coordinator.submission.isLocked', 'model.confirmation == nil']:
            self.assertIn(token, source)
        self.assertIn('guard canApply, let formatted = try? hours.wireValue()', source)
        self.assertIn('if value != originalValue { model.draft.businessTime = value }', source)
        self.assertIn('func cancel() { consumed = true }', source)

    def test_local_clock_controls_never_use_dates_or_timezone_conversion(self):
        source = self.read('App/MerchantOnboardingHoursEditor.swift')
        for forbidden in ['DatePicker', 'Calendar.', 'TimeZone', 'Date(', 'URLSession', 'uploadLicense(', 'submitConfirmed(', 'Task {']:
            self.assertNotIn(forbidden, source)
        self.assertIn('ForEach(0..<(hour ? 24 : 60)', source)
        self.assertIn('ForEach(0..<7', source)

    def test_keys_and_explicit_history_cancel_and_zero_duration_cases_exist(self):
        fragment = json.loads(self.read('Resources/MerchantOnboardingHoursLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 3)
        self.assertEqual({key: json.loads(self.read('Resources/Localizable.xcstrings'))['strings'][key] for key in fragment}, fragment)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())
        tests = self.read('Tests/AppUnitTests/MerchantOnboardingHoursSessionTests.swift')
        for method in ['testCancelPreservesOriginalByteSequenceAfterLocalEdits',
                       'testNoOpApplyDoesNotNormalizeExistingDayOrderOrMinutes',
                       'testUnknownHistoricalFormatCannotApplyDefaultsWithoutExplicitEdit',
                       'testSourceReloadAccountChangeAndOtherDraftEditRejectStaleApply',
                       'testEmptyDraftUsesExplicitDefaultChoiceButRejectsZeroDuration']:
            self.assertIn('func ' + method, tests)

if __name__ == '__main__': unittest.main()
