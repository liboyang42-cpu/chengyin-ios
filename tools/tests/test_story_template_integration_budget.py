"""Live additive story-template budget, source binding, and exact R2 replay."""
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest
from unittest.mock import patch
from tools import run_ui_shard as shard, ci_gates
from tools.tests.story_template_budget_history import (
    before_story_template, canonical, source_index, materialize_pre_story_ui,
    historical_pre_story_source, historical_pre_story_module,
    CURRENT_PROFILE_SHA256, BASELINE_PROFILE_SHA256, PLAN, MARKER,
)
from tools.tests.club_parity_budget_history import before_club_parity, materialize_pre_club_ui

from tools.tests.player_map_history_budget_history import frozen_story_context
_FROZEN_STORY = frozen_story_context()
ROOT = _FROZEN_STORY.root
shard, ci_gates = _FROZEN_STORY.runner, _FROZEN_STORY.gates
UI = ROOT / 'Tests/AppUITests'
PROFILE = ROOT / 'tools/ui_duration_weights.json'


class StoryTemplateIntegrationBudgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile = json.loads(PROFILE.read_text())
        cls.prior = before_story_template(cls.profile)
        cls.plan = cls.profile['planning_budget'][PLAN]
        cls.contract = json.loads(shard.STORY_TEMPLATE_CONTRACT_PATH.read_text())
        cls.new = cls.contract['required_floors']

    def with_profile(self, profile, source=UI):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'profile.json'
            path.write_text(json.dumps(profile))
            before = path.read_bytes()
            result = shard.measured_weights(source, path)
            self.assertEqual(path.read_bytes(), before)
            return result

    def decimal_costs(self):
        p = self.profile
        costs = defaultdict(Decimal)
        for key in self.plan['current_inventory']:
            old = p['method_seconds'].get(key, p['estimated_method_seconds'].get(key, 60))
            value = max(old, p.get('method_planning_floors', {}).get(key, {}).get('seconds', 0), self.new.get(key, {}).get('seconds', 0))
            costs[key.split('.')[0]] += Decimal(str(value))
        return costs

    def test_exact_718_methods_153_classes_and_six_additive_whole_methods(self):
        counts = shard.discover(UI)
        self.assertEqual((sum(counts.values()), len(counts)), (718, 153))
        old = set(self.prior['planning_budget']['reviewed_club_parity_replan']['current_inventory'])
        current = set(self.plan['current_inventory'])
        self.assertEqual(current - old, set(self.new))
        self.assertTrue(old <= current)
        self.assertEqual(hashlib.sha256('\n'.join(sorted(current)).encode()).hexdigest(), self.plan['current_inventory_sha256'])
        for key in self.new:
            self.assertEqual(counts[key.split('.')[0]], 1)
        groups = shard.partition(self.decimal_costs(), 73)
        flat = sum(groups, [])
        self.assertEqual((len(flat), len(set(flat)), set(flat)), (153, 153, set(counts)))
        self.assertEqual(sum(counts[key] for key in flat), 718)

    def test_every_old_observation_estimate_provenance_and_plan_is_exact(self):
        for key, value in self.prior.items():
            if key in ('estimated_method_seconds', 'estimate_provenance', 'planning_budget'):
                continue
            self.assertEqual(self.profile[key], value, key)
        for key, value in self.prior['estimated_method_seconds'].items():
            self.assertEqual(self.profile['estimated_method_seconds'][key], value)
        old_rows = self.prior['estimate_provenance']['methods']
        self.assertEqual(self.profile['estimate_provenance']['methods'][:len(old_rows)], old_rows)
        for key, value in self.prior['planning_budget'].items():
            self.assertEqual(self.profile['planning_budget'][key], value)
        self.assertEqual(len(self.profile['run117_method_observations']), 647)
        self.assertEqual(self.profile['method_seconds']['ClubOperationsFlowTests.testAdminProfileHasNoOwnerSettingsOrRoleActions'], 27.351)

    def test_all_153_forecasts_are_exact_and_73_preserves_old_30_second_margin(self):
        costs = self.decimal_costs()
        self.assertEqual(sum(costs.values()), Decimal('98087.381'))
        self.assertEqual(max(costs.values()), 1470)
        self.assertEqual((shard.DEFAULT_SHARD_COUNT, ci_gates.SHARD_COUNT, self.plan['shard_count']), (73, 73, 73))
        self.assertEqual((self.plan['deadline_seconds'], self.plan['startup_reserve_seconds'], self.plan['complete_method_limit_seconds']), (1800, 300, 900))
        for count in range(1, 154):
            peak = max(sum(costs[name] for name in group) + 300 for group in shard.partition(costs, count))
            self.assertEqual(str(peak), self.plan['forecasts'][str(count)])
            if count < 72:
                self.assertGreater(peak, 1800)
        self.assertEqual({key: self.plan['forecasts'][key] for key in ('67', '71', '72', '73')}, {'67': '1907.064', '71': '1826.149', '72': '1797.226', '73': '1770'})
        self.assertEqual(self.plan['remaining_margin_seconds'], '30')
        actual = shard.measured_weights(UI, PROFILE)
        for key, value in costs.items():
            self.assertAlmostEqual(actual[key], float(value), places=8)
        self.assertEqual(shard.partition(actual, 73), shard.partition(costs, 73))

    def test_actual_workflow_completes_all_73_and_preserves_execution_limits(self):
        workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        outputs = re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}', workflow, re.M)
        self.assertEqual(outputs, [(str(i), str(i)) for i in range(73)])
        matrix = re.search(r'shard:\s*\[([0-9,\s]+)\]', workflow)[1]
        self.assertEqual([int(x) for x in matrix.split(',')], list(range(73)))
        self.assertEqual(re.findall(r'run_ui_shard.py[^\n]*--count (\d+)', workflow), ['73'])
        self.assertEqual(re.findall(r'--deadline-seconds (\d+)', workflow), ['1800'])
        self.assertNotIn('continue-on-error', workflow)
        self.assertIn('math.isfinite(value) and 0 < value <= 900', (ROOT / 'tools/run_ui_shard.py').read_text())
        self.assertIn('-maximum-test-execution-time-allowance 120', workflow)  # unchanged AppUnit limit

    def test_helper_wait_and_loop_arithmetic_remains_unmeasured(self):
        records = {row['method']: row for row in self.profile['estimate_provenance']['methods']}
        self.assertEqual(self.plan['complete_method_derivations'], list(self.new.values()))
        for key, row in self.new.items():
            self.assertFalse(row['measured'])
            self.assertEqual(row['timing_status'], 'UNMEASURED_ENGINEERING_PLANNING_ASSUMPTION')
            self.assertEqual((row['seconds'], self.profile['estimated_method_seconds'][key]), (900, 900))
            self.assertNotIn(key, self.profile['method_seconds'])
            self.assertEqual(records[key], row)
            d = row['derivation']; end = 'EndFlowTests.' in key
            self.assertEqual(d['tap_helper_calls'], 24 if end else 27)
            self.assertEqual(sum(d['other_explicit_wait_caps_seconds'].values()), 115)
            self.assertEqual(d['all_explicit_wait_caps_seconds'], d['tap_helper_calls'] * 10 + 115)
            self.assertEqual((d['reveal_calls'], d['maximum_swipes_per_reveal'], d['maximum_viewport_query_iterations_per_reveal']), (14, 10, 11))
            self.assertEqual(d['reveal_iteration_allowance_seconds'], 14 * 11 * 2)
            self.assertEqual(d['other_whole_method_overhead_seconds_assumption'], 117)
            self.assertEqual(d['round_up_seconds'], 30 if end else 0)
            self.assertEqual(90 + d['all_explicit_wait_caps_seconds'] + 308 + 117 + d['round_up_seconds'], 900)
            self.assertIn('not a source-derived duration', d['assumption_limit'])
            self.assertEqual(set(row['shared_helper_source_sha256']), {'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift', 'Tests/AppUITests/FailureScreenshot.swift', 'Tests/AppUITests/FixtureEnvironmentAssertions.swift'})

    def test_old_full_profiles_receive_all_nine_required_floors_without_mutation(self):
        for profile in [self.prior, before_club_parity(self.prior)]:
            actual = self.with_profile(profile)
            self.assertAlmostEqual(sum(actual.values()), 98087.381, places=8)
            self.assertAlmostEqual(actual['ClubOperationsFlowTests'], 1465.141, places=8)
            self.assertEqual(actual['ClubProfileScopeFlowTests'], 1350)
            for key in self.new:
                self.assertEqual(actual[key.split('.')[0]], 900)

    def test_removing_all_self_reported_story_costs_and_markers_cannot_lower_floors(self):
        p = deepcopy(self.profile)
        p['planning_budget'].pop(PLAN)
        p['estimate_provenance']['methods'] = [r for r in p['estimate_provenance']['methods'] if r['method'] not in self.new]
        for key in self.new:
            p['estimated_method_seconds'].pop(key)
        self.assertEqual(p, self.prior)
        actual = self.with_profile(p)
        self.assertAlmostEqual(sum(actual.values()), 98087.381, places=8)
        for key in self.new:
            p['method_seconds'][key] = 1
        actual = self.with_profile(p)
        self.assertAlmostEqual(sum(actual.values()), 98087.381, places=8)

    def test_low_future_observations_do_not_shadow_source_floor_and_remain_stored(self):
        for value in (1, 17, 899, 900):
            p = deepcopy(self.profile)
            for key in self.new:
                p['method_seconds'][key] = value
            actual = self.with_profile(p)
            self.assertAlmostEqual(sum(actual.values()), 98087.381, places=8)
            self.assertEqual(p['method_seconds'][next(iter(self.new))], value)

    def test_claimed_plan_missing_cost_identity_inventory_or_provenance_fails_closed(self):
        for mutation in ('plan', 'estimate', 'low_estimate', 'plan_cost', 'plan_cost_and_estimate', 'inventory', 'duplicate_inventory', 'inventory_hash', 'method_count', 'class_count', 'new_methods', 'record', 'record_cost', 'record_file', 'record_declaration', 'record_non_test', 'shared_hash', 'missing_shared_map'):
            p = deepcopy(self.profile); key = next(iter(self.new)); row = next(r for r in p['estimate_provenance']['methods'] if r['method'] == key)
            if mutation == 'plan': p['planning_budget'].pop(PLAN)
            elif mutation == 'estimate': p['estimated_method_seconds'].pop(key)
            elif mutation == 'low_estimate': p['estimated_method_seconds'][key] = 60
            elif mutation == 'plan_cost': p['planning_budget'][PLAN]['whole_method_estimates'].pop(key)
            elif mutation == 'plan_cost_and_estimate':
                p['planning_budget'][PLAN]['whole_method_estimates'].pop(key); p['estimated_method_seconds'].pop(key)
            elif mutation == 'inventory': p['planning_budget'][PLAN]['current_inventory'].pop()
            elif mutation == 'duplicate_inventory': p['planning_budget'][PLAN]['current_inventory'].append(p['planning_budget'][PLAN]['current_inventory'][0])
            elif mutation == 'inventory_hash': p['planning_budget'][PLAN]['current_inventory_sha256'] = '0' * 64
            elif mutation == 'method_count': p['planning_budget'][PLAN]['method_count'] = 712
            elif mutation == 'class_count': p['planning_budget'][PLAN]['class_count'] = 147
            elif mutation == 'new_methods': p['planning_budget'][PLAN]['new_methods'].pop()
            elif mutation == 'record': p['estimate_provenance']['methods'].remove(row)
            elif mutation == 'record_cost': row['seconds'] = 60
            elif mutation == 'missing_shared_map': row.pop('shared_helper_source_sha256')
            elif mutation == 'shared_hash': row['shared_helper_source_sha256'][next(iter(row['shared_helper_source_sha256']))] = '0' * 64
            else: row[{'record_file': 'test_file_sha256', 'record_declaration': 'declaration_sha256', 'record_non_test': 'all_non_test_source_sha256'}[mutation]] = '0' * 64
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                self.with_profile(p)

    def test_each_test_or_shared_helper_change_fails_even_with_recomputed_custom_hashes(self):
        files = sorted({Path(row['test_path']).name for row in self.new.values()} | {Path(name).name for row in self.new.values() for name in row['shared_helper_source_sha256']})
        for name in files:
            with tempfile.TemporaryDirectory() as directory:
                ui = Path(directory) / 'ui'; shutil.copytree(UI, ui)
                target = ui / name; target.write_text(target.read_text() + '\n// changed source\n')
                p = deepcopy(self.profile)
                for row in p['estimate_provenance']['methods']:
                    if row['method'] not in self.new: continue
                    if Path(row['test_path']).name == name:
                        row['test_file_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
                        source = re.sub(r'(?m)^    (func (test\w+)\b[\s\S]*?^    })', '', target.read_text())
                        row['all_non_test_source_sha256'] = hashlib.sha256(re.sub(r'(?m)^[ \t]*\n', '', source).encode()).hexdigest()
                    for helper in row['shared_helper_source_sha256']:
                        if Path(helper).name == name: row['shared_helper_source_sha256'][helper] = hashlib.sha256(target.read_bytes()).hexdigest()
                with self.subTest(file=name), self.assertRaises(ValueError): self.with_profile(p, ui)

    def test_copied_renamed_classes_methods_and_helpers_cannot_disguise_current_source(self):
        for remove_semantic_markers in (False, True):
            with tempfile.TemporaryDirectory() as directory:
                ui = Path(directory) / 'ui'; shutil.copytree(UI, ui)
                for path in list(ui.glob('ProjectStoryTemplate*.swift')):
                    source = path.read_text().replace('ProjectStoryTemplate', 'RenamedBudget').replace('GapPreviewCancelApplySaveAndRestore', 'Cheap')
                    if remove_semantic_markers:
                        source = source.replace('projectStoryTemplate.', 'renamedFixture.').replace('--project-story-template', '--renamed-fixture')
                    target = path.with_name(path.name.replace('ProjectStoryTemplate', 'RenamedBudget'))
                    path.unlink(); target.write_text(source)
                profile = {'version': 1, 'unobserved_method_seconds': 1, 'method_seconds': {}}
                with self.subTest(remove_markers=remove_semantic_markers), self.assertRaises(ValueError):
                    self.with_profile(profile, ui)

    def test_each_missing_new_method_or_helper_fails_with_old_profile(self):
        files = sorted({Path(row['test_path']).name for row in self.new.values()} | {'ProjectStoryTemplateFlowSupport.swift'})
        for name in files:
            with tempfile.TemporaryDirectory() as directory:
                ui = Path(directory) / 'ui'; shutil.copytree(UI, ui); (ui / name).unlink()
                with self.subTest(file=name), self.assertRaises(ValueError): self.with_profile(self.prior, ui)

    def test_removing_all_six_classes_but_leaving_helper_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = Path(directory) / 'ui'; shutil.copytree(UI, ui)
            for row in self.new.values(): (ui / Path(row['test_path']).name).unlink()
            with self.assertRaises(ValueError): self.with_profile(self.prior, ui)

    def test_missing_or_corrupt_trusted_contract_fails_with_current_or_old_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            contract = Path(directory) / 'contract.json'
            for mode in ('missing', 'floor', 'helper', 'declaration'):
                if mode != 'missing':
                    data = deepcopy(self.contract); row = next(iter(data['required_floors'].values()))
                    if mode == 'floor': row['seconds'] = 1
                    elif mode == 'helper': row['shared_helper_source_sha256'][next(iter(row['shared_helper_source_sha256']))] = '0' * 64
                    else: row['declaration_sha256'] = '0' * 64
                    contract.write_text(json.dumps(data))
                with patch.object(shard, 'STORY_TEMPLATE_CONTRACT_PATH', contract):
                    for profile in (self.profile, self.prior):
                        with self.subTest(mode=mode), self.assertRaises(ValueError): self.with_profile(profile)

    def test_real_historical_source_and_profile_keep_exact_old_totals(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            r2 = materialize_pre_story_ui(root / 'r2')
            actual = self.with_profile(self.prior, r2)
            self.assertEqual((sum(shard.discover(r2).values()), len(actual)), (712, 147))
            self.assertAlmostEqual(sum(actual.values()), 92687.381, places=8)
            older = materialize_pre_club_ui(root / 'older')
            actual = self.with_profile(before_club_parity(self.prior), older)
            self.assertEqual((sum(shard.discover(older).values()), len(actual)), (710, 146))
            self.assertAlmostEqual(sum(actual.values()), 91064.732, places=8)
            with self.assertRaises(ValueError): self.with_profile(self.profile, r2)

    def test_arbitrary_unrelated_custom_profile_retains_original_measurement_semantics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'Example.swift').write_text('final class Example: XCTestCase { func testOne() {} }')
            p = {'version': 1, 'unobserved_method_seconds': 60, 'method_seconds': {'Example.testOne': 17}, 'estimated_method_seconds': {'Example.testOne': 700}}
            self.assertEqual(self.with_profile(p, root), {'Example': 17})

    def test_exact_profile_inverse_and_frozen_r2_file_identity(self):
        self.assertEqual(canonical(self.profile), CURRENT_PROFILE_SHA256)
        self.assertEqual(canonical(self.prior), BASELINE_PROFILE_SHA256)
        self.assertEqual(self.prior, json.loads(historical_pre_story_source(PROFILE).read_text()))
        self.assertEqual(before_story_template(self.prior), self.prior)
        self.assertEqual(before_story_template(before_club_parity(self.profile)), before_club_parity(self.profile))
        for original, row in source_index()['historical_sources'].items():
            self.assertEqual(hashlib.sha256(historical_pre_story_source(ROOT / original).read_bytes()).hexdigest(), row['sha256'])
        old = historical_pre_story_module(ROOT / 'tools/run_ui_shard.py', 'story_history_runner_test')
        gates = historical_pre_story_module(ROOT / 'tools/ci_gates.py', 'story_history_gates_test')
        self.assertEqual((old.DEFAULT_SHARD_COUNT, gates.SHARD_COUNT), (67, 67))

    def test_history_inverse_rejects_all_partial_or_mutated_current_layers(self):
        for mutation in ('new_cost', 'old_cost', 'plan', 'new_record', 'old_record', 'inventory', 'reserve', 'shards', 'old_observation'):
            p = deepcopy(self.profile)
            if mutation == 'new_cost': p['estimated_method_seconds'][next(iter(self.new))] = 60
            elif mutation == 'old_cost': p['method_seconds'][next(iter(p['method_seconds']))] = 1
            elif mutation == 'plan': p['planning_budget'].pop(PLAN)
            elif mutation == 'new_record': p['estimate_provenance']['methods'].pop()
            elif mutation == 'old_record': p['estimate_provenance']['methods'][0]['seconds'] = 1
            elif mutation == 'inventory': p['planning_budget'][PLAN]['current_inventory'].pop()
            elif mutation == 'duplicate_inventory': p['planning_budget'][PLAN]['current_inventory'].append(p['planning_budget'][PLAN]['current_inventory'][0])
            elif mutation == 'inventory_hash': p['planning_budget'][PLAN]['current_inventory_sha256'] = '0' * 64
            elif mutation == 'method_count': p['planning_budget'][PLAN]['method_count'] = 712
            elif mutation == 'class_count': p['planning_budget'][PLAN]['class_count'] = 147
            elif mutation == 'new_methods': p['planning_budget'][PLAN]['new_methods'].pop()
            elif mutation == 'reserve': p['planning_budget'][PLAN]['startup_reserve_seconds'] = 0
            elif mutation == 'shards': p['planning_budget'][PLAN]['shard_count'] = 67
            else: p['run117_method_observations'].pop()
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError): before_story_template(p)

    def test_history_materialization_is_byte_exact_and_rejects_contamination(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = materialize_pre_story_ui(directory)
            rows = source_index()['baseline_ui_sources']
            self.assertEqual({p.name for p in ui.glob('*.swift')}, {Path(row['path']).name for row in rows})
            for row in rows:
                self.assertEqual(hashlib.sha256((ui / Path(row['path']).name).read_bytes()).hexdigest(), row['sha256'])
            self.assertFalse(any(ui.glob('ProjectStoryTemplate*.swift')))
            (ui / 'ProjectStoryTemplateForeign.swift').write_text('// not historical\n')
            with self.assertRaises(AssertionError): materialize_pre_story_ui(directory)

    def test_delivered_budget_and_inventory_recompute_from_actual_live_source(self):
        doc = json.loads((ROOT / 'docs/project-story-template-ui-budget.json').read_text())
        self.assertEqual(doc['plan'], self.plan)
        costs = self.decimal_costs(); groups = shard.partition(costs, 73); counts = shard.discover(UI)
        self.assertEqual(doc['class_costs'], {k: str(v) for k, v in sorted(costs.items())})
        self.assertEqual(len(doc['shards']), 73)
        for row, group in zip(doc['shards'], groups):
            self.assertEqual(row['classes'], group)
            self.assertEqual(row['methods'], sum(counts[name] for name in group))
            self.assertEqual(Decimal(row['projected_seconds_with_startup']), sum(costs[name] for name in group) + 300)
        inventory = json.loads((ROOT / 'docs/ui-shard-inventory.json').read_text())
        self.assertEqual((inventory['total_tests'], inventory['total_classes'], inventory['shard_count']), (718, 153, 73))
        self.assertEqual(inventory['classes'], counts)
        self.assertEqual(inventory['shards'], groups)


if __name__ == '__main__':
    unittest.main()
