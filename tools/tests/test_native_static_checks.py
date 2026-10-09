"""Execute real small Git checkouts, then verify the live Linux-to-Apple gate."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import run_static_checks as runner

spec = importlib.util.spec_from_file_location('live_static_ci_gates', ROOT / 'tools/ci_gates.py')
gates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gates)


class StaticRunnerFixtures(unittest.TestCase):
    def setUp(self):
        self.life = tempfile.TemporaryDirectory(prefix='native-static-fixture-')
        self.addCleanup(self.life.cleanup)
        self.base = Path(self.life.name)
        self.root = self.base / 'source'
        self.temp = self.base / 'runner-temp'
        self.temp.mkdir()
        (self.root / 'tools/tests').mkdir(parents=True)
        (self.root / 'Tests/ContractChecks').mkdir(parents=True)
        for name in ['run_static_checks.py', 'ci_gates.py', 'test_products.py']:
            shutil.copyfile(ROOT / 'tools' / name, self.root / 'tools' / name)
        self.tools = self.root / 'tools/tests/test_probe.py'
        self.contracts = self.root / 'Tests/ContractChecks/test_probe.py'
        self.tools.write_text('import unittest\nclass Tools(unittest.TestCase):\n def test_tools(self): self.assertTrue(True)\n')
        self.contracts.write_text('import unittest\nclass Contracts(unittest.TestCase):\n def test_contracts(self): self.assertTrue(True)\n')
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in runner.SOURCE_ENVIRONMENTS and key not in {'PYTHONOPTIMIZE', 'PYTHONPATH'}}
        self.environment.update(RUNNER_TEMP=str(self.temp), GITHUB_RUN_ID='1234', GITHUB_RUN_ATTEMPT='2',
                                PYTHONDONTWRITEBYTECODE='1')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Static fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.commit()
        self.output = self.temp / 'artifacts'
        self.github_output = self.temp / 'github-output'

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True).strip()

    def commit(self):
        self.git('add', '--all')
        self.git('commit', '-qm', 'Synthetic static fixture', '--allow-empty')
        self.environment['GITHUB_SHA'] = self.git('rev-parse', 'HEAD')

    def execute(self, expected=0, environment=None):
        result = subprocess.run([sys.executable, '-B', str(self.root / 'tools/run_static_checks.py'),
                                 'run', '--output', str(self.output), '--github-output', str(self.github_output)],
                                cwd=self.root, env=environment or self.environment,
                                text=True, capture_output=True, timeout=30)
        if expected == 0:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((self.output / 'manifest.json').exists())
            self.assertFalse(self.github_output.exists())
        return result

    def receipt(self):
        return self.github_output.read_text().strip().split('=', 1)[1]

    def verify(self, expected=None, environment=None):
        with mock.patch.dict(os.environ, environment or self.environment, clear=True):
            return runner.verify_bundle(self.output, self.root, expected)

    def change_report(self, name, change):
        path = self.output / (name + '.json')
        report = json.loads(path.read_text())
        change(report)
        path.write_text(runner.encode(report) + '\n')
        manifest_path = self.output / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['suites'][name]['report_sha256'] = runner.digest(path.read_bytes())
        manifest_path.write_text(runner.encode(manifest) + '\n')

    def test_real_both_discoveries_run_separate_processes_and_bind_exact_git_run_source(self):
        self.execute()
        receipt = self.receipt()
        self.assertEqual(self.verify(receipt), receipt)
        data = json.loads(receipt)
        self.assertEqual((data['head'], data['commit']), (self.environment['GITHUB_SHA'],) * 2)
        self.assertEqual(data['tree'], self.git('rev-parse', 'HEAD^{tree}'))
        self.assertEqual((data['run_id'], data['run_attempt']), ('1234', '2'))
        reports = {name: json.loads((self.output / (name + '.json')).read_text()) for name in runner.SUITES}
        self.assertNotEqual(reports['tools']['process_id'], reports['contracts']['process_id'])
        for name, class_name in [('tools', 'Tools'), ('contracts', 'Contracts')]:
            report = reports[name]
            self.assertEqual(report['discovered_ids'], [f'test_probe.{class_name}.test_{name}'])
            self.assertEqual(report['executed_ids'], report['discovered_ids'])
            self.assertEqual(report['successes'], report['discovered_ids'])
            self.assertEqual((report['discovered_count'], report['executed_count'], report['tests_run']), (1, 1, 1))
        self.assertEqual(self.git('status', '--porcelain=v1', '--untracked-files=all'), '')
        self.assertFalse(any(self.root.rglob('*.pyc')))

    def test_real_failure_does_not_short_circuit_second_suite_or_create_manifest(self):
        self.tools.write_text(self.tools.read_text().replace('assertTrue(True)', 'assertTrue(False)'))
        self.commit(); self.execute(1)
        self.assertEqual(json.loads((self.output / 'tools.json').read_text())['outcome_counts']['failures'], 1)
        self.assertEqual(json.loads((self.output / 'contracts.json').read_text())['outcome_counts']['successes'], 1)

    def test_empty_discovery_is_not_success(self):
        self.tools.unlink(); self.commit(); self.execute(1)
        self.assertTrue((self.output / 'contracts.json').exists())

    def test_missing_suite_is_not_success(self):
        shutil.rmtree(self.root / 'Tests/ContractChecks'); self.commit(); self.execute(1)

    def test_import_error_is_not_success(self):
        self.tools.write_text('raise RuntimeError("synthetic import failure")\n'); self.commit(); self.execute(1)
        report = json.loads((self.output / 'tools.json').read_text())
        self.assertTrue(report['discovery_errors'])
        self.assertEqual(report['outcome_counts']['errors'], 1)

    def test_runtime_error_is_recorded_and_rejected(self):
        self.tools.write_text(self.tools.read_text().replace('self.assertTrue(True)', 'raise RuntimeError("synthetic runtime error")'))
        self.commit(); self.execute(1)
        report = json.loads((self.output / 'tools.json').read_text())
        self.assertEqual(report['errors'], ['test_probe.Tools.test_tools'])
        self.assertEqual(report['outcome_counts']['errors'], 1)

    def test_duplicate_discovered_ids_cannot_pass(self):
        self.tools.write_text(self.tools.read_text() + '\ndef load_tests(loader, suite, pattern): return unittest.TestSuite([Tools("test_tools"), Tools("test_tools")])\n')
        self.commit(); self.execute(1)
        report = json.loads((self.output / 'tools.json').read_text())
        self.assertEqual((report['discovered_count'], report['tests_run']), (2, 2))

    def test_artifacts_inside_source_and_existing_outputs_cannot_be_reused(self):
        self.output = self.root / 'artifacts'; self.execute(1)
        self.output = self.temp / 'artifacts'; self.output.mkdir(); self.execute(1)

    def test_child_exit_zero_without_report_is_not_success(self):
        self.tools.write_text('import os\nos._exit(0)\n'); self.commit(); self.execute(1)
        self.assertTrue((self.output / 'contracts.json').exists())

    def test_cancelled_child_is_not_success(self):
        self.tools.write_text('import os,signal\nos.kill(os.getpid(), signal.SIGTERM)\n'); self.commit(); self.execute(1)
        self.assertTrue((self.output / 'contracts.json').exists())

    def test_unknown_skip_never_passes(self):
        self.tools.write_text(self.tools.read_text().replace('self.assertTrue(True)', 'self.skipTest("Node unavailable")'))
        self.commit(); self.execute(1)
        report = json.loads((self.output / 'tools.json').read_text())
        self.assertEqual(report['skipped'][0]['reason'], 'Node unavailable')

    def test_known_skip_requires_exact_method_reason_and_absent_source(self):
        path = self.root / 'Tests/ContractChecks/test_team_contracts.py'
        path.write_text('import unittest\nclass TeamSourceChecks(unittest.TestCase):\n'
                        ' def test_creation_matches_source_eligibility_sizes_and_default(self):\n'
                        '  self.skipTest("Preserved Flutter source is not available in this checkout")\n')
        self.commit(); self.execute()
        report = json.loads((self.output / 'contracts.json').read_text())
        self.assertEqual(report['skip_count'], 1)
        self.verify(self.receipt())
        (self.base / 'app-audit').mkdir()
        with self.assertRaisesRegex(ValueError, 'Unapproved static skip'):
            self.verify()

    def test_known_class_skip_accounts_for_every_discovered_method(self):
        path = self.root / 'Tests/ContractChecks/test_merchant_public_production.py'
        path.write_text('import unittest\nclass CurrentBackendMerchantSourceTests(unittest.TestCase):\n'
                        ' @classmethod\n def setUpClass(cls): raise unittest.SkipTest("NOT_RUN: explicit CURRENT backend source root not supplied")\n'
                        + ''.join(' def ' + identifier.rsplit('.', 1)[1] + '(self): pass\n'
                                for identifier in next(iter(runner.ALLOWED_CLASS_SKIPS.values()))))
        self.commit(); self.execute()
        report = json.loads((self.output / 'contracts.json').read_text())
        self.assertEqual((report['discovered_count'], report['executed_count'], report['skip_count']), (4, 1, 1))
        self.assertEqual(len(report['skipped'][0]['affected_ids']), 3)
        self.change_report('contracts', lambda row: row['skipped'][0]['affected_ids'].pop())
        with self.assertRaisesRegex(ValueError, 'exact discovered methods'):
            self.verify()

    def test_approved_class_skip_cannot_hide_new_or_missing_methods(self):
        path = self.root / 'Tests/ContractChecks/test_merchant_public_production.py'
        path.write_text('import unittest\nclass CurrentBackendMerchantSourceTests(unittest.TestCase):\n'
                        ' @classmethod\n def setUpClass(cls): raise unittest.SkipTest("NOT_RUN: explicit CURRENT backend source root not supplied")\n'
                        ' def test_unreviewed_method(self): pass\n')
        self.commit(); self.execute(1)

    def test_configured_source_missing_directory_or_files_cannot_become_skip(self):
        self.environment['CHENGYIN_BACKEND_SOURCE_ROOT'] = str(self.base / 'missing-source')
        self.execute(1)
        (self.base / 'missing-source').mkdir()
        path = self.root / 'Tests/ContractChecks/test_merchant_public_production.py'
        path.write_text('import unittest\nclass CurrentBackendMerchantSourceTests(unittest.TestCase):\n'
                        ' @classmethod\n def setUpClass(cls): raise unittest.SkipTest("NOT_RUN: explicit CURRENT backend source root not supplied")\n'
                        ' def test_one(self): pass\n')
        self.commit(); self.execute(1)

    def test_changed_source_during_suite_never_emits_receipt(self):
        self.tools.write_text('from pathlib import Path\nimport unittest\nclass Tools(unittest.TestCase):\n'
                              ' def test_mutates(self): Path(__file__).write_text("changed source")\n')
        self.commit(); self.execute(1)
        self.assertTrue((self.output / 'contracts.json').exists())

    def test_cross_suite_changed_then_restored_source_is_latched_failure(self):
        original = ('import unittest\nfrom pathlib import Path\nclass Contracts(unittest.TestCase):\n'
                    ' def test_contracts(self): self.assertTrue(False)\n'
                    ' @classmethod\n def tearDownClass(cls):\n'
                    '  path=Path(__file__)\n'
                    '  path.write_text(path.read_text().replace("self.assertTrue("+"True)", "self.assertTrue("+"False)"))\n')
        self.contracts.write_text(original)
        self.tools.write_text('import unittest\nfrom pathlib import Path\nclass Tools(unittest.TestCase):\n'
                              ' def test_temporarily_changes_contract_suite(self):\n'
                              '  path=Path(__file__).resolve().parents[2]/"Tests/ContractChecks/test_probe.py"\n'
                              '  path.write_text(path.read_text().replace("self.assertTrue(False)", "self.assertTrue(True)"))\n')
        self.commit()
        result = self.execute(1)
        # Both real processes report success, and the second restores the exact
        # Git bytes. Earlier boundary failures must still prevent a receipt.
        self.assertEqual(self.contracts.read_text(), original)
        self.assertEqual(self.git('status', '--porcelain'), '')
        for name in runner.SUITES:
            report = json.loads((self.output / (name + '.json')).read_text())
            self.assertEqual(report['outcome_counts']['successes'], 1)
        self.assertIn('Static source boundary after tools:', result.stderr)
        self.assertIn('Static source boundary before contracts:', result.stderr)

    def test_ignored_source_injection_is_rejected_even_when_git_status_is_clean(self):
        (self.root / '.gitignore').write_text('injected.py\n')
        self.commit()
        (self.root / 'injected.py').write_text('pass\n')
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.execute(1)

    def test_assume_unchanged_cannot_hide_modified_git_source_bytes(self):
        self.git('update-index', '--assume-unchanged', 'tools/tests/test_probe.py')
        self.tools.write_text(self.tools.read_text() + '\n')
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.execute(1)

    def test_wrong_sha_dirty_checkout_and_optimized_python_fail_before_success(self):
        for name, value in [('GITHUB_SHA', 'a' * 40), ('PYTHONOPTIMIZE', '1')]:
            with self.subTest(variable=name):
                environment = dict(self.environment); environment[name] = value
                self.execute(1, environment)
        self.tools.write_text(self.tools.read_text() + '\n')
        self.execute(1)

    def test_wrong_run_attempt_tree_sha_and_source_fail_receipt_verification(self):
        self.execute()
        for key, value in [('GITHUB_RUN_ID', '1235'), ('GITHUB_RUN_ATTEMPT', '3'), ('GITHUB_SHA', 'a' * 40)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify(environment=dict(self.environment, **{key: value}))
        manifest_path = self.output / 'manifest.json'
        original = manifest_path.read_bytes()
        for key, value in [('tree', 'a' * 40), ('source_sha256', 'a' * 64)]:
            manifest = json.loads(original); manifest['identity'][key] = value
            manifest_path.write_text(json.dumps(manifest))
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify()
        manifest_path.write_bytes(original)
        self.tools.write_text(self.tools.read_text() + '\n')
        with self.assertRaises(ValueError): self.verify()

    def test_missing_suite_malformed_manifest_and_digest_mismatch_fail(self):
        self.execute()
        path = self.output / 'manifest.json'; original = path.read_bytes()
        missing = json.loads(original); missing['suites'].pop('contracts')
        for raw in [b'{}', b'{broken', runner.encode(missing).encode(), b'{"version":1,"version":1}']:
            path.write_bytes(raw)
            with self.subTest(raw=raw), self.assertRaises(ValueError): self.verify()
        path.write_bytes(original)
        (self.output / 'contracts.log').write_text('forged success')
        with self.assertRaises(ValueError): self.verify()

    def test_matching_counts_do_not_hide_missing_executed_method(self):
        self.execute()
        self.change_report('contracts', lambda row: row.update(executed_ids=[], executed_count=0, tests_run=0))
        with self.assertRaisesRegex(ValueError, 'every discovered test'): self.verify()

    def test_different_receipt_digest_cannot_reuse_good_manifest(self):
        self.execute()
        receipt = json.loads(self.receipt()); receipt['manifest_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'successful job receipt'): self.verify(json.dumps(receipt))

    def test_expected_failure_is_recorded_but_unexpected_success_fails(self):
        self.tools.write_text('import unittest\nclass Tools(unittest.TestCase):\n @unittest.expectedFailure\n'
                              ' def test_expected(self): self.assertTrue(False)\n')
        self.commit(); self.execute()
        report = json.loads((self.output / 'tools.json').read_text())
        self.assertEqual(report['outcome_counts']['expected_failures'], 1)
        self.tools.write_text(self.tools.read_text().replace('assertTrue(False)', 'assertTrue(True)'))
        self.commit(); self.output = self.temp / 'unexpected-artifacts'; self.github_output = self.temp / 'unexpected-output'
        self.execute(1)
        self.assertEqual(json.loads((self.output / 'tools.json').read_text())['outcome_counts']['unexpected_successes'], 1)

    def test_native_and_aggregate_cli_consume_actual_same_run_fixture_artifact(self):
        self.execute()
        receipt = self.receipt()
        commit = self.environment['GITHUB_SHA']
        fingerprint = gates.encode({'version': 1, 'commit': commit, 'head': commit,
                                    'toolchain': {'xcode': 'synthetic fixture', 'developer': '/synthetic'}})
        needs = {name: {'result': 'success', 'outputs': {}} for name in gates.REQUIRED_JOBS}
        for name in ['native', 'device-build', 'us-build', 'app-unit-tests']:
            needs[name]['outputs']['build_fingerprint'] = fingerprint
        for name in ['static-checks', 'native']:
            needs[name]['outputs']['static_receipt'] = receipt
        needs['ui-tests']['outputs'] = dict(gates.ui_completion(index, fingerprint, commit) for index in range(79))
        env = dict(self.environment, EXPECTED_STATIC_RECEIPT=receipt, NEEDS_JSON=json.dumps(needs))
        command = [sys.executable, '-B', str(self.root / 'tools/ci_gates.py')]
        native = subprocess.run(command + ['verify-static', '--static-artifact', str(self.output),
                                            '--github-output', str(self.temp / 'native-output')],
                                cwd=self.root, env=env, text=True, capture_output=True)
        self.assertEqual(native.returncode, 0, native.stderr)
        self.assertEqual((self.temp / 'native-output').read_text(), 'static_receipt=' + receipt + '\n')
        aggregate = subprocess.run(command + ['aggregate', '--static-artifact', str(self.output)],
                                   cwd=self.root, env=env, text=True, capture_output=True)
        self.assertEqual(aggregate.returncode, 0, aggregate.stderr)
        for name in gates.REQUIRED_JOBS:
            for outcome in ['failure', 'cancelled', 'skipped', None]:
                changed = copy.deepcopy(needs); changed[name]['result'] = outcome
                with self.subTest(job=name, outcome=outcome), self.assertRaises(ValueError):
                    gates.aggregate(changed, commit, receipt, '1234', '2')
        for name in ['static-checks', 'native']:
            for field in ['commit', 'tree', 'run_id', 'run_attempt', 'source_sha256', 'manifest_sha256']:
                changed = copy.deepcopy(needs); value = json.loads(receipt)
                value[field] = {'run_id': '9999', 'run_attempt': '9'}.get(field, 'b' * len(value[field]))
                changed[name]['outputs']['static_receipt'] = json.dumps(value)
                with self.subTest(job=name, field=field), self.assertRaises(ValueError):
                    gates.aggregate(changed, commit, receipt, '1234', '2')
            changed = copy.deepcopy(needs); changed[name]['outputs'].pop('static_receipt')
            with self.assertRaises(ValueError): gates.aggregate(changed, commit, receipt, '1234', '2')
        for index in range(79):
            changed = copy.deepcopy(needs); changed['ui-tests']['outputs'].pop('shard_' + str(index))
            with self.assertRaises(ValueError): gates.aggregate(changed, commit, receipt, '1234', '2')
        needs['static-checks']['result'] = 'skipped'; env['NEEDS_JSON'] = json.dumps(needs)
        denied = subprocess.run(command + ['aggregate', '--static-artifact', str(self.output)],
                                cwd=self.root, env=env, text=True, capture_output=True)
        self.assertNotEqual(denied.returncode, 0)


class LiveStaticWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        self.jobs = dict(re.findall(r'^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)',
                                   self.workflow.split('jobs:\n', 1)[1], re.M | re.S))

    def test_live_graph_keeps_all_gates_and_static_success_precedes_any_apple_work(self):
        self.assertEqual(set(self.jobs), gates.REQUIRED_JOBS | {'required-native-gates'})
        static, native, aggregate = (self.jobs[name] for name in ['static-checks', 'native', 'required-native-gates'])
        self.assertIn('runs-on: ubuntu-24.04', static)
        self.assertIn('timeout-minutes: 30', static)
        self.assertNotIn('    needs:', static)
        self.assertIn('run_static_checks.py run', static)
        self.assertIn('id: static', static)
        self.assertIn('static_receipt: ${{ steps.static.outputs.static_receipt }}', static)
        self.assertIn('needs: static-checks', native)
        self.assertIn('name: native-products', native)
        self.assertIn('EXPECTED_STATIC_RECEIPT: ${{ needs.static-checks.outputs.static_receipt }}', native)
        self.assertIn('timeout-minutes: 25', native)
        self.assertLess(native.index('actions/download-artifact@'), native.index('ci_gates.py verify-static'))
        self.assertLess(native.index('ci_gates.py verify-static'), native.index('ci_gates.py fingerprint'))
        self.assertLess(native.index('ci_gates.py verify-static'), native.index('xcodebuild'))
        self.assertNotIn('unittest discover', native)
        for value in ['tools/check_scaffold.py', 'plutil -lint', 'swift test',
                      'check_content_draft_api_boundary.py', 'check_play_recovery_api_boundary.py',
                      'check_built_profile.py --market CN', 'check_gltf_linked.py',
                      'for scheme in Questify QuestifyAppUnitTests; do',
                      'CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build-for-testing', 'test_products.py pack']:
            self.assertIn(value, native)
        for name in ['device-build', 'us-build', 'app-unit-tests', 'ui-tests']:
            self.assertEqual(re.findall(r'^    needs: (.+)$', self.jobs[name], re.M), ['native'])
        self.assertNotIn('    needs:', self.jobs['secrets'])
        self.assertIn('name: native\n', aggregate)
        self.assertIn('if: ${{ always() }}', aggregate)
        direct = re.search(r'    needs: \[(.+)\]', aggregate).group(1).split(', ')
        self.assertEqual(set(direct), gates.REQUIRED_JOBS)
        self.assertIn('NEEDS_JSON: ${{ toJSON(needs) }}', aggregate)
        self.assertIn('ci_gates.py aggregate --static-artifact', aggregate)
        self.assertNotIn('if:', aggregate.split('    steps:\n', 1)[1])

    def test_artifact_is_same_run_same_attempt_and_fail_closed_with_read_only_pinned_actions(self):
        artifact = 'name: static-checks-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}'
        self.assertEqual(self.workflow.count(artifact), 3)
        for name in ['native', 'required-native-gates']:
            self.assertIn('path: ${{ runner.temp }}/native-static-checks', self.jobs[name])
        self.assertIn('if-no-files-found: error', self.jobs['static-checks'])
        self.assertEqual(self.workflow.count('permissions:'), 1)
        self.assertIn('permissions:\n  contents: read\n', self.workflow)
        self.assertNotIn('continue-on-error', self.workflow)
        self.assertNotIn('PYTHONOPTIMIZE', self.workflow)
        self.assertNotIn('actions/cache', self.workflow)
        self.assertNotIn('run-id:', self.workflow)
        self.assertEqual(self.workflow.count('persist-credentials: false'), len(self.jobs))
        for action in re.findall(r'uses: (\S+)', self.workflow):
            self.assertRegex(action, r'^[\w/-]+@[0-9a-f]{40}$')
        secrets = self.jobs['secrets']
        self.assertIn('gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e', secrets)
        self.assertIn('gitleaks git --redact --exit-code=2', secrets)

    def test_live_ui79_app_unit_and_time_budgets_are_unchanged(self):
        ui = self.jobs['ui-tests']
        self.assertIn('timeout-minutes: 37', ui)
        self.assertIn('--deadline-seconds 1800', ui)
        self.assertIn('--count 79', ui)
        self.assertIn('fail-fast: false', ui)
        self.assertNotIn('-skip-testing', self.workflow)
        self.assertEqual(len(re.findall(r'^      shard_\d+:', ui, re.M)), 79)
        self.assertIn('timeout-minutes: 20', self.jobs['app-unit-tests'])
        self.assertIn('-only-testing:QuestifyAppUnitTests test-without-building', self.jobs['app-unit-tests'])
        self.assertEqual(self.workflow.count('name: test-products-${{ github.sha }}'), 3)

    def test_skip_allowlist_is_exact_ids_and_reasons_not_numeric_pass_condition(self):
        self.assertEqual(len(runner.ALLOWED_SKIPS), 49)
        for identifier, reason in runner.ALLOWED_SKIPS.items():
            with self.subTest(identifier=identifier), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary) / 'source'; root.mkdir()
                self.assertTrue(runner.skip_allowed(identifier, reason, root, {}))
                self.assertFalse(runner.skip_allowed(identifier + '_new', reason, root, {}))
                self.assertFalse(runner.skip_allowed(identifier, reason + ' changed', root, {}))


if __name__ == '__main__':
    unittest.main()
