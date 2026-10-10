"""Source-only contracts. These checks do not execute Swift, SwiftUI or Apple tests."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = (ROOT / 'Core/TemplatePreferenceRemoval.swift').read_text()
CONTROL = (ROOT / 'App/TemplatePreferenceRemovalController.swift').read_text()
UI = (ROOT / 'App/TemplatePreferenceRemovalPanel.swift').read_text()
HOST = (ROOT / 'App/TemplatePreferenceDraftEditor.swift').read_text()
MODEL = (ROOT / 'App/TemplateAuthoringView.swift').read_text()


class PreferenceRemovalContracts(unittest.TestCase):
    def test_existing_local_editor_is_the_only_entry(self):
        self.assertEqual(HOST.count('TemplatePreferenceRemovalPanel(model: model)'), 1)
        self.assertIn('model.draft.id == nil', HOST)
        self.assertIn('model.draft.validationMethod == .preference', HOST)

    def test_projection_never_reserializes_source_or_repairs_results(self):
        self.assertIn('bytes.removeSubrange(range)', CORE)
        self.assertIn('source.utf8.elementsEqual(currentSource.utf8)', CORE)
        self.assertIn('_ = try Self(source: result)', CORE)
        for forbidden in ['JSONSerialization', 'JSONEncoder', 'Double(', 'Int(token', '"results"] =', '"tiebreak"] =']:
            self.assertNotIn(forbidden, CORE)

    def test_each_removal_keeps_the_structural_minimum(self):
        for text in ['questions.count > 1', 'options.count > 2', 'minimum = 1', 'minimum = 2',
                     'rows.count > minimum', 'rows.indices.contains(index)', 'steps.indices.contains(question)']:
            self.assertIn(text, CORE)
        self.assertIn('.disabled(!document.canRemoveQuestion)', UI)
        self.assertIn('.disabled(!question.canRemoveOption)', UI)

    def test_parser_is_bounded_and_duplicate_keys_cannot_collapse(self):
        for text in ['1_048_576', 'depth <= 64', 'nodeCount <= 20_000', '(1...128)', '(2...64)',
                     'optionCount <= 512', 'members[key] == nil', 'Data(try quoted().utf8)',
                     'case object([Data: PreferenceRemovalNode])', 'offset == bytes.count']:
            self.assertIn(text, CORE)

    def test_first_middle_last_delete_one_separator_only(self):
        self.assertIn('rows[index].range.lowerBound..<rows[index + 1].range.lowerBound', CORE)
        self.assertIn('rows[index - 1].range.upperBound..<rows[index].range.upperBound', CORE)

    def test_open_is_explicit_and_captures_owner_lifecycle_source(self):
        self.assertIn('let capture = controller.capture()', UI)
        self.assertIn('controller.open(capture)', UI)
        for text in ['capture.controller == identity', 'capture.generation == generation',
                     'capture.editorGeneration == model.metadataGeneration',
                     'capture.session == model.coordinator.session', 'capture.identity == model.coordinator.identity',
                     '$0.utf8.elementsEqual(capture.source.utf8)', 'model.canEdit', 'model.draft.finishEnabled', 'model.draft.id == nil']:
            self.assertIn(text, CONTROL)
        self.assertEqual(CONTROL.count('try? .init(source: capture.source)'), 1)

    def test_existing_editor_generation_rotates_at_required_boundaries(self):
        for name in ['load', 'changed', 'restore', 'discard', 'prepare', 'leave']:
            body = MODEL.split('func ' + name + '(')[1].split('\n    func ')[0]
            self.assertIn('metadataGeneration = UUID()', body, name)

    def test_current_review_is_required_and_retired_before_one_commit(self):
        confirm = CONTROL.split('@discardableResult func confirm')[1].split('func close')[0]
        for text in ['isCurrent(original)', 'review?.id == intent.id', 'intent.presentationID == original.id',
                     'document.removing(intent.target, from: source)']:
            self.assertIn(text, confirm)
        self.assertIn('retire(); model.draft.preferenceJson = next; model.changed()', confirm)
        self.assertEqual(CONTROL.count('model.draft.preferenceJson ='), 1)
        self.assertIn('guard presentation?.id == original.id else { return }; retire()', CONTROL)

    def test_cancel_disappear_and_generation_changes_retire_only_local_review(self):
        self.assertIn('controller.cancel(intent, in: original)', UI)
        self.assertIn('.onDisappear { controller.retire() }', UI)
        self.assertIn('.onDisappear { controller.close(original) }', UI)
        for field in ['model.metadataGeneration', 'model.coordinator.session', 'model.coordinator.identity']:
            self.assertIn('.onChange(of: ' + field + ')', UI)
        self.assertIn('.id(controller.review?.id ?? original.id)', UI)

    def test_no_network_storage_or_remote_enablement_is_added(self):
        for forbidden in ['URLSession', 'URLRequest', 'api/', '.saveLocal(', '.save(', '.submit(', '.publish(', 'UserDefaults', 'canSubmit =']:
            self.assertNotIn(forbidden, CORE + CONTROL + UI)
        contract = (ROOT / 'Core/TemplateAuthoringContract.swift').read_text()
        self.assertIn('!draft.validationMethod.isLocalConfigurationOnly', contract)
        self.assertIn('!d.validationMethod.isLocalConfigurationOnly', contract)

    def test_named_bilingual_catalog_covers_all_text_and_warns_about_recheck(self):
        catalog = json.loads((ROOT / 'Resources/TemplatePreferenceRemoval.xcstrings').read_text())
        keys = {'preferenceRemoval.' + x for x in re.findall(r'text\("(\w+)"\)', UI)}
        keys |= {'preferenceRemoval.open', 'preferenceRemoval.title'}
        self.assertEqual(keys, set(catalog['strings']))
        self.assertEqual(catalog['sourceLanguage'], 'en')
        for entry in catalog['strings'].values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for locale in entry['localizations'].values():
                self.assertEqual(locale['stringUnit']['state'], 'translated')
                self.assertTrue(locale['stringUnit']['value'].strip())
        self.assertIn('Check JSON again', catalog['strings']['preferenceRemoval.recheck']['localizations']['en']['stringUnit']['value'])
        self.assertNotIn('TemplatePreferenceRemoval(source:', UI)

    def test_authored_regressions_cover_boundaries_and_stale_actions(self):
        core_tests = (ROOT / 'Tests/CoreTests/TemplatePreferenceRemovalTests.swift').read_text()
        app_tests = (ROOT / 'Tests/AppUnitTests/TemplatePreferenceRemovalLifecycleTests.swift').read_text()
        for name in ['FirstMiddleLast', 'MinimumOneQuestionAndTwoOptions', 'ExactSourceRejects',
                     'DuplicateEscapedKeys', 'CanonicalDistinctUnknownKeys', 'DepthBytesAndProjectionBudgets']:
            self.assertIn(name, core_tests)
        for name in ['OpenRequestCancelAndClose', 'ExplicitCurrentConfirmation', 'CancelledReview',
                     'ReopenedSameBytes', 'SameByteABA', 'LoadRestoreDiscardAndLeave',
                     'AccountEpochRoleNamespaceAndLogout', 'OwnerABA', 'MethodFinishAndExistingTemplate',
                     'ConcurrentControllers', 'RemotePreparationStillRejects']:
            self.assertIn(name, app_tests)


if __name__ == '__main__':
    unittest.main()
