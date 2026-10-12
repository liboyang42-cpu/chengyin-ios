import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class PredictionPlanSourceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplatePredictionPlan.swift').read_text();cls.app=(ROOT/'App/TemplatePredictionPlanEditor.swift').read_text();cls.host=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
    def test_real_draft_entry_and_existing_hotspot_retained(self):
        for token in ['family == .predict && TemplatePredictionPlan(model.draft.advanced).isSupported','(!usesHotspotPlacement || $0.id != "hotspots") && (!usesPredictionPlan || !TemplatePredictionPlan.managedFields.contains($0.id))','TemplatePredictionPlanEditor(model: model)','TemplateHotspotPlacementView(model: model)']:self.assertIn(token,self.host)
        self.assertNotIn('"xp"',self.core.split('managedFields:')[1].split('\n')[0])
    def test_auto_key_targeted_rows_and_range(self):
        for token in ['rows.count < 4','next.addCreatorRow(.predict','field("label")','values.remove(at: index)','Array(0...23)','Array(0...30)']:self.assertIn(token,self.core)
        self.assertNotIn('field("key")',self.core);self.assertIn('Text(verbatim: row.key)',self.app)
    def test_all_schedule_actions_summary_and_existing_validation(self):
        for token in ['hourPicker(.closeAtHour)','hourPicker(.revealHour)','selection: editor.timingInput(.revealDays)','Section("templatePrediction.summary")','model.draft.advanced.creatorIssues(.predict)']:self.assertIn(token,self.app)
        self.assertIn('timing(.revealDays) == 0 && timing(.revealHour) < timing(.closeAtHour)',self.core)
        for token in ['DatePicker','Calendar.current','DateComponents']:self.assertNotIn(token,self.app+self.core)
    def test_non_normalizing_reads_and_exact_scope(self):
        for token in ['let candidate: Int?','TemplateAuthoringStory.sourceTrim','raw == nil ? fallback : raw?.integer','[.sortedKeys, .withoutEscapingSlashes]','fingerprint == Self.snapshot(draft)']:self.assertIn(token,self.core)
    def test_scoped_continuous_and_structural_input_guards(self):
        for token in ['session == model.coordinator.session','identity == model.coordinator.identity','plan.isCurrent(model.draft.advanced)','model.$draft.dropFirst()','Publishers.CombineLatest(model.$busy, model.$review)','self.inputGeneration == stamp','if structural { inputGeneration = UUID() }','self.model.metadataGeneration == metadata','.onDisappear { editor.retire() }','phase != .active']:self.assertIn(token,self.app)
    def test_existing_local_save_without_new_production_effects(self):
        self.assertIn('self.model.save()',self.app);self.assertIn('model.changed()',self.app)
        for token in ['URLSession','AsyncImage','AVPlayer','ProductionTransport','capabilityGrant','UNUserNotificationCenter','submitRequest','settlePrediction','sendEvent(']:self.assertNotIn(token,self.app+self.core)
    def test_localization_and_registration_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-prediction-plan.json').read_text())['strings']
        used=set(re.findall(r'"(templatePrediction\.[a-zA-Z]+)"',self.app))-{'templatePrediction.add','templatePrediction.hint','templatePrediction.revealDays','templatePrediction.saveLocal'}
        self.assertTrue(used.issubset(strings),used-set(strings))
        for key in ['templatePrediction.count %lld','templatePrediction.day %lld']:self.assertIn(key,strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        self.assertEqual(json.loads((ROOT/'docs/registration/template-prediction-plan.json').read_text())['dependencies'],[])
    def test_authored_native_coverage(self):
        core=(ROOT/'Tests/CoreTests/TemplatePredictionPlanTests.swift').read_text();app=(ROOT/'Tests/AppUnitTests/TemplatePredictionPlanEditorTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',core)),13);self.assertEqual(len(re.findall(r'func test',app)),13)
        for token in ['testRemoveAndAddCannotRetargetOldRowInputsOrButtons','testLocalSaveRestoreRetainsCurrentKeysLabelsAndRelativeDays','testPendingWriteLockBlocksPlanMutation']:self.assertIn(token,app)
