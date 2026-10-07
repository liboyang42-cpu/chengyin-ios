"""Historical 710-method coverage and exact preservation of the reviewed 707-method union."""
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
from pathlib import Path
import hashlib
import json
import re
import tempfile
import unittest

from tools.tests.club_parity_budget_history import (
    before_club_parity, historical_pre_club_source, historical_pre_club_module,
    materialize_pre_club_ui,
)
from tools.tests.creator_pending_budget_history import (
    BASELINE_PROFILE_SHA256, CURRENT_PROFILE_SHA256, before_creator_pending,
    canonical, materialize_pre_creator_ui, source_index,
)

ROOT = Path(__file__).resolve().parents[2]
shard = historical_pre_club_module(ROOT / 'tools/run_ui_shard.py', 'creator_pre_club_shard')
ci_gates = historical_pre_club_module(ROOT / 'tools/ci_gates.py', 'creator_pre_club_gates')


class CreatorPendingBudgetTests(unittest.TestCase):
    def setUp(self):
        self.history_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.history_directory.cleanup)
        self.ui_root = materialize_pre_club_ui(self.history_directory.name)
        self.profile = before_club_parity(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        self.profile_path = Path(self.history_directory.name) / 'profile.json'
        self.profile_path.write_text(json.dumps(self.profile))
        self.plan = self.profile['planning_budget']['reviewed_creator_pending_replan']
        self.previous = before_creator_pending(self.profile)
        self.index = source_index()
        self.methods = {}
        self.costs = defaultdict(Decimal)
        for path in sorted(self.ui_root.glob('*.swift')):
            source = path.read_text()
            methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not methods:
                continue
            classes = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
            self.assertEqual(len(classes), 1)
            for name in methods:
                key = classes[0] + '.' + name
                self.assertNotIn(key, self.methods)
                self.methods[key] = path
                self.costs[classes[0]] += self.cost(self.profile, key)

    @staticmethod
    def cost(profile, key):
        return Decimal(str(profile['method_seconds'].get(
            key, profile['estimated_method_seconds'].get(key, profile['unobserved_method_seconds']))))

    def test_all_710_complete_methods_in_146_direct_classes_execute_once(self):
        self.assertEqual((len(self.methods), len(self.costs)), (710, 146))
        self.assertEqual(sum(shard.discover(self.ui_root).values()), 710)
        self.assertEqual(set(self.methods), set(self.plan['current_inventory']))
        self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(),
                         self.plan['current_inventory_sha256'])
        prior = self.previous['planning_budget']['reviewed_combined_native_replan']['current_inventory']
        self.assertEqual((len(prior), len(self.plan['new_methods'])), (707, 3))
        self.assertFalse(set(prior) & set(self.plan['new_methods']))
        self.assertEqual(set(prior) | set(self.plan['new_methods']), set(self.methods))
        groups = shard.partition(self.costs, 65)
        flat = sum(groups, [])
        self.assertEqual((len(flat), len(set(flat))), (146, 146))
        actual_methods = [key for group in groups for name in group
                          for key in self.methods if key.split('.')[0] == name]
        self.assertEqual((len(actual_methods), len(set(actual_methods))), (710, 710))
        self.assertEqual(set(actual_methods), set(self.methods))

    def test_all_original_ui_files_and_complete_helpers_are_byte_exact(self):
        for row in self.index['baseline_ui_sources']:
            self.assertEqual(hashlib.sha256(historical_pre_club_source(ROOT / row['path']).read_bytes()).hexdigest(), row['sha256'])
        with tempfile.TemporaryDirectory() as directory:
            found = shard.discover(materialize_pre_creator_ui(directory))
            self.assertEqual((sum(found.values()), len(found)), (707, 143))
        for row in self.index['helper_sources']:
            self.assertEqual(hashlib.sha256(historical_pre_club_source(ROOT / row['path']).read_bytes()).hexdigest(), row['sha256'])

    def test_new_methods_keep_reviewed_full_bytes_and_conservative_estimates(self):
        self.assertEqual(sorted(self.plan['whole_method_estimates'].values()), [360, 540, 900])
        for row in self.index['new_ui_sources']:
            path = ROOT / row['path']
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row['sha256'])
            method = row['method'].split('.')[1]
            declarations = re.findall(r'(?m)^    (func ' + re.escape(method) + r'\b[\s\S]*?^    })', path.read_text())
            self.assertEqual(len(declarations), 1)
            self.assertEqual(hashlib.sha256(declarations[0].encode()).hexdigest(), row['whole_method_sha256'])
            self.assertEqual(self.cost(self.profile, row['method']), row['seconds'])
            self.assertNotIn(row['method'], self.profile['method_seconds'])
            record = [r for r in self.profile['estimate_provenance']['methods'] if r['method'] == row['method']]
            self.assertEqual(len(record), 1)
            self.assertFalse(record[0]['measured'])
            self.assertEqual(record[0]['timing_status'], 'UNMEASURED_CONSERVATIVE_ESTIMATE')
            self.assertEqual(record[0]['declaration_sha256'], row['whole_method_sha256'])
            self.assertIn('Entire setup/launch', record[0]['basis'])

    def test_every_prior_cost_and_all_647_observations_are_exactly_preserved(self):
        self.assertEqual(self.profile['method_seconds'], self.previous['method_seconds'])
        for key, value in self.previous.items():
            if key not in ('estimated_method_seconds', 'estimate_provenance', 'planning_budget'):
                self.assertEqual(self.profile[key], value, key)
        for key, value in self.previous['estimated_method_seconds'].items():
            self.assertEqual(self.profile['estimated_method_seconds'][key], value)
        self.assertEqual(len(self.profile['run117_method_observations']), 647)
        self.assertEqual(self.profile['run117_method_observations'], self.previous['run117_method_observations'])
        for key, value in self.previous['planning_budget'].items():
            self.assertEqual(self.profile['planning_budget'][key], value, key)
        self.assertEqual(self.profile['estimate_provenance']['methods'][:-3],
                         self.previous['estimate_provenance']['methods'])
        for key in self.previous['planning_budget']['reviewed_combined_native_replan']['current_inventory']:
            self.assertEqual(self.cost(self.profile, key), self.cost(self.previous, key))

    def test_estimate_provenance_binds_every_current_source_without_duplicate_or_hidden_cost(self):
        rows = self.profile['estimate_provenance']['methods']
        self.assertEqual(len(rows), len({row['method'] for row in rows}))
        self.assertEqual({row['method'] for row in rows}, set(self.profile['estimated_method_seconds']))
        for row in rows:
            self.assertFalse(row['measured'])
            self.assertEqual(self.cost(self.profile, row['method']), Decimal(str(row['seconds'])))
            self.assertEqual(hashlib.sha256(self.methods[row['method']].read_bytes()).hexdigest(), row['test_file_sha256'])
        for key in self.methods:
            self.assertGreater(self.cost(self.profile, key), 0)
            self.assertLessEqual(self.cost(self.profile, key), 900)

    def test_65_is_first_fitting_partition_and_does_not_increase_existing_shards(self):
        self.assertEqual((shard.DEFAULT_SHARD_COUNT, ci_gates.SHARD_COUNT, self.plan['shard_count']), (65, 65, 65))
        self.assertEqual((self.plan['deadline_seconds'], self.plan['startup_reserve_seconds'],
                          self.plan['complete_method_limit_seconds']), (1800, 300, 900))
        self.assertEqual(sum(self.costs.values()), Decimal('91064.732'))
        self.assertEqual(max(self.costs.values()), 1470)
        actual = shard.measured_weights(self.ui_root, self.profile_path)
        self.assertEqual(set(actual), set(self.costs))
        for key, value in actual.items():
            self.assertAlmostEqual(value, float(self.costs[key]), places=9)
        for count in range(38, 67):
            groups = shard.partition(self.costs, count)
            self.assertEqual(groups, shard.partition(actual, count))
            self.assertEqual(set(sum(groups, [])), set(self.costs))
            peak = max(sum(self.costs[key] for key in group) + 300 for group in groups)
            self.assertEqual(peak, Decimal(self.plan['forecasts'][str(count)]))
            if count < 65:
                self.assertGreater(peak, 1800)
            else:
                self.assertLessEqual(peak, 1800)
        self.assertEqual(self.plan['forecasts']['64'], '1826.149')
        self.assertEqual(self.plan['forecasts']['65'], '1797.226')
        self.assertEqual(self.plan['remaining_margin_seconds'], '2.774')
        self.assertEqual(self.plan['forecasts']['66'], '1770')

    def test_workflow_runner_completion_gate_and_deadline_remain_byte_exact(self):
        for key, path in [('workflow_sha256', '.github/workflows/native-ios.yml'),
                          ('runner_sha256', 'tools/run_ui_shard.py'), ('gates_sha256', 'tools/ci_gates.py')]:
            self.assertEqual(hashlib.sha256(historical_pre_club_source(ROOT / path).read_bytes()).hexdigest(), self.index[key])
        workflow = historical_pre_club_source(ROOT / '.github/workflows/native-ios.yml').read_text()
        outputs = re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}', workflow, re.M)
        self.assertEqual(outputs, [(str(i), str(i)) for i in range(65)])
        self.assertIn('--count 65 ', workflow)
        self.assertIn('--deadline-seconds 1800', workflow)

    def test_published_profile_reconstruction_is_exact_and_every_mutation_fails_closed(self):
        self.assertEqual(canonical(self.profile), CURRENT_PROFILE_SHA256)
        self.assertEqual(canonical(self.previous), BASELINE_PROFILE_SHA256)
        self.assertEqual(self.index['current_profile_canonical_sha256'], CURRENT_PROFILE_SHA256)
        for mutation in ('inventory', 'cost', 'old_cost', 'observation', 'source', 'history', 'reserve', 'count', 'removed_plan'):
            profile = deepcopy(self.profile)
            plan = profile['planning_budget']['reviewed_creator_pending_replan']
            if mutation == 'inventory':
                plan['current_inventory'].pop()
            elif mutation == 'cost':
                profile['estimated_method_seconds'][plan['new_methods'][0]] = 1
            elif mutation == 'old_cost':
                profile['method_seconds'][next(iter(profile['method_seconds']))] = 1
            elif mutation == 'observation':
                profile['run117_method_observations'].pop()
            elif mutation == 'source':
                profile['estimate_provenance']['methods'][-1]['test_file_sha256'] = '0' * 64
            elif mutation == 'history':
                profile['planning_budget']['reviewed_combined_native_replan']['current_inventory'].pop()
            elif mutation == 'reserve':
                plan['startup_reserve_seconds'] = 0
            elif mutation == 'count':
                plan['shard_count'] = 66
            else:
                profile['planning_budget'].pop('reviewed_creator_pending_replan')
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                before_creator_pending(profile)

    def test_delivered_plan_is_recomputed_from_actual_methods_and_unchanged_runner(self):
        evidence = json.loads((ROOT / 'docs/creator-pending-native-integration-budget.json').read_text())
        self.assertEqual(evidence['plan'], self.plan)
        self.assertEqual(evidence['class_costs'], {key: str(value) for key, value in sorted(self.costs.items())})
        groups = shard.partition(self.costs, 65)
        self.assertEqual(len(evidence['shards']), 65)
        self.assertEqual(sum(row['methods'] for row in evidence['shards']), 710)
        for number, row in enumerate(evidence['shards']):
            self.assertEqual((row['index'], row['classes']), (number, groups[number]))
            self.assertEqual(Decimal(row['projected_seconds_with_startup']),
                             sum(self.costs[key] for key in groups[number]) + 300)
            self.assertLessEqual(Decimal(row['projected_seconds_with_startup']), 1800)
