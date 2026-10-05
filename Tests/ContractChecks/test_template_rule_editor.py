"""Native static structure checks only; no Swift execution or mini runtime claims."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class TemplateRuleEditorChecks(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT/'Core/TemplateAuthoringRuleSteps.swift').read_text()
        self.model = (ROOT/'App/TemplateAuthoringView.swift').read_text()
        self.view = (ROOT/'App/TemplateAuthoringRuleFields.swift').read_text()
    def test_local_rows_keep_original_and_do_not_normalize_draft_on_load(self):
        for token in ['originalText = raw; storedText = raw', 'components(separatedBy: "\\n")', 'map(Self.sourceTrim)', 'joined(separator: "\\n")']:
            self.assertIn(token, self.core)
        self.assertNotIn('ruleInstructions =', self.model.split('func load()')[1].split('func changed()')[0])
    def test_add_remove_are_bounded_but_reorder_is_not_invented(self):
        for token in ['maximumRows = 12', 'rows.count < Self.maximumRows', 'rows.count > 1', 'EditError.lastRow', 'rows.remove(at: index)']:
            self.assertIn(token, self.core)
        self.assertNotIn('.onMove', self.view)
        self.assertNotIn('func reorder', self.core)
    def test_ascii_only_limit_has_no_silent_truncation_or_unicode_claim(self):
        self.assertIn('maximumASCIILength = 60', self.core)
        self.assertIn('text.unicodeScalars.allSatisfy { $0.value < 0x80 }', self.core)
        self.assertIn('non-ASCII counting unit is unverified', self.core)
        self.assertIn('!text.contains("\\r\\n")', self.core)
        for token in ['.prefix(', '.utf16.count', 'text.count >']:
            self.assertNotIn(token, self.core)
    def test_editor_is_mounted_instead_of_unrestricted_text_field(self):
        self.assertIn('TemplateAuthoringRuleFields(model: model)', self.model)
        self.assertNotIn('TemplateAuthoringField("ruleInstructions"', self.model)
        for token in ['model.ruleStep(row.id)', 'model.removeRuleStep(row.id)', 'model.addRuleStep()', '!model.ruleSteps.canAdd', 'model.ruleSteps.storedText ?? ""']:
            self.assertIn(token, self.view)
    def test_model_edits_use_existing_session_identity_and_draft_guards(self):
        for token in ['self.epoch == bindingEpoch', 'self.draftIdentity == bindingIdentity', 'self.epoch == self.coordinator.session', 'self.draftIdentity == self.coordinator.identity', 'self.ruleSteps.text(for: id) != nil', 'guard canEdit, ruleSteps.storedText == draft.ruleInstructions', 'draft.ruleInstructions = next.storedText']:
            self.assertIn(token, self.model)
        for method in ['func load()', 'func restore()', 'func discard()']:
            body = self.model.split(method, 1)[1].split('\n    func ', 1)[0]
            self.assertIn('resetRuleSteps()', body)
    def test_rule_constraints_are_not_added_to_wire_or_publish_gates(self):
        domain = (ROOT/'Core/TemplateAuthoringDomain.swift').read_text()
        contract = (ROOT/'Core/TemplateAuthoringContract.swift').read_text()
        self.assertNotIn('TemplateAuthoringRuleSteps', domain)
        self.assertNotIn('TemplateAuthoringRuleSteps', contract)
        self.assertIn('string("ruleInstructions", d.ruleInstructions)', contract)
        self.assertIn('guard !d.validationMethod.isLocalConfigurationOnly', contract)
    def test_labels_are_bilingual_and_ids_are_unique_per_row(self):
        catalog = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        for suffix in ['hint','historical','step','prompt','remove','add','asciiLimit','rowLimit','stepNumber %lld','removeNumber %lld']:
            for language in ['en','zh-Hans']:
                self.assertTrue(catalog['templateRules.'+suffix]['localizations'][language]['stringUnit']['value'])
        self.assertIn('id: \\.element.id', self.view)
        self.assertIn('public let id: UUID', self.core)
        self.assertIn('.accessibilityLabel(Text("templateRules.removeNumber', self.view)
        self.assertIn('.accessibilityLabel(Text("templateRules.stepNumber', self.view)
    def test_authored_core_and_lifecycle_regressions_are_present(self):
        core_tests = (ROOT/'Tests/CoreTests/TemplateAuthoringRuleStepsTests.swift').read_text()
        app_tests = (ROOT/'Tests/AppUnitTests/TemplateRuleStepModelTests.swift').read_text()
        for token in ['testUnsupportedHistoricalTextIsReadOnlyAndRoundTripsUnchanged','testECMAScriptWhitespaceDoesNotUseFoundationWiderTrim','testOnlyVerifiedASCII60BoundaryRejectsWithoutReplacingDraft','testModesZeroThroughFiveRetainWireFieldAndSixSevenRemainLocalOnly']:
            self.assertIn(token, core_tests)
        for token in ['testRetainedBindingCannotCrossAccountOrEpoch','testDeletedOrDiscardedRowBindingCannotEditAnotherRow','testLockedSubmissionCannotEditAnyRuleControl','testRuleEditInvalidatesReviewWithoutChangingRemoteGates']:
            self.assertIn(token, app_tests)

if __name__ == '__main__': unittest.main()
