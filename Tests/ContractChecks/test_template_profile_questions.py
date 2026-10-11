"""Focused source checks; not Swift/Apple or production profile execution."""
import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class ProfileQuestionChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateProfileQuestionComposition.swift').read_text()
        cls.app=(ROOT/'App/TemplateProfileQuestionFields.swift').read_text()
        cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplateProfileQuestionCompositionTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplateProfileQuestionControllerTests.swift').read_text()
    def test_supported_profile_lists_and_kind_delegate_existing_row_content(self):
        for token in ['else if usesProfileRows','TemplateProfileQuestionRowsEditor(model: model, questionIndex: profileQuestionIndex)','TemplateProfileKindFields(model: model, questionIndex: index)','profileComposition.isSupported','TemplateCreatorFieldsView(model: model, family: family, fields: fields, path: path + [.index(index)])']:
            self.assertIn(token,self.form)
        for token in ['rowContent(index)','@ViewBuilder rowContent:','editor.kindBinding()']:
            self.assertIn(token,self.app)
    def test_source_question_defaults_and_global_key_allocator(self):
        for token in ['questions.count + 1','"maxLength": .number(12), "required": .bool(true)','questions.flatMap { $0.options.map(\\.key) }','Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")','"opt" + String(index - letters.count + 1)','used.insert(key).inserted']:
            self.assertIn(token,self.core)
    def test_kind_transition_preserves_valid_lists_and_forces_required(self):
        for token in ['row["kind"] = .string(kind); row["required"] = .bool(true)','kind == "pick", questions[index].options.count < 2','nextOptionKeys(2)','"effects": .array([])']:
            self.assertIn(token,self.core)
        self.assertNotIn('removeValue(forKey: "options")',self.core)
        self.assertIn('templateProfile.kindHint',self.app)
    def test_count_guards_apply_to_batch_removal_and_ordering(self):
        for token in ['questions.count < 8','$0.options.count < 6','minimum: 1','minimum: 2','rows.count - selected.count >= minimum','selected.count == indexes.count','destination - selected.filter { $0 < destination }.count']:
            self.assertIn(token,self.core)
        for token in ['.onDelete(perform: editor.removeAction())','.onMove(perform: editor.moveAction())','.deleteDisabled(!editor.canRemove)']:
            self.assertIn(token,self.app)
    def test_exact_snapshots_and_owner_question_lifecycle_guards(self):
        for token in ['fingerprint == Self.snapshot(draft)','next.set("profile", "questions", .array(rows))']:
            self.assertIn(token,self.core)
        for token in ['model.objectWillChange.sink','self.generation == stamp','self.model.metadataGeneration == metadata','projection.questions[questionIndex].key == questionKey','model.coordinator.session == session','model.coordinator.identity == identity','mediaGeneration == model.mediaReviewGeneration','.onDisappear { editor.retire() }']:
            self.assertIn(token,self.app)
    def test_no_new_server_effect_or_override_policy(self):
        for token in ['URLSession','HTTPTransport','UserDefaults','factory','submit(','kaccha','row["override"] =']:
            self.assertNotIn(token,self.core+self.app)
        self.assertIn('model.changed()',self.app)
        self.assertIn('TemplateCreatorRehearsalView',self.form)
    def test_bilingual_fragments_and_registration(self):
        strings=json.loads((ROOT/'docs/localization/template-profile-questions.json').read_text())['strings']
        keys=set(re.findall(r'"(templateProfile\.[^"\\]+)"',self.app));self.assertTrue(keys<=set(strings),keys-set(strings))
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-profile-questions.json').read_text())
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_native_coverage_includes_complete_content_preservation_and_restore(self):
        for token in ['testGlobalKeyAllocationIncludesRetainedTextQuestionOptions','testKeyAllocatorContinuesAfterAlphabetAndFillsHoles','testOptionCountLimitsAndBatchRemovalPreserveMinimumTwo','testAddQuestionsSwitchKindsAndAllocateDistinctChoicesEndToEnd','testKindRoundTripRetainsLabelsAndEffectsThroughExistingFieldWrites','testQuestionReorderCannotRetargetAnOpenOptionListEvenAfterReload','testLocalSaveRestoreKeepsQuestionKindsAndGlobalKeys','testPendingWriteLockDeniesQuestionsKindsAndOptions']:
            self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
