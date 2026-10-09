"""Exercise the real current runner separately from preserved historical audits."""
from contextlib import redirect_stdout
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import ci_gates, run_ui_shard as runner
from tools import run138_editor_readiness as current
from tools import run138_current_source_projection as entry

ROOT = Path(__file__).resolve().parents[2]
UI = ROOT / 'Tests/AppUITests'
PROFILE = ROOT / 'tools/ui_duration_weights.json'


class CurrentCIEntryTests(unittest.TestCase):
    def test_real_dispatch_charges_every_new_action_and_preserves_other_class_costs(self):
        actual = runner.measured_weights(UI, PROFILE)
        old_ui = current.previous_directory(UI, PROFILE)
        previous = runner.measured_weights(old_ui, PROFILE)
        self.assertEqual((sum(runner.discover(UI).values()), len(actual)), (736, 163))
        self.assertEqual((sum(runner.discover(old_ui).values()), len(previous)), (736, 162))
        self.assertEqual(actual['ProjectEditFlowTests'], previous['ProjectEditFlowTests'] - 150 + 40)
        self.assertEqual(actual['ProjectEditReviewReadinessFlowTests'], 150 + 40)
        expected_deltas = {'ApprovedTopicSelectedCoverChineseFlowTests': 40,
                           'ApprovedTopicReviewCurrentChineseFlowTests': 40,
                           'MerchantMarketingUITests': 30, 'ProjectStoryImageFlowTests': 5,
                           'ApprovedReleaseRecoveryFlowTests': 40, 'OwnedTopicCoverRecoveryFlowTests': 40,
                           'ProjectStoryAudioRecoveryFlowTests': 80, 'OwnedCouponCodeJourneyUITests': 20,
                           'ApprovedTopicFrozenCoverPublicationFlowTests': 32, 'SquareWorkspaceFlowTests': 116.948}
        for name in previous:
            if name == 'ProjectEditFlowTests':
                continue
            self.assertAlmostEqual(actual[name] - previous[name], expected_deltas.get(name, 0))
        self.assertAlmostEqual(sum(actual.values()) - sum(previous.values()), 523.948)
        self.assertEqual(actual['ProjectStoryImageFlowTests'], 905)
        self.assertEqual(actual['MerchantMarketingUITests'], 438.399)

    def test_real_partition_covers_every_complete_class_once_under_unchanged_deadline(self):
        costs = runner.measured_weights(UI, PROFILE)
        groups = runner.partition(costs, runner.DEFAULT_SHARD_COUNT)
        names = [name for group in groups for name in group]
        self.assertEqual((runner.DEFAULT_SHARD_COUNT, ci_gates.SHARD_COUNT), (79, 79))
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(set(names), set(runner.discover(UI)))
        self.assertEqual(sum(runner.discover(UI)[name] for name in names), 736)
        peak = max(sum(costs[name] for name in group) for group in groups)
        self.assertAlmostEqual(peak, 1465.141)
        self.assertLessEqual(peak + 300, 1800)

    def test_real_cli_dry_run_selects_the_new_cost_partition_without_apple_execution(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools/run_ui_shard.py'),
                                 '--shard', '0', '--count', '79', '--dry-run'],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Inventory: 736 tests in 163 classes;', result.stdout)
        costs = runner.measured_weights(UI, PROFILE)
        selected = runner.partition(costs, 79)[0]
        self.assertIn(str(selected), result.stdout)
        self.assertNotIn('xcodebuild', result.stdout)

    def test_real_runner_rejects_missing_duplicate_unknown_and_changed_current_sources(self):
        for mode in ['missing', 'missing-new-class', 'duplicate', 'unknown', 'assertion', 'helper']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                ui = Path(temporary) / 'renamed-ui'
                shutil.copytree(UI, ui)
                if mode == 'missing':
                    (ui / 'TicketWalletFlowTests.swift').unlink()
                elif mode == 'missing-new-class':
                    (ui / 'ProjectEditReviewReadinessFlowTests.swift').unlink()
                elif mode == 'duplicate':
                    shutil.copyfile(ui / 'ProjectEditReviewReadinessFlowTests.swift', ui / 'Duplicate.swift')
                elif mode == 'unknown':
                    (ui / 'Unreviewed.swift').write_text('class Unreviewed: XCTestCase { func testNew() {} }')
                elif mode == 'assertion':
                    file = ui / 'ApprovedTopicSelectedCoverChineseFlowTests.swift'
                    text = file.read_text(); self.assertIn('checked.reviewSubmitCount,0', text)
                    file.write_text(text.replace('checked.reviewSubmitCount,0', 'checked.reviewSubmitCount,1', 1))
                else:
                    file = ui / 'FailureScreenshot.swift'; file.write_bytes(file.read_bytes() + b'\n')
                with self.assertRaises(ValueError):
                    runner.measured_weights(ui, PROFILE)

    def test_real_runner_rejects_profile_edits_including_old_observations_and_new_exception(self):
        baseline = json.loads(PROFILE.read_text())
        for mode in ['old-observation', 'estimated-floor', 'new-exception', 'missing-plan']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                profile = deepcopy(baseline)
                if mode == 'old-observation':
                    key = next(iter(profile['method_seconds'])); profile['method_seconds'][key] += 1
                elif mode == 'estimated-floor':
                    profile['estimated_method_seconds'][current.CHINESE] = 948
                elif mode == 'new-exception':
                    profile['planning_budget']['reviewed_run130_receipt_semantics']['source_bound_over900_exceptions']['Unrelated.testNew'] = 905
                else:
                    profile.pop('planning_budget')
                file = Path(temporary) / 'profile.json'; file.write_text(json.dumps(profile))
                with self.assertRaises(ValueError):
                    runner.measured_weights(UI, file)
        self.assertEqual(hashlib.sha256(PROFILE.read_bytes()).hexdigest(), '29702b1924f79fd62fed74b71de626e7e68545747990b0e55be21415accaced7')

    def test_every_entry_change_has_exact_before_after_and_rejects_unreviewed_bytes(self):
        expected = {'tools/run_ui_shard.py', 'tools/branch_history_handshake_planning.py',
                    'tools/run130_submission_evidence.py', 'tools/run138_ui52_driver_inverse.py',
                    'Tests/ContractChecks/test_project_edit_contracts.py',
                    'Tests/ContractChecks/test_run129_navigation_diagnostics.py',
                    'Tests/ContractChecks/test_run130_submission_evidence.py',
                    'tools/tests/test_branch_history_handshake_budget.py',
                    'tools/run129_repair_planning.py', 'tools/ci138_coupon_square_publication_driver.py',
                    'tools/tests/test_ci138_coupon_square_publication_driver.py',
                    'Tests/ContractChecks/test_ci138_version_row_source.py',
                    'Tests/ContractChecks/test_project_editor_readiness.py',
                    'tools/tests/story_template_budget_history.py',
                    'tools/tests/club_parity_budget_history.py',
                    'tools/tests/creator_pending_budget_history.py',
                    'tools/tests/combined_native_budget_history.py',
                    'tools/tests/player_map_history_budget_history.py',
                    'tools/tests/story_media_budget_history.py',
                    'tools/tests/reviewed_feature_budget_history.py',
                    'tools/tests/reviewed_map_budget_history.py'}
        expected.update({
            'Tests/ContractChecks/fixtures/run138_ui52_driver.json',
            'tools/story_reveal_arrival_contract.json', 'tools/remaining_editor_drivers_contract.json',
            'tools/story_reveal_arrival_inverse.py', 'tools/remaining_editor_drivers_inverse.py',
        })
        expected.update({'.github/workflows/native-ios.yml', 'tools/ci_gates.py',
                         'tools/tests/test_ci_gates.py', 'tools/tests/test_test_bundle_preflight.py'})
        self.assertEqual(set(entry.entry_contract()['files']), expected)
        entry.validate_entries()
        for relative, row in entry.entry_contract()['files'].items():
            raw = (ROOT / relative).read_bytes()
            before = entry.original_entry_bytes(relative, raw)
            self.assertEqual(hashlib.sha256(raw).hexdigest(), row['after_sha256'])
            self.assertEqual(hashlib.sha256(before).hexdigest(), row['before_sha256'])
            for mutant in [raw + b'\n', b'']:
                with self.subTest(path=relative), self.assertRaises(ValueError):
                    entry.original_entry_bytes(relative, mutant)
        self.assertEqual(hashlib.sha256(entry.historical_entry_bytes(ROOT, 'tools/run_ui_shard.py')).hexdigest(),
                         'ac27afad682873a4221e6f091909ee5e5f51091d5e5321db284cef0f993f68dc')

    def test_historical_contexts_keep_old_bodies_while_current_ui52_owned_sources_stay_live(self):
        old = entry.frozen_context('all')
        component = entry.frozen_context('ui52')
        self.assertEqual(len(runner.discover(old.root / 'Tests/AppUITests')), 162)
        self.assertEqual(len(runner.discover(component.root / 'Tests/AppUITests')), 162)
        self.assertEqual(len(runner.discover(UI)), 163)
        for relative in current.ui52_layer().contract()['files']:
            live = (ROOT / relative).read_bytes()
            self.assertEqual((component.root / relative).read_bytes(), live)
            self.assertEqual((old.root / relative).read_bytes(), current.ui52_layer().original_source(relative, live))
        result = current.ui52_layer().validate_current(ROOT)
        self.assertEqual(result['new_wait_allowance_seconds'], 35)
        for relative in entry.entry_contract()['files']:
            self.assertEqual((old.root / relative).read_bytes(), entry.historical_entry_bytes(ROOT, relative))

    def test_projection_cache_stays_bounded_and_revalidates_both_current_and_cached_bytes(self):
        first = current.previous_directory(UI, PROFILE)
        initial_count = len(current._lives)
        for _ in range(25):
            self.assertEqual(current.previous_directory(UI, PROFILE), first)
        self.assertEqual(len(current._lives), initial_count)
        target = first / 'TicketWalletFlowTests.swift'; saved = target.read_bytes()
        try:
            target.write_bytes(saved + b'\n')
            with self.assertRaisesRegex(ValueError, 'Cached exact historical UI'):
                current.previous_directory(UI, PROFILE)
        finally:
            target.write_bytes(saved)
        self.assertEqual(current.previous_directory(UI, PROFILE), first)
        context = entry.frozen_context()
        target = context.root / 'Tests/AppUITests/TicketWalletFlowTests.swift'; saved = target.read_bytes()
        try:
            target.write_bytes(saved + b'\n')
            with self.assertRaisesRegex(ValueError, 'Cached historical review context'):
                entry.frozen_context()
        finally:
            target.write_bytes(saved)
        self.assertEqual(entry.frozen_context().root, context.root)

    def test_encoded_leaf_contracts_keep_json_values_and_exact_historical_bytes(self):
        for relative in ('Tests/ContractChecks/fixtures/run138_ui52_driver.json',
                         'tools/story_reveal_arrival_contract.json',
                         'tools/remaining_editor_drivers_contract.json'):
            raw = (ROOT / relative).read_bytes()
            old = entry.original_entry_bytes(relative, raw)
            self.assertEqual(json.loads(raw), json.loads(old))
            self.assertEqual(raw.count(b'\\u0041'), 1)
            self.assertNotEqual(raw, old)
            self.assertEqual(hashlib.sha256(old).hexdigest(), entry.entry_contract()['files'][relative]['before_sha256'])
        for relative in ('tools/story_reveal_arrival_inverse.py', 'tools/remaining_editor_drivers_inverse.py'):
            self.assertEqual(hashlib.sha256(entry.historical_entry_bytes(ROOT, relative)).hexdigest(),
                             current.contract()['followon_support_sha256'][relative])

    def test_restored_ui52_reader_and_contract_are_validated_as_an_exact_pair(self):
        context = entry.frozen_context('ui52')
        historical = context.load('tools/run138_ui52_driver_inverse.py', 'encoded_ui52_pair_regression')
        raw = (context.root / historical.CONTRACT_PATH).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), historical.CONTRACT_SHA256)
        self.assertNotEqual(historical.CONTRACT_SHA256, current.ui52_layer().CONTRACT_SHA256)
        self.assertEqual(historical.validate_current(context.root)['new_wait_allowance_seconds'], 35)
        self.assertEqual(entry.validate_ui52_component()['new_wait_allowance_seconds'], 35)

    def test_equivalent_or_unreviewed_current_json_encodings_fail_closed(self):
        from tools.tests.test_run138_editor_readiness import copied_inputs
        for relative in ('Tests/ContractChecks/fixtures/run138_ui52_driver.json',
                         'tools/story_reveal_arrival_contract.json',
                         'tools/remaining_editor_drivers_contract.json',
                         'tools/run138_editor_readiness_contract.json'):
            with copied_inputs() as root:
                file = root / relative
                raw = file.read_bytes()
                alternative = raw.replace(b'WeChatApp\\u0041uth', b'WeChat\\u0041ppAuth')
                self.assertNotEqual(alternative, raw)
                self.assertEqual(json.loads(alternative), json.loads(raw))
                for mutant in (alternative, raw + b'\n', b''):
                    file.write_bytes(mutant)
                    with self.subTest(path=relative), self.assertRaises(ValueError):
                        current.validate_current(root / 'Tests/AppUITests', root / 'tools/ui_duration_weights.json', root)
                file.write_bytes(raw)

    def test_live_aggregate_requires_static_job_and_a_verified_receipt(self):
        # The old 79-shard assertions below retain their exact old gate. This
        # separate check exercises the actual current gate, never a projection.
        commit = 'a' * 40
        self.assertEqual(len(ci_gates.REQUIRED_JOBS), 7)
        self.assertIn('static-checks', ci_gates.REQUIRED_JOBS)
        needs = {name: {'result': 'success', 'outputs': {}} for name in ci_gates.REQUIRED_JOBS}
        for missing in (None, '', '{}'):
            with self.subTest(receipt=missing), self.assertRaises(ValueError):
                ci_gates.aggregate(needs, commit, missing, '1234', '2')
        # Actual positive receipts and all 79 negative shard cases are exercised
        # against real Git fixture artifacts by test_native_static_checks.py.

    def test_unchanged_aggregate_requires_all_79_exact_build_completions(self):
        context = entry.frozen_context('all')
        ci_gates = context.load('tools/ci_gates.py', 'run138_retained_pre_static_gates')
        commit = 'a' * 40
        fingerprint = ci_gates.encode({'version': 1, 'commit': commit, 'head': commit,
                                       'toolchain': {'xcode': 'synthetic test toolchain', 'developer': '/synthetic'}})
        needs = {name: {'result': 'success', 'outputs': {}} for name in ci_gates.REQUIRED_JOBS}
        for name in ['native', 'device-build', 'us-build', 'app-unit-tests']:
            needs[name]['outputs']['build_fingerprint'] = fingerprint
        digest = ci_gates.completion_digest(fingerprint, commit)
        needs['ui-tests']['outputs'] = {'shard_' + str(index): digest for index in range(79)}
        ci_gates.aggregate(needs, commit)
        for mode in ['missing', 'failed', 'wrong-build', 'unexpected']:
            changed = deepcopy(needs)
            if mode == 'missing':
                changed['ui-tests']['outputs'].pop('shard_78')
            elif mode == 'failed':
                changed['ui-tests']['result'] = 'failure'
            elif mode == 'wrong-build':
                changed['ui-tests']['outputs']['shard_78'] = 'wrong'
            else:
                changed['ui-tests']['outputs']['shard_79'] = digest
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                ci_gates.aggregate(changed, commit)


if __name__ == '__main__':
    unittest.main()
