#!/usr/bin/env python3
"""Focused source contracts only: never reports Swift compilation or execution."""
from pathlib import Path
import json
import re
import sys
import unittest

ROOT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else Path(__file__).resolve().parents[2]
CORE = (ROOT / 'Core/TemplateProfileOverrideConfiguration.swift').read_text()
APP = (ROOT / 'App/TemplateProfileOverrideEditor.swift').read_text()
HOST = (ROOT / 'App/TemplateCreatorConfigurationView.swift').read_text()
CORE_TEST = (ROOT / 'Tests/CoreTests/TemplateProfileOverrideConfigurationTests.swift').read_text()
APP_TEST = (ROOT / 'Tests/AppUnitTests/TemplateProfileOverrideEditorTests.swift').read_text()
LOC = json.loads((ROOT / 'docs/localization/template-profile-override.json').read_text())['strings']
REG = json.loads((ROOT / 'docs/registration/template-profile-override.json').read_text())
DOC = (ROOT / 'docs/template-profile-override.md').read_text()

class ProfileOverrideSourceContracts(unittest.TestCase):
    def test_exact_host_entry_retains_generic_kind_editor(self):
        self.assertEqual(HOST.count('NavigationLink("templateProfileOverride.title")'), 1)
        self.assertIn('if profileComposition.questions[index].kind == "pick" {', HOST)
        self.assertIn('questionKey: profileComposition.questions[index].key', HOST)
        self.assertIn('TemplateProfileKindFields(model: model, questionIndex: index)', HOST)

    def test_only_existing_override_key_is_written(self):
        self.assertIn('question["override"] = .object(override)', CORE)
        self.assertIn('question.removeValue(forKey: "override")', CORE)
        self.assertNotRegex(CORE, r'\["kaccha"\]\s*=')
        self.assertEqual(CORE.count('next.advanced.set('), 1)
        self.assertIn('next.advanced.set("profile", "questions", .array(rows))', CORE)
        self.assertIn('var next = draft;', CORE)

    def test_known_single_gte_rule_is_required_for_safe_editor(self):
        for fragment in ['requires.count == 1', 'Set(when.keys) == ["op", "var", "value"]', 'when["op"]?.string == "GTE"', 'Set(override.keys).isSubset(of: ["requires", "option", "voice"])']:
            self.assertIn(fragment, CORE)

    def test_real_boolean_and_pick_option_shape_gates(self):
        self.assertIn('if case .bool(true)? = profile?["enabled"]', CORE)
        self.assertIn('question?["kind"]?.string == "pick"', CORE)
        self.assertIn('(2...6).contains(items.count)', CORE)
        self.assertIn('composition.isSupported', CORE)

    def test_threshold_namespace_option_and_utf16_constraints(self):
        for fragment in ['(clue|relation|counter)', 'number.isFinite', '(-99...99).contains(number)', 'number.rounded() == number', 'options.contains(where:', '.utf16.count > 120', 'TemplateAuthoringStory.sourceTrim']:
            self.assertIn(fragment.replace('number.isFinite', 'value.isFinite'), CORE)
        self.assertIn('text.isEmpty ? 0 : Double(text)', CORE)

    def test_full_draft_and_stable_question_key_fence(self):
        for fragment in ['encoder.encode(draft)', '.sortedKeys', '.withoutEscapingSlashes', 'isCurrent(draft)', 'question["key"]?.string == questionKey', 'rows.indices.contains(index)']:
            self.assertIn(fragment, CORE)

    def test_field_updates_are_staged_without_model_writes(self):
        stage = APP.split('private func update(',1)[1].split('func applyAction',1)[0]
        self.assertIn('form = next', stage)
        self.assertNotIn('model.draft =', stage)
        self.assertNotIn('model.save()', stage)
        self.assertIn('form.enabled else { return }', APP)
        self.assertIn('self.generation == stamp', APP)

    def test_apply_and_save_use_real_existing_model_and_store_feedback(self):
        self.assertEqual(APP.count('self.model.draft = next'), 1)
        self.assertIn('self.model.changed()', APP)
        self.assertIn('if save { self.model.save() }', APP)
        self.assertIn('self.model.coordinator.messageKey', APP)
        self.assertIn('save ? self.canSave : self.canApply', APP)

    def test_inactive_cache_and_reload_lifecycle_are_explicit(self):
        self.assertIn('staged.enabled ? self.configuration?.initialForm : staged', APP)
        self.assertIn('form = value.initialForm', APP)
        self.assertIn('form = nil', APP)
        self.assertIn('.onDisappear { controller.retire() }', APP)
        self.assertIn('phase == .active { controller.reload() } else { controller.retire() }', APP)

    def test_owner_identity_metadata_media_and_external_aba_fences(self):
        for fragment in ['owner == model.coordinator.session', 'identity == model.coordinator.identity', 'metadata == model.metadataGeneration', 'media == model.mediaReviewGeneration', '!model.busy', 'model.review == nil', 'model.objectWillChange.sink', 'if !self.writing { self.retire() }']:
            self.assertIn(fragment, APP)

    def test_no_remote_permission_execution_or_central_writes(self):
        self.assertNotRegex(CORE + APP, r'URLSession|CLLocationManager|AVAudioSession|PHPhotoLibrary|requestAuthorization|coordinator\.confirm|model\.prepare|awardReward|completeTask')
        self.assertTrue(REG['central_registration'].startswith('INTEGRATED_IN_THIS_CANDIDATE:'))
        self.assertEqual(REG['active_catalog'], 'Resources/TemplateProfileOverride.xcstrings')

    def test_localization_covers_every_displayed_key(self):
        used = set(re.findall(r'"(templateProfileOverride\.[A-Za-z]+)"', CORE + APP)) - {'templateProfileOverride.close', 'templateProfileOverride.message'}
        self.assertEqual(used, set(LOC))
        self.assertEqual(len(LOC), 25)
        self.assertTrue(all(set(value['localizations']) == {'zh-Hans','en'} and all(row['stringUnit']['value'] for row in value['localizations'].values()) for value in LOC.values()))
        self.assertIn('{picked}', LOC['templateProfileOverride.voiceHint']['localizations']['en']['stringUnit']['value'])
        self.assertIn('{assigned}', LOC['templateProfileOverride.voiceHint']['localizations']['zh-Hans']['stringUnit']['value'])

    def test_native_inventory_and_registration_are_explicit(self):
        self.assertEqual(len(re.findall(r'func test\w+\(', CORE_TEST)), 20)
        self.assertEqual(len(re.findall(r'func test\w+\(', APP_TEST)), 16)
        self.assertEqual(len(REG['app_sources']), 2)
        self.assertEqual(len(REG['package_tests']) + len(REG['app_unit_tests']), 2)
        self.assertEqual(REG['native_status'], 'NOT_RUN')
        for name in ['testStorageFailureRetainsAppliedDraftAndExplicitRetrySucceeds', 'testWholeDraftABARejectsEarlierActionAfterReload', 'testBackgroundReentryDiscardsUnappliedStageButKeepsAppliedDraft', 'testComplexManualOverrideRemainsReadOnlyAndCannotBeDeletedOrSaved']:
            self.assertIn(name, APP_TEST)

    def test_documentation_identifies_source_differences_and_limits(self):
        for fragment in ['95e499471eaa39c28f77d16125f0cc17b8c37123', 'adfbde7c2030070f25a1fa7ff89f89ed93307d11', 'Mini itself has no additional threshold bound', 'NOT_RUN', 'unapplied', 'generic editor', 'No private module']:
            self.assertIn(fragment, DOC)

if __name__ == '__main__':
    unittest.main(verbosity=2)
