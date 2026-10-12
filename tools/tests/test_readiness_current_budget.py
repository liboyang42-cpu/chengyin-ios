"""Current-source budget/entry regressions. These are not Apple timing observations."""
import ast
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'tools/run138_editor_readiness.py'


def budget_functions():
    source = RUNNER.read_text()
    tree = ast.parse(source)
    namespace = {'Path': Path, 'math': math, 're': re,
                 'digest': lambda raw: hashlib.sha256(raw).hexdigest()}
    selected = []
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == '_PRODUCT_UI_BUDGET' for t in node.targets):
            selected.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name == 'validate_product_ui_budget':
            selected.append(node)
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(RUNNER), 'exec'), namespace)
    return namespace


class CurrentReadinessBudgetTests(unittest.TestCase):
    def setUp(self):
        self.n = budget_functions()
        self.c = json.loads((ROOT / 'tools/run138_editor_readiness_contract.json').read_bytes())

    def validate(self, value=None, root=ROOT):
        return self.n['validate_product_ui_budget'](value or self.c, root / 'Tests/AppUITests', root)

    def test_exact_current_product_sources_and_every_method_cost_validate(self):
        self.assertEqual(self.validate(), self.c['product_ui_budget']['class_increment_seconds'])
        self.assertFalse(self.c['product_ui_budget']['measured'])
        for row in self.c['product_ui_budget']['methods'].values():
            self.assertGreater(row['seconds'], 0)
            self.assertLessEqual(row['seconds'], 900)
            self.assertFalse(row['measured'])

    def test_nine_repaired_complete_methods_retain_strict_cap(self):
        expected = {'MerchantTemplateRuleStepsFlowTests': [790, 880],
                    'MerchantTemplateHintsFlowTests': [750, 900],
                    'MerchantTemplateStoryTimelineFlowTests': [710, 860, 690],
                    'MerchantStoreIndustryFlowTests': [790],
                    'MerchantRegistrationAvailabilityFlowTests': [630]}
        rows = self.c['product_ui_budget']['methods']
        for cls, costs in expected.items():
            actual = [r['seconds'] for k, r in rows.items()
                      if k.startswith(cls + '.') and 'local_reveal_calls' in r]
            self.assertEqual(actual, costs)

    def test_full_search_assumptions_not_discounted(self):
        a = self.c['product_ui_budget']['assumptions']
        self.assertEqual((a['per_reveal_seconds'], a['per_reveal_maximum_swipes'], a['per_reveal_maximum_viewports']), (40, 10, 11))
        self.assertEqual(a['per_local_reveal_maximum_swipes'], 1)
        self.assertEqual(a['per_local_reveal_maximum_viewports'], 2)
        self.assertEqual(a['per_local_reveal_seconds'], a['local_reveal_initial_lookup_seconds'] + 2 * (a['local_reveal_query_phase_seconds'] + a['local_reveal_gesture_and_settle_seconds']))
        self.assertEqual(a['per_direct_ax_query_seconds'], 2)

    def test_unknown_cost_discount_is_rejected(self):
        c = deepcopy(self.c)
        next(iter(c['product_ui_budget']['methods'].values()))['seconds'] -= 10
        with self.assertRaises(ValueError):
            self.validate(c)

    def test_same_contract_and_module_cannot_relax_900_guard(self):
        c = deepcopy(self.c)
        row = next(iter(c['product_ui_budget']['methods'].values()))
        row.update(lifecycle_seconds=1000, explicit_wait_seconds=0, bounded_reveal_calls=0,
                   direct_action_count=0, direct_ax_assertion_count=0, typed_characters=0,
                   unrounded_seconds=1000, seconds=1000)
        self.n['_PRODUCT_UI_BUDGET'] = c['product_ui_budget']
        with self.assertRaisesRegex(ValueError, 'action/wait allowance'):
            self.validate(c)

    def test_actual_ui_inventory_matches_current_entry_not_old_domain(self):
        keys = []
        classes = []
        for p in (ROOT / 'Tests/AppUITests').glob('*.swift'):
            methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', p.read_text())
            if not methods:
                continue
            [owner] = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', p.read_text())
            classes.append(owner)
            keys.extend(owner + '.' + m for m in methods)
        self.assertEqual((len(keys), len(classes)), (901, 201))
        self.assertEqual((self.c['method_count'], self.c['class_count_after']), (901, 201))
        source = RUNNER.read_text()
        self.assertIn('len(keys) != 901 or len(classes) != 201', source)
        self.assertIn('len(keys) != 736 or len(classes) != 162', source)
        self.assertNotIn('31193.948', source)

    def test_stale_participation_declaration_and_added_work_are_both_repaired(self):
        row = self.c['product_ui_budget']['methods']['MerchantTemplateParticipationPlanFlowTests.testCompletePlanReviewCannotSubmitAndCancelRetainsLocalFields']
        self.assertEqual((row['bounded_reveal_calls'], row['direct_ax_assertion_count'], row['seconds']), (12, 7, 660))

    def test_local_switch_keeps_native_track_and_all_visibility_guards(self):
        for cls in ['MerchantTemplateHintsFlowTests', 'MerchantTemplateStoryTimelineFlowTests']:
            source = (ROOT / ('Tests/AppUITests/' + cls + '.swift')).read_text()
            self.assertIn('element.descendants(matching: .switch).firstMatch', source)
            self.assertIn('element.exists && element.isEnabled && control.isEnabled', source)
            self.assertIn('revealFixtureElement(control, in: app, maximumSwipes: 0)', source)
            self.assertNotIn('tapFixtureNativeSwitch(', source)
            self.assertIn('let maximumSwipes = towardTop ? 10 : 1', source)

    def test_native_alert_resolution_rejects_duplicate_business_leaves(self):
        for cls in ['MerchantTemplateRuleStepsFlowTests', 'MerchantTemplateHintsFlowTests', 'MerchantTemplateStoryTimelineFlowTests', 'MerchantStoreIndustryFlowTests']:
            source = (ROOT / ('Tests/AppUITests/' + cls + '.swift')).read_text()
            self.assertIn('let candidates = matches.allElementsBoundByAccessibilityElement', source)
            self.assertIn('let leaves = candidates.filter', source)
            self.assertIn('guard !candidates.isEmpty else { return matches.firstMatch }', source)
            self.assertLess(source.index('guard !candidates.isEmpty'), source.index('XCTAssertEqual(leaves.count, 1)'))
            self.assertEqual(source.count('matches.allElementsBoundByAccessibilityElement'), 1)
            self.assertIn('$0.descendants(matching: .button).count == 0', source)
            self.assertIn('XCTAssertEqual(leaves.count, 1)', source)

    def test_registration_fixture_is_a_real_editable_rejection_state(self):
        source = (ROOT / 'Core/MerchantContentSyntheticFixtures.swift').read_text()
        [raw] = re.findall(r'public static let registration = #"(.*?)"#', source)
        value = json.loads(raw)
        self.assertEqual((value['status'], value['auditStatus']), (2, 2))
        self.assertEqual(value['reason'], 'Add a clear venue description')
        rules = (ROOT / 'Core/MerchantContentDomain.swift').read_text()
        self.assertIn('guard let status, let auditStatus else { return false }', rules)
        self.assertIn('(status == 0 && auditStatus == 0)', rules)
        self.assertIn('((status == 2 || status == 3) && auditStatus == 2)', rules)
        # Independent exhaustive state table of the unchanged source rule.
        allowed = {(s, a) for s in range(5) for a in range(4)
                   if (s == 0 and a == 0) or ((s == 2 or s == 3) and a == 2)}
        self.assertEqual(allowed, {(0, 0), (2, 2), (3, 2)})
        self.assertNotIn((2, 0), allowed)

    def test_history_composes_only_after_actual_current_authentication(self):
        source = (ROOT / 'tools/run138_current_source_projection.py').read_text()
        tree = ast.parse(source)
        node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'historical_entry_bytes')
        body = ast.get_source_segment(source, node)
        self.assertLess(body.index('club_authenticated_transaction(root)'), body.index('club_predecessor_source(relative, raw)'))
        self.assertLess(body.index('club_predecessor_source(relative, raw)'), body.index('return original_entry_bytes'))

    def test_complete_weights_calculation_keeps_existing_authenticated_boundary(self):
        source = RUNNER.read_text()
        tree = ast.parse(source)
        wrapper = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'weights')
        body = ast.get_source_segment(source, wrapper)
        self.assertIn('from tools.club_customer_directory_admission import club_authenticated_transaction', body)
        self.assertIn('with club_authenticated_transaction(root):', body)
        self.assertIn('return _weights(directory, profile_path, root)', body)
        calculation = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == '_weights')
        full = ast.get_source_segment(source, calculation)
        self.assertIn('validate_current(directory, profile_path, root)', full)
        self.assertIn('previous_directory(directory, profile_path, root)', full)
        self.assertIn('validate_product_ui_budget(c, directory, root)', full)

    def test_actual_root_uses_finite_guarded_predecessor_before_old_stage(self):
        source = (ROOT / 'tools/run138_current_source_projection.py').read_text()
        self.assertIn("predecessor.load('tools/run138_current_source_projection.py')", source)
        self.assertIn('historical.frozen_context(stage, predecessor.root)', source)
        self.assertIn('predecessor.verify()', source)
        self.assertLess(source.index('current.validate_current('), source.index('predecessor = club_original_current_context(root)'))


if __name__ == '__main__':
    unittest.main()
