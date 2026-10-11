"""Public, source-only checks for the independently ported P044 directory boundary."""
import ast
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest

from tools import club_customer_directory_admission as admission
from tools import run138_editor_readiness as readiness

ROOT = Path(__file__).resolve().parents[2]
INPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {
    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}
COMBINED_INPUTS = INPUTS | set(admission.EVOLUTION_SOURCES) | set(admission.EVOLUTION_SUPPORT) | set(admission.FLOOR_INPUTS)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


@contextmanager
def copied_admission_inputs():
    """Only bounded club and preceding admission inputs, never a repository checkout."""
    with tempfile.TemporaryDirectory(prefix='club-directory-admission-') as temporary:
        root = Path(temporary)
        for relative in sorted(COMBINED_INPUTS):
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())
        yield root


class ClubCustomerDirectoryRemoteAdmissionTests(unittest.TestCase):
    def test_three_product_sources_restore_exact_published_baseline_and_reject_edits(self):
        self.assertEqual(len(admission.SOURCE_EDITS), 4)
        for relative, row in admission.SOURCE_EDITS.items():
            raw = admission.permission_product_bytes(ROOT, relative)
            restored = admission.restore_product_source(relative, raw)
            self.assertEqual(digest(restored), row['before_sha256'])
            self.assertEqual(digest(raw), row['after_sha256'])
            for value in (raw + b'\n', bytes([raw[0] ^ 1]) + raw[1:], restored):
                with self.subTest(path=relative), self.assertRaises(ValueError):
                    admission.restore_product_source(relative, value)

    def test_pbx_package_and_spm_discovery_are_exactly_unchanged(self):
        for relative, expected in {
            'Questify.xcodeproj/project.pbxproj': 'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552',
            'Package.swift': '89fefe8ae302c55a9b8853a792f2426d6331eeaa2c1c1b905a77ef6efeac5e2d',
        }.items():
            self.assertEqual(digest(admission.permission_boundary_bytes(ROOT, relative)), expected)
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        for relative in ['Core/ClubGovernanceContracts.swift', 'Core/ClubCustomerHistoryTopicRoute.swift']:
            self.assertEqual(project.count('"path" = "' + relative + '";'), 1)
        self.assertIn('path: "Tests/CoreTests"', (ROOT / 'Package.swift').read_text())
        swift = (ROOT / 'Tests/CoreTests/ClubCustomerPermissionTests.swift').read_text()
        self.assertEqual(swift.count('    func test'), 7)
        self.assertNotIn('ClubCustomerListQuery', swift)
        self.assertIn('case .customerCount: expected = ["clubId": .integer(81)]', swift)
        self.assertIn('case .customer: expected = ["clubId": .integer(81), "memberId": .integer(704)]', swift)

    def test_whole_contract_is_exact_baseline_with_only_new_admission_rows(self):
        restored = admission.historical_scan_contract(ROOT).encode()
        self.assertEqual(digest(restored), admission.BASE_CONTRACT_SHA256)
        old, new = json.loads(restored), json.loads(admission.frozen_permission_contract(ROOT))
        self.assertEqual(len(old['feature_batch_sources']), 122)
        self.assertEqual(len(old['feature_batch_support_sha256']), 498)
        self.assertEqual(set(new['feature_batch_sources']) - set(old['feature_batch_sources']), set(admission.SOURCE_EDITS))
        self.assertEqual(set(new['feature_batch_support_sha256']) - set(old['feature_batch_support_sha256']), set(admission.ADDED_SUPPORT))
        self.assertEqual(len(INPUTS), 11)
        for key, value in old.items():
            if key not in ('feature_batch_sources', 'feature_batch_support_sha256'):
                self.assertEqual(new[key], value)
        for field in ('feature_batch_sources', 'feature_batch_support_sha256'):
            self.assertEqual({key: new[field][key] for key in old[field]}, old[field])

    def test_original_scanner_methods_assertions_and_historical_lines_are_preserved(self):
        path = 'tools/tests/test_gitleaks_configuration.py'
        raw = admission.permission_product_bytes(ROOT, path)
        previous = admission.restore_product_source(path, raw)
        self.assertEqual(digest(previous), 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')
        old_tree, new_tree = ast.parse(previous), ast.parse(raw)
        old_tests = [n for n in ast.walk(old_tree) if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')]
        new_tests = [n for n in ast.walk(new_tree) if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')]
        self.assertEqual(len(old_tests), 9)
        self.assertEqual([n.name for n in new_tests], [n.name for n in old_tests])
        for old, new in zip(old_tests, new_tests):
            old_assertions = [ast.dump(n) for n in ast.walk(old) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr.startswith('assert')]
            new_assertions = [ast.dump(n) for n in ast.walk(new) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr.startswith('assert')]
            self.assertEqual(new_assertions, old_assertions)
        baseline = admission.historical_scan_contract(ROOT).splitlines()
        current = (ROOT / admission.CONTRACT_PATH).read_text().splitlines()
        self.assertNotEqual(current[4027], baseline[4027])
        self.assertIn('test_merchant_business_access_lifetime.py', baseline[4027])
        self.assertIn('(4028, "feature_batch_support_sha256"', raw.decode())

    def test_no_change_to_write_selector_or_non_directory_reads(self):
        contracts = (ROOT / 'Core/ClubGovernanceContracts.swift').read_text()
        self.assertIn('case .checkin, .topicCustomers, .registrations: return "club:member:list:read"', contracts)
        self.assertNotIn('CHECKIN_RECEIPT', contracts)
        self.assertNotIn('TOPIC_CUSTOMERS', contracts)
        for path, expected in {
            'Core/ClubGovernanceCommands.swift': '5b7a7d842991aa199583185fa94f47274b9208de1833388c98a8eee11fda2f6c',
            'Core/ClubGovernanceService.swift': '0f9f4b680ee6b3127f9b1adc590705552a56c4d73c2850f5acac5f9e80844f59',
            'App/ClubGovernanceViews.swift': 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a',
            'App/ClubGovernanceCommandForm.swift': '28dcfc08ed90e072e51c7a28202a9af925907c9edbe8a296cf5092678f32174f',
            '.gitleaksignore': 'e6643cd2a90f794cf60c3f635243897b6fefb5adac156493eb2039e590ee09a0',
        }.items():
            self.assertEqual(digest(admission.permission_boundary_bytes(ROOT, path)), expected)

    def test_all_eleven_physical_inputs_reject_same_size_mtime_crlf_and_cr_edits(self):
        with copied_admission_inputs() as root:
            admission.historical_scan_contract(root)  # Warm call cannot authorize later bytes.
            for relative in sorted(COMBINED_INPUTS):
                file = root / relative
                saved, metadata = file.read_bytes(), file.stat()
                for name, value in [('same-size-mtime', bytes([saved[0] ^ 1]) + saved[1:]),
                                    ('crlf', saved.replace(b'\n', b'\r\n')),
                                    ('cr', saved.replace(b'\n', b'\r'))]:
                    with self.subTest(path=relative, mode=name):
                        file.write_bytes(value)
                        os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                        if name == 'same-size-mtime':
                            self.assertEqual(file.stat().st_size, metadata.st_size)
                            self.assertEqual(file.stat().st_mtime_ns, metadata.st_mtime_ns)
                        with self.assertRaises((ValueError, UnicodeError, json.JSONDecodeError)):
                            admission.historical_scan_contract(root)
                        file.write_bytes(saved)
            self.assertEqual(digest(admission.historical_scan_contract(root).encode()), admission.BASE_CONTRACT_SHA256)

    def test_missing_support_and_equivalent_json_are_rejected(self):
        with copied_admission_inputs() as root:
            for relative in admission.ADDED_SUPPORT + admission.EVOLUTION_SUPPORT:
                file = root / relative
                saved = file.read_bytes()
                file.unlink()
                with self.subTest(path=relative), self.assertRaises((ValueError, FileNotFoundError)):
                    admission.historical_scan_contract(root)
                file.write_bytes(saved)
            file = root / admission.CONTRACT_PATH
            original = file.read_bytes()
            file.write_text(json.dumps(json.loads(original), sort_keys=True))
            with self.assertRaises(ValueError):
                admission.historical_scan_contract(root)

    def test_original_baseline_domain_and_mixed_states(self):
        with copied_admission_inputs() as root:
            baseline = admission.historical_scan_contract(root)
            (root / admission.CONTRACT_PATH).write_text(baseline)
            with self.assertRaisesRegex(ValueError, 'Hybrid baseline'):
                admission.historical_scan_contract(root)
            for relative in admission.SOURCE_EDITS:
                file = root / relative
                file.write_bytes(admission.restore_product_source(relative, file.read_bytes()))
            with self.assertRaisesRegex(ValueError, 'Hybrid baseline and current readiness reader'):
                admission.historical_scan_contract(root)
            reader = root / 'tools/run138_editor_readiness.py'
            from Tests.ContractChecks.test_category_roam_registration import uncached_readiness_source
            reader.write_bytes(uncached_readiness_source(reader.read_bytes()).replace(readiness.CONTRACT_SHA256.encode(), admission.BASE_CONTRACT_SHA256.encode()))
            self.assertEqual(digest(reader.read_bytes()), admission.BASE_READINESS_SHA256)
            with self.assertRaisesRegex(ValueError, 'Baseline domain contains new support'):
                admission.historical_scan_contract(root)
            for relative in admission.ADDED_SUPPORT:
                (root / relative).unlink()
            for relative in admission.EVOLUTION_SOURCES:
                file = root / relative
                file.write_bytes(admission.restore_evolution_source(relative, file.read_bytes()))
            for relative in admission.EVOLUTION_SUPPORT:
                (root / relative).unlink()
            (root / admission.CLUB_PREADMISSION_PATH).unlink()
            self.assertEqual(admission.historical_scan_contract(root), baseline)
            (root / admission.CONTRACT_PATH).write_bytes((ROOT / admission.CONTRACT_PATH).read_bytes())
            with self.assertRaises(ValueError):
                admission.historical_scan_contract(root)

    def test_contract_and_reader_forgery_cannot_repin_an_unreviewed_input(self):
        with copied_admission_inputs() as root:
            relative = 'docs/club-customer-permissions.md'
            file = root / relative
            file.write_bytes(file.read_bytes() + b'Unreviewed text\n')
            contract_file = root / admission.CONTRACT_PATH
            prior = contract_file.read_bytes()
            value = json.loads(prior)
            value['feature_batch_support_sha256'][relative] = digest(file.read_bytes())
            updated = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
            contract_file.write_bytes(updated)
            reader_file = root / 'tools/run138_editor_readiness.py'
            reader_file.write_bytes(reader_file.read_bytes().replace(digest(prior).encode(), digest(updated).encode()))
            with self.assertRaisesRegex(ValueError, 'reader changed'):
                admission.historical_scan_contract(root)


if __name__ == '__main__':
    unittest.main()
