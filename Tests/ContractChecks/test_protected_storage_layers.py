import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


def method_body(text, name):
    start = text.index('    func ' + name + '(')
    cursor = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[cursor] == '{') - (text[cursor] == '}')
        cursor += 1
    return text[start:cursor] + '\n'


class ProtectedStorageLayerTests(unittest.TestCase):
    def test_eight_device_methods_preserve_exact_reviewed_bodies(self):
        inventory = json.loads((ROOT / 'tools/protected_storage_device_inventory.json').read_text())
        self.assertEqual(len(inventory['tests']), 8)
        self.assertEqual(len({x['method'] for x in inventory['tests']}), 8)
        for item in inventory['tests']:
            device = (ROOT / f"Tests/AppUnitTests/{item['class']}.swift").read_text()
            simulator = (ROOT / f"Tests/AppUnitTests/{item['original_class']}.swift").read_text()
            self.assertIn('#if os(iOS) && !targetEnvironment(simulator)', device)
            body = method_body(device, item['method'])
            self.assertEqual(hashlib.sha256(body.encode()).hexdigest(), item['body_sha256'])
            self.assertNotIn('func ' + item['method'] + '(', simulator)
            self.assertEqual(item['status'], 'NOT_RUN_DEVICE_REQUIRED')
            self.assertNotIn('XCTSkip', device)
            self.assertIn(item['class'] + '.swift', (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text())

    def test_simulator_retains_real_checks_and_exact_non_a_rejections(self):
        content = (ROOT / 'Tests/AppUnitTests/ContentDraftSystemStorageTests.swift').read_text()
        play = (ROOT / 'Tests/AppUnitTests/PlayRecoverySystemStorageTests.swift').read_text()
        for name in ['testRealGenerationCASAndConditionalDelete',
                     'testRealSymlinkAncestorIsRejectedWithoutTouchingTarget',
                     'testRealWeakExistingDirectoryIsRejectedWithoutPermissionRepair']:
            self.assertIn('func ' + name, content)
        self.assertIn('testFactoryRejectsMismatchedNamespaceAndRegionBeforeOSConstruction', play)
        self.assertIn('error as? ContentDraftIssue, .storageUnavailable', content)
        self.assertIn('error as? PlayExperienceError, .persistenceUnavailable', play)
        for method in ['insert', 'createPresence', 'hasPresence', 'readDurably', 'removeDurably']:
            self.assertIn('store.' + method, content)
        self.assertIn('SecItemCopyMatching(query as CFDictionary, nil), errSecItemNotFound', play)
        self.assertGreaterEqual(play.count('try assertNoWrites()'), 4)
        fixture = content.split('@MainActor enum NonClassAStorageFixture', 1)[1]
        for token in ['guard protection == 3', 'F_SETPROTECTIONCLASS, Int32(3)',
                      'info.st_uid == geteuid()', 'info.st_mode & 0o777 == 0o700',
                      'contents.isEmpty', 'mkdirat(parent, leaf', 'O_NOFOLLOW', 'throw FixtureFailure.prerequisite']:
            self.assertIn(token, fixture)
        self.assertNotIn('XCTSkip', fixture)
        production = (ROOT / 'Core/ContentDraftSystemStorage.swift').read_text()
        self.assertIn('completeProtectionClass: Int32 = 1', production)
        self.assertIn('F_GETPROTECTIONCLASS) == Self.completeProtectionClass', production)
        self.assertNotIn('targetEnvironment(simulator)', production)

    def test_non_a_fixture_callback_and_local_helper_declare_actor_boundaries(self):
        content = (ROOT / 'Tests/AppUnitTests/ContentDraftSystemStorageTests.swift').read_text()
        play = (ROOT / 'Tests/AppUnitTests/PlayRecoverySystemStorageTests.swift').read_text()
        self.assertIn('withDirectory(_ body: @MainActor (URL) async throws -> Void)', content)
        self.assertIn('@MainActor func assertNoWrites() throws', play)
        self.assertIn('try await NonClassAStorageFixture.assertUnchanged(root)', content)

    def test_compile_and_runtime_status_are_independent_for_every_outcome(self):
        spec = importlib.util.spec_from_file_location('storage_coverage', ROOT / 'tools/report_protected_storage_coverage.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for outcome, expected in [('success', 'COMPILED_UNSIGNED_NOT_EXECUTED'), ('failure', 'COMPILE_FAILED'),
                                  ('cancelled', 'COMPILE_CANCELLED'), ('skipped', 'COMPILE_NOT_RUN')]:
            result = module.report(outcome, 'synthetic-commit')
            self.assertEqual(result['device_compile'], expected)
            self.assertEqual(result['device_execution'], 'NOT_RUN_DEVICE_REQUIRED')
            self.assertEqual(result['device_lock_enforcement'], 'NOT_RUN_DEVICE_REQUIRED')
            self.assertEqual(len(result['tests']), 8)
            self.assertTrue(all(x['status'] == 'NOT_RUN_DEVICE_REQUIRED' for x in result['tests']))
        with tempfile.TemporaryDirectory() as tmp:
            output, summary = Path(tmp) / 'report.json', Path(tmp) / 'summary.md'
            subprocess.run(['python3', str(ROOT / 'tools/report_protected_storage_coverage.py'),
                            '--compile-outcome', 'failure', '--commit', 'synthetic-commit',
                            '--output', str(output), '--summary', str(summary)], check=True, capture_output=True)
            self.assertEqual(json.loads(output.read_text())['device_compile'], 'COMPILE_FAILED')
            self.assertEqual(summary.read_text().count('- QuestifyAppUnitTests/'), 8)

    def test_ci_compiles_device_tests_and_reports_without_claiming_execution(self):
        workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        device = workflow.split('  device-build:')[1].split('  us-build:')[0]
        for token in ['-scheme QuestifyAppUnitTests', '-sdk iphoneos', "generic/platform=iOS",
                      'CODE_SIGNING_ALLOWED=NO build-for-testing', 'if: always()',
                      'steps.protected_storage_device_compile.outcome', 'report_protected_storage_coverage.py',
                      'protected-storage-coverage-${{ github.sha }}']:
            self.assertIn(token, device)
        self.assertNotIn('test-without-building', device)
        self.assertNotIn('continue-on-error', device)
        self.assertNotIn('-skip-testing', workflow)


if __name__ == '__main__':
    unittest.main()
