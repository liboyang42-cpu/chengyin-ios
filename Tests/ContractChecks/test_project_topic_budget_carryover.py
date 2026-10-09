"""Static contracts for unchanged existing XP-budget carry-over; not Swift execution."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[2]
C=(R/'Core/ProjectTopicBudgetCarryOver.swift').read_text()
W=(R/'Core/ProjectEditContract.swift').read_text()
T=(R/'Tests/CoreTests/ProjectTopicBudgetCarryOverTests.swift').read_text()
class TopicBudgetCarryOverContracts(unittest.TestCase):
    def test_exact_single_budget_field_joins_existing_carryover(self):
        self.assertIn('fields = ["xpBudget"]',C)
        self.assertIn('ProjectTeamConfiguration.fields + ProjectTopicBudgetCarryOver.fields',W)
        self.assertIn('for key in topicCarryOver { if let value = topic[key] { d.preserved[key] = value } }',W)
        self.assertIn('for key in topicCarryOver { if let value = draft.preserved[key] { payload[key] = value } }',W)
    def test_whitelist_returns_before_budget_guard(self):
        self.assertLess(W.index('if scope == .whitelist'),W.index('guard ProjectTopicBudgetCarryOver.allows'))
    def test_create_shape_does_not_gain_a_budget_field(self):
        self.assertIn('guard let topicID else { return raw == nil || raw == .null }',C)
        self.assertIn('if topicID == nil { payload["xpBudget"] = nil }',W)
    def test_bounds_match_positive_java_integer_without_defaulting(self):
        self.assertIn('guard let value = raw.integer',C)
        self.assertIn('(1...Int(Int32.max)).contains(value)',C)
        self.assertNotIn('?? 3000',C+W)
    def test_unknown_both_raw_and_baseline_fail_closed(self):
        self.assertIn('supported(raw), supported(original)',C)
        self.assertIn('guard let raw, raw != .null else { return true }',C)
    def test_exact_unchanged_value_and_absence_null_distinction(self):
        self.assertIn('return raw == original',C)
        self.assertIn('let raw = draft.preserved["xpBudget"]',C)
        self.assertIn('let original = baseline?.draft.preserved["xpBudget"]',C)
        self.assertNotIn('raw ??',C)
    def test_owner_product_id_scope_and_exact_revision_proof(self):
        for x in ['topicID > 0','baseline.topicID == topicID','baseline.scope == .full','baseline.draft.owner == draft.owner','baseline.draft.product == draft.product','!baseline.draft.baseRevision.isEmpty','baseline.draft.baseRevision.utf8.elementsEqual(draft.baseRevision.utf8)']:
            self.assertIn(x,C)
    def test_existing_team_guard_is_retained(self):
        self.assertIn('guard ProjectTeamConfiguration.canSubmit(draft, baseline: baseline)',W)
    def test_no_budget_mutation_ui_network_or_reward_authority(self):
        for x in ['result.preserved','draft.preserved["xpBudget"] =','URLRequest','URLSession','/api/','submit(','claim(','reward(','AppSession','SwiftUI']:
            self.assertNotIn(x,C)
    def test_actual_readback_and_payload_regression(self):
        for x in ['AuthoritativeReadbackRetainsBudgetAndUnrelatedEdit','ProjectEditContract.decodeEditDetail','ProjectEditContract.payload','BothProductsAndInt32Boundary','ActualPreparedReviewFreezesSavedBudget']:
            self.assertIn(x,T)
    def test_legacy_and_scope_regressions(self):
        for x in ['MissingAndNullExistingValuesStayDistinct','BudgetChangesMissingOldLocal','NewDraftKeepsDefaultBehavior','WhitelistKeepsOriginalShape','OldLocalEnvelopeCannotHideUnknownFreshBudget']:
            self.assertIn(x,T)
    def test_negative_ownership_and_numeric_regressions(self):
        for x in ['PositiveBudgetRequiresAnExistingMatchingFullBaseline','OwnerProductAndExactRevisionMismatch','EmptyRevisionDoesNotProve','UnknownNonpositiveFractionalAndOverflow','Int64(Int32.max) + 1']:
            self.assertIn(x,T)
if __name__=='__main__':unittest.main()
