"""Source-bound Run130 receipt budgets and fail-closed historical projections.

These are local planning proofs, not Apple timing measurements or permission to
publish. Mutations use temporary copies; the accepted source evidence is fixed.
"""
from contextlib import contextmanager
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import ci_gates, run130_receipt_planning as layer, run_ui_shard as shard

from tools.branch_history_handshake_planning import frozen_receipt_context
RETAINED_RECEIPT_CONTEXT = frozen_receipt_context()
ROOT = RETAINED_RECEIPT_CONTEXT.root
UI = ROOT / 'Tests/AppUITests'
PROFILE = ROOT / 'tools/ui_duration_weights.json'
HELPER = 'ProjectSubmissionEvidenceUITestSupport.swift'
SIX_HELD_CLASSES = (
    'ApprovedReleaseRecoveryFlowTests',
    'ApprovedTopicReviewCurrentChineseFlowTests',
    'ApprovedTopicReviewUnknownFlowTests',
    'ApprovedTopicSelectedCoverChineseFlowTests',
    'ProjectStoryAudioRecoveryFlowTests',
    'OwnedTopicCoverRecoveryFlowTests',
)


class ReceiptPlanningBudgetTests(unittest.TestCase):
    def setUp(self):
        self.profile = json.loads(PROFILE.read_text())
        self.contract = layer.contract()

    def run_profile(self, profile, ui=UI):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'profile.json'
            path.write_text(json.dumps(profile))
            return shard.measured_weights(ui, path)

    @contextmanager
    def copied_ui(self, name='AppUITests'):
        with tempfile.TemporaryDirectory() as temporary:
            ui = Path(temporary) / name
            shutil.copytree(UI, ui)
            yield ui

    @contextmanager
    def copied_root_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in [
                'tools/run130_receipt_planning_contract.json',
                'Tests/ContractChecks/fixtures/run130_submission_evidence.json',
                *self.contract['critical_App_sources'],
            ]:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((ROOT / relative).read_bytes())
            with patch.object(layer, 'ROOT', root):
                yield root

    def test_exact_contract_and_source_evidence_hashes_are_pinned(self):
        raw = (ROOT / 'tools/run130_receipt_planning_contract.json').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), layer.CONTRACT_SHA256)
        self.assertEqual(layer.validate_current(UI), self.contract)
        self.assertEqual(self.contract['source_contract_sha256'],
                         layer.source_layer().CONTRACT_SHA256)

    def test_all_736_methods_162_classes_and_every_ui_file_are_bound(self):
        counts = shard.discover(UI)
        self.assertEqual((sum(counts.values()), len(counts)), (736, 162))
        self.assertEqual(len(self.contract['current_inventory']), 736)
        self.assertEqual(len(set(self.contract['current_inventory'])), 736)
        self.assertEqual(len(self.contract['current_ui_sources']), 168)
        self.assertEqual(
            {p.name: {'sha256': layer.digest(p.read_bytes())} for p in UI.glob('*.swift')},
            self.contract['current_ui_sources'],
        )

    def test_exactly_18_whole_methods_and_twelve_902_to_908_exceptions(self):
        rows = self.contract['required_floors']
        self.assertEqual(len(rows), 18)
        exceptions = {key: row['candidate_complete_method_seconds']
                      for key, row in rows.items()
                      if row['candidate_complete_method_seconds'] > 900}
        self.assertEqual(exceptions, layer.FIXED_EXCEPTIONS)
        self.assertEqual(exceptions, self.contract['fixed_over900_exceptions'])
        self.assertEqual(len(exceptions), 12)
        self.assertEqual(sorted(exceptions.values()),
                         [902, 902, 904, 904, 904, 904, 906, 906, 908, 908, 908, 908])
        self.assertEqual(self.profile['planning_budget'][layer.PLAN]
                         ['source_bound_over900_exceptions'], exceptions)

    def test_real_method_calls_charge_118_seconds_without_unused_helper_calls(self):
        added = 0
        for key, row in self.contract['required_floors'].items():
            with self.subTest(method=key):
                source = (ROOT / row['path']).read_text()
                [(body, method)] = re.findall(layer.PATTERN, source)
                self.assertEqual(key.split('.')[1], method)
                helpers = {name: text for name, text in re.findall(
                    r'(?m)^    private func (\w+)(\([^\n]*[\s\S]*?^    })', source)}

                def executed_sources(text, ancestors=()):
                    expanded = text
                    for name, helper in helpers.items():
                        calls = len(re.findall(r'(?<![\w.])' + re.escape(name) + r'\s*\(', text))
                        if not calls:
                            continue
                        self.assertNotIn(name, ancestors, 'Recursive helper needs explicit costing')
                        expanded += calls * executed_sources(helper, ancestors + (name,))
                    return expanded

                executed = executed_sources(body)
                receipts = executed.count('phase: .receipt')
                histories = executed.count('phase: .history')
                absences = len(re.findall(
                    r'XCTAssertEqual\(app\.descendants\(matching: \.any\)'
                    r'\.matching\(identifier: "projectSubmission\.[^"]+"\)\.count, 0\)', executed))
                unused = source.count('assertProjectSubmissionEvidenceValue(') - receipts - histories
                self.assertEqual((receipts, histories, absences, unused),
                                 (row['positive_receipt_lookups'], row['positive_history_lookups'],
                                  row['global_absence_assertions'], row['unused_helper_calls_not_charged']))
                delta = 2 * (receipts + histories + absences)
                self.assertEqual(delta, row['added_unmeasured_seconds'])
                self.assertEqual(row['candidate_complete_method_seconds'],
                                 row['historical_floor_seconds'] + delta)
                self.assertIs(row['measured'], False)
                added += delta
        self.assertEqual(added, 118)
        self.assertEqual(self.contract['additional_seconds'], 118)
        self.assertIs(self.profile['planning_budget'][layer.PLAN]['measured'], False)

    def test_profile_projection_restores_every_previous_value_without_mutating_input(self):
        original = deepcopy(self.profile)
        previous = layer.previous_profile(self.profile)
        self.assertEqual(self.profile, original)
        frozen = json.loads((layer.FIXTURES / 'tools/ui_duration_weights.json').read_text())
        self.assertEqual(previous, frozen)
        self.assertEqual(layer.canonical(previous), self.contract['previous_profile_canonical_sha256'])
        self.assertEqual(layer.canonical(self.profile), self.contract['current_profile_canonical_sha256'])
        self.assertNotIn(layer.PLAN, previous['planning_budget'])
        for key, value in previous.items():
            if key == 'planning_budget':
                for plan, fields in value.items():
                    self.assertEqual(self.profile[key][plan], fields)
            else:
                self.assertEqual(self.profile[key], value)

    def test_previous_directory_recovers_every_exact_original_file_and_omits_new_helper(self):
        previous = layer.previous_directory(UI)
        self.assertEqual(
            {p.name: {'sha256': layer.digest(p.read_bytes())} for p in previous.glob('*.swift')},
            self.contract['previous_ui_sources'],
        )
        self.assertEqual(len(list(previous.glob('*.swift'))), 167)
        self.assertFalse((previous / HELPER).exists())
        self.assertEqual(shard.discover(previous), shard.discover(UI))

    def test_historical_single_source_projection_accepts_only_pinned_preimages(self):
        previous = layer.previous_directory(UI)
        for name, allowed in self.contract['accepted_historical_sources'].items():
            with self.subTest(source=name):
                original = layer.previous_source(UI / name)
                self.assertEqual(original.read_bytes(), (previous / name).read_bytes())
                self.assertIn(layer.digest(original.read_bytes()), allowed)
                self.assertEqual(layer.previous_source(original), original)

    def test_new_helper_cannot_claim_a_historical_preimage(self):
        with self.assertRaisesRegex(ValueError, 'no original source'):
            layer.previous_source(UI / HELPER)

    def test_frozen_context_contains_original_audit_bytes_and_inventory(self):
        frozen = layer.frozen_prepared_context()
        self.addCleanup(frozen.lifetime.cleanup)
        for relative, row in self.contract['historical_audit_files'].items():
            with self.subTest(path=relative):
                self.assertEqual(layer.digest((frozen.root / relative).read_bytes()), row['sha256'])
        actual = {p.name: {'sha256': layer.digest(p.read_bytes())}
                  for p in (frozen.root / 'Tests/AppUITests').glob('*.swift')}
        self.assertEqual(actual, self.contract['previous_ui_sources'])

    def test_effective_costs_only_raise_the_18_methods_and_keep_all_other_old_floors(self):
        frozen = layer.frozen_prepared_context()
        self.addCleanup(frozen.lifetime.cleanup)
        before = shard.measured_weights(frozen.root / 'Tests/AppUITests',
                                        frozen.root / 'tools/ui_duration_weights.json')
        after = self.run_profile(self.profile)
        required = {key.split('.')[0]: row for key, row in self.contract['required_floors'].items()}
        self.assertEqual(set(before), set(after))
        self.assertEqual(len(required), 18)
        for name, seconds in before.items():
            with self.subTest(test_class=name):
                self.assertGreaterEqual(after[name], seconds)
                if name in required:
                    self.assertEqual(seconds, required[name]['historical_floor_seconds'])
                    self.assertEqual(after[name], required[name]['candidate_complete_method_seconds'])
                else:
                    self.assertEqual(after[name], seconds)
        self.assertAlmostEqual(sum(before.values()), 104507.381, places=7)
        self.assertAlmostEqual(sum(after.values()), 104625.381, places=7)

    def test_79_shards_run_every_class_once_with_1765_141_peak_including_startup(self):
        costs = {name: Decimal(str(value)) for name, value in self.run_profile(self.profile).items()}
        groups = shard.partition(costs, 79)
        flat = [name for group in groups for name in group]
        self.assertEqual(len(groups), 79)
        self.assertEqual(len(flat), len(set(flat)))
        self.assertEqual(set(flat), set(costs))
        counts = shard.discover(UI)
        self.assertEqual(sum(counts[name] for name in flat), 736)
        peak = max(sum(costs[name] for name in group) + 300 for group in groups)
        self.assertEqual(peak, Decimal('1765.141'))
        self.assertEqual(Decimal(1800) - peak, Decimal('34.859'))
        self.assertEqual(self.contract['shard_count'], 79)
        self.assertEqual(Decimal(str(self.contract['peak_with300_seconds'])), peak)
        self.assertEqual(Decimal(str(self.contract['headroom_seconds'])), Decimal(1800) - peak)
        self.assertGreater(max(sum(costs[name] for name in group) + 300
                               for group in shard.partition(costs, 78)), Decimal(1770))

    def test_workflow_deadline_shard_count_and_six930_holds_are_unchanged(self):
        self.assertEqual((shard.DEFAULT_SHARD_COUNT, ci_gates.SHARD_COUNT), (79, 79))
        workflow = (ROOT / '.github/workflows/native-ios.yml').read_bytes()
        self.assertEqual(workflow, (layer.FIXTURES / '.github/workflows/native-ios.yml').read_bytes())
        self.assertIn(b'--deadline-seconds 1800', workflow)
        self.assertIn(b'timeout-minutes: 37', workflow)
        self.assertIn(('shard: [' + ', '.join(map(str, range(79))) + ']').encode(), workflow)
        self.assertIs(self.contract['six930_proposals_applied'], False)
        self.assertIs(self.profile['planning_budget'][layer.PLAN]['other900_cap_and_six930_holds_unchanged'], True)
        current = self.run_profile(self.profile)
        for name in SIX_HELD_CLASSES:
            with self.subTest(test_class=name):
                self.assertLess(current[name], 930)

    def test_every_receipt_method_source_mutation_is_rejected_before_budget_projection(self):
        for key, row in self.contract['required_floors'].items():
            with self.subTest(method=key), self.copied_ui() as ui:
                source = ui / Path(row['path']).name
                text = source.read_text()
                source.write_text(text.replace('phase: .receipt', 'phase: .history', 1)
                                  if 'phase: .receipt' in text else text + '\n// unreviewed\n')
                with self.assertRaisesRegex(ValueError, 'current receipt UI sources'):
                    self.run_profile(self.profile, ui)

    def test_missing_added_renamed_duplicate_or_helper_changed_ui_fails_closed(self):
        row = next(iter(self.contract['required_floors'].values()))
        for mode in ['remove_method_file', 'remove_helper', 'duplicate_method', 'rename_method',
                     'rename_class', 'extra_file', 'shared_helper', 'unrelated_helper', 'local_helper']:
            with self.subTest(mode=mode), self.copied_ui() as ui:
                path = ui / Path(row['path']).name
                text = path.read_text()
                if mode == 'remove_method_file':
                    path.unlink()
                elif mode == 'remove_helper':
                    (ui / HELPER).unlink()
                elif mode == 'duplicate_method':
                    [(body, _)] = re.findall(layer.PATTERN, text)
                    path.write_text(text + '\n    ' + body)
                elif mode == 'rename_method':
                    path.write_text(text.replace('func test', 'func testRenamed', 1))
                elif mode == 'rename_class':
                    path.write_text(text.replace('final class ', 'final class Renamed', 1))
                elif mode == 'extra_file':
                    (ui / 'Unreviewed.swift').write_text('import XCTest\n// unknown helper\n')
                elif mode == 'shared_helper':
                    target = ui / HELPER
                    target.write_text(target.read_text().replace('.element', '.firstMatch', 1))
                elif mode == 'unrelated_helper':
                    target = next(p for p in ui.glob('*.swift')
                                  if p.name not in self.contract['accepted_historical_sources'] and p.name != HELPER)
                    target.write_bytes(target.read_bytes() + b'\n// unreviewed\n')
                else:
                    path.write_text(text.replace('timeout: 5', 'timeout: 50', 1))
                with self.assertRaises(ValueError):
                    self.run_profile(self.profile, ui)

    def test_changed_or_incomplete_ui_cannot_be_hidden_behind_previous_directory(self):
        for mode in ['missing_file', 'changed_file', 'extra_file']:
            with self.subTest(mode=mode), self.copied_ui() as ui:
                path = ui / next(iter(self.contract['accepted_historical_sources']))
                if mode == 'missing_file':
                    path.unlink()
                elif mode == 'changed_file':
                    path.write_bytes(path.read_bytes() + b'\n// changed\n')
                else:
                    (ui / 'Extra.swift').write_text('// extra\n')
                with self.assertRaises(ValueError):
                    layer.previous_directory(ui)

    def test_changed_historical_preimage_cannot_be_reprojected(self):
        previous = layer.previous_directory(UI)
        for name in self.contract['accepted_historical_sources']:
            with self.subTest(source=name), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / 'AppUITests' / name
                path.parent.mkdir()
                path.write_bytes((previous / name).read_bytes() + b'\n// unknown historical bytes\n')
                with self.assertRaises(ValueError):
                    layer.previous_source(path)

    def test_critical_app_bytes_and_source_evidence_cannot_change(self):
        for relative in [*self.contract['critical_App_sources'],
                         'Tests/ContractChecks/fixtures/run130_submission_evidence.json']:
            with self.subTest(path=relative), self.copied_root_inputs() as root:
                path = root / relative
                path.write_bytes(path.read_bytes() + b'\n')
                with self.assertRaises(ValueError):
                    layer.validate_current(UI)

    def test_missing_critical_source_or_evidence_does_not_get_regenerated(self):
        for relative in [*self.contract['critical_App_sources'],
                         'Tests/ContractChecks/fixtures/run130_submission_evidence.json']:
            with self.subTest(path=relative), self.copied_root_inputs() as root:
                path = root / relative
                path.unlink()
                with self.assertRaises(FileNotFoundError):
                    layer.validate_current(UI)
                self.assertFalse(path.exists())

    def test_every_frozen_historical_input_is_checked_before_use(self):
        for relative in self.contract['historical_audit_files']:
            for mode in ['changed', 'missing']:
                with self.subTest(path=relative, mode=mode), tempfile.TemporaryDirectory() as temporary:
                    fixtures = Path(temporary) / 'fixtures'
                    shutil.copytree(layer.FIXTURES, fixtures)
                    path = fixtures / relative
                    if mode == 'missing':
                        path.unlink()
                    else:
                        path.write_bytes(path.read_bytes() + b'\n')
                    with patch.object(layer, 'FIXTURES', fixtures), self.assertRaises((ValueError, FileNotFoundError)):
                        layer.frozen_prepared_context()
                    if mode == 'missing':
                        self.assertFalse(path.exists())

    def test_current_plan_cannot_be_deleted_or_renamed(self):
        for mode in ['delete', 'rename', 'remove_all_plans']:
            profile = deepcopy(self.profile)
            if mode == 'delete':
                profile['planning_budget'].pop(layer.PLAN)
            elif mode == 'rename':
                profile['planning_budget']['unreviewed_alias'] = profile['planning_budget'].pop(layer.PLAN)
            else:
                profile.pop('planning_budget')
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.run_profile(profile)

    def test_copied_current_ui_cannot_fall_back_without_plan_or_helper(self):
        previous = layer.previous_profile(self.profile)
        for name in ['AppUITests', 'renamed-ui']:
            for remove_helper in [False, True]:
                with self.subTest(name=name, remove_helper=remove_helper), self.copied_ui(name) as ui:
                    if remove_helper:
                        (ui / HELPER).unlink()
                    with self.assertRaises(ValueError):
                        self.run_profile(previous, ui)

    def test_each_whole_method_floor_rejects_lower_raised_or_deleted_values(self):
        for key, row in self.contract['required_floors'].items():
            for value in [None, row['historical_floor_seconds'] - 1, 930]:
                profile = deepcopy(self.profile)
                floors = profile['planning_budget'][layer.PLAN]['whole_method_seconds']
                if value is None:
                    floors.pop(key)
                else:
                    floors[key] = value
                with self.subTest(method=key, value=value), self.assertRaises(ValueError):
                    self.run_profile(profile)

    def test_exception_allowlist_cannot_be_extended_reduced_or_reassigned(self):
        for mode in ['extra', 'missing', 'raised', 'lowered', 'renamed']:
            profile = deepcopy(self.profile)
            exceptions = profile['planning_budget'][layer.PLAN]['source_bound_over900_exceptions']
            key = next(iter(exceptions))
            if mode == 'extra':
                exceptions['UnapprovedFlowTests.testUnknown'] = 902
            elif mode == 'missing':
                exceptions.pop(key)
            elif mode == 'raised':
                exceptions[key] = 930
            elif mode == 'lowered':
                exceptions[key] = 900
            else:
                exceptions['UnapprovedFlowTests.testUnknown'] = exceptions.pop(key)
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.run_profile(profile)

    def test_profile_metadata_counts_measurement_and_hold_flags_cannot_change(self):
        for key, value in [('method_count', 735), ('class_count', 161), ('additional_seconds', 117),
                           ('measured', True), ('other900_cap_and_six930_holds_unchanged', False)]:
            profile = deepcopy(self.profile)
            profile['planning_budget'][layer.PLAN][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.run_profile(profile)

    def test_historical_observations_estimates_default_and_floors_cannot_be_shadowed(self):
        mutations = []
        for field in ['method_seconds', 'estimated_method_seconds']:
            for value in [1, 901]:
                profile = deepcopy(self.profile)
                profile[field][next(iter(profile[field]))] = value
                mutations.append((field, value, profile))
        profile = deepcopy(self.profile)
        profile['unobserved_method_seconds'] = 1
        mutations.append(('default', 1, profile))
        profile = deepcopy(self.profile)
        profile['method_planning_floors'].clear()
        mutations.append(('old_floors', 'removed', profile))
        profile = deepcopy(self.profile)
        profile['planning_budget'].pop('reviewed_run130_prepared_readiness')
        mutations.append(('old_plan', 'removed', profile))
        for field, value, profile in mutations:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                self.run_profile(profile)

    def test_unknown_extra_profile_field_cannot_smuggle_a_new_override(self):
        profile = deepcopy(self.profile)
        profile['unreviewed_override'] = {'maximum_method_seconds': 930}
        with self.assertRaisesRegex(ValueError, 'Changed current receipt profile'):
            layer.previous_profile(profile)

    def test_current_profile_cannot_be_applied_to_historical_ui(self):
        previous = layer.previous_directory(UI)
        with self.assertRaises(ValueError):
            self.run_profile(self.profile, previous)

    def test_source_bound_current_plan_rejects_unrelated_ui(self):
        with tempfile.TemporaryDirectory() as temporary:
            ui = Path(temporary)
            (ui / 'Example.swift').write_text('import XCTest\nfinal class Example: XCTestCase { func testOnly() {} }\n')
            with self.assertRaises(ValueError):
                self.run_profile(self.profile, ui)

    def test_unrelated_legacy_sources_keep_generic_900_cap(self):
        with tempfile.TemporaryDirectory() as temporary:
            ui = Path(temporary) / 'AppUITests'
            ui.mkdir()
            (ui / 'Example.swift').write_text('import XCTest\nfinal class Example: XCTestCase { func testOnly() {} }\n')
            base = {'version': 1, 'method_seconds': {}, 'unobserved_method_seconds': 900}
            self.assertEqual(self.run_profile(base, ui), {'Example': 900})
            for field in ['unobserved_method_seconds', 'method_seconds', 'estimated_method_seconds']:
                for value in [901, 902, 908, 930]:
                    profile = deepcopy(base)
                    profile[field] = value if field == 'unobserved_method_seconds' else {'Example.testOnly': value}
                    with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                        self.run_profile(profile, ui)

    def test_contract_mutations_cannot_self_authorize_changed_evidence_or_budgets(self):
        for mode in ['floor', 'exceptions', 'source_hash', 'inventory', 'delta', 'shards', 'six930', 'measured']:
            contract = deepcopy(self.contract)
            row = contract['required_floors'][next(iter(contract['required_floors']))]
            if mode == 'floor':
                row['candidate_complete_method_seconds'] = 930
            elif mode == 'exceptions':
                contract['fixed_over900_exceptions']['Example.testOnly'] = 930
            elif mode == 'source_hash':
                contract['source_contract_sha256'] = '0' * 64
            elif mode == 'inventory':
                contract['current_inventory'].pop()
            elif mode == 'delta':
                contract['additional_seconds'] = 0
            elif mode == 'shards':
                contract['shard_count'] = 80
            elif mode == 'six930':
                contract['six930_proposals_applied'] = True
            else:
                row['measured'] = True
            with self.subTest(mode=mode), self.copied_root_inputs() as root:
                (root / 'tools/run130_receipt_planning_contract.json').write_text(json.dumps(contract))
                with self.assertRaisesRegex(ValueError, 'Unreviewed receipt planning contract'):
                    layer.contract()

    def test_missing_or_malformed_contract_is_not_regenerated_or_silently_accepted(self):
        for mode in ['missing', 'malformed']:
            with self.subTest(mode=mode), self.copied_root_inputs() as root:
                path = root / 'tools/run130_receipt_planning_contract.json'
                if mode == 'missing':
                    path.unlink()
                else:
                    path.write_text('{')
                with self.assertRaises((ValueError, FileNotFoundError)):
                    layer.contract()
                if mode == 'missing':
                    self.assertFalse(path.exists())


if __name__ == '__main__':
    unittest.main()
