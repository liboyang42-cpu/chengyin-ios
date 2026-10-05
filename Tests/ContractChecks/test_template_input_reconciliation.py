"""Native control reconciliation source checks; not UIKit/XCTest execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TemplateInputReconciliationContracts(unittest.TestCase):
    def test_only_rejected_row_gets_a_new_control_identity(self):
        model = (ROOT / 'App/TemplateAuthoringView.swift').read_text()
        view = (ROOT / 'App/TemplateAuthoringRuleFields.swift').read_text()
        self.assertIn('self.changeRuleSteps(rejectedRowID: id)', model)
        failure = model.split('catch TemplateAuthoringRuleSteps.EditError.asciiLength', 1)[1].split('catch TemplateAuthoringRuleSteps.EditError.rowLimit', 1)[0]
        self.assertIn('ruleInputRevisions[rejectedRowID] = UUID()', failure)
        for forbidden in ['draft.ruleInstructions =', 'ruleSteps =', '.prefix(', '.accessibilityValue(']:
            self.assertNotIn(forbidden, failure)
        self.assertIn('.id(InputIdentity(rowID: row.id, rejectionRevision: model.ruleInputRevisions[row.id]))', view)
        self.assertNotIn('.accessibilityValue(', view)
        self.assertIn('ruleInputRevisions = ruleInputRevisions.filter { next.text(for: $0.key) != nil }', model)
        self.assertIn('ruleStepIssue = nil; ruleInputRevisions = [:]', model)

    def test_hint_control_supports_raw_newlines_without_binding_normalization(self):
        view = (ROOT / 'App/TemplateLegacyHintFields.swift').read_text()
        self.assertIn('TemplateAuthoringField(field.rawValue, text: model.legacyHint(field), multiline: true)', view)
        for forbidden in ['replacingOccurrences', 'trimmingCharacters', '.prefix(', '.accessibilityValue(']:
            self.assertNotIn(forbidden, view)
        self.assertIn('guard self.canEdit, self.legacyHintLeaseIsCurrent', view)
        self.assertIn('canReadLegacyHints && coordinator.session == session', view)

    def test_ui_captures_active_value_before_probe_and_keeps_exact_assertions(self):
        source = '\n'.join((ROOT / ('Tests/AppUITests/' + name + '.swift')).read_text() for name in ['TemplateEditorControlsFlowTests', 'TemplateHistoricalHintFlowTests'])
        self.assertLess(source.index('let visibleAfterRejection ='), source.index('let acceptedAfterRejection = try inspect(app)'))
        self.assertLess(source.index('let visibleAfterReenable ='), source.index('let acceptedAfterReenable = try inspect(app)'))
        for token in ['bytes(visibleAfterRejection, sixty)', 'assertHints(hints, draft: acceptedAfterReenable.draft)',
                      'bytes(visibleAfterReenable[index], hints[index])',
                      'bytes(input("templateRules.input.11", in: app, towardTop: true).value as? String, sixty)',
                      'bytes(input("templateAuthor.field." + field, in: app).value as? String, hints[index])',
                      'recoveredInput.typeText(XCUIKeyboardKey.delete.rawValue + "a")',
                      'UNMEASURED full-method replacement estimate: 360 seconds.',
                      'UNMEASURED full-method replacement estimate: 540 seconds.']:
            self.assertIn(token, source)
        self.assertIn('Array($0.utf8)', source)

    def test_historical_and_model_byte_protection_remain_required(self):
        core = (ROOT / 'Core/TemplateAuthoringRuleSteps.swift').read_text()
        self.assertIn('originalText = raw; storedText = raw', core)
        self.assertIn('maximumASCIILength = 60', core)
        self.assertIn('guard !Self.exceedsVerifiedASCIILimit(text)', core)
        self.assertNotIn('ruleInputRevisions', core)
        unit = (ROOT / 'Tests/AppUnitTests/TemplateRuleStepModelTests.swift').read_text()
        for token in ['testRejectedInputRotatesOnlyItsNativeFieldIdentityWithoutChangingAcceptedBytes',
                      'XCTAssertNotEqual(firstRejection, secondRejection)',
                      'XCTAssertNil(model.ruleInputRevisions[other])',
                      'XCTAssertEqual(model.ruleInputRevisions[id], secondRejection)',
                      'XCTAssertEqual(historical.draft.ruleInstructions, raw)']:
            self.assertIn(token, unit)


if __name__ == '__main__': unittest.main()
