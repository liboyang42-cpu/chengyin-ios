"""Execute real small Git checkouts, then verify the live Linux-to-Apple gate."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import run_static_checks as runner

spec = importlib.util.spec_from_file_location('live_static_ci_gates', ROOT / 'tools/ci_gates.py')
gates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gates)


def read_until(process, marker, timeout=10):
    """Bounded read of real pipe bytes; no readline waiting for a newline."""
    output = b''
    deadline = time.monotonic() + timeout
    while marker not in output:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
            raise AssertionError('Timed out waiting for live output: ' + repr(output))
        chunk = os.read(process.stdout.fileno(), 65536)
        if not chunk:
            raise AssertionError('Process exited before live output: ' + repr(output))
        output += chunk
    return output


def finish_process(process):
    if process.poll() is None:
        process.terminate()
    try:
        process.communicate(timeout=12)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate(timeout=5)
        raise


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

    def test_live_partial_output_precedes_completion_and_matches_artifact_once(self):
        release = self.temp / 'release'
        self.tools.write_text(
            'import os, sys, time, unittest\nfrom pathlib import Path\n'
            'class Tools(unittest.TestCase):\n'
            ' def test_stream(self):\n'
            '  os.write(2, b"STDERR-BEFORE\\n")\n'
            '  sys.stdout.write("VISIBLE-PARTIAL")\n'
            '  while not Path(os.environ["RELEASE"]).exists(): time.sleep(.01)\n'
            '  os.write(1, b"\\xff\\n")\n')
        self.commit()
        command = [sys.executable, '-B', str(self.root / 'tools/run_static_checks.py'),
                   'run', '--output', str(self.output), '--github-output', str(self.github_output)]
        process = subprocess.Popen(command, cwd=self.root, env=dict(self.environment, RELEASE=str(release)),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.addCleanup(finish_process, process)
        early = read_until(process, b'VISIBLE-PARTIAL')
        self.assertIsNone(process.poll())
        self.assertFalse((self.output / 'tools.json').exists())
        self.assertIn(b'DISCOVERY START tools', early)
        self.assertIn(b'DISCOVERY END tools duration_seconds=', early)
        self.assertIn(b'START test_probe.Tools.test_stream', early)
        self.assertIn(b'STDERR-BEFORE', early)
        self.assertNotIn(b'END test_probe.Tools.test_stream', early)
        release.touch()
        tail, _ = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 0, early + tail)
        expected = b''
        for name, specification in runner.SUITES.items():
            raw = (self.output / (name + '.log')).read_bytes()
            expected += ('Full static discovery: ' + name + ' ' + str(specification) + '\n').encode() + raw
            self.assertEqual((early + tail).count(raw), 1)
        self.assertEqual(early + tail, expected)
        self.assertIn(b'VISIBLE-PARTIAL\xff\n', expected)
        self.assertRegex(expected, rb'END test_probe.Tools.test_stream duration_seconds=\d+\.\d{6}')
        self.assertEqual(self.verify(self.receipt()), self.receipt())

    def test_logged_failure_skip_and_import_error_keep_counts_and_exit_status(self):
        cases = [
            ('failure', 'import unittest\nclass Tools(unittest.TestCase):\n def test_one(self): self.fail("fixture")\n', 1, 1, 0, 1, 0),
            ('skip', 'import unittest\nclass Tools(unittest.TestCase):\n @unittest.skip("fixture")\n def test_one(self): pass\n', 1, 1, 1, 0, 0),
            ('class_skip', 'import unittest\nclass Tools(unittest.TestCase):\n @classmethod\n def setUpClass(cls): raise unittest.SkipTest("fixture")\n def test_one(self): pass\n', 1, 0, 1, 0, 0),
            ('import_error', 'raise RuntimeError("fixture import failure")\n', 1, 1, 0, 0, 1),
        ]
        for name, source, discovered, executed, skips, failures, errors in cases:
            with self.subTest(case=name):
                self.tools.write_text(source)
                self.commit()
                self.output = self.temp / name
                self.github_output = self.temp / (name + '-output')
                result = self.execute(1)
                self.assertEqual(result.returncode, 1)
                report = json.loads((self.output / 'tools.json').read_text())
                self.assertEqual((report['discovered_count'], report['executed_count'], report['tests_run'],
                                  report['skip_count'], len(report['failures']), len(report['errors'])),
                                 (discovered, executed, executed, skips, failures, errors))
                self.assertEqual(bool(report['discovery_errors']), name == 'import_error')
                log = (self.output / 'tools.log').read_text()
                self.assertEqual(result.stdout.count(log), 1)
                self.assertIn('DISCOVERY START tools', log)
                self.assertIn('DISCOVERY END tools duration_seconds=', log)
                for identifier in report['executed_ids']:
                    self.assertIn('START ' + identifier + '\n', log)
                    self.assertIn('END ' + identifier + ' duration_seconds=', log)
                self.assertTrue((self.output / 'contracts.json').exists())

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


class StaticObservabilityFixtures(unittest.TestCase):
    def setUp(self):
        self.life = tempfile.TemporaryDirectory(prefix='native-static-output-')
        self.addCleanup(self.life.cleanup)
        self.base = Path(self.life.name)
        self.log = self.base / 'child.log'

    def start_wrapper(self, child):
        code = ('import os, sys\nfrom pathlib import Path\n'
                'sys.path.insert(0, ' + repr(str(ROOT / 'tools')) + ')\n'
                'import run_static_checks as runner\n'
                'result = runner.run_logged_process(' + repr([sys.executable, '-B', '-u', '-c', child]) +
                ', Path.cwd(), dict(os.environ), Path(' + repr(str(self.log)) + '))\n'
                'print("CHILD_RETURN_CODE=" + str(result.returncode), flush=True)\n')
        process = subprocess.Popen([sys.executable, '-B', '-u', '-c', code],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.addCleanup(finish_process, process)
        return process

    def test_tee_preserves_nonzero_exit_and_merged_bytes(self):
        process = self.start_wrapper('import os\nos.write(1, b"out\\n")\nos.write(2, b"err\\n")\nraise SystemExit(7)')
        output, _ = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, output)
        self.assertEqual(self.log.read_bytes(), b'out\nerr\n')
        self.assertEqual(output, self.log.read_bytes() + b'CHILD_RETURN_CODE=7\n')

    def test_tee_retries_short_console_writes_without_losing_bytes(self):
        class ShortWriter(io.BytesIO):
            def write(self, value):
                return super().write(value[:3])
        output = ShortWriter()
        console = mock.Mock(buffer=output)
        command = [sys.executable, '-B', '-u', '-c', 'import os; os.write(1, bytes(range(256)))']
        with mock.patch.object(runner.sys, 'stdout', console):
            result = runner.run_logged_process(command, self.base, dict(os.environ), self.log)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(output.getvalue(), bytes(range(256)))
        self.assertEqual(output.getvalue(), self.log.read_bytes())

    def test_cancellation_during_short_write_flushes_the_pending_chunk(self):
        for signum in [signal.SIGTERM, signal.SIGINT]:
            with self.subTest(signal=signum):
                class InterruptedWriter(io.BytesIO):
                    sent = False

                    def write(self, value):
                        if not self.sent:
                            self.sent = True
                            os.kill(os.getpid(), signum)
                        return super().write(value[:3])
                output = InterruptedWriter()
                log = self.base / ('cancel-' + str(signum) + '.log')
                command = [sys.executable, '-B', '-u', '-c',
                           'import os,time; os.write(1, bytes(range(256))); time.sleep(30)']
                with mock.patch.object(runner.sys, 'stdout', mock.Mock(buffer=output)):
                    with self.assertRaises(SystemExit) as stopped:
                        runner.run_logged_process(command, self.base, dict(os.environ), log)
                self.assertEqual(stopped.exception.code, 128 + signum)
                self.assertEqual(output.getvalue(), bytes(range(256)))
                self.assertEqual(output.getvalue(), log.read_bytes())

    def test_killed_child_with_inherited_writer_cannot_hold_tee_open(self):
        # The grandchild inherits stdout/stderr and ignores TERM. A pipe tee
        # would wait forever after the direct child dies unless it cleans up.
        grandchild = ('import signal,time\n'
                      'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                      'print("INHERITED-WRITER", flush=True)\ntime.sleep(30)')
        child = ('import os,signal,subprocess,sys,time\n'
                 'print("CHILD_PID=" + str(os.getpid()), flush=True)\n'
                 'subprocess.Popen([sys.executable,"-u","-c",' + repr(grandchild) + '])\ntime.sleep(30)')
        process = self.start_wrapper(child)
        early = read_until(process, b'INHERITED-WRITER\n')
        pid = int(re.search(rb'CHILD_PID=(\d+)', early).group(1))
        os.kill(pid, signal.SIGKILL)
        tail, _ = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, early + tail)
        self.assertEqual(early + tail, self.log.read_bytes() + b'CHILD_RETURN_CODE=-9\n')

    def test_parent_timeout_term_reaps_child_and_relays_shutdown_output(self):
        child = ('import os,signal,time\n'
                 'def stop(signum, frame):\n'
                 ' print("SHUTDOWN", flush=True)\n raise SystemExit(0)\n'
                 'signal.signal(signal.SIGTERM, stop)\n'
                 'print("CHILD_PID=" + str(os.getpid()), flush=True)\ntime.sleep(30)')
        process = self.start_wrapper(child)
        early = read_until(process, b'CHILD_PID=')
        # The marker is deliberately a complete short print in the fixture.
        while b'\n' not in early:
            early += read_until(process, b'\n')
        pid = int(re.search(rb'CHILD_PID=(\d+)', early).group(1))
        with self.assertRaises(subprocess.TimeoutExpired):
            process.wait(timeout=.05)
        process.terminate()
        tail, _ = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 128 + signal.SIGTERM, early + tail)
        self.assertEqual(early + tail, self.log.read_bytes())
        self.assertIn(b'SHUTDOWN\n', early + tail)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_parent_term_escalates_for_child_ignoring_term(self):
        child = ('import os,signal,time\n'
                 'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                 'print("CHILD_PID=" + str(os.getpid()), flush=True)\ntime.sleep(30)')
        process = self.start_wrapper(child)
        early = read_until(process, b'\n')
        pid = int(re.search(rb'CHILD_PID=(\d+)', early).group(1))
        started = time.monotonic()
        process.terminate()
        time.sleep(.05)
        process.terminate()  # Repeated cancellation must not interrupt cleanup.
        tail, _ = process.communicate(timeout=10)
        self.assertLess(time.monotonic() - started, 10)
        self.assertEqual(process.returncode, 128 + signal.SIGTERM, early + tail)
        self.assertEqual(early + tail, self.log.read_bytes())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_import_and_class_setup_stacks_show_location_without_locals(self):
        directory = self.base / 'source/tools/tests'
        directory.mkdir(parents=True)
        for phase in ['import', 'class_setup']:
            with self.subTest(phase=phase):
                body = ('import time, unittest\n'
                        'def stall():\n'
                        ' private_local = "SECRET-LOCAL-MUST-NOT-APPEAR"\n'
                        ' time.sleep(.2)\n')
                if phase == 'import':
                    body += 'stall()\n'
                body += 'class Probe(unittest.TestCase):\n'
                if phase == 'class_setup':
                    body += ' @classmethod\n def setUpClass(cls): stall()\n'
                body += ' def test_one(self): pass\n'
                (directory / 'test_probe.py').write_text(body)
                code = ('import os,sys\nfrom pathlib import Path\n'
                        'sys.path.insert(0, ' + repr(str(ROOT / 'tools')) + ')\n'
                        'import run_static_checks as runner\n'
                        'original = runner._diagnostic_watchdog\n'
                        'def accelerated(stopped, interval, descriptor):\n'
                        ' assert interval == 60\n original(stopped, .05, descriptor)\n'
                        'runner._diagnostic_watchdog = accelerated\n'
                        'os.environ["NATIVE_STATIC_DIAGNOSTIC_STACKS"] = "1"\n'
                        'report = runner.suite_report("tools", Path(' + repr(str(self.base / 'source')) + '))\n'
                        'print("REPORT=" + runner.encode(report))\n')
                result = subprocess.run([sys.executable, '-B', '-u', '-c', code],
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                report = json.loads(result.stdout.split('REPORT=', 1)[1])
                self.assertEqual((report['discovered_count'], report['tests_run'], report['skip_count']), (1, 1, 0))
                self.assertEqual(report['successes'], ['test_probe.Probe.test_one'])
                self.assertEqual(report['discovery_errors'], [])
                self.assertNotIn('SECRET-LOCAL-MUST-NOT-APPEAR', result.stdout + result.stderr)
                self.assertIn('in stall', result.stderr)
                stack = result.stderr.index('Timeout')
                end = result.stderr.index('DISCOVERY END tools')
                self.assertLess(result.stderr.index('DISCOVERY START tools'), stack)
                if phase == 'import':
                    self.assertLess(stack, end)
                else:
                    self.assertLess(end, stack)
                    self.assertLess(stack, result.stderr.index('START test_probe.Probe.test_one'))

    def test_startup_cancellation_owns_child_inside_popen_and_at_handoff(self):
        for boundary in ['inside_popen', 'returned_handle']:
            for signum in [signal.SIGTERM, signal.SIGINT]:
                with self.subTest(boundary=boundary, signal=signum):
                    captured = []
                    handlers = {value: signal.getsignal(value) for value in [signal.SIGTERM, signal.SIGINT]}
                    mask = signal.pthread_sigmask(signal.SIG_BLOCK, [])

                    def cleanup(processes=captured):
                        for process in processes:
                            if process.poll() is None:
                                os.killpg(process.pid, signal.SIGKILL)
                            process.wait(timeout=5)
                    self.addCleanup(cleanup)

                    def trace(frame, event, arg):
                        process = None
                        if (boundary == 'inside_popen' and event == 'return'
                                and frame.f_code is subprocess.Popen._execute_child.__code__):
                            process = frame.f_locals['self']
                        elif (boundary == 'returned_handle' and event == 'line'
                              and frame.f_code is runner.run_logged_process.__code__):
                            process = frame.f_locals.get('process')
                        if process is not None:
                            captured.append(process)
                            sys.settrace(None)
                            os.kill(os.getpid(), signum)
                            # Refresh CPython's tracing locals snapshot after
                            # the handler changes a closure cell; do not write
                            # its pre-signal value back when this trace returns.
                            frame.f_locals
                        return trace

                    command = [sys.executable, '-B', '-u', '-c', 'import time; time.sleep(60)']
                    log = self.base / (boundary + '-' + str(signum) + '.log')
                    try:
                        sys.settrace(trace)
                        with self.assertRaises(SystemExit) as stopped:
                            runner.run_logged_process(command, self.base, dict(os.environ), log)
                    finally:
                        sys.settrace(None)
                    self.assertEqual(stopped.exception.code, 128 + signum)
                    self.assertEqual(len(captured), 1)
                    self.assertIsNotNone(captured[0].poll())
                    with self.assertRaises(ProcessLookupError):
                        os.kill(captured[0].pid, 0)
                    self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, []), mask)
                    self.assertEqual({value: signal.getsignal(value) for value in handlers}, handlers)

    def test_first_cancellation_at_cleanup_entry_still_reaps_child(self):
        source = Path(runner.__file__).read_text().splitlines()
        # R2's phase assignment and R2b's handle check are their respective
        # first cleanup instructions; the same regression must fail on R2.
        targets = [index for index, line in enumerate(source, 1)
                   if line.strip() in {"phase = 'cleanup'", 'if process is not None:'}]
        boundary = min(targets)
        for signum in [signal.SIGTERM, signal.SIGINT]:
            with self.subTest(signal=signum):
                captured = []

                def cleanup(processes=captured):
                    for process in processes:
                        if process.poll() is None:
                            os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
                self.addCleanup(cleanup)

                def trace(frame, event, arg):
                    if (event == 'line' and frame.f_code is runner.run_logged_process.__code__
                            and frame.f_lineno == boundary):
                        captured.append(frame.f_locals['process'])
                        sys.settrace(None)
                        os.kill(os.getpid(), signum)
                        frame.f_locals  # Refresh the post-handler closure snapshot.
                    return trace

                class FailedConsole:
                    def write(self, value):
                        return 0

                    def flush(self):
                        pass
                command = [sys.executable, '-B', '-u', '-c',
                           'import time; print("ready", flush=True); time.sleep(60)']
                log = self.base / ('cleanup-' + str(signum) + '.log')
                try:
                    sys.settrace(trace)
                    with mock.patch.object(runner.sys, 'stdout', mock.Mock(buffer=FailedConsole())):
                        with self.assertRaises(SystemExit) as stopped:
                            runner.run_logged_process(command, self.base, dict(os.environ), log)
                finally:
                    sys.settrace(None)
                self.assertEqual(stopped.exception.code, 128 + signum)
                self.assertEqual(len(captured), 1)
                self.assertIsNotNone(captured[0].poll())
                with self.assertRaises(ProcessLookupError):
                    os.kill(captured[0].pid, 0)

    def test_child_starts_with_original_unblocked_cancellation_mask(self):
        before = signal.pthread_sigmask(signal.SIG_BLOCK, [])
        self.assertTrue({signal.SIGTERM, signal.SIGINT}.isdisjoint(before))
        code = ('import json,signal; '
                'print(json.dumps(sorted(map(int, signal.pthread_sigmask(signal.SIG_BLOCK, [])))))')
        output = io.BytesIO()
        with mock.patch.object(runner.sys, 'stdout', mock.Mock(buffer=output)):
            result = runner.run_logged_process([sys.executable, '-B', '-u', '-c', code],
                                               self.base, dict(os.environ), self.log)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(output.getvalue()), sorted(map(int, before)))
        self.assertEqual(output.getvalue(), self.log.read_bytes())

    def test_test_markers_use_monotonic_elapsed_without_changing_outcomes(self):
        class Probe(unittest.TestCase):
            def test_success(self):
                pass
        stream = io.StringIO()
        result = runner.RecordingResult(unittest.runner._WritelnDecorator(stream), True, 2)
        test = Probe('test_success')
        with mock.patch.object(runner.time, 'monotonic', side_effect=[100.0, 100.25]):
            test.run(result)
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(result.executed_ids, [test.id()])
        self.assertEqual(result.success_ids, [test.id()])
        self.assertTrue(result.wasSuccessful())
        self.assertIn('START ' + test.id() + '\n', stream.getvalue())
        self.assertIn('END ' + test.id() + ' duration_seconds=0.250000\n', stream.getvalue())

    def test_diagnostic_stacks_are_opt_in_sixty_seconds_and_always_cancelled(self):
        with mock.patch.object(runner.threading, 'Thread') as thread, \
             mock.patch.object(runner.threading, 'Event') as event:
            with mock.patch.dict(os.environ, {'NATIVE_STATIC_DIAGNOSTIC_STACKS': '0'}):
                with runner.diagnostic_stacks():
                    pass
            thread.assert_not_called()
            event.assert_not_called()
            with mock.patch.dict(os.environ, {'NATIVE_STATIC_DIAGNOSTIC_STACKS': '1'}):
                with self.assertRaisesRegex(RuntimeError, 'fixture failure'):
                    with runner.diagnostic_stacks():
                        raise RuntimeError('fixture failure')
            thread.assert_called_once_with(target=runner._diagnostic_watchdog,
                args=(event.return_value, 60, sys.stderr.fileno()),
                name='static-stack-diagnostics', daemon=True)
            thread.return_value.start.assert_called_once_with()
            event.return_value.set.assert_called_once_with()
            thread.return_value.join.assert_called_once_with()

    def test_diagnostic_worker_repeats_real_interval_and_stops_without_native_watchdog(self):
        stopped = mock.Mock()
        stopped.wait.side_effect = [False, False, True]
        with mock.patch.object(runner.faulthandler, 'dump_traceback') as dump, \
             mock.patch.object(runner.faulthandler, 'dump_traceback_later') as unsafe, \
             mock.patch.object(runner.os, 'write') as write:
            runner._diagnostic_watchdog(stopped, 60, 2)
        self.assertEqual(stopped.wait.call_args_list, [mock.call(60)] * 3)
        self.assertEqual(dump.call_args_list, [mock.call(file=2, all_threads=True)] * 2)
        self.assertEqual(write.call_args_list, [mock.call(2, b'Timeout (60-second diagnostic interval)!\n')] * 2)
        unsafe.assert_not_called()

    def test_diagnostic_worker_error_does_not_change_body_exception_or_leave_worker(self):
        before = set(runner.threading.enumerate())
        for error in [OSError('private failure'), RuntimeError('private failure'), ValueError('private failure')]:
            stopped = mock.Mock()
            stopped.wait.return_value = False
            with mock.patch.object(runner.faulthandler, 'dump_traceback', side_effect=error), \
                 mock.patch.object(runner.os, 'write'):
                runner._diagnostic_watchdog(stopped, 60, 2)
            stopped.wait.assert_called_once_with(60)
        with mock.patch.dict(os.environ, {'NATIVE_STATIC_DIAGNOSTIC_STACKS': '1'}):
            for _ in range(20):
                with self.assertRaisesRegex(RuntimeError, 'original body failure'):
                    with runner.diagnostic_stacks():
                        raise RuntimeError('original body failure')
        self.assertEqual(set(runner.threading.enumerate()), before)

    def test_diagnostic_frame_churn_and_teardown_preserve_real_process_outcome(self):
        code = ("import os,sys,time,types,threading,faulthandler\n"
                "from pathlib import Path\n"
                "sys.path.insert(0, " + repr(str(ROOT / 'tools')) + ")\n"
                "import run_static_checks as runner\n"
                "original = runner._diagnostic_watchdog\n"
                "samples = []\n"
                "dump = runner.faulthandler.dump_traceback\n"
                "def real_dump(**kwargs):\n"
                " samples.append(1)\n dump(**kwargs)\n"
                "runner.faulthandler.dump_traceback = real_dump\n"
                "def accelerated(stopped, interval, descriptor):\n"
                " assert interval == 60\n original(stopped, .00001, descriptor)\n"
                "runner._diagnostic_watchdog = accelerated\n"
                "os.environ['NATIVE_STATIC_DIAGNOSTIC_STACKS'] = '1'\n"
                "baseline = set(threading.enumerate())\n"
                "def template(): return 1\n"
                "with open(os.devnull, 'w') as out:\n"
                " sys.stderr = out\n"
                " for iteration in range(12):\n"
                "  with runner.diagnostic_stacks():\n"
                "   until = time.monotonic() + .025\n"
                "   while time.monotonic() < until:\n"
                "    code = template.__code__.replace(); function = types.FunctionType(code, {})\n"
                "    assert function() == 1\n"
                "    del function, code\n"
                "  assert set(threading.enumerate()) == baseline\n"
                "assert len(samples) >= 12, len(samples)\n"
                "print('CHURN_AND_CANCEL_OK')\n")
        result = subprocess.run([sys.executable, '-B', '-u', '-c', code],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), 'CHURN_AND_CANCEL_OK')
        self.assertEqual(result.stderr, '')


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
