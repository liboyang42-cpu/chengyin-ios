"""Bounded source contracts; does not execute Swift, SwiftUI, or a backend."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class QAAnswerSelectionChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateQAAnswerSelection.swift').read_text()
        cls.app = (ROOT / 'App/TemplateQAAnswerEditor.swift').read_text()
        cls.form = (ROOT / 'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.core_tests = (ROOT / 'Tests/CoreTests/TemplateQAAnswerSelectionTests.swift').read_text()
        cls.app_tests = (ROOT / 'Tests/AppUnitTests/TemplateQAAnswerEditorTests.swift').read_text()

    def test_answer_overview_is_mounted_in_existing_qa_form(self):
        for token in ['family == .qa && field.id == "multi" && path == [.field("multi")]',
                      'TemplateQAAnswerFields(model: model)', 'text("qa", "mode") == "PICK"',
                      'field.id == "correct" && TemplateQAAnswerSelection(model.draft.advanced).isSupported',
                      'if !TemplateQAAnswerSelection(model.draft.advanced).isSupported { control']:
            self.assertIn(token, self.form)
        for token in ['case .rows', '.onDelete', '.onMove', 'addCreatorRow', 'TemplateCreatorRehearsalView']:
            self.assertIn(token, self.form)

    def test_single_multi_and_first_correct_retention_use_existing_fields(self):
        for token in ['case .choose(let index)', 'row["correct"] = .bool(offset == index)',
                      'row["correct"] = .bool(!(row["correct"]?.bool ?? false))',
                      'case .setMultiple(let enabled)', 'fields["multi"] = .bool(enabled)',
                      'var kept = false', '&& !kept', 'if correct { kept = true }',
                      'next.value["qa"] = .object(fields)']:
            self.assertIn(token, self.core)
        self.assertNotIn('TemplateCreatorSchema.defaults', self.core)
        self.assertNotIn('normalize', self.core.split('public init', 1)[1])

    def test_exact_snapshot_and_shape_boundaries(self):
        for token in ['fingerprint == Self.snapshot(draft)', 'encoder.encode(value)', '.sortedKeys',
                      '(rows?.count ?? 0) <= 4', 'booleanOrMissing', 'rows.indices.contains(index)',
                      'fields?["enabled"]?.bool == true', 'fields?["mode"]?.string == "PICK"']:
            self.assertIn(token, self.core)

    def test_callbacks_are_lifecycle_scoped_and_retire_synchronously(self):
        for token in ['model.objectWillChange.sink', 'self?.generation = UUID()',
                      '@Published private var active', 'active && model.canReadStoryDraft',
                      'model.coordinator.session == session', 'model.coordinator.identity == identity',
                      'model.mediaReviewGeneration == mediaGeneration', 'self.canEdit',
                      'self.generation == stamp', 'self.model.metadataGeneration == metadata',
                      'self.model.changed()', '.onAppear { editor.reload() }',
                      '.onDisappear { editor.retire() }', '.onChange(of: model.mediaReviewGeneration)']:
            self.assertIn(token, self.app)

    def test_no_new_services_storage_schema_or_submission_calls(self):
        for token in ['URLSession', 'HTTPTransport', 'capabilityGrant', 'publish(', 'savePending(',
                      'UserDefaults', 'makePlayer', 'factory', 'import AVFoundation']:
            self.assertNotIn(token, self.core + self.app)
        self.assertIn('next != self.model.draft.advanced', self.app)

    def test_localization_and_registration_fragments_cover_new_ui(self):
        fragment = json.loads((ROOT / 'docs/localization/template-qa-answer-selection.json').read_text())['strings']
        keys = set(re.findall(r'"(templateQAAnswers\.[^"\\]+)"', self.app))
        self.assertTrue(keys <= set(fragment), keys - set(fragment))
        self.assertIn('templateQAAnswers.optionNumber %lld', fragment)
        for key, entry in fragment.items():
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][lang]['stringUnit']['value'], (key, lang))
        registration = json.loads((ROOT / 'docs/registration/template-qa-answer-selection.json').read_text())
        for key in ['app_sources', 'app_unit_tests', 'package_tests']:
            for path in registration[key]:
                self.assertTrue((ROOT / path).exists(), path)

    def test_authored_native_tests_cover_complete_flow_and_fences(self):
        for token in ['testSingleChoiceSelectsExactlyOneAndCannotUncheckItself',
                      'testMultipleChoiceCanSelectAndUnselectIndependently',
                      'testTurningMultipleOffKeepsFirstCorrectWithoutInventingOne',
                      'testOnlyAnswerFlagsChangeAndFutureFieldsRemainVerbatim',
                      'testUnsupportedShapesRemainUnchanged',
                      'testExistingSerializationRestoreAndRehearsalUseConfiguredAnswers']:
            self.assertIn(token, self.core_tests)
        for token in ['testSingleMultiAndBackToSingleFollowCompleteAnswerFlow',
                      'testLocalSaveAndFreshRestoreKeepChoicesForExistingRehearsal',
                      'testStaleChoicesAndModeBindingsRejectImmediatelyBeforeOnChangeRuns',
                      'testEditingAddingReorderingAndRemovingExistingOptionsRefreshesOverview',
                      'testLoadRestoreDiscardOwnerAndDismissalFenceRetainedCallbacks',
                      'testDurablePendingWriteLockRejectsAnswerChanges']:
            self.assertIn(token, self.app_tests)

if __name__ == '__main__':
    unittest.main()
