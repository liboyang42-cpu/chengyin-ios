"""Small tag-picker source checks; not Swift compilation or runtime evidence."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantDecorTagPickerContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_only_decor_tag_section_mounts_picker_and_retains_legacy_editor(self):
        source = self.read('App/MerchantOperationsEditor.swift')
        self.assertEqual(source.count('MerchantDecorTagEditor(model: model)'), 1)
        section = source.split('case .decor(let value):', 1)[1].split('case .gallery', 1)[0]
        self.assertIn('MerchantDecorTagEditor(model: model)', section)
        self.assertIn('merchant.operations.field.tags', section)

    def test_original_values_are_not_normalized_or_truncated_on_open(self):
        source = self.read('Core/MerchantDecorTagDraft.swift')
        self.assertIn('public init(selected: [String]) { self.selected = selected }', source)
        self.assertIn('selected.count <= 12', source)
        self.assertIn('raw.utf16.count <= 16', source)
        self.assertIn('lhs.utf16.elementsEqual(rhs.utf16)', source)
        self.assertNotIn('.prefix(12)', source)
        self.assertNotIn('selected = Array(Set', source)

    def test_apply_checks_scope_identity_original_document_and_consumption(self):
        source = self.read('App/MerchantDecorTagEditor.swift')
        for token in ['!consumed', 'owner.isCurrent', '!owner.isBusy', '!owner.isLocked', 'owner.confirmation == nil',
                      'owner.reader.scope == scope', 'owner.draftIdentity == identity',
                      'owner.draft == .decor(original)', 'MerchantDecorTagDraft.equal(current.tags, original.tags)',
                      'guard isCurrent, draft.canApply else { return false }']:
            self.assertIn(token, source)
        apply = source.split('func apply() -> Bool {', 1)[1].split('func cancel()', 1)[0]
        self.assertLess(apply.index('consumed = true'), apply.index('document.edit(.decor(edited))'))
        self.assertIn('var edited = original; edited.tags = draft.selected', apply)
        self.assertIn('if MerchantDecorTagDraft.equal(draft.selected, original.tags) { return true }', apply)

    def test_only_explicit_local_apply_writes_document_and_cancel_is_permanent(self):
        source = self.read('App/MerchantDecorTagEditor.swift')
        self.assertEqual(source.count('document.edit('), 1)
        self.assertIn('func cancel() { consumed = true }', source)
        for token in ['onChange(of: model.coordinator.draftIdentity)', 'onChange(of: model.coordinator.reader.scope)',
                      'onChange(of: scenePhase)', 'onDisappear { close() }']:
            self.assertIn(token, source)
        for forbidden in ['URLSession', 'document.confirm(', 'saveReviewed(', 'request(', 'UserDefaults']:
            self.assertNotIn(forbidden, source)

    def test_bilingual_keys_and_authority_cases_are_present(self):
        fragment = json.loads(self.read('Resources/MerchantDecorTagLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 33)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual({key: catalog[key] for key in fragment}, fragment)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())
        tests = self.read('Tests/AppUnitTests/MerchantDecorTagPickerTests.swift')
        for method in ['testOpenEditAndCancelNeverChangeOriginalDocumentOrSend',
                       'testHistoricalOverLimitIsNotSilentlyTruncatedOrApplied',
                       'testConcurrentOtherFieldEditCannotBeOverwrittenByOldPicker',
                       'testReloadAccountSwitchAndDiscardInvalidateOldPicker',
                       'testFailedExistingSaveRetainsAppliedTagsForReopen']:
            self.assertIn('func ' + method, tests)

if __name__ == '__main__': unittest.main()
