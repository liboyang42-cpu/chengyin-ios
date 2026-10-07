"""Pre-club source/profile identities remain exact through the new planning layer."""
from tools.tests.story_template_budget_history import before_story_template
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest

from tools import run_ui_shard
from tools.tests.club_parity_budget_history import (
    BASELINE_PROFILE_SHA256, CURRENT_PROFILE_SHA256, NEW_CLASS,
    before_club_parity, canonical, historical_pre_club_module,
    historical_pre_club_source, materialize_pre_club_ui, source_index,
)
from tools.tests.creator_pending_budget_history import before_creator_pending, materialize_pre_creator_ui
from tools.tests.combined_native_budget_history import before_combined, materialize_independent_ui
from tools.tests.story_media_budget_history import before_story_media, materialize_historical_pre_media_ui
from tools.tests.reviewed_feature_budget_history import before_reviewed_features, materialize_historical_pre_feature_ui

ROOT = Path(__file__).resolve().parents[2]
ADMIN = 'ClubOperationsFlowTests.testAdminProfileHasNoOwnerSettingsOrRoleActions'


class ClubParityBudgetHistoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.current = before_story_template(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        cls.previous = before_club_parity(cls.current)

    def test_exact_current_inverse_keeps_647_observations_and_every_old_cost(self):
        original = canonical(self.current)
        prior = before_club_parity(self.current)
        self.assertEqual(original, CURRENT_PROFILE_SHA256)
        self.assertEqual(canonical(self.current), original)
        self.assertEqual(canonical(prior), BASELINE_PROFILE_SHA256)
        self.assertEqual(prior, self.previous)
        self.assertEqual(prior['method_seconds'], self.current['method_seconds'])
        self.assertEqual(prior['method_seconds'][ADMIN], 27.351)
        self.assertEqual(len(prior['run117_method_observations']), 647)
        self.assertEqual(prior['run117_method_observations'], self.current['run117_method_observations'])
        for key in prior:
            if key.endswith('_method_observations') or key == 'superseded_method_observations':
                self.assertEqual(prior[key], self.current[key], key)
        for key, seconds in prior['estimated_method_seconds'].items():
            self.assertEqual(seconds, self.current['estimated_method_seconds'][key])
        self.assertEqual(prior['estimate_provenance']['methods'], self.current['club_parity_previous_estimate_provenance'])
        self.assertNotIn('method_planning_floors', prior)
        self.assertNotIn('club_parity_previous_estimate_provenance', prior)
        self.assertNotIn('reviewed_club_parity_replan', prior['planning_budget'])

    def test_already_historical_profiles_are_accepted_without_change(self):
        histories = [self.previous, before_creator_pending(self.current),
                     before_combined(self.current, 'media'), before_combined(self.current, 'map'),
                     before_story_media(self.current), before_reviewed_features(self.current)]
        for profile in histories:
            with self.subTest(canonical=canonical(profile)):
                self.assertEqual(before_club_parity(profile), profile)

    def test_every_profile_mutation_fails_closed(self):
        for mutation in ('new_cost', 'old_cost', 'floor', 'floor_source', 'floor_declaration',
                         'floor_helpers', 'old_estimate', 'provenance', 'saved_provenance',
                         'observations', 'inventory', 'reserve', 'count', 'older_plan',
                         'missing_floor', 'missing_previous_provenance', 'missing_plan'):
            profile = deepcopy(self.current)
            plan = profile['planning_budget']['reviewed_club_parity_replan']
            if mutation == 'new_cost':
                profile['estimated_method_seconds'][plan['new_methods'][0]] = 1
            elif mutation == 'old_cost':
                profile['method_seconds'][ADMIN] = 1
            elif mutation == 'floor':
                profile['method_planning_floors'][ADMIN]['seconds'] = 1
            elif mutation in ('floor_source', 'floor_declaration', 'floor_helpers'):
                key = {'floor_source': 'test_file_sha256', 'floor_declaration': 'declaration_sha256',
                       'floor_helpers': 'all_non_test_source_sha256'}[mutation]
                profile['method_planning_floors'][ADMIN][key] = '0' * 64
            elif mutation == 'old_estimate':
                profile['estimated_method_seconds'][next(iter(self.previous['estimated_method_seconds']))] = 1
            elif mutation == 'provenance':
                profile['estimate_provenance']['methods'][-1]['test_file_sha256'] = '0' * 64
            elif mutation == 'saved_provenance':
                profile['club_parity_previous_estimate_provenance'][0]['seconds'] = 1
            elif mutation == 'observations':
                profile['run117_method_observations'].pop()
            elif mutation == 'inventory':
                plan['current_inventory'].pop()
            elif mutation == 'reserve':
                plan['startup_reserve_seconds'] = 0
            elif mutation == 'count':
                plan['shard_count'] = 65
            elif mutation == 'older_plan':
                profile['planning_budget']['reviewed_creator_pending_replan']['current_inventory'].pop()
            elif mutation == 'missing_floor':
                profile.pop('method_planning_floors')
            elif mutation == 'missing_previous_provenance':
                profile.pop('club_parity_previous_estimate_provenance')
            else:
                profile['planning_budget'].pop('reviewed_club_parity_replan')
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                before_club_parity(profile)

    def test_each_remaining_club_marker_without_its_plan_is_rejected(self):
        for marker in ('saved_provenance', 'floor', 'new_estimate', 'new_provenance'):
            profile = deepcopy(self.previous)
            if marker == 'saved_provenance':
                profile['club_parity_previous_estimate_provenance'] = deepcopy(self.current['club_parity_previous_estimate_provenance'])
            elif marker == 'floor':
                profile['method_planning_floors'] = deepcopy(self.current['method_planning_floors'])
            elif marker == 'new_estimate':
                method = self.current['planning_budget']['reviewed_club_parity_replan']['new_methods'][0]
                profile['estimated_method_seconds'][method] = self.current['estimated_method_seconds'][method]
            else:
                profile['estimate_provenance']['methods'].append(deepcopy(self.current['estimate_provenance']['methods'][-1]))
            with self.subTest(marker=marker), self.assertRaises(AssertionError):
                before_club_parity(profile)

    def test_every_historical_inventory_excludes_the_new_class(self):
        stages = [(materialize_pre_club_ui, (), 710, 146),
                  (materialize_pre_creator_ui, (), 707, 143),
                  (materialize_independent_ui, ('media',), 704, 141),
                  (materialize_independent_ui, ('map',), 664, 108),
                  (materialize_historical_pre_media_ui, (), 661, 107),
                  (materialize_historical_pre_feature_ui, (), 660, 102)]
        for materialize, args, methods, classes in stages:
            with self.subTest(stage=materialize.__name__, args=args), tempfile.TemporaryDirectory() as directory:
                destination = materialize(directory, *args)
                counts = run_ui_shard.discover(destination)
                self.assertEqual((sum(counts.values()), len(counts)), (methods, classes))
                self.assertNotIn(NEW_CLASS, counts)
                self.assertFalse((destination / (NEW_CLASS + '.swift')).exists())

    def test_pre_club_materialization_is_full_byte_exact_and_rejects_contamination(self):
        index = source_index()
        with tempfile.TemporaryDirectory() as directory:
            destination = materialize_pre_club_ui(directory)
            inventory = []
            for row in index['baseline_ui_sources']:
                source = destination / Path(row['path']).name
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), row['sha256'])
                text = source.read_text()
                methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', text)
                if methods:
                    cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text)
                    self.assertEqual(len(cases), 1)
                    inventory.extend(cases[0] + '.' + name for name in methods)
            self.assertEqual(len(inventory), len(set(inventory)))
            self.assertEqual(hashlib.sha256('\n'.join(sorted(inventory)).encode()).hexdigest(), index['baseline_inventory_sha256'])
            (destination / (NEW_CLASS + '.swift')).write_text('// Must never join old discovery.\n')
            with self.assertRaises(AssertionError):
                materialize_pre_club_ui(directory)
        with self.assertRaises(AssertionError):
            historical_pre_club_source(ROOT / 'Tests/AppUITests' / (NEW_CLASS + '.swift'))

    def test_pre_club_runner_gate_workflow_and_all_11_club_methods_are_pinned(self):
        index = source_index()
        for original, row in index['historical_sources'].items():
            source = historical_pre_club_source(ROOT / original)
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), row['sha256'])
        source = historical_pre_club_source(ROOT / 'Tests/AppUITests/ClubOperationsFlowTests.swift').read_text()
        self.assertEqual(len(re.findall(r'\bfunc\s+(test\w+)\s*\(', source)), 11)
        shard = historical_pre_club_module(ROOT / 'tools/run_ui_shard.py', 'history_pre_club_shard')
        gates = historical_pre_club_module(ROOT / 'tools/ci_gates.py', 'history_pre_club_gates')
        self.assertEqual((shard.DEFAULT_SHARD_COUNT, gates.SHARD_COUNT, index['baseline_shard_count']), (65, 65, 65))
        workflow = historical_pre_club_source(ROOT / '.github/workflows/native-ios.yml').read_text()
        outputs = re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}', workflow, re.M)
        self.assertEqual(outputs, [(str(number), str(number)) for number in range(65)])
        self.assertIn('--count 65 ', workflow)
        self.assertIn('--deadline-seconds 1800', workflow)
