"""Public raw-source read-failure admission; no Swift/backend execution implied."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]

def load(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

raw = load('tools/check_profile_read_failure_contract.py', 'profile_read_failure_raw')
# Ordinary unittest discovery must execute the unchanged thirteen raw cases.
ProfileReadFailureContracts = raw.ProfileReadFailureContracts

def digest(value):
    return hashlib.sha256(value).hexdigest()


ORIGINAL_READINESS_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'
READINESS_PATH = 'tools/run138_editor_readiness_contract.json'
SCANNER_PATH = 'tools/tests/test_gitleaks_configuration.py'

def historical_readiness_contract(data, root=ROOT):
    """Historical line reader only; the current central gate still rejects old bytes."""
    if digest(data) == ORIGINAL_READINESS_SHA256:
        return data
    runner = (Path(root)/'tools/run138_editor_readiness.py').read_bytes()
    pins = re.findall(rb"^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner, re.MULTILINE)
    if len(pins) != 1 or digest(data) != pins[0].decode('ascii'):
        raise ValueError('Unknown complete current readiness contract')
    contract = json.loads(data)
    row = contract['feature_batch_sources'][raw.CORE]
    if len(row['hunks']) != 9 or row['after_sha256'] != raw.CURRENT_COORDINATOR_SHA256:
        raise ValueError('Not the bounded read-error contract increment')
    value = (Path(root)/raw.CORE).read_text()
    for hunk in reversed(row['hunks'][5:]):
        if value.count(hunk['after']) != 1:
            raise ValueError('Missing or repeated read-error inverse span')
        value = value.replace(hunk['after'], hunk['before'], 1)
    if digest(value.encode()) != raw.OLD_COORDINATOR_SHA256:
        raise ValueError('Original profile source not restored')
    row['after_sha256'] = raw.OLD_COORDINATOR_SHA256
    row['hunks'] = row['hunks'][:5]
    support = contract['feature_batch_support_sha256']
    support['Tests/ContractChecks/test_profile_avatar.py'] = '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0'
    support['Tests/ContractChecks/test_profile_reload_discard.py'] = '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'
    for path in ['tools/check_profile_read_failure_contract.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', raw.TESTS, SCANNER_PATH]:
        del support[path]
    original = (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()
    if digest(original) != ORIGINAL_READINESS_SHA256:
        raise ValueError('Complete original readiness contract not restored')
    return original

class ProfileReadFailureRemoteAdmission(unittest.TestCase):
    def test_public_discovery_includes_all_thirteen_raw_checks(self):
        self.assertEqual(unittest.defaultTestLoader.loadTestsFromTestCase(ProfileReadFailureContracts).countTestCases(), 13)
        self.assertEqual(raw.ROOT, ROOT)
        self.assertEqual(digest((ROOT/'tools/check_profile_read_failure_contract.py').read_bytes()),
                         'e492facdded0e76615721d90081b912738ba490e503aab61a7ed549a6b2a4b8a')

    def test_historical_readers_preserve_original_complete_bytes(self):
        for relative, end, replacements, expected in [
            ('Tests/ContractChecks/test_profile_reload_discard.py', "VIEW=ROOT/", [
                ('sha(historical_profile_input(path, (ROOT/path).read_bytes()))', 'sha((ROOT/path).read_bytes())')],
             '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'),
            ('Tests/ContractChecks/test_profile_avatar.py', 'PROTECTED = ', [
                ('value=historical_profile_input(path, (ROOT/path).read_bytes())', 'value=(ROOT/path).read_bytes()'),
                ('hashlib.sha256(historical_protected_input(path, (ROOT/path).read_bytes())).hexdigest()', 'hashlib.sha256((ROOT/path).read_bytes()).hexdigest()')],
             '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0')]:
            source = (ROOT/relative).read_text()
            start = source.index('ROOT=Path(__file__).resolve().parents[2]\n') + len('ROOT=Path(__file__).resolve().parents[2]\n')
            stop = source.index(end, start)
            self.assertTrue(source[start:stop].startswith('\n# Read-error admission'))
            source = source[:start] + source[stop:]
            for after, before in replacements:
                self.assertEqual(source.count(after), 1)
                source = source.replace(after, before, 1)
            self.assertEqual(digest(source.encode()), expected, relative)

    def test_nested_reload_pin_is_restored_independently_of_earlier_failures(self):
        avatar = load('Tests/ContractChecks/test_profile_avatar.py', 'profile_avatar_admission')
        relative = 'Tests/ContractChecks/test_profile_reload_discard.py'
        current = (ROOT/relative).read_bytes()
        restored = avatar.historical_protected_input(relative, current)
        self.assertEqual(digest(restored), '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25')
        self.assertEqual(digest(restored), avatar.PROTECTED[relative])
        self.assertEqual(avatar.historical_reload_checker(restored), restored)
        for mutant in [current+b' ', current.replace(b'historical_profile_input(path, (ROOT/path).read_bytes())', b'(ROOT/path).read_bytes()', 1), current.replace(b'\n', b'\r\n')]:
            with self.assertRaises(ValueError):
                avatar.historical_reload_checker(mutant)

    def test_each_changed_protected_input_recovers_exact_original_bytes(self):
        avatar = load('Tests/ContractChecks/test_profile_avatar.py', 'avatar_frozen_inputs')
        for relative in ['Tests/CoreTests/ProfileEditTests.swift', 'Tests/ContractChecks/test_profile_reload_discard.py']:
            current = (ROOT/relative).read_bytes()
            restored = avatar.historical_protected_input(relative, current)
            self.assertEqual(digest(restored), avatar.PROTECTED[relative], relative)
            self.assertEqual(avatar.historical_protected_input(relative, restored), restored)
            for mutant in [current+b' ', b'\xef\xbb\xbf'+current, current.replace(b'\n', b'\r\n'), current+b'\xff']:
                with self.subTest(path=relative), self.assertRaises(ValueError):
                    avatar.historical_protected_input(relative, mutant)
        current = (ROOT/raw.TESTS).read_bytes()
        marker = avatar.CORE_TESTS_APPEND_MARKER
        original, suffix = current.split(marker, 1)
        for mutant in [current+marker, original+marker+suffix+b' ', original+b' '+marker+suffix, original+b'\n']:
            with self.assertRaises(ValueError):
                avatar.historical_core_tests(mutant)
        self.assertEqual(digest(original), raw.OLD_CORE_TESTS_SHA256)

    def test_historical_coordinator_boundaries_remain_narrow(self):
        data = (ROOT/raw.CORE).read_bytes()
        old = raw.validated_original_coordinator(data)
        for relative in ['Tests/ContractChecks/test_profile_avatar.py', 'Tests/ContractChecks/test_profile_reload_discard.py']:
            reader = load(relative, 'reader_'+Path(relative).stem)
            self.assertEqual(reader.historical_profile_input(raw.CORE, data), old)
            self.assertEqual(reader.historical_profile_input(raw.CORE, old), old)
            self.assertEqual(reader.historical_profile_input('unrelated', data), data)
            for name, mutant in raw.coordinator_byte_mutations(data):
                with self.subTest(reader=relative, mutation=name), self.assertRaises(ValueError):
                    reader.historical_profile_input(raw.CORE, mutant)

    def test_original_contract_floor_hunks_pins_and_algorithm_are_frozen(self):
        contract = json.loads((ROOT/'tools/run138_editor_readiness_contract.json').read_bytes())
        row = contract['feature_batch_sources'][raw.CORE]
        self.assertEqual(row['before_sha256'], 'c08da5dead9c78d7256fecf8853f4a9a4122a5cf3ad5cca4dec3cbce7a03982f')
        self.assertEqual(row['after_sha256'], raw.CURRENT_COORDINATOR_SHA256)
        self.assertEqual(len(row['hunks']), 9)
        value = (ROOT/raw.CORE).read_text()
        for hunk in reversed(row['hunks'][5:]):
            self.assertEqual(value.count(hunk['after']), 1)
            value = value.replace(hunk['after'], hunk['before'], 1)
        self.assertEqual(digest(value.encode()), raw.OLD_COORDINATOR_SHA256)
        # Recover the complete old contract, not a selected set of assertions.
        row['after_sha256'] = raw.OLD_COORDINATOR_SHA256
        row['hunks'] = row['hunks'][:5]
        support = contract['feature_batch_support_sha256']
        support['Tests/ContractChecks/test_profile_avatar.py'] = '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0'
        support['Tests/ContractChecks/test_profile_reload_discard.py'] = '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'
        for path in ['tools/check_profile_read_failure_contract.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', raw.TESTS, SCANNER_PATH]:
            del support[path]
        self.assertEqual(digest((json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()), '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6')
        self.assertEqual(digest((ROOT/'tools/run138_current_source_projection.py').read_bytes()), 'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727')
        source = (ROOT/'tools/run138_editor_readiness.py').read_text()
        current = digest((ROOT/'tools/run138_editor_readiness_contract.json').read_bytes())
        self.assertEqual(source.count("CONTRACT_SHA256 = '"+current+"'"), 1)
        original = source.replace("CONTRACT_SHA256 = '"+current+"'", "CONTRACT_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'", 1)
        self.assertEqual(digest(original.encode()), 'cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f')

    def test_scanner_reader_inverse_recovers_complete_original_checker(self):
        source = (ROOT/SCANNER_PATH).read_text()
        for before, after in reversed(SCANNER_READER_HUNKS):
            self.assertEqual(source.count(after), 1)
            source = source.replace(after, before, 1)
        self.assertEqual(digest(source.encode()), 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')
        self.assertEqual(len(re.findall(r'^    def test_', source, re.MULTILINE)), 9)

    def test_scanner_contract_reader_restores_old_lines_and_rejects_drift(self):
        current = (ROOT/READINESS_PATH).read_bytes()
        old = historical_readiness_contract(current)
        self.assertEqual(digest(old), ORIGINAL_READINESS_SHA256)
        self.assertEqual(historical_readiness_contract(old), old)
        self.assertEqual(digest(old.decode().splitlines()[4027].encode()),
                         'a808e190bda202c021e4cbada812e684d92e4e7ac6848d2016c944c3d3d494e4')
        for mutant in [current+b' ', b'\xef\xbb\xbf'+current, current+b'\xff',
                       current.replace(b'\n', b'\r\n'), current.replace(b'"hunks": [', b'"hunks": [ ', 1),
                       old+b'\n', b'{}\n']:
            with self.assertRaises(ValueError):
                historical_readiness_contract(mutant)
        # Old bytes remain historical-only; the real current contract gate rejects them.
        sys.path.insert(0, str(ROOT/'tools'))
        try:
            import run138_editor_readiness as planning
            self.assertNotEqual(digest(old), planning.CONTRACT_SHA256)
            self.assertEqual(digest(current), planning.CONTRACT_SHA256)
        finally:
            sys.path.pop(0)

    def test_actual_central_validators_and_current_rejection(self):
        sys.path.insert(0, str(ROOT/'tools'))
        try:
            import run138_current_source_projection as projection
            import run138_editor_readiness as planning
            projection.validate_feature_batch_sources(ROOT)
            projection.validate_entries(ROOT)
            data = (ROOT/raw.CORE).read_bytes()
            restored = projection.original_feature_batch_bytes(raw.CORE, data, ROOT)
            self.assertEqual(digest(restored), 'c08da5dead9c78d7256fecf8853f4a9a4122a5cf3ad5cca4dec3cbce7a03982f')
            for mutant in [raw.validated_original_coordinator(data), *[m for _, m in raw.coordinator_byte_mutations(data)]]:
                with self.assertRaises(ValueError):
                    projection.original_feature_batch_bytes(raw.CORE, mutant, ROOT)
            required = planning.required_followon_files(ROOT)
            self.assertTrue({'tools/check_profile_read_failure_contract.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', raw.TESTS} <= required)
        finally:
            sys.path.pop(0)

SCANNER_READER_HUNKS = [('ROOT = Path(__file__).resolve().parents[2]\n', "ROOT = Path(__file__).resolve().parents[2]\n\n# This adapter restores only the original line-bound historical contract input.\nimport importlib.util\n_profile_spec = importlib.util.spec_from_file_location(\n    'profile_read_failure_remote_admission',\n    ROOT / 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py')\n_profile_admission = importlib.util.module_from_spec(_profile_spec)\n_profile_spec.loader.exec_module(_profile_admission)\n"), ('raw = (ROOT / FILE_DIGEST_PATH).read_text()', "raw = _profile_admission.historical_readiness_contract(\n            (ROOT / FILE_DIGEST_PATH).read_bytes(), ROOT).decode('utf-8')")]

if __name__ == '__main__':
    unittest.main()
