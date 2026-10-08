"""The handshake budget suite must load without other tests preparing sys.path."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class HandshakeCleanProcessImportTests(unittest.TestCase):
    def test_handshake_suite_runs_first_in_clean_discovery_without_pythonpath(self):
        environment = os.environ.copy()
        environment.pop('PYTHONPATH', None)
        environment['PYTHONDONTWRITEBYTECODE'] = '1'
        result = subprocess.run(
            [sys.executable, '-m', 'unittest', 'discover', '-s', 'tools/tests',
             '-p', 'test_branch_history_handshake_budget.py', '-v'],
            cwd=ROOT, env=environment, capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('Ran 16 tests', output)
        self.assertRegex(output, r'(?m)^OK$')
        self.assertNotIn('_FailedTest', output)
        self.assertNotIn('ModuleNotFoundError', output)


if __name__ == '__main__':
    unittest.main()
