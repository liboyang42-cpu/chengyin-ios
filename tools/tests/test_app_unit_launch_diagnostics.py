import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('launch_diagnostics', Path(__file__).resolve().parents[1] / 'collect_app_unit_launch_diagnostics.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AppUnitLaunchDiagnosticsTests(unittest.TestCase):
    def test_facts_keep_only_fixed_labels_codes_and_constraint_slots(self):
        source = 'Questify /private/secret/person token=VERYPRIVATE AMFI Launch Constraint Violation c[1]p[1]m[1]e[2] NSPOSIXErrorDomain Code=162'
        result = module.facts(source)
        self.assertIn('launch_constraint', result['categories'])
        self.assertEqual(result['codes'], [162])
        self.assertEqual(result['constraint_slots'], ['c[1]', 'e[2]', 'm[1]', 'p[1]'])
        encoded = json.dumps(result)
        for private in ['/private', 'VERYPRIVATE', 'person', 'token']: self.assertNotIn(private, encoded)

    def test_summary_preserves_integer_counts_not_arbitrary_fields(self):
        data = {'totalTestCount': 0, 'failedTests': 0, 'passedTests': 'secret', 'email': 'private@example.com',
                'failure': {'message': 'RBSRequestErrorDomain Code=5 Launch failed.'}}
        result = module.summarize(json.dumps(data).encode())
        self.assertEqual(result['counts'], {'totalTestCount': 0, 'failedTests': 0})
        self.assertIn('launch_failed', result['facts']['categories'])
        self.assertNotIn('private@example.com', json.dumps(result))

    def test_non_json_or_wrong_log_shape_has_no_raw_echo(self):
        self.assertEqual(module.summarize(b'PRIVATE'), {'format': 'unavailable_or_non_json'})
        self.assertEqual(module.summarize(b'{}', logs=True), {'format': 'unexpected_json_shape'})

    def test_logs_recheck_app_filter_and_bound_records(self):
        data = [{'eventMessage': 'other-app AMFI Code=999 PRIVATE'},
                {'eventMessage': 'Questify launchd job spawn failed Code=162 PRIVATE',
                 'timestamp': '2026-10-04 11:00:58.704Z', 'environment': 'PRIVATE'}] * 100
        result = module.summarize(json.dumps(data).encode(), logs=True)
        self.assertEqual(len(result['records']), module.MAX_RECORDS)
        self.assertEqual(result['source_records'], 200)
        self.assertNotIn('PRIVATE', json.dumps(result))
        self.assertNotIn('999', json.dumps(result))

    def test_capture_success_and_stderr_are_bounded_and_separate(self):
        meta, data = module.capture([sys.executable, '-c', 'import sys; print("ok"); print("PRIVATE",file=sys.stderr)'])
        self.assertEqual(meta['state'], 'complete'); self.assertEqual(meta['exit_code'], 0)
        self.assertEqual(data, b'ok\n'); self.assertEqual(meta['stderr_bytes'], 8)
        self.assertNotIn('PRIVATE', json.dumps(meta))

    def test_capture_failure_never_returns_raw_error_output(self):
        meta, data = module.capture([sys.executable, '-c', 'print("PRIVATE"); raise SystemExit(3)'])
        self.assertEqual(meta['exit_code'], 3); self.assertEqual(data, b'')

    def test_capture_limit_stops_own_command(self):
        meta, data = module.capture([sys.executable, '-c', 'print("X"*100000)'], limit=100)
        self.assertEqual(meta['state'], 'output_limit')
        self.assertLessEqual(meta['stdout_bytes'] + meta['stderr_bytes'], 100)
        self.assertEqual(data, b'')

    def test_capture_timeout_stops_own_command(self):
        meta, data = module.capture([sys.executable, '-c', 'import time; time.sleep(10)'], timeout=0.02)
        self.assertEqual(meta['state'], 'timeout'); self.assertEqual(data, b'')

    def test_missing_tools_are_explicit(self):
        meta, data = module.capture(['/nonexistent/synthetic-tool'])
        self.assertEqual(meta, {'state': 'unavailable'}); self.assertEqual(data, b'')

    def test_collection_commands_are_read_only_and_exactly_scoped(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'questify-app-unit-results.xcresult').mkdir()
            (root / 'questify-app-unit-boot.log').write_text('Data Migration Failed PRIVATE')
            commands = []
            def run(command):
                commands.append(command)
                return {'state': 'complete', 'exit_code': 0}, b'[]'
            simulator = 'A1194899-F789-4C4B-A9E2-EFDC6C72EB35'
            result = module.collect(root, simulator, run)
            self.assertEqual(len(commands), 3)
            self.assertEqual(commands[0][:5], ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary'])
            self.assertEqual(commands[1][0], '/usr/bin/log')
            self.assertEqual(commands[2][:4], ['xcrun', 'simctl', 'spawn', simulator])
            for command in commands[1:]:
                self.assertIn(module.PREDICATE, command)
                self.assertEqual(command[command.index('--last')+1], '15m')
            self.assertFalse(result['root_cause_established'])
            self.assertTrue(result['diagnostic_only'])
            self.assertIn('migration_failed', result['boot']['facts']['categories'])
            self.assertNotIn('PRIVATE', json.dumps(result))

    def test_missing_input_and_malicious_simulator_never_spawns(self):
        with tempfile.TemporaryDirectory() as folder:
            calls = []
            result = module.collect(Path(folder), '; changed-setting', lambda c: (calls.append(c) or ({'state':'unavailable'}, b'')))
            self.assertEqual(len(calls), 1)
            self.assertEqual(result['xcresult_summary']['state'], 'missing')
            self.assertEqual(result['simulator_launch_log']['state'], 'missing_or_invalid_simulator_id')

    def test_workflow_retains_original_testing_and_large_artifact(self):
        text = (Path(__file__).resolve().parents[2] / '.github/workflows/native-ios.yml').read_text()
        job = text.split('  app-unit-tests:\n', 1)[1].split('  ui-tests:\n', 1)[0]
        self.assertIn('set -o pipefail', job)
        self.assertIn('simctl bootstatus "$TEST_SIMULATOR_ID" -b', job)
        self.assertIn('-only-testing:QuestifyAppUnitTests test-without-building', job)
        self.assertLess(job.index('test-without-building'), job.index('collect_app_unit_launch_diagnostics.py'))
        self.assertLess(job.index('collect_app_unit_launch_diagnostics.py'), job.index('Retain app-unit test results briefly'))
        self.assertIn('questify-app-unit-results.xcresult', job)
        self.assertEqual(text.count('collect_app_unit_launch_diagnostics.py'), 1)
        self.assertNotIn('continue-on-error', job)
        self.assertNotIn('--deep', job)
