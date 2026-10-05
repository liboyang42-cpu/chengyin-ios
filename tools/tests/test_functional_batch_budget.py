from tools.tests.run109_amendment_budget_history import before_run109_amendments, HISTORICAL_SHARD_COUNT
from tools.tests.run109_amendment_budget_history import historical_ui_sources
"""Exhaustive active planning and reversible published timing history."""
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import unittest
from tools import run_ui_shard as shard
from tools.tests.functional_batch_budget_history import before_functional_batch, baseline_ids, BASELINE_PROFILE_SHA256

ROOT = Path(__file__).resolve().parents[2]
NEW_METHODS = {
    'NonCashRewardFlowTests.testDetailDisclosesFrozenTermsExactMapOriginAndUnavailableClaimFacts',
    'PlayExperienceFlowTests.testChineseFreePackKeepsStoreChoiceAfterBackAndRefresh',
    'PlayExperienceFlowTests.testOrdinaryReadFallbackUsesFreeStoreCardsAndNoOrientationAnswerForm',
    'TemplateMediaReviewFlowTests.testAudioMetadataAndStoryLocalReviewReturnWithoutAttachingAnything',
    'TemplateMediaReviewFlowTests.testDefaultOffReviewCancelReopenAndFinishNeverOfferUploadOrApply',
    'TemplateMediaReviewFlowTests.testGeneratedImageCropReselectPendingCancelAndFailureKeepRawReferences',
}


