"""Focused native source checks for P086 optional pause fallback; no runtime claim."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantStationOptionalFallbackContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_wire_contract_omits_no_plan_and_rejects_partial_plan(self):
        source = self.read('Core/MerchantStationContracts.swift')
        pause = source.split('case .pause:', 2)[-1].split('case .verify:', 1)[0]
        self.assertIn('required(["reasonCode", "resumeEta"], optional: ["reason", "fallbackPlanCode", "fallbackPlanVersion"])', pause)
        self.assertIn('guard hasFallbackCode == hasFallbackVersion', pause)
        self.assertIn('if hasFallbackCode {', pause)
        self.assertIn('Self.validTime(payload["resumeEta"]?.text ?? "")', pause)
        self.assertIn('text.utf16.count <= 200', pause)

    def test_action_scope_revision_and_approved_plan_validation_remain(self):
        source = self.read('Core/MerchantStationContracts.swift')
        self.assertIn('projection.activityID == activityID, projection.revision == expectedRevision, projection.allows(action, nodeID: nodeID)', source)
        self.assertIn('if action == .pause, payload["fallbackPlanCode"] != nil', source)
        self.assertIn('$0["sourceNodeId"].safeInteger == nodeID', source)
        self.assertIn('$0["planVersion"].safeInteger == payload["fallbackPlanVersion"]?.safeInteger', source)
        self.assertIn('guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional))', source)

    def test_editor_has_explicit_none_and_no_positional_default(self):
        source = self.read('App/MerchantContentEditor.swift')
        self.assertIn('@State private var pauseFallback: MerchantStationPauseChoice?', source)
        self.assertNotIn('fallbackIndex', source)
        self.assertIn('Text("merchant.stationPause.noFallback").tag(nil as MerchantStationPauseChoice?)', source)
        self.assertIn('selection: pauseFallback, projection: p, nodeID: node', source)
        self.assertIn('pauseFallback = $0; dirty = true; model.cancel()', source)
        self.assertIn('text = [:]; checked = [:]; pauseFallback = nil; dirty = false', source)
        self.assertIn('guard c.isCurrent, !c.busy, !c.locked, c.review == nil', source)

    def test_stale_choice_is_not_replaced_and_current_option_is_required_once(self):
        source = self.read('Core/MerchantStationPauseChoice.swift')
        self.assertIn('choices.filter({ $0 == selection }).count == 1', source)
        self.assertIn('selection.sourceNodeID == nodeID', source)
        self.assertIn('if let selection {', source)
        self.assertIn('fields["fallbackPlanCode"] = .string(selection.planCode)', source)
        self.assertNotIn('fields["fallbackPlanCode"] = .null', source)
        self.assertIn('if !note.isEmpty { fields["reason"] = .string(note) }', source)
        ui = self.read('App/MerchantContentEditor.swift')
        self.assertIn('if let pauseFallback, !options.contains(pauseFallback)', ui)
        self.assertIn('Text("merchant.stationPause.selectionChanged").tag(Optional(pauseFallback))', ui)

    def test_no_fallback_consequence_is_visible_in_editor_and_frozen_review(self):
        editor = self.read('App/MerchantContentEditor.swift')
        review = self.read('App/MerchantContentViews.swift').split('struct MerchantContentReviewView', 1)[1]
        self.assertIn('merchant.stationPause.noFallbackConsequence', editor)
        self.assertIn('if case .station(let command) = review.command, command.pausesWithoutFallback', review)
        self.assertLess(review.index('merchant.stationPause.noFallbackConsequence'), review.index('Button("merchant.content.confirm")'))
        self.assertIn('!model.coordinator.service.permitsWrites', review)
        self.assertIn('await model.confirm(review)', review)

    def test_existing_frozen_review_unknown_lock_and_endpoint_are_reused(self):
        service = self.read('Core/MerchantContentService.swift')
        coordinator = self.read('Core/MerchantContentCoordinator.swift')
        command = self.read('Core/MerchantContentCommands.swift')
        self.assertIn('guard latest == baseline', service)
        self.assertIn('try journal.insert(record)', service)
        self.assertIn('execution: Execution = .disabled', service)
        self.assertIn('guard isCurrent, !busy, !locked, review == frozen', coordinator)
        self.assertIn('case .station(let c): return json("api/game/session/command", try c.fields())', command)
        helper = self.read('Core/MerchantStationPauseChoice.swift')
        for prohibited in ['URLSession', 'execute(', 'UserDefaults', 'FileManager', 'refundAmount', 'paymentAmount']:
            self.assertNotIn(prohibited, helper)

    def test_bilingual_copy_explains_no_reroute_and_existing_support(self):
        fragment = json.loads(self.read('Resources/MerchantStationPauseLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 4)
        for value in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'].strip())
        consequence = fragment['merchant.stationPause.noFallbackConsequence']['localizations']
        self.assertIn('not be directed to another station', consequence['en']['stringUnit']['value'])
        self.assertIn('现有平台客服', consequence['zh-Hans']['stringUnit']['value'])

    def test_authored_cases_cover_absence_stale_selection_and_authority(self):
        source = self.read('Tests/CoreTests/MerchantStationPauseChoiceTests.swift')
        for name in ['testNoFallbackWorksWithoutCandidatesAndOmitsBothFieldsRatherThanNull',
                     'testExplicitNoneAfterSelectionLeavesNoOldFallbackFields',
                     'testChoiceSurvivesReorderWithoutSwitchingToDifferentPlan',
                     'testRemovedOrChangedChoiceDoesNotSilentlyBecomeNone',
                     'testPartialNullBlankAndInvalidVersionPayloadsAreRejected',
                     'testNoFallbackDoesNotBypassActionStationStateOrRevision',
                     'testNoFallbackCannotSmuggleTargetRefundPaymentOrMerchantFields']:
            self.assertIn('func ' + name, source)

if __name__ == '__main__': unittest.main()
