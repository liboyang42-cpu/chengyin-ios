"""Supplementary authoring contract checks. No Apple execution is implied."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class CreatorRootAuthoringChecks(unittest.TestCase):
    @classmethod
    def setUpClass(c):
        c.model=(ROOT/'Core/TemplateRootAuthoring.swift').read_text()
        c.legacy=(ROOT/'Core/TemplateLegacyVariantAuthoring.swift').read_text()
        c.view=(ROOT/'App/TemplateRootAuthoringView.swift').read_text()
        c.preview=(ROOT/'App/TemplateRootRehearsalView.swift').read_text()
        c.draft=(ROOT/'Core/TemplateAdvancedDraft.swift').read_text()
        c.catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
    def test_root_registry_is_separate(self):
        self.assertIn('case mistakeTier, variants, roleViews',self.model)
        schema=(ROOT/'Core/TemplateCreatorSchema.swift').read_text().split('public var id:',1)[0]
        for name in ['mistakeTier','variants','roleViews']:self.assertNotIn(name,schema)
    def test_exact_relax_whitelist(self):
        declared=set(re.findall(r'= "([A-Za-z]+\.[A-Za-z]+)"',self.model.split('public var id:',2)[1])) if False else set(re.findall(r'= "([A-Za-z]+\.[A-Za-z]+)"',self.model.split('public enum TemplateRelaxField')[1].split('public var id:')[0]))
        expected=set('timer.durationSeconds typeIn.seconds ballShake.seconds sort.maxAttempts pricePair.maxTries typeIn.tries qa.maxTries hiddenObject.maxTries stopwatch.tries estimate.tolerance compass.tolerance stopwatch.toleranceMs reaction.goalMs quietHold.seconds shout.seconds countdown.seconds compass.holdSeconds ballShake.goal'.split())
        self.assertEqual(declared,expected)
    def test_first_match_not_stacked(self):
        self.assertIn('simulated.value.removeValue(forKey: "variants")',self.model)
        self.assertIn('!simulated.issues.isEmpty',self.model)
        self.assertIn('return (index, simulated)',self.model)
        self.assertIn('eligibleRelaxFields.contains(field)',self.model)
    def test_no_tightening_or_answer_changes(self):
        self.assertIn('field.lowers ? sign != "-"',self.model)
        self.assertIn('!field.attempts || amount != 0',self.model)
        self.assertIn('field.attempts &&',self.model)
        self.assertIn('"^[+=-][0-9]{1,5}$"',self.model)
    def test_backend_role_shape(self):
        self.assertIn('roles.count != 2',self.model)
        self.assertIn('views.count != 2',self.model)
        self.assertIn('items.count <= 8',self.model)
        self.assertIn('value.utf16.count <= 200',self.model)
        self.assertIn('["A", "B"]',self.model)
    def test_condition_wire_shapes_and_system_whitelist(self):
        self.assertIn('["var", "op", "value", "nodeId"]',self.model)
        self.assertIn('(mistakes|outcome|passed)',self.model)
        self.assertIn('sample.completedNodes.contains',self.model)
        self.assertIn('sample.tags.contains(value["value"]',self.model)
    def test_d20_is_variant_and_faces_are_not_required(self):
        self.assertIn('if diceMode == "d20" { break }',self.draft)
        self.assertIn('if game == .dice && diceMode != "d20"',self.draft)
        for token in ['number(section, "dc", 1, 40)','number(section, "modifier", -20, 20)','["normal", "advantage", "disadvantage"]']:
            self.assertIn(token,self.legacy)
    def test_legacy_bounds_and_unknowns(self):
        self.assertIn('number(section, "xp", 0, 1000',self.legacy)
        self.assertIn('number(section, "goalMs", 120, 3000)',self.legacy)
        self.assertIn('where !known.contains(key)',self.legacy)
    def test_d20_deterministic_creator_sample(self):
        self.assertIn('mode == "normal" ? [12] : [12, 7]',self.legacy)
        self.assertIn('total >=',self.legacy)
        self.assertIn('creatorRoot.d20RuntimeLimit',self.preview)
    def test_existing_editor_and_review_are_wired(self):
        form=(ROOT/'App/TemplateAuthoringDetailForms.swift').read_text()
        review=(ROOT/'App/TemplateAuthoringView.swift').read_text()
        self.assertIn('TemplateRootAuthoringView(model: model)',form)
        self.assertIn('TemplateD20ConfigurationView(model: model)',(ROOT/'App/TemplateAdvancedGameConfigurationView.swift').read_text())
        self.assertIn('TemplateRootRehearsalView(draft: draft.advanced)',review)
        self.assertIn('TemplateD20RehearsalView(draft: draft.advanced)',review)
    def test_root_serialization_preserves_root_only_configuration(self):
        self.assertIn('|| hasRootAuthoringConfiguration else',self.draft)
        self.assertIn('normalized.normalizeRootAuthoring()',self.draft)
        self.assertIn('rootCreatorIssues.map',self.draft)
    def test_no_raw_json_editor_or_live_calls(self):
        source=self.view+self.preview+self.model+self.legacy
        for token in ['TextEditor','URLSession','capabilityGrant','sendEvent(','submit(','HealthKit','CMPedometer']:self.assertNotIn(token,source)
        for control in ['Picker(','.onMove','.onDelete','TemplateConditionEditor','TemplateRelaxOperationEditor']:self.assertIn(control,self.view)
    def test_bilingual_fragment_and_labels(self):
        fragment=json.loads((ROOT/'Resources/CreatorRootLocalizations.fragment.json').read_text())
        self.assertEqual(len(fragment),82)
        for key in fragment:
            self.assertIn(key,self.catalog)
            for lang in ['en','zh-Hans']:self.assertTrue(self.catalog[key]['localizations'][lang]['stringUnit']['value'])
    def test_sort_attempt_operand_is_authorable(self):
        form=(ROOT/'App/TemplateMiniGameConfigurationView.swift').read_text()
        self.assertIn('TemplateAuthoringField("maxAttempts"',form)
        self.assertIn('number("sort", "maxAttempts", 0, 10',self.legacy)
    def test_runtime_acceptance_not_implied(self):
        self.assertIn('creatorRoot.roleViewsLimit',self.view)
        self.assertIn('creatorRoot.damageServer',self.view)
        self.assertIn('creatorRoot.rehearsalLimit',self.preview)
