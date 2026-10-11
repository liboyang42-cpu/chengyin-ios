"""Bounded source checks only; not Swift, Apple, or backend execution."""
import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class BlindOptionsChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateBlindOptions.swift').read_text()
        cls.app = (ROOT / 'App/TemplateBlindOptionEditor.swift').read_text()
        cls.form = (ROOT / 'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.core_tests = (ROOT / 'Tests/CoreTests/TemplateBlindOptionsTests.swift').read_text()
        cls.app_tests = (ROOT / 'Tests/AppUnitTests/TemplateBlindOptionEditorTests.swift').read_text()

    def test_mounts_full_composer_and_preserves_prior_qa_and_rehearsal(self):
        for token in ['family == .blindTaste && field.id == "answerKey"', 'TemplateBlindOptionFields(model: model)',
                      'TemplateBlindOptions(model.draft.advanced).isSupported', 'creator.field.blindTaste.answerKey',
                      'TemplateQAAnswerFields(model: model)', 'TemplateCreatorRehearsalView', '.onMove', '.onDelete']:
            self.assertIn(token, self.form)
        for token in ['editor.text(row.id, .key)', 'editor.text(row.id, .label)', 'editor.chooseAction(row.id)',
                      'editor.removeAction(row.id)', 'editor.addAction()', 'editor.moveAction(row.id, row.id - 1)', 'editor.moveAction(row.id, row.id + 1)']:
            self.assertIn(token, self.app)

    def test_free_keys_and_row_limit_use_mini_contract(self):
        for token in ['rows.count < 6', '(values?.count ?? 0) <= 6', 'Array("ABCDEFGHIJ")',
                      'Set(rows.map(\\.key))', '!used.contains($0)', '"key": .string(key), "label": .string("")']:
            self.assertIn(token, self.core)
        add = self.core.split('case .add:', 1)[1].split('case .remove', 1)[0]
        self.assertNotIn('answerKey', add)

    def test_rename_and_delete_follow_existing_answer_key_atomically(self):
        for token in ['case .updateKey(let index, let text)', '== previousKey', 'fields["answerKey"] = .string(text)',
                      'case .remove(let index)', '== (removed["key"]?.string ?? "")',
                      'values.first?.object?["key"]?.string ?? ""', 'fields["answerKey"] = .string(rows[index].key)',
                      'fields["options"] = .array(values)', 'next.value["blindTaste"] = .object(fields)']:
            self.assertIn(token, self.core)

    def test_snapshot_shapes_selection_and_unknown_field_preservation(self):
        for token in ['fingerprint == Self.snapshot(draft)', 'encoder.encode(value)', '.sortedKeys',
                      'stringOrMissing', 'TemplateCreatorSchema.keyPattern', 'rows.filter { $0.key == key }.count == 1',
                      'var row = values[index].object!', 'values.indices.contains(index)']:
            self.assertIn(token, self.core)
        self.assertNotIn('TemplateCreatorSchema.defaults', self.core)

    def test_current_typing_and_stale_controls_have_distinct_fences(self):
        for token in ['model.objectWillChange.sink', 'self.actionGeneration = UUID()',
                      'if !self.writingText { self.textGeneration = UUID() }', 'self.textGeneration == stamp',
                      'self.writingText = true', 'defer { self.writingText = false }',
                      'self.actionGeneration == stamp', 'self.model.metadataGeneration == metadata',
                      'model.coordinator.session == session', 'model.coordinator.identity == identity',
                      'model.mediaReviewGeneration == mediaGeneration', 'model.canEdit',
                      '.onAppear { editor.reload() }', '.onDisappear { editor.retire() }', '@Published private var active']:
            self.assertIn(token, self.app)

    def test_no_new_production_services_schema_or_storage(self):
        for token in ['URLSession', 'HTTPTransport', 'UserDefaults', 'savePending(', 'capabilityGrant', 'factory', 'publish(']:
            self.assertNotIn(token, self.core + self.app)
        self.assertIn('model.changed()', self.app)

    def test_bilingual_and_registration_fragments(self):
        strings = json.loads((ROOT / 'docs/localization/template-blind-options.json').read_text())['strings']
        keys = set(re.findall(r'"(templateBlindOptions\.[^"\\]+)"', self.app))
        self.assertTrue(keys <= set(strings), keys - set(strings))
        for suffix in ['optionNumber', 'removeNumber']:
            self.assertIn('templateBlindOptions.' + suffix + ' %lld', strings)
        for entry in strings.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])
        registration = json.loads((ROOT / 'docs/registration/template-blind-options.json').read_text())
        for key in ['app_sources', 'app_unit_tests', 'package_tests']:
            for path in registration[key]:
                self.assertTrue((ROOT / path).is_file())

    def test_native_tests_cover_complete_user_flow_and_recovery(self):
        for token in ['testAddUsesFirstFreeLetterAndDoesNotChangeAnswer', 'testMaximumSixOptionsAndCustomKeysDoNotCollide',
                      'testSelectedKeyFollowsRenameWhileOtherKeyAndLabelDoNotChangeAnswer',
                      'testDeleteSelectedFallsBackToFirstRemainingAndLastRemovalClearsAnswer',
                      'testSerializationLocalRestoreAndExistingRehearsalShareTheChosenKey']:
            self.assertIn(token, self.core_tests)
        for token in ['testAddEditChooseRenameDeleteCompleteFlow', 'testRepeatedKeyAndLabelTypingKeepsCurrentRowsStable',
                      'testNativeSaveFreshRestoreAndLocalRehearsalUseResultingAnswer',
                      'testExternalReorderAndSameValueABAInvalidateFieldsBeforeParentOnChange',
                      'testLoadRestoreDiscardLeaveAndOwnerChangeRejectRetainedControls',
                      'testDurablePendingWriteLockRejectsOptionMutation']:
            self.assertIn(token, self.app_tests)

if __name__ == '__main__':
    unittest.main()
