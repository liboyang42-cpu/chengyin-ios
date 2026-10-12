import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class LegacyQuestionRehearsalSourceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateLegacyQuestionRehearsal.swift').read_text();cls.app=(ROOT/'App/TemplateLegacyQuestionRehearsalView.swift').read_text();cls.host=(ROOT/'App/TemplateAuthoringDetailForms.swift').read_text()
    def test_real_current_draft_entry_excludes_other_contracts(self):
        for token in ['TemplateLegacyQuestionRehearsal(model.draft).isAvailable','TemplateLegacyQuestionRehearsalView(model: model)','TemplateLegacyHintFields(model: model)','TemplateChoiceOptionRowsFields(model: model)','@StateObject private var rewards: TemplateRewardKindEditor']:self.assertIn(token,self.host)
        for token in ['draft.finishEnabled','[.text, .choice].contains(draft.validationMethod)','!draft.advanced.hasLegacyHintPrimaryGame','TemplateChoiceOptionRows(draft: draft)']:self.assertIn(token,self.core)
    def test_source_answer_alias_and_exact_comparison(self):
        for token in ['TemplateAuthoringStory.sourceTrim(answer).lowercased()','aliases.contains(Data(got.utf8))','aliases.isEmpty','CharacterSet(charactersIn: "、,，;；','\\u{FEFF}','\\u{3000}']:self.assertIn(token,self.core)
        self.assertNotIn('caseInsensitiveCompare',self.core)
    def test_hint_priority_and_no_hint_two_promotion(self):
        for token in ['draft.legacyHintsAreEnabled','draft.hint1 ?? ""','draft.answerReveal ?? ""','first.isEmpty ? reveal : first']:self.assertIn(token,self.core)
        self.assertNotIn('draft.hint2',self.core)
    def test_complete_retry_reset_and_option_identity(self):
        for token in ['public mutating func setAnswer','public mutating func select','public mutating func revealHint','public mutating func submit','public mutating func restart','state = matched ? .completed : .wrong','if matched { answer = ""; selected = nil; hintRevealed = false }','letter.rawValue']:self.assertIn(token,self.core)
    def test_ephemeral_only_no_model_or_network_writes(self):
        for token in ['model.draft =','model.changed(','model.save(','coordinator.change(','URLSession','AsyncImage','AVPlayer','submitRequest','ProductionTransport','sendEvent(','capabilityGrant']:self.assertNotIn(token,self.app+self.core)
        self.assertNotIn('Codable',self.core)
    def test_ownership_and_lifecycle_guards(self):
        for token in ['session == model.coordinator.session','identity == model.coordinator.identity','rehearsal.isCurrent(model.draft)','model.$draft.dropFirst()','Publishers.CombineLatest(model.$busy, model.$review)','self.inputGeneration == stamp','self.model.metadataGeneration == metadata','.onDisappear { editor.retire() }','phase != .active']:self.assertIn(token,self.app)
    def test_bilingual_fragment_and_registration(self):
        strings=json.loads((ROOT/'docs/localization/template-legacy-question-rehearsal.json').read_text())['strings'];used=set(re.findall(r'"(templateLegacyQuiz\.[a-zA-Z]+)"',self.app))-{'templateLegacyQuiz.hintText'}
        self.assertTrue(used.issubset(strings),used-set(strings))
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        self.assertEqual(json.loads((ROOT/'docs/registration/template-legacy-question-rehearsal.json').read_text())['dependencies'],[])
    def test_native_coverage_authored(self):
        core=(ROOT/'Tests/CoreTests/TemplateLegacyQuestionRehearsalTests.swift').read_text();app=(ROOT/'Tests/AppUnitTests/TemplateLegacyQuestionRehearsalViewTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',core)),14);self.assertEqual(len(re.findall(r'func test',app)),14)
        for token in ['testTextWrongHintRetryCompleteAndRestartDoesNotWriteDraft','testReloadUsesCurrentQuestionAndAnswerRatherThanDemoData','testPendingWriteLockPreventsRehearsalActions']:self.assertIn(token,app)
