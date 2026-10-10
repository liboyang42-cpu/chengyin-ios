"""Offline configuration guards; the real full-history scanner runs in CI."""
from pathlib import Path
import re
import json
import hashlib
import unittest


ROOT = Path(__file__).resolve().parents[2]
MAIN_MERGE_COMMIT = "4e7349186d21448354d3bf4c6b4ab6adfc25fc1f"
MAIN_MERGE_RECORDS = json.loads((ROOT / "tools/tests/fixtures/gitleaks-main-merge-audit-2026-10-05.json").read_text())["findings"]
MAIN_MERGE_FINDINGS = {f"{r['commit']}:{r['path']}:{r['rule']}:{r['line']}" for r in MAIN_MERGE_RECORDS}
IMPORT_COMMIT = "e39c367a35e1f15f9553701cbad56d0d10796c80"
COVERAGE_PROSE_FINDING = "bcd754bd41dd41b3dad22a436211cd89ee47b657:docs/public-template/composition-read-grant.md:generic-api-key:75"
CI132_PROSE_FINDING = "c95737b4c54881a7492ca72bd31f68749304d1d1:docs/square-post-local-media.md:generic-api-key:31"
FILE_DIGEST_COMMIT = "65023b84211895bf6c3f6d8ec64804edbfc45e4d"
FILE_DIGEST_PATH = "tools/run138_editor_readiness_contract.json"
FILE_DIGEST_RECORDS = (
    (174, "current_ui_sources", "WeChatAppAuthFlowTests.swift",
     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",
     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),
    (243, "previous_ui_sources", "WeChatAppAuthFlowTests.swift",
     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",
     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),
    (4028, "feature_batch_support_sha256", "Tests/ContractChecks/test_merchant_business_access_lifetime.py",
     "Tests/ContractChecks/test_merchant_business_access_lifetime.py",
     "a808e190bda202c021e4cbada812e684d92e4e7ac6848d2016c944c3d3d494e4"),
)
FILE_DIGEST_FINDINGS = {
    f"{FILE_DIGEST_COMMIT}:{FILE_DIGEST_PATH}:generic-api-key:{row[0]}"
    for row in FILE_DIGEST_RECORDS
}

COUPON_FIXTURE_FINDINGS = {
    f"abe535809517ceb327223679f85c14b5f5b8b6d7:App/CouponRuntimeFixture.swift:generic-api-key:{line}"
    for line in (55, 81, 110)
}


