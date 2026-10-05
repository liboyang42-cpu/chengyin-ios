"""Current exhaustive planning and exact historical evidence for runtime repairs."""
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import unittest
from tools import run_ui_shard as shard
from tools.tests.run108_runtime_budget_history import historical_profile, BASELINE_SHA256

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    'IntegratedNativeAcceptanceFlowTests.testActualPhoneHomeDetailManualMapPlayAndFreshOwnedOrderJourney': 240,
    'IntegratedNativeAcceptanceFlowTests.testConfiguredAuthenticationDoesNotGrantDetailMapPlayOrOwnedOrders': 210,
    'SignedInContentDetailFlowTests.testEmptyShelfChineseAndRoleChangeClearProjection': 120,
    'SignedInContentDetailFlowTests.testActivityTopicRouteClearsOnRoleChangeAndSignOut': 180,
    'TemplateEditorControlsFlowTests.testRuleRowsPreserveSourceUntilEditAndBoundASCIIThroughLocalRestore': 360,
    'TemplateEditorControlsFlowTests.testHistoricalBytesHintOffRestoreAndSameOwnerLockedReadback': 540,
}


class RuntimeRepairBudgetTests(unittest.TestCase):
    def setUp(self):
        self.profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        self.plan = self.profile['planning_budget']['run108_runtime_replan']

    def test_six_full_method_replacements_are_unmeasured_and_bound_to_current_bytes(self):
        records = self.profile['estimate_provenance']['methods'][-6:]
        self.assertEqual({record['method']: record['seconds'] for record in records}, EXPECTED)
        self.assertEqual(set(self.plan['expanded_methods']), set(EXPECTED))
        for record in records:
            self.assertIs(record['measured'], False)
            self.assertTrue(record['basis'])
            method = record['method']
            self.assertNotIn(method, self.profile['method_seconds'])
            self.assertEqual(self.profile['estimated_method_seconds'][method], record['seconds'])
            case, name = method.split('.')
            path = ROOT / 'Tests/AppUITests' / (case + '.swift')
            source = path.read_text()
            start = source.index('    func ' + name + '(')
            end = source.index('\n    }', start) + len('\n    }')
            self.assertEqual(hashlib.sha256(source[start:end].encode()).hexdigest(), record['integrated_method_sha256'])
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), record['integrated_file_sha256'])
            if 'breakdown_seconds' in record:
                self.assertEqual(sum(record['breakdown_seconds'].values()), record['seconds'])

    def test_every_prior_observation_estimate_and_plan_reconstructs_exactly(self):
        prior = historical_profile(self.profile)
        digest = hashlib.sha256(json.dumps(prior, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.assertEqual(digest, BASELINE_SHA256)
        self.assertEqual(prior['method_seconds']['IntegratedNativeAcceptanceFlowTests.testActualPhoneHomeDetailManualMapPlayAndFreshOwnedOrderJourney'], 138.538)
        self.assertEqual(prior['method_seconds']['IntegratedNativeAcceptanceFlowTests.testConfiguredAuthenticationDoesNotGrantDetailMapPlayOrOwnedOrders'], 132.433)
        self.assertEqual(prior['method_seconds']['SignedInContentDetailFlowTests.testEmptyShelfChineseAndRoleChangeClearProjection'], 16.259)
        for corrupt in ['method_seconds', 'estimated_method_seconds']:
            mutated = deepcopy(self.profile)
            mutated[corrupt]['Unrelated.testHistory'] = 123
            with self.assertRaises(AssertionError):
                historical_profile(mutated)

    def test_complete_source_inventory_fits_once_with_unchanged_deadline_and_reserve(self):
        profile = self.profile
        costs = {}; ids = []
        for path in sorted((ROOT / 'Tests/AppUITests').glob('*.swift')):
            source = path.read_text(); methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not methods:
                continue
            case = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)[0]
            names = [case + '.' + method for method in methods]; ids.extend(names)
            costs[case] = sum(Decimal(str(profile['method_seconds'].get(method,
                profile['estimated_method_seconds'].get(method, profile['unobserved_method_seconds'])))) for method in names)
        self.assertEqual((len(ids), len(set(ids)), len(costs)), (654, 654, 98))
        self.assertEqual(hashlib.sha256('\n'.join(sorted(ids)).encode()).hexdigest(), self.plan['inventory_sha256'])
        self.assertEqual(sum(costs.values()), Decimal('33779.320'))
        self.assertEqual(Decimal(str(self.plan['total_method_seconds'])), sum(costs.values()))
        self.assertEqual(sum(costs.values()) - Decimal('33256.550'), Decimal('522.770'))
        self.assertEqual((profile['planning_budget']['deadline_seconds'], profile['planning_budget']['startup_reserve_seconds'], profile['unobserved_method_seconds']), (1800, 300, 60))
        self.assertGreater(sum(costs.values()), 22 * 1500)
        groups = shard.partition(costs, 23)
        self.assertEqual(groups, shard.partition(shard.measured_weights(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json'), 23))
        flat = [case for group in groups for case in group]
        self.assertEqual(len(flat), len(set(flat)))
        self.assertEqual(set(flat), set(costs))
        peak = max(sum(costs[case] for case in group) + 300 for group in groups)
        self.assertEqual(peak, Decimal('1794.380'))
        self.assertEqual(Decimal(str(self.plan['maximum_projected_seconds_with_reserve'])), peak)
        self.assertEqual(1800 - peak, Decimal(str(self.plan['forecast_headroom_seconds'])))
        self.assertEqual(shard.DEFAULT_SHARD_COUNT, self.plan['shard_count'])
        self.assertEqual(self.plan['new_method_count'], 0)
        self.assertTrue(self.plan['assertion_target_only_migration'])