class FunctionalBatchBudgetTests(unittest.TestCase):
    def setUp(self):
        self.profile = before_run109_amendments(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        self.plan = self.profile['planning_budget']['reviewed_native_functional_replan']

    def inventory(self):
        result = {}; costs = {}
        for path in historical_ui_sources(ROOT / 'Tests/AppUITests'):
            text = path.read_text(); names = re.findall(r'\bfunc\s+(test\w+)\s*\(', text)
            if not names:
                continue
            cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text)
            self.assertEqual(len(cases), 1); case = cases[0]
            self.assertNotIn(case, costs); self.assertEqual(len(names), len(set(names)))
            costs[case] = Decimal(0)
            for name in names:
                method = case + '.' + name
                self.assertNotIn(method, result); result[method] = path
                costs[case] += Decimal(str(self.profile['method_seconds'].get(method,
                    self.profile['estimated_method_seconds'].get(method, self.profile['unobserved_method_seconds']))))
        return result, costs

    def test_all_660_current_methods_are_required_and_no_published_method_disappeared(self):
        methods, costs = self.inventory()
        self.assertEqual((len(methods), len(costs)), (660, 99))
        self.assertTrue(baseline_ids().issubset(methods))
        self.assertEqual(set(methods) - baseline_ids(), NEW_METHODS)
        self.assertEqual(set(self.plan['new_methods']), NEW_METHODS)
        self.assertEqual(self.plan['new_method_count'], 6)
        digest = hashlib.sha256('\n'.join(sorted(methods)).encode()).hexdigest()
        self.assertEqual(digest, 'c42bb16a52b7dd8d900d91dd6e1b121ecc26101c464848660b5d8069d60a44ee')
        self.assertEqual(digest, self.plan['current_inventory_sha256'])

    def test_all_106_full_method_estimates_bind_current_source_and_are_never_measurements(self):
        methods, _ = self.inventory()
        records = self.profile['estimate_provenance']['methods'][-106:]
        self.assertEqual(len(records), self.plan['provenance_record_count'])
        self.assertEqual(len({r['method'] for r in records}), 106)
        self.assertEqual({r['method'] for r in records}, set(self.plan['expanded_or_reestimated_methods']))
        for record in records:
            method = record['method']; self.assertIn(method, methods)
            self.assertIs(record['measured'], False)
            self.assertEqual(record['source'], 'reviewedNativeFunctionalBatch20261005')
            self.assertTrue(record['basis']); self.assertTrue(record['basis_components'])
            self.assertNotIn(method, self.profile['method_seconds'])
            self.assertEqual(self.profile['estimated_method_seconds'][method], record['seconds'])
            self.assertGreater(record['seconds'], 0); self.assertLessEqual(record['seconds'], 900)
            self.assertEqual(hashlib.sha256(methods[method].read_bytes()).hexdigest(), record['test_file_sha256'])
            self.assertRegex(record['declaration_sha256'], r'^[a-f0-9]{64}$')
        # The Account overlap is absorbed by exact ID, not added a second time.
        expected = {
            'IntegratedNativeAcceptanceFlowTests.testActualPhoneHomeDetailManualMapPlayAndFreshOwnedOrderJourney': 240,
            'IntegratedNativeAcceptanceFlowTests.testConfiguredAuthenticationDoesNotGrantDetailMapPlayOrOwnedOrders': 210,
            'CouponRuntimeFlowTests.testNormalRootDiskRestartDoesNotRedispatchUnknownCreation': 420,
            'NonCashRewardFlowTests.testDetailDisclosesFrozenTermsExactMapOriginAndUnavailableClaimFacts': 480,
            'TemplateMediaReviewFlowTests.testAudioMetadataAndStoryLocalReviewReturnWithoutAttachingAnything': 660,
            'MerchantTemplateAssistFlowTests.testReviewExplicitApplyReturnsToSameUnsavedTemplate': 360,
        }
        for method, seconds in expected.items():
            self.assertEqual(self.profile['estimated_method_seconds'][method], seconds)
        self.assertIn('never added twice', records[0]['basis'])

    def test_published_run109_profile_and_every_previous_plan_reconstruct_exactly(self):
        old = before_functional_batch(self.profile)
        digest = hashlib.sha256(json.dumps(old, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.assertEqual(digest, BASELINE_PROFILE_SHA256)
        self.assertEqual(old['planning_budget']['run108_runtime_replan']['maximum_projected_seconds_with_reserve'], 1794.38)
        self.assertEqual(old['planning_budget']['run108_runtime_replan']['method_count'], 654)
        for key in ['method_seconds', 'estimated_method_seconds']:
            mutated = deepcopy(self.profile); mutated[key]['Unexpected.testMutation'] = 100
            with self.assertRaises(AssertionError):
                before_functional_batch(mutated)
        broken = deepcopy(self.profile); broken.pop('functional_batch_superseded_estimates')
        with self.assertRaises((KeyError, AssertionError)):
            before_functional_batch(broken)

    def test_decimal_lpt_and_live_runner_use_same_exhaustive_bounded_29_shards(self):
        methods, costs = self.inventory(); budget = self.profile['planning_budget']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds'], self.profile['unobserved_method_seconds']), (1800, 300, 60))
        self.assertEqual(sum(costs.values()), Decimal('41707.817'))
        self.assertEqual(max(costs.values()), Decimal('1490'))
        self.assertEqual(costs['OwnerDraftBrowserFlowTests'], Decimal('1465.827'))
        self.assertEqual(costs['CouponRuntimeFlowTests'], Decimal('1450'))
        self.assertEqual(costs['NonCashRewardFlowTests'], Decimal('1160'))
        self.assertEqual(costs['TemplateMediaReviewFlowTests'], Decimal('1320'))
        self.assertEqual(costs['MerchantTemplateAssistFlowTests'], Decimal('686.615'))
        for count in range(23, 30):
            groups = shard.partition(costs, count)
            peak = max(sum(costs[c] for c in group) + 300 for group in groups)
            self.assertEqual(peak, Decimal(self.plan['plans_maximum_with_reserve'][str(count)]))
            if count < 29:
                self.assertGreater(peak, 1800)
            else:
                self.assertEqual(peak, Decimal('1790'))
        self.assertGreater(sum(costs.values()), 27 * 1500)
        live_costs = {case: float(value) for case, value in costs.items()}
        self.assertEqual(groups, shard.partition(live_costs, 29))
        flat = [c for group in groups for c in group]
        self.assertEqual(len(flat), len(set(flat))); self.assertEqual(set(flat), set(costs))
        self.assertEqual(sum(sum(method.startswith(c + '.') for method in methods) for c in flat), 660)
        self.assertEqual(HISTORICAL_SHARD_COUNT, self.plan['shard_count'])
        self.assertEqual(HISTORICAL_SHARD_COUNT, 29)
        self.assertEqual(Decimal(str(self.plan['forecast_headroom_seconds'])), Decimal('10'))
