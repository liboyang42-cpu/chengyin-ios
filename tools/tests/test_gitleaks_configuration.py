"""Offline configuration guards; the real full-history scanner runs in CI."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
IMPORT_COMMIT = "e39c367a35e1f15f9553701cbad56d0d10796c80"


class GitleaksConfigurationTests(unittest.TestCase):
    def test_reviewed_ignores_are_commit_bound(self):
        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        self.assertEqual(len(entries), 42)
        self.assertEqual(len(set(entries)), 42)
        for entry in entries:
            with self.subTest(entry=entry):
                self.assertRegex(entry, rf"^{IMPORT_COMMIT}:[^:*?\[\]]+:generic-api-key:[1-9][0-9]*$")
                commit, path, rule, line = entry.split(":")
                self.assertNotIn(f"{path}:{rule}:{line}", entries)
                self.assertNotIn(f"{'0' * 40}:{path}:{rule}:{line}", entries)

    def test_scan_stays_read_only_and_pinned(self):
        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()
        job = workflow.split("  secrets:\n", 1)[1].split("  app-unit-tests:\n", 1)[0]
        self.assertIn("permissions:\n  contents: read\n", workflow)
        self.assertIn("fetch-depth: 0", job)
        self.assertIn("persist-credentials: false", job)
        self.assertIn("gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e", job)
        for key, value in [("GITLEAKS_VERSION", "8.24.3"),
                           ("GITLEAKS_ENABLE_COMMENTS", "false"),
                           ("GITLEAKS_ENABLE_UPLOAD_ARTIFACT", "false")]:
            self.assertIn(f"{key}: '{value}'", job)
        self.assertNotIn("continue-on-error", job)

    def test_full_history_step_reuses_binary_and_fails_closed(self):
        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()
        step = workflow.split("      - name: Scan full checked-out branch history\n", 1)[1]
        step = step.split("  app-unit-tests:\n", 1)[0]
        self.assertIn("shell: bash", step)
        self.assertIn("set -euo pipefail", step)
        self.assertIn("command -v gitleaks >/dev/null", step)
        self.assertIn("test \"$(gitleaks version)\" = '8.24.3'", step)
        self.assertIn('gitleaks git --redact --exit-code=2 --log-opts="--full-history -m HEAD"', step)
        commands = "\n".join(line for line in step.splitlines() if not line.lstrip().startswith("#"))
        self.assertNotRegex(commands, r"--all|--first-parent|--no-merges|curl|wget|\|\|\s*true")


if __name__ == "__main__":
    unittest.main()
