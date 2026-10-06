from tools.tests.combined_native_budget_history import before_combined, materialize_independent_ui, independent_workflow
import tempfile
"""MV09 complete-method source preservation, immutable history, and actual planning."""
from copy import deepcopy
from decimal import Decimal
from pathlib import Path
import hashlib
import json
import re
import tempfile
import unittest
from tools import run_ui_shard as shard, ci_gates
from tools.tests.reviewed_map_budget_history import (
    before_reviewed_map, canonical, source_index, materialize_historical_pre_map_ui,
    BASELINE_PROFILE_SHA256, CURRENT_PROFILE_SHA256, FIXTURES,
)

ROOT = Path(__file__).resolve().parents[2]


def declaration(source, name):
    values = re.findall(r'(?m)^    (func ' + re.escape(name) + r'\b[\s\S]*?^    })', source)
    assert len(values) == 1, name
    return values[0]


class ReviewedMapBudget(unittest.TestCase):
    def setUp(self):
        self.history_directory=tempfile.TemporaryDirectory();self.addCleanup(self.history_directory.cleanup)
        self.ui_root=materialize_independent_ui(self.history_directory.name,'map')
        self.profile = before_combined(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()),'map')
        self.profile_path=Path(self.history_directory.name)/'profile.json';self.profile_path.write_text(json.dumps(self.profile))
        self.prior = before_reviewed_map(self.profile)
        self.plan = self.profile['planning_budget']['reviewed_map_alternative_list_replan']
        self.methods = {}
        self.costs = {}
        for path in sorted(self.ui_root.glob('*.swift')):
            source = path.read_text()
            names = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not names:
                continue
            cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
            self.assertEqual(len(cases), 1)
            case = cases[0]
            self.assertNotIn(case, self.costs)
            self.costs[case] = Decimal(0)
            for name in names:
                key = case + '.' + name
                self.assertNotIn(key, self.methods)
                self.methods[key] = path
                self.costs[case] += self.cost(self.profile, key)

    @staticmethod
    def cost(profile, key):
        return Decimal(str(profile['method_seconds'].get(key, profile['estimated_method_seconds'].get(key, 60))))

    def test_all_661_published_methods_and_sources_remain_exactly_and_three_are_added(self):
        self.assertEqual((len(self.methods), len(self.costs)), (664, 108))
        old = self.prior['planning_budget']['reviewed_native_features_replan']['current_inventory']
        self.assertEqual(set(self.methods), set(old) | set(self.plan['new_methods']))
        self.assertEqual(len(self.plan['new_methods']), 3)
        self.assertEqual(self.plan['published_method_migrations'], {})
        self.assertEqual(set(self.methods), set(self.plan['current_inventory']))
        self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(), self.plan['current_inventory_sha256'])
        for row in source_index()['baseline_ui_sources']:
            name, digest = row['path'], row['sha256']
            self.assertEqual(hashlib.sha256((self.ui_root/name).read_bytes()).hexdigest(), digest)
        with tempfile.TemporaryDirectory() as directory:
            sources = materialize_historical_pre_map_ui(directory)
            self.assertEqual(sum(shard.discover(sources).values()), 661)
            self.assertEqual(len(shard.discover(sources)), 107)
        self.assertEqual(sum(shard.discover(self.ui_root).values()), 664)

    def test_new_full_methods_and_every_helper_are_byte_preserved_from_reviewed_r2(self):
        index = source_index()
        original_bytes = (FIXTURES/'SearchMapFlowTests.swift.txt').read_bytes()
        self.assertEqual(hashlib.sha256(original_bytes).hexdigest(), index['reviewed_search_map_source_sha256'])
        before = original_bytes.decode()
        moved = (self.ui_root/'SearchMapAlternativeListFlowTests.swift').read_text()
        self.assertEqual(hashlib.sha256(moved.encode()).hexdigest(), index['dedicated_file_sha256'])
        self.assertIn('final class SearchMapAlternativeListFlowTests: XCTestCase', moved)
        for row in index['new_records']:
            name = row['method'].split('.')[1]
            self.assertEqual(declaration(before, name), declaration(moved, name))
            self.assertEqual(hashlib.sha256(declaration(moved, name).encode()).hexdigest(), row['declaration_sha256'])
        def non_test_text(text):
            for name in re.findall(r'\bfunc\s+(test\w+)\s*\(', text):
                text = text.replace(declaration(text, name), '', 1)
            text = text.replace('SearchMapAlternativeListFlowTests', 'SearchMapFlowTests', 1)
            return re.sub(r'\n{3,}', '\n\n', re.sub(r'(?m)^[ \t]+$', '', text))
        self.assertEqual(non_test_text(before), non_test_text(moved))

    def test_all_old_costs_observations_and_source_run_identity_are_unchanged(self):
        old = self.prior['planning_budget']['reviewed_native_features_replan']['current_inventory']
        for key in old:
            self.assertEqual(self.cost(self.profile, key), self.cost(self.prior, key))
        self.assertEqual(len(self.profile['run117_method_observations']), 647)
        for field in self.prior:
            if field not in ('planning_budget', 'estimated_method_seconds', 'estimate_provenance'):
                self.assertEqual(self.profile[field], self.prior[field], field)
        self.assertEqual(self.profile['estimate_provenance']['methods'][:-3], self.prior['estimate_provenance']['methods'])
        self.assertEqual(self.plan['failed_prefixes_used_as_method_costs'], 0)
        records = self.profile['estimate_provenance']['methods']
        self.assertEqual(len(records), len({row['method'] for row in records}))
        self.assertEqual({row['method'] for row in records}, set(self.profile['estimated_method_seconds']))
        for row in records:
            self.assertFalse(row['measured'])
            self.assertEqual(self.cost(self.profile, row['method']), Decimal(str(row['seconds'])))
            self.assertEqual(hashlib.sha256(self.methods[row['method']].read_bytes()).hexdigest(), row['test_file_sha256'])
        fragment_bytes = (FIXTURES/'whole-method-timing-fragment.json').read_bytes()
        self.assertEqual(hashlib.sha256(fragment_bytes).hexdigest(), source_index()['reviewed_timing_fragment_sha256'])
        fragment = json.loads(fragment_bytes)
        self.assertEqual([r['whole_method_seconds'] for r in fragment['new_ui_methods']], [360, 240, 210])
        for row in fragment['new_ui_methods']:
            current = self.plan['reviewed_unpublished_method_migrations'][row['method']]
            self.assertEqual(self.cost(self.profile, current), row['whole_method_seconds'])
            self.assertNotIn(current, self.profile['method_seconds'])
        self.assertEqual(self.costs['SearchMapAlternativeListFlowTests'], 810)
        self.assertEqual(self.costs['SearchMapFlowTests'], Decimal('670.135'))

    def test_actual_all_class_partition_keeps_all_methods_and_full_startup_reserve(self):
        self.assertEqual((39, 39, self.plan['shard_count']), (39, 39, 39))
        self.assertEqual((self.plan['deadline_seconds'], self.plan['startup_reserve_seconds']), (1800, 300))
        actual = shard.measured_weights(self.ui_root, self.profile_path)
        self.assertEqual(set(actual), set(self.costs))
        for case in self.costs:
            self.assertAlmostEqual(float(self.costs[case]), actual[case], places=9)
        self.assertEqual(max(self.costs.values()), Decimal(self.plan['maximum_class_seconds']))
        self.assertLessEqual(max(self.costs.values()), 1500)
        for count in (38, 39, 40):
            groups = shard.partition(self.costs, count)
            self.assertEqual(groups, shard.partition(actual, count))
            flat = sum(groups, [])
            self.assertEqual(len(flat), len(set(flat)))
            self.assertEqual(set(flat), set(self.costs))
            self.assertEqual(sum(shard.discover(self.ui_root)[case] for case in flat), 664)
            maximum = max(sum(self.costs[case] for case in group)+300 for group in groups)
            self.assertEqual(maximum, Decimal(self.plan['forecasts'][str(count)]))
            if count == 39:
                self.assertEqual(maximum, Decimal('1738.315'))
                self.assertGreaterEqual(1800-maximum, 60)
        workflow = independent_workflow('map').read_text()
        outputs = re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}', workflow, re.M)
        self.assertEqual(outputs, [(str(i), str(i)) for i in range(39)])
        self.assertIn('--count 39 ', workflow)
        self.assertIn('--deadline-seconds 1800', workflow)

    def test_exact_inverse_and_corruption_negative_controls_preserve_history(self):
        self.assertEqual(canonical(self.profile), CURRENT_PROFILE_SHA256)
        self.assertEqual(canonical(self.prior), BASELINE_PROFILE_SHA256)
        for mutation in ('inventory', 'new_cost', 'old_cost', 'source', 'observation', 'historical_run', 'migration'):
            damaged = deepcopy(self.profile)
            if mutation == 'inventory':
                damaged['planning_budget']['reviewed_map_alternative_list_replan']['current_inventory'].pop()
            elif mutation == 'new_cost':
                damaged['estimated_method_seconds'][self.plan['new_methods'][0]] = 1
            elif mutation == 'old_cost':
                damaged['method_seconds'][next(iter(damaged['method_seconds']))] = 1
            elif mutation == 'source':
                damaged['estimate_provenance']['methods'][-1]['test_file_sha256'] = '0'*64
            elif mutation == 'observation':
                damaged['run117_method_observations'].pop()
            elif mutation == 'historical_run':
                damaged['run117_method_observations'][0]['run_id'] = 0
            else:
                damaged['planning_budget']['reviewed_map_alternative_list_replan']['reviewed_unpublished_method_migrations'].popitem()
            with self.assertRaises(AssertionError):
                before_reviewed_map(damaged)
