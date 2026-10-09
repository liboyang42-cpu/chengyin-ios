"""Narrow source checks for a reversible local featured-clear edit, not Swift execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantFeaturedClearContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_existing_editor_mount_and_frozen_review_are_explicit(self):
        source = self.read('App/MerchantOperationsEditor.swift')
        self.assertIn('MerchantFeaturedClearControl(model: model, source: value)', source)
        self.assertIn('if case .decor(let value) = confirmation.draft, value.featuredType == 0, value.featuredID == nil', source)
        self.assertIn('merchant.featuredClear.review', source)
        self.assertNotIn('Text("merchant.operations.decorPreserved")', source)

    def test_clear_and_restore_check_same_read_and_original_draft(self):
        source = self.read('App/MerchantFeaturedClearControl.swift')
        for token in ['owner.isCurrent', '!owner.isBusy', '!owner.isLocked', 'owner.confirmation == nil',
                      'owner.reader.scope == scope', 'owner.draftIdentity == identity',
                      'owner.baseline == .decor(baseline)', 'owner.draft == .decor(source)',
                      'guard isCurrent, !isCleared', 'guard isCurrent, canRestore, let baseline']:
            self.assertIn(token, source)
        self.assertIn('var edited = source; edited.featuredType = 0; edited.featuredID = nil', source)
        self.assertIn('edited.featuredType = baseline.featuredType; edited.featuredID = baseline.featuredID', source)

    def test_missing_type_does_not_become_explicit_clear(self):
        source = self.read('Core/MerchantOperationsContracts.swift')
        self.assertIn('featuredType = c.merchantInteger(.featuredType)', source)
        self.assertIn('&& !(featuredType == 0 && featuredID == nil) { return "merchant.operations.decorEmpty" }', source)
        self.assertNotIn('featuredType = c.merchantInteger(.featuredType) ?? 0', source)
        self.assertIn('"featuredType": featuredType as Any? ?? NSNull()', source)
        self.assertIn('"featuredId": featuredID as Any? ?? NSNull()', source)

    def test_only_local_edit_no_direct_save_or_new_request(self):
        source = self.read('App/MerchantFeaturedClearControl.swift')
        self.assertEqual(source.count('model.edit(.decor(edited))'), 2)
        for forbidden in ['Task {', 'URLSession', 'saveReviewed(', 'model.confirm(', 'request(', 'UserDefaults']:
            self.assertNotIn(forbidden, source)
        tests = self.read('Tests/AppUnitTests/MerchantFeaturedClearControlTests.swift')
        for method in ['testRestoreCannotCrossReloadEvenWhenReadValuesMatch', 'testAccountSwitchAndDiscardInvalidateCapturedControls',
                       'testFrozenReviewKeepsZeroNullAndCancelDoesNotSave', 'testUnknownSaveLockPreventsClearAndRestore']:
            self.assertIn('func ' + method, tests)

    def test_unique_bilingual_keys_and_empty_payload_negative_cases(self):
        fragment = json.loads(self.read('Resources/MerchantFeaturedClearLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 5)
        self.assertEqual({key: json.loads(self.read('Resources/Localizable.xcstrings'))['strings'][key] for key in fragment}, fragment)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())
        tests = self.read('Tests/CoreTests/MerchantFeaturedClearContractTests.swift')
        self.assertIn('testMissingAndNullTypeRemainEmptyInsteadOfDefaultingToClear', tests)
        self.assertIn('testClearDoesNotAllowConflictingIDOrOversizedGallery', tests)

if __name__ == '__main__': unittest.main()
