"""Test gate failure handling without treating mocked compiles as Apple evidence."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('draft_api_gate', ROOT / 'tools/check_content_draft_api_boundary.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ContentDraftAPIGateTests(unittest.TestCase):
    def invoke(self, results=None, *, platform='darwin', compiler='/synthetic/swiftc', built=True):
        with tempfile.TemporaryDirectory() as temporary:
            module = Path(temporary)
            if built:
                (module / 'QuestifyCore.swiftmodule').mkdir()
            with patch.object(gate.sys, 'argv', ['check', '--module-path', str(module)]), \
                 patch.object(gate.sys, 'platform', platform), \
                 patch.object(gate.shutil, 'which', return_value=compiler), \
                 patch.object(gate.subprocess, 'run', side_effect=results) as run, \
                 contextlib.redirect_stdout(io.StringIO()):
                status = gate.main()
                return status, run.call_args_list

    def result(self, code, diagnostic=''):
        return subprocess.CompletedProcess([], code, '', diagnostic)

    def test_missing_toolchain_or_module_is_not_a_pass(self):
        for options in [{'platform': 'linux'}, {'compiler': None}, {'built': False}]:
            status, calls = self.invoke(**options)
            self.assertEqual(status, 2)
            self.assertEqual(calls, [])

    def test_positive_failure_stops_before_negative_controls(self):
        status, calls = self.invoke([self.result(1, 'cannot import module')])
        self.assertEqual(status, 1)
        self.assertEqual(len(calls), 1)

    def test_negative_control_requires_expected_diagnostic_and_normal_error_exit(self):
        expected = "cannot convert value of type 'ContentDraftMutation' to expected argument type 'ContentDraftPreparedDispatch'"
        for result in [self.result(0, expected), self.result(-11, expected), self.result(2, expected), self.result(1, 'unrelated compiler failure')]:
            status, calls = self.invoke([self.result(0), result])
            self.assertEqual(status, 1)
            self.assertEqual(len(calls), 2)
        status, calls = self.invoke([self.result(0), self.result(1, expected),
            self.result(1, "inaccessible due to 'fileprivate' protection level"),
            self.result(1, 'no accessible initializers')])
        self.assertEqual(status, 0)
        self.assertEqual(len(calls), 4)
        self.assertTrue(all(call.kwargs['timeout'] == 60 for call in calls))

    def test_timeout_and_launch_failure_fail_closed(self):
        for failure in [OSError('compiler unavailable'), subprocess.TimeoutExpired('swiftc', 60)]:
            status, calls = self.invoke([failure])
            self.assertEqual(status, 1)
            self.assertEqual(len(calls), 1)

    def test_hosted_gate_follows_swift_build_and_cannot_be_ignored(self):
        workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        domain = workflow.index('run: swift test')
        start = workflow.index('- name: Compile content-draft API boundary controls')
        end = workflow.index('- name: Compile iOS simulator app', start)
        section = workflow[start:end]
        self.assertLess(domain, start)
        self.assertIn('run: python3 tools/check_content_draft_api_boundary.py --module-path .build/debug/Modules', section)
        for forbidden in ['continue-on-error', '||', 'if:']:
            self.assertNotIn(forbidden, section)
