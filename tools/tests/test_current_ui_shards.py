"""Exact current complete-method union and strict shard-limit negative controls."""
from copy import deepcopy
import json
from pathlib import Path
import unittest
from tools import run138_current_ui_shards as planner

ROOT = Path(__file__).resolve().parents[2]


class CurrentUIShardTests(unittest.TestCase):
    def setUp(self):
        self.inventory = {c: [c + '/testOne', c + '/testTwo'] for c in planner.SPLIT_CLASSES}
        self.costs = {c: 1600 for c in planner.SPLIT_CLASSES}
        self.budget = {'methods': {m.replace('/', '.'): {'seconds': 800, 'existing_method_increment': False, 'measured': False}
                                  for methods in self.inventory.values() for m in methods}}
        for i in range(79):
            c = 'RetainedClass' + str(i)
            self.inventory[c] = [c + '/testOriginal']
            self.costs[c] = 600
        self.plan = planner.make_plan(self.costs, self.inventory, self.budget)

    def validate(self, groups=None, expansion=None):
        return planner.validate_partition(groups or self.plan['shards'], self.plan['unit_seconds'],
                                          expansion or self.plan['unit_methods'], self.inventory)

    def test_every_complete_method_occurs_exactly_once_and_old_classes_stay_whole(self):
        self.validate()
        self.assertTrue(all(v <= 1500 for v in self.plan['shard_seconds']))
        self.assertEqual(sum(self.plan['shard_method_counts']), sum(map(len, self.inventory.values())))
        self.assertEqual(len([u for u in self.plan['unit_seconds'] if '/' not in u]), 79)
        self.assertEqual(len([u for u in self.plan['unit_seconds'] if '/' in u]), 12)

    def test_missing_shard_fails(self):
        with self.assertRaises(ValueError): self.validate(self.plan['shards'][:-1])

    def test_repeated_unit_fails(self):
        groups = deepcopy(self.plan['shards']); groups[0].append(groups[1][0])
        with self.assertRaises(ValueError): self.validate(groups)

    def test_missing_method_in_expansion_fails(self):
        expansion = deepcopy(self.plan['unit_methods']); expansion[next(iter(expansion))] = []
        with self.assertRaises(ValueError): self.validate(expansion=expansion)

    def test_class_method_overlap_fails(self):
        expansion = deepcopy(self.plan['unit_methods']); names = list(expansion)
        expansion[names[0]] += expansion[names[1]]
        with self.assertRaises(ValueError): self.validate(expansion=expansion)

    def test_overloaded_shard_cannot_be_waived(self):
        groups = deepcopy(self.plan['shards']); groups[0] += groups.pop()
        groups[0] += groups.pop()
        with self.assertRaisesRegex(ValueError, '1500'): self.validate(groups)

    def test_method_over_900_fails_even_if_class_sum_matches(self):
        c = next(iter(planner.SPLIT_CLASSES)); key = self.inventory[c][0].replace('/', '.')
        self.budget['methods'][key]['seconds'] = 901; self.costs[c] = 1701
        with self.assertRaisesRegex(ValueError, '900'): planner.make_plan(self.costs, self.inventory, self.budget)

    def test_partial_method_increment_cannot_replace_complete_method(self):
        next(iter(self.budget['methods'].values()))['existing_method_increment'] = True
        with self.assertRaises(ValueError): planner.make_plan(self.costs, self.inventory, self.budget)

    def test_unapproved_new_split_class_fails(self):
        self.costs['RetainedClass0'] = 1501
        with self.assertRaisesRegex(ValueError, 'allowlist'): planner.make_plan(self.costs, self.inventory, self.budget)

    def test_unaccounted_old_class_allowance_fails(self):
        self.costs[next(iter(planner.SPLIT_CLASSES))] += 1
        with self.assertRaisesRegex(ValueError, 'allowance'): planner.make_plan(self.costs, self.inventory, self.budget)

    def test_source_bound_six_classes_have_independent_lifecycles(self):
        for name in planner.SPLIT_CLASSES:
            source = (ROOT / ('Tests/AppUITests/' + name + '.swift')).read_text()
            self.assertIn('private var app: XCUIApplication?', source)
            self.assertIn('let app = XCUIApplication()', source)
            self.assertIn('app.launch()', source)
            self.assertIn('continueAfterFailure = false', source)
            self.assertIn('app?.terminate(); app = nil', source)
            self.assertNotIn('static var', source)
            self.assertNotIn('static let', source)
            self.assertNotIn('override class func', source)

    def test_direct_cli_binds_only_its_verified_repository_import_root(self):
        source = (ROOT / 'tools/run_ui_shard.py').read_text()
        self.assertIn('ROOT = pathlib.Path(__file__).resolve().parents[1]', source)
        self.assertIn('if str(ROOT) not in sys.path:', source)
        self.assertIn('sys.path.insert(0, str(ROOT))', source)
        self.assertLess(source.index('sys.path.insert(0, str(ROOT))'), source.index('def measured_weights'))
