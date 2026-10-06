"""Published coverage, intact method moves, and complete feature batch budgets."""
from copy import deepcopy
from decimal import Decimal
from pathlib import Path
import hashlib, json, re, unittest
from tools import run_ui_shard as shard, ci_gates
from tools.tests.reviewed_feature_budget_history import (
    before_reviewed_features, historical_pre_feature_ui_source, canonical,
    CURRENT_PROFILE_SHA256, BASELINE_PROFILE_SHA256, source_index,
)

ROOT = Path(__file__).resolve().parents[2]

class ReviewedFeatureBudget(unittest.TestCase):
    def setUp(self):
        self.profile = json.loads((ROOT/'tools/ui_duration_weights.json').read_text())
        self.plan = self.profile['planning_budget']['reviewed_native_features_replan']
        self.methods = {}; self.costs = {}
        for path in sorted((ROOT/'Tests/AppUITests').glob('*.swift')):
            source = path.read_text()
            methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not methods: continue
            cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
            self.assertEqual(len(cases), 1)
            case = cases[0]; self.assertNotIn(case, self.costs); self.costs[case] = Decimal(0)
            for name in methods:
                key = case+'.'+name; self.assertNotIn(key, self.methods); self.methods[key] = path
                self.costs[case] += self.cost(key)

    def cost(self, key):
        return Decimal(str(self.profile['method_seconds'].get(key, self.profile['estimated_method_seconds'].get(key, 60))))

    def test_all_prior_methods_remain_and_only_one_owned_coupon_journey_is_new(self):
        self.assertEqual((len(self.methods), len(self.costs)), (661, 107))
        self.assertEqual(set(self.methods), set(self.plan['current_inventory']))
        self.assertEqual(len(self.plan['current_inventory']), 661)
        self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(), self.plan['current_inventory_sha256'])
        prior = before_reviewed_features(self.profile)
        old = prior['planning_budget']['run116_repair_replan']['current_inventory']
        moves = self.plan['method_migrations']
        self.assertEqual((len(moves), len(set(moves.values()))), (13, 13))
        self.assertEqual({moves.get(k,k) for k in old} | set(self.plan['new_methods']), set(self.methods))
        self.assertEqual(self.plan['new_methods'], ['OwnedCouponCodeJourneyUITests.testOwnedListDetailCancelConfirmBackAndReopenRequireFreshConsent'])
        self.assertEqual(sum(shard.discover(ROOT/'Tests/AppUITests').values()), 661)

    def test_moved_complete_method_bytes_and_setup_helpers_are_preserved(self):
        records = json.loads((ROOT/'tools/tests/fixtures/reviewed-feature-whole-method-migrations.json').read_text())
        self.assertEqual(len(records), 4)
        def declaration(source, name):
            values = re.findall(r'(?m)^    (func '+re.escape(name)+r'\b[\s\S]*?^    })', source)
            self.assertEqual(len(values),1, name)
            return values[0]
        for record in records:
            old_path = ROOT/'Tests/AppUITests'/(record['old_class']+'.swift')
            before = historical_pre_feature_ui_source(old_path).read_text()
            remaining = old_path.read_text()
            new_path = ROOT/'Tests/AppUITests'/(record['new_class']+'.swift')
            moved = new_path.read_text()
            self.assertEqual(hashlib.sha256(before.encode()).hexdigest(), record['before_sha256'])
            self.assertEqual(hashlib.sha256(remaining.encode()).hexdigest(), record['remaining_file_sha256'])
            self.assertEqual(hashlib.sha256(moved.encode()).hexdigest(), record['new_file_sha256'])
            for row in record['moves']:
                name = row['old_id'].split('.')[1]
                self.assertNotIn(row['old_id'], self.methods); self.assertIn(row['new_id'], self.methods)
                self.assertEqual(declaration(before,name), declaration(moved,name))
                self.assertEqual(hashlib.sha256(declaration(moved,name).encode()).hexdigest(), row['exact_declaration_sha256'])
            for text in (remaining, moved):
                stripped = text
                for name in re.findall(r'\bfunc\s+(test\w+)\s*\(', text):
                    stripped = stripped.replace(declaration(text,name), '', 1)
                stripped = stripped.replace(record['new_class'], record['old_class'], 1)
                stripped = re.sub(r'(?m)^[ \t]+$', '', stripped)
                self.assertEqual(hashlib.sha256(stripped.encode()).hexdigest(), record['non_test_declarations_sha256'])

    def test_every_full_allowance_is_retained_or_raised_and_current_sources_are_bound(self):
        prior = before_reviewed_features(self.profile)
        for old in prior['planning_budget']['run116_repair_replan']['current_inventory']:
            current = self.plan['method_migrations'].get(old, old)
            previous = Decimal(str(prior['method_seconds'].get(old, prior['estimated_method_seconds'].get(old, 60))))
            self.assertGreaterEqual(self.cost(current), previous)
        rows = self.profile['estimate_provenance']['methods']
        self.assertEqual({x['method'] for x in rows}, set(self.profile['estimated_method_seconds']))
        self.assertEqual(len(rows), len({x['method'] for x in rows}))
        for row in rows:
            self.assertFalse(row['measured'])
            self.assertEqual(self.cost(row['method']), Decimal(str(row['seconds'])))
            self.assertEqual(hashlib.sha256(self.methods[row['method']].read_bytes()).hexdigest(), row['test_file_sha256'])
            self.assertGreater(self.cost(row['method']), 0); self.assertLessEqual(self.cost(row['method']), 900)
        self.assertEqual(len(self.plan['account_whole_method_replacements']), 44)
        for row in self.plan['account_whole_method_replacements']:
            self.assertFalse(row['measured'])
            self.assertGreaterEqual(self.cost(row['method']), Decimal(str(row['prior_complete_method_seconds'])) + Decimal(30*row['account_traversals']))
            self.assertNotIn(row['method'], self.profile['method_seconds'])
        self.assertEqual(self.plan['failed_prefixes_used_as_method_costs'],0)
        self.assertEqual(self.cost(self.plan['new_methods'][0]),360)

    def test_actual_partition_and_all_completion_outputs_keep_hard_limits(self):
        self.assertEqual((shard.DEFAULT_SHARD_COUNT, ci_gates.SHARD_COUNT, self.plan['shard_count']), (38,38,38))
        self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds']),(1800,300))
        self.assertEqual(max(self.costs.values()),Decimal(str(self.plan['maximum_class_seconds'])))
        self.assertLessEqual(max(self.costs.values()),1500)
        actual=shard.measured_weights(ROOT/'Tests/AppUITests',ROOT/'tools/ui_duration_weights.json')
        self.assertEqual(set(self.costs),set(actual))
        for case in self.costs:self.assertAlmostEqual(float(self.costs[case]),actual[case],places=9)
        self.assertEqual(shard.partition(self.costs,38),shard.partition(actual,38))
        for count in (36,37,38):
            groups = shard.partition(self.costs,count)
            flat = sum(groups,[]); self.assertEqual(len(flat),len(set(flat)));self.assertEqual(set(flat),set(self.costs))
            maximum = max(sum(self.costs[name] for name in group)+300 for group in groups)
            self.assertEqual(maximum,Decimal(str(self.plan['forecasts'][str(count)])))
            if count<38:self.assertGreater(maximum,1800)
            else:self.assertLessEqual(maximum,1800)
        workflow=(ROOT/'.github/workflows/native-ios.yml').read_text()
        outputs=re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',workflow,re.M)
        self.assertEqual(outputs,[(str(i),str(i)) for i in range(38)])
        self.assertIn('--count 38 ',workflow);self.assertIn('--deadline-seconds 1800',workflow)

    def test_exact_published_history_and_negative_controls(self):
        self.assertEqual(canonical(self.profile),CURRENT_PROFILE_SHA256)
        self.assertEqual(canonical(before_reviewed_features(self.profile)),BASELINE_PROFILE_SHA256)
        self.assertEqual(len(source_index()['new_ui_filenames']),5)
        for corrupt in ('inventory','cost','old_cost','migration','source'):
            candidate=deepcopy(self.profile)
            if corrupt=='inventory':candidate['planning_budget']['reviewed_native_features_replan']['current_inventory'].pop()
            elif corrupt=='cost':candidate['estimated_method_seconds'][next(iter(candidate['estimated_method_seconds']))]=1
            elif corrupt=='old_cost':candidate['reviewed_features_previous_method_seconds'].popitem()
            elif corrupt=='migration':candidate['planning_budget']['reviewed_native_features_replan']['method_migrations'].popitem()
            else:candidate['estimate_provenance']['methods'][0]['test_file_sha256']='0'*64
            with self.assertRaises(AssertionError):before_reviewed_features(candidate)
