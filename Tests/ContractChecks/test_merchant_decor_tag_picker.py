"""Small tag-picker source checks; not Swift compilation or runtime evidence."""
from pathlib import Path
import json
import hashlib
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantDecorTagPickerContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def assert_readonly_tag_entry(self, source):
        self.assertEqual(source.count('MerchantDecorTagEditor(model: model)'), 1)
        decor = source.split('case .decor(let value):', 1)[1].split('case .gallery', 1)[0]
        section = decor.split('Section("merchant.operations.tags") {', 1)[1].split(
            'mediaSection("merchant.operations.cover", field: .coverImage)', 1)[0]
        expected = r'''ForEach(Array(value.tags.enumerated()), id: \.offset) { index, tag in
                    Text(verbatim: tag)
                        .accessibilityIdentifier("merchant.operations.tags.value." + String(index))
                }
                MerchantDecorTagEditor(model: model)
            }'''
        # An exact small UI shape makes a reintroduced setter or hidden/truncated display fail.
        # This is source-contract coverage, not proof of SwiftUI rendering or behavior.
        self.assertEqual(section.split(), expected.split())
        self.assertNotRegex(source, r"\.tags\s*=")
        self.assertNotIn('merchant.operations.field.tags', source)
        self.assertNotIn('Text("merchant.operations.tagsHint")', decor)

    def test_only_decor_tag_section_mounts_picker_and_displays_literal_rows(self):
        self.assert_readonly_tag_entry(self.read('App/MerchantOperationsEditor.swift'))

    def test_readonly_entry_gate_rejects_raw_setter_and_lossy_display(self):
        source = self.read('App/MerchantOperationsEditor.swift')
        mutations = {
            'raw_setter': source.replace('MerchantDecorTagEditor(model: model)',
                'TextField("Tags", text: Binding(get: { "" }, set: { raw in value.tags = raw.components(separatedBy: ";") }))\nMerchantDecorTagEditor(model: model)'),
            'missing_picker': source.replace('MerchantDecorTagEditor(model: model)', ''),
            'truncation': source.replace('value.tags.enumerated()', 'value.tags.prefix(12).enumerated()'),
            'deduplication': source.replace('Array(value.tags.enumerated())', 'Array(Set(value.tags).enumerated())'),
            'sorting': source.replace('value.tags.enumerated()', 'value.tags.sorted().enumerated()'),
            'trim': source.replace('Text(verbatim: tag)', 'Text(verbatim: tag.trimmingCharacters(in: .whitespacesAndNewlines))'),
            'localized_data': source.replace('Text(verbatim: tag)', 'Text(LocalizedStringKey(tag))'),
            'hidden': source.replace('Text(verbatim: tag)', 'Text(verbatim: tag).hidden()'),
            'duplicate_identity': source.replace('id: \\.offset) { index, tag', 'id: \\.element) { index, tag'),
            'split_labels': source.replace('value.tags.enumerated()', 'value.tags.joined(separator: ";").components(separatedBy: ";").enumerated()'),
        }
        for name, changed in mutations.items():
            with self.subTest(name=name):
                self.assertNotEqual(changed, source)
                with self.assertRaises(AssertionError): self.assert_readonly_tag_entry(changed)

    def test_semicolon_and_historical_regression_cases_are_authored(self):
        core = self.read('Tests/CoreTests/MerchantDecorTagDraftTests.swift')
        app = self.read('Tests/AppUnitTests/MerchantDecorTagPickerTests.swift')
        for method in ['testSemicolonCustomLabelRemainsOneLiteralTag',
                       'testHistoricalLabelsRemainByteExactUntilExplicitRemoval']:
            self.assertIn('func ' + method, core)
        for method in ['testSemicolonTagApplyCancelAndReopenPreserveExactLabels',
                       'testDuplicateOverLimitHistoricalTagsStayUnchangedOnOpenCancelAndInvalidOwner']:
            self.assertIn('func ' + method, app)

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


# Only the reviewed merchant tag increment is inverted.
MERCHANT_SCANNER_CONTRACT_PREIMAGE = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'
MERCHANT_SCANNER_EDITOR_PREIMAGE = '3e1a134db3355e63c068fcb4ff5dbb5abc7d7ac00488c6548d9a054339e80e1f'
MERCHANT_SCANNER_SUPPORT_PREIMAGES = {'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift': 'caaae8dab10e8a9d69500cf1243d1b31311f0b8d4eda568a2dfc58c7ab10d0cc', 'Tests/ContractChecks/test_merchant_decor_tag_picker.py': '491182e97a8e53e1b3372c130d1a1f7857c10804302578a624c706d473e2fec7', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift': '5e90fd3657fd322477dc3c28347fb0efc3e33553ae39ef4bf990308bf445de86', 'docs/merchant-decor-tag-picker/implementation.md': '5d7d4a190a5b0146433d7e7d077789ce99fad2669f0a44798a067e7f1702b141'}
MERCHANT_SCANNER_TAG_HUNK = {'before': '            Section("merchant.operations.tags") {\n                TextField("merchant.operations.tags", text: Binding(get: { currentDecor?.tags.joined(separator: ";") ?? "" }, set: { raw in\n                    guard var value = currentDecor else { return }; value.tags = raw.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; model.edit(.decor(value))\n                }), axis: .vertical).accessibilityIdentifier("merchant.operations.field.tags")\n                Text("merchant.operations.tagsHint").font(.footnote).foregroundStyle(.secondary)\n                MerchantDecorTagEditor(model: model)\n            }\n', 'after': '            Section("merchant.operations.tags") {\n                ForEach(Array(value.tags.enumerated()), id: \\.offset) { index, tag in\n                    Text(verbatim: tag)\n                        .accessibilityIdentifier("merchant.operations.tags.value." + String(index))\n                }\n                MerchantDecorTagEditor(model: model)\n            }\n'}


def historical_scanner_contract_bytes(root=ROOT):
    """Admit the exact combined raw group, then recover the original scanner input."""
    root = Path(root)
    spec = importlib.util.spec_from_file_location(
        '_combined_profile_scanner_history',
        root / 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py')
    admission = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(admission)
    return admission.historical_readiness_contract(
        (root / admission.READINESS_PATH).read_bytes(), root)

if __name__ == '__main__': unittest.main()