class GitleaksConfigurationTests(unittest.TestCase):
    def test_reviewed_ignores_are_commit_bound(self):
        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        self.assertEqual(len(entries), 92)
        self.assertEqual(len(set(entries)), 92)
        self.assertEqual(entries.count(COVERAGE_PROSE_FINDING), 1)
        self.assertEqual(entries.count(CI132_PROSE_FINDING), 1)
        legacy = [entry for entry in entries if entry not in (COVERAGE_PROSE_FINDING, CI132_PROSE_FINDING) and entry not in COUPON_FIXTURE_FINDINGS and entry not in MAIN_MERGE_FINDINGS and entry not in FILE_DIGEST_FINDINGS]
        self.assertEqual(len(legacy), 42)
        for entry in legacy:
            with self.subTest(entry=entry):
                self.assertRegex(entry, rf"^{IMPORT_COMMIT}:[^:*?\[\]]+:generic-api-key:[1-9][0-9]*$")
                commit, path, rule, line = entry.split(":")
                self.assertNotIn(f"{path}:{rule}:{line}", entries)
                self.assertNotIn(f"{'0' * 40}:{path}:{rule}:{line}", entries)

    def test_main_merge_exceptions_bind_exact_source_lines_and_do_not_cover_new_history(self):
        entries = {line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith("#")}
        self.assertEqual(len(MAIN_MERGE_FINDINGS), 42)
        self.assertTrue(MAIN_MERGE_FINDINGS.issubset(entries))
        self.assertEqual({r["classification"] for r in MAIN_MERGE_RECORDS},
                         {"external_source_sha256_provenance", "native_source_sha256", "forbidden_mutation_route_assertion_literal"})
        for row in MAIN_MERGE_RECORDS:
            with self.subTest(path=row["path"], line=row["line"]):
                self.assertEqual(row["commit"], MAIN_MERGE_COMMIT)
                self.assertEqual(row["rule"], "generic-api-key")
                line = (ROOT / row["path"]).read_text().splitlines()[row["line"] - 1]
                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), row["source_line_sha256"])
                suffix = f"{row['path']}:{row['rule']}:{row['line']}"
                self.assertNotIn(suffix, entries)
                self.assertNotIn("0" * 40 + ":" + suffix, entries)
                unlisted_line = max(r["line"] for r in MAIN_MERGE_RECORDS if r["path"] == row["path"]) + 1
                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row['path']}:{row['rule']}:{unlisted_line}", entries)
                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row['path']}:other-rule:{row['line']}", entries)
        self.assertFalse(any(entry.startswith("6757dfac63086ac80bc849df587895bcaaa820df:") for entry in entries))

    def test_file_digest_findings_recompute_from_exact_native_source_bytes(self):
        raw = (ROOT / FILE_DIGEST_PATH).read_text()
        contract = json.loads(raw)
        for number, section, key, source, line_digest in FILE_DIGEST_RECORDS:
            with self.subTest(line=number):
                line = raw.splitlines()[number - 1]
                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), line_digest)
                expected = hashlib.sha256((ROOT / source).read_bytes()).hexdigest()
                self.assertEqual(contract[section][key], expected)
                # Bind the actual finding line to the reviewed JSON field, not just a matching value elsewhere.
                self.assertEqual(json.loads("{" + line.strip().rstrip(",") + "}"), {key: expected})

    def test_file_digest_exceptions_cannot_ignore_new_commits_paths_rules_or_lines(self):
        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        self.assertEqual({entry for entry in entries if FILE_DIGEST_PATH in entry}, FILE_DIGEST_FINDINGS)
        self.assertEqual({entry for entry in entries if entry.startswith(FILE_DIGEST_COMMIT + ":")}, FILE_DIGEST_FINDINGS)
        for finding in FILE_DIGEST_FINDINGS:
            self.assertEqual(entries.count(finding), 1)
            commit, path, rule, line = finding.split(":")
            for other in (f"{path}:{rule}:{line}",
                          f"{'0' * 40}:{path}:{rule}:{line}",
                          f"{commit}:tools/other.json:{rule}:{line}",
                          f"{commit}:{path}:other-rule:{line}",
                          f"{commit}:{path}:{rule}:{int(line) - 1}",
                          f"{commit}:{path}:{rule}:{int(line) + 1}"):
                with self.subTest(other=other):
                    self.assertNotIn(other, entries)
        self.assertFalse((ROOT / ".gitleaks.toml").exists())

    def test_new_prose_exception_is_exact_and_new_text_is_not_ignored(self):
        commit, path, rule, line = COVERAGE_PROSE_FINDING.split(":")
        self.assertEqual(commit, "bcd754bd41dd41b3dad22a436211cd89ee47b657")
        self.assertEqual(path, "docs/public-template/composition-read-grant.md")
        self.assertEqual((rule, line), ("generic-api-key", "75"))
        entries = (ROOT / ".gitleaksignore").read_text().splitlines()
        self.assertNotIn(f"{path}:{rule}:{line}", entries)
        self.assertNotIn(f"{'0' * 40}:{path}:{rule}:{line}", entries)
        self.assertIn("viewers, absent grants", (ROOT / path).read_text())

    def test_ci132_prose_exception_cannot_ignore_other_commits_paths_rules_or_lines(self):
        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        commit, path, rule, line = CI132_PROSE_FINDING.split(":")
        self.assertEqual(commit, "c95737b4c54881a7492ca72bd31f68749304d1d1")
        self.assertEqual(path, "docs/square-post-local-media.md")
        self.assertEqual((rule, line), ("generic-api-key", "31"))
        self.assertEqual([entry for entry in entries if path in entry], [CI132_PROSE_FINDING])
        for other in (f"{path}:{rule}:{line}",
                      f"{'0' * 40}:{path}:{rule}:{line}",
                      f"{commit}:docs/other.md:{rule}:{line}",
                      f"{commit}:{path}:other-rule:{line}",
                      f"{commit}:{path}:{rule}:30",
                      f"{commit}:{path}:{rule}:32"):
            with self.subTest(other=other):
                self.assertNotIn(other, entries)
        for entry in entries:
            self.assertRegex(entry, r"^[0-9a-f]{40}:[^:*?\[\]]+:generic-api-key:[1-9][0-9]*$")
        current_line = (ROOT / path).read_text().splitlines()[int(line) - 1]
        self.assertIn("Backend ownership checks and moderation remain prerequisites.", current_line)
        self.assertIn("Readback must remain authenticated.", current_line)
        self.assertIn("Expired or revoked approvals and interrupted uploads require explicit recovery handling.", current_line)

    def test_coupon_fixture_exceptions_are_exact_historical_findings_only(self):
        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        self.assertEqual({entry for entry in entries if "CouponRuntimeFixture" in entry}, COUPON_FIXTURE_FINDINGS)
        for finding in COUPON_FIXTURE_FINDINGS:
            self.assertEqual(entries.count(finding), 1)
            commit, path, rule, line = finding.split(":")
            self.assertEqual(commit, "abe535809517ceb327223679f85c14b5f5b8b6d7")
            self.assertEqual(path, "App/CouponRuntimeFixture.swift")
            self.assertEqual(rule, "generic-api-key")
            self.assertNotIn(f"{path}:{rule}:{line}", entries)
            self.assertNotIn(f"{'0' * 40}:{path}:{rule}:{line}", entries)
        fixture = (ROOT / "App/CouponRuntimeFixture.swift").read_text()
        self.assertTrue(fixture.startswith("#if DEBUG"))
        self.assertEqual(fixture.count('"test-7"'), 3)
        self.assertIn('https://coupon-runtime.example/native', fixture)
        self.assertIn('makeTransport: { self }', fixture)
        self.assertNotIn('URLSession', fixture)
        self.assertFalse((ROOT / ".gitleaks.toml").exists())

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
