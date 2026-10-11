"""Focused source checks, not Swift/Apple or live branch execution."""
import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class BranchCompositionChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateBranchComposition.swift').read_text()
        cls.app=(ROOT/'App/TemplateBranchCompositionFields.swift').read_text()
        cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplateBranchCompositionTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplateBranchCompositionControllerTests.swift').read_text()
    def test_three_coupled_actions_mounted_in_existing_forms(self):
        for token in ['TemplateBranchTerminalFields(model: model, stepIndex: index).id(step.id)','TemplateBranchAddRowButton(model: model)','TemplateBranchAddRowButton(model: model, stepIndex: index).id(step.id)','branchComposition.isSupported','case .toggle','addCreatorRow(family, path: path, field: field)']:
            self.assertIn(token,self.form)
    def test_terminal_and_option_fields_are_mutually_visible_for_supported_steps(self):
        for token in ['path.count == 3','path[0] == .field("steps")','if let step = branchStep','["outcomeCode", "outcomeLabel"].contains(field.id) && !step.terminal','field.id == "options" && step.terminal']:
            self.assertIn(token,self.form)
        for token in ['templateBranch.terminalHint','if editor.terminal','templateBranch.continueWithChoice']:
            self.assertIn(token,self.app)
    def test_source_terminal_defaults_and_atomic_choice_clearing(self):
        for token in ['case .addStep','"terminal": .bool(true)','"outcomeCode": .string("COMPLETED")','defaultOutcomeLabel = "完成节点"','row["options"] = .array([])','title.isEmpty ? Self.defaultOutcomeLabel : title']:
            self.assertIn(token,self.core)
        self.assertNotIn('trimmingCharacters',self.core)
    def test_add_choice_atomically_switches_parent_and_keeps_contract_limits(self):
        for token in ['steps.count < 50','$0.optionCount < 12','options.count <= 12','"nextStepId": .string("")','"score": .number(0)','row["options"] = .array(options); row["terminal"] = .bool(false)','used.insert(id).inserted']:
            self.assertIn(token,self.core)
    def test_existing_content_ordering_validation_and_rehearsal_are_reused(self):
        for token in ['.onDelete','.onMove','TemplateCreatorRehearsalView','TemplateCreatorSchema.fields(family)','case .stateValue']:
            self.assertIn(token,self.form)
        for token in ['URLSession','HTTPTransport','factory','submit(','UserDefaults']:
            self.assertNotIn(token,self.core+self.app)
        self.assertNotIn('set("branch", "startStepId"',self.core)
    def test_owner_id_and_same_value_publication_guards(self):
        for token in ['model.objectWillChange.sink','self.generation == stamp','snapshot.applying(edit','self.model.metadataGeneration == metadata','model.coordinator.session == session','model.coordinator.identity == identity','mediaGeneration == model.mediaReviewGeneration','projection.steps[stepIndex].id == stepID','.onDisappear { editor.retire() }']:
            self.assertIn(token,self.app)
        self.assertIn('fingerprint == Self.snapshot(draft)',self.core)
    def test_bilingual_fragments_and_registration(self):
        strings=json.loads((ROOT/'docs/localization/template-branch-composition.json').read_text())['strings']
        keys=set(re.findall(r'"(templateBranch\.[^"\\]+)"',self.app));self.assertTrue(keys<=set(strings),keys-set(strings))
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-branch-composition.json').read_text())
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_native_coverage_is_a_complete_edit_and_restore_chain(self):
        for token in ['testAddStepUsesMiniDefaultsAndNeverRewritesStartReference','testTerminalTransitionClearsChoicesAndSuppliesOutcomeFromTitle','testCompleteGraphUsesExistingValidationSerializationAndLocalRehearsal','testNewStepContinueWithChoiceEditThenTerminalCompleteFlow','testExternalTextChangeAndSameValueABARetireActions','testStepIdentityAndReorderCannotRetargetCapturedControllerAfterReload','testLocalSaveAndRestoreKeepTerminalOutcomeAndClearedChoices','testPendingLockDeniesRootAndStepChanges']:
            self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
