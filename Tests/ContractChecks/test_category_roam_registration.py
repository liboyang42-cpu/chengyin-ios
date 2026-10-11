"""Current-group registration and exact historical category read-in contracts."""
from pathlib import Path
import ast, copy, hashlib, json, re, tempfile, unittest
from unittest.mock import patch
from Tests.ContractChecks.test_roam_route_replay import SOURCE_INVERSES as ROAM_SOURCE_INVERSES

ROOT = Path(__file__).resolve().parents[2]
SELF_PATH = 'Tests/ContractChecks/test_category_roam_registration.py'
CONTRACT_PATH = 'tools/run138_editor_readiness_contract.json'
RUNNER_PATH = 'tools/run138_editor_readiness.py'
CATEGORY_GATE = 'Tests/ContractChecks/test_global_search_category_recovery.py'
CATALOG_PATH = 'Resources/Localizable.xcstrings'
HISTORY_PATH = 'App/RoamHistoryViews.swift'
BASE_CONTRACT_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'
BASE_RUNNER_SHA256 = 'cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f'
CATEGORY_CONTRACT_SHA256 = '71104bcb92917bc7c5b65de316ce35861a1e1343f6133d6665aa6380153a91b6'
CATEGORY_CONTRACT_BYTES = 1331787
CATEGORY_RUNNER_SHA256 = 'f495215ea73dbf60f77c18d70ed6d40ec83dcd4c42fa32cddef46c610a779e01'
ORIGINAL_CATEGORY_GATE_SHA256 = '601d09dcf08c00f1de69a9d8cff4a69ba72925733840ec6020110e210a6060a5'
ADAPTED_CATEGORY_GATE_SHA256 = '1a5fde2e4d839d72af0ae89380aabe0ed8af83e7f3f8199d55d020d1ceb01455'
CATEGORY_GATE_DELTAS = [(398, b"import hashlib\nfrom pathlib import Path\nimport unittest\nfrom Tests.ContractChecks.test_category_roam_registration import pre_roam_category_inputs, pre_roam_category_contract_bytes\n\nROOT = Path(__file__).resolve().parents[2]\nVIEW_SHA256 = '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78'\n", b"import hashlib\nfrom pathlib import Path\nimport unittest\n\nROOT = Path(__file__).resolve().parents[2]\nVIEW_SHA256 = '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78'\n"), (48864, b'\n\ndef historical_category_contract_bytes(raw, *, root=ROOT):\n    raw, root = pre_roam_category_inputs(raw, root=root)\n    import json\n    import re\n    root = Path(root)\n', b'\n\ndef historical_category_contract_bytes(raw, *, root=ROOT):\n    import json\n    import re\n    root = Path(root)\n'), (59368, b"        raw = (ROOT / CONTRACT_PATH).read_bytes()\n        prior = historical_category_contract_bytes(raw)\n        self.assertEqual(hashlib.sha256(prior).hexdigest(), BASE_CONTRACT_SHA256)\n        old = json.loads(prior); current = json.loads(pre_roam_category_contract_bytes(raw, root=ROOT))\n        for path, row in SOURCE_INVERSES.items():\n            self.assertEqual(current['feature_batch_sources'][path]['before_sha256'], old['feature_batch_sources'][path]['before_sha256'])\n        self.assertEqual(set(current['feature_batch_sources']), set(old['feature_batch_sources']))\n        from Tests.ContractChecks.test_category_roam_registration import category_scanner_bytes\n        scanner = category_scanner_bytes((ROOT / 'tools/tests/test_gitleaks_configuration.py').read_bytes(), root=ROOT)\n        restored = scanner.replace(b'from Tests.ContractChecks.test_global_search_category_recovery import historical_category_contract_bytes\\n', b'', 1)\n        restored = restored.replace(b'raw = historical_category_contract_bytes((ROOT / FILE_DIGEST_PATH).read_bytes(), root=ROOT).decode()', b'raw = (ROOT / FILE_DIGEST_PATH).read_text()', 1)\n        self.assertEqual(hashlib.sha256(restored).hexdigest(), 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')\n", b"        raw = (ROOT / CONTRACT_PATH).read_bytes()\n        prior = historical_category_contract_bytes(raw)\n        self.assertEqual(hashlib.sha256(prior).hexdigest(), BASE_CONTRACT_SHA256)\n        old = json.loads(prior); current = json.loads(raw)\n        for path, row in SOURCE_INVERSES.items():\n            self.assertEqual(current['feature_batch_sources'][path]['before_sha256'], old['feature_batch_sources'][path]['before_sha256'])\n        self.assertEqual(set(current['feature_batch_sources']), set(old['feature_batch_sources']))\n        scanner = (ROOT / 'tools/tests/test_gitleaks_configuration.py').read_bytes()\n        restored = scanner.replace(b'from Tests.ContractChecks.test_global_search_category_recovery import historical_category_contract_bytes\\n', b'', 1)\n        restored = restored.replace(b'raw = historical_category_contract_bytes((ROOT / FILE_DIGEST_PATH).read_bytes(), root=ROOT).decode()', b'raw = (ROOT / FILE_DIGEST_PATH).read_text()', 1)\n        self.assertEqual(hashlib.sha256(restored).hexdigest(), 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')\n")]
CATEGORY_HISTORY_ROW_SHA256 = '08c9d5a5a2c5a9ac467148353b627380a5f895be07f6e9cc560cfcb45705358a'
HISTORY_FLOOR = '1926c84b140127cb8f4c65aae81e7305dfb730b1f219459e4b05001baefe4751'
IGNORE_SHA256 = 'e6643cd2a90f794cf60c3f635243897b6fefb5adac156493eb2039e590ee09a0'
CATEGORY_SOURCES = ('App/GlobalSearchView.swift', 'Core/SearchMapReading.swift', 'App/SearchMapFilterSheet.swift')
CATEGORY_SUPPORT = ('Tests/ContractChecks/test_global_search_category_recovery.py', 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift', 'docs/global-search-category-recovery.md', 'tools/tests/test_gitleaks_configuration.py')
ROAM_SUPPORT = ('Tests/CoreTests/RoamRouteReplayTests.swift', 'Tests/ContractChecks/test_roam_route_replay.py', 'docs/roam-route-replay.md')
FROZEN_SHA256 = {'App/GlobalSearchView.swift': '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78', 'Core/SearchMapReading.swift': '34c67b5893b5ebba2eec8fdfc468a9b1662f4b94f86936d63d755385954d9aad', 'App/SearchMapFilterSheet.swift': 'd805599b752fcd104e40b382fb30d5bc96b9f8f27622766bfaefeed402c07b54', 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift': '4a78eca6ec1df117f1fd24675e775e7ffe4c6f1dc85f2e4988d223705092108e', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift': '4f7ed5b79dd4929b5eb828c53e1a07826e1a8b6ff78a09c0f55148faa24a4dad', 'docs/global-search-category-recovery.md': '886a26d9fa6bbe316551c53fb83d7cdfae754351693d9a671040f6a72c878dca', 'tools/tests/test_gitleaks_configuration.py': 'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30', 'App/RoamHistoryViews.swift': '2a4d67bbb003df0646599c911ae8c2ac6e20b99e2af7ae81f89be384af608172', 'App/RoamExperienceComponents.swift': '02188caf2ccd48dae34f6775828d2e722ce4f8239f9925af8d972d9148e772fb', 'Core/RoamExperienceMath.swift': '65f5ef1e0f0161c5875f6e962790e2690ef9de210da7cb75b7a72c3cda3b8a6b', 'Resources/Localizable.xcstrings': '901ba5a72ab2748c171483dff7743c63a30552ab9ded21b2c3379ae410f2a898', 'Tests/CoreTests/RoamRouteReplayTests.swift': 'bee4110b199342c675def44f367f9da180da699124b9cf5f9222e7ad06441e0a', 'Tests/ContractChecks/test_roam_route_replay.py': '83d0cb05ce9ec6289354c960494e6923b78a2825f6c244ec08b6693dfbe8c5c3', 'docs/roam-route-replay.md': '5c409db1da0daffd0a5143873e96310094c417941b7497e1b5536e02b57a4395'}
APPROVED_PATHS = ['App/GlobalSearchView.swift', 'Core/SearchMapReading.swift', 'App/SearchMapFilterSheet.swift', 'Tests/ContractChecks/test_global_search_category_recovery.py', 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift', 'docs/global-search-category-recovery.md', 'tools/run138_editor_readiness_contract.json', 'tools/run138_editor_readiness.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', 'App/RoamHistoryViews.swift', 'App/RoamExperienceComponents.swift', 'Core/RoamExperienceMath.swift', 'Resources/Localizable.xcstrings', 'Tests/CoreTests/RoamRouteReplayTests.swift', 'Tests/ContractChecks/test_roam_route_replay.py', 'docs/roam-route-replay.md', 'Tests/ContractChecks/test_category_roam_registration.py']
IMPLEMENTATION_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()

def require(condition, message):
    if not condition:
        raise AssertionError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def restore_category_gate(raw):
    raw = category_gate_without_template(raw)
    require(digest(raw) == ADAPTED_CATEGORY_GATE_SHA256, 'Unknown adapted category gate')
    value = raw
    for offset, after, before in reversed(CATEGORY_GATE_DELTAS):
        require(value.count(after) == 1 and value[offset:offset + len(after)] == after,
                'Missing, moved or repeated category read-in span')
        value = value[:offset] + before + value[offset + len(after):]
    require(digest(value) == ORIGINAL_CATEGORY_GATE_SHA256, 'Original complete category gate changed')
    return value


def checked_current(raw, root):
    """Admit the actual current 18-file group before exposing any old bytes."""
    root = Path(root)
    require((root / CONTRACT_PATH).read_bytes() == raw, 'Live current contract differs from supplied bytes')
    runner = (root / RUNNER_PATH).read_bytes()
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    require(len(pins) == 1, 'Missing or repeated complete current contract pin')
    require(digest(runner.replace(pins[0], BASE_CONTRACT_SHA256.encode())) == BASE_RUNNER_SHA256,
            'Current runner contains more than the approved contract pin')
    require(digest(raw).encode() == pins[0], 'Unknown complete current combined contract')
    value = json.loads(raw)
    require(encode(value) == raw, 'Noncanonical or duplicate current contract bytes')
    sources = {path: (root / path).read_bytes() for path in FROZEN_SHA256}
    for path, expected in FROZEN_SHA256.items():
        require(digest(sources[path]) == expected, 'Changed current frozen leaf: ' + path)
    sources[CATEGORY_GATE] = (root / CATEGORY_GATE).read_bytes()
    sources[SELF_PATH] = (root / SELF_PATH).read_bytes()
    require(digest(sources[SELF_PATH]) == IMPLEMENTATION_SHA256,
            'Loaded combined gate does not match current source')
    restore_category_gate(sources[CATEGORY_GATE])
    for path in CATEGORY_SOURCES + tuple(ROAM_SOURCE_INVERSES):
        row = value['feature_batch_sources'].get(path)
        require(row is not None and row['after_sha256'] == digest(sources[path]),
                'Missing or changed real current source registration: ' + path)
    for path in CATEGORY_SUPPORT + ROAM_SUPPORT + (SELF_PATH,):
        require(value['feature_batch_support_sha256'].get(path) == digest(sources[path]),
                'Missing or changed real current support pin: ' + path)
    require(value['feature_batch_support_sha256'].get(CATALOG_PATH) == digest(sources[CATALOG_PATH]),
            'Catalog support must bind the real current catalog')
    return value, sources, runner, pins[0]


def restore_category_contract(value):
    """Remove only exact Roam registration and restore the full admitted category contract."""
    value = copy.deepcopy(value)
    for path, inverse in ROAM_SOURCE_INVERSES.items():
        require(path in value['feature_batch_sources'], 'Missing Roam source row: ' + path)
        row = value['feature_batch_sources'][path]
        hunks = [{'before': before.decode(), 'after': after.decode()} for after, before in inverse['spans']]
        require(row['after_sha256'] == inverse['after'], 'Unknown Roam row postimage: ' + path)
        if path == HISTORY_PATH:
            require(row['before_sha256'] == HISTORY_FLOOR and row['hunks'][-len(hunks):] == hunks,
                    'Changed History original floor or exact appended inverse')
            del row['hunks'][-len(hunks):]
            row['after_sha256'] = inverse['before']
            require(digest(encode(row)) == CATEGORY_HISTORY_ROW_SHA256, 'Original category History row changed')
        else:
            require(row == {'before_sha256': inverse['before'], 'after_sha256': inverse['after'], 'hunks': hunks},
                    'Changed exact newly registered Roam row: ' + path)
            del value['feature_batch_sources'][path]
    for path in ROAM_SUPPORT + (SELF_PATH,):
        require(path in value['feature_batch_support_sha256'], 'Missing combined support row: ' + path)
        del value['feature_batch_support_sha256'][path]
    value['feature_batch_support_sha256'][CATALOG_PATH] = ROAM_SOURCE_INVERSES[CATALOG_PATH]['before']
    value['feature_batch_support_sha256'][CATEGORY_GATE] = ORIGINAL_CATEGORY_GATE_SHA256
    previous = encode(value)
    require(digest(previous) == CATEGORY_CONTRACT_SHA256 and len(previous) == CATEGORY_CONTRACT_BYTES,
            'Exact complete category-only contract was not restored')
    return previous


def pre_roam_category_contract_bytes(raw, *, root=ROOT):
    value, _, _, _ = checked_current(raw, root)
    return restore_category_contract(value)


_cache = None
_context_creations = 0


def pre_roam_category_inputs(raw, *, root=ROOT):
    """Nine data files only; original category assertions still execute unmodified."""
    global _cache, _context_creations
    root = Path(root)
    value, sources, runner, pin = checked_current(raw, root)
    previous = restore_category_contract(value)
    historical = {path: sources[path] for path in CATEGORY_SOURCES + CATEGORY_SUPPORT}
    historical[CATEGORY_GATE] = restore_category_gate(sources[CATEGORY_GATE])
    historical['tools/tests/test_gitleaks_configuration.py'] = category_scanner_bytes(sources['tools/tests/test_gitleaks_configuration.py'], root=root)
    historical[RUNNER_PATH] = runner.replace(pin, CATEGORY_CONTRACT_SHA256.encode())
    require(digest(historical[RUNNER_PATH]) == CATEGORY_RUNNER_SHA256, 'Original category runner changed')
    require(len(historical) == 9, 'Historical category context exceeded nine files')
    key = (str(root.resolve()), digest(raw))
    expected = {path: digest(data) for path, data in historical.items()}
    if _cache is not None and _cache['key'] == key:
        target = _cache['root']
        actual = {str(path.relative_to(target)): digest(path.read_bytes())
                  for path in target.rglob('*') if path.is_file()}
        require(actual == expected, 'Cached nine-file historical category context changed')
        return previous, target
    if _cache is not None:
        _cache['life'].cleanup()
    life = tempfile.TemporaryDirectory(prefix='category-roam-history-')
    target = Path(life.name)
    for path, data in historical.items():
        file = target / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data)
    _cache = {'key': key, 'root': target, 'life': life}
    _context_creations += 1
    return previous, target


class CategoryRoamRegistrationContracts(unittest.TestCase):
    def setUp(self):
        self.raw = (ROOT / CONTRACT_PATH).read_bytes()

    def test_current_18_file_group_is_bound_before_historical_projection(self):
        value, sources, runner, _ = checked_current(self.raw, ROOT)
        sources = dict(sources); sources[PROFILE_PATH] = (ROOT / PROFILE_PATH).read_bytes(); del sources[SCANNER_PATH]
        self.assertEqual(len(sources), 16)
        self.assertEqual(len(FROZEN_SHA256), 14)
        self.assertEqual(set(sources) | {CONTRACT_PATH, RUNNER_PATH}, set(APPROVED_PATHS))
        self.assertEqual(digest(self.raw), re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)[0].decode())
        self.assertEqual(value['feature_batch_sources'][HISTORY_PATH]['before_sha256'], HISTORY_FLOOR)

    def test_exact_combined_to_category_to_original_complete_contracts(self):
        from Tests.ContractChecks import test_global_search_category_recovery as category
        old = pre_roam_category_contract_bytes(self.raw)
        self.assertEqual(digest(old), CATEGORY_CONTRACT_SHA256)
        self.assertEqual(len(old), CATEGORY_CONTRACT_BYTES)
        self.assertEqual(digest(category.historical_category_contract_bytes(self.raw)), BASE_CONTRACT_SHA256)
        current = historical_r2_contract(self.raw, ROOT); prior = json.loads(old)
        self.assertEqual(set(current['feature_batch_sources']) - set(prior['feature_batch_sources']),
                         set(ROAM_SOURCE_INVERSES) - {HISTORY_PATH})

    def test_original_category_gate_and_all_assertions_restore_exactly(self):
        current = (ROOT / CATEGORY_GATE).read_bytes()
        prior = restore_category_gate(current)
        self.assertEqual(digest(prior), ORIGINAL_CATEGORY_GATE_SHA256)
        self.assertEqual(len(prior), 64871)
        def assertions(raw):
            return [ast.dump(node, include_attributes=False) for node in ast.walk(ast.parse(raw))
                    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr.startswith('assert')]
        self.assertEqual(assertions(current), assertions(prior))
        def tests(raw):
            return [node.name for node in ast.walk(ast.parse(raw))
                    if isinstance(node, ast.FunctionDef) and node.name.startswith('test_')]
        self.assertEqual(tests(current), tests(prior)); self.assertEqual(len(tests(prior)), 19)
        # Remove just the one inserted read-in statement from the original function body.
        marker = b'    raw, root = pre_roam_category_inputs(raw, root=root)\n'
        self.assertEqual(current.count(marker), 1)

    def test_original_scanner_and_real_source_are_not_replaced_by_history(self):
        scanner = (ROOT / 'tools/tests/test_gitleaks_configuration.py').read_bytes()
        self.assertEqual(digest(scanner), FROZEN_SHA256['tools/tests/test_gitleaks_configuration.py'])
        self.assertIn(b'(4028, "feature_batch_support_sha256"', scanner)
        self.assertEqual(digest((ROOT / '.gitleaksignore').read_bytes()), IGNORE_SHA256)
        prior, context = pre_roam_category_inputs(self.raw)
        files = {str(p.relative_to(context)) for p in context.rglob('*') if p.is_file()}
        self.assertEqual(files, set(CATEGORY_SOURCES + CATEGORY_SUPPORT + (RUNNER_PATH,)))
        self.assertNotIn(CATALOG_PATH, files)
        self.assertEqual((ROOT / CONTRACT_PATH).read_bytes(), self.raw)
        self.assertNotEqual(digest(prior), digest(self.raw))

    def test_all_current_files_missing_newline_and_crlf_fail_closed(self):
        # Prime history before every live-file mutation. Supplied raw stays saved.
        pre_roam_category_inputs(self.raw)
        real_read = Path.read_bytes
        for path in APPROVED_PATHS:
            target = ROOT / path
            raw = real_read(target)
            for changed in (raw + b'\n', raw.replace(b'\n', b'\r\n')):
                def altered(obj, target=target, changed=changed):
                    return changed if obj == target else real_read(obj)
                with patch.object(Path, 'read_bytes', altered):
                    with self.assertRaises(AssertionError): pre_roam_category_inputs(self.raw)
                if path == CONTRACT_PATH:
                    with self.assertRaises(AssertionError): pre_roam_category_inputs(changed)
            def missing(obj, target=target):
                if obj == target: raise FileNotFoundError(str(target))
                return real_read(obj)
            with patch.object(Path, 'read_bytes', missing):
                with self.assertRaises(FileNotFoundError): pre_roam_category_inputs(self.raw)

    def _reject_repinned(self, value):
        raw = encode(value)
        runner_path = ROOT / RUNNER_PATH
        original = Path.read_bytes
        runner = original(runner_path).replace(digest(self.raw).encode(), digest(raw).encode())
        with patch.object(Path, 'read_bytes', lambda obj: runner if obj == runner_path else raw if obj == ROOT / CONTRACT_PATH else original(obj)):
            with self.assertRaises(AssertionError): pre_roam_category_inputs(raw)

    def test_missing_roam_rows_and_supports_fail_even_after_complete_repins(self):
        value = json.loads(self.raw)
        for path in ROAM_SOURCE_INVERSES:
            changed = copy.deepcopy(value); del changed['feature_batch_sources'][path]
            self._reject_repinned(changed)
        for path in ROAM_SUPPORT + (SELF_PATH,):
            changed = copy.deepcopy(value); del changed['feature_batch_support_sha256'][path]
            self._reject_repinned(changed)
        changed = copy.deepcopy(value)
        changed['feature_batch_support_sha256'][CATALOG_PATH] = ROAM_SOURCE_INVERSES[CATALOG_PATH]['before']
        self._reject_repinned(changed)

    def test_original_floors_unknown_rows_and_inverse_hunks_cannot_be_hidden_by_repins(self):
        value = json.loads(self.raw)
        for path in CATEGORY_SOURCES + tuple(ROAM_SOURCE_INVERSES):
            changed = copy.deepcopy(value); changed['feature_batch_sources'][path]['before_sha256'] = '0' * 64
            self._reject_repinned(changed)
            changed = copy.deepcopy(value); changed['feature_batch_sources'][path]['hunks'].pop()
            self._reject_repinned(changed)
        changed = copy.deepcopy(value)
        changed['feature_batch_sources']['App/Unexpected.swift'] = {'before_sha256': '0' * 64, 'after_sha256': '1' * 64, 'hunks': []}
        self._reject_repinned(changed)

    def test_mixed_catalog_and_unregistered_foreign_keys_fail_before_old_gate(self):
        from Tests.ContractChecks.test_roam_route_replay import project_saved_route_source
        current = (ROOT / CATALOG_PATH).read_bytes()
        base = project_saved_route_source(CATALOG_PATH, current)
        value = json.loads(current); value['strings']['unregisteredForeign.key'] = {'localizations': {}}
        target = ROOT / CATALOG_PATH; original = Path.read_bytes
        for bad in (base, encode(value)):
            with patch.object(Path, 'read_bytes', lambda obj: bad if obj == target else original(obj)):
                with self.assertRaises(AssertionError): pre_roam_category_inputs(self.raw)

    def test_category_adapter_missing_duplicated_moved_or_assertion_drift_rejected(self):
        raw = (ROOT / CATEGORY_GATE).read_bytes()
        for offset, after, before in CATEGORY_GATE_DELTAS:
            for bad in (raw[:offset] + raw[offset + len(after):], raw + after,
                        after + raw[:offset] + raw[offset + len(after):]):
                with self.assertRaises(AssertionError): restore_category_gate(bad)
        bad = raw.replace(b'self.assertEqual', b'self.assertNotEqual', 1)
        with self.assertRaises(AssertionError): restore_category_gate(bad)
        for offset in range(len(raw)):
            bad = raw[:offset] + bytes([raw[offset] ^ 1]) + raw[offset + 1:]
            with self.assertRaises(AssertionError): restore_category_gate(bad)

    def test_nine_file_cache_is_bounded_and_revalidates_current_and_cached_bytes(self):
        _, first = pre_roam_category_inputs(self.raw)
        count = _context_creations
        for _ in range(25): self.assertEqual(pre_roam_category_inputs(self.raw)[1], first)
        self.assertEqual(_context_creations, count)
        target = first / CATEGORY_GATE; saved = target.read_bytes()
        try:
            target.write_bytes(saved + b'\n')
            with self.assertRaisesRegex(AssertionError, 'Cached nine-file'): pre_roam_category_inputs(self.raw)
        finally:
            target.write_bytes(saved)
        real_read = Path.read_bytes; current = ROOT / HISTORY_PATH
        with patch.object(Path, 'read_bytes', lambda obj: real_read(obj) + b'\n' if obj == current else real_read(obj)):
            with self.assertRaises(AssertionError): pre_roam_category_inputs(self.raw)
        self.assertEqual(pre_roam_category_inputs(self.raw)[1], first)

    def test_current_central_source_inverses_keep_all_seven_original_floors(self):
        from tools import run138_current_source_projection as entry
        value = json.loads(self.raw)
        for path in CATEGORY_SOURCES + tuple(ROAM_SOURCE_INVERSES):
            raw = (ROOT / path).read_bytes()
            before = entry.original_feature_batch_bytes(path, raw, ROOT)
            self.assertEqual(digest(before), value['feature_batch_sources'][path]['before_sha256'])
            with self.assertRaises(ValueError): entry.original_feature_batch_bytes(path, raw + b'\n', ROOT)

    def test_existing_scope_and_public_discovery_stay_bounded(self):
        self.assertEqual(len(APPROVED_PATHS), 18)
        self.assertEqual(len(set(APPROVED_PATHS)), 18)
        for path in ['Tests/ContractChecks/test_search_map_layer_retry.py', 'Tests/CoreTests/SearchMapLayerRetryTests.swift']:
            self.assertFalse((ROOT / path).exists())
        self.assertIn("'contracts': {'directory': 'Tests/ContractChecks', 'pattern': 'test_*.py'}",
                      (ROOT / 'tools/run_static_checks.py').read_text())
        self.assertTrue(Path(__file__).name.startswith('test_'))


# Exact discovery/Roam layer on the frozen club R2 floor.
ADMISSION_FINGERPRINT = '1593f471ec9335da9f0c9e72db12061f037ae7ae3a1fe4b00c8431f4641ae3b3'
CATEGORY_TEMPLATE_OFFSET = 65180
CURRENT_APPROVED_PATHS = ['App/GlobalSearchView.swift',
 'Core/SearchMapReading.swift',
 'App/SearchMapFilterSheet.swift',
 'Tests/ContractChecks/test_global_search_category_recovery.py',
 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift',
 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift',
 'docs/global-search-category-recovery.md',
 'tools/run138_editor_readiness_contract.json',
 'tools/run138_editor_readiness.py',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'App/RoamHistoryViews.swift',
 'App/RoamExperienceComponents.swift',
 'Core/RoamExperienceMath.swift',
 'Resources/Localizable.xcstrings',
 'Tests/CoreTests/RoamRouteReplayTests.swift',
 'Tests/ContractChecks/test_roam_route_replay.py',
 'docs/roam-route-replay.md',
 'Tests/ContractChecks/test_category_roam_registration.py',
 'Tests/ContractChecks/test_template_shelf_state_projection.py',
 'tools/tests/creator_shelf_state_history.py',
 'tools/tests/test_creator_shelf_state_history.py']
EXTRA_INPUT_ROWS = {'Tests/ContractChecks/test_template_shelf_state_projection.py': {'before_sha256': '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4',
                                                                  'after_sha256': 'f229a3c1447956510c42368847e70a3c94d0935b838828bb959e124507b51595',
                                                                  'hunks': [{'before': 'SWIFT_TESTS = '
                                                                                       "'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'\n"
                                                                                       '\n'
                                                                                       'def digest(text): return '
                                                                                       'hashlib.sha256(text.encode()).hexdigest()\n'
                                                                                       'def read(path): return (ROOT / '
                                                                                       'path).read_text()\n'
                                                                                       'def section(text, first, '
                                                                                       'last):\n'
                                                                                       '    start = text.index(first)\n'
                                                                                       '    return '
                                                                                       'text[start:text.index(last, '
                                                                                       'start)]\n',
                                                                             'after': 'SWIFT_TESTS = '
                                                                                      "'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'\n"
                                                                                      '\n'
                                                                                      'def digest(text): return '
                                                                                      'hashlib.sha256(text.encode()).hexdigest()\n'
                                                                                      'def read(path):\n'
                                                                                      '    if path == CATALOG:\n'
                                                                                      '        from '
                                                                                      'Tests.ContractChecks.test_category_roam_registration '
                                                                                      'import creator_catalog_input\n'
                                                                                      '        return '
                                                                                      'creator_catalog_input((ROOT / '
                                                                                      'path).read_bytes(), '
                                                                                      'ROOT).decode()\n'
                                                                                      '    return (ROOT / '
                                                                                      'path).read_text()\n'
                                                                                      'def section(text, first, '
                                                                                      'last):\n'
                                                                                      '    start = text.index(first)\n'
                                                                                      '    return '
                                                                                      'text[start:text.index(last, '
                                                                                      'start)]\n'}]},
 'tools/tests/creator_shelf_state_history.py': {'before_sha256': '63d498f92184bfdf2349849c683347adc5766e73878cc1f5e86790b68799d2e3',
                                                'after_sha256': 'db500fc7605d2fd12e98b4b042fd11ef284645156d0e4698f688ea3c92890b0e',
                                                'hunks': [{'before': '\n'
                                                                     '\n'
                                                                     'def historical_pre_shelf_state_sources(*, '
                                                                     'root=ROOT):\n'
                                                                     '    root = Path(root)\n'
                                                                     '    sources = {}\n'
                                                                     '    for name in REFRESH_INPUTS:\n',
                                                           'after': '\n'
                                                                    '\n'
                                                                    'def historical_pre_shelf_state_sources(*, '
                                                                    'root=ROOT):\n'
                                                                    '    from '
                                                                    'Tests.ContractChecks.test_category_roam_registration '
                                                                    'import creator_history_root\n'
                                                                    '    root = creator_history_root(root, '
                                                                    'live_root=ROOT)\n'
                                                                    '    root = Path(root)\n'
                                                                    '    sources = {}\n'
                                                                    '    for name in REFRESH_INPUTS:\n'}]},
 'tools/tests/test_creator_shelf_state_history.py': {'before_sha256': 'baa95d45430a19f2a7c472dcd269150197617f45d50735aa84b142ca2973d33c',
                                                     'after_sha256': 'accaa341cf2803a6847c19ee675d7bb9d06b831d300c1a56d9f17d9aeddfb65e',
                                                     'hunks': [{'before': '\n'
                                                                          '\n'
                                                                          'def assert_current_raw(root):\n'
                                                                          '    for name, expected in '
                                                                          'CURRENT_SHA.items():\n'
                                                                          '        if digest((root / '
                                                                          'name).read_bytes()) != expected:\n'
                                                                          "            raise ValueError('Changed raw "
                                                                          "state input: ' + name)\n",
                                                                'after': '\n'
                                                                         '\n'
                                                                         'def assert_current_raw(root):\n'
                                                                         '    from '
                                                                         'Tests.ContractChecks.test_category_roam_registration '
                                                                         'import creator_history_root\n'
                                                                         '    root = creator_history_root(root, '
                                                                         'live_root=ROOT)\n'
                                                                         '    for name, expected in '
                                                                         'CURRENT_SHA.items():\n'
                                                                         '        if digest((root / '
                                                                         'name).read_bytes()) != expected:\n'
                                                                         "            raise ValueError('Changed raw "
                                                                         "state input: ' + name)\n"},
                                                               {'before': '        self.temp = '
                                                                          'tempfile.TemporaryDirectory()\n'
                                                                          '        self.addCleanup(self.temp.cleanup)\n'
                                                                          '        self.root = Path(self.temp.name)\n'
                                                                          '        self.current = {name: (ROOT / '
                                                                          'name).read_bytes() for name in '
                                                                          'state.SOURCE_SHA256}\n'
                                                                          '        self.legacy = dict(self.current)\n'
                                                                          '        for name in state.INVERSE_DELTAS:\n'
                                                                          '            self.legacy[name] = '
                                                                          'state.restore_state_bytes(name, '
                                                                          'self.current[name])\n',
                                                                'after': '        self.temp = '
                                                                         'tempfile.TemporaryDirectory()\n'
                                                                         '        self.addCleanup(self.temp.cleanup)\n'
                                                                         '        self.root = Path(self.temp.name)\n'
                                                                         '        from '
                                                                         'Tests.ContractChecks.test_category_roam_registration '
                                                                         'import creator_history_sources\n'
                                                                         '        self.current = '
                                                                         'creator_history_sources(ROOT, '
                                                                         'state.SOURCE_SHA256)\n'
                                                                         '        self.legacy = dict(self.current)\n'
                                                                         '        for name in state.INVERSE_DELTAS:\n'
                                                                         '            self.legacy[name] = '
                                                                         'state.restore_state_bytes(name, '
                                                                         'self.current[name])\n'},
                                                               {'before': '                sources[key]=changed\n'
                                                                          '                with '
                                                                          'self.assertRaises(ValueError):projection.validate_feature_batch_sources(ROOT)\n'
                                                                          '            sources[key]=raw\n'
                                                                          '            '
                                                                          'old=raw.replace(state.SOURCE_SHA256[CATALOG][1].encode(),state.SOURCE_SHA256[CATALOG][0].encode(),1)\n'
                                                                          '            sources[key]=old\n'
                                                                          '            with '
                                                                          "patch.object(planning,'CONTRACT_SHA256',digest(old)):\n"
                                                                          '                with '
                                                                          "self.assertRaisesRegex(ValueError,'Current "
                                                                          'feature-batch input changed: '
                                                                          "Resources/Localizable'):\n",
                                                                'after': '                sources[key]=changed\n'
                                                                         '                with '
                                                                         'self.assertRaises(ValueError):projection.validate_feature_batch_sources(ROOT)\n'
                                                                         '            sources[key]=raw\n'
                                                                         '            old_value=json.loads(raw); '
                                                                         "old_value['feature_batch_support_sha256'][CATALOG]=state.SOURCE_SHA256[CATALOG][0]\n"
                                                                         '            '
                                                                         "old=(json.dumps(old_value,ensure_ascii=False,indent=2)+'\\n').encode()\n"
                                                                         '            sources[key]=old\n'
                                                                         '            with '
                                                                         "patch.object(planning,'CONTRACT_SHA256',digest(old)):\n"
                                                                         '                with '
                                                                         "self.assertRaisesRegex(ValueError,'Current "
                                                                         'feature-batch input changed: '
                                                                         "Resources/Localizable'):\n"},
                                                               {'before': '\n'
                                                                          '# CLUB_HISTORY_INPUT_BEGIN\n'
                                                                          'def _restore_preclub_history_test(data):\n'
                                                                          '    from tools import '
                                                                          'club_customer_directory_admission as club\n'
                                                                          '    return '
                                                                          'club.restore_creator_history_test(data)\n'
                                                                          '# CLUB_HISTORY_INPUT_END\n',
                                                                'after': '\n'
                                                                         '# CLUB_HISTORY_INPUT_BEGIN\n'
                                                                         'def _restore_preclub_history_test(data):\n'
                                                                         '    from '
                                                                         'Tests.ContractChecks.test_category_roam_registration '
                                                                         'import creator_history_test_preimage\n'
                                                                         '    data = '
                                                                         'creator_history_test_preimage(data, ROOT)\n'
                                                                         '    from tools import '
                                                                         'club_customer_directory_admission as club\n'
                                                                         '    return '
                                                                         'club.restore_creator_history_test(data)\n'
                                                                         '# CLUB_HISTORY_INPUT_END\n'}]}}
CREATOR_FIXTURE_INPUTS = ('App/TemplateAuthoringMineView.swift',
 'Core/TemplateAuthoringShelf.swift',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
 'Resources/Localizable.xcstrings',
 'Tests/ContractChecks/test_template_shelf_state_projection.py',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift')
EXTRA_PARENT_SUPPORT = {'Tests/ContractChecks/test_template_shelf_state_projection.py': None,
 'tools/tests/creator_shelf_state_history.py': None,
 'tools/tests/test_creator_shelf_state_history.py': 'baa95d45430a19f2a7c472dcd269150197617f45d50735aa84b142ca2973d33c'}
CREATOR_RAW_GATE_PATH = 'Tests/ContractChecks/test_template_shelf_state_projection.py'
CREATOR_STATE_HELPER_PATH = 'tools/tests/creator_shelf_state_history.py'
CREATOR_HISTORY_TEST_PATH = 'tools/tests/test_creator_shelf_state_history.py'
PROFILE_PATH = 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py'
SCANNER_PATH = 'tools/tests/test_gitleaks_configuration.py'
ROAM_GATE_PATH = 'Tests/ContractChecks/test_roam_route_replay.py'
PARENT_TREE = '548c57fec97ae694bd3e20aa9163d35317a419e2'
PARENT_CONTRACT_SHA256 = '3902a64b0aaaf37362fe251bb3b6b1a2f1da824ba721cb0af2c3bf4ef1006bfd'
PARENT_PROFILE_SHA256 = '1a0779ba66616abee50b9ae87cc3d0f6ac3a6574a971aa323d14f7d745c3765d'
PARENT_CATALOG_SHA256 = '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995'
PARENT_SCANNER_SHA256 = 'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30'
PARENT_PROFILE_ROW = {'before_sha256': '1a0779ba66616abee50b9ae87cc3d0f6ac3a6574a971aa323d14f7d745c3765d',
 'after_sha256': '877a77cd39de29df24bc1ee180ba20e723797f2721e3deca8c06766aafef0293',
 'hunks': [{'before': 'from unittest.mock import patch\n'
                      '\n'
                      'ROOT = Path(__file__).resolve().parents[2]\n'
                      '\n'
                      'def load(relative, name):\n'
                      '    spec = importlib.util.spec_from_file_location(name, ROOT / relative)\n',
            'after': 'from unittest.mock import patch\n'
                     '\n'
                     'ROOT = Path(__file__).resolve().parents[2]\n'
                     "DISCOVERY_HELPER_FINGERPRINT = '<DISCOVERY_HELPER>'\n"
                     '\n'
                     'def load(relative, name):\n'
                     '    spec = importlib.util.spec_from_file_location(name, ROOT / relative)\n'},
           {'before': '\n'
                      '\n'
                      'def _merchant_business_compile_contract(contract, root=ROOT):\n'
                      '    root=Path(root)\n'
                      '    contract,current_encoded=_club_bound_merchant_input(contract,root)\n'
                      "    encoded=(json.dumps(contract,indent=2,ensure_ascii=False)+'\\n').encode()\n",
            'after': '\n'
                     '\n'
                     'def _merchant_business_compile_contract(contract, root=ROOT):\n'
                     '    from Tests.ContractChecks.test_category_roam_registration import profile_contract_inputs\n'
                     "    contract, root = profile_contract_inputs(contract, root, 'merchant')\n"
                     '    root=Path(root)\n'
                     '    contract,current_encoded=_club_bound_merchant_input(contract,root)\n'
                     "    encoded=(json.dumps(contract,indent=2,ensure_ascii=False)+'\\n').encode()\n"},
           {'before': 'CLUB_DIRECTORY_HELPER_SHA256 = '
                      "'80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297'\n"
                      '\n'
                      'def _club_directory_contract(contract, root=ROOT):\n'
                      "    helper = Path(root) / 'tools/club_customer_directory_admission.py'\n"
                      '    if digest(helper.read_bytes()) != CLUB_DIRECTORY_HELPER_SHA256:\n'
                      "        raise ValueError('Unreviewed complete club helper input')\n",
            'after': 'CLUB_DIRECTORY_HELPER_SHA256 = '
                     "'80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297'\n"
                     '\n'
                     'def _club_directory_contract(contract, root=ROOT):\n'
                     '    from Tests.ContractChecks.test_category_roam_registration import profile_contract_inputs\n'
                     "    contract, root = profile_contract_inputs(contract, root, 'club')\n"
                     "    helper = Path(root) / 'tools/club_customer_directory_admission.py'\n"
                     '    if digest(helper.read_bytes()) != CLUB_DIRECTORY_HELPER_SHA256:\n'
                     "        raise ValueError('Unreviewed complete club helper input')\n"},
           {'before': '\n'
                      '\n'
                      'def _creator_state_contract(contract, root=ROOT):\n'
                      '    # The current full contract, runner and admission module are authenticated by\n'
                      '    # the caller before entering this historical-only layer. Never scan this view.\n'
                      '    root = Path(root)\n',
            'after': '\n'
                     '\n'
                     'def _creator_state_contract(contract, root=ROOT):\n'
                     '    from Tests.ContractChecks.test_category_roam_registration import profile_contract_inputs\n'
                     "    contract, root = profile_contract_inputs(contract, root, 'creator')\n"
                     '    # The current full contract, runner and admission module are authenticated by\n'
                     '    # the caller before entering this historical-only layer. Never scan this view.\n'
                     '    root = Path(root)\n'},
           {'before': '\n'
                      '\n'
                      'def _combined_profile_contract_checked(data, root=ROOT):\n'
                      '    """Exact combined current -> reviewed profile R2 contract, never current admission."""\n'
                      '    root = Path(root)\n'
                      "    runner = (root / 'tools/run138_editor_readiness.py').read_bytes()\n",
            'after': '\n'
                     '\n'
                     'def _combined_profile_contract_checked(data, root=ROOT):\n'
                     '    from Tests.ContractChecks.test_category_roam_registration import profile_history_inputs\n'
                     "    data, root = profile_history_inputs(data, root, 'combined')\n"
                     '    """Exact combined current -> reviewed profile R2 contract, never current admission."""\n'
                     '    root = Path(root)\n'
                     "    runner = (root / 'tools/run138_editor_readiness.py').read_bytes()\n"},
           {'before': '    return restored\n'
                      '\n'
                      'def historical_readiness_contract(data, root=ROOT):\n'
                      '    """Historical line reader only; the current central gate still rejects old bytes."""\n'
                      '    if digest(data) == ORIGINAL_READINESS_SHA256:\n'
                      '        return data\n',
            'after': '    return restored\n'
                     '\n'
                     'def historical_readiness_contract(data, root=ROOT):\n'
                     '    from Tests.ContractChecks.test_category_roam_registration import profile_history_inputs\n'
                     "    data, root = profile_history_inputs(data, root, 'history')\n"
                     '    """Historical line reader only; the current central gate still rejects old bytes."""\n'
                     '    if digest(data) == ORIGINAL_READINESS_SHA256:\n'
                     '        return data\n'}]}
CURRENT_SOURCE_ROWS = {'App/GlobalSearchView.swift': {'before_sha256': 'c70fee37e02a6b4e2ee6540104932b175fee1d0faed013141fecb8cbce6c7cec',
                                'after_sha256': '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78',
                                'hunks': [{'before': '    @State private var filter = GlobalSearchQuery()\n'
                                                     '    @State private var categories: [DiscoveryCategory] = []\n'
                                                     '    @State private var categoryFailed = false\n'
                                                     '    @State private var result: GlobalSearchResults?\n'
                                                     '    @State private var issue: String?\n'
                                                     '    @State private var loading = false\n'
                                                     '    @State private var activeQuery: GlobalSearchQuery?\n'
                                                     '    @State private var selectedKind: GlobalSearchKind?\n'
                                                     '    @State private var showsFilters = false\n'
                                                     '    @State private var history: [String] = []\n'
                                                     '    @State private var historyFailure = false\n'
                                                     '    @State private var gate = SearchMapQueryGate()\n'
                                                     '    @State private var categoryGate = SearchMapQueryGate()\n'
                                                     '    @State private var preparedScope: UUID?\n'
                                                     '    private let historyStore = SearchMapLocalHistory()\n'
                                                     '\n'
                                                     '    var body: some View {\n'
                                                     '        ScrollView {\n'
                                                     '            VStack(alignment: .leading, spacing: 18) {\n'
                                                     '                if historyFailure { '
                                                     'Text("searchMap.historyUnavailable").font(.caption).foregroundStyle(.secondary) '
                                                     '}\n'
                                                     '                if reader.isOfflineExample { '
                                                     'Text("searchMap.offline").font(.caption).foregroundStyle(.secondary) '
                                                     '}\n'
                                                     '                HStack {\n'
                                                     '                    TextField("searchMap.placeholder", text: '
                                                     '$filter.keyword).textInputAutocapitalization(.never)\n'
                                                     '                        .submitLabel(.search).onSubmit { Task { '
                                                     'await search() } }\n'
                                                     '                        '
                                                     '.accessibilityIdentifier("searchMap.keyword")\n'
                                                     '                    Button { showsFilters = true } label: { '
                                                     'Label("searchMap.filters", systemImage: '
                                                     '"line.3.horizontal.decrease") }\n',
                                           'after': '    @State private var filter = GlobalSearchQuery()\n'
                                                    '    @State private var categories: [DiscoveryCategory] = []\n'
                                                    '    @State private var categoryFailed = false\n'
                                                    '    @State private var retainedResults = '
                                                    'GlobalSearchRetainedResults()\n'
                                                    '    @State private var isVisible = false\n'
                                                    '    @State private var issue: String?\n'
                                                    '    @State private var loading = false\n'
                                                    '    @State private var selectedKind: GlobalSearchKind?\n'
                                                    '    @State private var showsFilters = false\n'
                                                    '    @State private var history: [String] = []\n'
                                                    '    @State private var historyFailure = false\n'
                                                    '    @State private var categoryGate = SearchMapQueryGate()\n'
                                                    '    @State private var preparedOwner: ReadOwner?\n'
                                                    '    private let historyStore = SearchMapLocalHistory()\n'
                                                    '\n'
                                                    '    private struct ReadOwner: Equatable {\n'
                                                    '        let readerID: ObjectIdentifier\n'
                                                    '        let scope: UUID\n'
                                                    '        let authenticated: Bool\n'
                                                    '        let configured: Bool\n'
                                                    '    }\n'
                                                    '    private var readOwner: ReadOwner {\n'
                                                    '        .init(readerID: ObjectIdentifier(reader), scope: '
                                                    'reader.scope,\n'
                                                    '              authenticated: reader.isAuthenticated, configured: '
                                                    'reader.isConfigured)\n'
                                                    '    }\n'
                                                    '    private var resultContext: GlobalSearchResultContext {\n'
                                                    '        .init(readerID: ObjectIdentifier(reader), scope: '
                                                    'reader.scope, isAuthenticated: reader.isAuthenticated,\n'
                                                    '              isConfigured: reader.isConfigured, query: filter)\n'
                                                    '    }\n'
                                                    '    var body: some View {\n'
                                                    '        ScrollView {\n'
                                                    '            VStack(alignment: .leading, spacing: 18) {\n'
                                                    '                if historyFailure { '
                                                    'Text("searchMap.historyUnavailable").font(.caption).foregroundStyle(.secondary) '
                                                    '}\n'
                                                    '                if reader.isOfflineExample { '
                                                    'Text("searchMap.offline").font(.caption).foregroundStyle(.secondary) '
                                                    '}\n'
                                                    '                HStack {\n'
                                                    '                    TextField("searchMap.placeholder", text: '
                                                    'Binding(get: { filter.keyword }, set: '
                                                    'setKeyword)).textInputAutocapitalization(.never)\n'
                                                    '                        .submitLabel(.search).onSubmit { Task { '
                                                    'await search() } }\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("searchMap.keyword")\n'
                                                    '                    Button { showsFilters = true } label: { '
                                                    'Label("searchMap.filters", systemImage: '
                                                    '"line.3.horizontal.decrease") }\n'},
                                          {'before': '                } label: { Label("merchant.discover.title", '
                                                     'systemImage: "storefront") }\n'
                                                     '                    .frame(minHeight: '
                                                     '44).accessibilityIdentifier("merchant.discover.entry")\n'
                                                     '                if !reader.isConfigured { SearchMapIssue(key: '
                                                     '"searchMap.notConfigured") }\n'
                                                     '                else if loading { '
                                                     'ProgressView("searchMap.loading").frame(maxWidth: '
                                                     '.infinity).accessibilityIdentifier("searchMap.loading") }\n'
                                                     '                else if let issue { SearchMapIssue(key: issue) { '
                                                     'Task { await search() } } }\n'
                                                     '                else if let result { results(result) }\n'
                                                     '                else { suggestions }\n'
                                                     '            }.padding()\n'
                                                     '        }\n'
                                                     '        .appNavigationTitle("searchMap.title")\n',
                                           'after': '                } label: { Label("merchant.discover.title", '
                                                    'systemImage: "storefront") }\n'
                                                    '                    .frame(minHeight: '
                                                    '44).accessibilityIdentifier("merchant.discover.entry")\n'
                                                    '                if !reader.isConfigured { SearchMapIssue(key: '
                                                    '"searchMap.notConfigured") }\n'
                                                    '                else {\n'
                                                    '                    if loading { '
                                                    'ProgressView("searchMap.loading").frame(maxWidth: '
                                                    '.infinity).accessibilityIdentifier("searchMap.loading") }\n'
                                                    '                    if let issue { SearchMapIssue(key: issue) { '
                                                    'Task { await search() } } }\n'
                                                    '                    if let snapshot = '
                                                    'retainedResults.snapshot(in: resultContext) {\n'
                                                    '                        results(snapshot.results, retainedKinds: '
                                                    'snapshot.retainedKinds)\n'
                                                    '                    } else if !loading && issue == nil { '
                                                    'suggestions }\n'
                                                    '                }\n'
                                                    '            }.padding()\n'
                                                    '        }\n'
                                                    '        .appNavigationTitle("searchMap.title")\n'},
                                          {'before': '                applyFilter(next)\n'
                                                     '            }\n'
                                                     '        }\n'
                                                     '        .task(id: reader.scope) { await prepare() }\n'
                                                     '        .onChange(of: filter.keyword) { _, keyword in if '
                                                     'activeQuery?.keyword != keyword { invalidate() } }\n'
                                                     '        .onDisappear { gate.invalidate(); '
                                                     'categoryGate.invalidate(); loading = false }\n'
                                                     '    }\n'
                                                     '    @ViewBuilder private var suggestions: some View {\n'
                                                     '        if !history.isEmpty {\n',
                                           'after': '                applyFilter(next)\n'
                                                    '            }\n'
                                                    '        }\n'
                                                    '        .task(id: readOwner) { await prepare() }\n'
                                                    '        .onAppear { isVisible = true }\n'
                                                    '        .onDisappear { isVisible = false; '
                                                    'retainedResults.cancelPending(); categoryGate.invalidate(); '
                                                    'loading = false }\n'
                                                    '    }\n'
                                                    '    @ViewBuilder private var suggestions: some View {\n'
                                                    '        if !history.isEmpty {\n'},
                                          {'before': '                    .frame(minHeight: '
                                                     '44).accessibilityIdentifier("searchMap.clearHistory")\n'
                                                     '            }\n'
                                                     '            ForEach(history, id: \\.self) { keyword in\n'
                                                     '                Button { filter.keyword = keyword; Task { await '
                                                     'search() } } label: { Label(keyword, systemImage: "clock") }\n'
                                                     '                    .frame(minHeight: 44)\n'
                                                     '            }\n'
                                                     '        }\n',
                                           'after': '                    .frame(minHeight: '
                                                    '44).accessibilityIdentifier("searchMap.clearHistory")\n'
                                                    '            }\n'
                                                    '            ForEach(history, id: \\.self) { keyword in\n'
                                                    '                Button { setKeyword(keyword); Task { await '
                                                    'search() } } label: { Label(keyword, systemImage: "clock") }\n'
                                                    '                    .frame(minHeight: 44)\n'
                                                    '            }\n'
                                                    '        }\n'},
                                          {'before': '            }\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '    @ViewBuilder private func results(_ value: '
                                                     'GlobalSearchResults) -> some View {\n'
                                                     '        if !value.gatedKinds.isEmpty {\n'
                                                     '            Label("searchMap.partialSignIn", systemImage: '
                                                     '"lock").font(.footnote)\n'
                                                     '                '
                                                     '.accessibilityIdentifier("searchMap.guestGate")\n',
                                           'after': '            }\n'
                                                    '        }\n'
                                                    '    }\n'
                                                    '    @ViewBuilder private func results(_ value: '
                                                    'GlobalSearchResults, retainedKinds: [GlobalSearchKind]) -> some '
                                                    'View {\n'
                                                    '        if loading && !value.rows.isEmpty {\n'
                                                    '            '
                                                    'Text("globalSearchRetention.refreshing").font(.footnote).foregroundStyle(.secondary)\n'
                                                    '                '
                                                    '.accessibilityIdentifier("globalSearchRetention.refreshing")\n'
                                                    '        }\n'
                                                    '        if !retainedKinds.isEmpty {\n'
                                                    '            VStack(alignment: .leading, spacing: 4) {\n'
                                                    '                Text("globalSearchRetention.stale")\n'
                                                    '                ForEach(retainedKinds, id: \\.self) { kind in '
                                                    'Label(kind.titleKey, systemImage: "clock.arrow.circlepath") }\n'
                                                    '            '
                                                    '}.font(.footnote).accessibilityIdentifier("globalSearchRetention.stale")\n'
                                                    '        }\n'
                                                    '        if !value.gatedKinds.isEmpty {\n'
                                                    '            Label("searchMap.partialSignIn", systemImage: '
                                                    '"lock").font(.footnote)\n'
                                                    '                '
                                                    '.accessibilityIdentifier("searchMap.guestGate")\n'},
                                          {'before': '            }.frame(minHeight: 44)\n'
                                                     '        }\n'
                                                     '        let visible = value.rows.filter { selectedKind == nil || '
                                                     '$0.kind == selectedKind }\n'
                                                     '        if visible.isEmpty && !value.allFailed { '
                                                     'ContentUnavailableView("searchMap.empty", systemImage: '
                                                     '"magnifyingglass", description: Text("searchMap.emptyHint")) }\n'
                                                     '        ForEach(visible) { row in\n'
                                                     '            NavigationLink { destination(row.destination) } '
                                                     'label: { SearchMapCard(row: row, offline: '
                                                     'reader.isOfflineExample) }\n'
                                                     '                '
                                                     '.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.result.\\(row.id)")\n',
                                           'after': '            }.frame(minHeight: 44)\n'
                                                    '        }\n'
                                                    '        let visible = value.rows.filter { selectedKind == nil || '
                                                    '$0.kind == selectedKind }\n'
                                                    '        if visible.isEmpty && !loading && !value.allFailed && '
                                                    'value.failedKinds.isEmpty && value.gatedKinds.isEmpty { '
                                                    'ContentUnavailableView("searchMap.empty", systemImage: '
                                                    '"magnifyingglass", description: Text("searchMap.emptyHint")) }\n'
                                                    '        ForEach(visible) { row in\n'
                                                    '            NavigationLink { destination(row.destination) } '
                                                    'label: { SearchMapCard(row: row, offline: '
                                                    'reader.isOfflineExample) }\n'
                                                    '                '
                                                    '.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.result.\\(row.id)")\n'},
                                          {'before': '        // Invalidate synchronously, including category-only '
                                                     'searches cleared to an empty query.\n'
                                                     '        filter = next; invalidate(); Task { await search() }\n'
                                                     '    }\n'
                                                     '    private func invalidate() { gate.invalidate(); activeQuery = '
                                                     'nil; result = nil; issue = nil; loading = false }\n'
                                                     '    private func prepare(force: Bool = false) async {\n'
                                                     '        if preparedScope != reader.scope {\n'
                                                     '            preparedScope = reader.scope; invalidate(); '
                                                     'categories = []; categoryFailed = false\n'
                                                     '            history = historyStore.read(namespace: '
                                                     'historyNamespace); historyFailure = historyStore.failed\n'
                                                     '        }\n'
                                                     '        guard reader.isConfigured, force || categories.isEmpty '
                                                     'else { return }\n',
                                           'after': '        // Invalidate synchronously, including category-only '
                                                    'searches cleared to an empty query.\n'
                                                    '        filter = next; invalidate(); Task { await search() }\n'
                                                    '    }\n'
                                                    '    private func setKeyword(_ value: String) {\n'
                                                    '        guard !filter.keyword.utf8.elementsEqual(value.utf8) else '
                                                    '{ return }\n'
                                                    '        invalidate(); filter.keyword = value\n'
                                                    '    }\n'
                                                    '    private func invalidate() { retainedResults.invalidate(); '
                                                    'issue = nil; loading = false; selectedKind = nil }\n'
                                                    '    private func prepare(force: Bool = false) async {\n'
                                                    '        if preparedOwner != readOwner {\n'
                                                    '            preparedOwner = readOwner; invalidate(); categories = '
                                                    '[]; categoryFailed = false\n'
                                                    '            history = historyStore.read(namespace: '
                                                    'historyNamespace); historyFailure = historyStore.failed\n'
                                                    '        }\n'
                                                    '        guard reader.isConfigured, force || categories.isEmpty '
                                                    'else { return }\n'},
                                          {'before': '    }\n'
                                                     '    private func search() async {\n'
                                                     '        let query = filter\n'
                                                     '        guard reader.isConfigured, query.canSearch else { return '
                                                     '}\n'
                                                     '        let ticket = gate.begin(scope: reader.scope)\n'
                                                     '        activeQuery = query\n'
                                                     '        loading = true; result = nil; issue = nil\n'
                                                     '        defer { if gate.accepts(ticket, scope: reader.scope) { '
                                                     'loading = false } }\n'
                                                     '        do {\n'
                                                     '            let value = try await reader.search(query)\n'
                                                     '            guard gate.accepts(ticket, scope: reader.scope), '
                                                     'filter == query else { return }\n'
                                                     '            result = value\n'
                                                     '            history = historyStore.add(query.keyword, namespace: '
                                                     'historyNamespace, current: history); historyFailure = '
                                                     'historyStore.failed\n'
                                                     '        } catch {\n'
                                                     '            guard gate.accepts(ticket, scope: reader.scope), '
                                                     'filter == query else { return }\n'
                                                     '            issue = SearchMapIssue.key(error)\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '}\n',
                                           'after': '    }\n'
                                                    '    private func search() async {\n'
                                                    '        let query = filter\n'
                                                    '        guard isVisible else { return }\n'
                                                    '        guard reader.isConfigured, query.canSearch else { return '
                                                    '}\n'
                                                    '        let captured = resultContext\n'
                                                    '        let ticket = retainedResults.begin(in: captured)\n'
                                                    '        loading = true; issue = nil\n'
                                                    '        do {\n'
                                                    '            let value = try await reader.search(query)\n'
                                                    '            guard !Task.isCancelled, isVisible, filter == query, '
                                                    'retainedResults.accepts(ticket, in: resultContext) else { return '
                                                    '}\n'
                                                    '            loading = false\n'
                                                    '            retainedResults.finish(value, ticket: ticket, in: '
                                                    'resultContext)\n'
                                                    '            history = historyStore.add(query.keyword, namespace: '
                                                    'historyNamespace, current: history); historyFailure = '
                                                    'historyStore.failed\n'
                                                    '        } catch {\n'
                                                    '            guard isVisible, retainedResults.accepts(ticket, in: '
                                                    'resultContext) else { return }\n'
                                                    '            loading = false\n'
                                                    '            retainedResults.fail(ticket, in: resultContext)\n'
                                                    '            if !(error is CancellationError) { issue = '
                                                    'SearchMapIssue.key(error) }\n'
                                                    '        }\n'
                                                    '    }\n'
                                                    '}\n'},
                                          {'before': 'import SwiftUI\n'
                                                     '\n'
                                                     '@MainActor struct GlobalSearchView<Destination: View>: View {\n'
                                                     '    let reader: any SearchMapReading\n'
                                                     '    var historyNamespace: String? = nil\n'
                                                     '    var publicMerchant = PublicMerchantHomeContext()\n'
                                                     '    var onSignIn: (() -> Void)? = nil\n'
                                                     '    let destination: (SearchMapDestination) -> Destination\n'
                                                     '    @State private var filter = GlobalSearchQuery()\n'
                                                     '    @State private var categories: [DiscoveryCategory] = []\n'
                                                     '    @State private var categoryFailed = false\n'
                                                     '    @State private var retainedResults = '
                                                     'GlobalSearchRetainedResults()\n'
                                                     '    @State private var isVisible = false\n'
                                                     '    @State private var issue: String?\n',
                                           'after': 'import SwiftUI\n'
                                                    '\n'
                                                    '@MainActor struct GlobalSearchView<Destination: View>: View {\n'
                                                    '    @Environment(\\.scenePhase) private var scenePhase\n'
                                                    '    let reader: any SearchMapReading\n'
                                                    '    var historyNamespace: String? = nil\n'
                                                    '    var publicMerchant = PublicMerchantHomeContext()\n'
                                                    '    var onSignIn: (() -> Void)? = nil\n'
                                                    '    let destination: (SearchMapDestination) -> Destination\n'
                                                    '    @State private var filter = GlobalSearchQuery()\n'
                                                    '    @State private var categoryRecovery = '
                                                    'SearchMapCategoryRecovery()\n'
                                                    '    @State private var categoryPresentationID = UUID()\n'
                                                    '    @State private var filterPresentationID = UUID()\n'
                                                    '    @State private var filterSheetVisible = false\n'
                                                    '    @State private var retainedResults = '
                                                    'GlobalSearchRetainedResults()\n'
                                                    '    @State private var isVisible = false\n'
                                                    '    @State private var issue: String?\n'},
                                          {'before': '    @State private var showsFilters = false\n'
                                                     '    @State private var history: [String] = []\n'
                                                     '    @State private var historyFailure = false\n'
                                                     '    @State private var categoryGate = SearchMapQueryGate()\n'
                                                     '    @State private var preparedOwner: ReadOwner?\n'
                                                     '    private let historyStore = SearchMapLocalHistory()\n'
                                                     '\n',
                                           'after': '    @State private var showsFilters = false\n'
                                                    '    @State private var history: [String] = []\n'
                                                    '    @State private var historyFailure = false\n'
                                                    '    @State private var preparedOwner: ReadOwner?\n'
                                                    '    private let historyStore = SearchMapLocalHistory()\n'
                                                    '\n'},
                                          {'before': '                    TextField("searchMap.placeholder", text: '
                                                     'Binding(get: { filter.keyword }, set: '
                                                     'setKeyword)).textInputAutocapitalization(.never)\n'
                                                     '                        .submitLabel(.search).onSubmit { Task { '
                                                     'await search() } }\n'
                                                     '                        '
                                                     '.accessibilityIdentifier("searchMap.keyword")\n'
                                                     '                    Button { showsFilters = true } label: { '
                                                     'Label("searchMap.filters", systemImage: '
                                                     '"line.3.horizontal.decrease") }\n'
                                                     '                        .labelStyle(.iconOnly).frame(minWidth: '
                                                     '44, minHeight: 44).accessibilityIdentifier("searchMap.filters")\n'
                                                     '                '
                                                     '}.padding(12).background(.secondary.opacity(0.08), in: '
                                                     'RoundedRectangle(cornerRadius: 16))\n'
                                                     '                Button("searchMap.search") { Task { await '
                                                     'search() } }\n',
                                           'after': '                    TextField("searchMap.placeholder", text: '
                                                    'Binding(get: { filter.keyword }, set: '
                                                    'setKeyword)).textInputAutocapitalization(.never)\n'
                                                    '                        .submitLabel(.search).onSubmit { Task { '
                                                    'await search() } }\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("searchMap.keyword")\n'
                                                    '                    Button { openFilters() } label: { '
                                                    'Label("searchMap.filters", systemImage: '
                                                    '"line.3.horizontal.decrease") }\n'
                                                    '                        .labelStyle(.iconOnly).frame(minWidth: '
                                                    '44, minHeight: 44).accessibilityIdentifier("searchMap.filters")\n'
                                                    '                '
                                                    '}.padding(12).background(.secondary.opacity(0.08), in: '
                                                    'RoundedRectangle(cornerRadius: 16))\n'
                                                    '                Button("searchMap.search") { Task { await '
                                                    'search() } }\n'},
                                          {'before': '        }\n'
                                                     '        .appNavigationTitle("searchMap.title")\n'
                                                     '        .sheet(isPresented: $showsFilters) {\n'
                                                     '            SearchMapFilterSheet(filter: filter, categories: '
                                                     'categories, categoryFailed: categoryFailed) { next in\n'
                                                     '                applyFilter(next)\n'
                                                     '            }\n'
                                                     '        }\n'
                                                     '        .task(id: readOwner) { await prepare() }\n'
                                                     '        .onAppear { isVisible = true }\n'
                                                     '        .onDisappear { isVisible = false; '
                                                     'retainedResults.cancelPending(); categoryGate.invalidate(); '
                                                     'loading = false }\n'
                                                     '    }\n'
                                                     '    @ViewBuilder private var suggestions: some View {\n'
                                                     '        if !history.isEmpty {\n'
                                                     '            HStack {\n'
                                                     '                Text("searchMap.history").font(.headline)\n',
                                           'after': '        }\n'
                                                    '        .appNavigationTitle("searchMap.title")\n'
                                                    '        .sheet(isPresented: $showsFilters) {\n'
                                                    '            let presentationID = filterPresentationID\n'
                                                    '            let context = categoryRecovery.context(for: '
                                                    'categoryOwner)\n'
                                                    '            let applyContext = '
                                                    'categoryRecovery.presentationContext(for: categoryOwner)\n'
                                                    '            SearchMapFilterSheet(filter: filter, categories: '
                                                    'categories, categoryFailed: categoryFailed,\n'
                                                    '                                 categoryLoading: '
                                                    'categoryLoading, categoryLoaded: categoryLoaded,\n'
                                                    '                                 retryCategories: context.map { '
                                                    'captured in {\n'
                                                    '                                     guard showsFilters, '
                                                    'filterSheetVisible, presentationID == filterPresentationID else { '
                                                    'return }\n'
                                                    '                                     _ = '
                                                    'categoryRecovery.retry(in: captured)\n'
                                                    '                                 } }) { next in\n'
                                                    '                guard showsFilters, filterSheetVisible, '
                                                    'presentationID == filterPresentationID,\n'
                                                    '                      let applyContext, '
                                                    'categoryRecovery.acceptsPresentation(applyContext) else { return '
                                                    '}\n'
                                                    '                applyFilter(next)\n'
                                                    '            }\n'
                                                    '            .onAppear {\n'
                                                    '                guard showsFilters, presentationID == '
                                                    'filterPresentationID, categoryRecovery.owns(categoryOwner) else { '
                                                    'return }\n'
                                                    '                filterSheetVisible = true; '
                                                    'updateCategoryPresentation()\n'
                                                    '            }\n'
                                                    '            .onDisappear {\n'
                                                    '                guard presentationID == filterPresentationID, '
                                                    'categoryRecovery.owns(categoryOwner) else { return }\n'
                                                    '                filterSheetVisible = false; '
                                                    'updateCategoryPresentation()\n'
                                                    '            }\n'
                                                    '        }\n'
                                                    '        .task(id: readOwner) { await prepare() }\n'
                                                    '        .onChange(of: categoryOwner) { _, _ in '
                                                    'updateCategoryPresentation() }\n'
                                                    '        .onChange(of: scenePhase) { _, _ in '
                                                    'updateCategoryPresentation() }\n'
                                                    '        .onChange(of: showsFilters) { _, visible in\n'
                                                    '            if !visible { filterSheetVisible = false }\n'
                                                    '            updateCategoryPresentation()\n'
                                                    '        }\n'
                                                    '        .onAppear { isVisible = true; categoryPresentationID = '
                                                    'UUID(); updateCategoryPresentation() }\n'
                                                    '        .onDisappear {\n'
                                                    '            isVisible = false; retainedResults.cancelPending(); '
                                                    'loading = false\n'
                                                    '            categoryRecovery.update(reader: reader, '
                                                    'presentationID: nil, active: false)\n'
                                                    '        }\n'
                                                    '    }\n'
                                                    '    private var categoryOwner: SearchMapCategoryRecovery.Owner { '
                                                    '.init(reader: reader) }\n'
                                                    '    private var categories: [DiscoveryCategory] { '
                                                    'categoryRecovery.owns(categoryOwner) ? '
                                                    'categoryRecovery.categories : [] }\n'
                                                    '    private var categoryFailed: Bool { '
                                                    'categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == '
                                                    '.failed }\n'
                                                    '    private var categoryLoading: Bool { '
                                                    'categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == '
                                                    '.loading }\n'
                                                    '    private var categoryLoaded: Bool { '
                                                    'categoryRecovery.owns(categoryOwner) && categoryRecovery.phase == '
                                                    '.loaded }\n'
                                                    '    private func openFilters() {\n'
                                                    '        filterPresentationID = UUID(); filterSheetVisible = '
                                                    'false; showsFilters = true\n'
                                                    '        updateCategoryPresentation()\n'
                                                    '    }\n'
                                                    '    private func updateCategoryPresentation() {\n'
                                                    '        // The page and sheet share the directory, never a draft '
                                                    'or search request.\n'
                                                    '        // Switching surfaces retires callbacks; a settled '
                                                    'directory survives reopening.\n'
                                                    '        let presentationID = showsFilters ? (filterSheetVisible ? '
                                                    'filterPresentationID : nil) : categoryPresentationID\n'
                                                    '        categoryRecovery.update(reader: reader, presentationID: '
                                                    'presentationID,\n'
                                                    '                                active: isVisible && scenePhase '
                                                    '== .active)\n'
                                                    '        if let context = categoryRecovery.context(for: '
                                                    'categoryOwner) {\n'
                                                    '            categoryRecovery.loadIfNeeded(in: context)\n'
                                                    '        }\n'
                                                    '    }\n'
                                                    '    @ViewBuilder private var suggestions: some View {\n'
                                                    '        let context = categoryRecovery.context(for: '
                                                    'categoryOwner)\n'
                                                    '        if !history.isEmpty {\n'
                                                    '            HStack {\n'
                                                    '                Text("searchMap.history").font(.headline)\n'},
                                          {'before': '            }\n'
                                                     '        }\n'
                                                     '        Text("searchMap.categories").font(.headline)\n'
                                                     '        if categoryFailed { SearchMapIssue(key: '
                                                     '"searchMap.categoryFailed") { Task { await prepare(force: true) '
                                                     '} } }\n'
                                                     '        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], '
                                                     'spacing: 12) {\n'
                                                     '            ForEach(categories) { category in\n'
                                                     '                Button {\n'
                                                     '                    var next = filter; next.categoryID = '
                                                     'category.id; applyFilter(next)\n'
                                                     '                } label: {\n'
                                                     '                    Text(verbatim: '
                                                     'category.name).frame(maxWidth: .infinity, minHeight: 44)\n',
                                           'after': '            }\n'
                                                    '        }\n'
                                                    '        Text("searchMap.categories").font(.headline)\n'
                                                    '        if categoryLoading {\n'
                                                    '            '
                                                    'ProgressView("searchMap.loading").accessibilityIdentifier("globalSearch.category.loading")\n'
                                                    '        } else if categoryFailed {\n'
                                                    '            SearchMapIssue(key: "searchMap.categoryFailed") {\n'
                                                    '                guard !showsFilters, let context else { return }\n'
                                                    '                _ = categoryRecovery.retry(in: context)\n'
                                                    '            }\n'
                                                    '        }\n'
                                                    '        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], '
                                                    'spacing: 12) {\n'
                                                    '            ForEach(categories) { category in\n'
                                                    '                Button {\n'
                                                    '                    guard !showsFilters, let context, '
                                                    'categoryRecovery.accepts(context) else { return }\n'
                                                    '                    var next = filter; next.categoryID = '
                                                    'category.id; applyFilter(next)\n'
                                                    '                } label: {\n'
                                                    '                    Text(verbatim: category.name).frame(maxWidth: '
                                                    '.infinity, minHeight: 44)\n'},
                                          {'before': '        invalidate(); filter.keyword = value\n'
                                                     '    }\n'
                                                     '    private func invalidate() { retainedResults.invalidate(); '
                                                     'issue = nil; loading = false; selectedKind = nil }\n'
                                                     '    private func prepare(force: Bool = false) async {\n'
                                                     '        if preparedOwner != readOwner {\n'
                                                     '            preparedOwner = readOwner; invalidate(); categories '
                                                     '= []; categoryFailed = false\n'
                                                     '            history = historyStore.read(namespace: '
                                                     'historyNamespace); historyFailure = historyStore.failed\n'
                                                     '        }\n'
                                                     '        guard reader.isConfigured, force || categories.isEmpty '
                                                     'else { return }\n'
                                                     '        let ticket = categoryGate.begin(scope: reader.scope)\n'
                                                     '        do {\n'
                                                     '            let value = try await reader.categories()\n'
                                                     '            guard categoryGate.accepts(ticket, scope: '
                                                     'reader.scope) else { return }; categories = value; '
                                                     'categoryFailed = false\n'
                                                     '        } catch {\n'
                                                     '            guard categoryGate.accepts(ticket, scope: '
                                                     'reader.scope) else { return }; categoryFailed = true\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '    private func search() async {\n'
                                                     '        let query = filter\n',
                                           'after': '        invalidate(); filter.keyword = value\n'
                                                    '    }\n'
                                                    '    private func invalidate() { retainedResults.invalidate(); '
                                                    'issue = nil; loading = false; selectedKind = nil }\n'
                                                    '    private func prepare() async {\n'
                                                    '        guard !Task.isCancelled else { return }\n'
                                                    '        if preparedOwner != readOwner {\n'
                                                    '            preparedOwner = readOwner; invalidate()\n'
                                                    '            history = historyStore.read(namespace: '
                                                    'historyNamespace); historyFailure = historyStore.failed\n'
                                                    '        }\n'
                                                    '        updateCategoryPresentation()\n'
                                                    '    }\n'
                                                    '    private func search() async {\n'
                                                    '        let query = filter\n'}]},
 'Core/SearchMapReading.swift': {'before_sha256': '2089e1dd5f41c81411472acfe8caf0f18e51693dd2c8ca390dde074409cde017',
                                 'after_sha256': '34c67b5893b5ebba2eec8fdfc468a9b1662f4b94f86936d63d755385954d9aad',
                                 'hunks': [{'before': '    func categories() async throws -> [DiscoveryCategory]\n'
                                                      '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                      'throws -> [MerchantDiscoveryRow]\n'
                                                      '    func search(_ query: GlobalSearchQuery) async throws -> '
                                                      'GlobalSearchResults\n'
                                                      '    func citySearch(_ query: CityNodeSearchQuery) async throws '
                                                      '-> CityNodeSearchResults\n'
                                                      '    func cityActivityPage(_ query: CityNodeSearchQuery, page: '
                                                      'Int) async throws -> SearchMapActivityPage\n'
                                                      '    func nearby(area: RoamSearchArea) async throws -> '
                                                      'SearchMapNearbyResults\n',
                                            'after': '    func categories() async throws -> [DiscoveryCategory]\n'
                                                     '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                     'throws -> [MerchantDiscoveryRow]\n'
                                                     '    func search(_ query: GlobalSearchQuery) async throws -> '
                                                     'GlobalSearchResults\n'
                                                     '    func cityNodes(_ query: CityNodeSearchQuery) async throws -> '
                                                     '[SearchMapCityNode]\n'
                                                     '    func citySearch(_ query: CityNodeSearchQuery) async throws '
                                                     '-> CityNodeSearchResults\n'
                                                     '    func cityActivityPage(_ query: CityNodeSearchQuery, page: '
                                                     'Int) async throws -> SearchMapActivityPage\n'
                                                     '    func nearby(area: RoamSearchArea) async throws -> '
                                                     'SearchMapNearbyResults\n'},
                                           {'before': '}\n'
                                                      '/// Older fixture readers have no discovery data; do not invent '
                                                      'empty successful results.\n'
                                                      'public extension SearchMapReading {\n'
                                                      '    var manualAreaRevision: UInt64 { 0 }\n'
                                                      '    func selectManualArea(_ area: RoamSearchArea?) {}\n'
                                                      '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                      'throws -> [MerchantDiscoveryRow] { throw APIError.notConfigured '
                                                      '}\n',
                                            'after': '}\n'
                                                     '/// Older fixture readers have no discovery data; do not invent '
                                                     'empty successful results.\n'
                                                     'public extension SearchMapReading {\n'
                                                     '    func cityNodes(_ query: CityNodeSearchQuery) async throws -> '
                                                     '[SearchMapCityNode] { throw APIError.notConfigured }\n'
                                                     '    var manualAreaRevision: UInt64 { 0 }\n'
                                                     '    func selectManualArea(_ area: RoamSearchArea?) {}\n'
                                                     '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                     'throws -> [MerchantDiscoveryRow] { throw APIError.notConfigured '
                                                     '}\n'},
                                           {'before': '            if token != nil, !result.gatedKinds.isEmpty { throw '
                                                      'APIError.unauthorized }\n'
                                                      '            return result\n'
                                                      '        }\n'
                                                      '    }\n'
                                                      '    public func citySearch(_ query: CityNodeSearchQuery) async '
                                                      'throws -> CityNodeSearchResults {\n'
                                                      '        manualAreaSelection?.ensureSelected(query.area)\n',
                                            'after': '            if token != nil, !result.gatedKinds.isEmpty { throw '
                                                     'APIError.unauthorized }\n'
                                                     '            return result\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '    public func cityNodes(_ query: CityNodeSearchQuery) async '
                                                     'throws -> [SearchMapCityNode] {\n'
                                                     '        // Injection does not activate an unapproved reader.\n'
                                                     '        guard currentContext().manualMapApprovalRevision != nil '
                                                     'else { throw APIError.notConfigured }\n'
                                                     '        manualAreaSelection?.ensureSelected(query.area)\n'
                                                     '        return try await read { try await $0.cityNodes(query, '
                                                     'token: $1) }\n'
                                                     '    }\n'
                                                     '    public func citySearch(_ query: CityNodeSearchQuery) async '
                                                     'throws -> CityNodeSearchResults {\n'
                                                     '        manualAreaSelection?.ensureSelected(query.area)\n'},
                                           {'before': '    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool '
                                                      '{ generation == ticket.generation && ticket.scope == scope && '
                                                      '!Task.isCancelled }\n'
                                                      '    public func invalidate() { generation &+= 1 }\n'
                                                      '}\n',
                                            'after': '    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { '
                                                     'generation == ticket.generation && ticket.scope == scope && '
                                                     '!Task.isCancelled }\n'
                                                     '    public func invalidate() { generation &+= 1 }\n'
                                                     '}\n'
                                                     '\n'
                                                     'import Observation\n'
                                                     '\n'
                                                     '/// Read-only category directory for one visible filter '
                                                     'presentation. The directory\n'
                                                     '/// never owns a query/draft, applies filters, or grants any '
                                                     'reader capability.\n'
                                                     '@Observable @MainActor public final class '
                                                     'SearchMapCategoryRecovery {\n'
                                                     '    public enum Phase: Equatable { case idle, loading, loaded, '
                                                     'failed }\n'
                                                     '    public struct Owner: Hashable {\n'
                                                     '        public let readerID: ObjectIdentifier\n'
                                                     '        public let scope: UUID\n'
                                                     '        public let configured: Bool\n'
                                                     '        public let authenticated: Bool\n'
                                                     '        public let manualAreaRevision: UInt64\n'
                                                     '        @MainActor public init(reader: any SearchMapReading) {\n'
                                                     '            readerID = ObjectIdentifier(reader); scope = '
                                                     'reader.scope\n'
                                                     '            configured = reader.isConfigured; authenticated = '
                                                     'reader.isAuthenticated\n'
                                                     '            manualAreaRevision = reader.manualAreaRevision\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '    public struct Context: Equatable {\n'
                                                     '        fileprivate let owner: Owner\n'
                                                     '        fileprivate let presentationID: UUID\n'
                                                     '        fileprivate let generation: UUID\n'
                                                     '    }\n'
                                                     '    public private(set) var categories: [DiscoveryCategory] = '
                                                     '[]\n'
                                                     '    public private(set) var phase: Phase = .idle\n'
                                                     '    private var settledPhase: Phase = .idle\n'
                                                     '    private var owner: Owner?\n'
                                                     '    private var presentationID: UUID?\n'
                                                     '    private var active = false\n'
                                                     '    private var generation = UUID()\n'
                                                     '    private var pending: UUID?\n'
                                                     '    @ObservationIgnored private weak var reader: (any '
                                                     'SearchMapReading)?\n'
                                                     '    @ObservationIgnored private var task: Task<Void, Never>?\n'
                                                     '    public init() {}\n'
                                                     '    deinit { task?.cancel() }\n'
                                                     '\n'
                                                     '    /// Every observed lifetime transition retires old '
                                                     'callbacks, including A/B/A.\n'
                                                     '    /// Reopening keeps a settled same-owner directory; '
                                                     'interrupted reads may resume.\n'
                                                     '    public func update(reader: any SearchMapReading, '
                                                     'presentationID: UUID?, active: Bool) {\n'
                                                     '        let next = Owner(reader: reader)\n'
                                                     '        if owner != next || self.presentationID != '
                                                     'presentationID || self.active != active {\n'
                                                     '            generation = UUID(); task?.cancel(); task = nil; '
                                                     'pending = nil\n'
                                                     '            if owner != next { categories = []; settledPhase = '
                                                     '.idle }\n'
                                                     '            phase = settledPhase\n'
                                                     '        }\n'
                                                     '        self.reader = reader; owner = next\n'
                                                     '        self.presentationID = presentationID; self.active = '
                                                     'active\n'
                                                     '    }\n'
                                                     '    public func owns(_ current: Owner) -> Bool {\n'
                                                     '        guard let reader else { return false }\n'
                                                     '        return owner == current && Owner(reader: reader) == '
                                                     'current\n'
                                                     '    }\n'
                                                     '    /// Local filter edits require a current presentation, not a '
                                                     'network capability.\n'
                                                     '    public func presentationContext(for current: Owner) -> '
                                                     'Context? {\n'
                                                     '        guard active, owns(current), let presentationID else { '
                                                     'return nil }\n'
                                                     '        return Context(owner: current, presentationID: '
                                                     'presentationID, generation: generation)\n'
                                                     '    }\n'
                                                     '    public func acceptsPresentation(_ context: Context) -> Bool '
                                                     '{\n'
                                                     '        self.presentationContext(for: context.owner) == context\n'
                                                     '    }\n'
                                                     '    /// A local Apply context must never authorize a category '
                                                     'read while unconfigured.\n'
                                                     '    public func context(for current: Owner) -> Context? {\n'
                                                     '        guard current.configured else { return nil }\n'
                                                     '        return presentationContext(for: current)\n'
                                                     '    }\n'
                                                     '    public func accepts(_ context: Context) -> Bool {\n'
                                                     '        self.context(for: context.owner) == context\n'
                                                     '    }\n'
                                                     '    @discardableResult public func loadIfNeeded(in context: '
                                                     'Context) -> Task<Void, Never>? {\n'
                                                     '        guard phase == .idle else { return nil }\n'
                                                     '        return begin(in: context)\n'
                                                     '    }\n'
                                                     '    @discardableResult public func retry(in context: Context) -> '
                                                     'Task<Void, Never>? {\n'
                                                     '        guard phase == .failed else { return nil }\n'
                                                     '        return begin(in: context)\n'
                                                     '    }\n'
                                                     '    private func begin(in context: Context) -> Task<Void, '
                                                     'Never>? {\n'
                                                     '        guard !Task.isCancelled, pending == nil, '
                                                     'accepts(context), let reader else { return nil }\n'
                                                     '        let requestID = UUID()\n'
                                                     '        // Acquire the single-flight slot before queuing '
                                                     'asynchronous work.\n'
                                                     '        pending = requestID; phase = .loading\n'
                                                     '        let request = Task { [weak self, weak reader] in\n'
                                                     '            defer { self?.finishPending(requestID) }\n'
                                                     '            guard !Task.isCancelled, let reader, '
                                                     'self?.accepts(context) == true else { return }\n'
                                                     '            do {\n'
                                                     '                let values = try await reader.categories()\n'
                                                     '                guard !Task.isCancelled, let self, self.pending '
                                                     '== requestID, self.accepts(context) else { return }\n'
                                                     '                self.categories = values // An authoritative '
                                                     'empty array is a successful directory.\n'
                                                     '                self.settledPhase = .loaded; self.phase = '
                                                     '.loaded\n'
                                                     '            } catch is CancellationError {\n'
                                                     '                // Cancellation restores the previous state; it '
                                                     'is not a new failure.\n'
                                                     '            } catch {\n'
                                                     '                guard !Task.isCancelled, let self, self.pending '
                                                     '== requestID, self.accepts(context) else { return }\n'
                                                     '                self.settledPhase = .failed; self.phase = '
                                                     '.failed\n'
                                                     '            }\n'
                                                     '        }\n'
                                                     '        task = request\n'
                                                     '        return request\n'
                                                     '    }\n'
                                                     '    private func finishPending(_ requestID: UUID) {\n'
                                                     '        guard pending == requestID else { return }\n'
                                                     '        pending = nil; task = nil\n'
                                                     '        if phase == .loading { phase = settledPhase }\n'
                                                     '    }\n'
                                                     '}\n'}]},
 'App/SearchMapFilterSheet.swift': {'before_sha256': '33348878001340ef3962016363280702c5be0b2377e0af6be881da7855512871',
                                    'after_sha256': 'd805599b752fcd104e40b382fb30d5bc96b9f8f27622766bfaefeed402c07b54',
                                    'hunks': [{'before': '                    if categoryFailed { '
                                                         'Text("searchMap.categoryFailed").font(.caption) }\n'
                                                         '                }\n'
                                                         '                Section("searchMap.dates") {\n'
                                                         '                    if applyCityOptions != nil {\n'
                                                         '                        Button("mapDatePreset.today") { '
                                                         'selectDatePreset(.today) }\n'
                                                         '                            .frame(minHeight: '
                                                         '44).accessibilityIdentifier("mapDatePreset.today")\n'
                                                         '                        Button("mapDatePreset.tomorrow") { '
                                                         'selectDatePreset(.tomorrow) }\n'
                                                         '                            .frame(minHeight: '
                                                         '44).accessibilityIdentifier("mapDatePreset.tomorrow")\n'
                                                         '                        '
                                                         'Text("mapDatePreset.disclosure").font(.footnote).foregroundStyle(.secondary)\n'
                                                         '                    }\n'
                                                         '                    TextField("searchMap.startDate", text: '
                                                         '$dateDraft.startDate).accessibilityIdentifier("searchMap.filter.start")\n'
                                                         '                    Button("mapDatePicker.start") { '
                                                         'openDatePicker(.start) }\n',
                                               'after': '                    if categoryFailed { '
                                                        'Text("searchMap.categoryFailed").font(.caption) }\n'
                                                        '                }\n'
                                                        '                Section("searchMap.dates") {\n'
                                                        '                    Button("mapDatePreset.today") { '
                                                        'selectDatePreset(.today) }\n'
                                                        '                        .frame(minHeight: '
                                                        '44).accessibilityIdentifier("mapDatePreset.today")\n'
                                                        '                    Button("mapDatePreset.tomorrow") { '
                                                        'selectDatePreset(.tomorrow) }\n'
                                                        '                        .frame(minHeight: '
                                                        '44).accessibilityIdentifier("mapDatePreset.tomorrow")\n'
                                                        '                    if applyCityOptions != nil {\n'
                                                        '                        '
                                                        'Text("mapDatePreset.disclosure").font(.footnote).foregroundStyle(.secondary)\n'
                                                        '                    } else {\n'
                                                        '                        '
                                                        'Text("globalDatePreset.disclosure").font(.footnote).foregroundStyle(.secondary)\n'
                                                        '                    }\n'
                                                        '                    TextField("searchMap.startDate", text: '
                                                        '$dateDraft.startDate).accessibilityIdentifier("searchMap.filter.start")\n'
                                                        '                    Button("mapDatePicker.start") { '
                                                        'openDatePicker(.start) }\n'},
                                              {'before': '    let applyCityOptions: ((String, String, Int) -> Void)?\n'
                                                         '    let categories: [DiscoveryCategory]\n'
                                                         '    let categoryFailed: Bool\n'
                                                         '    let apply: (GlobalSearchQuery) -> Void\n'
                                                         '    init(filter: GlobalSearchQuery, categories: '
                                                         '[DiscoveryCategory], categoryFailed: Bool,\n'
                                                         '         tag: String = "", cityRole: String = "", sortType: '
                                                         'Int = 1,\n'
                                                         '         applyCityOptions: ((String, String, Int) -> Void)? '
                                                         '= nil, apply: @escaping (GlobalSearchQuery) -> Void) {\n'
                                                         '        _draft = State(initialValue: filter)\n',
                                               'after': '    let applyCityOptions: ((String, String, Int) -> Void)?\n'
                                                        '    let categories: [DiscoveryCategory]\n'
                                                        '    let categoryFailed: Bool\n'
                                                        '    let categoryLoading: Bool\n'
                                                        '    let categoryLoaded: Bool\n'
                                                        '    let retryCategories: (() -> Void)?\n'
                                                        '    let apply: (GlobalSearchQuery) -> Void\n'
                                                        '    init(filter: GlobalSearchQuery, categories: '
                                                        '[DiscoveryCategory], categoryFailed: Bool,\n'
                                                        '         categoryLoading: Bool = false, categoryLoaded: Bool '
                                                        '= false, retryCategories: (() -> Void)? = nil,\n'
                                                        '         tag: String = "", cityRole: String = "", sortType: '
                                                        'Int = 1,\n'
                                                        '         applyCityOptions: ((String, String, Int) -> Void)? = '
                                                        'nil, apply: @escaping (GlobalSearchQuery) -> Void) {\n'
                                                        '        _draft = State(initialValue: filter)\n'},
                                              {'before': '        _maximum = State(initialValue: '
                                                         'filter.maximumPrice.map { String($0) } ?? "")\n'
                                                         '        _dateDraft = State(initialValue: '
                                                         'SearchMapDateFilterDraft(filter: filter))\n'
                                                         '        self.categories = categories; self.categoryFailed = '
                                                         'categoryFailed; self.apply = apply\n'
                                                         '    }\n'
                                                         '    var body: some View {\n'
                                                         '        NavigationStack {\n',
                                               'after': '        _maximum = State(initialValue: '
                                                        'filter.maximumPrice.map { String($0) } ?? "")\n'
                                                        '        _dateDraft = State(initialValue: '
                                                        'SearchMapDateFilterDraft(filter: filter))\n'
                                                        '        self.categories = categories; self.categoryFailed = '
                                                        'categoryFailed; self.apply = apply\n'
                                                        '        self.categoryLoading = categoryLoading; '
                                                        'self.categoryLoaded = categoryLoaded; self.retryCategories = '
                                                        'retryCategories\n'
                                                        '    }\n'
                                                        '    var body: some View {\n'
                                                        '        NavigationStack {\n'},
                                              {'before': '                    Picker("searchMap.category", selection: '
                                                         '$draft.categoryID) {\n'
                                                         '                        '
                                                         'Text("searchMap.all").tag(Int?.none)\n'
                                                         '                        ForEach(categories) { Text(verbatim: '
                                                         '$0.name).tag(Optional($0.id)) }\n'
                                                         '                    }\n'
                                                         '                    '
                                                         '.accessibilityIdentifier("searchMap.filter.category")\n'
                                                         '                    if categoryFailed { '
                                                         'Text("searchMap.categoryFailed").font(.caption) }\n'
                                                         '                }\n'
                                                         '                Section("searchMap.dates") {\n'
                                                         '                    Button("mapDatePreset.today") { '
                                                         'selectDatePreset(.today) }\n',
                                               'after': '                    Picker("searchMap.category", selection: '
                                                        '$draft.categoryID) {\n'
                                                        '                        Text("searchMap.all").tag(Int?.none)\n'
                                                        '                        ForEach(categories) { Text(verbatim: '
                                                        '$0.name).tag(Optional($0.id)) }\n'
                                                        '                        // Keep an explicit tag for a '
                                                        'selection missing from the new directory.\n'
                                                        "                        // Only the user's "
                                                        'selection/reset/Apply may change this manual draft.\n'
                                                        '                        if let selectedID = draft.categoryID, '
                                                        '!categories.contains(where: { $0.id == selectedID }) {\n'
                                                        '                            (Text("searchMap.category") + '
                                                        'Text(verbatim: " #\\(selectedID)"))\n'
                                                        '                                .tag(Optional(selectedID))\n'
                                                        '                        }\n'
                                                        '                    }\n'
                                                        '                    '
                                                        '.accessibilityIdentifier("searchMap.filter.category")\n'
                                                        '                    if categoryLoading {\n'
                                                        '                        '
                                                        'ProgressView("searchMap.loading").accessibilityIdentifier("searchMap.category.loading")\n'
                                                        '                    } else if categoryFailed {\n'
                                                        '                        '
                                                        'Text("searchMap.categoryFailed").font(.caption)\n'
                                                        '                            '
                                                        '.accessibilityIdentifier("searchMap.category.failed")\n'
                                                        '                        if let retryCategories {\n'
                                                        '                            Button("searchMap.retry", action: '
                                                        'retryCategories).frame(minHeight: 44)\n'
                                                        '                                '
                                                        '.accessibilityIdentifier("searchMap.category.retry")\n'
                                                        '                        }\n'
                                                        '                    } else if categoryLoaded && '
                                                        'categories.isEmpty {\n'
                                                        '                        '
                                                        'Text("searchMap.empty").font(.caption)\n'
                                                        '                            '
                                                        '.accessibilityIdentifier("searchMap.category.empty")\n'
                                                        '                    }\n'
                                                        '                }\n'
                                                        '                Section("searchMap.dates") {\n'
                                                        '                    Button("mapDatePreset.today") { '
                                                        'selectDatePreset(.today) }\n'}]},
 'App/RoamHistoryViews.swift': {'before_sha256': '1926c84b140127cb8f4c65aae81e7305dfb730b1f219459e4b05001baefe4751',
                                'after_sha256': '2a4d67bbb003df0646599c911ae8c2ac6e20b99e2af7ae81f89be384af608172',
                                'hunks': [{'before': '\n'
                                                     '@MainActor struct RoamHistoryView: View {\n'
                                                     '    let reader: any RoamExperienceReading\n'
                                                     '    @State private var records: [RoamHistoryRecord] = []\n'
                                                     '    @State private var error: Error?\n'
                                                     '    @State private var loaded = false\n'
                                                     '    var body: some View {\n'
                                                     '        ScrollView {\n'
                                                     '            LazyVStack(alignment: .leading, spacing: 16) {\n',
                                           'after': '\n'
                                                    '@MainActor struct RoamHistoryView: View {\n'
                                                    '    let reader: any RoamExperienceReading\n'
                                                    '    var liveDestination: (() -> AnyView)? = nil\n'
                                                    '    @State private var records: [RoamHistoryRecord] = []\n'
                                                    '    @State private var error: Error?\n'
                                                    '    @State private var loaded = false\n'
                                                    '    @State private var liveEntry = RoamHistoryLiveEntry()\n'
                                                    '    var body: some View {\n'
                                                    '        ScrollView {\n'
                                                    '            LazyVStack(alignment: .leading, spacing: 16) {\n'},
                                          {'before': '                    '
                                                     'ContentUnavailableView("roam.experience.historyEmpty", '
                                                     'systemImage: "figure.walk", description: '
                                                     'Text("roam.experience.historyEmptyHint"))\n'
                                                     '                        .accessibilityElement(children: '
                                                     '.contain)\n'
                                                     '                        '
                                                     '.accessibilityIdentifier("roam.experience.history.empty")\n'
                                                     '                } else {\n'
                                                     '                    let summary = RoamHistorySummary(records)\n'
                                                     '                    RoamExperienceCard {\n',
                                           'after': '                    '
                                                    'ContentUnavailableView("roam.experience.historyEmpty", '
                                                    'systemImage: "figure.walk", description: '
                                                    'Text("roam.experience.historyEmptyHint"))\n'
                                                    '                        .accessibilityElement(children: '
                                                    '.contain)\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("roam.experience.history.empty")\n'
                                                    '                    if liveEntry.canOpen(reader: reader, '
                                                    'hasDestination: liveDestination != nil) {\n'
                                                    '                        let presentationID = '
                                                    'liveEntry.presentationID\n'
                                                    '                        Button("roam.experience.live", '
                                                    'systemImage: "figure.walk") {\n'
                                                    '                            liveEntry.activate(reader: reader, '
                                                    'hasDestination: liveDestination != nil, presentationID: '
                                                    'presentationID)\n'
                                                    '                        }\n'
                                                    '                        .buttonStyle(.borderedProminent)\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("roam.experience.history.live.open")\n'
                                                    '                    }\n'
                                                    '                } else {\n'
                                                    '                    let summary = RoamHistorySummary(records)\n'
                                                    '                    RoamExperienceCard {\n'},
                                          {'before': '                }\n'
                                                     '            }.padding()\n'
                                                     '        }.navigationTitle("roam.experience.history")\n'
                                                     '            .task(id: reader.identity) { load() }\n'
                                                     '            .accessibilityIdentifier("roam.experience.history")\n'
                                                     '    }\n'
                                                     '    private func load() {\n'
                                                     '        records = []; error = nil; loaded = false\n'
                                                     '        do { records = try reader.history(); loaded = true } '
                                                     'catch { self.error = error }\n'
                                                     '    }\n'
                                                     '}\n'
                                                     '@MainActor struct RoamHistoryDetailView: View {\n',
                                           'after': '                }\n'
                                                    '            }.padding()\n'
                                                    '        }.navigationTitle("roam.experience.history")\n'
                                                    '            .task(id: RoamHistoryLiveOwner(reader: reader)) { '
                                                    'load() }\n'
                                                    '            .onAppear { liveEntry.appear() }\n'
                                                    '            .onDisappear { liveEntry.disappear() }\n'
                                                    '            .onChange(of: RoamHistoryLiveOwner(reader: reader)) { '
                                                    '_, _ in\n'
                                                    '                liveEntry.retireIfOwnerChanged(reader: reader, '
                                                    'hasDestination: liveDestination != nil)\n'
                                                    '            }\n'
                                                    '            .onChange(of: liveDestination != nil) { _, _ in\n'
                                                    '                liveEntry.retireIfOwnerChanged(reader: reader, '
                                                    'hasDestination: liveDestination != nil)\n'
                                                    '            }\n'
                                                    '            .navigationDestination(item: $liveEntry.target) { '
                                                    'target in\n'
                                                    '                if liveEntry.matches(target, reader: reader, '
                                                    'hasDestination: liveDestination != nil), let liveDestination {\n'
                                                    '                    liveDestination()\n'
                                                    '                }\n'
                                                    '            }\n'
                                                    '            .accessibilityIdentifier("roam.experience.history")\n'
                                                    '    }\n'
                                                    '    private func load() {\n'
                                                    '        records = []; error = nil; loaded = false\n'
                                                    '        let snapshot = liveEntry.beginRead(reader: reader)\n'
                                                    '        do {\n'
                                                    '            records = try reader.history(); loaded = true\n'
                                                    '            liveEntry.acceptRead(isEmpty: records.isEmpty, '
                                                    'snapshot: snapshot, reader: reader)\n'
                                                    '        } catch { self.error = error }\n'
                                                    '    }\n'
                                                    '}\n'
                                                    '\n'
                                                    '/// This only selects the already supplied live screen. It never '
                                                    'creates or starts a roam session.\n'
                                                    'struct RoamHistoryLiveOwner: Equatable, Hashable {\n'
                                                    '    let readerID: ObjectIdentifier\n'
                                                    '    let scopeKey: String?\n'
                                                    '    let epoch: UInt64?\n'
                                                    '    let isConfigured: Bool\n'
                                                    '    @MainActor init(reader: any RoamExperienceReading) {\n'
                                                    '        let identity = reader.identity\n'
                                                    '        readerID = ObjectIdentifier(reader)\n'
                                                    '        // storageKey preserves the exact UTF-8 namespace, '
                                                    'market, deployment and account bytes.\n'
                                                    '        scopeKey = identity?.scope.storageKey\n'
                                                    '        epoch = identity?.epoch\n'
                                                    '        isConfigured = reader.isConfigured\n'
                                                    '    }\n'
                                                    '    var isAuthorized: Bool { scopeKey != nil && isConfigured }\n'
                                                    '}\n'
                                                    '@MainActor struct RoamHistoryLiveEntry {\n'
                                                    '    struct Target: Hashable {\n'
                                                    '        let id = UUID()\n'
                                                    '        let owner: RoamHistoryLiveOwner\n'
                                                    '    }\n'
                                                    '    private var owner: RoamHistoryLiveOwner?\n'
                                                    '    private var successfulEmptyRead = false\n'
                                                    '    private var visible = false\n'
                                                    '    private(set) var presentationID = UUID()\n'
                                                    '    var target: Target?\n'
                                                    '\n'
                                                    '    mutating func beginRead(reader: any RoamExperienceReading) -> '
                                                    'RoamHistoryLiveOwner {\n'
                                                    '        invalidate()\n'
                                                    '        let snapshot = RoamHistoryLiveOwner(reader: reader)\n'
                                                    '        owner = snapshot\n'
                                                    '        return snapshot\n'
                                                    '    }\n'
                                                    '    mutating func acceptRead(isEmpty: Bool, snapshot: '
                                                    'RoamHistoryLiveOwner, reader: any RoamExperienceReading) {\n'
                                                    '        successfulEmptyRead = isEmpty && owner == snapshot && '
                                                    'snapshot == RoamHistoryLiveOwner(reader: reader)\n'
                                                    '    }\n'
                                                    '    mutating func appear() { visible = true; presentationID = '
                                                    'UUID() }\n'
                                                    '    mutating func disappear() {\n'
                                                    '        // Pushing the live screen hides this view; retain its '
                                                    'active destination until native Back.\n'
                                                    '        visible = false; presentationID = UUID()\n'
                                                    '    }\n'
                                                    '    func canOpen(reader: any RoamExperienceReading, '
                                                    'hasDestination: Bool) -> Bool {\n'
                                                    '        visible && target == nil && hasDestination && '
                                                    'successfulEmptyRead && owner?.isAuthorized == true\n'
                                                    '            && owner == RoamHistoryLiveOwner(reader: reader)\n'
                                                    '    }\n'
                                                    '    mutating func activate(reader: any RoamExperienceReading, '
                                                    'hasDestination: Bool, presentationID: UUID) {\n'
                                                    '        guard self.presentationID == presentationID, '
                                                    'canOpen(reader: reader, hasDestination: hasDestination), let '
                                                    'owner else { return }\n'
                                                    '        target = Target(owner: owner)\n'
                                                    '    }\n'
                                                    '    func matches(_ target: Target, reader: any '
                                                    'RoamExperienceReading, hasDestination: Bool) -> Bool {\n'
                                                    '        self.target == target && hasDestination && '
                                                    'target.owner.isAuthorized\n'
                                                    '            && target.owner == RoamHistoryLiveOwner(reader: '
                                                    'reader)\n'
                                                    '    }\n'
                                                    '    mutating func retireIfOwnerChanged(reader: any '
                                                    'RoamExperienceReading, hasDestination: Bool) {\n'
                                                    '        if owner != RoamHistoryLiveOwner(reader: reader) || '
                                                    '!hasDestination { invalidate() }\n'
                                                    '    }\n'
                                                    '    private mutating func invalidate() {\n'
                                                    '        target = nil; owner = nil; successfulEmptyRead = false; '
                                                    'presentationID = UUID()\n'
                                                    '    }\n'
                                                    '}\n'
                                                    '@MainActor struct RoamHistoryDetailView: View {\n'},
                                          {'before': '    @State private var showShare = false\n'
                                                     '    @State private var loaded = false\n'
                                                     '    @State private var error: Error?\n'
                                                     '    var body: some View {\n'
                                                     '        ScrollView {\n'
                                                     '            VStack(alignment: .leading, spacing: 20) {\n'
                                                     '                RoamExperienceNotice(offline: '
                                                     'reader.isOfflineExample)\n'
                                                     '                if let error { RoamExperienceIssue(error: error, '
                                                     'retry: load) }\n'
                                                     '                else if let record {\n'
                                                     '                    RoamExperienceCard {\n'
                                                     '                        VStack(alignment: .leading, spacing: 18) '
                                                     '{\n'
                                                     '                            Label("roam.experience.savedRecord", '
                                                     'systemImage: '
                                                     '"book.closed").font(.caption).foregroundStyle(.secondary)\n'
                                                     '                            if let zone = record.meaningfulZone '
                                                     '{ Text(verbatim: zone).font(.title2).bold() }\n'
                                                     '                            else { '
                                                     'Text("roam.experience.cityWalk").font(.title2).bold() }\n'
                                                     '                            if let date = record.recordedAt { '
                                                     'Text(date, style: .date) }\n'
                                                     '                            RoamRouteSketchView(record: record)\n'
                                                     '                            RoamRecordedStats(record: record)\n'
                                                     '                        }\n'
                                                     '                    }\n',
                                           'after': '    @State private var showShare = false\n'
                                                    '    @State private var loaded = false\n'
                                                    '    @State private var error: Error?\n'
                                                    '    @State private var loadedOwner: ReadKey?\n'
                                                    '    private struct ReadKey: Hashable {\n'
                                                    '        let owner: RoamHistoryLiveOwner\n'
                                                    '        let timestamp: Int64\n'
                                                    '    }\n'
                                                    '    private var readKey: ReadKey { .init(owner: .init(reader: '
                                                    'reader), timestamp: timestamp) }\n'
                                                    '    private var currentRecord: RoamHistoryRecord? { loadedOwner '
                                                    '== readKey ? record : nil }\n'
                                                    '    private var currentError: Error? { loadedOwner == readKey ? '
                                                    'error : nil }\n'
                                                    '    private var currentLoaded: Bool { loadedOwner == readKey && '
                                                    'loaded }\n'
                                                    '    var body: some View {\n'
                                                    '        ScrollView {\n'
                                                    '            VStack(alignment: .leading, spacing: 20) {\n'
                                                    '                RoamExperienceNotice(offline: '
                                                    'reader.isOfflineExample)\n'
                                                    '                if let error = currentError { '
                                                    'RoamExperienceIssue(error: error, retry: load) }\n'
                                                    '                else if let record = currentRecord {\n'
                                                    '                    RoamExperienceCard {\n'
                                                    '                        VStack(alignment: .leading, spacing: 18) '
                                                    '{\n'
                                                    '                            Label("roam.experience.savedRecord", '
                                                    'systemImage: '
                                                    '"book.closed").font(.caption).foregroundStyle(.secondary)\n'
                                                    '                            if let zone = record.meaningfulZone { '
                                                    'Text(verbatim: zone).font(.title2).bold() }\n'
                                                    '                            else { '
                                                    'Text("roam.experience.cityWalk").font(.title2).bold() }\n'
                                                    '                            if let date = record.recordedAt { '
                                                    'Text(date, style: .date) }\n'
                                                    '                            RoamSavedRouteReplayView(reader: '
                                                    'reader, record: record)\n'
                                                    '                            RoamRecordedStats(record: record)\n'
                                                    '                        }\n'
                                                    '                    }\n'},
                                          {'before': '                    Button("roam.share.title", systemImage: '
                                                     '"square.and.arrow.up") { showShare = true }\n'
                                                     '                        '
                                                     '.accessibilityIdentifier("roam.share.open")\n'
                                                     '                    '
                                                     'Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)\n'
                                                     '                } else if loaded {\n'
                                                     '                    '
                                                     'ContentUnavailableView("roam.experience.recordMissing", '
                                                     'systemImage: "questionmark.folder", description: '
                                                     'Text("roam.experience.recordMissingHint"))\n'
                                                     '                        '
                                                     '.accessibilityIdentifier("roam.experience.history.missing")\n'
                                                     '                } else { ProgressView("roam.loading") }\n'
                                                     '            }.padding()\n'
                                                     '        }.navigationTitle("roam.experience.session")\n'
                                                     '            .task(id: reader.identity) { showShare = false; '
                                                     'load() }\n'
                                                     '            .sheet(isPresented: $showShare) { if let record { '
                                                     'NavigationStack { RoamHistoryShareView(record: record) } } }\n'
                                                     '            .accessibilityIdentifier("roam.experience.session")\n'
                                                     '    }\n'
                                                     '    private func load() {\n'
                                                     '        record = nil; error = nil; loaded = false\n'
                                                     '        do { record = try reader.history().first { $0.ts == '
                                                     'timestamp }; loaded = true } catch { self.error = error }\n'
                                                     '    }\n'
                                                     '}\n',
                                           'after': '                    Button("roam.share.title", systemImage: '
                                                    '"square.and.arrow.up") { showShare = true }\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("roam.share.open")\n'
                                                    '                    '
                                                    'Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)\n'
                                                    '                } else if currentLoaded {\n'
                                                    '                    '
                                                    'ContentUnavailableView("roam.experience.recordMissing", '
                                                    'systemImage: "questionmark.folder", description: '
                                                    'Text("roam.experience.recordMissingHint"))\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("roam.experience.history.missing")\n'
                                                    '                } else { ProgressView("roam.loading") }\n'
                                                    '            }.padding()\n'
                                                    '        }.navigationTitle("roam.experience.session")\n'
                                                    '            .task(id: readKey) { showShare = false; load() }\n'
                                                    '            .onChange(of: readKey) { _, _ in showShare = false }\n'
                                                    '            .sheet(isPresented: $showShare) { if let record = '
                                                    'currentRecord { NavigationStack { RoamHistoryShareView(record: '
                                                    'record) } } }\n'
                                                    '            .accessibilityIdentifier("roam.experience.session")\n'
                                                    '    }\n'
                                                    '    private func load() {\n'
                                                    '        record = nil; error = nil; loaded = false; loadedOwner = '
                                                    'nil\n'
                                                    '        let captured = readKey\n'
                                                    '        do {\n'
                                                    '            let value = try reader.history().first { $0.ts == '
                                                    'timestamp }\n'
                                                    '            guard captured == readKey else { return }\n'
                                                    '            record = value; loaded = true; loadedOwner = '
                                                    'captured\n'
                                                    '        } catch {\n'
                                                    '            guard captured == readKey else { return }\n'
                                                    '            self.error = error; loadedOwner = captured\n'
                                                    '        }\n'
                                                    '    }\n'
                                                    '}\n'}]},
 'App/RoamExperienceComponents.swift': {'before_sha256': '5d07efdb738c201f6f9b6502b1211330db63d6873ed4be5d33e1eb054115b453',
                                        'after_sha256': '02188caf2ccd48dae34f6775828d2e722ce4f8239f9925af8d972d9148e772fb',
                                        'hunks': [{'before': '}\n'
                                                             'struct RoamRouteSketchView: View {\n'
                                                             '    let record: RoamHistoryRecord\n'
                                                             '    var body: some View {\n'
                                                             '        let sketch = RoamRouteSketch(track: '
                                                             'record.track, places: record.pois.map(\\.point))\n'
                                                             '        ZStack {\n',
                                                   'after': '}\n'
                                                            'struct RoamRouteSketchView: View {\n'
                                                            '    let record: RoamHistoryRecord\n'
                                                            '    var visibleSegments: Int? = nil\n'
                                                            '    var body: some View {\n'
                                                            '        let sketch = RoamRouteSketch(track: record.track, '
                                                            'places: record.pois.map(\\.point))\n'
                                                            '        ZStack {\n'},
                                                  {'before': '            } else {\n'
                                                             '                Canvas { context, size in\n'
                                                             '                    var path = Path()\n'
                                                             '                    for (index, point) in '
                                                             'sketch.track.enumerated() {\n'
                                                             '                        let position = CGPoint(x: '
                                                             'point.x * size.width, y: point.y * size.height)\n'
                                                             '                        if index == 0 { path.move(to: '
                                                             'position) } else { path.addLine(to: position) }\n'
                                                             '                    }\n',
                                                   'after': '            } else {\n'
                                                            '                Canvas { context, size in\n'
                                                            '                    var path = Path()\n'
                                                            '                    let segmentCount = max(0, '
                                                            'sketch.track.count - 1)\n'
                                                            '                    let pointCount = visibleSegments.map '
                                                            '{ min(segmentCount, max(0, $0)) + 1 } ?? '
                                                            'sketch.track.count\n'
                                                            '                    for (index, point) in '
                                                            'sketch.track.prefix(pointCount).enumerated() {\n'
                                                            '                        let position = CGPoint(x: point.x '
                                                            '* size.width, y: point.y * size.height)\n'
                                                            '                        if index == 0 { path.move(to: '
                                                            'position) } else { path.addLine(to: position) }\n'
                                                            '                    }\n'},
                                                  {'before': '        }.font(.subheadline).monospacedDigit()\n'
                                                             '    }\n'
                                                             '}\n',
                                                   'after': '        }.font(.subheadline).monospacedDigit()\n'
                                                            '    }\n'
                                                            '}\n'
                                                            '\n'
                                                            '/// Replays only the stored sketch. This view has no '
                                                            'location, network or write capability.\n'
                                                            '@MainActor struct RoamSavedRouteReplayView: View {\n'
                                                            '    let reader: any RoamExperienceReading\n'
                                                            '    let record: RoamHistoryRecord\n'
                                                            '    @Environment(\\.scenePhase) private var scenePhase\n'
                                                            '    @Environment(\\.accessibilityReduceMotion) private '
                                                            'var reduceMotion\n'
                                                            '    @State private var replay = RoamRouteReplayState()\n'
                                                            '    @State private var visible = false\n'
                                                            '    @State private var request: Request?\n'
                                                            '    private struct Request {\n'
                                                            '        let id = UUID()\n'
                                                            '        let context: RoamRouteReplayState.Context\n'
                                                            '        let counts: [Int]\n'
                                                            '    }\n'
                                                            '    private var owner: RoamRouteReplayState.Owner { '
                                                            '.init(reader: reader, record: record) }\n'
                                                            '    var body: some View {\n'
                                                            '        let current = owner\n'
                                                            '        let context = replay.context(for: current)\n'
                                                            '        VStack(alignment: .leading, spacing: 12) {\n'
                                                            '            // Always normalize the complete record; '
                                                            'revealing a prefix never rescales it.\n'
                                                            '            RoamRouteSketchView(record: record, '
                                                            'visibleSegments: context == nil ? nil : '
                                                            'replay.visibleSegments)\n'
                                                            '            if let context {\n'
                                                            '                if replay.phase == .playing {\n'
                                                            '                    Button("roamRouteReplay.skip", '
                                                            'systemImage: "forward.end") {\n'
                                                            '                        synchronize()\n'
                                                            '                        guard replay.accepts(context, '
                                                            'current: owner) else { return }\n'
                                                            '                        replay.skip(in: context, current: '
                                                            'owner); request = nil\n'
                                                            '                    }.frame(minHeight: '
                                                            '44).accessibilityIdentifier("roamRouteReplay.skip")\n'
                                                            '                } else {\n'
                                                            '                    '
                                                            'Button(LocalizedStringKey(replay.phase == .completed ? '
                                                            '"roamRouteReplay.again" : "roamRouteReplay.start"), '
                                                            'systemImage: "play") {\n'
                                                            '                        synchronize()\n'
                                                            '                        guard replay.accepts(context, '
                                                            'current: owner) else { return }\n'
                                                            '                        if let ticket = replay.start(in: '
                                                            'context, current: owner) {\n'
                                                            '                            request = Request(context: '
                                                            'ticket, counts: replay.plan.counts)\n'
                                                            '                        }\n'
                                                            '                    }.frame(minHeight: '
                                                            '44).accessibilityIdentifier("roamRouteReplay.start")\n'
                                                            '                }\n'
                                                            '                ProgressView(value: replay.progress, '
                                                            'total: 1)\n'
                                                            '                    '
                                                            '.accessibilityLabel(Text("roamRouteReplay.progress"))\n'
                                                            '                    '
                                                            '.accessibilityValue(Text(replay.progress, format: '
                                                            '.percent.precision(.fractionLength(0))))\n'
                                                            '                    '
                                                            '.accessibilityIdentifier("roamRouteReplay.progress")\n'
                                                            '                Text(LocalizedStringKey(replay.phase == '
                                                            '.playing ? "roamRouteReplay.playing" : (replay.phase == '
                                                            '.completed ? "roamRouteReplay.completed" : '
                                                            '"roamRouteReplay.ready")))\n'
                                                            '                    '
                                                            '.font(.caption).foregroundStyle(.secondary)\n'
                                                            '            }\n'
                                                            '        }\n'
                                                            '        .onAppear { visible = true; synchronize() }\n'
                                                            '        .onDisappear { visible = false; synchronize() }\n'
                                                            '        .onChange(of: owner) { _, _ in synchronize() }\n'
                                                            '        .onChange(of: scenePhase) { _, _ in synchronize() '
                                                            '}\n'
                                                            '        .onChange(of: reduceMotion) { _, _ in '
                                                            'synchronize() }\n'
                                                            '        .task(id: request?.id) {\n'
                                                            '            guard let captured = request else { return }\n'
                                                            '            for (index, count) in '
                                                            'captured.counts.enumerated() {\n'
                                                            '                if index > 0 {\n'
                                                            '                    do { try await '
                                                            'Task.sleep(nanoseconds: '
                                                            'RoamRouteReplayPlan.intervalNanoseconds) }\n'
                                                            '                    catch { return }\n'
                                                            '                }\n'
                                                            '                if reduceMotion { synchronize(); return '
                                                            '}\n'
                                                            '                guard !Task.isCancelled, visible, '
                                                            'scenePhase == .active,\n'
                                                            '                      replay.accepts(captured.context, '
                                                            'current: owner) else { return }\n'
                                                            '                replay.advance(to: count, in: '
                                                            'captured.context, current: owner)\n'
                                                            '            }\n'
                                                            '            // No old-task cleanup can clear a later '
                                                            'request.\n'
                                                            '        }\n'
                                                            '        .accessibilityElement(children: .contain)\n'
                                                            '        '
                                                            '.accessibilityIdentifier("roamRouteReplay.saved")\n'
                                                            '    }\n'
                                                            '    private func synchronize() {\n'
                                                            '        replay.update(owner: owner, active: visible && '
                                                            'scenePhase == .active, reduceMotion: reduceMotion)\n'
                                                            '        if let captured = request, '
                                                            '!replay.accepts(captured.context, current: owner) { '
                                                            'request = nil }\n'
                                                            '    }\n'
                                                            '}\n'}]},
 'Core/RoamExperienceMath.swift': {'before_sha256': '11fd35c304e0376c077924e870418b77db9f7cca3c738781f09e3d4a41f49844',
                                   'after_sha256': '65f5ef1e0f0161c5875f6e962790e2690ef9de210da7cb75b7a72c3cda3b8a6b',
                                   'hunks': [{'before': '        self.track = Array(normalized.prefix(track.count)); '
                                                        'self.places = Array(normalized.dropFirst(track.count))\n'
                                                        '    }\n'
                                                        '}\n',
                                              'after': '        self.track = Array(normalized.prefix(track.count)); '
                                                       'self.places = Array(normalized.dropFirst(track.count))\n'
                                                       '    }\n'
                                                       '}\n'
                                                       '\n'
                                                       '/// A bounded local display schedule; it never reads, changes '
                                                       'or saves a route.\n'
                                                       'public struct RoamRouteReplayPlan: Equatable {\n'
                                                       '    public static let intervalNanoseconds: UInt64 = '
                                                       '120_000_000\n'
                                                       '    public static let maximumFrames = 24\n'
                                                       '    public let counts: [Int]\n'
                                                       '    public init(segmentCount: Int) {\n'
                                                       '        let total = max(0, segmentCount)\n'
                                                       '        guard total > 0 else { counts = []; return }\n'
                                                       '        let frames = min(total, Self.maximumFrames)\n'
                                                       '        let step = total / frames + (total % frames == 0 ? 0 : '
                                                       '1)\n'
                                                       '        var result: [Int] = [], count = 0\n'
                                                       '        while count < total {\n'
                                                       '            count = total - count <= step ? total : count + '
                                                       'step\n'
                                                       '            result.append(count)\n'
                                                       '        }\n'
                                                       '        counts = result\n'
                                                       '    }\n'
                                                       '}\n'
                                                       '\n'
                                                       '/// Value-only replay authority. Timers live in the SwiftUI '
                                                       'detail presentation.\n'
                                                       '/// A context belongs to an exact reader/scope, complete '
                                                       'record value and visible lifetime.\n'
                                                       'public struct RoamRouteReplayState {\n'
                                                       '    public struct Owner: Equatable {\n'
                                                       '        public let readerID: ObjectIdentifier\n'
                                                       '        public let identity: RoamExperienceIdentity?\n'
                                                       '        public let storageKey: String?\n'
                                                       '        public let configured: Bool\n'
                                                       '        public let record: RoamHistoryRecord\n'
                                                       '        @MainActor public init(reader: any '
                                                       'RoamExperienceReading, record: RoamHistoryRecord) {\n'
                                                       '            readerID = ObjectIdentifier(reader); identity = '
                                                       'reader.identity\n'
                                                       '            storageKey = identity?.scope.storageKey\n'
                                                       '            configured = reader.isConfigured; self.record = '
                                                       'record\n'
                                                       '        }\n'
                                                       '    }\n'
                                                       '    public struct Context: Equatable {\n'
                                                       '        fileprivate let owner: Owner\n'
                                                       '        fileprivate let generation: UUID\n'
                                                       '    }\n'
                                                       '    public enum Phase: Equatable { case ready, playing, '
                                                       'completed }\n'
                                                       '    public private(set) var phase: Phase = .ready\n'
                                                       '    public private(set) var totalSegments = 0\n'
                                                       '    /// nil means the unchanged full static sketch, including '
                                                       'non-replay callers.\n'
                                                       '    public private(set) var visibleSegments: Int?\n'
                                                       '    private var owner: Owner?\n'
                                                       '    private var active = false\n'
                                                       '    private var reduceMotion = false\n'
                                                       '    private var generation = UUID()\n'
                                                       '    public init() {}\n'
                                                       '    public var progress: Double {\n'
                                                       '        guard totalSegments > 0 else { return 0 }\n'
                                                       '        return Double(visibleSegments ?? totalSegments) / '
                                                       'Double(totalSegments)\n'
                                                       '    }\n'
                                                       '    public var plan: RoamRouteReplayPlan { .init(segmentCount: '
                                                       'totalSegments) }\n'
                                                       '    public mutating func update(owner: Owner, active: Bool, '
                                                       'reduceMotion: Bool) {\n'
                                                       '        if self.owner != owner || self.active != active {\n'
                                                       '            generation = UUID(); phase = .ready; '
                                                       'visibleSegments = nil\n'
                                                       '            let points = RoamRouteSketch(track: '
                                                       'owner.record.track, places: '
                                                       'owner.record.pois.map(\\.point)).track\n'
                                                       '            let hasLine = zip(points, '
                                                       'points.dropFirst()).contains { pair in pair.0 != pair.1 }\n'
                                                       '            totalSegments = hasLine ? max(0, points.count - 1) '
                                                       ': 0\n'
                                                       '        }\n'
                                                       '        self.owner = owner; self.active = active; '
                                                       'self.reduceMotion = reduceMotion\n'
                                                       '        if reduceMotion && phase == .playing { complete() }\n'
                                                       '    }\n'
                                                       '    public func context(for current: Owner) -> Context? {\n'
                                                       '        guard active, owner == current, totalSegments > 0 else '
                                                       '{ return nil }\n'
                                                       '        return Context(owner: current, generation: '
                                                       'generation)\n'
                                                       '    }\n'
                                                       '    public func accepts(_ context: Context, current: Owner) -> '
                                                       'Bool {\n'
                                                       '        self.context(for: current) == context\n'
                                                       '    }\n'
                                                       '    @discardableResult public mutating func start(in context: '
                                                       'Context, current: Owner) -> Context? {\n'
                                                       '        guard accepts(context, current: current), phase != '
                                                       '.playing else { return nil }\n'
                                                       '        generation = UUID()\n'
                                                       '        if reduceMotion { phase = .completed; visibleSegments '
                                                       '= nil; return nil }\n'
                                                       '        phase = .playing; visibleSegments = 0\n'
                                                       '        return self.context(for: current)\n'
                                                       '    }\n'
                                                       '    public mutating func advance(to count: Int, in context: '
                                                       'Context, current: Owner) {\n'
                                                       '        guard accepts(context, current: current), phase == '
                                                       '.playing else { return }\n'
                                                       '        let bounded = min(totalSegments, max(0, count))\n'
                                                       '        guard bounded >= (visibleSegments ?? 0) else { return '
                                                       '}\n'
                                                       '        visibleSegments = bounded\n'
                                                       '        if bounded == totalSegments { complete() }\n'
                                                       '    }\n'
                                                       '    public mutating func skip(in context: Context, current: '
                                                       'Owner) {\n'
                                                       '        guard accepts(context, current: current), phase == '
                                                       '.playing else { return }\n'
                                                       '        complete()\n'
                                                       '    }\n'
                                                       '    private mutating func complete() {\n'
                                                       '        generation = UUID(); phase = .completed; '
                                                       'visibleSegments = nil\n'
                                                       '    }\n'
                                                       '}\n'}]},
 'Resources/Localizable.xcstrings': {'before_sha256': '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995',
                                     'after_sha256': '901ba5a72ab2748c171483dff7743c63a30552ab9ded21b2c3379ae410f2a898',
                                     'hunks': [{'before': '          }\n'
                                                          '        }\n'
                                                          '      }\n'
                                                          '    }\n'
                                                          '  },\n'
                                                          '  "version": "1.0"\n',
                                                'after': '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    },\n'
                                                         '    "roamRouteReplay.start": {\n'
                                                         '      "extractionState": "manual",\n'
                                                         '      "localizations": {\n'
                                                         '        "en": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "Replay saved route"\n'
                                                         '          }\n'
                                                         '        },\n'
                                                         '        "zh-Hans": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "回放已保存路线"\n'
                                                         '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    },\n'
                                                         '    "roamRouteReplay.again": {\n'
                                                         '      "extractionState": "manual",\n'
                                                         '      "localizations": {\n'
                                                         '        "en": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "Replay again"\n'
                                                         '          }\n'
                                                         '        },\n'
                                                         '        "zh-Hans": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "重新回放"\n'
                                                         '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    },\n'
                                                         '    "roamRouteReplay.skip": {\n'
                                                         '      "extractionState": "manual",\n'
                                                         '      "localizations": {\n'
                                                         '        "en": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "Show complete route"\n'
                                                         '          }\n'
                                                         '        },\n'
                                                         '        "zh-Hans": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "跳到完整路线"\n'
                                                         '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    },\n'
                                                         '    "roamRouteReplay.progress": {\n'
                                                         '      "extractionState": "manual",\n'
                                                         '      "localizations": {\n'
                                                         '        "en": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "Saved route replay progress"\n'
                                                         '          }\n'
                                                         '        },\n'
                                                         '        "zh-Hans": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "已保存路线回放进度"\n'
                                                         '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    },\n'
                                                         '    "roamRouteReplay.playing": {\n'
                                                         '      "extractionState": "manual",\n'
                                                         '      "localizations": {\n'
                                                         '        "en": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "Replaying this saved route"\n'
                                                         '          }\n'
                                                         '        },\n'
                                                         '        "zh-Hans": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "正在回放本次已保存路线"\n'
                                                         '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    },\n'
                                                         '    "roamRouteReplay.completed": {\n'
                                                         '      "extractionState": "manual",\n'
                                                         '      "localizations": {\n'
                                                         '        "en": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "Route replay complete"\n'
                                                         '          }\n'
                                                         '        },\n'
                                                         '        "zh-Hans": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "路线回放完成"\n'
                                                         '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    },\n'
                                                         '    "roamRouteReplay.ready": {\n'
                                                         '      "extractionState": "manual",\n'
                                                         '      "localizations": {\n'
                                                         '        "en": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "Complete saved route. Replay when you '
                                                         'choose."\n'
                                                         '          }\n'
                                                         '        },\n'
                                                         '        "zh-Hans": {\n'
                                                         '          "stringUnit": {\n'
                                                         '            "state": "translated",\n'
                                                         '            "value": "已显示完整保存路线，可随时选择回放。"\n'
                                                         '          }\n'
                                                         '        }\n'
                                                         '      }\n'
                                                         '    }\n'
                                                         '  },\n'
                                                         '  "version": "1.0"\n'}]}}
PARENT_SOURCE_ROWS = {'App/GlobalSearchView.swift': {'before_sha256': 'c70fee37e02a6b4e2ee6540104932b175fee1d0faed013141fecb8cbce6c7cec',
                                'after_sha256': '0aafd543944d3ad919da43ca44e107accdd01a7a42c268522addcc5f2dabd8a5',
                                'hunks': [{'before': '    @State private var filter = GlobalSearchQuery()\n'
                                                     '    @State private var categories: [DiscoveryCategory] = []\n'
                                                     '    @State private var categoryFailed = false\n'
                                                     '    @State private var result: GlobalSearchResults?\n'
                                                     '    @State private var issue: String?\n'
                                                     '    @State private var loading = false\n'
                                                     '    @State private var activeQuery: GlobalSearchQuery?\n'
                                                     '    @State private var selectedKind: GlobalSearchKind?\n'
                                                     '    @State private var showsFilters = false\n'
                                                     '    @State private var history: [String] = []\n'
                                                     '    @State private var historyFailure = false\n'
                                                     '    @State private var gate = SearchMapQueryGate()\n'
                                                     '    @State private var categoryGate = SearchMapQueryGate()\n'
                                                     '    @State private var preparedScope: UUID?\n'
                                                     '    private let historyStore = SearchMapLocalHistory()\n'
                                                     '\n'
                                                     '    var body: some View {\n'
                                                     '        ScrollView {\n'
                                                     '            VStack(alignment: .leading, spacing: 18) {\n'
                                                     '                if historyFailure { '
                                                     'Text("searchMap.historyUnavailable").font(.caption).foregroundStyle(.secondary) '
                                                     '}\n'
                                                     '                if reader.isOfflineExample { '
                                                     'Text("searchMap.offline").font(.caption).foregroundStyle(.secondary) '
                                                     '}\n'
                                                     '                HStack {\n'
                                                     '                    TextField("searchMap.placeholder", text: '
                                                     '$filter.keyword).textInputAutocapitalization(.never)\n'
                                                     '                        .submitLabel(.search).onSubmit { Task { '
                                                     'await search() } }\n'
                                                     '                        '
                                                     '.accessibilityIdentifier("searchMap.keyword")\n'
                                                     '                    Button { showsFilters = true } label: { '
                                                     'Label("searchMap.filters", systemImage: '
                                                     '"line.3.horizontal.decrease") }\n',
                                           'after': '    @State private var filter = GlobalSearchQuery()\n'
                                                    '    @State private var categories: [DiscoveryCategory] = []\n'
                                                    '    @State private var categoryFailed = false\n'
                                                    '    @State private var retainedResults = '
                                                    'GlobalSearchRetainedResults()\n'
                                                    '    @State private var isVisible = false\n'
                                                    '    @State private var issue: String?\n'
                                                    '    @State private var loading = false\n'
                                                    '    @State private var selectedKind: GlobalSearchKind?\n'
                                                    '    @State private var showsFilters = false\n'
                                                    '    @State private var history: [String] = []\n'
                                                    '    @State private var historyFailure = false\n'
                                                    '    @State private var categoryGate = SearchMapQueryGate()\n'
                                                    '    @State private var preparedOwner: ReadOwner?\n'
                                                    '    private let historyStore = SearchMapLocalHistory()\n'
                                                    '\n'
                                                    '    private struct ReadOwner: Equatable {\n'
                                                    '        let readerID: ObjectIdentifier\n'
                                                    '        let scope: UUID\n'
                                                    '        let authenticated: Bool\n'
                                                    '        let configured: Bool\n'
                                                    '    }\n'
                                                    '    private var readOwner: ReadOwner {\n'
                                                    '        .init(readerID: ObjectIdentifier(reader), scope: '
                                                    'reader.scope,\n'
                                                    '              authenticated: reader.isAuthenticated, configured: '
                                                    'reader.isConfigured)\n'
                                                    '    }\n'
                                                    '    private var resultContext: GlobalSearchResultContext {\n'
                                                    '        .init(readerID: ObjectIdentifier(reader), scope: '
                                                    'reader.scope, isAuthenticated: reader.isAuthenticated,\n'
                                                    '              isConfigured: reader.isConfigured, query: filter)\n'
                                                    '    }\n'
                                                    '    var body: some View {\n'
                                                    '        ScrollView {\n'
                                                    '            VStack(alignment: .leading, spacing: 18) {\n'
                                                    '                if historyFailure { '
                                                    'Text("searchMap.historyUnavailable").font(.caption).foregroundStyle(.secondary) '
                                                    '}\n'
                                                    '                if reader.isOfflineExample { '
                                                    'Text("searchMap.offline").font(.caption).foregroundStyle(.secondary) '
                                                    '}\n'
                                                    '                HStack {\n'
                                                    '                    TextField("searchMap.placeholder", text: '
                                                    'Binding(get: { filter.keyword }, set: '
                                                    'setKeyword)).textInputAutocapitalization(.never)\n'
                                                    '                        .submitLabel(.search).onSubmit { Task { '
                                                    'await search() } }\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("searchMap.keyword")\n'
                                                    '                    Button { showsFilters = true } label: { '
                                                    'Label("searchMap.filters", systemImage: '
                                                    '"line.3.horizontal.decrease") }\n'},
                                          {'before': '                } label: { Label("merchant.discover.title", '
                                                     'systemImage: "storefront") }\n'
                                                     '                    .frame(minHeight: '
                                                     '44).accessibilityIdentifier("merchant.discover.entry")\n'
                                                     '                if !reader.isConfigured { SearchMapIssue(key: '
                                                     '"searchMap.notConfigured") }\n'
                                                     '                else if loading { '
                                                     'ProgressView("searchMap.loading").frame(maxWidth: '
                                                     '.infinity).accessibilityIdentifier("searchMap.loading") }\n'
                                                     '                else if let issue { SearchMapIssue(key: issue) { '
                                                     'Task { await search() } } }\n'
                                                     '                else if let result { results(result) }\n'
                                                     '                else { suggestions }\n'
                                                     '            }.padding()\n'
                                                     '        }\n'
                                                     '        .appNavigationTitle("searchMap.title")\n',
                                           'after': '                } label: { Label("merchant.discover.title", '
                                                    'systemImage: "storefront") }\n'
                                                    '                    .frame(minHeight: '
                                                    '44).accessibilityIdentifier("merchant.discover.entry")\n'
                                                    '                if !reader.isConfigured { SearchMapIssue(key: '
                                                    '"searchMap.notConfigured") }\n'
                                                    '                else {\n'
                                                    '                    if loading { '
                                                    'ProgressView("searchMap.loading").frame(maxWidth: '
                                                    '.infinity).accessibilityIdentifier("searchMap.loading") }\n'
                                                    '                    if let issue { SearchMapIssue(key: issue) { '
                                                    'Task { await search() } } }\n'
                                                    '                    if let snapshot = '
                                                    'retainedResults.snapshot(in: resultContext) {\n'
                                                    '                        results(snapshot.results, retainedKinds: '
                                                    'snapshot.retainedKinds)\n'
                                                    '                    } else if !loading && issue == nil { '
                                                    'suggestions }\n'
                                                    '                }\n'
                                                    '            }.padding()\n'
                                                    '        }\n'
                                                    '        .appNavigationTitle("searchMap.title")\n'},
                                          {'before': '                applyFilter(next)\n'
                                                     '            }\n'
                                                     '        }\n'
                                                     '        .task(id: reader.scope) { await prepare() }\n'
                                                     '        .onChange(of: filter.keyword) { _, keyword in if '
                                                     'activeQuery?.keyword != keyword { invalidate() } }\n'
                                                     '        .onDisappear { gate.invalidate(); '
                                                     'categoryGate.invalidate(); loading = false }\n'
                                                     '    }\n'
                                                     '    @ViewBuilder private var suggestions: some View {\n'
                                                     '        if !history.isEmpty {\n',
                                           'after': '                applyFilter(next)\n'
                                                    '            }\n'
                                                    '        }\n'
                                                    '        .task(id: readOwner) { await prepare() }\n'
                                                    '        .onAppear { isVisible = true }\n'
                                                    '        .onDisappear { isVisible = false; '
                                                    'retainedResults.cancelPending(); categoryGate.invalidate(); '
                                                    'loading = false }\n'
                                                    '    }\n'
                                                    '    @ViewBuilder private var suggestions: some View {\n'
                                                    '        if !history.isEmpty {\n'},
                                          {'before': '                    .frame(minHeight: '
                                                     '44).accessibilityIdentifier("searchMap.clearHistory")\n'
                                                     '            }\n'
                                                     '            ForEach(history, id: \\.self) { keyword in\n'
                                                     '                Button { filter.keyword = keyword; Task { await '
                                                     'search() } } label: { Label(keyword, systemImage: "clock") }\n'
                                                     '                    .frame(minHeight: 44)\n'
                                                     '            }\n'
                                                     '        }\n',
                                           'after': '                    .frame(minHeight: '
                                                    '44).accessibilityIdentifier("searchMap.clearHistory")\n'
                                                    '            }\n'
                                                    '            ForEach(history, id: \\.self) { keyword in\n'
                                                    '                Button { setKeyword(keyword); Task { await '
                                                    'search() } } label: { Label(keyword, systemImage: "clock") }\n'
                                                    '                    .frame(minHeight: 44)\n'
                                                    '            }\n'
                                                    '        }\n'},
                                          {'before': '            }\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '    @ViewBuilder private func results(_ value: '
                                                     'GlobalSearchResults) -> some View {\n'
                                                     '        if !value.gatedKinds.isEmpty {\n'
                                                     '            Label("searchMap.partialSignIn", systemImage: '
                                                     '"lock").font(.footnote)\n'
                                                     '                '
                                                     '.accessibilityIdentifier("searchMap.guestGate")\n',
                                           'after': '            }\n'
                                                    '        }\n'
                                                    '    }\n'
                                                    '    @ViewBuilder private func results(_ value: '
                                                    'GlobalSearchResults, retainedKinds: [GlobalSearchKind]) -> some '
                                                    'View {\n'
                                                    '        if loading && !value.rows.isEmpty {\n'
                                                    '            '
                                                    'Text("globalSearchRetention.refreshing").font(.footnote).foregroundStyle(.secondary)\n'
                                                    '                '
                                                    '.accessibilityIdentifier("globalSearchRetention.refreshing")\n'
                                                    '        }\n'
                                                    '        if !retainedKinds.isEmpty {\n'
                                                    '            VStack(alignment: .leading, spacing: 4) {\n'
                                                    '                Text("globalSearchRetention.stale")\n'
                                                    '                ForEach(retainedKinds, id: \\.self) { kind in '
                                                    'Label(kind.titleKey, systemImage: "clock.arrow.circlepath") }\n'
                                                    '            '
                                                    '}.font(.footnote).accessibilityIdentifier("globalSearchRetention.stale")\n'
                                                    '        }\n'
                                                    '        if !value.gatedKinds.isEmpty {\n'
                                                    '            Label("searchMap.partialSignIn", systemImage: '
                                                    '"lock").font(.footnote)\n'
                                                    '                '
                                                    '.accessibilityIdentifier("searchMap.guestGate")\n'},
                                          {'before': '            }.frame(minHeight: 44)\n'
                                                     '        }\n'
                                                     '        let visible = value.rows.filter { selectedKind == nil || '
                                                     '$0.kind == selectedKind }\n'
                                                     '        if visible.isEmpty && !value.allFailed { '
                                                     'ContentUnavailableView("searchMap.empty", systemImage: '
                                                     '"magnifyingglass", description: Text("searchMap.emptyHint")) }\n'
                                                     '        ForEach(visible) { row in\n'
                                                     '            NavigationLink { destination(row.destination) } '
                                                     'label: { SearchMapCard(row: row, offline: '
                                                     'reader.isOfflineExample) }\n'
                                                     '                '
                                                     '.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.result.\\(row.id)")\n',
                                           'after': '            }.frame(minHeight: 44)\n'
                                                    '        }\n'
                                                    '        let visible = value.rows.filter { selectedKind == nil || '
                                                    '$0.kind == selectedKind }\n'
                                                    '        if visible.isEmpty && !loading && !value.allFailed && '
                                                    'value.failedKinds.isEmpty && value.gatedKinds.isEmpty { '
                                                    'ContentUnavailableView("searchMap.empty", systemImage: '
                                                    '"magnifyingglass", description: Text("searchMap.emptyHint")) }\n'
                                                    '        ForEach(visible) { row in\n'
                                                    '            NavigationLink { destination(row.destination) } '
                                                    'label: { SearchMapCard(row: row, offline: '
                                                    'reader.isOfflineExample) }\n'
                                                    '                '
                                                    '.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.result.\\(row.id)")\n'},
                                          {'before': '        // Invalidate synchronously, including category-only '
                                                     'searches cleared to an empty query.\n'
                                                     '        filter = next; invalidate(); Task { await search() }\n'
                                                     '    }\n'
                                                     '    private func invalidate() { gate.invalidate(); activeQuery = '
                                                     'nil; result = nil; issue = nil; loading = false }\n'
                                                     '    private func prepare(force: Bool = false) async {\n'
                                                     '        if preparedScope != reader.scope {\n'
                                                     '            preparedScope = reader.scope; invalidate(); '
                                                     'categories = []; categoryFailed = false\n'
                                                     '            history = historyStore.read(namespace: '
                                                     'historyNamespace); historyFailure = historyStore.failed\n'
                                                     '        }\n'
                                                     '        guard reader.isConfigured, force || categories.isEmpty '
                                                     'else { return }\n',
                                           'after': '        // Invalidate synchronously, including category-only '
                                                    'searches cleared to an empty query.\n'
                                                    '        filter = next; invalidate(); Task { await search() }\n'
                                                    '    }\n'
                                                    '    private func setKeyword(_ value: String) {\n'
                                                    '        guard !filter.keyword.utf8.elementsEqual(value.utf8) else '
                                                    '{ return }\n'
                                                    '        invalidate(); filter.keyword = value\n'
                                                    '    }\n'
                                                    '    private func invalidate() { retainedResults.invalidate(); '
                                                    'issue = nil; loading = false; selectedKind = nil }\n'
                                                    '    private func prepare(force: Bool = false) async {\n'
                                                    '        if preparedOwner != readOwner {\n'
                                                    '            preparedOwner = readOwner; invalidate(); categories = '
                                                    '[]; categoryFailed = false\n'
                                                    '            history = historyStore.read(namespace: '
                                                    'historyNamespace); historyFailure = historyStore.failed\n'
                                                    '        }\n'
                                                    '        guard reader.isConfigured, force || categories.isEmpty '
                                                    'else { return }\n'},
                                          {'before': '    }\n'
                                                     '    private func search() async {\n'
                                                     '        let query = filter\n'
                                                     '        guard reader.isConfigured, query.canSearch else { return '
                                                     '}\n'
                                                     '        let ticket = gate.begin(scope: reader.scope)\n'
                                                     '        activeQuery = query\n'
                                                     '        loading = true; result = nil; issue = nil\n'
                                                     '        defer { if gate.accepts(ticket, scope: reader.scope) { '
                                                     'loading = false } }\n'
                                                     '        do {\n'
                                                     '            let value = try await reader.search(query)\n'
                                                     '            guard gate.accepts(ticket, scope: reader.scope), '
                                                     'filter == query else { return }\n'
                                                     '            result = value\n'
                                                     '            history = historyStore.add(query.keyword, namespace: '
                                                     'historyNamespace, current: history); historyFailure = '
                                                     'historyStore.failed\n'
                                                     '        } catch {\n'
                                                     '            guard gate.accepts(ticket, scope: reader.scope), '
                                                     'filter == query else { return }\n'
                                                     '            issue = SearchMapIssue.key(error)\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '}\n',
                                           'after': '    }\n'
                                                    '    private func search() async {\n'
                                                    '        let query = filter\n'
                                                    '        guard isVisible else { return }\n'
                                                    '        guard reader.isConfigured, query.canSearch else { return '
                                                    '}\n'
                                                    '        let captured = resultContext\n'
                                                    '        let ticket = retainedResults.begin(in: captured)\n'
                                                    '        loading = true; issue = nil\n'
                                                    '        do {\n'
                                                    '            let value = try await reader.search(query)\n'
                                                    '            guard !Task.isCancelled, isVisible, filter == query, '
                                                    'retainedResults.accepts(ticket, in: resultContext) else { return '
                                                    '}\n'
                                                    '            loading = false\n'
                                                    '            retainedResults.finish(value, ticket: ticket, in: '
                                                    'resultContext)\n'
                                                    '            history = historyStore.add(query.keyword, namespace: '
                                                    'historyNamespace, current: history); historyFailure = '
                                                    'historyStore.failed\n'
                                                    '        } catch {\n'
                                                    '            guard isVisible, retainedResults.accepts(ticket, in: '
                                                    'resultContext) else { return }\n'
                                                    '            loading = false\n'
                                                    '            retainedResults.fail(ticket, in: resultContext)\n'
                                                    '            if !(error is CancellationError) { issue = '
                                                    'SearchMapIssue.key(error) }\n'
                                                    '        }\n'
                                                    '    }\n'
                                                    '}\n'}]},
 'Core/SearchMapReading.swift': {'before_sha256': '2089e1dd5f41c81411472acfe8caf0f18e51693dd2c8ca390dde074409cde017',
                                 'after_sha256': '1dee179f1505a44f1375ac860c7e7540f14d743a5302fc69707fbe3b32d5a02b',
                                 'hunks': [{'before': '    func categories() async throws -> [DiscoveryCategory]\n'
                                                      '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                      'throws -> [MerchantDiscoveryRow]\n'
                                                      '    func search(_ query: GlobalSearchQuery) async throws -> '
                                                      'GlobalSearchResults\n'
                                                      '    func citySearch(_ query: CityNodeSearchQuery) async throws '
                                                      '-> CityNodeSearchResults\n'
                                                      '    func cityActivityPage(_ query: CityNodeSearchQuery, page: '
                                                      'Int) async throws -> SearchMapActivityPage\n'
                                                      '    func nearby(area: RoamSearchArea) async throws -> '
                                                      'SearchMapNearbyResults\n',
                                            'after': '    func categories() async throws -> [DiscoveryCategory]\n'
                                                     '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                     'throws -> [MerchantDiscoveryRow]\n'
                                                     '    func search(_ query: GlobalSearchQuery) async throws -> '
                                                     'GlobalSearchResults\n'
                                                     '    func cityNodes(_ query: CityNodeSearchQuery) async throws -> '
                                                     '[SearchMapCityNode]\n'
                                                     '    func citySearch(_ query: CityNodeSearchQuery) async throws '
                                                     '-> CityNodeSearchResults\n'
                                                     '    func cityActivityPage(_ query: CityNodeSearchQuery, page: '
                                                     'Int) async throws -> SearchMapActivityPage\n'
                                                     '    func nearby(area: RoamSearchArea) async throws -> '
                                                     'SearchMapNearbyResults\n'},
                                           {'before': '}\n'
                                                      '/// Older fixture readers have no discovery data; do not invent '
                                                      'empty successful results.\n'
                                                      'public extension SearchMapReading {\n'
                                                      '    var manualAreaRevision: UInt64 { 0 }\n'
                                                      '    func selectManualArea(_ area: RoamSearchArea?) {}\n'
                                                      '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                      'throws -> [MerchantDiscoveryRow] { throw APIError.notConfigured '
                                                      '}\n',
                                            'after': '}\n'
                                                     '/// Older fixture readers have no discovery data; do not invent '
                                                     'empty successful results.\n'
                                                     'public extension SearchMapReading {\n'
                                                     '    func cityNodes(_ query: CityNodeSearchQuery) async throws -> '
                                                     '[SearchMapCityNode] { throw APIError.notConfigured }\n'
                                                     '    var manualAreaRevision: UInt64 { 0 }\n'
                                                     '    func selectManualArea(_ area: RoamSearchArea?) {}\n'
                                                     '    func merchantDiscovery(tag: MerchantDiscoveryTag) async '
                                                     'throws -> [MerchantDiscoveryRow] { throw APIError.notConfigured '
                                                     '}\n'},
                                           {'before': '            if token != nil, !result.gatedKinds.isEmpty { throw '
                                                      'APIError.unauthorized }\n'
                                                      '            return result\n'
                                                      '        }\n'
                                                      '    }\n'
                                                      '    public func citySearch(_ query: CityNodeSearchQuery) async '
                                                      'throws -> CityNodeSearchResults {\n'
                                                      '        manualAreaSelection?.ensureSelected(query.area)\n',
                                            'after': '            if token != nil, !result.gatedKinds.isEmpty { throw '
                                                     'APIError.unauthorized }\n'
                                                     '            return result\n'
                                                     '        }\n'
                                                     '    }\n'
                                                     '    public func cityNodes(_ query: CityNodeSearchQuery) async '
                                                     'throws -> [SearchMapCityNode] {\n'
                                                     '        // Injection does not activate an unapproved reader.\n'
                                                     '        guard currentContext().manualMapApprovalRevision != nil '
                                                     'else { throw APIError.notConfigured }\n'
                                                     '        manualAreaSelection?.ensureSelected(query.area)\n'
                                                     '        return try await read { try await $0.cityNodes(query, '
                                                     'token: $1) }\n'
                                                     '    }\n'
                                                     '    public func citySearch(_ query: CityNodeSearchQuery) async '
                                                     'throws -> CityNodeSearchResults {\n'
                                                     '        manualAreaSelection?.ensureSelected(query.area)\n'}]},
 'App/SearchMapFilterSheet.swift': {'before_sha256': '33348878001340ef3962016363280702c5be0b2377e0af6be881da7855512871',
                                    'after_sha256': 'a5e636bf36cc439e29071e4f0833ae885587a160ae2a3ae7d548fefb36845620',
                                    'hunks': [{'before': '                    if categoryFailed { '
                                                         'Text("searchMap.categoryFailed").font(.caption) }\n'
                                                         '                }\n'
                                                         '                Section("searchMap.dates") {\n'
                                                         '                    if applyCityOptions != nil {\n'
                                                         '                        Button("mapDatePreset.today") { '
                                                         'selectDatePreset(.today) }\n'
                                                         '                            .frame(minHeight: '
                                                         '44).accessibilityIdentifier("mapDatePreset.today")\n'
                                                         '                        Button("mapDatePreset.tomorrow") { '
                                                         'selectDatePreset(.tomorrow) }\n'
                                                         '                            .frame(minHeight: '
                                                         '44).accessibilityIdentifier("mapDatePreset.tomorrow")\n'
                                                         '                        '
                                                         'Text("mapDatePreset.disclosure").font(.footnote).foregroundStyle(.secondary)\n'
                                                         '                    }\n'
                                                         '                    TextField("searchMap.startDate", text: '
                                                         '$dateDraft.startDate).accessibilityIdentifier("searchMap.filter.start")\n'
                                                         '                    Button("mapDatePicker.start") { '
                                                         'openDatePicker(.start) }\n',
                                               'after': '                    if categoryFailed { '
                                                        'Text("searchMap.categoryFailed").font(.caption) }\n'
                                                        '                }\n'
                                                        '                Section("searchMap.dates") {\n'
                                                        '                    Button("mapDatePreset.today") { '
                                                        'selectDatePreset(.today) }\n'
                                                        '                        .frame(minHeight: '
                                                        '44).accessibilityIdentifier("mapDatePreset.today")\n'
                                                        '                    Button("mapDatePreset.tomorrow") { '
                                                        'selectDatePreset(.tomorrow) }\n'
                                                        '                        .frame(minHeight: '
                                                        '44).accessibilityIdentifier("mapDatePreset.tomorrow")\n'
                                                        '                    if applyCityOptions != nil {\n'
                                                        '                        '
                                                        'Text("mapDatePreset.disclosure").font(.footnote).foregroundStyle(.secondary)\n'
                                                        '                    } else {\n'
                                                        '                        '
                                                        'Text("globalDatePreset.disclosure").font(.footnote).foregroundStyle(.secondary)\n'
                                                        '                    }\n'
                                                        '                    TextField("searchMap.startDate", text: '
                                                        '$dateDraft.startDate).accessibilityIdentifier("searchMap.filter.start")\n'
                                                        '                    Button("mapDatePicker.start") { '
                                                        'openDatePicker(.start) }\n'}]},
 'App/RoamHistoryViews.swift': {'before_sha256': '1926c84b140127cb8f4c65aae81e7305dfb730b1f219459e4b05001baefe4751',
                                'after_sha256': '01690f38f74de0698dee84c8d28a8a2413b75d603444c59c6ffdc22d9c9b52b8',
                                'hunks': [{'before': '\n'
                                                     '@MainActor struct RoamHistoryView: View {\n'
                                                     '    let reader: any RoamExperienceReading\n'
                                                     '    @State private var records: [RoamHistoryRecord] = []\n'
                                                     '    @State private var error: Error?\n'
                                                     '    @State private var loaded = false\n'
                                                     '    var body: some View {\n'
                                                     '        ScrollView {\n'
                                                     '            LazyVStack(alignment: .leading, spacing: 16) {\n',
                                           'after': '\n'
                                                    '@MainActor struct RoamHistoryView: View {\n'
                                                    '    let reader: any RoamExperienceReading\n'
                                                    '    var liveDestination: (() -> AnyView)? = nil\n'
                                                    '    @State private var records: [RoamHistoryRecord] = []\n'
                                                    '    @State private var error: Error?\n'
                                                    '    @State private var loaded = false\n'
                                                    '    @State private var liveEntry = RoamHistoryLiveEntry()\n'
                                                    '    var body: some View {\n'
                                                    '        ScrollView {\n'
                                                    '            LazyVStack(alignment: .leading, spacing: 16) {\n'},
                                          {'before': '                    '
                                                     'ContentUnavailableView("roam.experience.historyEmpty", '
                                                     'systemImage: "figure.walk", description: '
                                                     'Text("roam.experience.historyEmptyHint"))\n'
                                                     '                        .accessibilityElement(children: '
                                                     '.contain)\n'
                                                     '                        '
                                                     '.accessibilityIdentifier("roam.experience.history.empty")\n'
                                                     '                } else {\n'
                                                     '                    let summary = RoamHistorySummary(records)\n'
                                                     '                    RoamExperienceCard {\n',
                                           'after': '                    '
                                                    'ContentUnavailableView("roam.experience.historyEmpty", '
                                                    'systemImage: "figure.walk", description: '
                                                    'Text("roam.experience.historyEmptyHint"))\n'
                                                    '                        .accessibilityElement(children: '
                                                    '.contain)\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("roam.experience.history.empty")\n'
                                                    '                    if liveEntry.canOpen(reader: reader, '
                                                    'hasDestination: liveDestination != nil) {\n'
                                                    '                        let presentationID = '
                                                    'liveEntry.presentationID\n'
                                                    '                        Button("roam.experience.live", '
                                                    'systemImage: "figure.walk") {\n'
                                                    '                            liveEntry.activate(reader: reader, '
                                                    'hasDestination: liveDestination != nil, presentationID: '
                                                    'presentationID)\n'
                                                    '                        }\n'
                                                    '                        .buttonStyle(.borderedProminent)\n'
                                                    '                        '
                                                    '.accessibilityIdentifier("roam.experience.history.live.open")\n'
                                                    '                    }\n'
                                                    '                } else {\n'
                                                    '                    let summary = RoamHistorySummary(records)\n'
                                                    '                    RoamExperienceCard {\n'},
                                          {'before': '                }\n'
                                                     '            }.padding()\n'
                                                     '        }.navigationTitle("roam.experience.history")\n'
                                                     '            .task(id: reader.identity) { load() }\n'
                                                     '            .accessibilityIdentifier("roam.experience.history")\n'
                                                     '    }\n'
                                                     '    private func load() {\n'
                                                     '        records = []; error = nil; loaded = false\n'
                                                     '        do { records = try reader.history(); loaded = true } '
                                                     'catch { self.error = error }\n'
                                                     '    }\n'
                                                     '}\n'
                                                     '@MainActor struct RoamHistoryDetailView: View {\n',
                                           'after': '                }\n'
                                                    '            }.padding()\n'
                                                    '        }.navigationTitle("roam.experience.history")\n'
                                                    '            .task(id: RoamHistoryLiveOwner(reader: reader)) { '
                                                    'load() }\n'
                                                    '            .onAppear { liveEntry.appear() }\n'
                                                    '            .onDisappear { liveEntry.disappear() }\n'
                                                    '            .onChange(of: RoamHistoryLiveOwner(reader: reader)) { '
                                                    '_, _ in\n'
                                                    '                liveEntry.retireIfOwnerChanged(reader: reader, '
                                                    'hasDestination: liveDestination != nil)\n'
                                                    '            }\n'
                                                    '            .onChange(of: liveDestination != nil) { _, _ in\n'
                                                    '                liveEntry.retireIfOwnerChanged(reader: reader, '
                                                    'hasDestination: liveDestination != nil)\n'
                                                    '            }\n'
                                                    '            .navigationDestination(item: $liveEntry.target) { '
                                                    'target in\n'
                                                    '                if liveEntry.matches(target, reader: reader, '
                                                    'hasDestination: liveDestination != nil), let liveDestination {\n'
                                                    '                    liveDestination()\n'
                                                    '                }\n'
                                                    '            }\n'
                                                    '            .accessibilityIdentifier("roam.experience.history")\n'
                                                    '    }\n'
                                                    '    private func load() {\n'
                                                    '        records = []; error = nil; loaded = false\n'
                                                    '        let snapshot = liveEntry.beginRead(reader: reader)\n'
                                                    '        do {\n'
                                                    '            records = try reader.history(); loaded = true\n'
                                                    '            liveEntry.acceptRead(isEmpty: records.isEmpty, '
                                                    'snapshot: snapshot, reader: reader)\n'
                                                    '        } catch { self.error = error }\n'
                                                    '    }\n'
                                                    '}\n'
                                                    '\n'
                                                    '/// This only selects the already supplied live screen. It never '
                                                    'creates or starts a roam session.\n'
                                                    'struct RoamHistoryLiveOwner: Equatable, Hashable {\n'
                                                    '    let readerID: ObjectIdentifier\n'
                                                    '    let scopeKey: String?\n'
                                                    '    let epoch: UInt64?\n'
                                                    '    let isConfigured: Bool\n'
                                                    '    @MainActor init(reader: any RoamExperienceReading) {\n'
                                                    '        let identity = reader.identity\n'
                                                    '        readerID = ObjectIdentifier(reader)\n'
                                                    '        // storageKey preserves the exact UTF-8 namespace, '
                                                    'market, deployment and account bytes.\n'
                                                    '        scopeKey = identity?.scope.storageKey\n'
                                                    '        epoch = identity?.epoch\n'
                                                    '        isConfigured = reader.isConfigured\n'
                                                    '    }\n'
                                                    '    var isAuthorized: Bool { scopeKey != nil && isConfigured }\n'
                                                    '}\n'
                                                    '@MainActor struct RoamHistoryLiveEntry {\n'
                                                    '    struct Target: Hashable {\n'
                                                    '        let id = UUID()\n'
                                                    '        let owner: RoamHistoryLiveOwner\n'
                                                    '    }\n'
                                                    '    private var owner: RoamHistoryLiveOwner?\n'
                                                    '    private var successfulEmptyRead = false\n'
                                                    '    private var visible = false\n'
                                                    '    private(set) var presentationID = UUID()\n'
                                                    '    var target: Target?\n'
                                                    '\n'
                                                    '    mutating func beginRead(reader: any RoamExperienceReading) -> '
                                                    'RoamHistoryLiveOwner {\n'
                                                    '        invalidate()\n'
                                                    '        let snapshot = RoamHistoryLiveOwner(reader: reader)\n'
                                                    '        owner = snapshot\n'
                                                    '        return snapshot\n'
                                                    '    }\n'
                                                    '    mutating func acceptRead(isEmpty: Bool, snapshot: '
                                                    'RoamHistoryLiveOwner, reader: any RoamExperienceReading) {\n'
                                                    '        successfulEmptyRead = isEmpty && owner == snapshot && '
                                                    'snapshot == RoamHistoryLiveOwner(reader: reader)\n'
                                                    '    }\n'
                                                    '    mutating func appear() { visible = true; presentationID = '
                                                    'UUID() }\n'
                                                    '    mutating func disappear() {\n'
                                                    '        // Pushing the live screen hides this view; retain its '
                                                    'active destination until native Back.\n'
                                                    '        visible = false; presentationID = UUID()\n'
                                                    '    }\n'
                                                    '    func canOpen(reader: any RoamExperienceReading, '
                                                    'hasDestination: Bool) -> Bool {\n'
                                                    '        visible && target == nil && hasDestination && '
                                                    'successfulEmptyRead && owner?.isAuthorized == true\n'
                                                    '            && owner == RoamHistoryLiveOwner(reader: reader)\n'
                                                    '    }\n'
                                                    '    mutating func activate(reader: any RoamExperienceReading, '
                                                    'hasDestination: Bool, presentationID: UUID) {\n'
                                                    '        guard self.presentationID == presentationID, '
                                                    'canOpen(reader: reader, hasDestination: hasDestination), let '
                                                    'owner else { return }\n'
                                                    '        target = Target(owner: owner)\n'
                                                    '    }\n'
                                                    '    func matches(_ target: Target, reader: any '
                                                    'RoamExperienceReading, hasDestination: Bool) -> Bool {\n'
                                                    '        self.target == target && hasDestination && '
                                                    'target.owner.isAuthorized\n'
                                                    '            && target.owner == RoamHistoryLiveOwner(reader: '
                                                    'reader)\n'
                                                    '    }\n'
                                                    '    mutating func retireIfOwnerChanged(reader: any '
                                                    'RoamExperienceReading, hasDestination: Bool) {\n'
                                                    '        if owner != RoamHistoryLiveOwner(reader: reader) || '
                                                    '!hasDestination { invalidate() }\n'
                                                    '    }\n'
                                                    '    private mutating func invalidate() {\n'
                                                    '        target = nil; owner = nil; successfulEmptyRead = false; '
                                                    'presentationID = UUID()\n'
                                                    '    }\n'
                                                    '}\n'
                                                    '@MainActor struct RoamHistoryDetailView: View {\n'}]},
 'App/RoamExperienceComponents.swift': None,
 'Core/RoamExperienceMath.swift': None,
 'Resources/Localizable.xcstrings': None}
ADDED_SUPPORT_PATHS = ('Tests/ContractChecks/test_global_search_category_recovery.py',
 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift',
 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift',
 'docs/global-search-category-recovery.md',
 'Tests/CoreTests/RoamRouteReplayTests.swift',
 'Tests/ContractChecks/test_roam_route_replay.py',
 'docs/roam-route-replay.md',
 'Tests/ContractChecks/test_category_roam_registration.py')
PARENT_TO_CATEGORY_DELTA = [{'path': ['feature_batch_sources', 'App/ClubGovernanceViews.swift'],
  'before': 'c635bf66b98375c4d691fffd8051b90bf145fe5cf66681dc9d5d462cd99ce89e',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'App/GlobalSearchView.swift', 'after_sha256'],
  'before': '174d78310f6ed62053df8ce70aaecc10b27fdd65831e3a8cb72b0fe9c5c2db71',
  'action': 'set',
  'value': '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78'},
 {'path': ['feature_batch_sources', 'App/GlobalSearchView.swift', 'hunks'],
  'before': '37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570',
  'action': 'splice',
  'start': 8,
  'stop': 8,
  'value': [{'before': 'import SwiftUI\n'
                       '\n'
                       '@MainActor struct GlobalSearchView<Destination: View>: View {\n'
                       '    let reader: any SearchMapReading\n'
                       '    var historyNamespace: String? = nil\n'
                       '    var publicMerchant = PublicMerchantHomeContext()\n'
                       '    var onSignIn: (() -> Void)? = nil\n'
                       '    let destination: (SearchMapDestination) -> Destination\n'
                       '    @State private var filter = GlobalSearchQuery()\n'
                       '    @State private var categories: [DiscoveryCategory] = []\n'
                       '    @State private var categoryFailed = false\n'
                       '    @State private var retainedResults = GlobalSearchRetainedResults()\n'
                       '    @State private var isVisible = false\n'
                       '    @State private var issue: String?\n',
             'after': 'import SwiftUI\n'
                      '\n'
                      '@MainActor struct GlobalSearchView<Destination: View>: View {\n'
                      '    @Environment(\\.scenePhase) private var scenePhase\n'
                      '    let reader: any SearchMapReading\n'
                      '    var historyNamespace: String? = nil\n'
                      '    var publicMerchant = PublicMerchantHomeContext()\n'
                      '    var onSignIn: (() -> Void)? = nil\n'
                      '    let destination: (SearchMapDestination) -> Destination\n'
                      '    @State private var filter = GlobalSearchQuery()\n'
                      '    @State private var categoryRecovery = SearchMapCategoryRecovery()\n'
                      '    @State private var categoryPresentationID = UUID()\n'
                      '    @State private var filterPresentationID = UUID()\n'
                      '    @State private var filterSheetVisible = false\n'
                      '    @State private var retainedResults = GlobalSearchRetainedResults()\n'
                      '    @State private var isVisible = false\n'
                      '    @State private var issue: String?\n'},
            {'before': '    @State private var showsFilters = false\n'
                       '    @State private var history: [String] = []\n'
                       '    @State private var historyFailure = false\n'
                       '    @State private var categoryGate = SearchMapQueryGate()\n'
                       '    @State private var preparedOwner: ReadOwner?\n'
                       '    private let historyStore = SearchMapLocalHistory()\n'
                       '\n',
             'after': '    @State private var showsFilters = false\n'
                      '    @State private var history: [String] = []\n'
                      '    @State private var historyFailure = false\n'
                      '    @State private var preparedOwner: ReadOwner?\n'
                      '    private let historyStore = SearchMapLocalHistory()\n'
                      '\n'},
            {'before': '                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, '
                       'set: setKeyword)).textInputAutocapitalization(.never)\n'
                       '                        .submitLabel(.search).onSubmit { Task { await search() } }\n'
                       '                        .accessibilityIdentifier("searchMap.keyword")\n'
                       '                    Button { showsFilters = true } label: { Label("searchMap.filters", '
                       'systemImage: "line.3.horizontal.decrease") }\n'
                       '                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: '
                       '44).accessibilityIdentifier("searchMap.filters")\n'
                       '                }.padding(12).background(.secondary.opacity(0.08), in: '
                       'RoundedRectangle(cornerRadius: 16))\n'
                       '                Button("searchMap.search") { Task { await search() } }\n',
             'after': '                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, '
                      'set: setKeyword)).textInputAutocapitalization(.never)\n'
                      '                        .submitLabel(.search).onSubmit { Task { await search() } }\n'
                      '                        .accessibilityIdentifier("searchMap.keyword")\n'
                      '                    Button { openFilters() } label: { Label("searchMap.filters", systemImage: '
                      '"line.3.horizontal.decrease") }\n'
                      '                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: '
                      '44).accessibilityIdentifier("searchMap.filters")\n'
                      '                }.padding(12).background(.secondary.opacity(0.08), in: '
                      'RoundedRectangle(cornerRadius: 16))\n'
                      '                Button("searchMap.search") { Task { await search() } }\n'},
            {'before': '        }\n'
                       '        .appNavigationTitle("searchMap.title")\n'
                       '        .sheet(isPresented: $showsFilters) {\n'
                       '            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: '
                       'categoryFailed) { next in\n'
                       '                applyFilter(next)\n'
                       '            }\n'
                       '        }\n'
                       '        .task(id: readOwner) { await prepare() }\n'
                       '        .onAppear { isVisible = true }\n'
                       '        .onDisappear { isVisible = false; retainedResults.cancelPending(); '
                       'categoryGate.invalidate(); loading = false }\n'
                       '    }\n'
                       '    @ViewBuilder private var suggestions: some View {\n'
                       '        if !history.isEmpty {\n'
                       '            HStack {\n'
                       '                Text("searchMap.history").font(.headline)\n',
             'after': '        }\n'
                      '        .appNavigationTitle("searchMap.title")\n'
                      '        .sheet(isPresented: $showsFilters) {\n'
                      '            let presentationID = filterPresentationID\n'
                      '            let context = categoryRecovery.context(for: categoryOwner)\n'
                      '            let applyContext = categoryRecovery.presentationContext(for: categoryOwner)\n'
                      '            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: '
                      'categoryFailed,\n'
                      '                                 categoryLoading: categoryLoading, categoryLoaded: '
                      'categoryLoaded,\n'
                      '                                 retryCategories: context.map { captured in {\n'
                      '                                     guard showsFilters, filterSheetVisible, presentationID == '
                      'filterPresentationID else { return }\n'
                      '                                     _ = categoryRecovery.retry(in: captured)\n'
                      '                                 } }) { next in\n'
                      '                guard showsFilters, filterSheetVisible, presentationID == '
                      'filterPresentationID,\n'
                      '                      let applyContext, categoryRecovery.acceptsPresentation(applyContext) else '
                      '{ return }\n'
                      '                applyFilter(next)\n'
                      '            }\n'
                      '            .onAppear {\n'
                      '                guard showsFilters, presentationID == filterPresentationID, '
                      'categoryRecovery.owns(categoryOwner) else { return }\n'
                      '                filterSheetVisible = true; updateCategoryPresentation()\n'
                      '            }\n'
                      '            .onDisappear {\n'
                      '                guard presentationID == filterPresentationID, '
                      'categoryRecovery.owns(categoryOwner) else { return }\n'
                      '                filterSheetVisible = false; updateCategoryPresentation()\n'
                      '            }\n'
                      '        }\n'
                      '        .task(id: readOwner) { await prepare() }\n'
                      '        .onChange(of: categoryOwner) { _, _ in updateCategoryPresentation() }\n'
                      '        .onChange(of: scenePhase) { _, _ in updateCategoryPresentation() }\n'
                      '        .onChange(of: showsFilters) { _, visible in\n'
                      '            if !visible { filterSheetVisible = false }\n'
                      '            updateCategoryPresentation()\n'
                      '        }\n'
                      '        .onAppear { isVisible = true; categoryPresentationID = UUID(); '
                      'updateCategoryPresentation() }\n'
                      '        .onDisappear {\n'
                      '            isVisible = false; retainedResults.cancelPending(); loading = false\n'
                      '            categoryRecovery.update(reader: reader, presentationID: nil, active: false)\n'
                      '        }\n'
                      '    }\n'
                      '    private var categoryOwner: SearchMapCategoryRecovery.Owner { .init(reader: reader) }\n'
                      '    private var categories: [DiscoveryCategory] { categoryRecovery.owns(categoryOwner) ? '
                      'categoryRecovery.categories : [] }\n'
                      '    private var categoryFailed: Bool { categoryRecovery.owns(categoryOwner) && '
                      'categoryRecovery.phase == .failed }\n'
                      '    private var categoryLoading: Bool { categoryRecovery.owns(categoryOwner) && '
                      'categoryRecovery.phase == .loading }\n'
                      '    private var categoryLoaded: Bool { categoryRecovery.owns(categoryOwner) && '
                      'categoryRecovery.phase == .loaded }\n'
                      '    private func openFilters() {\n'
                      '        filterPresentationID = UUID(); filterSheetVisible = false; showsFilters = true\n'
                      '        updateCategoryPresentation()\n'
                      '    }\n'
                      '    private func updateCategoryPresentation() {\n'
                      '        // The page and sheet share the directory, never a draft or search request.\n'
                      '        // Switching surfaces retires callbacks; a settled directory survives reopening.\n'
                      '        let presentationID = showsFilters ? (filterSheetVisible ? filterPresentationID : nil) : '
                      'categoryPresentationID\n'
                      '        categoryRecovery.update(reader: reader, presentationID: presentationID,\n'
                      '                                active: isVisible && scenePhase == .active)\n'
                      '        if let context = categoryRecovery.context(for: categoryOwner) {\n'
                      '            categoryRecovery.loadIfNeeded(in: context)\n'
                      '        }\n'
                      '    }\n'
                      '    @ViewBuilder private var suggestions: some View {\n'
                      '        let context = categoryRecovery.context(for: categoryOwner)\n'
                      '        if !history.isEmpty {\n'
                      '            HStack {\n'
                      '                Text("searchMap.history").font(.headline)\n'},
            {'before': '            }\n'
                       '        }\n'
                       '        Text("searchMap.categories").font(.headline)\n'
                       '        if categoryFailed { SearchMapIssue(key: "searchMap.categoryFailed") { Task { await '
                       'prepare(force: true) } } }\n'
                       '        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n'
                       '            ForEach(categories) { category in\n'
                       '                Button {\n'
                       '                    var next = filter; next.categoryID = category.id; applyFilter(next)\n'
                       '                } label: {\n'
                       '                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n',
             'after': '            }\n'
                      '        }\n'
                      '        Text("searchMap.categories").font(.headline)\n'
                      '        if categoryLoading {\n'
                      '            '
                      'ProgressView("searchMap.loading").accessibilityIdentifier("globalSearch.category.loading")\n'
                      '        } else if categoryFailed {\n'
                      '            SearchMapIssue(key: "searchMap.categoryFailed") {\n'
                      '                guard !showsFilters, let context else { return }\n'
                      '                _ = categoryRecovery.retry(in: context)\n'
                      '            }\n'
                      '        }\n'
                      '        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n'
                      '            ForEach(categories) { category in\n'
                      '                Button {\n'
                      '                    guard !showsFilters, let context, categoryRecovery.accepts(context) else { '
                      'return }\n'
                      '                    var next = filter; next.categoryID = category.id; applyFilter(next)\n'
                      '                } label: {\n'
                      '                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n'},
            {'before': '        invalidate(); filter.keyword = value\n'
                       '    }\n'
                       '    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; '
                       'selectedKind = nil }\n'
                       '    private func prepare(force: Bool = false) async {\n'
                       '        if preparedOwner != readOwner {\n'
                       '            preparedOwner = readOwner; invalidate(); categories = []; categoryFailed = false\n'
                       '            history = historyStore.read(namespace: historyNamespace); historyFailure = '
                       'historyStore.failed\n'
                       '        }\n'
                       '        guard reader.isConfigured, force || categories.isEmpty else { return }\n'
                       '        let ticket = categoryGate.begin(scope: reader.scope)\n'
                       '        do {\n'
                       '            let value = try await reader.categories()\n'
                       '            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; '
                       'categories = value; categoryFailed = false\n'
                       '        } catch {\n'
                       '            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; '
                       'categoryFailed = true\n'
                       '        }\n'
                       '    }\n'
                       '    private func search() async {\n'
                       '        let query = filter\n',
             'after': '        invalidate(); filter.keyword = value\n'
                      '    }\n'
                      '    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; '
                      'selectedKind = nil }\n'
                      '    private func prepare() async {\n'
                      '        guard !Task.isCancelled else { return }\n'
                      '        if preparedOwner != readOwner {\n'
                      '            preparedOwner = readOwner; invalidate()\n'
                      '            history = historyStore.read(namespace: historyNamespace); historyFailure = '
                      'historyStore.failed\n'
                      '        }\n'
                      '        updateCategoryPresentation()\n'
                      '    }\n'
                      '    private func search() async {\n'
                      '        let query = filter\n'}]},
 {'path': ['feature_batch_sources', 'App/MerchantBusinessEditor.swift', 'after_sha256'],
  'before': '67b852532b465c62cfae6f668ef0d6baf751dc2d6bb7701625f9655b11ec26c0',
  'action': 'set',
  'value': '37e4fb670565770a72f1c1ad0e1c5b2ac4affc35669514597c80790d4e8f394d'},
 {'path': ['feature_batch_sources', 'App/MerchantBusinessEditor.swift', 'hunks'],
  'before': '9205dec16d8c192e382a466ebf8f1dde7c930e1f227da4cf84ae866c12add914',
  'action': 'splice',
  'start': 6,
  'stop': 7,
  'value': []},
 {'path': ['feature_batch_sources', 'App/MerchantOperationsEditor.swift', 'after_sha256'],
  'before': '6326778c3e36fb1282a9d0676c5d83d9612953fb45ca4a73219118c16b23c98e',
  'action': 'set',
  'value': '3e1a134db3355e63c068fcb4ff5dbb5abc7d7ac00488c6548d9a054339e80e1f'},
 {'path': ['feature_batch_sources', 'App/MerchantOperationsEditor.swift', 'hunks'],
  'before': 'c750691c49a6fe75117fca99b118bdc27acbb3f42ed6766361646c3a4fb46478',
  'action': 'splice',
  'start': 4,
  'stop': 5,
  'value': []},
 {'path': ['feature_batch_sources', 'App/ProjectNodeImageCrop.swift'],
  'before': '1e3c444f460d833e3724a8f1e0bd0022043650711fd2374cb44778ff97085fcd',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'App/SearchMapFilterSheet.swift', 'after_sha256'],
  'before': 'c5ca57943a46cbdc2bc77a0f6a82ba703e4e2cddb794d3048dd473abd87693df',
  'action': 'set',
  'value': 'd805599b752fcd104e40b382fb30d5bc96b9f8f27622766bfaefeed402c07b54'},
 {'path': ['feature_batch_sources', 'App/SearchMapFilterSheet.swift', 'hunks'],
  'before': '37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570',
  'action': 'splice',
  'start': 1,
  'stop': 1,
  'value': [{'before': '    let applyCityOptions: ((String, String, Int) -> Void)?\n'
                       '    let categories: [DiscoveryCategory]\n'
                       '    let categoryFailed: Bool\n'
                       '    let apply: (GlobalSearchQuery) -> Void\n'
                       '    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool,\n'
                       '         tag: String = "", cityRole: String = "", sortType: Int = 1,\n'
                       '         applyCityOptions: ((String, String, Int) -> Void)? = nil, apply: @escaping '
                       '(GlobalSearchQuery) -> Void) {\n'
                       '        _draft = State(initialValue: filter)\n',
             'after': '    let applyCityOptions: ((String, String, Int) -> Void)?\n'
                      '    let categories: [DiscoveryCategory]\n'
                      '    let categoryFailed: Bool\n'
                      '    let categoryLoading: Bool\n'
                      '    let categoryLoaded: Bool\n'
                      '    let retryCategories: (() -> Void)?\n'
                      '    let apply: (GlobalSearchQuery) -> Void\n'
                      '    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool,\n'
                      '         categoryLoading: Bool = false, categoryLoaded: Bool = false, retryCategories: (() -> '
                      'Void)? = nil,\n'
                      '         tag: String = "", cityRole: String = "", sortType: Int = 1,\n'
                      '         applyCityOptions: ((String, String, Int) -> Void)? = nil, apply: @escaping '
                      '(GlobalSearchQuery) -> Void) {\n'
                      '        _draft = State(initialValue: filter)\n'},
            {'before': '        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")\n'
                       '        _dateDraft = State(initialValue: SearchMapDateFilterDraft(filter: filter))\n'
                       '        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = '
                       'apply\n'
                       '    }\n'
                       '    var body: some View {\n'
                       '        NavigationStack {\n',
             'after': '        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")\n'
                      '        _dateDraft = State(initialValue: SearchMapDateFilterDraft(filter: filter))\n'
                      '        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = apply\n'
                      '        self.categoryLoading = categoryLoading; self.categoryLoaded = categoryLoaded; '
                      'self.retryCategories = retryCategories\n'
                      '    }\n'
                      '    var body: some View {\n'
                      '        NavigationStack {\n'},
            {'before': '                    Picker("searchMap.category", selection: $draft.categoryID) {\n'
                       '                        Text("searchMap.all").tag(Int?.none)\n'
                       '                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }\n'
                       '                    }\n'
                       '                    .accessibilityIdentifier("searchMap.filter.category")\n'
                       '                    if categoryFailed { Text("searchMap.categoryFailed").font(.caption) }\n'
                       '                }\n'
                       '                Section("searchMap.dates") {\n'
                       '                    Button("mapDatePreset.today") { selectDatePreset(.today) }\n',
             'after': '                    Picker("searchMap.category", selection: $draft.categoryID) {\n'
                      '                        Text("searchMap.all").tag(Int?.none)\n'
                      '                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }\n'
                      '                        // Keep an explicit tag for a selection missing from the new '
                      'directory.\n'
                      "                        // Only the user's selection/reset/Apply may change this manual draft.\n"
                      '                        if let selectedID = draft.categoryID, !categories.contains(where: { '
                      '$0.id == selectedID }) {\n'
                      '                            (Text("searchMap.category") + Text(verbatim: " #\\(selectedID)"))\n'
                      '                                .tag(Optional(selectedID))\n'
                      '                        }\n'
                      '                    }\n'
                      '                    .accessibilityIdentifier("searchMap.filter.category")\n'
                      '                    if categoryLoading {\n'
                      '                        '
                      'ProgressView("searchMap.loading").accessibilityIdentifier("searchMap.category.loading")\n'
                      '                    } else if categoryFailed {\n'
                      '                        Text("searchMap.categoryFailed").font(.caption)\n'
                      '                            .accessibilityIdentifier("searchMap.category.failed")\n'
                      '                        if let retryCategories {\n'
                      '                            Button("searchMap.retry", action: retryCategories).frame(minHeight: '
                      '44)\n'
                      '                                .accessibilityIdentifier("searchMap.category.retry")\n'
                      '                        }\n'
                      '                    } else if categoryLoaded && categories.isEmpty {\n'
                      '                        Text("searchMap.empty").font(.caption)\n'
                      '                            .accessibilityIdentifier("searchMap.category.empty")\n'
                      '                    }\n'
                      '                }\n'
                      '                Section("searchMap.dates") {\n'
                      '                    Button("mapDatePreset.today") { selectDatePreset(.today) }\n'}]},
 {'path': ['feature_batch_sources', 'Core/ClubCustomerHistoryTopicRoute.swift'],
  'before': 'a6e773edc9ae5920a4e1fb22a573ea82dfc2f0991df4761c66e89a75081782ec',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'Core/ClubGovernanceContracts.swift'],
  'before': '76632c1320fcc6ec6eb65b2697df3bf44150c65209c213b0977f2fc2d1f541d3',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'Core/ProfileEditCoordinator.swift', 'after_sha256'],
  'before': '2fcb7ae759943efbf9853cf9f1e6c720d25c491a2014e98679d72422ab15088c',
  'action': 'set',
  'value': '2abfe23ec770e6c0b6781c42b3a5b502a4855a8394ba46a4db5857eed563bb7b'},
 {'path': ['feature_batch_sources', 'Core/ProfileEditCoordinator.swift', 'hunks'],
  'before': 'e8e2474f08704fb066f3d358fe583db8a00857bc8af3baf2e4a65d980d9f67ac',
  'action': 'splice',
  'start': 5,
  'stop': 9,
  'value': []},
 {'path': ['feature_batch_sources', 'Core/SearchMapReading.swift', 'after_sha256'],
  'before': 'bd6b7eaf583db062f295daa7676c38e0e041f3e8950c95b2a0b2743991a61d1e',
  'action': 'set',
  'value': '34c67b5893b5ebba2eec8fdfc468a9b1662f4b94f86936d63d755385954d9aad'},
 {'path': ['feature_batch_sources', 'Core/SearchMapReading.swift', 'hunks'],
  'before': '37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570',
  'action': 'splice',
  'start': 3,
  'stop': 3,
  'value': [{'before': '    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { generation == '
                       'ticket.generation && ticket.scope == scope && !Task.isCancelled }\n'
                       '    public func invalidate() { generation &+= 1 }\n'
                       '}\n',
             'after': '    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { generation == '
                      'ticket.generation && ticket.scope == scope && !Task.isCancelled }\n'
                      '    public func invalidate() { generation &+= 1 }\n'
                      '}\n'
                      '\n'
                      'import Observation\n'
                      '\n'
                      '/// Read-only category directory for one visible filter presentation. The directory\n'
                      '/// never owns a query/draft, applies filters, or grants any reader capability.\n'
                      '@Observable @MainActor public final class SearchMapCategoryRecovery {\n'
                      '    public enum Phase: Equatable { case idle, loading, loaded, failed }\n'
                      '    public struct Owner: Hashable {\n'
                      '        public let readerID: ObjectIdentifier\n'
                      '        public let scope: UUID\n'
                      '        public let configured: Bool\n'
                      '        public let authenticated: Bool\n'
                      '        public let manualAreaRevision: UInt64\n'
                      '        @MainActor public init(reader: any SearchMapReading) {\n'
                      '            readerID = ObjectIdentifier(reader); scope = reader.scope\n'
                      '            configured = reader.isConfigured; authenticated = reader.isAuthenticated\n'
                      '            manualAreaRevision = reader.manualAreaRevision\n'
                      '        }\n'
                      '    }\n'
                      '    public struct Context: Equatable {\n'
                      '        fileprivate let owner: Owner\n'
                      '        fileprivate let presentationID: UUID\n'
                      '        fileprivate let generation: UUID\n'
                      '    }\n'
                      '    public private(set) var categories: [DiscoveryCategory] = []\n'
                      '    public private(set) var phase: Phase = .idle\n'
                      '    private var settledPhase: Phase = .idle\n'
                      '    private var owner: Owner?\n'
                      '    private var presentationID: UUID?\n'
                      '    private var active = false\n'
                      '    private var generation = UUID()\n'
                      '    private var pending: UUID?\n'
                      '    @ObservationIgnored private weak var reader: (any SearchMapReading)?\n'
                      '    @ObservationIgnored private var task: Task<Void, Never>?\n'
                      '    public init() {}\n'
                      '    deinit { task?.cancel() }\n'
                      '\n'
                      '    /// Every observed lifetime transition retires old callbacks, including A/B/A.\n'
                      '    /// Reopening keeps a settled same-owner directory; interrupted reads may resume.\n'
                      '    public func update(reader: any SearchMapReading, presentationID: UUID?, active: Bool) {\n'
                      '        let next = Owner(reader: reader)\n'
                      '        if owner != next || self.presentationID != presentationID || self.active != active {\n'
                      '            generation = UUID(); task?.cancel(); task = nil; pending = nil\n'
                      '            if owner != next { categories = []; settledPhase = .idle }\n'
                      '            phase = settledPhase\n'
                      '        }\n'
                      '        self.reader = reader; owner = next\n'
                      '        self.presentationID = presentationID; self.active = active\n'
                      '    }\n'
                      '    public func owns(_ current: Owner) -> Bool {\n'
                      '        guard let reader else { return false }\n'
                      '        return owner == current && Owner(reader: reader) == current\n'
                      '    }\n'
                      '    /// Local filter edits require a current presentation, not a network capability.\n'
                      '    public func presentationContext(for current: Owner) -> Context? {\n'
                      '        guard active, owns(current), let presentationID else { return nil }\n'
                      '        return Context(owner: current, presentationID: presentationID, generation: generation)\n'
                      '    }\n'
                      '    public func acceptsPresentation(_ context: Context) -> Bool {\n'
                      '        self.presentationContext(for: context.owner) == context\n'
                      '    }\n'
                      '    /// A local Apply context must never authorize a category read while unconfigured.\n'
                      '    public func context(for current: Owner) -> Context? {\n'
                      '        guard current.configured else { return nil }\n'
                      '        return presentationContext(for: current)\n'
                      '    }\n'
                      '    public func accepts(_ context: Context) -> Bool {\n'
                      '        self.context(for: context.owner) == context\n'
                      '    }\n'
                      '    @discardableResult public func loadIfNeeded(in context: Context) -> Task<Void, Never>? {\n'
                      '        guard phase == .idle else { return nil }\n'
                      '        return begin(in: context)\n'
                      '    }\n'
                      '    @discardableResult public func retry(in context: Context) -> Task<Void, Never>? {\n'
                      '        guard phase == .failed else { return nil }\n'
                      '        return begin(in: context)\n'
                      '    }\n'
                      '    private func begin(in context: Context) -> Task<Void, Never>? {\n'
                      '        guard !Task.isCancelled, pending == nil, accepts(context), let reader else { return nil '
                      '}\n'
                      '        let requestID = UUID()\n'
                      '        // Acquire the single-flight slot before queuing asynchronous work.\n'
                      '        pending = requestID; phase = .loading\n'
                      '        let request = Task { [weak self, weak reader] in\n'
                      '            defer { self?.finishPending(requestID) }\n'
                      '            guard !Task.isCancelled, let reader, self?.accepts(context) == true else { return '
                      '}\n'
                      '            do {\n'
                      '                let values = try await reader.categories()\n'
                      '                guard !Task.isCancelled, let self, self.pending == requestID, '
                      'self.accepts(context) else { return }\n'
                      '                self.categories = values // An authoritative empty array is a successful '
                      'directory.\n'
                      '                self.settledPhase = .loaded; self.phase = .loaded\n'
                      '            } catch is CancellationError {\n'
                      '                // Cancellation restores the previous state; it is not a new failure.\n'
                      '            } catch {\n'
                      '                guard !Task.isCancelled, let self, self.pending == requestID, '
                      'self.accepts(context) else { return }\n'
                      '                self.settledPhase = .failed; self.phase = .failed\n'
                      '            }\n'
                      '        }\n'
                      '        task = request\n'
                      '        return request\n'
                      '    }\n'
                      '    private func finishPending(_ requestID: UUID) {\n'
                      '        guard pending == requestID else { return }\n'
                      '        pending = nil; task = nil\n'
                      '        if phase == .loading { phase = settledPhase }\n'
                      '    }\n'
                      '}\n'}]},
 {'path': ['feature_batch_sources', 'Questify.xcodeproj/project.pbxproj', 'after_sha256'],
  'before': '6883e4530fbca37c79bdca43fcb209f4ffb3e11cdfbbba3fde031f3c1c96ef71',
  'action': 'set',
  'value': 'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552'},
 {'path': ['feature_batch_sources', 'Questify.xcodeproj/project.pbxproj', 'hunks'],
  'before': '52d0cf99f6d80b742a26bbf95e3d4060fd16558c4e3a061bb5f5404feff359cf',
  'action': 'splice',
  'start': 206,
  'stop': 209,
  'value': []},
 {'path': ['feature_batch_sources', 'Tests/CoreTests/ClubGovernanceProductionTests.swift'],
  'before': 'cfa722c02b6910be22438f52fa82789dd7976ca6cfbdfc3193c49910c063dda4',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift'],
  'before': '8f14b344f58bcb72eb7268a38d3410600ccea57c455f0bf35d817b4054e13990',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'App/ProjectNodeImageCrop.swift'],
  'before': 'e486a844955b62dfa373c30989f0955412cfe75c872cfba7794bb07741ed1e04',
  'action': 'set',
  'value': 'f9997b618a2d850070052092f2e83ef8b81b7ee1bcadba1cb7e7b846e7ab964a'},
 {'path': ['feature_batch_support_sha256', 'Resources/Localizable.xcstrings'],
  'before': 'a01d298725f0209abe21f00a7845573740514181d7e1d3970ed2dd1ff1016126',
  'action': 'set',
  'value': '6e9a854e14c29ad90a8b4ed88735e5641d15efc53ca810fb49dc366d3509910a'},
 {'path': ['feature_batch_support_sha256', 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift'],
  'before': '1df7ddb22f7a28984e54fd748a84132b77ee7b6e0a6ecfb258c082ce37d22c1d',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'],
  'before': 'edca032ba88b7e2886e6443d30c27ba481180c22f341323004b545f8ec4793d1',
  'action': 'set',
  'value': 'caaae8dab10e8a9d69500cf1243d1b31311f0b8d4eda568a2dfc58c7ab10d0cc'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py'],
  'before': 'e51a7f3d7658daabff340a7505b6b0730c11214d7d4f94e8f1e3aec0a180f34a',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_club_customer_keyword_debounce.py'],
  'before': '4300286e5fe123977572507261b58ed0ae9986635123dab4ce8c47c3e132247a',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_club_customer_permissions.py'],
  'before': '486f0e1c2bf48819826c7fbfbd25d3cf17992c06b4d5416b830481efc37dcd24',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_global_search_category_recovery.py'],
  'before': None,
  'action': 'set',
  'value': '601d09dcf08c00f1de69a9d8cff4a69ba72925733840ec6020110e210a6060a5'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_merchant_decor_tag_picker.py'],
  'before': 'ba26e3e554981a70af63427ac35c1c03d881236aa0925023017fff3814aca4fa',
  'action': 'set',
  'value': '491182e97a8e53e1b3372c130d1a1f7857c10804302578a624c706d473e2fec7'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_merchant_review_draft_return.py'],
  'before': '7a182efdc5e19e88364b7dc8f340a9411230a26d7a18781b348d0432d25ae08f',
  'action': 'set',
  'value': 'e9f31299585059f9ce7f6e23002bd815471f7ba85e83707fe9fd571934dd1968'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_profile_avatar.py'],
  'before': '7a72694829eed0698bc0a35a850b3085b98b45c0f877258586f8b58bad9d0b1d',
  'action': 'set',
  'value': '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py'],
  'before': '2eebccd3f4fcae76a5d9b1ccfe6961b792e74651d9046acde80127248753e3b9',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_profile_reload_discard.py'],
  'before': '75ace966791986d90b86bf771cc7b2057a19b37c5ede5f95d2c9f24905627bdd',
  'action': 'set',
  'value': '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/ClubCustomerPermissionTests.swift'],
  'before': '108023cc9f80e19b7647eec88430fc3295589b3876eccf89ef54052a1df43166',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift'],
  'before': None,
  'action': 'set',
  'value': '4a78eca6ec1df117f1fd24675e775e7ffe4c6f1dc85f2e4988d223705092108e'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'],
  'before': '8254125aa4a884f5c921414223a88c3eb1383254dbdb4127b979d9311cee529d',
  'action': 'set',
  'value': '5e90fd3657fd322477dc3c28347fb0efc3e33553ae39ef4bf990308bf445de86'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/ProfileEditTests.swift'],
  'before': '543bd382680a1b81d5480030727a0e60aed607f23b5f75b5f070790c438b6721',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift'],
  'before': '49f0c005f050ea4b11e897d7091ae5a287c5015b18ded5996c5791eca142ffd4',
  'action': 'set',
  'value': 'c0d731ccb927b9bad2ae07f65fac52ac99f924e121c66bede81ee5b411742bba'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift'],
  'before': None,
  'action': 'set',
  'value': '4f7ed5b79dd4929b5eb828c53e1a07826e1a8b6ff78a09c0f55148faa24a4dad'},
 {'path': ['feature_batch_support_sha256', 'docs/club-customer-keyword-debounce.md'],
  'before': 'fb566ab4570fac0340d6e2e614e9f567f1aa355ea34edffb2b4509c1d2ea29c3',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'docs/club-customer-permissions.md'],
  'before': '8aa8718047b2ec4da1d6a7d19b288abdaf8bf3df0d84dcbb9a6e1749413a094d',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'docs/global-search-category-recovery.md'],
  'before': None,
  'action': 'set',
  'value': '886a26d9fa6bbe316551c53fb83d7cdfae754351693d9a671040f6a72c878dca'},
 {'path': ['feature_batch_support_sha256', 'docs/merchant-decor-tag-picker/implementation.md'],
  'before': 'a9ab2ea9ba3a17a861fde2315e664ff8912a95370b0e758782eb4a652780fe1d',
  'action': 'set',
  'value': '5d7d4a190a5b0146433d7e7d077789ce99fad2669f0a44798a067e7f1702b141'},
 {'path': ['feature_batch_support_sha256', 'tools/check_profile_read_failure_contract.py'],
  'before': '93be0320b66acf7ce52b812efd7cc93e035a6b2807f9566652d59686df2149a3',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'tools/club_customer_directory_admission.py'],
  'before': '05883b9edd5018bdeb8880a1b0729caf659b3194e2cac84e0f3bff5a0b0547a5',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'tools/tests/test_creator_shelf_state_history.py'],
  'before': '17cef4270aefc68b8b39fc0c10fe8d0fd25808e1647e686b49f5546a8330d414',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'tools/tests/test_gitleaks_configuration.py'],
  'before': '886f3811e0cb120f2018706fd68914c0020cacbb4a52cba572ce1602dc2335b3',
  'action': 'set',
  'value': '9ee49cce7ab873e11deae82b643f48abc57482ce316c43764a0a6aa5d7579e52'},
 {'path': ['followon_support_sha256', 'tools/run_static_checks.py'],
  'before': '2dd7cec71218f96c5d579f804542357c1f19e9ee5f5e110a80efa99856135937',
  'action': 'set',
  'value': '5765354aae29e6b044cd45bc6145c3a35b6420579295631a5c74bca4959a1ed4'},
 {'path': ['followon_support_sha256', 'tools/tests/test_native_static_checks.py'],
  'before': 'be67bf7aa3d544af21ac920f84f37d3f295277e3cc23d6d19bc8804bf6e5256e',
  'action': 'set',
  'value': 'f1a980c56b45f543465417d3a2d884a2dc1fc624eaeb6625d84ace7f88735f0c'}]
PARENT_TO_CATEGORY_ORDER = {'followon_support_sha256': ['tools/ci138_followon_handshake_contract.json',
                             'tools/tests/test_review_availability_inverse.py',
                             'tools/ci138_followon_projection.py',
                             'tools/story_reveal_arrival_inverse.py',
                             'tools/story_reveal_arrival_contract.json',
                             'tools/remaining_editor_drivers_inverse.py',
                             'tools/remaining_editor_drivers_contract.json',
                             'tools/review_availability_inverse.py',
                             'tools/review_availability_contract.json',
                             'tools/ci138_coupon_square_publication_driver.py',
                             'docs/ci138-coupon-square-publication-driver-contract.json',
                             'tools/tests/test_story_reveal_arrival.py',
                             'tools/tests/test_remaining_editor_drivers.py',
                             'tools/tests/test_ci138_coupon_square_publication_driver.py',
                             'tools/story_template_planning_contract.json',
                             'tools/player_map_history_planning_contract.json',
                             '.github/workflows/native-ios.yml',
                             'tools/run130_receipt_planning.py',
                             'App/SquareWorkspaceView.swift',
                             'tools/run_ui_shard.py',
                             'Core/ApprovedTopicReleasePublicationClient.swift',
                             'App/ApprovedReleasePreparationView.swift',
                             'tools/branch_history_handshake_planning_contract.json',
                             'tools/club_parity_planning_contract.json',
                             'tools/run130_receipt_planning_contract.json',
                             'tools/run130_prepared_readiness_contract.json',
                             'tools/run129_late_readiness_contract.json',
                             'App/CouponCodeView.swift',
                             'tools/ci_gates.py',
                             'tools/run129_repair_planning_contract.json',
                             'tools/ui_duration_weights.json',
                             'Tests/ContractChecks/test_run129_navigation_diagnostics.py',
                             'tools/branch_history_handshake_planning.py',
                             'Tests/AppUnitTests/PlayBranchHistoryFixtureHandshakeTests.swift',
                             'Tests/ContractChecks/test_branch_history_fixture_handshake.py',
                             'App/PublishingContextHandoffViews.swift',
                             'App/PlayBranchHistoryView.swift',
                             'App/PlayBranchHistoryFixtureSupport.swift',
                             'App/ProjectSubmissionEvidenceViews.swift',
                             'tools/tests/test_ci138_followon_integration.py',
                             'tools/run_static_checks.py',
                             'tools/tests/test_native_static_checks.py'],
 'feature_batch_sources': ['App/ProjectEditView.swift',
                           'App/ProjectEditDetailForms.swift',
                           'App/QuestifyDensityMap.swift',
                           'Tests/ContractChecks/test_ci138_map_readonly_enabled.py',
                           'Questify.xcodeproj/project.pbxproj',
                           'Tests/AppUITests/MerchantContentFlowTests.swift',
                           'App/AccountComplianceViews.swift',
                           'App/AppSession.swift',
                           'App/ClubOperationsViews.swift',
                           'App/DiscoveryReading.swift',
                           'App/MerchantBusinessRecordViews.swift',
                           'App/MerchantBusinessViews.swift',
                           'App/MerchantContentEditor.swift',
                           'App/MerchantContentViews.swift',
                           'App/MerchantNPCViews.swift',
                           'App/MerchantOperationsEditor.swift',
                           'App/MerchantOperationsViews.swift',
                           'App/QuestifyApp.swift',
                           'App/QuestifyImageEntityCard.swift',
                           'App/RoamBrowserView.swift',
                           'App/RoamItemDetailView.swift',
                           'App/SearchMapCanvas.swift',
                           'App/SearchMapExplorerView.swift',
                           'App/ShopNPCView.swift',
                           'App/TopicBrowserView.swift',
                           'Core/AccountComplianceCoordinator.swift',
                           'Core/AccountComplianceService.swift',
                           'Core/MerchantContentCommands.swift',
                           'Core/MerchantNPCCoordinators.swift',
                           'Core/MerchantStationContracts.swift',
                           'Core/RuntimeLocationProjection.swift',
                           'App/FreeExplorationViews.swift',
                           'App/MerchantOnboardingView.swift',
                           'App/MerchantTemplateAssistSheet.swift',
                           'App/MerchantTemplateSuggestionReviewPanel.swift',
                           'App/PlayExperienceView.swift',
                           'App/ProjectStoryAudioAuthorView.swift',
                           'App/PublicMerchantHomeView.swift',
                           'App/ShopNPCSessionHost.swift',
                           'Core/MerchantOnboardingContracts.swift',
                           'Core/MerchantOperationsContracts.swift',
                           'Core/MerchantOperationsReading.swift',
                           'Core/MerchantOperationsService.swift',
                           'Core/MerchantTemplateAssistFlow.swift',
                           'Core/MerchantTemplateSuggestionReview.swift',
                           'Core/ProjectStoryAudioFlow.swift',
                           'Core/ProjectStoryAudioJournal.swift',
                           'Core/ProjectStoryAudioTarget.swift',
                           'Core/PublicMerchantHome.swift',
                           'Core/RoamMerchant.swift',
                           'Core/ShopNPCContracts.swift',
                           'Core/ShopNPCCoordinator.swift',
                           'App/MerchantHomeView.swift',
                           'App/MerchantMarketingView.swift',
                           'App/NativeEntryLandingView.swift',
                           'App/ProjectEditRichStoryForms.swift',
                           'App/PublishingAIDraftSheet.swift',
                           'Core/MerchantMarketingModels.swift',
                           'Core/ProjectInitialState.swift',
                           'Core/PublishingAIDraftFlow.swift',
                           'App/OfficialEventsBrowserView.swift',
                           'Core/OfficialEventContracts.swift',
                           'Core/RoamContracts.swift',
                           'App/ActivityDetailView.swift',
                           'App/ProjectStoryTemplatePresentation.swift',
                           'App/ProjectStoryTemplateView.swift',
                           'App/ShopNPCFixtureView.swift',
                           'Core/ActivityDetail.swift',
                           'App/AccountView.swift',
                           'App/GrowthCenterView.swift',
                           'App/GrowthLeaderboardView.swift',
                           'App/MerchantNPCFixtureView.swift',
                           'Core/MerchantNPCContracts.swift',
                           'Core/MerchantNPCHTTP.swift',
                           'App/TemplateAuthoringView.swift',
                           'Core/TemplateAuthoringCoordinator.swift',
                           'Core/TemplateAuthoringService.swift',
                           'Core/TemplateAuthoringStorage.swift',
                           'App/ClubAIDesignView.swift',
                           'Core/ClubAIDesignFlow.swift',
                           'App/MerchantEngagementViews.swift',
                           'App/ProfileOrdersView.swift',
                           'App/ProjectEndingConditionPicker.swift',
                           'Core/ProfileContracts.swift',
                           'App/MerchantBusinessEditor.swift',
                           'Core/MerchantBusinessMutation.swift',
                           'App/MerchantNPCComposerRetention.swift',
                           'App/ObjectBadgeViews.swift',
                           'App/GlobalSearchView.swift',
                           'App/MerchantNPCKnowledgeDraftView.swift',
                           'Core/SearchMapService.swift',
                           'App/OwnedOrderComposition.swift',
                           'App/SearchMapFilterSheet.swift',
                           'App/ProfileEditView.swift',
                           'App/RoamExperienceHubView.swift',
                           'App/RoamHistoryViews.swift',
                           'App/TicketWalletDetailView.swift',
                           'App/SocialGuideViews.swift',
                           'App/TicketWalletModel.swift',
                           'App/TicketWalletView.swift',
                           'Core/ProfileEditContracts.swift',
                           'Core/ProfileEditCoordinator.swift',
                           'Core/ProfileEditService.swift',
                           'Core/TicketWalletReading.swift',
                           'Core/ProjectEditContract.swift',
                           'Core/ProjectEditCoordinator.swift',
                           'Core/ProjectEditDraft.swift',
                           'Core/ProjectEditHTTPService.swift',
                           'Core/ProjectEditStoryContract.swift',
                           'Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift',
                           'App/ProjectStoryImageAuthorView.swift',
                           'App/ProjectStoryImagePresentation.swift',
                           'Core/ProjectStoryImageTarget.swift',
                           'Core/MerchantBusinessCoordinator.swift',
                           'App/ProjectInitialStateEditor.swift',
                           'App/ProjectNodeBusinessHoursField.swift',
                           'Core/ProjectNodeBusinessHours.swift',
                           'App/AppCompositionRoot.swift',
                           'App/MerchantProjectsView.swift',
                           'Core/MerchantContentService.swift',
                           'App/ProjectEditPendingPresentation.swift',
                           'Core/SearchMapReading.swift'],
 'feature_batch_support_sha256': ['App/MerchantCityQuotaSummary.swift',
                                  'App/MerchantCustomerContactSummary.swift',
                                  'App/MerchantCustomerEmptyRecoverySection.swift',
                                  'App/MerchantStationServiceTimeFields.swift',
                                  'App/NPCChatDataView.swift',
                                  'App/NPCQuickQuestionBar.swift',
                                  'App/ProjectCategoryPicker.swift',
                                  'App/ProjectEditDatePicker.swift',
                                  'App/ProjectEditIssueNavigation.swift',
                                  'App/ProjectEditNodeDescriptionField.swift',
                                  'App/ProjectEditStarterPresentation.swift',
                                  'App/ProjectPendingNodeRemovalController.swift',
                                  'App/QuestifyProgressiveBlurArtwork.swift',
                                  'App/SearchMapLayerSelection.swift',
                                  'Core/MerchantCityClaimWithdrawal.swift',
                                  'Core/MerchantCityQuota.swift',
                                  'Core/MerchantCustomerContactPresentation.swift',
                                  'Core/MerchantCustomerEmptyRecovery.swift',
                                  'Core/MerchantNPCKnowledgeDraft.swift',
                                  'Core/MerchantNPCKnowledgeDraftCoordinator.swift',
                                  'Core/MerchantNPCKnowledgeValidation.swift',
                                  'Core/MerchantStationPauseChoice.swift',
                                  'Core/MerchantStationServiceWindow.swift',
                                  'Core/NPCChatData.swift',
                                  'Core/NPCChatDataCoordinator.swift',
                                  'Core/NPCQuickQuestion.swift',
                                  'Core/ProgressiveBlurParameters.swift',
                                  'Core/ProjectEditDateSelection.swift',
                                  'Core/ProjectEditIssueLocation.swift',
                                  'Core/ProjectPendingNodeRemoval.swift',
                                  'Core/RoamEventDestination.swift',
                                  'Core/RoamRetainedRead.swift',
                                  'Core/SearchMapLayerVisibility.swift',
                                  'Core/SearchMapViewportSelection.swift',
                                  'Resources/Localizable.xcstrings',
                                  'Resources/MerchantCityClaimWithdrawalLocalizations.fragment.json',
                                  'Resources/MerchantCityQuotaLocalizations.fragment.json',
                                  'Resources/MerchantCustomerContactLocalizations.fragment.json',
                                  'Resources/MerchantCustomerEmptyRecoveryLocalizations.fragment.json',
                                  'Resources/MerchantStationPauseLocalizations.fragment.json',
                                  'Resources/MerchantStationServiceTimeLocalizations.fragment.json',
                                  'Resources/ProjectCategoryPicker.xcstrings',
                                  'Resources/ProjectEditDatePicker.xcstrings',
                                  'Resources/ProjectPendingNodeRemoval.xcstrings',
                                  'Resources/ProjectPendingNodeRemovalLocalizations.fragment.json',
                                  'Resources/RoamEventDestinationLocalizations.fragment.json',
                                  'Resources/RoamRetainedReadLocalizations.fragment.json',
                                  'Resources/SearchMapLayerVisibilityLocalizations.fragment.json',
                                  'Resources/SearchMapViewportLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantCustomerContactSummaryTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCKnowledgeDraftViewTests.swift',
                                  'Tests/AppUnitTests/NPCChatDataViewTests.swift',
                                  'Tests/AppUnitTests/NPCQuickQuestionBarTests.swift',
                                  'Tests/AppUnitTests/ProjectCategoryPickerTests.swift',
                                  'Tests/AppUnitTests/ProjectEditDatePickerTests.swift',
                                  'Tests/AppUnitTests/ProjectEditExactAutosaveTests.swift',
                                  'Tests/AppUnitTests/ProjectEditIssueNavigationTests.swift',
                                  'Tests/AppUnitTests/ProjectEditNodeDescriptionFieldTests.swift',
                                  'Tests/AppUnitTests/ProjectPendingNodeRemovalControllerTests.swift',
                                  'Tests/AppUnitTests/QuestifyProgressiveBlurArtworkTests.swift',
                                  'Tests/AppUnitTests/RoamEventDestinationViewTests.swift',
                                  'Tests/AppUnitTests/RoamRetainedReadViewTests.swift',
                                  'Tests/AppUnitTests/SearchMapLayerVisibilityViewTests.swift',
                                  'Tests/AppUnitTests/SearchMapViewportSelectionViewTests.swift',
                                  'Tests/ContractChecks/merchant_customer_empty_inverse.py',
                                  'Tests/ContractChecks/test_merchant_business_access_lifetime.py',
                                  'Tests/ContractChecks/test_merchant_city_claim_withdrawal.py',
                                  'Tests/ContractChecks/test_merchant_city_quota.py',
                                  'Tests/ContractChecks/test_merchant_customer_contact.py',
                                  'Tests/ContractChecks/test_merchant_customer_empty_recovery.py',
                                  'Tests/ContractChecks/test_merchant_station_optional_fallback.py',
                                  'Tests/ContractChecks/test_merchant_station_service_time.py',
                                  'Tests/ContractChecks/test_run129_map_button_role.py',
                                  'Tests/ContractChecks/test_run130_topic_media_source_adapter.py',
                                  'Tests/CoreTests/MerchantCityClaimWithdrawalTests.swift',
                                  'Tests/CoreTests/MerchantCityQuotaTests.swift',
                                  'Tests/CoreTests/MerchantContentContractTests.swift',
                                  'Tests/CoreTests/MerchantCustomerContactPresentationTests.swift',
                                  'Tests/CoreTests/MerchantCustomerEmptyRecoveryTests.swift',
                                  'Tests/CoreTests/MerchantNPCKnowledgeDraftTests.swift',
                                  'Tests/CoreTests/MerchantStationPauseChoiceTests.swift',
                                  'Tests/CoreTests/MerchantStationServiceWindowTests.swift',
                                  'Tests/CoreTests/NPCChatDataTests.swift',
                                  'Tests/CoreTests/NPCQuickQuestionTests.swift',
                                  'Tests/CoreTests/ProgressiveBlurParametersTests.swift',
                                  'Tests/CoreTests/ProjectEditDateSelectionTests.swift',
                                  'Tests/CoreTests/ProjectEditIssueLocationTests.swift',
                                  'Tests/CoreTests/ProjectPendingNodeRemovalTests.swift',
                                  'Tests/CoreTests/RoamEventDestinationTests.swift',
                                  'Tests/CoreTests/RoamRetainedReadTests.swift',
                                  'Tests/CoreTests/SearchMapLayerVisibilityTests.swift',
                                  'Tests/CoreTests/SearchMapViewportSelectionTests.swift',
                                  'docs/merchant-city-claim-withdrawal/implementation.md',
                                  'docs/merchant-city-quota/implementation.md',
                                  'docs/merchant-customer-contact/implementation.md',
                                  'docs/merchant-customer-empty-recovery/implementation.md',
                                  'docs/merchant-station-pause/optional-fallback.md',
                                  'docs/merchant-station-service-time/implementation.md',
                                  'tools/ci138_followon_projection.py',
                                  'tools/map_readonly_contract.json',
                                  'tools/map_readonly_inverse.py',
                                  'tools/review_availability_inverse.py',
                                  'tools/run138_ci_entry_contract.json',
                                  'tools/tests/test_review_availability_inverse.py',
                                  'App/MerchantDecorTagEditor.swift',
                                  'App/MerchantFeaturedActivityPicker.swift',
                                  'App/MerchantFeaturedClearControl.swift',
                                  'App/MerchantOnboardingHoursEditor.swift',
                                  'App/MerchantTemplateSuggestionEditSheet.swift',
                                  'App/ProjectChapterAudioAuthorView.swift',
                                  'App/ProjectChapterAudioField.swift',
                                  'App/ProjectChapterAudioPresentation.swift',
                                  'App/ProjectEditorAudioPreview.swift',
                                  'App/ShopNPCQuestionReuseButton.swift',
                                  'App/ShopNPCScriptedGuideView.swift',
                                  'Core/MerchantDecorTagDraft.swift',
                                  'Core/MerchantFeaturedActivityOptions.swift',
                                  'Core/MerchantTemplateSuggestionEdit.swift',
                                  'Core/ProjectChapterAudio.swift',
                                  'Core/RoamFeaturedActivitySelection.swift',
                                  'Core/RoamPlayerProfileSelection.swift',
                                  'Core/RoamRouteTopicDestination.swift',
                                  'Core/ShopNPCQuestionReuse.swift',
                                  'Core/ShopNPCScriptedGuide.swift',
                                  'Resources/MerchantDecorTagLocalizations.fragment.json',
                                  'Resources/MerchantFeaturedActivityLocalizations.fragment.json',
                                  'Resources/MerchantFeaturedClearLocalizations.fragment.json',
                                  'Resources/MerchantOnboardingHoursLocalizations.fragment.json',
                                  'Resources/ProjectChapterAudio.xcstrings',
                                  'Resources/ProjectEditorAudioPreview.xcstrings',
                                  'Resources/ProjectInitialState.xcstrings',
                                  'Resources/PublicMerchantHomeBusinessStateLocalizations.fragment.json',
                                  'Resources/RoamMerchantBusinessStateLocalizations.fragment.json',
                                  'Resources/RoamPlayerProfileLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift',
                                  'Tests/AppUnitTests/MerchantFeaturedActivityPickerTests.swift',
                                  'Tests/AppUnitTests/MerchantFeaturedClearControlTests.swift',
                                  'Tests/AppUnitTests/MerchantOnboardingHoursSessionTests.swift',
                                  'Tests/AppUnitTests/MerchantTemplateSuggestionEditTests.swift',
                                  'Tests/AppUnitTests/ProjectChapterAudioFieldTests.swift',
                                  'Tests/AppUnitTests/ProjectChapterAudioPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectEditorAudioPreviewTests.swift',
                                  'Tests/AppUnitTests/ProjectInitialStateEditorTests.swift',
                                  'Tests/AppUnitTests/PublicMerchantHomeBusinessStateViewTests.swift',
                                  'Tests/AppUnitTests/RoamFeaturedActivitySelectionViewTests.swift',
                                  'Tests/AppUnitTests/RoamMerchantBusinessStateViewTests.swift',
                                  'Tests/AppUnitTests/RoamPlayerProfileSelectionViewTests.swift',
                                  'Tests/AppUnitTests/RoamRouteTopicDestinationViewTests.swift',
                                  'Tests/AppUnitTests/ShopNPCQuestionReuseTests.swift',
                                  'Tests/AppUnitTests/ShopNPCScriptedGuideTests.swift',
                                  'Tests/ContractChecks/test_merchant_decor_tag_picker.py',
                                  'Tests/ContractChecks/test_merchant_featured_activity_picker.py',
                                  'Tests/ContractChecks/test_merchant_featured_clear.py',
                                  'Tests/ContractChecks/test_merchant_onboarding_hours_editor.py',
                                  'Tests/ContractChecks/test_shop_npc_interruption.py',
                                  'Tests/CoreTests/MerchantDecorTagDraftTests.swift',
                                  'Tests/CoreTests/MerchantFeaturedActivityOptionsTests.swift',
                                  'Tests/CoreTests/MerchantFeaturedClearContractTests.swift',
                                  'Tests/CoreTests/MerchantOnboardingContractTests.swift',
                                  'Tests/CoreTests/MerchantOnboardingHoursTests.swift',
                                  'Tests/CoreTests/MerchantTemplateSuggestionEditTests.swift',
                                  'Tests/CoreTests/ProjectChapterAudioTests.swift',
                                  'Tests/CoreTests/ProjectChapterAudioUploadTests.swift',
                                  'Tests/CoreTests/ProjectInitialStateTests.swift',
                                  'Tests/CoreTests/PublicMerchantHomeBusinessStateTests.swift',
                                  'Tests/CoreTests/RoamFeaturedActivitySelectionTests.swift',
                                  'Tests/CoreTests/RoamMerchantBusinessStateTests.swift',
                                  'Tests/CoreTests/RoamPlayerProfileSelectionTests.swift',
                                  'Tests/CoreTests/RoamRouteTopicDestinationTests.swift',
                                  'Tests/CoreTests/ShopNPCQuestionReuseTests.swift',
                                  'Tests/CoreTests/ShopNPCScriptedGuideTests.swift',
                                  'docs/merchant-decor-tag-picker/implementation.md',
                                  'docs/merchant-featured-activity-picker/implementation.md',
                                  'docs/merchant-featured-clear/implementation.md',
                                  'docs/merchant-onboarding-hours/implementation.md',
                                  'App/MerchantInsightRecommendationRows.swift',
                                  'App/ProjectThoughtDefinitionsEditor.swift',
                                  'App/PublishingAIQuotaSection.swift',
                                  'Core/MerchantInsightRecommendation.swift',
                                  'Core/ProjectThoughtDefinitions.swift',
                                  'Resources/MerchantInsightNavigationLocalizations.fragment.json',
                                  'Resources/ProjectThoughtDefinitions.xcstrings',
                                  'Tests/AppUnitTests/ProjectThoughtDefinitionsEditorTests.swift',
                                  'Tests/AppUnitTests/PublishingAIQuotaSectionTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_navigation.py',
                                  'Tests/CoreTests/MerchantInsightRecommendationTests.swift',
                                  'Tests/CoreTests/ProjectThoughtDefinitionsTests.swift',
                                  'Tests/CoreTests/PublishingAIQuotaReadTests.swift',
                                  'docs/merchant-insight-navigation/implementation.md',
                                  'App/MerchantNPCConversationHistoryView.swift',
                                  'Core/MerchantNPCConversationHistory.swift',
                                  'Core/ProjectEndingConditionChoices.swift',
                                  'Resources/ProjectEndingConditionPicker.xcstrings',
                                  'Resources/RoamPlaceReadStatusLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantNPCComposerRetentionTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCConversationHistoryTests.swift',
                                  'Tests/AppUnitTests/OfficialEventBrowseStateViewTests.swift',
                                  'Tests/AppUnitTests/ProjectEndingConditionPickerTests.swift',
                                  'Tests/AppUnitTests/RoamPlaceReadStatusViewTests.swift',
                                  'Tests/ContractChecks/test_official_event_contracts.py',
                                  'Tests/ContractChecks/test_official_preference_ui_regressions.py',
                                  'Tests/CoreTests/MerchantNPCConversationHistoryTests.swift',
                                  'Tests/CoreTests/OfficialEventTests.swift',
                                  'Tests/CoreTests/ProjectEndingConditionChoicesTests.swift',
                                  'Tests/CoreTests/RoamPlaceReadStatusTests.swift',
                                  'App/MerchantInsightProfileSummary.swift',
                                  'App/ProjectNodeGameplayRemovalField.swift',
                                  'Core/ActivityRequiredClubSelection.swift',
                                  'Core/ProjectNodeGameplayRemoval.swift',
                                  'Resources/ActivityRequiredClubLocalizations.fragment.json',
                                  'Resources/MerchantInsightProfileLocalizations.fragment.json',
                                  'Resources/ProjectNodeGameplayRemoval.xcstrings',
                                  'Tests/AppUnitTests/ActivityRequiredClubSelectionViewTests.swift',
                                  'Tests/AppUnitTests/MerchantInsightProfileSummaryTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeGameplayRemovalFieldTests.swift',
                                  'Tests/AppUnitTests/PublishingAIDraftCandidateRetentionTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_profile_entry.py',
                                  'Tests/CoreTests/ActivityRequiredClubSelectionTests.swift',
                                  'Tests/CoreTests/ProjectNodeGameplayRemovalTests.swift',
                                  'Tests/CoreTests/PublishingAIDraftCandidateRetentionTests.swift',
                                  'docs/merchant-insight-profile-entry/implementation.md',
                                  'App/ProjectNodeTemplateSelectionField.swift',
                                  'Core/ProjectNodeTemplateSelection.swift',
                                  'Resources/ProjectNodeTemplateSelection.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodeTemplateSelectionPresentationTests.swift',
                                  'Tests/AppUnitTests/ShopNPCModernOutcomeTests.swift',
                                  'Tests/ContractChecks/check_shop_npc.py',
                                  'Tests/CoreTests/ProjectNodeTemplateSelectionTests.swift',
                                  'Tests/CoreTests/ShopNPCInterruptionTests.swift',
                                  'Tests/CoreTests/ShopNPCModernOutcomeTests.swift',
                                  'Tests/CoreTests/ShopNPCTests.swift',
                                  'App/ActivityAssociatedPlaysSection.swift',
                                  'App/MerchantInsightAttributionSummary.swift',
                                  'App/MerchantInsightRecentVisitorsSection.swift',
                                  'Core/MerchantInsightAttribution.swift',
                                  'Core/MerchantInsightRecentVisitors.swift',
                                  'Resources/ActivityAssociatedPlaysLocalizations.fragment.json',
                                  'Resources/MerchantInsightAttributionLocalizations.fragment.json',
                                  'Resources/MerchantInsightVisitorsLocalizations.fragment.json',
                                  'Tests/AppUnitTests/ActivityAssociatedPlaysViewTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_attribution.py',
                                  'Tests/ContractChecks/test_merchant_insight_recent_visitors.py',
                                  'Tests/CoreTests/ActivityAssociatedPlaysTests.swift',
                                  'Tests/CoreTests/MerchantInsightAttributionTests.swift',
                                  'Tests/CoreTests/MerchantInsightRecentVisitorsTests.swift',
                                  'docs/merchant-insight-attribution/implementation.md',
                                  'docs/merchant-insight-recent-visitors/implementation.md',
                                  'Resources/GrowthLeaderboardExploreLocalizations.fragment.json',
                                  'Resources/MerchantInsightInterpretationLocalizations.fragment.json',
                                  'Tests/AppUnitTests/GrowthLeaderboardExploreViewTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCResponseIdentityTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_interpretation.py',
                                  'Tests/CoreTests/MerchantInsightInterpretationTests.swift',
                                  'Tests/CoreTests/MerchantNPCResponseIdentityTests.swift',
                                  'Tests/CoreTests/MerchantNPCTests.swift',
                                  'docs/merchant-insight-interpretation/implementation.md',
                                  'App/ProjectNodeTemplateCreationField.swift',
                                  'Core/TemplateAuthoringSavedDraft.swift',
                                  'Resources/MerchantCoopCapacityClearLocalizations.fragment.json',
                                  'Resources/ProjectNodeTemplateCreation.xcstrings',
                                  'Tests/AppUnitTests/GrowthBadgeExploreViewTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeTemplateCreationTests.swift',
                                  'Tests/ContractChecks/test_merchant_coop_capacity_clear.py',
                                  'Tests/CoreTests/MerchantCoopCapacityClearTests.swift',
                                  'Tests/CoreTests/TemplateAuthoringSavedDraftTests.swift',
                                  'docs/merchant-coop-capacity-clear/implementation.md',
                                  'Resources/MerchantCoopChargeChoiceLocalizations.fragment.json',
                                  'Tests/AppUnitTests/ClubAIDesignCandidateRetentionTests.swift',
                                  'Tests/ContractChecks/test_merchant_coop_charge_choice.py',
                                  'Tests/CoreTests/ClubAIDesignCandidateRetentionTests.swift',
                                  'Tests/CoreTests/MerchantCoopChargeChoiceTests.swift',
                                  'Tests/CoreTests/MerchantOperationsTests.swift',
                                  'docs/merchant-coop-charge-choice/implementation.md',
                                  'App/MerchantCRMDateRangePicker.swift',
                                  'Core/MerchantCRMDateRange.swift',
                                  'Core/ProjectStoryConditionChoice.swift',
                                  'Resources/MerchantCRMDatePickerLocalizations.fragment.json',
                                  'Resources/ProfileOrderTicketScheduleLocalizations.fragment.json',
                                  'Tests/AppUnitTests/ProfileOrderTicketScheduleViewTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryConditionPickerTests.swift',
                                  'Tests/ContractChecks/test_merchant_crm_date_picker.py',
                                  'Tests/CoreTests/MerchantCRMDateRangeTests.swift',
                                  'Tests/CoreTests/ProfileOrderTicketScheduleTests.swift',
                                  'Tests/CoreTests/ProjectStoryConditionChoiceTests.swift',
                                  'docs/merchant-crm-date-picker/implementation.md',
                                  'App/MerchantNPCGreetingPreview.swift',
                                  'Resources/MerchantNoteCorrectionLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantNPCGreetingPreviewTests.swift',
                                  'Tests/ContractChecks/test_merchant_note_correction_presentation.py',
                                  'Tests/CoreTests/MerchantNoteCorrectionPresentationTests.swift',
                                  'docs/merchant-note-correction/implementation.md',
                                  'App/ProjectNodeRouteMappingEditor.swift',
                                  'Core/MerchantRedemptionFilter.swift',
                                  'Core/ProjectNodeRouteMapping.swift',
                                  'Resources/MerchantRedemptionFilterLocalizations.fragment.json',
                                  'Resources/ProjectNodeRouteMapping.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodeRouteMappingEditorTests.swift',
                                  'Tests/ContractChecks/test_merchant_redemption_filter.py',
                                  'Tests/CoreTests/MerchantNPCMessageDraftTests.swift',
                                  'Tests/CoreTests/MerchantRedemptionFilterTests.swift',
                                  'Tests/CoreTests/ProjectNodeRouteMappingTests.swift',
                                  'docs/merchant-redemption-filter/implementation.md',
                                  'App/MerchantNPCTranscriptScroll.swift',
                                  'Resources/MerchantAftercareDecisionLocalizations.fragment.json',
                                  'Resources/ObjectBadgeWallLayoutLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantAftercareDecisionChangeTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCTranscriptScrollTests.swift',
                                  'Tests/AppUnitTests/ObjectBadgeWallLayoutTests.swift',
                                  'Tests/ContractChecks/test_merchant_aftercare_decision_change.py',
                                  'Tests/ContractChecks/test_object_badge_wall_layout.py',
                                  'docs/merchant-aftercare-decision/implementation.md',
                                  'App/MerchantAftercareEvidenceFlow.swift',
                                  'App/MerchantNPCKnowledgeDismissal.swift',
                                  'App/ProjectNodePhotoRemovalField.swift',
                                  'Core/GlobalSearchRetainedResults.swift',
                                  'Core/ProjectNodePhotoRemoval.swift',
                                  'Resources/GlobalSearchRetentionLocalizations.fragment.json',
                                  'Resources/MerchantAftercareEvidenceLocalizations.fragment.json',
                                  'Resources/ProjectNodePhotoRemoval.xcstrings',
                                  'Tests/AppUnitTests/MerchantAftercareEvidenceFlowTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCKnowledgeDismissalTests.swift',
                                  'Tests/AppUnitTests/ProjectNodePhotoRemovalViewTests.swift',
                                  'Tests/ContractChecks/test_merchant_aftercare_evidence_flow.py',
                                  'Tests/CoreTests/GlobalSearchRetainedResultsTests.swift',
                                  'Tests/CoreTests/ProjectNodePhotoRemovalTests.swift',
                                  'docs/merchant-aftercare-evidence/implementation.md',
                                  'App/MerchantStationLiveCodeView.swift',
                                  'App/ProjectStoryVariablePicker.swift',
                                  'Core/ProjectStoryVariableInsertion.swift',
                                  'Resources/GlobalSearchDatePresetLocalizations.fragment.json',
                                  'Resources/MerchantStationLiveCodeLocalizations.fragment.json',
                                  'Resources/ProfileOrderTicketEntryLocalizations.fragment.json',
                                  'Resources/ProjectStoryVariableInsertion.xcstrings',
                                  'Tests/AppUnitTests/MerchantStationLiveCodeTests.swift',
                                  'Tests/AppUnitTests/ProfileOrderTicketNavigationTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryVariablePickerTests.swift',
                                  'Tests/AppUnitTests/SearchMapDatePresetDraftTests.swift',
                                  'Tests/ContractChecks/test_merchant_station_live_code.py',
                                  'Tests/ContractChecks/test_owned_order_composition.py',
                                  'Tests/ContractChecks/test_search_map_date_presets.py',
                                  'Tests/CoreTests/MerchantStationLiveCodeTimeTests.swift',
                                  'Tests/CoreTests/ProjectStoryVariableInsertionTests.swift',
                                  'docs/merchant-station-live-code/implementation.md',
                                  'App/ProjectDraftNodeOverview.swift',
                                  'Core/ProjectDraftNodeProjection.swift',
                                  'Resources/ProfileReloadDiscardLocalizations.fragment.json',
                                  'Resources/ProjectDraftNodeOverview.xcstrings',
                                  'Tests/AppUnitTests/ProfileReloadDiscardTests.swift',
                                  'Tests/AppUnitTests/ProjectDraftNodeOverviewTests.swift',
                                  'Tests/AppUnitTests/RoamHistoryLiveEntryTests.swift',
                                  'Tests/AppUnitTests/TicketWalletPlayEntryTests.swift',
                                  'Tests/ContractChecks/test_profile_reload_discard.py',
                                  'Tests/ContractChecks/test_roam_history_live_entry.py',
                                  'Tests/ContractChecks/test_ticket_wallet_play_entry.py',
                                  'Tests/CoreTests/ProjectDraftNodeProjectionTests.swift',
                                  'App/ExploreCompletionView.swift',
                                  'App/MerchantNPCRecoveryPresentation.swift',
                                  'App/SocialGuideTemplateSection.swift',
                                  'Core/ExploreCompletionContracts.swift',
                                  'Core/ExploreCompletionRead.swift',
                                  'Resources/ExploreCompletionLocalizations.fragment.json',
                                  'Resources/MerchantNPCRecoveryLocalizations.fragment.json',
                                  'Resources/ProjectNodeBusinessHours.xcstrings',
                                  'Resources/SocialGuideTemplateLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantNPCRecoveryPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeBusinessHoursViewTests.swift',
                                  'Tests/AppUnitTests/SocialGuideTemplateTests.swift',
                                  'Tests/ContractChecks/test_explore_completion_read.py',
                                  'Tests/ContractChecks/test_merchant_npc_recovery.py',
                                  'Tests/ContractChecks/test_social_guide_templates.py',
                                  'Tests/CoreTests/ExploreCompletionReadTests.swift',
                                  'Tests/CoreTests/ProjectNodeBusinessHoursTests.swift',
                                  'App/ProfileAvatarDraftSection.swift',
                                  'App/ProjectStoryTextField.swift',
                                  'App/ProjectStoryTextInsertionButton.swift',
                                  'Core/ProfileAvatarFlow.swift',
                                  'Core/ProfileAvatarJournal.swift',
                                  'Core/ProfileAvatarUpload.swift',
                                  'Core/ProjectEmptyStoryTextRemoval.swift',
                                  'Core/ProjectStoryTextInsertion.swift',
                                  'Resources/ProfileAvatarLocalizations.fragment.json',
                                  'Resources/ProjectStoryTextField.xcstrings',
                                  'Resources/ProjectStoryTextInsertion.xcstrings',
                                  'Tests/AppUnitTests/ProfileAvatarPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryTextFieldTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryTextInsertionButtonTests.swift',
                                  'Tests/ContractChecks/test_profile_avatar.py',
                                  'Tests/ContractChecks/test_ticket_wallet_read_lifetime.py',
                                  'Tests/CoreTests/ProfileAvatarTests.swift',
                                  'Tests/CoreTests/ProjectEmptyStoryTextRemovalTests.swift',
                                  'Tests/CoreTests/ProjectStoryTextInsertionTests.swift',
                                  'Tests/CoreTests/TicketWalletTests.swift',
                                  'App/TicketWalletTeamView.swift',
                                  'Core/ProjectChapterRecruitmentCarryOver.swift',
                                  'Resources/TicketWalletTeamLocalizations.fragment.json',
                                  'Tests/AppUnitTests/TicketWalletTeamTests.swift',
                                  'Tests/ContractChecks/test_ticket_wallet_team.py',
                                  'Tests/CoreTests/ProjectEditTests.swift',
                                  'App/MerchantStationSubmissionImportView.swift',
                                  'Core/MerchantStationSubmissionCode.swift',
                                  'Resources/MerchantStationSubmissionImportLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantStationSubmissionImportTests.swift',
                                  'Tests/ContractChecks/test_merchant_station_submission_import.py',
                                  'Tests/CoreTests/MerchantStationSubmissionCodeTests.swift',
                                  'App/ProjectAlbumImageAuthorField.swift',
                                  'Resources/ProjectAlbumImageAuthor.xcstrings',
                                  'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift',
                                  'Tests/CoreTests/ProjectStoryImageTests.swift',
                                  'Core/ProjectAlbumPhotoOrder.swift',
                                  'Resources/ProjectAlbumPhotoOrder.xcstrings',
                                  'Tests/AppUnitTests/ProjectAlbumPhotoOrderPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_album_photo_order.py',
                                  'Tests/CoreTests/ProjectAlbumPhotoOrderTests.swift',
                                  'App/MerchantOperatorInvitationReceiptView.swift',
                                  'Core/MerchantOperatorInvitationPresentation.swift',
                                  'Resources/MerchantOperatorInvitationReceiptLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantOperatorInvitationReceiptTests.swift',
                                  'Tests/ContractChecks/test_merchant_operator_invitation_receipt.py',
                                  'Tests/CoreTests/MerchantOperatorInvitationPresentationTests.swift',
                                  'App/ProjectInitialAttributesEditor.swift',
                                  'App/ProjectNodeDurationField.swift',
                                  'Core/ProjectInitialAttributes.swift',
                                  'Core/ProjectNodeDuration.swift',
                                  'Resources/ProjectInitialAttributes.xcstrings',
                                  'Resources/ProjectNodeDuration.xcstrings',
                                  'Tests/AppUnitTests/ProjectInitialAttributesPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeDurationPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_initial_attributes.py',
                                  'Tests/ContractChecks/test_project_node_duration.py',
                                  'Tests/CoreTests/ProjectInitialAttributesTests.swift',
                                  'Tests/CoreTests/ProjectNodeDurationTests.swift',
                                  'Tests/ContractChecks/test_project_node_business_hours_clear.py',
                                  'App/ProjectRichStoryInsertionButton.swift',
                                  'Core/ProjectRichStoryInsertion.swift',
                                  'Resources/ProjectRichStoryInsertion.xcstrings',
                                  'Tests/AppUnitTests/ProjectRichStoryInsertionPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_rich_story_insertion.py',
                                  'Tests/CoreTests/ProjectRichStoryInsertionTests.swift',
                                  'App/MerchantReviewPhotoGallery.swift',
                                  'Resources/MerchantReviewPhotoGalleryLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantReviewPhotoGalleryTests.swift',
                                  'Tests/ContractChecks/test_merchant_review_photo_gallery.py',
                                  'App/ProjectAlbumPhotoRemovalButton.swift',
                                  'Core/ProjectAlbumPhotoRemoval.swift',
                                  'Resources/ProjectAlbumPhotoRemoval.xcstrings',
                                  'Tests/AppUnitTests/ProjectAlbumPhotoRemovalPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_album_photo_removal.py',
                                  'Tests/CoreTests/ProjectAlbumPhotoRemovalTests.swift',
                                  'App/ProjectDraftStoryPreviewView.swift',
                                  'Core/ProjectDraftStoryPreview.swift',
                                  'Resources/ProjectDraftStoryPreview.xcstrings',
                                  'Tests/AppUnitTests/ProjectDraftStoryPreviewPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_draft_story_preview.py',
                                  'Tests/CoreTests/ProjectDraftStoryPreviewTests.swift',
                                  'App/ProjectTeamConfigurationEditor.swift',
                                  'Core/ProjectTeamConfiguration.swift',
                                  'Resources/ProjectTeamConfiguration.xcstrings',
                                  'Tests/AppUnitTests/ProjectTeamConfigurationPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_team_configuration.py',
                                  'Tests/CoreTests/ProjectTeamConfigurationTests.swift',
                                  'App/ProjectNodeImageAuthorView.swift',
                                  'App/ProjectNodeImageCompositionRoute.swift',
                                  'App/ProjectNodeImageCrop.swift',
                                  'App/ProjectNodeImagePresentation.swift',
                                  'Core/ProjectNodeImageFlow.swift',
                                  'Core/ProjectNodeImageJournal.swift',
                                  'Core/ProjectNodeImageTarget.swift',
                                  'Core/ProjectNodeImageUpload.swift',
                                  'Resources/ProjectNodeImageAuthor.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodeImageAuthorTests.swift',
                                  'Tests/CoreTests/ProjectNodeImageTests.swift',
                                  'Core/ProjectTopicBudgetCarryOver.swift',
                                  'Resources/MerchantProjectWorkspaceLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantProjectWorkspaceEntryTests.swift',
                                  'Tests/ContractChecks/test_merchant_project_workspace_entry.py',
                                  'Tests/ContractChecks/test_project_topic_budget_carryover.py',
                                  'Tests/CoreTests/MerchantProjectWorkspaceScopeTests.swift',
                                  'Tests/CoreTests/ProjectTopicBudgetCarryOverTests.swift',
                                  'App/MerchantReviewDraftReturn.swift',
                                  'App/ProjectCityStoryNodeRemovalController.swift',
                                  'Core/ProjectCityStoryNodeRemoval.swift',
                                  'Resources/MerchantReviewDraftReturnLocalizations.fragment.json',
                                  'Resources/ProjectCityStoryNodeRemoval.xcstrings',
                                  'Tests/AppUnitTests/MerchantReviewDraftReturnTests.swift',
                                  'Tests/AppUnitTests/ProjectCityStoryNodeRemovalPresentationTests.swift',
                                  'Tests/ContractChecks/test_merchant_review_draft_return.py',
                                  'Tests/ContractChecks/test_project_city_story_node_removal.py',
                                  'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift',
                                  'App/ProjectNodePlacePicker.swift',
                                  'App/ProjectPendingNodePlacePicker.swift',
                                  'Core/ProjectNodePlaceSelection.swift',
                                  'Resources/ProjectNodePlacePicker.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodePlacePickerTests.swift',
                                  'Tests/AppUnitTests/ProjectPendingNodePlacePickerTests.swift',
                                  'Tests/ContractChecks/test_project_node_place_picker.py',
                                  'Tests/ContractChecks/test_project_pending_node_place_picker.py',
                                  'Tests/CoreTests/ProjectNodePlaceSelectionTests.swift',
                                  'Tests/CoreTests/SearchMapCityNodeReadTests.swift',
                                  'Tests/ContractChecks/test_global_search_category_recovery.py',
                                  'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift',
                                  'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift',
                                  'docs/global-search-category-recovery.md',
                                  'tools/tests/test_gitleaks_configuration.py']}
PARENT_TO_R2_DELTA = [{'path': ['feature_batch_sources', 'App/ClubGovernanceViews.swift'],
  'before': 'c635bf66b98375c4d691fffd8051b90bf145fe5cf66681dc9d5d462cd99ce89e',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'App/GlobalSearchView.swift', 'after_sha256'],
  'before': '174d78310f6ed62053df8ce70aaecc10b27fdd65831e3a8cb72b0fe9c5c2db71',
  'action': 'set',
  'value': '5f679b73132b5bf9aed78a94964eab58b11c37335dba7d0acec940415462ac78'},
 {'path': ['feature_batch_sources', 'App/GlobalSearchView.swift', 'hunks'],
  'before': '37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570',
  'action': 'splice',
  'start': 8,
  'stop': 8,
  'value': [{'before': 'import SwiftUI\n'
                       '\n'
                       '@MainActor struct GlobalSearchView<Destination: View>: View {\n'
                       '    let reader: any SearchMapReading\n'
                       '    var historyNamespace: String? = nil\n'
                       '    var publicMerchant = PublicMerchantHomeContext()\n'
                       '    var onSignIn: (() -> Void)? = nil\n'
                       '    let destination: (SearchMapDestination) -> Destination\n'
                       '    @State private var filter = GlobalSearchQuery()\n'
                       '    @State private var categories: [DiscoveryCategory] = []\n'
                       '    @State private var categoryFailed = false\n'
                       '    @State private var retainedResults = GlobalSearchRetainedResults()\n'
                       '    @State private var isVisible = false\n'
                       '    @State private var issue: String?\n',
             'after': 'import SwiftUI\n'
                      '\n'
                      '@MainActor struct GlobalSearchView<Destination: View>: View {\n'
                      '    @Environment(\\.scenePhase) private var scenePhase\n'
                      '    let reader: any SearchMapReading\n'
                      '    var historyNamespace: String? = nil\n'
                      '    var publicMerchant = PublicMerchantHomeContext()\n'
                      '    var onSignIn: (() -> Void)? = nil\n'
                      '    let destination: (SearchMapDestination) -> Destination\n'
                      '    @State private var filter = GlobalSearchQuery()\n'
                      '    @State private var categoryRecovery = SearchMapCategoryRecovery()\n'
                      '    @State private var categoryPresentationID = UUID()\n'
                      '    @State private var filterPresentationID = UUID()\n'
                      '    @State private var filterSheetVisible = false\n'
                      '    @State private var retainedResults = GlobalSearchRetainedResults()\n'
                      '    @State private var isVisible = false\n'
                      '    @State private var issue: String?\n'},
            {'before': '    @State private var showsFilters = false\n'
                       '    @State private var history: [String] = []\n'
                       '    @State private var historyFailure = false\n'
                       '    @State private var categoryGate = SearchMapQueryGate()\n'
                       '    @State private var preparedOwner: ReadOwner?\n'
                       '    private let historyStore = SearchMapLocalHistory()\n'
                       '\n',
             'after': '    @State private var showsFilters = false\n'
                      '    @State private var history: [String] = []\n'
                      '    @State private var historyFailure = false\n'
                      '    @State private var preparedOwner: ReadOwner?\n'
                      '    private let historyStore = SearchMapLocalHistory()\n'
                      '\n'},
            {'before': '                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, '
                       'set: setKeyword)).textInputAutocapitalization(.never)\n'
                       '                        .submitLabel(.search).onSubmit { Task { await search() } }\n'
                       '                        .accessibilityIdentifier("searchMap.keyword")\n'
                       '                    Button { showsFilters = true } label: { Label("searchMap.filters", '
                       'systemImage: "line.3.horizontal.decrease") }\n'
                       '                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: '
                       '44).accessibilityIdentifier("searchMap.filters")\n'
                       '                }.padding(12).background(.secondary.opacity(0.08), in: '
                       'RoundedRectangle(cornerRadius: 16))\n'
                       '                Button("searchMap.search") { Task { await search() } }\n',
             'after': '                    TextField("searchMap.placeholder", text: Binding(get: { filter.keyword }, '
                      'set: setKeyword)).textInputAutocapitalization(.never)\n'
                      '                        .submitLabel(.search).onSubmit { Task { await search() } }\n'
                      '                        .accessibilityIdentifier("searchMap.keyword")\n'
                      '                    Button { openFilters() } label: { Label("searchMap.filters", systemImage: '
                      '"line.3.horizontal.decrease") }\n'
                      '                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: '
                      '44).accessibilityIdentifier("searchMap.filters")\n'
                      '                }.padding(12).background(.secondary.opacity(0.08), in: '
                      'RoundedRectangle(cornerRadius: 16))\n'
                      '                Button("searchMap.search") { Task { await search() } }\n'},
            {'before': '        }\n'
                       '        .appNavigationTitle("searchMap.title")\n'
                       '        .sheet(isPresented: $showsFilters) {\n'
                       '            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: '
                       'categoryFailed) { next in\n'
                       '                applyFilter(next)\n'
                       '            }\n'
                       '        }\n'
                       '        .task(id: readOwner) { await prepare() }\n'
                       '        .onAppear { isVisible = true }\n'
                       '        .onDisappear { isVisible = false; retainedResults.cancelPending(); '
                       'categoryGate.invalidate(); loading = false }\n'
                       '    }\n'
                       '    @ViewBuilder private var suggestions: some View {\n'
                       '        if !history.isEmpty {\n'
                       '            HStack {\n'
                       '                Text("searchMap.history").font(.headline)\n',
             'after': '        }\n'
                      '        .appNavigationTitle("searchMap.title")\n'
                      '        .sheet(isPresented: $showsFilters) {\n'
                      '            let presentationID = filterPresentationID\n'
                      '            let context = categoryRecovery.context(for: categoryOwner)\n'
                      '            let applyContext = categoryRecovery.presentationContext(for: categoryOwner)\n'
                      '            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: '
                      'categoryFailed,\n'
                      '                                 categoryLoading: categoryLoading, categoryLoaded: '
                      'categoryLoaded,\n'
                      '                                 retryCategories: context.map { captured in {\n'
                      '                                     guard showsFilters, filterSheetVisible, presentationID == '
                      'filterPresentationID else { return }\n'
                      '                                     _ = categoryRecovery.retry(in: captured)\n'
                      '                                 } }) { next in\n'
                      '                guard showsFilters, filterSheetVisible, presentationID == '
                      'filterPresentationID,\n'
                      '                      let applyContext, categoryRecovery.acceptsPresentation(applyContext) else '
                      '{ return }\n'
                      '                applyFilter(next)\n'
                      '            }\n'
                      '            .onAppear {\n'
                      '                guard showsFilters, presentationID == filterPresentationID, '
                      'categoryRecovery.owns(categoryOwner) else { return }\n'
                      '                filterSheetVisible = true; updateCategoryPresentation()\n'
                      '            }\n'
                      '            .onDisappear {\n'
                      '                guard presentationID == filterPresentationID, '
                      'categoryRecovery.owns(categoryOwner) else { return }\n'
                      '                filterSheetVisible = false; updateCategoryPresentation()\n'
                      '            }\n'
                      '        }\n'
                      '        .task(id: readOwner) { await prepare() }\n'
                      '        .onChange(of: categoryOwner) { _, _ in updateCategoryPresentation() }\n'
                      '        .onChange(of: scenePhase) { _, _ in updateCategoryPresentation() }\n'
                      '        .onChange(of: showsFilters) { _, visible in\n'
                      '            if !visible { filterSheetVisible = false }\n'
                      '            updateCategoryPresentation()\n'
                      '        }\n'
                      '        .onAppear { isVisible = true; categoryPresentationID = UUID(); '
                      'updateCategoryPresentation() }\n'
                      '        .onDisappear {\n'
                      '            isVisible = false; retainedResults.cancelPending(); loading = false\n'
                      '            categoryRecovery.update(reader: reader, presentationID: nil, active: false)\n'
                      '        }\n'
                      '    }\n'
                      '    private var categoryOwner: SearchMapCategoryRecovery.Owner { .init(reader: reader) }\n'
                      '    private var categories: [DiscoveryCategory] { categoryRecovery.owns(categoryOwner) ? '
                      'categoryRecovery.categories : [] }\n'
                      '    private var categoryFailed: Bool { categoryRecovery.owns(categoryOwner) && '
                      'categoryRecovery.phase == .failed }\n'
                      '    private var categoryLoading: Bool { categoryRecovery.owns(categoryOwner) && '
                      'categoryRecovery.phase == .loading }\n'
                      '    private var categoryLoaded: Bool { categoryRecovery.owns(categoryOwner) && '
                      'categoryRecovery.phase == .loaded }\n'
                      '    private func openFilters() {\n'
                      '        filterPresentationID = UUID(); filterSheetVisible = false; showsFilters = true\n'
                      '        updateCategoryPresentation()\n'
                      '    }\n'
                      '    private func updateCategoryPresentation() {\n'
                      '        // The page and sheet share the directory, never a draft or search request.\n'
                      '        // Switching surfaces retires callbacks; a settled directory survives reopening.\n'
                      '        let presentationID = showsFilters ? (filterSheetVisible ? filterPresentationID : nil) : '
                      'categoryPresentationID\n'
                      '        categoryRecovery.update(reader: reader, presentationID: presentationID,\n'
                      '                                active: isVisible && scenePhase == .active)\n'
                      '        if let context = categoryRecovery.context(for: categoryOwner) {\n'
                      '            categoryRecovery.loadIfNeeded(in: context)\n'
                      '        }\n'
                      '    }\n'
                      '    @ViewBuilder private var suggestions: some View {\n'
                      '        let context = categoryRecovery.context(for: categoryOwner)\n'
                      '        if !history.isEmpty {\n'
                      '            HStack {\n'
                      '                Text("searchMap.history").font(.headline)\n'},
            {'before': '            }\n'
                       '        }\n'
                       '        Text("searchMap.categories").font(.headline)\n'
                       '        if categoryFailed { SearchMapIssue(key: "searchMap.categoryFailed") { Task { await '
                       'prepare(force: true) } } }\n'
                       '        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n'
                       '            ForEach(categories) { category in\n'
                       '                Button {\n'
                       '                    var next = filter; next.categoryID = category.id; applyFilter(next)\n'
                       '                } label: {\n'
                       '                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n',
             'after': '            }\n'
                      '        }\n'
                      '        Text("searchMap.categories").font(.headline)\n'
                      '        if categoryLoading {\n'
                      '            '
                      'ProgressView("searchMap.loading").accessibilityIdentifier("globalSearch.category.loading")\n'
                      '        } else if categoryFailed {\n'
                      '            SearchMapIssue(key: "searchMap.categoryFailed") {\n'
                      '                guard !showsFilters, let context else { return }\n'
                      '                _ = categoryRecovery.retry(in: context)\n'
                      '            }\n'
                      '        }\n'
                      '        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {\n'
                      '            ForEach(categories) { category in\n'
                      '                Button {\n'
                      '                    guard !showsFilters, let context, categoryRecovery.accepts(context) else { '
                      'return }\n'
                      '                    var next = filter; next.categoryID = category.id; applyFilter(next)\n'
                      '                } label: {\n'
                      '                    Text(verbatim: category.name).frame(maxWidth: .infinity, minHeight: 44)\n'},
            {'before': '        invalidate(); filter.keyword = value\n'
                       '    }\n'
                       '    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; '
                       'selectedKind = nil }\n'
                       '    private func prepare(force: Bool = false) async {\n'
                       '        if preparedOwner != readOwner {\n'
                       '            preparedOwner = readOwner; invalidate(); categories = []; categoryFailed = false\n'
                       '            history = historyStore.read(namespace: historyNamespace); historyFailure = '
                       'historyStore.failed\n'
                       '        }\n'
                       '        guard reader.isConfigured, force || categories.isEmpty else { return }\n'
                       '        let ticket = categoryGate.begin(scope: reader.scope)\n'
                       '        do {\n'
                       '            let value = try await reader.categories()\n'
                       '            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; '
                       'categories = value; categoryFailed = false\n'
                       '        } catch {\n'
                       '            guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; '
                       'categoryFailed = true\n'
                       '        }\n'
                       '    }\n'
                       '    private func search() async {\n'
                       '        let query = filter\n',
             'after': '        invalidate(); filter.keyword = value\n'
                      '    }\n'
                      '    private func invalidate() { retainedResults.invalidate(); issue = nil; loading = false; '
                      'selectedKind = nil }\n'
                      '    private func prepare() async {\n'
                      '        guard !Task.isCancelled else { return }\n'
                      '        if preparedOwner != readOwner {\n'
                      '            preparedOwner = readOwner; invalidate()\n'
                      '            history = historyStore.read(namespace: historyNamespace); historyFailure = '
                      'historyStore.failed\n'
                      '        }\n'
                      '        updateCategoryPresentation()\n'
                      '    }\n'
                      '    private func search() async {\n'
                      '        let query = filter\n'}]},
 {'path': ['feature_batch_sources', 'App/MerchantBusinessEditor.swift', 'after_sha256'],
  'before': '67b852532b465c62cfae6f668ef0d6baf751dc2d6bb7701625f9655b11ec26c0',
  'action': 'set',
  'value': '37e4fb670565770a72f1c1ad0e1c5b2ac4affc35669514597c80790d4e8f394d'},
 {'path': ['feature_batch_sources', 'App/MerchantBusinessEditor.swift', 'hunks'],
  'before': '9205dec16d8c192e382a466ebf8f1dde7c930e1f227da4cf84ae866c12add914',
  'action': 'splice',
  'start': 6,
  'stop': 7,
  'value': []},
 {'path': ['feature_batch_sources', 'App/MerchantOperationsEditor.swift', 'after_sha256'],
  'before': '6326778c3e36fb1282a9d0676c5d83d9612953fb45ca4a73219118c16b23c98e',
  'action': 'set',
  'value': '3e1a134db3355e63c068fcb4ff5dbb5abc7d7ac00488c6548d9a054339e80e1f'},
 {'path': ['feature_batch_sources', 'App/MerchantOperationsEditor.swift', 'hunks'],
  'before': 'c750691c49a6fe75117fca99b118bdc27acbb3f42ed6766361646c3a4fb46478',
  'action': 'splice',
  'start': 4,
  'stop': 5,
  'value': []},
 {'path': ['feature_batch_sources', 'App/ProjectNodeImageCrop.swift'],
  'before': '1e3c444f460d833e3724a8f1e0bd0022043650711fd2374cb44778ff97085fcd',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'App/RoamExperienceComponents.swift'],
  'before': None,
  'action': 'set',
  'value': {'before_sha256': '5d07efdb738c201f6f9b6502b1211330db63d6873ed4be5d33e1eb054115b453',
            'after_sha256': '02188caf2ccd48dae34f6775828d2e722ce4f8239f9925af8d972d9148e772fb',
            'hunks': [{'before': '}\n'
                                 'struct RoamRouteSketchView: View {\n'
                                 '    let record: RoamHistoryRecord\n'
                                 '    var body: some View {\n'
                                 '        let sketch = RoamRouteSketch(track: record.track, places: '
                                 'record.pois.map(\\.point))\n'
                                 '        ZStack {\n',
                       'after': '}\n'
                                'struct RoamRouteSketchView: View {\n'
                                '    let record: RoamHistoryRecord\n'
                                '    var visibleSegments: Int? = nil\n'
                                '    var body: some View {\n'
                                '        let sketch = RoamRouteSketch(track: record.track, places: '
                                'record.pois.map(\\.point))\n'
                                '        ZStack {\n'},
                      {'before': '            } else {\n'
                                 '                Canvas { context, size in\n'
                                 '                    var path = Path()\n'
                                 '                    for (index, point) in sketch.track.enumerated() {\n'
                                 '                        let position = CGPoint(x: point.x * size.width, y: point.y * '
                                 'size.height)\n'
                                 '                        if index == 0 { path.move(to: position) } else { '
                                 'path.addLine(to: position) }\n'
                                 '                    }\n',
                       'after': '            } else {\n'
                                '                Canvas { context, size in\n'
                                '                    var path = Path()\n'
                                '                    let segmentCount = max(0, sketch.track.count - 1)\n'
                                '                    let pointCount = visibleSegments.map { min(segmentCount, max(0, '
                                '$0)) + 1 } ?? sketch.track.count\n'
                                '                    for (index, point) in '
                                'sketch.track.prefix(pointCount).enumerated() {\n'
                                '                        let position = CGPoint(x: point.x * size.width, y: point.y * '
                                'size.height)\n'
                                '                        if index == 0 { path.move(to: position) } else { '
                                'path.addLine(to: position) }\n'
                                '                    }\n'},
                      {'before': '        }.font(.subheadline).monospacedDigit()\n    }\n}\n',
                       'after': '        }.font(.subheadline).monospacedDigit()\n'
                                '    }\n'
                                '}\n'
                                '\n'
                                '/// Replays only the stored sketch. This view has no location, network or write '
                                'capability.\n'
                                '@MainActor struct RoamSavedRouteReplayView: View {\n'
                                '    let reader: any RoamExperienceReading\n'
                                '    let record: RoamHistoryRecord\n'
                                '    @Environment(\\.scenePhase) private var scenePhase\n'
                                '    @Environment(\\.accessibilityReduceMotion) private var reduceMotion\n'
                                '    @State private var replay = RoamRouteReplayState()\n'
                                '    @State private var visible = false\n'
                                '    @State private var request: Request?\n'
                                '    private struct Request {\n'
                                '        let id = UUID()\n'
                                '        let context: RoamRouteReplayState.Context\n'
                                '        let counts: [Int]\n'
                                '    }\n'
                                '    private var owner: RoamRouteReplayState.Owner { .init(reader: reader, record: '
                                'record) }\n'
                                '    var body: some View {\n'
                                '        let current = owner\n'
                                '        let context = replay.context(for: current)\n'
                                '        VStack(alignment: .leading, spacing: 12) {\n'
                                '            // Always normalize the complete record; revealing a prefix never '
                                'rescales it.\n'
                                '            RoamRouteSketchView(record: record, visibleSegments: context == nil ? nil '
                                ': replay.visibleSegments)\n'
                                '            if let context {\n'
                                '                if replay.phase == .playing {\n'
                                '                    Button("roamRouteReplay.skip", systemImage: "forward.end") {\n'
                                '                        synchronize()\n'
                                '                        guard replay.accepts(context, current: owner) else { return '
                                '}\n'
                                '                        replay.skip(in: context, current: owner); request = nil\n'
                                '                    }.frame(minHeight: '
                                '44).accessibilityIdentifier("roamRouteReplay.skip")\n'
                                '                } else {\n'
                                '                    Button(LocalizedStringKey(replay.phase == .completed ? '
                                '"roamRouteReplay.again" : "roamRouteReplay.start"), systemImage: "play") {\n'
                                '                        synchronize()\n'
                                '                        guard replay.accepts(context, current: owner) else { return '
                                '}\n'
                                '                        if let ticket = replay.start(in: context, current: owner) {\n'
                                '                            request = Request(context: ticket, counts: '
                                'replay.plan.counts)\n'
                                '                        }\n'
                                '                    }.frame(minHeight: '
                                '44).accessibilityIdentifier("roamRouteReplay.start")\n'
                                '                }\n'
                                '                ProgressView(value: replay.progress, total: 1)\n'
                                '                    .accessibilityLabel(Text("roamRouteReplay.progress"))\n'
                                '                    .accessibilityValue(Text(replay.progress, format: '
                                '.percent.precision(.fractionLength(0))))\n'
                                '                    .accessibilityIdentifier("roamRouteReplay.progress")\n'
                                '                Text(LocalizedStringKey(replay.phase == .playing ? '
                                '"roamRouteReplay.playing" : (replay.phase == .completed ? "roamRouteReplay.completed" '
                                ': "roamRouteReplay.ready")))\n'
                                '                    .font(.caption).foregroundStyle(.secondary)\n'
                                '            }\n'
                                '        }\n'
                                '        .onAppear { visible = true; synchronize() }\n'
                                '        .onDisappear { visible = false; synchronize() }\n'
                                '        .onChange(of: owner) { _, _ in synchronize() }\n'
                                '        .onChange(of: scenePhase) { _, _ in synchronize() }\n'
                                '        .onChange(of: reduceMotion) { _, _ in synchronize() }\n'
                                '        .task(id: request?.id) {\n'
                                '            guard let captured = request else { return }\n'
                                '            for (index, count) in captured.counts.enumerated() {\n'
                                '                if index > 0 {\n'
                                '                    do { try await Task.sleep(nanoseconds: '
                                'RoamRouteReplayPlan.intervalNanoseconds) }\n'
                                '                    catch { return }\n'
                                '                }\n'
                                '                if reduceMotion { synchronize(); return }\n'
                                '                guard !Task.isCancelled, visible, scenePhase == .active,\n'
                                '                      replay.accepts(captured.context, current: owner) else { return '
                                '}\n'
                                '                replay.advance(to: count, in: captured.context, current: owner)\n'
                                '            }\n'
                                '            // No old-task cleanup can clear a later request.\n'
                                '        }\n'
                                '        .accessibilityElement(children: .contain)\n'
                                '        .accessibilityIdentifier("roamRouteReplay.saved")\n'
                                '    }\n'
                                '    private func synchronize() {\n'
                                '        replay.update(owner: owner, active: visible && scenePhase == .active, '
                                'reduceMotion: reduceMotion)\n'
                                '        if let captured = request, !replay.accepts(captured.context, current: owner) '
                                '{ request = nil }\n'
                                '    }\n'
                                '}\n'}]}},
 {'path': ['feature_batch_sources', 'App/RoamHistoryViews.swift', 'after_sha256'],
  'before': '0053e1ca7f234bd69c4c98c4ee765b9d5d9e709e30d39cb393845a09159213e5',
  'action': 'set',
  'value': '2a4d67bbb003df0646599c911ae8c2ac6e20b99e2af7ae81f89be384af608172'},
 {'path': ['feature_batch_sources', 'App/RoamHistoryViews.swift', 'hunks'],
  'before': '37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570',
  'action': 'splice',
  'start': 3,
  'stop': 3,
  'value': [{'before': '    @State private var showShare = false\n'
                       '    @State private var loaded = false\n'
                       '    @State private var error: Error?\n'
                       '    var body: some View {\n'
                       '        ScrollView {\n'
                       '            VStack(alignment: .leading, spacing: 20) {\n'
                       '                RoamExperienceNotice(offline: reader.isOfflineExample)\n'
                       '                if let error { RoamExperienceIssue(error: error, retry: load) }\n'
                       '                else if let record {\n'
                       '                    RoamExperienceCard {\n'
                       '                        VStack(alignment: .leading, spacing: 18) {\n'
                       '                            Label("roam.experience.savedRecord", systemImage: '
                       '"book.closed").font(.caption).foregroundStyle(.secondary)\n'
                       '                            if let zone = record.meaningfulZone { Text(verbatim: '
                       'zone).font(.title2).bold() }\n'
                       '                            else { Text("roam.experience.cityWalk").font(.title2).bold() }\n'
                       '                            if let date = record.recordedAt { Text(date, style: .date) }\n'
                       '                            RoamRouteSketchView(record: record)\n'
                       '                            RoamRecordedStats(record: record)\n'
                       '                        }\n'
                       '                    }\n',
             'after': '    @State private var showShare = false\n'
                      '    @State private var loaded = false\n'
                      '    @State private var error: Error?\n'
                      '    @State private var loadedOwner: ReadKey?\n'
                      '    private struct ReadKey: Hashable {\n'
                      '        let owner: RoamHistoryLiveOwner\n'
                      '        let timestamp: Int64\n'
                      '    }\n'
                      '    private var readKey: ReadKey { .init(owner: .init(reader: reader), timestamp: timestamp) }\n'
                      '    private var currentRecord: RoamHistoryRecord? { loadedOwner == readKey ? record : nil }\n'
                      '    private var currentError: Error? { loadedOwner == readKey ? error : nil }\n'
                      '    private var currentLoaded: Bool { loadedOwner == readKey && loaded }\n'
                      '    var body: some View {\n'
                      '        ScrollView {\n'
                      '            VStack(alignment: .leading, spacing: 20) {\n'
                      '                RoamExperienceNotice(offline: reader.isOfflineExample)\n'
                      '                if let error = currentError { RoamExperienceIssue(error: error, retry: load) }\n'
                      '                else if let record = currentRecord {\n'
                      '                    RoamExperienceCard {\n'
                      '                        VStack(alignment: .leading, spacing: 18) {\n'
                      '                            Label("roam.experience.savedRecord", systemImage: '
                      '"book.closed").font(.caption).foregroundStyle(.secondary)\n'
                      '                            if let zone = record.meaningfulZone { Text(verbatim: '
                      'zone).font(.title2).bold() }\n'
                      '                            else { Text("roam.experience.cityWalk").font(.title2).bold() }\n'
                      '                            if let date = record.recordedAt { Text(date, style: .date) }\n'
                      '                            RoamSavedRouteReplayView(reader: reader, record: record)\n'
                      '                            RoamRecordedStats(record: record)\n'
                      '                        }\n'
                      '                    }\n'},
            {'before': '                    Button("roam.share.title", systemImage: "square.and.arrow.up") { showShare '
                       '= true }\n'
                       '                        .accessibilityIdentifier("roam.share.open")\n'
                       '                    '
                       'Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)\n'
                       '                } else if loaded {\n'
                       '                    ContentUnavailableView("roam.experience.recordMissing", systemImage: '
                       '"questionmark.folder", description: Text("roam.experience.recordMissingHint"))\n'
                       '                        .accessibilityIdentifier("roam.experience.history.missing")\n'
                       '                } else { ProgressView("roam.loading") }\n'
                       '            }.padding()\n'
                       '        }.navigationTitle("roam.experience.session")\n'
                       '            .task(id: reader.identity) { showShare = false; load() }\n'
                       '            .sheet(isPresented: $showShare) { if let record { NavigationStack { '
                       'RoamHistoryShareView(record: record) } } }\n'
                       '            .accessibilityIdentifier("roam.experience.session")\n'
                       '    }\n'
                       '    private func load() {\n'
                       '        record = nil; error = nil; loaded = false\n'
                       '        do { record = try reader.history().first { $0.ts == timestamp }; loaded = true } catch '
                       '{ self.error = error }\n'
                       '    }\n'
                       '}\n',
             'after': '                    Button("roam.share.title", systemImage: "square.and.arrow.up") { showShare '
                      '= true }\n'
                      '                        .accessibilityIdentifier("roam.share.open")\n'
                      '                    '
                      'Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)\n'
                      '                } else if currentLoaded {\n'
                      '                    ContentUnavailableView("roam.experience.recordMissing", systemImage: '
                      '"questionmark.folder", description: Text("roam.experience.recordMissingHint"))\n'
                      '                        .accessibilityIdentifier("roam.experience.history.missing")\n'
                      '                } else { ProgressView("roam.loading") }\n'
                      '            }.padding()\n'
                      '        }.navigationTitle("roam.experience.session")\n'
                      '            .task(id: readKey) { showShare = false; load() }\n'
                      '            .onChange(of: readKey) { _, _ in showShare = false }\n'
                      '            .sheet(isPresented: $showShare) { if let record = currentRecord { NavigationStack { '
                      'RoamHistoryShareView(record: record) } } }\n'
                      '            .accessibilityIdentifier("roam.experience.session")\n'
                      '    }\n'
                      '    private func load() {\n'
                      '        record = nil; error = nil; loaded = false; loadedOwner = nil\n'
                      '        let captured = readKey\n'
                      '        do {\n'
                      '            let value = try reader.history().first { $0.ts == timestamp }\n'
                      '            guard captured == readKey else { return }\n'
                      '            record = value; loaded = true; loadedOwner = captured\n'
                      '        } catch {\n'
                      '            guard captured == readKey else { return }\n'
                      '            self.error = error; loadedOwner = captured\n'
                      '        }\n'
                      '    }\n'
                      '}\n'}]},
 {'path': ['feature_batch_sources', 'App/SearchMapFilterSheet.swift', 'after_sha256'],
  'before': 'c5ca57943a46cbdc2bc77a0f6a82ba703e4e2cddb794d3048dd473abd87693df',
  'action': 'set',
  'value': 'd805599b752fcd104e40b382fb30d5bc96b9f8f27622766bfaefeed402c07b54'},
 {'path': ['feature_batch_sources', 'App/SearchMapFilterSheet.swift', 'hunks'],
  'before': '37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570',
  'action': 'splice',
  'start': 1,
  'stop': 1,
  'value': [{'before': '    let applyCityOptions: ((String, String, Int) -> Void)?\n'
                       '    let categories: [DiscoveryCategory]\n'
                       '    let categoryFailed: Bool\n'
                       '    let apply: (GlobalSearchQuery) -> Void\n'
                       '    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool,\n'
                       '         tag: String = "", cityRole: String = "", sortType: Int = 1,\n'
                       '         applyCityOptions: ((String, String, Int) -> Void)? = nil, apply: @escaping '
                       '(GlobalSearchQuery) -> Void) {\n'
                       '        _draft = State(initialValue: filter)\n',
             'after': '    let applyCityOptions: ((String, String, Int) -> Void)?\n'
                      '    let categories: [DiscoveryCategory]\n'
                      '    let categoryFailed: Bool\n'
                      '    let categoryLoading: Bool\n'
                      '    let categoryLoaded: Bool\n'
                      '    let retryCategories: (() -> Void)?\n'
                      '    let apply: (GlobalSearchQuery) -> Void\n'
                      '    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool,\n'
                      '         categoryLoading: Bool = false, categoryLoaded: Bool = false, retryCategories: (() -> '
                      'Void)? = nil,\n'
                      '         tag: String = "", cityRole: String = "", sortType: Int = 1,\n'
                      '         applyCityOptions: ((String, String, Int) -> Void)? = nil, apply: @escaping '
                      '(GlobalSearchQuery) -> Void) {\n'
                      '        _draft = State(initialValue: filter)\n'},
            {'before': '        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")\n'
                       '        _dateDraft = State(initialValue: SearchMapDateFilterDraft(filter: filter))\n'
                       '        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = '
                       'apply\n'
                       '    }\n'
                       '    var body: some View {\n'
                       '        NavigationStack {\n',
             'after': '        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")\n'
                      '        _dateDraft = State(initialValue: SearchMapDateFilterDraft(filter: filter))\n'
                      '        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = apply\n'
                      '        self.categoryLoading = categoryLoading; self.categoryLoaded = categoryLoaded; '
                      'self.retryCategories = retryCategories\n'
                      '    }\n'
                      '    var body: some View {\n'
                      '        NavigationStack {\n'},
            {'before': '                    Picker("searchMap.category", selection: $draft.categoryID) {\n'
                       '                        Text("searchMap.all").tag(Int?.none)\n'
                       '                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }\n'
                       '                    }\n'
                       '                    .accessibilityIdentifier("searchMap.filter.category")\n'
                       '                    if categoryFailed { Text("searchMap.categoryFailed").font(.caption) }\n'
                       '                }\n'
                       '                Section("searchMap.dates") {\n'
                       '                    Button("mapDatePreset.today") { selectDatePreset(.today) }\n',
             'after': '                    Picker("searchMap.category", selection: $draft.categoryID) {\n'
                      '                        Text("searchMap.all").tag(Int?.none)\n'
                      '                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }\n'
                      '                        // Keep an explicit tag for a selection missing from the new '
                      'directory.\n'
                      "                        // Only the user's selection/reset/Apply may change this manual draft.\n"
                      '                        if let selectedID = draft.categoryID, !categories.contains(where: { '
                      '$0.id == selectedID }) {\n'
                      '                            (Text("searchMap.category") + Text(verbatim: " #\\(selectedID)"))\n'
                      '                                .tag(Optional(selectedID))\n'
                      '                        }\n'
                      '                    }\n'
                      '                    .accessibilityIdentifier("searchMap.filter.category")\n'
                      '                    if categoryLoading {\n'
                      '                        '
                      'ProgressView("searchMap.loading").accessibilityIdentifier("searchMap.category.loading")\n'
                      '                    } else if categoryFailed {\n'
                      '                        Text("searchMap.categoryFailed").font(.caption)\n'
                      '                            .accessibilityIdentifier("searchMap.category.failed")\n'
                      '                        if let retryCategories {\n'
                      '                            Button("searchMap.retry", action: retryCategories).frame(minHeight: '
                      '44)\n'
                      '                                .accessibilityIdentifier("searchMap.category.retry")\n'
                      '                        }\n'
                      '                    } else if categoryLoaded && categories.isEmpty {\n'
                      '                        Text("searchMap.empty").font(.caption)\n'
                      '                            .accessibilityIdentifier("searchMap.category.empty")\n'
                      '                    }\n'
                      '                }\n'
                      '                Section("searchMap.dates") {\n'
                      '                    Button("mapDatePreset.today") { selectDatePreset(.today) }\n'}]},
 {'path': ['feature_batch_sources', 'Core/ClubCustomerHistoryTopicRoute.swift'],
  'before': 'a6e773edc9ae5920a4e1fb22a573ea82dfc2f0991df4761c66e89a75081782ec',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'Core/ClubGovernanceContracts.swift'],
  'before': '76632c1320fcc6ec6eb65b2697df3bf44150c65209c213b0977f2fc2d1f541d3',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'Core/ProfileEditCoordinator.swift', 'after_sha256'],
  'before': '2fcb7ae759943efbf9853cf9f1e6c720d25c491a2014e98679d72422ab15088c',
  'action': 'set',
  'value': '2abfe23ec770e6c0b6781c42b3a5b502a4855a8394ba46a4db5857eed563bb7b'},
 {'path': ['feature_batch_sources', 'Core/ProfileEditCoordinator.swift', 'hunks'],
  'before': 'e8e2474f08704fb066f3d358fe583db8a00857bc8af3baf2e4a65d980d9f67ac',
  'action': 'splice',
  'start': 5,
  'stop': 9,
  'value': []},
 {'path': ['feature_batch_sources', 'Core/RoamExperienceMath.swift'],
  'before': None,
  'action': 'set',
  'value': {'before_sha256': '11fd35c304e0376c077924e870418b77db9f7cca3c738781f09e3d4a41f49844',
            'after_sha256': '65f5ef1e0f0161c5875f6e962790e2690ef9de210da7cb75b7a72c3cda3b8a6b',
            'hunks': [{'before': '        self.track = Array(normalized.prefix(track.count)); self.places = '
                                 'Array(normalized.dropFirst(track.count))\n'
                                 '    }\n'
                                 '}\n',
                       'after': '        self.track = Array(normalized.prefix(track.count)); self.places = '
                                'Array(normalized.dropFirst(track.count))\n'
                                '    }\n'
                                '}\n'
                                '\n'
                                '/// A bounded local display schedule; it never reads, changes or saves a route.\n'
                                'public struct RoamRouteReplayPlan: Equatable {\n'
                                '    public static let intervalNanoseconds: UInt64 = 120_000_000\n'
                                '    public static let maximumFrames = 24\n'
                                '    public let counts: [Int]\n'
                                '    public init(segmentCount: Int) {\n'
                                '        let total = max(0, segmentCount)\n'
                                '        guard total > 0 else { counts = []; return }\n'
                                '        let frames = min(total, Self.maximumFrames)\n'
                                '        let step = total / frames + (total % frames == 0 ? 0 : 1)\n'
                                '        var result: [Int] = [], count = 0\n'
                                '        while count < total {\n'
                                '            count = total - count <= step ? total : count + step\n'
                                '            result.append(count)\n'
                                '        }\n'
                                '        counts = result\n'
                                '    }\n'
                                '}\n'
                                '\n'
                                '/// Value-only replay authority. Timers live in the SwiftUI detail presentation.\n'
                                '/// A context belongs to an exact reader/scope, complete record value and visible '
                                'lifetime.\n'
                                'public struct RoamRouteReplayState {\n'
                                '    public struct Owner: Equatable {\n'
                                '        public let readerID: ObjectIdentifier\n'
                                '        public let identity: RoamExperienceIdentity?\n'
                                '        public let storageKey: String?\n'
                                '        public let configured: Bool\n'
                                '        public let record: RoamHistoryRecord\n'
                                '        @MainActor public init(reader: any RoamExperienceReading, record: '
                                'RoamHistoryRecord) {\n'
                                '            readerID = ObjectIdentifier(reader); identity = reader.identity\n'
                                '            storageKey = identity?.scope.storageKey\n'
                                '            configured = reader.isConfigured; self.record = record\n'
                                '        }\n'
                                '    }\n'
                                '    public struct Context: Equatable {\n'
                                '        fileprivate let owner: Owner\n'
                                '        fileprivate let generation: UUID\n'
                                '    }\n'
                                '    public enum Phase: Equatable { case ready, playing, completed }\n'
                                '    public private(set) var phase: Phase = .ready\n'
                                '    public private(set) var totalSegments = 0\n'
                                '    /// nil means the unchanged full static sketch, including non-replay callers.\n'
                                '    public private(set) var visibleSegments: Int?\n'
                                '    private var owner: Owner?\n'
                                '    private var active = false\n'
                                '    private var reduceMotion = false\n'
                                '    private var generation = UUID()\n'
                                '    public init() {}\n'
                                '    public var progress: Double {\n'
                                '        guard totalSegments > 0 else { return 0 }\n'
                                '        return Double(visibleSegments ?? totalSegments) / Double(totalSegments)\n'
                                '    }\n'
                                '    public var plan: RoamRouteReplayPlan { .init(segmentCount: totalSegments) }\n'
                                '    public mutating func update(owner: Owner, active: Bool, reduceMotion: Bool) {\n'
                                '        if self.owner != owner || self.active != active {\n'
                                '            generation = UUID(); phase = .ready; visibleSegments = nil\n'
                                '            let points = RoamRouteSketch(track: owner.record.track, places: '
                                'owner.record.pois.map(\\.point)).track\n'
                                '            let hasLine = zip(points, points.dropFirst()).contains { pair in pair.0 '
                                '!= pair.1 }\n'
                                '            totalSegments = hasLine ? max(0, points.count - 1) : 0\n'
                                '        }\n'
                                '        self.owner = owner; self.active = active; self.reduceMotion = reduceMotion\n'
                                '        if reduceMotion && phase == .playing { complete() }\n'
                                '    }\n'
                                '    public func context(for current: Owner) -> Context? {\n'
                                '        guard active, owner == current, totalSegments > 0 else { return nil }\n'
                                '        return Context(owner: current, generation: generation)\n'
                                '    }\n'
                                '    public func accepts(_ context: Context, current: Owner) -> Bool {\n'
                                '        self.context(for: current) == context\n'
                                '    }\n'
                                '    @discardableResult public mutating func start(in context: Context, current: '
                                'Owner) -> Context? {\n'
                                '        guard accepts(context, current: current), phase != .playing else { return nil '
                                '}\n'
                                '        generation = UUID()\n'
                                '        if reduceMotion { phase = .completed; visibleSegments = nil; return nil }\n'
                                '        phase = .playing; visibleSegments = 0\n'
                                '        return self.context(for: current)\n'
                                '    }\n'
                                '    public mutating func advance(to count: Int, in context: Context, current: Owner) '
                                '{\n'
                                '        guard accepts(context, current: current), phase == .playing else { return }\n'
                                '        let bounded = min(totalSegments, max(0, count))\n'
                                '        guard bounded >= (visibleSegments ?? 0) else { return }\n'
                                '        visibleSegments = bounded\n'
                                '        if bounded == totalSegments { complete() }\n'
                                '    }\n'
                                '    public mutating func skip(in context: Context, current: Owner) {\n'
                                '        guard accepts(context, current: current), phase == .playing else { return }\n'
                                '        complete()\n'
                                '    }\n'
                                '    private mutating func complete() {\n'
                                '        generation = UUID(); phase = .completed; visibleSegments = nil\n'
                                '    }\n'
                                '}\n'}]}},
 {'path': ['feature_batch_sources', 'Core/SearchMapReading.swift', 'after_sha256'],
  'before': 'bd6b7eaf583db062f295daa7676c38e0e041f3e8950c95b2a0b2743991a61d1e',
  'action': 'set',
  'value': '34c67b5893b5ebba2eec8fdfc468a9b1662f4b94f86936d63d755385954d9aad'},
 {'path': ['feature_batch_sources', 'Core/SearchMapReading.swift', 'hunks'],
  'before': '37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570',
  'action': 'splice',
  'start': 3,
  'stop': 3,
  'value': [{'before': '    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { generation == '
                       'ticket.generation && ticket.scope == scope && !Task.isCancelled }\n'
                       '    public func invalidate() { generation &+= 1 }\n'
                       '}\n',
             'after': '    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { generation == '
                      'ticket.generation && ticket.scope == scope && !Task.isCancelled }\n'
                      '    public func invalidate() { generation &+= 1 }\n'
                      '}\n'
                      '\n'
                      'import Observation\n'
                      '\n'
                      '/// Read-only category directory for one visible filter presentation. The directory\n'
                      '/// never owns a query/draft, applies filters, or grants any reader capability.\n'
                      '@Observable @MainActor public final class SearchMapCategoryRecovery {\n'
                      '    public enum Phase: Equatable { case idle, loading, loaded, failed }\n'
                      '    public struct Owner: Hashable {\n'
                      '        public let readerID: ObjectIdentifier\n'
                      '        public let scope: UUID\n'
                      '        public let configured: Bool\n'
                      '        public let authenticated: Bool\n'
                      '        public let manualAreaRevision: UInt64\n'
                      '        @MainActor public init(reader: any SearchMapReading) {\n'
                      '            readerID = ObjectIdentifier(reader); scope = reader.scope\n'
                      '            configured = reader.isConfigured; authenticated = reader.isAuthenticated\n'
                      '            manualAreaRevision = reader.manualAreaRevision\n'
                      '        }\n'
                      '    }\n'
                      '    public struct Context: Equatable {\n'
                      '        fileprivate let owner: Owner\n'
                      '        fileprivate let presentationID: UUID\n'
                      '        fileprivate let generation: UUID\n'
                      '    }\n'
                      '    public private(set) var categories: [DiscoveryCategory] = []\n'
                      '    public private(set) var phase: Phase = .idle\n'
                      '    private var settledPhase: Phase = .idle\n'
                      '    private var owner: Owner?\n'
                      '    private var presentationID: UUID?\n'
                      '    private var active = false\n'
                      '    private var generation = UUID()\n'
                      '    private var pending: UUID?\n'
                      '    @ObservationIgnored private weak var reader: (any SearchMapReading)?\n'
                      '    @ObservationIgnored private var task: Task<Void, Never>?\n'
                      '    public init() {}\n'
                      '    deinit { task?.cancel() }\n'
                      '\n'
                      '    /// Every observed lifetime transition retires old callbacks, including A/B/A.\n'
                      '    /// Reopening keeps a settled same-owner directory; interrupted reads may resume.\n'
                      '    public func update(reader: any SearchMapReading, presentationID: UUID?, active: Bool) {\n'
                      '        let next = Owner(reader: reader)\n'
                      '        if owner != next || self.presentationID != presentationID || self.active != active {\n'
                      '            generation = UUID(); task?.cancel(); task = nil; pending = nil\n'
                      '            if owner != next { categories = []; settledPhase = .idle }\n'
                      '            phase = settledPhase\n'
                      '        }\n'
                      '        self.reader = reader; owner = next\n'
                      '        self.presentationID = presentationID; self.active = active\n'
                      '    }\n'
                      '    public func owns(_ current: Owner) -> Bool {\n'
                      '        guard let reader else { return false }\n'
                      '        return owner == current && Owner(reader: reader) == current\n'
                      '    }\n'
                      '    /// Local filter edits require a current presentation, not a network capability.\n'
                      '    public func presentationContext(for current: Owner) -> Context? {\n'
                      '        guard active, owns(current), let presentationID else { return nil }\n'
                      '        return Context(owner: current, presentationID: presentationID, generation: generation)\n'
                      '    }\n'
                      '    public func acceptsPresentation(_ context: Context) -> Bool {\n'
                      '        self.presentationContext(for: context.owner) == context\n'
                      '    }\n'
                      '    /// A local Apply context must never authorize a category read while unconfigured.\n'
                      '    public func context(for current: Owner) -> Context? {\n'
                      '        guard current.configured else { return nil }\n'
                      '        return presentationContext(for: current)\n'
                      '    }\n'
                      '    public func accepts(_ context: Context) -> Bool {\n'
                      '        self.context(for: context.owner) == context\n'
                      '    }\n'
                      '    @discardableResult public func loadIfNeeded(in context: Context) -> Task<Void, Never>? {\n'
                      '        guard phase == .idle else { return nil }\n'
                      '        return begin(in: context)\n'
                      '    }\n'
                      '    @discardableResult public func retry(in context: Context) -> Task<Void, Never>? {\n'
                      '        guard phase == .failed else { return nil }\n'
                      '        return begin(in: context)\n'
                      '    }\n'
                      '    private func begin(in context: Context) -> Task<Void, Never>? {\n'
                      '        guard !Task.isCancelled, pending == nil, accepts(context), let reader else { return nil '
                      '}\n'
                      '        let requestID = UUID()\n'
                      '        // Acquire the single-flight slot before queuing asynchronous work.\n'
                      '        pending = requestID; phase = .loading\n'
                      '        let request = Task { [weak self, weak reader] in\n'
                      '            defer { self?.finishPending(requestID) }\n'
                      '            guard !Task.isCancelled, let reader, self?.accepts(context) == true else { return '
                      '}\n'
                      '            do {\n'
                      '                let values = try await reader.categories()\n'
                      '                guard !Task.isCancelled, let self, self.pending == requestID, '
                      'self.accepts(context) else { return }\n'
                      '                self.categories = values // An authoritative empty array is a successful '
                      'directory.\n'
                      '                self.settledPhase = .loaded; self.phase = .loaded\n'
                      '            } catch is CancellationError {\n'
                      '                // Cancellation restores the previous state; it is not a new failure.\n'
                      '            } catch {\n'
                      '                guard !Task.isCancelled, let self, self.pending == requestID, '
                      'self.accepts(context) else { return }\n'
                      '                self.settledPhase = .failed; self.phase = .failed\n'
                      '            }\n'
                      '        }\n'
                      '        task = request\n'
                      '        return request\n'
                      '    }\n'
                      '    private func finishPending(_ requestID: UUID) {\n'
                      '        guard pending == requestID else { return }\n'
                      '        pending = nil; task = nil\n'
                      '        if phase == .loading { phase = settledPhase }\n'
                      '    }\n'
                      '}\n'}]},
 {'path': ['feature_batch_sources', 'Questify.xcodeproj/project.pbxproj', 'after_sha256'],
  'before': '6883e4530fbca37c79bdca43fcb209f4ffb3e11cdfbbba3fde031f3c1c96ef71',
  'action': 'set',
  'value': 'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552'},
 {'path': ['feature_batch_sources', 'Questify.xcodeproj/project.pbxproj', 'hunks'],
  'before': '52d0cf99f6d80b742a26bbf95e3d4060fd16558c4e3a061bb5f5404feff359cf',
  'action': 'splice',
  'start': 206,
  'stop': 209,
  'value': []},
 {'path': ['feature_batch_sources', 'Resources/Localizable.xcstrings'],
  'before': None,
  'action': 'set',
  'value': {'before_sha256': '6e9a854e14c29ad90a8b4ed88735e5641d15efc53ca810fb49dc366d3509910a',
            'after_sha256': 'fb84580d8986ad419bc6eeeb26901ad91fd8f448cbf367b6944c8b104887c8fa',
            'hunks': [{'before': '          }\n        }\n      }\n    }\n  },\n  "version": "1.0"\n',
                       'after': '          }\n'
                                '        }\n'
                                '      }\n'
                                '    },\n'
                                '    "roamRouteReplay.start": {\n'
                                '      "extractionState": "manual",\n'
                                '      "localizations": {\n'
                                '        "en": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "Replay saved route"\n'
                                '          }\n'
                                '        },\n'
                                '        "zh-Hans": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "回放已保存路线"\n'
                                '          }\n'
                                '        }\n'
                                '      }\n'
                                '    },\n'
                                '    "roamRouteReplay.again": {\n'
                                '      "extractionState": "manual",\n'
                                '      "localizations": {\n'
                                '        "en": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "Replay again"\n'
                                '          }\n'
                                '        },\n'
                                '        "zh-Hans": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "重新回放"\n'
                                '          }\n'
                                '        }\n'
                                '      }\n'
                                '    },\n'
                                '    "roamRouteReplay.skip": {\n'
                                '      "extractionState": "manual",\n'
                                '      "localizations": {\n'
                                '        "en": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "Show complete route"\n'
                                '          }\n'
                                '        },\n'
                                '        "zh-Hans": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "跳到完整路线"\n'
                                '          }\n'
                                '        }\n'
                                '      }\n'
                                '    },\n'
                                '    "roamRouteReplay.progress": {\n'
                                '      "extractionState": "manual",\n'
                                '      "localizations": {\n'
                                '        "en": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "Saved route replay progress"\n'
                                '          }\n'
                                '        },\n'
                                '        "zh-Hans": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "已保存路线回放进度"\n'
                                '          }\n'
                                '        }\n'
                                '      }\n'
                                '    },\n'
                                '    "roamRouteReplay.playing": {\n'
                                '      "extractionState": "manual",\n'
                                '      "localizations": {\n'
                                '        "en": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "Replaying this saved route"\n'
                                '          }\n'
                                '        },\n'
                                '        "zh-Hans": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "正在回放本次已保存路线"\n'
                                '          }\n'
                                '        }\n'
                                '      }\n'
                                '    },\n'
                                '    "roamRouteReplay.completed": {\n'
                                '      "extractionState": "manual",\n'
                                '      "localizations": {\n'
                                '        "en": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "Route replay complete"\n'
                                '          }\n'
                                '        },\n'
                                '        "zh-Hans": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "路线回放完成"\n'
                                '          }\n'
                                '        }\n'
                                '      }\n'
                                '    },\n'
                                '    "roamRouteReplay.ready": {\n'
                                '      "extractionState": "manual",\n'
                                '      "localizations": {\n'
                                '        "en": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "Complete saved route. Replay when you choose."\n'
                                '          }\n'
                                '        },\n'
                                '        "zh-Hans": {\n'
                                '          "stringUnit": {\n'
                                '            "state": "translated",\n'
                                '            "value": "已显示完整保存路线，可随时选择回放。"\n'
                                '          }\n'
                                '        }\n'
                                '      }\n'
                                '    }\n'
                                '  },\n'
                                '  "version": "1.0"\n'}]}},
 {'path': ['feature_batch_sources', 'Tests/CoreTests/ClubGovernanceProductionTests.swift'],
  'before': 'cfa722c02b6910be22438f52fa82789dd7976ca6cfbdfc3193c49910c063dda4',
  'action': 'remove'},
 {'path': ['feature_batch_sources', 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift'],
  'before': '8f14b344f58bcb72eb7268a38d3410600ccea57c455f0bf35d817b4054e13990',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'App/ProjectNodeImageCrop.swift'],
  'before': 'e486a844955b62dfa373c30989f0955412cfe75c872cfba7794bb07741ed1e04',
  'action': 'set',
  'value': 'f9997b618a2d850070052092f2e83ef8b81b7ee1bcadba1cb7e7b846e7ab964a'},
 {'path': ['feature_batch_support_sha256', 'Resources/Localizable.xcstrings'],
  'before': 'a01d298725f0209abe21f00a7845573740514181d7e1d3970ed2dd1ff1016126',
  'action': 'set',
  'value': 'fb84580d8986ad419bc6eeeb26901ad91fd8f448cbf367b6944c8b104887c8fa'},
 {'path': ['feature_batch_support_sha256', 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift'],
  'before': '1df7ddb22f7a28984e54fd748a84132b77ee7b6e0a6ecfb258c082ce37d22c1d',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'],
  'before': 'edca032ba88b7e2886e6443d30c27ba481180c22f341323004b545f8ec4793d1',
  'action': 'set',
  'value': 'caaae8dab10e8a9d69500cf1243d1b31311f0b8d4eda568a2dfc58c7ab10d0cc'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_category_roam_registration.py'],
  'before': None,
  'action': 'set',
  'value': '960f1d8e34f917070381ac24dd4382ae76c031a16e827fccddc3b641207462ff'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py'],
  'before': 'e51a7f3d7658daabff340a7505b6b0730c11214d7d4f94e8f1e3aec0a180f34a',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_club_customer_keyword_debounce.py'],
  'before': '4300286e5fe123977572507261b58ed0ae9986635123dab4ce8c47c3e132247a',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_club_customer_permissions.py'],
  'before': '486f0e1c2bf48819826c7fbfbd25d3cf17992c06b4d5416b830481efc37dcd24',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_global_search_category_recovery.py'],
  'before': None,
  'action': 'set',
  'value': '84a9740edc1f019f456da9500ff17f142ef0e4c3d6c9216a382d290bb2255112'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_merchant_decor_tag_picker.py'],
  'before': 'ba26e3e554981a70af63427ac35c1c03d881236aa0925023017fff3814aca4fa',
  'action': 'set',
  'value': '491182e97a8e53e1b3372c130d1a1f7857c10804302578a624c706d473e2fec7'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_merchant_review_draft_return.py'],
  'before': '7a182efdc5e19e88364b7dc8f340a9411230a26d7a18781b348d0432d25ae08f',
  'action': 'set',
  'value': 'e9f31299585059f9ce7f6e23002bd815471f7ba85e83707fe9fd571934dd1968'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_profile_avatar.py'],
  'before': '7a72694829eed0698bc0a35a850b3085b98b45c0f877258586f8b58bad9d0b1d',
  'action': 'set',
  'value': '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py'],
  'before': '2eebccd3f4fcae76a5d9b1ccfe6961b792e74651d9046acde80127248753e3b9',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_profile_reload_discard.py'],
  'before': '75ace966791986d90b86bf771cc7b2057a19b37c5ede5f95d2c9f24905627bdd',
  'action': 'set',
  'value': '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'},
 {'path': ['feature_batch_support_sha256', 'Tests/ContractChecks/test_roam_route_replay.py'],
  'before': None,
  'action': 'set',
  'value': '7975870aa351513b00d8eb7fe4dd24c984d127a3fea0eb612daa8d9a20f78152'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/ClubCustomerPermissionTests.swift'],
  'before': '108023cc9f80e19b7647eec88430fc3295589b3876eccf89ef54052a1df43166',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift'],
  'before': None,
  'action': 'set',
  'value': '4a78eca6ec1df117f1fd24675e775e7ffe4c6f1dc85f2e4988d223705092108e'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'],
  'before': '8254125aa4a884f5c921414223a88c3eb1383254dbdb4127b979d9311cee529d',
  'action': 'set',
  'value': '5e90fd3657fd322477dc3c28347fb0efc3e33553ae39ef4bf990308bf445de86'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/ProfileEditTests.swift'],
  'before': '543bd382680a1b81d5480030727a0e60aed607f23b5f75b5f070790c438b6721',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift'],
  'before': '49f0c005f050ea4b11e897d7091ae5a287c5015b18ded5996c5791eca142ffd4',
  'action': 'set',
  'value': 'c0d731ccb927b9bad2ae07f65fac52ac99f924e121c66bede81ee5b411742bba'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/RoamRouteReplayTests.swift'],
  'before': None,
  'action': 'set',
  'value': 'bee4110b199342c675def44f367f9da180da699124b9cf5f9222e7ad06441e0a'},
 {'path': ['feature_batch_support_sha256', 'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift'],
  'before': None,
  'action': 'set',
  'value': '4f7ed5b79dd4929b5eb828c53e1a07826e1a8b6ff78a09c0f55148faa24a4dad'},
 {'path': ['feature_batch_support_sha256', 'docs/club-customer-keyword-debounce.md'],
  'before': 'fb566ab4570fac0340d6e2e614e9f567f1aa355ea34edffb2b4509c1d2ea29c3',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'docs/club-customer-permissions.md'],
  'before': '8aa8718047b2ec4da1d6a7d19b288abdaf8bf3df0d84dcbb9a6e1749413a094d',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'docs/global-search-category-recovery.md'],
  'before': None,
  'action': 'set',
  'value': '886a26d9fa6bbe316551c53fb83d7cdfae754351693d9a671040f6a72c878dca'},
 {'path': ['feature_batch_support_sha256', 'docs/merchant-decor-tag-picker/implementation.md'],
  'before': 'a9ab2ea9ba3a17a861fde2315e664ff8912a95370b0e758782eb4a652780fe1d',
  'action': 'set',
  'value': '5d7d4a190a5b0146433d7e7d077789ce99fad2669f0a44798a067e7f1702b141'},
 {'path': ['feature_batch_support_sha256', 'docs/roam-route-replay.md'],
  'before': None,
  'action': 'set',
  'value': '5c409db1da0daffd0a5143873e96310094c417941b7497e1b5536e02b57a4395'},
 {'path': ['feature_batch_support_sha256', 'tools/check_profile_read_failure_contract.py'],
  'before': '93be0320b66acf7ce52b812efd7cc93e035a6b2807f9566652d59686df2149a3',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'tools/club_customer_directory_admission.py'],
  'before': '05883b9edd5018bdeb8880a1b0729caf659b3194e2cac84e0f3bff5a0b0547a5',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'tools/tests/test_creator_shelf_state_history.py'],
  'before': '17cef4270aefc68b8b39fc0c10fe8d0fd25808e1647e686b49f5546a8330d414',
  'action': 'remove'},
 {'path': ['feature_batch_support_sha256', 'tools/tests/test_gitleaks_configuration.py'],
  'before': '886f3811e0cb120f2018706fd68914c0020cacbb4a52cba572ce1602dc2335b3',
  'action': 'set',
  'value': '9ee49cce7ab873e11deae82b643f48abc57482ce316c43764a0a6aa5d7579e52'},
 {'path': ['followon_support_sha256', 'tools/run_static_checks.py'],
  'before': '2dd7cec71218f96c5d579f804542357c1f19e9ee5f5e110a80efa99856135937',
  'action': 'set',
  'value': '5765354aae29e6b044cd45bc6145c3a35b6420579295631a5c74bca4959a1ed4'},
 {'path': ['followon_support_sha256', 'tools/tests/test_native_static_checks.py'],
  'before': 'be67bf7aa3d544af21ac920f84f37d3f295277e3cc23d6d19bc8804bf6e5256e',
  'action': 'set',
  'value': 'f1a980c56b45f543465417d3a2d884a2dc1fc624eaeb6625d84ace7f88735f0c'}]
PARENT_TO_R2_ORDER = {'followon_support_sha256': ['tools/ci138_followon_handshake_contract.json',
                             'tools/tests/test_review_availability_inverse.py',
                             'tools/ci138_followon_projection.py',
                             'tools/story_reveal_arrival_inverse.py',
                             'tools/story_reveal_arrival_contract.json',
                             'tools/remaining_editor_drivers_inverse.py',
                             'tools/remaining_editor_drivers_contract.json',
                             'tools/review_availability_inverse.py',
                             'tools/review_availability_contract.json',
                             'tools/ci138_coupon_square_publication_driver.py',
                             'docs/ci138-coupon-square-publication-driver-contract.json',
                             'tools/tests/test_story_reveal_arrival.py',
                             'tools/tests/test_remaining_editor_drivers.py',
                             'tools/tests/test_ci138_coupon_square_publication_driver.py',
                             'tools/story_template_planning_contract.json',
                             'tools/player_map_history_planning_contract.json',
                             '.github/workflows/native-ios.yml',
                             'tools/run130_receipt_planning.py',
                             'App/SquareWorkspaceView.swift',
                             'tools/run_ui_shard.py',
                             'Core/ApprovedTopicReleasePublicationClient.swift',
                             'App/ApprovedReleasePreparationView.swift',
                             'tools/branch_history_handshake_planning_contract.json',
                             'tools/club_parity_planning_contract.json',
                             'tools/run130_receipt_planning_contract.json',
                             'tools/run130_prepared_readiness_contract.json',
                             'tools/run129_late_readiness_contract.json',
                             'App/CouponCodeView.swift',
                             'tools/ci_gates.py',
                             'tools/run129_repair_planning_contract.json',
                             'tools/ui_duration_weights.json',
                             'Tests/ContractChecks/test_run129_navigation_diagnostics.py',
                             'tools/branch_history_handshake_planning.py',
                             'Tests/AppUnitTests/PlayBranchHistoryFixtureHandshakeTests.swift',
                             'Tests/ContractChecks/test_branch_history_fixture_handshake.py',
                             'App/PublishingContextHandoffViews.swift',
                             'App/PlayBranchHistoryView.swift',
                             'App/PlayBranchHistoryFixtureSupport.swift',
                             'App/ProjectSubmissionEvidenceViews.swift',
                             'tools/tests/test_ci138_followon_integration.py',
                             'tools/run_static_checks.py',
                             'tools/tests/test_native_static_checks.py'],
 'feature_batch_sources': ['App/ProjectEditView.swift',
                           'App/ProjectEditDetailForms.swift',
                           'App/QuestifyDensityMap.swift',
                           'Tests/ContractChecks/test_ci138_map_readonly_enabled.py',
                           'Questify.xcodeproj/project.pbxproj',
                           'Tests/AppUITests/MerchantContentFlowTests.swift',
                           'App/AccountComplianceViews.swift',
                           'App/AppSession.swift',
                           'App/ClubOperationsViews.swift',
                           'App/DiscoveryReading.swift',
                           'App/MerchantBusinessRecordViews.swift',
                           'App/MerchantBusinessViews.swift',
                           'App/MerchantContentEditor.swift',
                           'App/MerchantContentViews.swift',
                           'App/MerchantNPCViews.swift',
                           'App/MerchantOperationsEditor.swift',
                           'App/MerchantOperationsViews.swift',
                           'App/QuestifyApp.swift',
                           'App/QuestifyImageEntityCard.swift',
                           'App/RoamBrowserView.swift',
                           'App/RoamItemDetailView.swift',
                           'App/SearchMapCanvas.swift',
                           'App/SearchMapExplorerView.swift',
                           'App/ShopNPCView.swift',
                           'App/TopicBrowserView.swift',
                           'Core/AccountComplianceCoordinator.swift',
                           'Core/AccountComplianceService.swift',
                           'Core/MerchantContentCommands.swift',
                           'Core/MerchantNPCCoordinators.swift',
                           'Core/MerchantStationContracts.swift',
                           'Core/RuntimeLocationProjection.swift',
                           'App/FreeExplorationViews.swift',
                           'App/MerchantOnboardingView.swift',
                           'App/MerchantTemplateAssistSheet.swift',
                           'App/MerchantTemplateSuggestionReviewPanel.swift',
                           'App/PlayExperienceView.swift',
                           'App/ProjectStoryAudioAuthorView.swift',
                           'App/PublicMerchantHomeView.swift',
                           'App/ShopNPCSessionHost.swift',
                           'Core/MerchantOnboardingContracts.swift',
                           'Core/MerchantOperationsContracts.swift',
                           'Core/MerchantOperationsReading.swift',
                           'Core/MerchantOperationsService.swift',
                           'Core/MerchantTemplateAssistFlow.swift',
                           'Core/MerchantTemplateSuggestionReview.swift',
                           'Core/ProjectStoryAudioFlow.swift',
                           'Core/ProjectStoryAudioJournal.swift',
                           'Core/ProjectStoryAudioTarget.swift',
                           'Core/PublicMerchantHome.swift',
                           'Core/RoamMerchant.swift',
                           'Core/ShopNPCContracts.swift',
                           'Core/ShopNPCCoordinator.swift',
                           'App/MerchantHomeView.swift',
                           'App/MerchantMarketingView.swift',
                           'App/NativeEntryLandingView.swift',
                           'App/ProjectEditRichStoryForms.swift',
                           'App/PublishingAIDraftSheet.swift',
                           'Core/MerchantMarketingModels.swift',
                           'Core/ProjectInitialState.swift',
                           'Core/PublishingAIDraftFlow.swift',
                           'App/OfficialEventsBrowserView.swift',
                           'Core/OfficialEventContracts.swift',
                           'Core/RoamContracts.swift',
                           'App/ActivityDetailView.swift',
                           'App/ProjectStoryTemplatePresentation.swift',
                           'App/ProjectStoryTemplateView.swift',
                           'App/ShopNPCFixtureView.swift',
                           'Core/ActivityDetail.swift',
                           'App/AccountView.swift',
                           'App/GrowthCenterView.swift',
                           'App/GrowthLeaderboardView.swift',
                           'App/MerchantNPCFixtureView.swift',
                           'Core/MerchantNPCContracts.swift',
                           'Core/MerchantNPCHTTP.swift',
                           'App/TemplateAuthoringView.swift',
                           'Core/TemplateAuthoringCoordinator.swift',
                           'Core/TemplateAuthoringService.swift',
                           'Core/TemplateAuthoringStorage.swift',
                           'App/ClubAIDesignView.swift',
                           'Core/ClubAIDesignFlow.swift',
                           'App/MerchantEngagementViews.swift',
                           'App/ProfileOrdersView.swift',
                           'App/ProjectEndingConditionPicker.swift',
                           'Core/ProfileContracts.swift',
                           'App/MerchantBusinessEditor.swift',
                           'Core/MerchantBusinessMutation.swift',
                           'App/MerchantNPCComposerRetention.swift',
                           'App/ObjectBadgeViews.swift',
                           'App/GlobalSearchView.swift',
                           'App/MerchantNPCKnowledgeDraftView.swift',
                           'Core/SearchMapService.swift',
                           'App/OwnedOrderComposition.swift',
                           'App/SearchMapFilterSheet.swift',
                           'App/ProfileEditView.swift',
                           'App/RoamExperienceHubView.swift',
                           'App/RoamHistoryViews.swift',
                           'App/TicketWalletDetailView.swift',
                           'App/SocialGuideViews.swift',
                           'App/TicketWalletModel.swift',
                           'App/TicketWalletView.swift',
                           'Core/ProfileEditContracts.swift',
                           'Core/ProfileEditCoordinator.swift',
                           'Core/ProfileEditService.swift',
                           'Core/TicketWalletReading.swift',
                           'Core/ProjectEditContract.swift',
                           'Core/ProjectEditCoordinator.swift',
                           'Core/ProjectEditDraft.swift',
                           'Core/ProjectEditHTTPService.swift',
                           'Core/ProjectEditStoryContract.swift',
                           'Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift',
                           'App/ProjectStoryImageAuthorView.swift',
                           'App/ProjectStoryImagePresentation.swift',
                           'Core/ProjectStoryImageTarget.swift',
                           'Core/MerchantBusinessCoordinator.swift',
                           'App/ProjectInitialStateEditor.swift',
                           'App/ProjectNodeBusinessHoursField.swift',
                           'Core/ProjectNodeBusinessHours.swift',
                           'App/AppCompositionRoot.swift',
                           'App/MerchantProjectsView.swift',
                           'Core/MerchantContentService.swift',
                           'App/ProjectEditPendingPresentation.swift',
                           'Core/SearchMapReading.swift',
                           'App/RoamExperienceComponents.swift',
                           'Core/RoamExperienceMath.swift',
                           'Resources/Localizable.xcstrings'],
 'feature_batch_support_sha256': ['App/MerchantCityQuotaSummary.swift',
                                  'App/MerchantCustomerContactSummary.swift',
                                  'App/MerchantCustomerEmptyRecoverySection.swift',
                                  'App/MerchantStationServiceTimeFields.swift',
                                  'App/NPCChatDataView.swift',
                                  'App/NPCQuickQuestionBar.swift',
                                  'App/ProjectCategoryPicker.swift',
                                  'App/ProjectEditDatePicker.swift',
                                  'App/ProjectEditIssueNavigation.swift',
                                  'App/ProjectEditNodeDescriptionField.swift',
                                  'App/ProjectEditStarterPresentation.swift',
                                  'App/ProjectPendingNodeRemovalController.swift',
                                  'App/QuestifyProgressiveBlurArtwork.swift',
                                  'App/SearchMapLayerSelection.swift',
                                  'Core/MerchantCityClaimWithdrawal.swift',
                                  'Core/MerchantCityQuota.swift',
                                  'Core/MerchantCustomerContactPresentation.swift',
                                  'Core/MerchantCustomerEmptyRecovery.swift',
                                  'Core/MerchantNPCKnowledgeDraft.swift',
                                  'Core/MerchantNPCKnowledgeDraftCoordinator.swift',
                                  'Core/MerchantNPCKnowledgeValidation.swift',
                                  'Core/MerchantStationPauseChoice.swift',
                                  'Core/MerchantStationServiceWindow.swift',
                                  'Core/NPCChatData.swift',
                                  'Core/NPCChatDataCoordinator.swift',
                                  'Core/NPCQuickQuestion.swift',
                                  'Core/ProgressiveBlurParameters.swift',
                                  'Core/ProjectEditDateSelection.swift',
                                  'Core/ProjectEditIssueLocation.swift',
                                  'Core/ProjectPendingNodeRemoval.swift',
                                  'Core/RoamEventDestination.swift',
                                  'Core/RoamRetainedRead.swift',
                                  'Core/SearchMapLayerVisibility.swift',
                                  'Core/SearchMapViewportSelection.swift',
                                  'Resources/Localizable.xcstrings',
                                  'Resources/MerchantCityClaimWithdrawalLocalizations.fragment.json',
                                  'Resources/MerchantCityQuotaLocalizations.fragment.json',
                                  'Resources/MerchantCustomerContactLocalizations.fragment.json',
                                  'Resources/MerchantCustomerEmptyRecoveryLocalizations.fragment.json',
                                  'Resources/MerchantStationPauseLocalizations.fragment.json',
                                  'Resources/MerchantStationServiceTimeLocalizations.fragment.json',
                                  'Resources/ProjectCategoryPicker.xcstrings',
                                  'Resources/ProjectEditDatePicker.xcstrings',
                                  'Resources/ProjectPendingNodeRemoval.xcstrings',
                                  'Resources/ProjectPendingNodeRemovalLocalizations.fragment.json',
                                  'Resources/RoamEventDestinationLocalizations.fragment.json',
                                  'Resources/RoamRetainedReadLocalizations.fragment.json',
                                  'Resources/SearchMapLayerVisibilityLocalizations.fragment.json',
                                  'Resources/SearchMapViewportLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantCustomerContactSummaryTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCKnowledgeDraftViewTests.swift',
                                  'Tests/AppUnitTests/NPCChatDataViewTests.swift',
                                  'Tests/AppUnitTests/NPCQuickQuestionBarTests.swift',
                                  'Tests/AppUnitTests/ProjectCategoryPickerTests.swift',
                                  'Tests/AppUnitTests/ProjectEditDatePickerTests.swift',
                                  'Tests/AppUnitTests/ProjectEditExactAutosaveTests.swift',
                                  'Tests/AppUnitTests/ProjectEditIssueNavigationTests.swift',
                                  'Tests/AppUnitTests/ProjectEditNodeDescriptionFieldTests.swift',
                                  'Tests/AppUnitTests/ProjectPendingNodeRemovalControllerTests.swift',
                                  'Tests/AppUnitTests/QuestifyProgressiveBlurArtworkTests.swift',
                                  'Tests/AppUnitTests/RoamEventDestinationViewTests.swift',
                                  'Tests/AppUnitTests/RoamRetainedReadViewTests.swift',
                                  'Tests/AppUnitTests/SearchMapLayerVisibilityViewTests.swift',
                                  'Tests/AppUnitTests/SearchMapViewportSelectionViewTests.swift',
                                  'Tests/ContractChecks/merchant_customer_empty_inverse.py',
                                  'Tests/ContractChecks/test_merchant_business_access_lifetime.py',
                                  'Tests/ContractChecks/test_merchant_city_claim_withdrawal.py',
                                  'Tests/ContractChecks/test_merchant_city_quota.py',
                                  'Tests/ContractChecks/test_merchant_customer_contact.py',
                                  'Tests/ContractChecks/test_merchant_customer_empty_recovery.py',
                                  'Tests/ContractChecks/test_merchant_station_optional_fallback.py',
                                  'Tests/ContractChecks/test_merchant_station_service_time.py',
                                  'Tests/ContractChecks/test_run129_map_button_role.py',
                                  'Tests/ContractChecks/test_run130_topic_media_source_adapter.py',
                                  'Tests/CoreTests/MerchantCityClaimWithdrawalTests.swift',
                                  'Tests/CoreTests/MerchantCityQuotaTests.swift',
                                  'Tests/CoreTests/MerchantContentContractTests.swift',
                                  'Tests/CoreTests/MerchantCustomerContactPresentationTests.swift',
                                  'Tests/CoreTests/MerchantCustomerEmptyRecoveryTests.swift',
                                  'Tests/CoreTests/MerchantNPCKnowledgeDraftTests.swift',
                                  'Tests/CoreTests/MerchantStationPauseChoiceTests.swift',
                                  'Tests/CoreTests/MerchantStationServiceWindowTests.swift',
                                  'Tests/CoreTests/NPCChatDataTests.swift',
                                  'Tests/CoreTests/NPCQuickQuestionTests.swift',
                                  'Tests/CoreTests/ProgressiveBlurParametersTests.swift',
                                  'Tests/CoreTests/ProjectEditDateSelectionTests.swift',
                                  'Tests/CoreTests/ProjectEditIssueLocationTests.swift',
                                  'Tests/CoreTests/ProjectPendingNodeRemovalTests.swift',
                                  'Tests/CoreTests/RoamEventDestinationTests.swift',
                                  'Tests/CoreTests/RoamRetainedReadTests.swift',
                                  'Tests/CoreTests/SearchMapLayerVisibilityTests.swift',
                                  'Tests/CoreTests/SearchMapViewportSelectionTests.swift',
                                  'docs/merchant-city-claim-withdrawal/implementation.md',
                                  'docs/merchant-city-quota/implementation.md',
                                  'docs/merchant-customer-contact/implementation.md',
                                  'docs/merchant-customer-empty-recovery/implementation.md',
                                  'docs/merchant-station-pause/optional-fallback.md',
                                  'docs/merchant-station-service-time/implementation.md',
                                  'tools/ci138_followon_projection.py',
                                  'tools/map_readonly_contract.json',
                                  'tools/map_readonly_inverse.py',
                                  'tools/review_availability_inverse.py',
                                  'tools/run138_ci_entry_contract.json',
                                  'tools/tests/test_review_availability_inverse.py',
                                  'App/MerchantDecorTagEditor.swift',
                                  'App/MerchantFeaturedActivityPicker.swift',
                                  'App/MerchantFeaturedClearControl.swift',
                                  'App/MerchantOnboardingHoursEditor.swift',
                                  'App/MerchantTemplateSuggestionEditSheet.swift',
                                  'App/ProjectChapterAudioAuthorView.swift',
                                  'App/ProjectChapterAudioField.swift',
                                  'App/ProjectChapterAudioPresentation.swift',
                                  'App/ProjectEditorAudioPreview.swift',
                                  'App/ShopNPCQuestionReuseButton.swift',
                                  'App/ShopNPCScriptedGuideView.swift',
                                  'Core/MerchantDecorTagDraft.swift',
                                  'Core/MerchantFeaturedActivityOptions.swift',
                                  'Core/MerchantTemplateSuggestionEdit.swift',
                                  'Core/ProjectChapterAudio.swift',
                                  'Core/RoamFeaturedActivitySelection.swift',
                                  'Core/RoamPlayerProfileSelection.swift',
                                  'Core/RoamRouteTopicDestination.swift',
                                  'Core/ShopNPCQuestionReuse.swift',
                                  'Core/ShopNPCScriptedGuide.swift',
                                  'Resources/MerchantDecorTagLocalizations.fragment.json',
                                  'Resources/MerchantFeaturedActivityLocalizations.fragment.json',
                                  'Resources/MerchantFeaturedClearLocalizations.fragment.json',
                                  'Resources/MerchantOnboardingHoursLocalizations.fragment.json',
                                  'Resources/ProjectChapterAudio.xcstrings',
                                  'Resources/ProjectEditorAudioPreview.xcstrings',
                                  'Resources/ProjectInitialState.xcstrings',
                                  'Resources/PublicMerchantHomeBusinessStateLocalizations.fragment.json',
                                  'Resources/RoamMerchantBusinessStateLocalizations.fragment.json',
                                  'Resources/RoamPlayerProfileLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift',
                                  'Tests/AppUnitTests/MerchantFeaturedActivityPickerTests.swift',
                                  'Tests/AppUnitTests/MerchantFeaturedClearControlTests.swift',
                                  'Tests/AppUnitTests/MerchantOnboardingHoursSessionTests.swift',
                                  'Tests/AppUnitTests/MerchantTemplateSuggestionEditTests.swift',
                                  'Tests/AppUnitTests/ProjectChapterAudioFieldTests.swift',
                                  'Tests/AppUnitTests/ProjectChapterAudioPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectEditorAudioPreviewTests.swift',
                                  'Tests/AppUnitTests/ProjectInitialStateEditorTests.swift',
                                  'Tests/AppUnitTests/PublicMerchantHomeBusinessStateViewTests.swift',
                                  'Tests/AppUnitTests/RoamFeaturedActivitySelectionViewTests.swift',
                                  'Tests/AppUnitTests/RoamMerchantBusinessStateViewTests.swift',
                                  'Tests/AppUnitTests/RoamPlayerProfileSelectionViewTests.swift',
                                  'Tests/AppUnitTests/RoamRouteTopicDestinationViewTests.swift',
                                  'Tests/AppUnitTests/ShopNPCQuestionReuseTests.swift',
                                  'Tests/AppUnitTests/ShopNPCScriptedGuideTests.swift',
                                  'Tests/ContractChecks/test_merchant_decor_tag_picker.py',
                                  'Tests/ContractChecks/test_merchant_featured_activity_picker.py',
                                  'Tests/ContractChecks/test_merchant_featured_clear.py',
                                  'Tests/ContractChecks/test_merchant_onboarding_hours_editor.py',
                                  'Tests/ContractChecks/test_shop_npc_interruption.py',
                                  'Tests/CoreTests/MerchantDecorTagDraftTests.swift',
                                  'Tests/CoreTests/MerchantFeaturedActivityOptionsTests.swift',
                                  'Tests/CoreTests/MerchantFeaturedClearContractTests.swift',
                                  'Tests/CoreTests/MerchantOnboardingContractTests.swift',
                                  'Tests/CoreTests/MerchantOnboardingHoursTests.swift',
                                  'Tests/CoreTests/MerchantTemplateSuggestionEditTests.swift',
                                  'Tests/CoreTests/ProjectChapterAudioTests.swift',
                                  'Tests/CoreTests/ProjectChapterAudioUploadTests.swift',
                                  'Tests/CoreTests/ProjectInitialStateTests.swift',
                                  'Tests/CoreTests/PublicMerchantHomeBusinessStateTests.swift',
                                  'Tests/CoreTests/RoamFeaturedActivitySelectionTests.swift',
                                  'Tests/CoreTests/RoamMerchantBusinessStateTests.swift',
                                  'Tests/CoreTests/RoamPlayerProfileSelectionTests.swift',
                                  'Tests/CoreTests/RoamRouteTopicDestinationTests.swift',
                                  'Tests/CoreTests/ShopNPCQuestionReuseTests.swift',
                                  'Tests/CoreTests/ShopNPCScriptedGuideTests.swift',
                                  'docs/merchant-decor-tag-picker/implementation.md',
                                  'docs/merchant-featured-activity-picker/implementation.md',
                                  'docs/merchant-featured-clear/implementation.md',
                                  'docs/merchant-onboarding-hours/implementation.md',
                                  'App/MerchantInsightRecommendationRows.swift',
                                  'App/ProjectThoughtDefinitionsEditor.swift',
                                  'App/PublishingAIQuotaSection.swift',
                                  'Core/MerchantInsightRecommendation.swift',
                                  'Core/ProjectThoughtDefinitions.swift',
                                  'Resources/MerchantInsightNavigationLocalizations.fragment.json',
                                  'Resources/ProjectThoughtDefinitions.xcstrings',
                                  'Tests/AppUnitTests/ProjectThoughtDefinitionsEditorTests.swift',
                                  'Tests/AppUnitTests/PublishingAIQuotaSectionTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_navigation.py',
                                  'Tests/CoreTests/MerchantInsightRecommendationTests.swift',
                                  'Tests/CoreTests/ProjectThoughtDefinitionsTests.swift',
                                  'Tests/CoreTests/PublishingAIQuotaReadTests.swift',
                                  'docs/merchant-insight-navigation/implementation.md',
                                  'App/MerchantNPCConversationHistoryView.swift',
                                  'Core/MerchantNPCConversationHistory.swift',
                                  'Core/ProjectEndingConditionChoices.swift',
                                  'Resources/ProjectEndingConditionPicker.xcstrings',
                                  'Resources/RoamPlaceReadStatusLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantNPCComposerRetentionTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCConversationHistoryTests.swift',
                                  'Tests/AppUnitTests/OfficialEventBrowseStateViewTests.swift',
                                  'Tests/AppUnitTests/ProjectEndingConditionPickerTests.swift',
                                  'Tests/AppUnitTests/RoamPlaceReadStatusViewTests.swift',
                                  'Tests/ContractChecks/test_official_event_contracts.py',
                                  'Tests/ContractChecks/test_official_preference_ui_regressions.py',
                                  'Tests/CoreTests/MerchantNPCConversationHistoryTests.swift',
                                  'Tests/CoreTests/OfficialEventTests.swift',
                                  'Tests/CoreTests/ProjectEndingConditionChoicesTests.swift',
                                  'Tests/CoreTests/RoamPlaceReadStatusTests.swift',
                                  'App/MerchantInsightProfileSummary.swift',
                                  'App/ProjectNodeGameplayRemovalField.swift',
                                  'Core/ActivityRequiredClubSelection.swift',
                                  'Core/ProjectNodeGameplayRemoval.swift',
                                  'Resources/ActivityRequiredClubLocalizations.fragment.json',
                                  'Resources/MerchantInsightProfileLocalizations.fragment.json',
                                  'Resources/ProjectNodeGameplayRemoval.xcstrings',
                                  'Tests/AppUnitTests/ActivityRequiredClubSelectionViewTests.swift',
                                  'Tests/AppUnitTests/MerchantInsightProfileSummaryTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeGameplayRemovalFieldTests.swift',
                                  'Tests/AppUnitTests/PublishingAIDraftCandidateRetentionTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_profile_entry.py',
                                  'Tests/CoreTests/ActivityRequiredClubSelectionTests.swift',
                                  'Tests/CoreTests/ProjectNodeGameplayRemovalTests.swift',
                                  'Tests/CoreTests/PublishingAIDraftCandidateRetentionTests.swift',
                                  'docs/merchant-insight-profile-entry/implementation.md',
                                  'App/ProjectNodeTemplateSelectionField.swift',
                                  'Core/ProjectNodeTemplateSelection.swift',
                                  'Resources/ProjectNodeTemplateSelection.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodeTemplateSelectionPresentationTests.swift',
                                  'Tests/AppUnitTests/ShopNPCModernOutcomeTests.swift',
                                  'Tests/ContractChecks/check_shop_npc.py',
                                  'Tests/CoreTests/ProjectNodeTemplateSelectionTests.swift',
                                  'Tests/CoreTests/ShopNPCInterruptionTests.swift',
                                  'Tests/CoreTests/ShopNPCModernOutcomeTests.swift',
                                  'Tests/CoreTests/ShopNPCTests.swift',
                                  'App/ActivityAssociatedPlaysSection.swift',
                                  'App/MerchantInsightAttributionSummary.swift',
                                  'App/MerchantInsightRecentVisitorsSection.swift',
                                  'Core/MerchantInsightAttribution.swift',
                                  'Core/MerchantInsightRecentVisitors.swift',
                                  'Resources/ActivityAssociatedPlaysLocalizations.fragment.json',
                                  'Resources/MerchantInsightAttributionLocalizations.fragment.json',
                                  'Resources/MerchantInsightVisitorsLocalizations.fragment.json',
                                  'Tests/AppUnitTests/ActivityAssociatedPlaysViewTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_attribution.py',
                                  'Tests/ContractChecks/test_merchant_insight_recent_visitors.py',
                                  'Tests/CoreTests/ActivityAssociatedPlaysTests.swift',
                                  'Tests/CoreTests/MerchantInsightAttributionTests.swift',
                                  'Tests/CoreTests/MerchantInsightRecentVisitorsTests.swift',
                                  'docs/merchant-insight-attribution/implementation.md',
                                  'docs/merchant-insight-recent-visitors/implementation.md',
                                  'Resources/GrowthLeaderboardExploreLocalizations.fragment.json',
                                  'Resources/MerchantInsightInterpretationLocalizations.fragment.json',
                                  'Tests/AppUnitTests/GrowthLeaderboardExploreViewTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCResponseIdentityTests.swift',
                                  'Tests/ContractChecks/test_merchant_insight_interpretation.py',
                                  'Tests/CoreTests/MerchantInsightInterpretationTests.swift',
                                  'Tests/CoreTests/MerchantNPCResponseIdentityTests.swift',
                                  'Tests/CoreTests/MerchantNPCTests.swift',
                                  'docs/merchant-insight-interpretation/implementation.md',
                                  'App/ProjectNodeTemplateCreationField.swift',
                                  'Core/TemplateAuthoringSavedDraft.swift',
                                  'Resources/MerchantCoopCapacityClearLocalizations.fragment.json',
                                  'Resources/ProjectNodeTemplateCreation.xcstrings',
                                  'Tests/AppUnitTests/GrowthBadgeExploreViewTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeTemplateCreationTests.swift',
                                  'Tests/ContractChecks/test_merchant_coop_capacity_clear.py',
                                  'Tests/CoreTests/MerchantCoopCapacityClearTests.swift',
                                  'Tests/CoreTests/TemplateAuthoringSavedDraftTests.swift',
                                  'docs/merchant-coop-capacity-clear/implementation.md',
                                  'Resources/MerchantCoopChargeChoiceLocalizations.fragment.json',
                                  'Tests/AppUnitTests/ClubAIDesignCandidateRetentionTests.swift',
                                  'Tests/ContractChecks/test_merchant_coop_charge_choice.py',
                                  'Tests/CoreTests/ClubAIDesignCandidateRetentionTests.swift',
                                  'Tests/CoreTests/MerchantCoopChargeChoiceTests.swift',
                                  'Tests/CoreTests/MerchantOperationsTests.swift',
                                  'docs/merchant-coop-charge-choice/implementation.md',
                                  'App/MerchantCRMDateRangePicker.swift',
                                  'Core/MerchantCRMDateRange.swift',
                                  'Core/ProjectStoryConditionChoice.swift',
                                  'Resources/MerchantCRMDatePickerLocalizations.fragment.json',
                                  'Resources/ProfileOrderTicketScheduleLocalizations.fragment.json',
                                  'Tests/AppUnitTests/ProfileOrderTicketScheduleViewTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryConditionPickerTests.swift',
                                  'Tests/ContractChecks/test_merchant_crm_date_picker.py',
                                  'Tests/CoreTests/MerchantCRMDateRangeTests.swift',
                                  'Tests/CoreTests/ProfileOrderTicketScheduleTests.swift',
                                  'Tests/CoreTests/ProjectStoryConditionChoiceTests.swift',
                                  'docs/merchant-crm-date-picker/implementation.md',
                                  'App/MerchantNPCGreetingPreview.swift',
                                  'Resources/MerchantNoteCorrectionLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantNPCGreetingPreviewTests.swift',
                                  'Tests/ContractChecks/test_merchant_note_correction_presentation.py',
                                  'Tests/CoreTests/MerchantNoteCorrectionPresentationTests.swift',
                                  'docs/merchant-note-correction/implementation.md',
                                  'App/ProjectNodeRouteMappingEditor.swift',
                                  'Core/MerchantRedemptionFilter.swift',
                                  'Core/ProjectNodeRouteMapping.swift',
                                  'Resources/MerchantRedemptionFilterLocalizations.fragment.json',
                                  'Resources/ProjectNodeRouteMapping.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodeRouteMappingEditorTests.swift',
                                  'Tests/ContractChecks/test_merchant_redemption_filter.py',
                                  'Tests/CoreTests/MerchantNPCMessageDraftTests.swift',
                                  'Tests/CoreTests/MerchantRedemptionFilterTests.swift',
                                  'Tests/CoreTests/ProjectNodeRouteMappingTests.swift',
                                  'docs/merchant-redemption-filter/implementation.md',
                                  'App/MerchantNPCTranscriptScroll.swift',
                                  'Resources/MerchantAftercareDecisionLocalizations.fragment.json',
                                  'Resources/ObjectBadgeWallLayoutLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantAftercareDecisionChangeTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCTranscriptScrollTests.swift',
                                  'Tests/AppUnitTests/ObjectBadgeWallLayoutTests.swift',
                                  'Tests/ContractChecks/test_merchant_aftercare_decision_change.py',
                                  'Tests/ContractChecks/test_object_badge_wall_layout.py',
                                  'docs/merchant-aftercare-decision/implementation.md',
                                  'App/MerchantAftercareEvidenceFlow.swift',
                                  'App/MerchantNPCKnowledgeDismissal.swift',
                                  'App/ProjectNodePhotoRemovalField.swift',
                                  'Core/GlobalSearchRetainedResults.swift',
                                  'Core/ProjectNodePhotoRemoval.swift',
                                  'Resources/GlobalSearchRetentionLocalizations.fragment.json',
                                  'Resources/MerchantAftercareEvidenceLocalizations.fragment.json',
                                  'Resources/ProjectNodePhotoRemoval.xcstrings',
                                  'Tests/AppUnitTests/MerchantAftercareEvidenceFlowTests.swift',
                                  'Tests/AppUnitTests/MerchantNPCKnowledgeDismissalTests.swift',
                                  'Tests/AppUnitTests/ProjectNodePhotoRemovalViewTests.swift',
                                  'Tests/ContractChecks/test_merchant_aftercare_evidence_flow.py',
                                  'Tests/CoreTests/GlobalSearchRetainedResultsTests.swift',
                                  'Tests/CoreTests/ProjectNodePhotoRemovalTests.swift',
                                  'docs/merchant-aftercare-evidence/implementation.md',
                                  'App/MerchantStationLiveCodeView.swift',
                                  'App/ProjectStoryVariablePicker.swift',
                                  'Core/ProjectStoryVariableInsertion.swift',
                                  'Resources/GlobalSearchDatePresetLocalizations.fragment.json',
                                  'Resources/MerchantStationLiveCodeLocalizations.fragment.json',
                                  'Resources/ProfileOrderTicketEntryLocalizations.fragment.json',
                                  'Resources/ProjectStoryVariableInsertion.xcstrings',
                                  'Tests/AppUnitTests/MerchantStationLiveCodeTests.swift',
                                  'Tests/AppUnitTests/ProfileOrderTicketNavigationTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryVariablePickerTests.swift',
                                  'Tests/AppUnitTests/SearchMapDatePresetDraftTests.swift',
                                  'Tests/ContractChecks/test_merchant_station_live_code.py',
                                  'Tests/ContractChecks/test_owned_order_composition.py',
                                  'Tests/ContractChecks/test_search_map_date_presets.py',
                                  'Tests/CoreTests/MerchantStationLiveCodeTimeTests.swift',
                                  'Tests/CoreTests/ProjectStoryVariableInsertionTests.swift',
                                  'docs/merchant-station-live-code/implementation.md',
                                  'App/ProjectDraftNodeOverview.swift',
                                  'Core/ProjectDraftNodeProjection.swift',
                                  'Resources/ProfileReloadDiscardLocalizations.fragment.json',
                                  'Resources/ProjectDraftNodeOverview.xcstrings',
                                  'Tests/AppUnitTests/ProfileReloadDiscardTests.swift',
                                  'Tests/AppUnitTests/ProjectDraftNodeOverviewTests.swift',
                                  'Tests/AppUnitTests/RoamHistoryLiveEntryTests.swift',
                                  'Tests/AppUnitTests/TicketWalletPlayEntryTests.swift',
                                  'Tests/ContractChecks/test_profile_reload_discard.py',
                                  'Tests/ContractChecks/test_roam_history_live_entry.py',
                                  'Tests/ContractChecks/test_ticket_wallet_play_entry.py',
                                  'Tests/CoreTests/ProjectDraftNodeProjectionTests.swift',
                                  'App/ExploreCompletionView.swift',
                                  'App/MerchantNPCRecoveryPresentation.swift',
                                  'App/SocialGuideTemplateSection.swift',
                                  'Core/ExploreCompletionContracts.swift',
                                  'Core/ExploreCompletionRead.swift',
                                  'Resources/ExploreCompletionLocalizations.fragment.json',
                                  'Resources/MerchantNPCRecoveryLocalizations.fragment.json',
                                  'Resources/ProjectNodeBusinessHours.xcstrings',
                                  'Resources/SocialGuideTemplateLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantNPCRecoveryPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeBusinessHoursViewTests.swift',
                                  'Tests/AppUnitTests/SocialGuideTemplateTests.swift',
                                  'Tests/ContractChecks/test_explore_completion_read.py',
                                  'Tests/ContractChecks/test_merchant_npc_recovery.py',
                                  'Tests/ContractChecks/test_social_guide_templates.py',
                                  'Tests/CoreTests/ExploreCompletionReadTests.swift',
                                  'Tests/CoreTests/ProjectNodeBusinessHoursTests.swift',
                                  'App/ProfileAvatarDraftSection.swift',
                                  'App/ProjectStoryTextField.swift',
                                  'App/ProjectStoryTextInsertionButton.swift',
                                  'Core/ProfileAvatarFlow.swift',
                                  'Core/ProfileAvatarJournal.swift',
                                  'Core/ProfileAvatarUpload.swift',
                                  'Core/ProjectEmptyStoryTextRemoval.swift',
                                  'Core/ProjectStoryTextInsertion.swift',
                                  'Resources/ProfileAvatarLocalizations.fragment.json',
                                  'Resources/ProjectStoryTextField.xcstrings',
                                  'Resources/ProjectStoryTextInsertion.xcstrings',
                                  'Tests/AppUnitTests/ProfileAvatarPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryTextFieldTests.swift',
                                  'Tests/AppUnitTests/ProjectStoryTextInsertionButtonTests.swift',
                                  'Tests/ContractChecks/test_profile_avatar.py',
                                  'Tests/ContractChecks/test_ticket_wallet_read_lifetime.py',
                                  'Tests/CoreTests/ProfileAvatarTests.swift',
                                  'Tests/CoreTests/ProjectEmptyStoryTextRemovalTests.swift',
                                  'Tests/CoreTests/ProjectStoryTextInsertionTests.swift',
                                  'Tests/CoreTests/TicketWalletTests.swift',
                                  'App/TicketWalletTeamView.swift',
                                  'Core/ProjectChapterRecruitmentCarryOver.swift',
                                  'Resources/TicketWalletTeamLocalizations.fragment.json',
                                  'Tests/AppUnitTests/TicketWalletTeamTests.swift',
                                  'Tests/ContractChecks/test_ticket_wallet_team.py',
                                  'Tests/CoreTests/ProjectEditTests.swift',
                                  'App/MerchantStationSubmissionImportView.swift',
                                  'Core/MerchantStationSubmissionCode.swift',
                                  'Resources/MerchantStationSubmissionImportLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantStationSubmissionImportTests.swift',
                                  'Tests/ContractChecks/test_merchant_station_submission_import.py',
                                  'Tests/CoreTests/MerchantStationSubmissionCodeTests.swift',
                                  'App/ProjectAlbumImageAuthorField.swift',
                                  'Resources/ProjectAlbumImageAuthor.xcstrings',
                                  'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift',
                                  'Tests/CoreTests/ProjectStoryImageTests.swift',
                                  'Core/ProjectAlbumPhotoOrder.swift',
                                  'Resources/ProjectAlbumPhotoOrder.xcstrings',
                                  'Tests/AppUnitTests/ProjectAlbumPhotoOrderPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_album_photo_order.py',
                                  'Tests/CoreTests/ProjectAlbumPhotoOrderTests.swift',
                                  'App/MerchantOperatorInvitationReceiptView.swift',
                                  'Core/MerchantOperatorInvitationPresentation.swift',
                                  'Resources/MerchantOperatorInvitationReceiptLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantOperatorInvitationReceiptTests.swift',
                                  'Tests/ContractChecks/test_merchant_operator_invitation_receipt.py',
                                  'Tests/CoreTests/MerchantOperatorInvitationPresentationTests.swift',
                                  'App/ProjectInitialAttributesEditor.swift',
                                  'App/ProjectNodeDurationField.swift',
                                  'Core/ProjectInitialAttributes.swift',
                                  'Core/ProjectNodeDuration.swift',
                                  'Resources/ProjectInitialAttributes.xcstrings',
                                  'Resources/ProjectNodeDuration.xcstrings',
                                  'Tests/AppUnitTests/ProjectInitialAttributesPresentationTests.swift',
                                  'Tests/AppUnitTests/ProjectNodeDurationPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_initial_attributes.py',
                                  'Tests/ContractChecks/test_project_node_duration.py',
                                  'Tests/CoreTests/ProjectInitialAttributesTests.swift',
                                  'Tests/CoreTests/ProjectNodeDurationTests.swift',
                                  'Tests/ContractChecks/test_project_node_business_hours_clear.py',
                                  'App/ProjectRichStoryInsertionButton.swift',
                                  'Core/ProjectRichStoryInsertion.swift',
                                  'Resources/ProjectRichStoryInsertion.xcstrings',
                                  'Tests/AppUnitTests/ProjectRichStoryInsertionPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_rich_story_insertion.py',
                                  'Tests/CoreTests/ProjectRichStoryInsertionTests.swift',
                                  'App/MerchantReviewPhotoGallery.swift',
                                  'Resources/MerchantReviewPhotoGalleryLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantReviewPhotoGalleryTests.swift',
                                  'Tests/ContractChecks/test_merchant_review_photo_gallery.py',
                                  'App/ProjectAlbumPhotoRemovalButton.swift',
                                  'Core/ProjectAlbumPhotoRemoval.swift',
                                  'Resources/ProjectAlbumPhotoRemoval.xcstrings',
                                  'Tests/AppUnitTests/ProjectAlbumPhotoRemovalPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_album_photo_removal.py',
                                  'Tests/CoreTests/ProjectAlbumPhotoRemovalTests.swift',
                                  'App/ProjectDraftStoryPreviewView.swift',
                                  'Core/ProjectDraftStoryPreview.swift',
                                  'Resources/ProjectDraftStoryPreview.xcstrings',
                                  'Tests/AppUnitTests/ProjectDraftStoryPreviewPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_draft_story_preview.py',
                                  'Tests/CoreTests/ProjectDraftStoryPreviewTests.swift',
                                  'App/ProjectTeamConfigurationEditor.swift',
                                  'Core/ProjectTeamConfiguration.swift',
                                  'Resources/ProjectTeamConfiguration.xcstrings',
                                  'Tests/AppUnitTests/ProjectTeamConfigurationPresentationTests.swift',
                                  'Tests/ContractChecks/test_project_team_configuration.py',
                                  'Tests/CoreTests/ProjectTeamConfigurationTests.swift',
                                  'App/ProjectNodeImageAuthorView.swift',
                                  'App/ProjectNodeImageCompositionRoute.swift',
                                  'App/ProjectNodeImageCrop.swift',
                                  'App/ProjectNodeImagePresentation.swift',
                                  'Core/ProjectNodeImageFlow.swift',
                                  'Core/ProjectNodeImageJournal.swift',
                                  'Core/ProjectNodeImageTarget.swift',
                                  'Core/ProjectNodeImageUpload.swift',
                                  'Resources/ProjectNodeImageAuthor.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodeImageAuthorTests.swift',
                                  'Tests/CoreTests/ProjectNodeImageTests.swift',
                                  'Core/ProjectTopicBudgetCarryOver.swift',
                                  'Resources/MerchantProjectWorkspaceLocalizations.fragment.json',
                                  'Tests/AppUnitTests/MerchantProjectWorkspaceEntryTests.swift',
                                  'Tests/ContractChecks/test_merchant_project_workspace_entry.py',
                                  'Tests/ContractChecks/test_project_topic_budget_carryover.py',
                                  'Tests/CoreTests/MerchantProjectWorkspaceScopeTests.swift',
                                  'Tests/CoreTests/ProjectTopicBudgetCarryOverTests.swift',
                                  'App/MerchantReviewDraftReturn.swift',
                                  'App/ProjectCityStoryNodeRemovalController.swift',
                                  'Core/ProjectCityStoryNodeRemoval.swift',
                                  'Resources/MerchantReviewDraftReturnLocalizations.fragment.json',
                                  'Resources/ProjectCityStoryNodeRemoval.xcstrings',
                                  'Tests/AppUnitTests/MerchantReviewDraftReturnTests.swift',
                                  'Tests/AppUnitTests/ProjectCityStoryNodeRemovalPresentationTests.swift',
                                  'Tests/ContractChecks/test_merchant_review_draft_return.py',
                                  'Tests/ContractChecks/test_project_city_story_node_removal.py',
                                  'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift',
                                  'App/ProjectNodePlacePicker.swift',
                                  'App/ProjectPendingNodePlacePicker.swift',
                                  'Core/ProjectNodePlaceSelection.swift',
                                  'Resources/ProjectNodePlacePicker.xcstrings',
                                  'Tests/AppUnitTests/ProjectNodePlacePickerTests.swift',
                                  'Tests/AppUnitTests/ProjectPendingNodePlacePickerTests.swift',
                                  'Tests/ContractChecks/test_project_node_place_picker.py',
                                  'Tests/ContractChecks/test_project_pending_node_place_picker.py',
                                  'Tests/CoreTests/ProjectNodePlaceSelectionTests.swift',
                                  'Tests/CoreTests/SearchMapCityNodeReadTests.swift',
                                  'Tests/ContractChecks/test_global_search_category_recovery.py',
                                  'Tests/CoreTests/GlobalSearchCategoryRecoveryTests.swift',
                                  'Tests/CoreTests/SearchMapCategoryRecoveryTests.swift',
                                  'docs/global-search-category-recovery.md',
                                  'tools/tests/test_gitleaks_configuration.py',
                                  'Tests/CoreTests/RoamRouteReplayTests.swift',
                                  'Tests/ContractChecks/test_roam_route_replay.py',
                                  'docs/roam-route-replay.md',
                                  'Tests/ContractChecks/test_category_roam_registration.py']}
R2_CONTRACT_SHA256 = '41083c4118f8b581b96084fc74026a345e161b816556407a289f65f2d4fac76b'
CATEGORY_SCANNER_BYTES = ('"""Offline configuration guards; the real full-history scanner runs in CI."""\n'
 'from pathlib import Path\n'
 'import re\n'
 'import json\n'
 'import hashlib\n'
 'import unittest\n'
 'from Tests.ContractChecks.test_global_search_category_recovery import historical_category_contract_bytes\n'
 '\n'
 '\n'
 'ROOT = Path(__file__).resolve().parents[2]\n'
 'MAIN_MERGE_COMMIT = "4e7349186d21448354d3bf4c6b4ab6adfc25fc1f"\n'
 'MAIN_MERGE_RECORDS = json.loads((ROOT / '
 '"tools/tests/fixtures/gitleaks-main-merge-audit-2026-10-05.json").read_text())["findings"]\n'
 'MAIN_MERGE_FINDINGS = {f"{r[\'commit\']}:{r[\'path\']}:{r[\'rule\']}:{r[\'line\']}" for r in MAIN_MERGE_RECORDS}\n'
 'IMPORT_COMMIT = "e39c367a35e1f15f9553701cbad56d0d10796c80"\n'
 'COVERAGE_PROSE_FINDING = '
 '"bcd754bd41dd41b3dad22a436211cd89ee47b657:docs/public-template/composition-read-grant.md:generic-api-key:75"\n'
 'CI132_PROSE_FINDING = "c95737b4c54881a7492ca72bd31f68749304d1d1:docs/square-post-local-media.md:generic-api-key:31"\n'
 'FILE_DIGEST_COMMIT = "65023b84211895bf6c3f6d8ec64804edbfc45e4d"\n'
 'FILE_DIGEST_PATH = "tools/run138_editor_readiness_contract.json"\n'
 'FILE_DIGEST_RECORDS = (\n'
 '    (174, "current_ui_sources", "WeChatAppAuthFlowTests.swift",\n'
 '     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",\n'
 '     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),\n'
 '    (243, "previous_ui_sources", "WeChatAppAuthFlowTests.swift",\n'
 '     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",\n'
 '     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),\n'
 '    (4028, "feature_batch_support_sha256", "Tests/ContractChecks/test_merchant_business_access_lifetime.py",\n'
 '     "Tests/ContractChecks/test_merchant_business_access_lifetime.py",\n'
 '     "a808e190bda202c021e4cbada812e684d92e4e7ac6848d2016c944c3d3d494e4"),\n'
 ')\n'
 'FILE_DIGEST_FINDINGS = {\n'
 '    f"{FILE_DIGEST_COMMIT}:{FILE_DIGEST_PATH}:generic-api-key:{row[0]}"\n'
 '    for row in FILE_DIGEST_RECORDS\n'
 '}\n'
 '\n'
 'COUPON_FIXTURE_FINDINGS = {\n'
 '    f"abe535809517ceb327223679f85c14b5f5b8b6d7:App/CouponRuntimeFixture.swift:generic-api-key:{line}"\n'
 '    for line in (55, 81, 110)\n'
 '}\n'
 '\n'
 '\n'
 'class GitleaksConfigurationTests(unittest.TestCase):\n'
 '    def test_reviewed_ignores_are_commit_bound(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual(len(entries), 92)\n'
 '        self.assertEqual(len(set(entries)), 92)\n'
 '        self.assertEqual(entries.count(COVERAGE_PROSE_FINDING), 1)\n'
 '        self.assertEqual(entries.count(CI132_PROSE_FINDING), 1)\n'
 '        legacy = [entry for entry in entries if entry not in (COVERAGE_PROSE_FINDING, CI132_PROSE_FINDING) and entry '
 'not in COUPON_FIXTURE_FINDINGS and entry not in MAIN_MERGE_FINDINGS and entry not in FILE_DIGEST_FINDINGS]\n'
 '        self.assertEqual(len(legacy), 42)\n'
 '        for entry in legacy:\n'
 '            with self.subTest(entry=entry):\n'
 '                self.assertRegex(entry, rf"^{IMPORT_COMMIT}:[^:*?\\[\\]]+:generic-api-key:[1-9][0-9]*$")\n'
 '                commit, path, rule, line = entry.split(":")\n'
 '                self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '                self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '\n'
 '    def test_main_merge_exceptions_bind_exact_source_lines_and_do_not_cover_new_history(self):\n'
 '        entries = {line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")}\n'
 '        self.assertEqual(len(MAIN_MERGE_FINDINGS), 42)\n'
 '        self.assertTrue(MAIN_MERGE_FINDINGS.issubset(entries))\n'
 '        self.assertEqual({r["classification"] for r in MAIN_MERGE_RECORDS},\n'
 '                         {"external_source_sha256_provenance", "native_source_sha256", '
 '"forbidden_mutation_route_assertion_literal"})\n'
 '        for row in MAIN_MERGE_RECORDS:\n'
 '            with self.subTest(path=row["path"], line=row["line"]):\n'
 '                self.assertEqual(row["commit"], MAIN_MERGE_COMMIT)\n'
 '                self.assertEqual(row["rule"], "generic-api-key")\n'
 '                line = (ROOT / row["path"]).read_text().splitlines()[row["line"] - 1]\n'
 '                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), row["source_line_sha256"])\n'
 '                suffix = f"{row[\'path\']}:{row[\'rule\']}:{row[\'line\']}"\n'
 '                self.assertNotIn(suffix, entries)\n'
 '                self.assertNotIn("0" * 40 + ":" + suffix, entries)\n'
 '                unlisted_line = max(r["line"] for r in MAIN_MERGE_RECORDS if r["path"] == row["path"]) + 1\n'
 '                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row[\'path\']}:{row[\'rule\']}:{unlisted_line}", entries)\n'
 '                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row[\'path\']}:other-rule:{row[\'line\']}", entries)\n'
 '        self.assertFalse(any(entry.startswith("6757dfac63086ac80bc849df587895bcaaa820df:") for entry in entries))\n'
 '\n'
 '    def test_file_digest_findings_recompute_from_exact_native_source_bytes(self):\n'
 '        raw = historical_category_contract_bytes((ROOT / FILE_DIGEST_PATH).read_bytes(), root=ROOT).decode()\n'
 '        contract = json.loads(raw)\n'
 '        for number, section, key, source, line_digest in FILE_DIGEST_RECORDS:\n'
 '            with self.subTest(line=number):\n'
 '                line = raw.splitlines()[number - 1]\n'
 '                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), line_digest)\n'
 '                expected = hashlib.sha256((ROOT / source).read_bytes()).hexdigest()\n'
 '                self.assertEqual(contract[section][key], expected)\n'
 '                # Bind the actual finding line to the reviewed JSON field, not just a matching value elsewhere.\n'
 '                self.assertEqual(json.loads("{" + line.strip().rstrip(",") + "}"), {key: expected})\n'
 '\n'
 '    def test_file_digest_exceptions_cannot_ignore_new_commits_paths_rules_or_lines(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual({entry for entry in entries if FILE_DIGEST_PATH in entry}, FILE_DIGEST_FINDINGS)\n'
 '        self.assertEqual({entry for entry in entries if entry.startswith(FILE_DIGEST_COMMIT + ":")}, '
 'FILE_DIGEST_FINDINGS)\n'
 '        for finding in FILE_DIGEST_FINDINGS:\n'
 '            self.assertEqual(entries.count(finding), 1)\n'
 '            commit, path, rule, line = finding.split(":")\n'
 '            for other in (f"{path}:{rule}:{line}",\n'
 '                          f"{\'0\' * 40}:{path}:{rule}:{line}",\n'
 '                          f"{commit}:tools/other.json:{rule}:{line}",\n'
 '                          f"{commit}:{path}:other-rule:{line}",\n'
 '                          f"{commit}:{path}:{rule}:{int(line) - 1}",\n'
 '                          f"{commit}:{path}:{rule}:{int(line) + 1}"):\n'
 '                with self.subTest(other=other):\n'
 '                    self.assertNotIn(other, entries)\n'
 '        self.assertFalse((ROOT / ".gitleaks.toml").exists())\n'
 '\n'
 '    def test_new_prose_exception_is_exact_and_new_text_is_not_ignored(self):\n'
 '        commit, path, rule, line = COVERAGE_PROSE_FINDING.split(":")\n'
 '        self.assertEqual(commit, "bcd754bd41dd41b3dad22a436211cd89ee47b657")\n'
 '        self.assertEqual(path, "docs/public-template/composition-read-grant.md")\n'
 '        self.assertEqual((rule, line), ("generic-api-key", "75"))\n'
 '        entries = (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '        self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '        self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '        self.assertIn("viewers, absent grants", (ROOT / path).read_text())\n'
 '\n'
 '    def test_ci132_prose_exception_cannot_ignore_other_commits_paths_rules_or_lines(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        commit, path, rule, line = CI132_PROSE_FINDING.split(":")\n'
 '        self.assertEqual(commit, "c95737b4c54881a7492ca72bd31f68749304d1d1")\n'
 '        self.assertEqual(path, "docs/square-post-local-media.md")\n'
 '        self.assertEqual((rule, line), ("generic-api-key", "31"))\n'
 '        self.assertEqual([entry for entry in entries if path in entry], [CI132_PROSE_FINDING])\n'
 '        for other in (f"{path}:{rule}:{line}",\n'
 '                      f"{\'0\' * 40}:{path}:{rule}:{line}",\n'
 '                      f"{commit}:docs/other.md:{rule}:{line}",\n'
 '                      f"{commit}:{path}:other-rule:{line}",\n'
 '                      f"{commit}:{path}:{rule}:30",\n'
 '                      f"{commit}:{path}:{rule}:32"):\n'
 '            with self.subTest(other=other):\n'
 '                self.assertNotIn(other, entries)\n'
 '        for entry in entries:\n'
 '            self.assertRegex(entry, r"^[0-9a-f]{40}:[^:*?\\[\\]]+:generic-api-key:[1-9][0-9]*$")\n'
 '        current_line = (ROOT / path).read_text().splitlines()[int(line) - 1]\n'
 '        self.assertIn("Backend ownership checks and moderation remain prerequisites.", current_line)\n'
 '        self.assertIn("Readback must remain authenticated.", current_line)\n'
 '        self.assertIn("Expired or revoked approvals and interrupted uploads require explicit recovery handling.", '
 'current_line)\n'
 '\n'
 '    def test_coupon_fixture_exceptions_are_exact_historical_findings_only(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual({entry for entry in entries if "CouponRuntimeFixture" in entry}, COUPON_FIXTURE_FINDINGS)\n'
 '        for finding in COUPON_FIXTURE_FINDINGS:\n'
 '            self.assertEqual(entries.count(finding), 1)\n'
 '            commit, path, rule, line = finding.split(":")\n'
 '            self.assertEqual(commit, "abe535809517ceb327223679f85c14b5f5b8b6d7")\n'
 '            self.assertEqual(path, "App/CouponRuntimeFixture.swift")\n'
 '            self.assertEqual(rule, "generic-api-key")\n'
 '            self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '            self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '        fixture = (ROOT / "App/CouponRuntimeFixture.swift").read_text()\n'
 '        self.assertTrue(fixture.startswith("#if DEBUG"))\n'
 '        self.assertEqual(fixture.count(\'"test-7"\'), 3)\n'
 "        self.assertIn('https://coupon-runtime.example/native', fixture)\n"
 "        self.assertIn('makeTransport: { self }', fixture)\n"
 "        self.assertNotIn('URLSession', fixture)\n"
 '        self.assertFalse((ROOT / ".gitleaks.toml").exists())\n'
 '\n'
 '    def test_scan_stays_read_only_and_pinned(self):\n'
 '        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()\n'
 '        job = workflow.split("  secrets:\\n", 1)[1].split("  app-unit-tests:\\n", 1)[0]\n'
 '        self.assertIn("permissions:\\n  contents: read\\n", workflow)\n'
 '        self.assertIn("fetch-depth: 0", job)\n'
 '        self.assertIn("persist-credentials: false", job)\n'
 '        self.assertIn("gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e", job)\n'
 '        for key, value in [("GITLEAKS_VERSION", "8.24.3"),\n'
 '                           ("GITLEAKS_ENABLE_COMMENTS", "false"),\n'
 '                           ("GITLEAKS_ENABLE_UPLOAD_ARTIFACT", "false")]:\n'
 '            self.assertIn(f"{key}: \'{value}\'", job)\n'
 '        self.assertNotIn("continue-on-error", job)\n'
 '\n'
 '    def test_full_history_step_reuses_binary_and_fails_closed(self):\n'
 '        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()\n'
 '        step = workflow.split("      - name: Scan full checked-out branch history\\n", 1)[1]\n'
 '        step = step.split("  app-unit-tests:\\n", 1)[0]\n'
 '        self.assertIn("shell: bash", step)\n'
 '        self.assertIn("set -euo pipefail", step)\n'
 '        self.assertIn("command -v gitleaks >/dev/null", step)\n'
 '        self.assertIn("test \\"$(gitleaks version)\\" = \'8.24.3\'", step)\n'
 '        self.assertIn(\'gitleaks git --redact --exit-code=2 --log-opts="--full-history -m HEAD"\', step)\n'
 '        commands = "\\n".join(line for line in step.splitlines() if not line.lstrip().startswith("#"))\n'
 '        self.assertNotRegex(commands, r"--all|--first-parent|--no-merges|curl|wget|\\|\\|\\s*true")\n'
 '\n'
 '\n'
 'if __name__ == "__main__":\n'
 '    unittest.main()\n')
PROFILE_CONTEXT_INPUTS = ('App/ClubGovernanceViews.swift',
 'App/MerchantBusinessEditor.swift',
 'App/MerchantOperationsEditor.swift',
 'App/ProjectNodeImageCrop.swift',
 'App/TemplateAuthoringMineView.swift',
 'Core/ClubCustomerHistoryTopicRoute.swift',
 'Core/ClubGovernanceContracts.swift',
 'Core/ProfileEditCoordinator.swift',
 'Core/TemplateAuthoringShelf.swift',
 'Questify.xcodeproj/project.pbxproj',
 'Resources/Localizable.xcstrings',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift',
 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py',
 'Tests/ContractChecks/test_club_customer_permissions.py',
 'Tests/ContractChecks/test_merchant_decor_tag_picker.py',
 'Tests/ContractChecks/test_merchant_review_draft_return.py',
 'Tests/ContractChecks/test_profile_avatar.py',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'Tests/ContractChecks/test_profile_reload_discard.py',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py',
 'Tests/ContractChecks/test_template_shelf_state_projection.py',
 'Tests/CoreTests/ClubCustomerPermissionTests.swift',
 'Tests/CoreTests/ClubGovernanceProductionTests.swift',
 'Tests/CoreTests/MerchantDecorTagDraftTests.swift',
 'Tests/CoreTests/ProfileEditTests.swift',
 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift',
 'docs/club-customer-keyword-debounce.md',
 'docs/club-customer-permissions.md',
 'docs/merchant-decor-tag-picker/implementation.md',
 'docs/profile-read-failure-recovery.md',
 'tools/check_profile_read_failure_contract.py',
 'tools/club_customer_directory_admission.py',
 'tools/run138_editor_readiness.py',
 'tools/run138_editor_readiness_contract.json',
 'tools/run_static_checks.py',
 'tools/tests/creator_shelf_refresh_history.py',
 'tools/tests/creator_shelf_state_history.py',
 'tools/tests/test_creator_pending_synthetic_storage_history.py',
 'tools/tests/test_creator_shelf_refresh_history.py',
 'tools/tests/test_creator_shelf_state_history.py',
 'tools/tests/test_gitleaks_configuration.py',
 'tools/tests/test_native_static_checks.py')
PARENT_INPUT_SHA256 = {'Tests/CoreTests/ClubGovernanceProductionTests.swift': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift': '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673',
 'Tests/CoreTests/ProfileEditTests.swift': '6319234ba77c43afec858692bc9ff00308be774b58ea585069a7b3dc90ce654c',
 'App/ProjectNodeImageCrop.swift': '47901a84bfc8ffa2f69dca618ab4de6eb7a151f7cc20fdebd4cb79425bcdb894',
 'Tests/CoreTests/ClubCustomerPermissionTests.swift': 'b4451e3ab27422f568b31c114f2c0cfc30335c24115c36f117b1f64579271590',
 'tools/check_profile_read_failure_contract.py': 'e492facdded0e76615721d90081b912738ba490e503aab61a7ed549a6b2a4b8a',
 'Tests/ContractChecks/test_template_shelf_state_projection.py': '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
 'docs/club-customer-permissions.md': 'f32d0102eeb5bb2bc696b139389a5e674140623f7597973ffce5468629cd1f10',
 'tools/tests/creator_shelf_refresh_history.py': '55632e1d0235628b55478a6b50a5e5d369bf2c54d73f4d09ec33becf84b6d7e5',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': 'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87',
 'tools/tests/test_creator_shelf_refresh_history.py': '26b98d87f9c465dd2e6cefbc31734e5925c13a86003a9e695a09f4b83ad36061',
 'docs/merchant-decor-tag-picker/implementation.md': '1d320a30163c369a222815a565bb1bc8ab4675b7905de465a205e50a95297539',
 'tools/tests/test_creator_pending_synthetic_storage_history.py': '8d4b8e0bf04a7ce28622b416956af3628348bf3f86d5af5630fe04bb07e7e739',
 'Tests/ContractChecks/test_profile_reload_discard.py': '044ef04942dd76592917397f686cbe6c7d50bd199ceb0776806af965da78fada',
 'App/TemplateAuthoringMineView.swift': '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py': '262ed2f2d1151dbe6994048cc21e76b98799fc34a68caeba59c08947508c8e6c',
 'App/MerchantOperationsEditor.swift': '3656f645fdac72a57fc05caeafc71a61bdcb1728d7c5da0196ce7d0fa184fbbe',
 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift': 'bad6293bda4a08e10687686625969954a6b906f9b8c618c8462579840d343a3c',
 'tools/club_customer_directory_admission.py': '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297',
 'Core/TemplateAuthoringShelf.swift': 'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a',
 'Core/ClubGovernanceContracts.swift': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32',
 'Tests/ContractChecks/test_club_customer_permissions.py': '773186689d0583d41d6ab75298e4b815e86dc688a2ce5043cdba43d0a5b2ffba',
 'Questify.xcodeproj/project.pbxproj': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50',
 'tools/run_static_checks.py': 'a681d224bfbef5372678a11625fa6330da097b470592e0572c1afd88f77a0210',
 'Tests/ContractChecks/test_merchant_review_draft_return.py': 'e5b7c6ce7d66037ed49dba6b32b59fcf213c57e24b6f8694285e7d612575d777',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift': '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift': '2c3cfc1da3d145221e13d9561c1bfb9166b58c84807bfd93034fcaff44b303a5',
 'docs/profile-read-failure-recovery.md': 'b9ec88b1988042cd4d28a39e4640e6980fc1d02d2a7f248ab564a05e25b372fa',
 'Core/ClubCustomerHistoryTopicRoute.swift': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2',
 'tools/tests/creator_shelf_state_history.py': '63d498f92184bfdf2349849c683347adc5766e73878cc1f5e86790b68799d2e3',
 'App/ClubGovernanceViews.swift': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff',
 'Tests/CoreTests/MerchantDecorTagDraftTests.swift': '407e2da4496c3d3a81a1017a84220a41636631c3dfa6867805d510412e0cc3af',
 'tools/tests/test_gitleaks_configuration.py': 'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py': 'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8',
 'docs/club-customer-keyword-debounce.md': '1fa12a8011cb1b2c3d7425dcd8f1f8ca07f27be08adb8a545c1be98f97806f0e',
 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift': '8f6e488cbdb80d6c62ebd1aa62c280aadbd9c2b9e69b0f62dd17c1ad435a703e',
 'tools/tests/test_creator_shelf_state_history.py': 'baa95d45430a19f2a7c472dcd269150197617f45d50735aa84b142ca2973d33c',
 'Core/ProfileEditCoordinator.swift': 'bbd462eed41321ab249fda4e2f80e48aad51942cc6ce195bbd45b7e52b1e1b67',
 'Tests/ContractChecks/test_merchant_decor_tag_picker.py': 'ce4a480162243e0e8b497fcc13fe6e08c8d28f00c3574e956f4ae4c6260ff1b5',
 'tools/tests/test_native_static_checks.py': 'b471892d1834b973424f1d74d4e00fb12fe37a8df8689f063441813d265eee3a',
 'Tests/ContractChecks/test_profile_avatar.py': '031747f2374ef01e935753b51be7859c75f3f5861a83037cd935089ed006a1db',
 'App/MerchantBusinessEditor.swift': '13ff93a1d1608d0fc10cbbb1e2aa31b6f7b5496ea37553e052d147ab6611aff0'}
PROTECTED_PBX_ROW = {'before_sha256': 'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552',
 'after_sha256': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50',
 'hunks': [{'before': '\t\t\t\t"71A7505267803344467EE759",\n'
                      '\t\t\t\t"6AAF4C68E4CB945E5E18944C",\n'
                      '\t\t\t\t"4A57125287F6AEF51C738309",\n'
                      '\t\t\t\t"791E6BF02CD332B0299A3459",\n'
                      '\t\t\t\t"783FC56096E91597FD59C9D5",\n'
                      '\t\t\t\t"8E1251348B29DBD73A8A5393",\n',
            'after': '\t\t\t\t"71A7505267803344467EE759",\n'
                     '\t\t\t\t"6AAF4C68E4CB945E5E18944C",\n'
                     '\t\t\t\t"4A57125287F6AEF51C738309",\n'
                     '\t\t\t\t"2A4F7E878F7689C47FE34583",\n'
                     '\t\t\t\t"791E6BF02CD332B0299A3459",\n'
                     '\t\t\t\t"783FC56096E91597FD59C9D5",\n'
                     '\t\t\t\t"8E1251348B29DBD73A8A5393",\n'},
           {'before': '\t\t\t"path" = "Config/AppUnitTests.xcconfig";\n'
                      '\t\t\t"sourceTree" = "<group>";\n'
                      '\t\t};\n'
                      '\t\t"791E6BF02CD332B0299A3459" = {\n'
                      '\t\t\t"isa" = "PBXFileReference";\n'
                      '\t\t\t"lastKnownFileType" = "sourcecode.swift";\n',
            'after': '\t\t\t"path" = "Config/AppUnitTests.xcconfig";\n'
                     '\t\t\t"sourceTree" = "<group>";\n'
                     '\t\t};\n'
                     '\t\t"2A4F7E878F7689C47FE34583" = {\n'
                     '\t\t\t"isa" = "PBXFileReference";\n'
                     '\t\t\t"lastKnownFileType" = "sourcecode.swift";\n'
                     '\t\t\t"path" = "Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift";\n'
                     '\t\t\t"sourceTree" = "<group>";\n'
                     '\t\t};\n'
                     '\t\t"4FF7D0B5D5B04E3FAAE97D5A" = {\n'
                     '\t\t\t"isa" = "PBXBuildFile";\n'
                     '\t\t\t"fileRef" = "2A4F7E878F7689C47FE34583";\n'
                     '\t\t};\n'
                     '\t\t"791E6BF02CD332B0299A3459" = {\n'
                     '\t\t\t"isa" = "PBXFileReference";\n'
                     '\t\t\t"lastKnownFileType" = "sourcecode.swift";\n'},
           {'before': '\t\t\t"isa" = "PBXSourcesBuildPhase";\n'
                      '\t\t\t"buildActionMask" = 2147483647;\n'
                      '\t\t\t"files" = (\n'
                      '\t\t\t\t"19EC95F64576113ABFA6995C",\n'
                      '\t\t\t\t"347E85455BBF6CC9554E794C",\n'
                      '\t\t\t\t"A11ED0B2DB9D772EBD8F9407",\n',
            'after': '\t\t\t"isa" = "PBXSourcesBuildPhase";\n'
                     '\t\t\t"buildActionMask" = 2147483647;\n'
                     '\t\t\t"files" = (\n'
                     '\t\t\t\t"4FF7D0B5D5B04E3FAAE97D5A",\n'
                     '\t\t\t\t"19EC95F64576113ABFA6995C",\n'
                     '\t\t\t\t"347E85455BBF6CC9554E794C",\n'
                     '\t\t\t\t"A11ED0B2DB9D772EBD8F9407",\n'}]}
PROTECTED_PBX_SHA256 = 'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552'
PROFILE_CONTRACT_FLOORS = {'combined': ('3902a64b0aaaf37362fe251bb3b6b1a2f1da824ba721cb0af2c3bf4ef1006bfd',),
 'history': ('3902a64b0aaaf37362fe251bb3b6b1a2f1da824ba721cb0af2c3bf4ef1006bfd',
             '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'),
 'club': ('3902a64b0aaaf37362fe251bb3b6b1a2f1da824ba721cb0af2c3bf4ef1006bfd',),
 'merchant': ('3902a64b0aaaf37362fe251bb3b6b1a2f1da824ba721cb0af2c3bf4ef1006bfd',
              'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053'),
 'creator': ('427074d1dc2ffa0c530cec669a0d490934fa266de7067b28de2d4d5fc0506e4a',)}

def _inverse_exact(raw, row, label):
    require(digest(raw) == row['after_sha256'], 'Unknown complete current input: ' + label)
    value = raw
    for hunk in reversed(row['hunks']):
        after = hunk['after'].encode(); before = hunk['before'].encode()
        require(value.count(after) == 1, 'Missing/repeated exact input span: ' + label)
        value = value.replace(after, before, 1)
    require(digest(value) == row['before_sha256'], 'Complete predecessor not restored: ' + label)
    return value



# Exact parser/property repair layer on the complete published discovery predecessor.
REPAIR_PRE_CONTRACT_SHA256 = 'b72d9b1024daadb5273a4de24c0175d42c04516b1f89c6c53c0f9c40dd7a77b6'
REPAIR_PRE_RUNNER_SHA256 = 'f39364ce7df89dc337047e825294047fa0af2f461424cd9aa1e6384c0c389d4f'
REPAIR_PRE_PROFILE_SHA256 = 'f9904bbd44d23bcaacd02be0647cf6bc4d7f0d5994371a8f05f2edac868b59ec'
REPAIR_PRE_FINGERPRINT = '9151580209a925a141535c70e229ab1c0609d3cd0d7b8b544f16f16df2a543a9'
REPAIR_SOURCE_INVERSES = {'App/ProjectThoughtDefinitionsEditor.swift': {'before_sha256': 'dc2bcdecf846d8226db09d96df7ce7688cabc722249add64a114d48721263bd9',
                                               'after_sha256': 'e580e547bd55d7a0df2ef032fb39699aeb6187701cc604ab5d20be1129f91750',
                                               'hunks': [{'before': '        let id = UUID(), incarnation: '
                                                                    'UUID, session: ProjectEditSession?, '
                                                                    'identity: ProjectEditDraftIdentity?\n'
                                                                    '        let revision: Int, bytes: '
                                                                    'Data\n',
                                                          'after': '        let id = UUID()\n'
                                                                   '        let incarnation: UUID\n'
                                                                   '        let session: '
                                                                   'ProjectEditSession?\n'
                                                                   '        let identity: '
                                                                   'ProjectEditDraftIdentity?\n'
                                                                   '        let revision: Int\n'
                                                                   '        let bytes: Data\n'},
                                                         {'before': '        let id = UUID(), key: String, '
                                                                    'revision: Int, impacts: [String]\n',
                                                          'after': '        let id = UUID()\n'
                                                                   '        let key: String\n'
                                                                   '        let revision: Int\n'
                                                                   '        let impacts: [String]\n'}]},
 'App/ProjectEndingConditionPicker.swift': {'before_sha256': '1b0a460cc65ee4ba69be25390940f188bbeaddbd824ee4d77d053dfdb28ba5a8',
                                            'after_sha256': '16da43f7d88ae2aa153b622dfce15d91938d580a8ad0fdec61f51418d7827688',
                                            'hunks': [{'before': '@MainActor final class '
                                                                 'ProjectEndingConditionController: '
                                                                 'ObservableObject {\n'
                                                                 '    struct Presentation: Identifiable {\n'
                                                                 '        let id = UUID(), incarnation: '
                                                                 'UUID, session: ProjectEditSession?, '
                                                                 'identity: ProjectEditDraftIdentity?\n'
                                                                 '        let revision: Int, bytes: Data\n',
                                                       'after': '@MainActor final class '
                                                                'ProjectEndingConditionController: '
                                                                'ObservableObject {\n'
                                                                '    struct Presentation: Identifiable {\n'
                                                                '        let id = UUID()\n'
                                                                '        let incarnation: UUID\n'
                                                                '        let session: ProjectEditSession?\n'
                                                                '        let identity: '
                                                                'ProjectEditDraftIdentity?\n'
                                                                '        let revision: Int\n'
                                                                '        let bytes: Data\n'},
                                                      {'before': '@MainActor final class '
                                                                 'ProjectStoryConditionController: '
                                                                 'ObservableObject {\n'
                                                                 '    struct Presentation: Identifiable {\n'
                                                                 '        let id = UUID(), incarnation: '
                                                                 'UUID, session: ProjectEditSession?, '
                                                                 'identity: ProjectEditDraftIdentity?\n'
                                                                 '        let revision: Int, bytes: Data\n',
                                                       'after': '@MainActor final class '
                                                                'ProjectStoryConditionController: '
                                                                'ObservableObject {\n'
                                                                '    struct Presentation: Identifiable {\n'
                                                                '        let id = UUID()\n'
                                                                '        let incarnation: UUID\n'
                                                                '        let session: ProjectEditSession?\n'
                                                                '        let identity: '
                                                                'ProjectEditDraftIdentity?\n'
                                                                '        let revision: Int\n'
                                                                '        let bytes: Data\n'}]},
 'tools/club_customer_directory_admission.py': {'before_sha256': '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297',
                                                'after_sha256': '1878c5c48f1da07910178409ca0b927be695e92a462497dc8cd9aa7d9a929aaf',
                                                'hunks': [{'before': 'FLOOR_INPUTS = '
                                                                     "('App/MerchantBusinessEditor.swift',",
                                                           'after': 'FLOOR_INPUTS = '
                                                                    "('App/ProjectThoughtDefinitionsEditor.swift',\n"
                                                                    ' '
                                                                    "'App/ProjectEndingConditionPicker.swift',\n"
                                                                    " 'App/MerchantBusinessEditor.swift',"},
                                                          {'before': 'def '
                                                                     'current_predecessor_contract(contract, '
                                                                     'root):\n'
                                                                     '    """Full club raw admission -> '
                                                                     'exact complete creator floor; never a '
                                                                     'scanner view."""\n'
                                                                     '    root = Path(root)\n'
                                                                     '    if digest((root / '
                                                                     'HELPER_PATH).read_bytes()) != '
                                                                     'HELPER_SHA256:\n'
                                                                     "        raise ValueError('Current club "
                                                                     "reader changed')\n"
                                                                     '    prefix = (root / '
                                                                     "HELPER_PATH).read_bytes().split(b'\\n# "
                                                                     'Finite club layer on the exact '
                                                                     'creator/fixed45 floor. Frozen reader '
                                                                     "above retained.\\n', 1)[0]\n"
                                                                     '    if digest(prefix) != '
                                                                     'FROZEN16_HELPER_SHA256:\n'
                                                                     "        raise ValueError('Frozen club "
                                                                     "reader was not retained exactly')\n"
                                                                     '    permission_prefix = '
                                                                     "prefix.split(b'\\n# Exact keyword/PBX "
                                                                     'evolution. Original eleven-file reader '
                                                                     "above is retained byte-for-byte.\\n', "
                                                                     '1)[0]\n'
                                                                     '    if digest(permission_prefix) != '
                                                                     'FROZEN_PERMISSION_HELPER_SHA256:\n'
                                                                     "        raise ValueError('Frozen "
                                                                     'original club11 helper not retained '
                                                                     "exactly')\n"
                                                                     '    restore_creator_history_test((root '
                                                                     '/ CLUB_HISTORY_PATH).read_bytes())\n'
                                                                     '    support = '
                                                                     "contract['feature_batch_support_sha256']\n"
                                                                     '    if support.get(HELPER_PATH) != '
                                                                     'HELPER_SHA256:\n'
                                                                     "        raise ValueError('Current club "
                                                                     "helper support changed')\n"
                                                                     '    for name, expected in '
                                                                     'CLUB_RAW_SHA256.items():\n'
                                                                     '        if digest((root / '
                                                                     'name).read_bytes()) != expected:\n'
                                                                     "            raise ValueError('Changed "
                                                                     "or mixed club raw input: ' + name)\n"
                                                                     '        if name in support and '
                                                                     'support[name] != expected:\n'
                                                                     "            raise ValueError('Changed "
                                                                     "club support binding: ' + name)\n"
                                                                     '    if digest((root / '
                                                                     "'tools/tests/test_gitleaks_configuration.py').read_bytes()) "
                                                                     '!= CURRENT_SCANNER_SHA256:\n'
                                                                     "        raise ValueError('Current "
                                                                     "scanner changed')\n"
                                                                     '    for name, expected in '
                                                                     'CLUB_SOURCE_ROWS.items():\n'
                                                                     '        if '
                                                                     "contract['feature_batch_sources'].pop(name, "
                                                                     'None) != expected:\n'
                                                                     "            raise ValueError('Unknown "
                                                                     "club source inverse: ' + name)\n"
                                                                     '        _inverse_row(name, (root / '
                                                                     'name).read_bytes(), expected)\n'
                                                                     '    pbx = '
                                                                     "'Questify.xcodeproj/project.pbxproj'\n"
                                                                     '    row = '
                                                                     "contract['feature_batch_sources'][pbx]\n"
                                                                     '    extension = '
                                                                     'EVOLUTION_SOURCES[pbx]\n'
                                                                     "    if row['after_sha256'] != "
                                                                     "extension['after_sha256'] or "
                                                                     "row['hunks'][-len(extension['hunks']):] "
                                                                     "!= extension['hunks']:\n"
                                                                     "        raise ValueError('Unknown club "
                                                                     "PBX extension')\n"
                                                                     '    restore_evolution_source(pbx, '
                                                                     '(root / pbx).read_bytes())\n'
                                                                     '    del '
                                                                     "row['hunks'][-len(extension['hunks']):]\n"
                                                                     "    row['after_sha256'] = "
                                                                     "extension['before_sha256']\n"
                                                                     '    if digest(_encoded(row)) != '
                                                                     'CLUB_PBX_PRE_ROW_SHA256:\n'
                                                                     "        raise ValueError('Complete "
                                                                     "preceding PBX row not restored')\n"
                                                                     '    for name in CLUB_SUPPORT_PATHS:\n'
                                                                     '        if name not in support:\n'
                                                                     "            raise ValueError('Missing "
                                                                     "club support row: ' + name)\n"
                                                                     '        del support[name]\n'
                                                                     '    support[CLUB_PREADMISSION_PATH] = '
                                                                     'CLUB_PREADMISSION_SHA256\n'
                                                                     '    if digest(_encoded(contract)) != '
                                                                     'CLUB_PRECONTRACT_SHA256:\n'
                                                                     "        raise ValueError('Complete "
                                                                     "creator predecessor not restored')\n"
                                                                     '    return contract\n'
                                                                     '\n',
                                                           'after': 'def '
                                                                    'current_predecessor_contract(contract, '
                                                                    'root):\n'
                                                                    '    """Full club raw admission -> exact '
                                                                    'complete creator floor; never a scanner '
                                                                    'view."""\n'
                                                                    '    root = Path(root)\n'
                                                                    '    if digest((root / '
                                                                    'HELPER_PATH).read_bytes()) != '
                                                                    "'80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297':\n"
                                                                    "        raise ValueError('Current club "
                                                                    "reader changed')\n"
                                                                    '    prefix = (root / '
                                                                    "HELPER_PATH).read_bytes().split(b'\\n# "
                                                                    'Finite club layer on the exact '
                                                                    'creator/fixed45 floor. Frozen reader '
                                                                    "above retained.\\n', 1)[0]\n"
                                                                    '    if digest(prefix) != '
                                                                    'FROZEN16_HELPER_SHA256:\n'
                                                                    "        raise ValueError('Frozen club "
                                                                    "reader was not retained exactly')\n"
                                                                    '    permission_prefix = '
                                                                    "prefix.split(b'\\n# Exact keyword/PBX "
                                                                    'evolution. Original eleven-file reader '
                                                                    "above is retained byte-for-byte.\\n', "
                                                                    '1)[0]\n'
                                                                    '    if digest(permission_prefix) != '
                                                                    'FROZEN_PERMISSION_HELPER_SHA256:\n'
                                                                    "        raise ValueError('Frozen "
                                                                    'original club11 helper not retained '
                                                                    "exactly')\n"
                                                                    '    restore_creator_history_test((root '
                                                                    '/ CLUB_HISTORY_PATH).read_bytes())\n'
                                                                    '    support = '
                                                                    "contract['feature_batch_support_sha256']\n"
                                                                    '    if support.get(HELPER_PATH) != '
                                                                    "'80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297':\n"
                                                                    "        raise ValueError('Current club "
                                                                    "helper support changed')\n"
                                                                    '    for name, expected in '
                                                                    'CLUB_RAW_SHA256.items():\n'
                                                                    '        if digest((root / '
                                                                    'name).read_bytes()) != expected:\n'
                                                                    "            raise ValueError('Changed "
                                                                    "or mixed club raw input: ' + name)\n"
                                                                    '        if name in support and '
                                                                    'support[name] != expected:\n'
                                                                    "            raise ValueError('Changed "
                                                                    "club support binding: ' + name)\n"
                                                                    '    if digest((root / '
                                                                    "'tools/tests/test_gitleaks_configuration.py').read_bytes()) "
                                                                    '!= CURRENT_SCANNER_SHA256:\n'
                                                                    "        raise ValueError('Current "
                                                                    "scanner changed')\n"
                                                                    '    for name, expected in '
                                                                    'CLUB_SOURCE_ROWS.items():\n'
                                                                    '        if '
                                                                    "contract['feature_batch_sources'].pop(name, "
                                                                    'None) != expected:\n'
                                                                    "            raise ValueError('Unknown "
                                                                    "club source inverse: ' + name)\n"
                                                                    '        _inverse_row(name, (root / '
                                                                    'name).read_bytes(), expected)\n'
                                                                    '    pbx = '
                                                                    "'Questify.xcodeproj/project.pbxproj'\n"
                                                                    '    row = '
                                                                    "contract['feature_batch_sources'][pbx]\n"
                                                                    '    extension = EVOLUTION_SOURCES[pbx]\n'
                                                                    "    if row['after_sha256'] != "
                                                                    "extension['after_sha256'] or "
                                                                    "row['hunks'][-len(extension['hunks']):] "
                                                                    "!= extension['hunks']:\n"
                                                                    "        raise ValueError('Unknown club "
                                                                    "PBX extension')\n"
                                                                    '    restore_evolution_source(pbx, (root '
                                                                    '/ pbx).read_bytes())\n'
                                                                    '    del '
                                                                    "row['hunks'][-len(extension['hunks']):]\n"
                                                                    "    row['after_sha256'] = "
                                                                    "extension['before_sha256']\n"
                                                                    '    if digest(_encoded(row)) != '
                                                                    'CLUB_PBX_PRE_ROW_SHA256:\n'
                                                                    "        raise ValueError('Complete "
                                                                    "preceding PBX row not restored')\n"
                                                                    '    for name in CLUB_SUPPORT_PATHS:\n'
                                                                    '        if name not in support:\n'
                                                                    "            raise ValueError('Missing "
                                                                    "club support row: ' + name)\n"
                                                                    '        del support[name]\n'
                                                                    '    support[CLUB_PREADMISSION_PATH] = '
                                                                    'CLUB_PREADMISSION_SHA256\n'
                                                                    '    if digest(_encoded(contract)) != '
                                                                    'CLUB_PRECONTRACT_SHA256:\n'
                                                                    "        raise ValueError('Complete "
                                                                    "creator predecessor not restored')\n"
                                                                    '    return contract\n'
                                                                    '\n'},
                                                          {'before': '    frozen_test = '
                                                                     '_inverse_row(FROZEN_TEST_PATH, '
                                                                     '(Path(root) / '
                                                                     'FROZEN_TEST_PATH).read_bytes(), '
                                                                     'FROZEN16_TEST_INVERSE)\n',
                                                           'after': '    from '
                                                                    'Tests.ContractChecks.test_category_roam_registration '
                                                                    'import repair_predecessor_source\n'
                                                                    '    current_test = '
                                                                    'repair_predecessor_source(FROZEN_TEST_PATH, '
                                                                    '(Path(root) / '
                                                                    'FROZEN_TEST_PATH).read_bytes())\n'
                                                                    '    frozen_test = '
                                                                    '_inverse_row(FROZEN_TEST_PATH, '
                                                                    'current_test, '
                                                                    'FROZEN16_TEST_INVERSE)\n'}]},
 'tools/tests/test_creator_shelf_state_history.py': {'before_sha256': 'accaa341cf2803a6847c19ee675d7bb9d06b831d300c1a56d9f17d9aeddfb65e',
                                                     'after_sha256': '2806301717bd6b0d1ff66462cb006e801853daa9a87ffdd9aa679c8deb6994bf',
                                                     'hunks': [{'before': '        '
                                                                          "script=(ROOT/'tools/run138_editor_readiness.py').read_bytes()\n"
                                                                          '        '
                                                                          'script=script.replace(digest(current_raw).encode(),digest(raw).encode(),1)\n',
                                                                'after': '        '
                                                                         "script=(ROOT/'tools/run138_editor_readiness.py').read_bytes()\n"
                                                                         '        from '
                                                                         'Tests.ContractChecks.test_category_roam_registration '
                                                                         'import uncached_readiness_source\n'
                                                                         '        '
                                                                         'script=uncached_readiness_source(script)\n'
                                                                         '        '
                                                                         'script=script.replace(digest(current_raw).encode(),digest(raw).encode(),1)\n'},
                                                               {'before': '# CLUB_HISTORY_INPUT_END\n',
                                                                'after': '# CLUB_HISTORY_INPUT_END\n'
                                                                         '\n'
                                                                         '\n'
                                                                         'def '
                                                                         '_restore_precache_history_test(data):\n'
                                                                         '    """Keep the parser input '
                                                                         "adapter's ValueError boundary and "
                                                                         'complete b75 preimage."""\n'
                                                                         '    try:\n'
                                                                         '        return '
                                                                         '_restore_preclub_history_test(data)\n'
                                                                         '    except AssertionError as '
                                                                         'error:\n'
                                                                         '        raise '
                                                                         'ValueError(str(error)) from '
                                                                         'error\n'}]},
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': {'before_sha256': 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
                                                                           'after_sha256': '09b5c57129442da635c71ff664b9a8c22ff0d694184592b86058312eb073e11e',
                                                                           'hunks': [{'before': '            '
                                                                                                'reader.write_bytes(reader.read_bytes().replace(readiness.CONTRACT_SHA256.encode(), '
                                                                                                'admission.BASE_CONTRACT_SHA256.encode()))\n',
                                                                                      'after': '            '
                                                                                               'from '
                                                                                               'Tests.ContractChecks.test_category_roam_registration '
                                                                                               'import '
                                                                                               'uncached_readiness_source\n'
                                                                                               '            '
                                                                                               'reader.write_bytes(uncached_readiness_source(reader.read_bytes()).replace(readiness.CONTRACT_SHA256.encode(), '
                                                                                               'admission.BASE_CONTRACT_SHA256.encode()))\n'}]}}
REPAIR_CURRENT_SOURCE_ROWS = {'App/ProjectThoughtDefinitionsEditor.swift': {'before_sha256': 'dc2bcdecf846d8226db09d96df7ce7688cabc722249add64a114d48721263bd9',
                                               'after_sha256': 'e580e547bd55d7a0df2ef032fb39699aeb6187701cc604ab5d20be1129f91750',
                                               'hunks': [{'before': '        let id = UUID(), incarnation: '
                                                                    'UUID, session: ProjectEditSession?, '
                                                                    'identity: ProjectEditDraftIdentity?\n'
                                                                    '        let revision: Int, bytes: '
                                                                    'Data\n',
                                                          'after': '        let id = UUID()\n'
                                                                   '        let incarnation: UUID\n'
                                                                   '        let session: '
                                                                   'ProjectEditSession?\n'
                                                                   '        let identity: '
                                                                   'ProjectEditDraftIdentity?\n'
                                                                   '        let revision: Int\n'
                                                                   '        let bytes: Data\n'},
                                                         {'before': '        let id = UUID(), key: String, '
                                                                    'revision: Int, impacts: [String]\n',
                                                          'after': '        let id = UUID()\n'
                                                                   '        let key: String\n'
                                                                   '        let revision: Int\n'
                                                                   '        let impacts: [String]\n'}]},
 'App/ProjectEndingConditionPicker.swift': {'before_sha256': '188e81782efb8117c5dc669021c228c425c050996b0e6727aa325b00ea6eb418',
                                            'after_sha256': '16da43f7d88ae2aa153b622dfce15d91938d580a8ad0fdec61f51418d7827688',
                                            'hunks': [{'before': '    @ObservedObject var controller: '
                                                                 'ProjectEndingConditionController\n'
                                                                 '    @ObservedObject private var model: '
                                                                 'ProjectEditModel\n'
                                                                 '    let original: '
                                                                 'ProjectEndingConditionController.Presentation\n'
                                                                 '    @State private var selectedID: '
                                                                 'String?\n'
                                                                 '    init(controller: '
                                                                 'ProjectEndingConditionController, '
                                                                 'original: '
                                                                 'ProjectEndingConditionController.Presentation) '
                                                                 '{\n'
                                                                 '        self.controller = controller; '
                                                                 'self.original = original; model = '
                                                                 'controller.context.model\n'
                                                                 '        _selectedID = State(initialValue: '
                                                                 'original.choices.first(where: {\n'
                                                                 '            '
                                                                 'ProjectEditPendingMaterials.exactData($0.value) '
                                                                 '== original.oldValue.flatMap { '
                                                                 'ProjectEditPendingMaterials.exactData($0) '
                                                                 '}\n'
                                                                 '        })?.id)\n'
                                                                 '    }\n'
                                                                 '    private var originalText: String {\n'
                                                                 '        guard let raw = original.oldValue, '
                                                                 'let bytes = '
                                                                 'ProjectEditPendingMaterials.exactData(raw) '
                                                                 'else { return "—" }\n'
                                                                 '        return raw.text ?? '
                                                                 'String(decoding: bytes, as: UTF8.self)\n'
                                                                 '    }\n'
                                                                 '    var body: some View {\n'
                                                                 '        NavigationStack {\n'
                                                                 '            Form {\n'
                                                                 '                if '
                                                                 'controller.isCurrent(original) {\n'
                                                                 '                    '
                                                                 'LabeledContent(content: { Text(verbatim: '
                                                                 'originalText).textSelection(.enabled) },\n'
                                                                 '                        label: { '
                                                                 'Text("projectEndingChoice.current", '
                                                                 'tableName: "ProjectEndingConditionPicker") '
                                                                 '})\n'
                                                                 '                    '
                                                                 'Text("projectEndingChoice.scope", '
                                                                 'tableName: '
                                                                 '"ProjectEndingConditionPicker").font(.caption)\n'
                                                                 '                    if '
                                                                 'original.choices.isEmpty { '
                                                                 'Text("projectEndingChoice.empty", '
                                                                 'tableName: "ProjectEndingConditionPicker") '
                                                                 '}\n'
                                                                 '                    '
                                                                 'ForEach(original.choices) { choice in\n'
                                                                 '                        Button { '
                                                                 'selectedID = choice.id } label: {\n'
                                                                 '                            HStack {\n'
                                                                 '                                '
                                                                 'VStack(alignment: .leading) {\n',
                                                       'after': '    @ObservedObject var controller: '
                                                                'ProjectEndingConditionController\n'
                                                                '    @ObservedObject private var model: '
                                                                'ProjectEditModel\n'
                                                                '    let original: '
                                                                'ProjectEndingConditionController.Presentation\n'
                                                                '    init(controller: '
                                                                'ProjectEndingConditionController, original: '
                                                                'ProjectEndingConditionController.Presentation) '
                                                                '{\n'
                                                                '        self.controller = controller; '
                                                                'self.original = original; model = '
                                                                'controller.context.model\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        '
                                                                'ProjectConditionChoiceSheet(choices: '
                                                                'original.choices, oldValue: '
                                                                'original.oldValue,\n'
                                                                '            isCurrent: '
                                                                'controller.isCurrent(original), titleKey: '
                                                                '"projectEndingChoice.title",\n'
                                                                '            scopeKey: '
                                                                '"projectEndingChoice.scope", emptyKey: '
                                                                '"projectEndingChoice.empty",\n'
                                                                '            apply: { controller.apply(id: '
                                                                '$0, original: original) }, close: { '
                                                                'controller.close(original) })\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '/// Shared source-only UI. Ending and voice '
                                                                'controllers keep separate typed targets and '
                                                                'semantics.\n'
                                                                '@MainActor private struct '
                                                                'ProjectConditionChoiceSheet: View {\n'
                                                                '    let choices: '
                                                                '[ProjectEndingConditionChoices.Choice]\n'
                                                                '    let oldValue: ProjectEditJSON?\n'
                                                                '    let isCurrent: Bool\n'
                                                                '    let titleKey: String, scopeKey: String, '
                                                                'emptyKey: String\n'
                                                                '    let apply: (String) -> Void, close: () '
                                                                '-> Void\n'
                                                                '    @State private var selectedID: String?\n'
                                                                '    init(choices: '
                                                                '[ProjectEndingConditionChoices.Choice], '
                                                                'oldValue: ProjectEditJSON?, isCurrent: '
                                                                'Bool,\n'
                                                                '         titleKey: String, scopeKey: '
                                                                'String, emptyKey: String, apply: @escaping '
                                                                '(String) -> Void, close: @escaping () -> '
                                                                'Void) {\n'
                                                                '        self.choices = choices; '
                                                                'self.oldValue = oldValue; self.isCurrent = '
                                                                'isCurrent\n'
                                                                '        self.titleKey = titleKey; '
                                                                'self.scopeKey = scopeKey; self.emptyKey = '
                                                                'emptyKey; self.apply = apply; self.close = '
                                                                'close\n'
                                                                '        _selectedID = State(initialValue: '
                                                                'choices.first(where: {\n'
                                                                '            '
                                                                'ProjectEditPendingMaterials.exactData($0.value) '
                                                                '== oldValue.flatMap { '
                                                                'ProjectEditPendingMaterials.exactData($0) '
                                                                '}\n'
                                                                '        })?.id)\n'
                                                                '    }\n'
                                                                '    private var originalText: String {\n'
                                                                '        guard let raw = oldValue, let bytes '
                                                                '= '
                                                                'ProjectEditPendingMaterials.exactData(raw) '
                                                                'else { return "—" }\n'
                                                                '        return raw.text ?? String(decoding: '
                                                                'bytes, as: UTF8.self)\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        NavigationStack {\n'
                                                                '            Form {\n'
                                                                '                if isCurrent {\n'
                                                                '                    LabeledContent(content: '
                                                                '{ Text(verbatim: '
                                                                'originalText).textSelection(.enabled) },\n'
                                                                '                        label: { '
                                                                'Text("projectEndingChoice.current", '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '})\n'
                                                                '                    '
                                                                'Text(LocalizedStringKey(scopeKey), '
                                                                'tableName: '
                                                                '"ProjectEndingConditionPicker").font(.caption)\n'
                                                                '                    if choices.isEmpty { '
                                                                'Text(LocalizedStringKey(emptyKey), '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '}\n'
                                                                '                    ForEach(choices) { '
                                                                'choice in\n'
                                                                '                        Button { selectedID '
                                                                '= choice.id } label: {\n'
                                                                '                            HStack {\n'
                                                                '                                '
                                                                'VStack(alignment: .leading) {\n'},
                                                      {'before': '                            }\n'
                                                                 '                        }\n'
                                                                 '                    }\n'
                                                                 '                    Button(action: { if '
                                                                 'let selectedID { controller.apply(id: '
                                                                 'selectedID, original: original) } },\n'
                                                                 '                        label: { '
                                                                 'Text("projectEndingChoice.confirm", '
                                                                 'tableName: "ProjectEndingConditionPicker") '
                                                                 '})\n'
                                                                 '                        '
                                                                 '.disabled(selectedID == '
                                                                 'nil).accessibilityIdentifier("projectEndingChoice.confirm")\n'
                                                                 '                } else { '
                                                                 'Text("projectStarter.stale") }\n'
                                                                 '            }\n'
                                                                 '            '
                                                                 '.navigationTitle(Text("projectEndingChoice.title", '
                                                                 'tableName: '
                                                                 '"ProjectEndingConditionPicker"))\n'
                                                                 '            .toolbar { '
                                                                 'ToolbarItem(placement: '
                                                                 '.cancellationAction) { '
                                                                 'Button("action.cancel") { '
                                                                 'controller.close(original) } } }\n'
                                                                 '        }\n'
                                                                 '    }\n'
                                                                 '}\n',
                                                       'after': '                            }\n'
                                                                '                        }\n'
                                                                '                    }\n'
                                                                '                    Button(action: { if let '
                                                                'selectedID { apply(selectedID) } },\n'
                                                                '                        label: { '
                                                                'Text("projectEndingChoice.confirm", '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '})\n'
                                                                '                        '
                                                                '.disabled(selectedID == '
                                                                'nil).accessibilityIdentifier("projectEndingChoice.confirm")\n'
                                                                '                } else { '
                                                                'Text("projectStarter.stale") }\n'
                                                                '            }\n'
                                                                '            '
                                                                '.navigationTitle(Text(LocalizedStringKey(titleKey), '
                                                                'tableName: '
                                                                '"ProjectEndingConditionPicker"))\n'
                                                                '            .toolbar { '
                                                                'ToolbarItem(placement: .cancellationAction) '
                                                                '{ Button("action.cancel", action: close) } '
                                                                '}\n'
                                                                '        }\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '@MainActor final class '
                                                                'ProjectStoryConditionController: '
                                                                'ObservableObject {\n'
                                                                '    struct Presentation: Identifiable {\n'
                                                                '        let id = UUID(), incarnation: UUID, '
                                                                'session: ProjectEditSession?, identity: '
                                                                'ProjectEditDraftIdentity?\n'
                                                                '        let revision: Int, bytes: Data\n'
                                                                '        let lease: '
                                                                'ProjectEditStarterController.Lease\n'
                                                                '        let target: '
                                                                'ProjectStoryConditionChoice.Target\n'
                                                                '        let choices: '
                                                                '[ProjectEndingConditionChoices.Choice]\n'
                                                                '        let oldValue: ProjectEditJSON?\n'
                                                                '    }\n'
                                                                '    let model: ProjectEditModel\n'
                                                                '    let chapterID: String\n'
                                                                '    let block: Binding<ProjectEditBlock>\n'
                                                                '    @Published private(set) var '
                                                                'presentation: Presentation?\n'
                                                                '    init(model: ProjectEditModel, '
                                                                'chapterID: String, block: '
                                                                'Binding<ProjectEditBlock>) {\n'
                                                                '        self.model = model; self.chapterID '
                                                                '= chapterID; self.block = block\n'
                                                                '    }\n'
                                                                '    private var target: '
                                                                'ProjectStoryConditionChoice.Target? {\n'
                                                                '        guard model.captureStarterLease() '
                                                                '!= nil, let target = try? '
                                                                'ProjectStoryConditionChoice.Target(draft: '
                                                                'model.draft, chapterID: chapterID, blockID: '
                                                                'block.wrappedValue.id),\n'
                                                                '              '
                                                                'ProjectEditPendingMaterials.exactData(block.wrappedValue) '
                                                                '== target.blockBytes else { return nil }\n'
                                                                '        return target\n'
                                                                '    }\n'
                                                                '    var available: Bool { target != nil }\n'
                                                                '    func open() {\n'
                                                                '        guard presentation == nil, let '
                                                                'target, let lease = '
                                                                'model.captureStarterLease(), let bytes = '
                                                                'ProjectEditPendingMaterials.exactData(model.draft) '
                                                                'else { return }\n'
                                                                '        presentation = .init(incarnation: '
                                                                'model.editorIncarnation, session: '
                                                                'model.coordinator.session, identity: '
                                                                'model.coordinator.identity,\n'
                                                                '            revision: '
                                                                'model.draftMutationRevision, bytes: bytes, '
                                                                'lease: lease, target: target,\n'
                                                                '            choices: '
                                                                'ProjectEndingConditionChoices.choices(in: '
                                                                'model.draft, operation: "HAS_TAG"), '
                                                                'oldValue: '
                                                                'ProjectStoryConditionChoice.currentValue(target, '
                                                                'in: model.draft))\n'
                                                                '    }\n'
                                                                '    func isCurrent(_ original: '
                                                                'Presentation) -> Bool {\n'
                                                                '        presentation?.id == original.id && '
                                                                'model.isCurrentStarterLease(original.lease) '
                                                                '&& available && original.incarnation == '
                                                                'model.editorIncarnation &&\n'
                                                                '        original.session == '
                                                                'model.coordinator.session && '
                                                                'original.identity == '
                                                                'model.coordinator.identity &&\n'
                                                                '        original.revision == '
                                                                'model.draftMutationRevision && '
                                                                'ProjectEditPendingMaterials.exactData(model.draft) '
                                                                '== original.bytes &&\n'
                                                                '        '
                                                                'block.wrappedValue.id.utf8.elementsEqual(original.target.blockID.utf8) '
                                                                '&& '
                                                                'ProjectEditPendingMaterials.exactData(block.wrappedValue) '
                                                                '== original.target.blockBytes\n'
                                                                '    }\n'
                                                                '    func apply(id: String, original: '
                                                                'Presentation) {\n'
                                                                '        guard isCurrent(original), let '
                                                                'choice = original.choices.first(where: { '
                                                                '$0.id == id }),\n'
                                                                '              let next = try? '
                                                                'ProjectStoryConditionChoice.applying(choice, '
                                                                'to: model.draft, target: original.target) '
                                                                'else { return }\n'
                                                                '        if '
                                                                'ProjectEditPendingMaterials.exactData(next) '
                                                                '!= original.bytes { model.draft = next }\n'
                                                                '        close(original)\n'
                                                                '    }\n'
                                                                '    func close(_ original: Presentation) { '
                                                                'if presentation?.id == original.id { '
                                                                'presentation = nil } }\n'
                                                                '    func retire() { presentation = nil }\n'
                                                                '    func binding(_ original: Presentation?) '
                                                                '-> Binding<Presentation?> {\n'
                                                                '        .init(get: { guard let original, '
                                                                'self.isCurrent(original) else { return nil '
                                                                '}; return original },\n'
                                                                '              set: { if $0 == nil, let '
                                                                'original { self.close(original) } })\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '@MainActor struct '
                                                                'ProjectStoryConditionEntry: View {\n'
                                                                '    @ObservedObject private var model: '
                                                                'ProjectEditModel\n'
                                                                '    @StateObject private var controller: '
                                                                'ProjectStoryConditionController\n'
                                                                '    init(model: ProjectEditModel, '
                                                                'chapterID: String, block: '
                                                                'Binding<ProjectEditBlock>) {\n'
                                                                '        self.model = model; _controller = '
                                                                'StateObject(wrappedValue: .init(model: '
                                                                'model, chapterID: chapterID, block: '
                                                                'block))\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        let original = '
                                                                'controller.presentation\n'
                                                                '        Button(action: { controller.open() '
                                                                '}, label: { '
                                                                'Text("projectEndingChoice.choose", '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '})\n'
                                                                '            '
                                                                '.disabled(!controller.available).accessibilityIdentifier("projectStoryCondition.open")\n'
                                                                '            .sheet(item: '
                                                                'controller.binding(original)) { original in '
                                                                'ProjectStoryConditionSheet(controller: '
                                                                'controller, original: original) }\n'
                                                                '            .onChange(of: '
                                                                'model.editorIncarnation) { _, _ in '
                                                                'controller.retire() }\n'
                                                                '            .onDisappear { '
                                                                'controller.retire() }\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '@MainActor private struct '
                                                                'ProjectStoryConditionSheet: View {\n'
                                                                '    @ObservedObject var controller: '
                                                                'ProjectStoryConditionController\n'
                                                                '    @ObservedObject private var model: '
                                                                'ProjectEditModel\n'
                                                                '    let original: '
                                                                'ProjectStoryConditionController.Presentation\n'
                                                                '    init(controller: '
                                                                'ProjectStoryConditionController, original: '
                                                                'ProjectStoryConditionController.Presentation) '
                                                                '{\n'
                                                                '        self.controller = controller; '
                                                                'self.original = original; model = '
                                                                'controller.model\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        '
                                                                'ProjectConditionChoiceSheet(choices: '
                                                                'original.choices, oldValue: '
                                                                'original.oldValue,\n'
                                                                '            isCurrent: '
                                                                'controller.isCurrent(original), titleKey: '
                                                                '"projectStoryCondition.title",\n'
                                                                '            scopeKey: '
                                                                '"projectStoryCondition.scope", emptyKey: '
                                                                '"projectStoryCondition.empty",\n'
                                                                '            apply: { controller.apply(id: '
                                                                '$0, original: original) }, close: { '
                                                                'controller.close(original) })\n'
                                                                '    }\n'
                                                                '}\n'},
                                                      {'before': '@MainActor final class '
                                                                 'ProjectEndingConditionController: '
                                                                 'ObservableObject {\n'
                                                                 '    struct Presentation: Identifiable {\n'
                                                                 '        let id = UUID(), incarnation: '
                                                                 'UUID, session: ProjectEditSession?, '
                                                                 'identity: ProjectEditDraftIdentity?\n'
                                                                 '        let revision: Int, bytes: Data\n',
                                                       'after': '@MainActor final class '
                                                                'ProjectEndingConditionController: '
                                                                'ObservableObject {\n'
                                                                '    struct Presentation: Identifiable {\n'
                                                                '        let id = UUID()\n'
                                                                '        let incarnation: UUID\n'
                                                                '        let session: ProjectEditSession?\n'
                                                                '        let identity: '
                                                                'ProjectEditDraftIdentity?\n'
                                                                '        let revision: Int\n'
                                                                '        let bytes: Data\n'},
                                                      {'before': '@MainActor final class '
                                                                 'ProjectStoryConditionController: '
                                                                 'ObservableObject {\n'
                                                                 '    struct Presentation: Identifiable {\n'
                                                                 '        let id = UUID(), incarnation: '
                                                                 'UUID, session: ProjectEditSession?, '
                                                                 'identity: ProjectEditDraftIdentity?\n'
                                                                 '        let revision: Int, bytes: Data\n',
                                                       'after': '@MainActor final class '
                                                                'ProjectStoryConditionController: '
                                                                'ObservableObject {\n'
                                                                '    struct Presentation: Identifiable {\n'
                                                                '        let id = UUID()\n'
                                                                '        let incarnation: UUID\n'
                                                                '        let session: ProjectEditSession?\n'
                                                                '        let identity: '
                                                                'ProjectEditDraftIdentity?\n'
                                                                '        let revision: Int\n'
                                                                '        let bytes: Data\n'}]}}
REPAIR_PRE_SOURCE_ROWS = {'App/ProjectThoughtDefinitionsEditor.swift': None,
 'App/ProjectEndingConditionPicker.swift': {'before_sha256': '188e81782efb8117c5dc669021c228c425c050996b0e6727aa325b00ea6eb418',
                                            'after_sha256': '1b0a460cc65ee4ba69be25390940f188bbeaddbd824ee4d77d053dfdb28ba5a8',
                                            'hunks': [{'before': '    @ObservedObject var controller: '
                                                                 'ProjectEndingConditionController\n'
                                                                 '    @ObservedObject private var model: '
                                                                 'ProjectEditModel\n'
                                                                 '    let original: '
                                                                 'ProjectEndingConditionController.Presentation\n'
                                                                 '    @State private var selectedID: '
                                                                 'String?\n'
                                                                 '    init(controller: '
                                                                 'ProjectEndingConditionController, '
                                                                 'original: '
                                                                 'ProjectEndingConditionController.Presentation) '
                                                                 '{\n'
                                                                 '        self.controller = controller; '
                                                                 'self.original = original; model = '
                                                                 'controller.context.model\n'
                                                                 '        _selectedID = State(initialValue: '
                                                                 'original.choices.first(where: {\n'
                                                                 '            '
                                                                 'ProjectEditPendingMaterials.exactData($0.value) '
                                                                 '== original.oldValue.flatMap { '
                                                                 'ProjectEditPendingMaterials.exactData($0) '
                                                                 '}\n'
                                                                 '        })?.id)\n'
                                                                 '    }\n'
                                                                 '    private var originalText: String {\n'
                                                                 '        guard let raw = original.oldValue, '
                                                                 'let bytes = '
                                                                 'ProjectEditPendingMaterials.exactData(raw) '
                                                                 'else { return "—" }\n'
                                                                 '        return raw.text ?? '
                                                                 'String(decoding: bytes, as: UTF8.self)\n'
                                                                 '    }\n'
                                                                 '    var body: some View {\n'
                                                                 '        NavigationStack {\n'
                                                                 '            Form {\n'
                                                                 '                if '
                                                                 'controller.isCurrent(original) {\n'
                                                                 '                    '
                                                                 'LabeledContent(content: { Text(verbatim: '
                                                                 'originalText).textSelection(.enabled) },\n'
                                                                 '                        label: { '
                                                                 'Text("projectEndingChoice.current", '
                                                                 'tableName: "ProjectEndingConditionPicker") '
                                                                 '})\n'
                                                                 '                    '
                                                                 'Text("projectEndingChoice.scope", '
                                                                 'tableName: '
                                                                 '"ProjectEndingConditionPicker").font(.caption)\n'
                                                                 '                    if '
                                                                 'original.choices.isEmpty { '
                                                                 'Text("projectEndingChoice.empty", '
                                                                 'tableName: "ProjectEndingConditionPicker") '
                                                                 '}\n'
                                                                 '                    '
                                                                 'ForEach(original.choices) { choice in\n'
                                                                 '                        Button { '
                                                                 'selectedID = choice.id } label: {\n'
                                                                 '                            HStack {\n'
                                                                 '                                '
                                                                 'VStack(alignment: .leading) {\n',
                                                       'after': '    @ObservedObject var controller: '
                                                                'ProjectEndingConditionController\n'
                                                                '    @ObservedObject private var model: '
                                                                'ProjectEditModel\n'
                                                                '    let original: '
                                                                'ProjectEndingConditionController.Presentation\n'
                                                                '    init(controller: '
                                                                'ProjectEndingConditionController, original: '
                                                                'ProjectEndingConditionController.Presentation) '
                                                                '{\n'
                                                                '        self.controller = controller; '
                                                                'self.original = original; model = '
                                                                'controller.context.model\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        '
                                                                'ProjectConditionChoiceSheet(choices: '
                                                                'original.choices, oldValue: '
                                                                'original.oldValue,\n'
                                                                '            isCurrent: '
                                                                'controller.isCurrent(original), titleKey: '
                                                                '"projectEndingChoice.title",\n'
                                                                '            scopeKey: '
                                                                '"projectEndingChoice.scope", emptyKey: '
                                                                '"projectEndingChoice.empty",\n'
                                                                '            apply: { controller.apply(id: '
                                                                '$0, original: original) }, close: { '
                                                                'controller.close(original) })\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '/// Shared source-only UI. Ending and voice '
                                                                'controllers keep separate typed targets and '
                                                                'semantics.\n'
                                                                '@MainActor private struct '
                                                                'ProjectConditionChoiceSheet: View {\n'
                                                                '    let choices: '
                                                                '[ProjectEndingConditionChoices.Choice]\n'
                                                                '    let oldValue: ProjectEditJSON?\n'
                                                                '    let isCurrent: Bool\n'
                                                                '    let titleKey: String, scopeKey: String, '
                                                                'emptyKey: String\n'
                                                                '    let apply: (String) -> Void, close: () '
                                                                '-> Void\n'
                                                                '    @State private var selectedID: String?\n'
                                                                '    init(choices: '
                                                                '[ProjectEndingConditionChoices.Choice], '
                                                                'oldValue: ProjectEditJSON?, isCurrent: '
                                                                'Bool,\n'
                                                                '         titleKey: String, scopeKey: '
                                                                'String, emptyKey: String, apply: @escaping '
                                                                '(String) -> Void, close: @escaping () -> '
                                                                'Void) {\n'
                                                                '        self.choices = choices; '
                                                                'self.oldValue = oldValue; self.isCurrent = '
                                                                'isCurrent\n'
                                                                '        self.titleKey = titleKey; '
                                                                'self.scopeKey = scopeKey; self.emptyKey = '
                                                                'emptyKey; self.apply = apply; self.close = '
                                                                'close\n'
                                                                '        _selectedID = State(initialValue: '
                                                                'choices.first(where: {\n'
                                                                '            '
                                                                'ProjectEditPendingMaterials.exactData($0.value) '
                                                                '== oldValue.flatMap { '
                                                                'ProjectEditPendingMaterials.exactData($0) '
                                                                '}\n'
                                                                '        })?.id)\n'
                                                                '    }\n'
                                                                '    private var originalText: String {\n'
                                                                '        guard let raw = oldValue, let bytes '
                                                                '= '
                                                                'ProjectEditPendingMaterials.exactData(raw) '
                                                                'else { return "—" }\n'
                                                                '        return raw.text ?? String(decoding: '
                                                                'bytes, as: UTF8.self)\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        NavigationStack {\n'
                                                                '            Form {\n'
                                                                '                if isCurrent {\n'
                                                                '                    LabeledContent(content: '
                                                                '{ Text(verbatim: '
                                                                'originalText).textSelection(.enabled) },\n'
                                                                '                        label: { '
                                                                'Text("projectEndingChoice.current", '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '})\n'
                                                                '                    '
                                                                'Text(LocalizedStringKey(scopeKey), '
                                                                'tableName: '
                                                                '"ProjectEndingConditionPicker").font(.caption)\n'
                                                                '                    if choices.isEmpty { '
                                                                'Text(LocalizedStringKey(emptyKey), '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '}\n'
                                                                '                    ForEach(choices) { '
                                                                'choice in\n'
                                                                '                        Button { selectedID '
                                                                '= choice.id } label: {\n'
                                                                '                            HStack {\n'
                                                                '                                '
                                                                'VStack(alignment: .leading) {\n'},
                                                      {'before': '                            }\n'
                                                                 '                        }\n'
                                                                 '                    }\n'
                                                                 '                    Button(action: { if '
                                                                 'let selectedID { controller.apply(id: '
                                                                 'selectedID, original: original) } },\n'
                                                                 '                        label: { '
                                                                 'Text("projectEndingChoice.confirm", '
                                                                 'tableName: "ProjectEndingConditionPicker") '
                                                                 '})\n'
                                                                 '                        '
                                                                 '.disabled(selectedID == '
                                                                 'nil).accessibilityIdentifier("projectEndingChoice.confirm")\n'
                                                                 '                } else { '
                                                                 'Text("projectStarter.stale") }\n'
                                                                 '            }\n'
                                                                 '            '
                                                                 '.navigationTitle(Text("projectEndingChoice.title", '
                                                                 'tableName: '
                                                                 '"ProjectEndingConditionPicker"))\n'
                                                                 '            .toolbar { '
                                                                 'ToolbarItem(placement: '
                                                                 '.cancellationAction) { '
                                                                 'Button("action.cancel") { '
                                                                 'controller.close(original) } } }\n'
                                                                 '        }\n'
                                                                 '    }\n'
                                                                 '}\n',
                                                       'after': '                            }\n'
                                                                '                        }\n'
                                                                '                    }\n'
                                                                '                    Button(action: { if let '
                                                                'selectedID { apply(selectedID) } },\n'
                                                                '                        label: { '
                                                                'Text("projectEndingChoice.confirm", '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '})\n'
                                                                '                        '
                                                                '.disabled(selectedID == '
                                                                'nil).accessibilityIdentifier("projectEndingChoice.confirm")\n'
                                                                '                } else { '
                                                                'Text("projectStarter.stale") }\n'
                                                                '            }\n'
                                                                '            '
                                                                '.navigationTitle(Text(LocalizedStringKey(titleKey), '
                                                                'tableName: '
                                                                '"ProjectEndingConditionPicker"))\n'
                                                                '            .toolbar { '
                                                                'ToolbarItem(placement: .cancellationAction) '
                                                                '{ Button("action.cancel", action: close) } '
                                                                '}\n'
                                                                '        }\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '@MainActor final class '
                                                                'ProjectStoryConditionController: '
                                                                'ObservableObject {\n'
                                                                '    struct Presentation: Identifiable {\n'
                                                                '        let id = UUID(), incarnation: UUID, '
                                                                'session: ProjectEditSession?, identity: '
                                                                'ProjectEditDraftIdentity?\n'
                                                                '        let revision: Int, bytes: Data\n'
                                                                '        let lease: '
                                                                'ProjectEditStarterController.Lease\n'
                                                                '        let target: '
                                                                'ProjectStoryConditionChoice.Target\n'
                                                                '        let choices: '
                                                                '[ProjectEndingConditionChoices.Choice]\n'
                                                                '        let oldValue: ProjectEditJSON?\n'
                                                                '    }\n'
                                                                '    let model: ProjectEditModel\n'
                                                                '    let chapterID: String\n'
                                                                '    let block: Binding<ProjectEditBlock>\n'
                                                                '    @Published private(set) var '
                                                                'presentation: Presentation?\n'
                                                                '    init(model: ProjectEditModel, '
                                                                'chapterID: String, block: '
                                                                'Binding<ProjectEditBlock>) {\n'
                                                                '        self.model = model; self.chapterID '
                                                                '= chapterID; self.block = block\n'
                                                                '    }\n'
                                                                '    private var target: '
                                                                'ProjectStoryConditionChoice.Target? {\n'
                                                                '        guard model.captureStarterLease() '
                                                                '!= nil, let target = try? '
                                                                'ProjectStoryConditionChoice.Target(draft: '
                                                                'model.draft, chapterID: chapterID, blockID: '
                                                                'block.wrappedValue.id),\n'
                                                                '              '
                                                                'ProjectEditPendingMaterials.exactData(block.wrappedValue) '
                                                                '== target.blockBytes else { return nil }\n'
                                                                '        return target\n'
                                                                '    }\n'
                                                                '    var available: Bool { target != nil }\n'
                                                                '    func open() {\n'
                                                                '        guard presentation == nil, let '
                                                                'target, let lease = '
                                                                'model.captureStarterLease(), let bytes = '
                                                                'ProjectEditPendingMaterials.exactData(model.draft) '
                                                                'else { return }\n'
                                                                '        presentation = .init(incarnation: '
                                                                'model.editorIncarnation, session: '
                                                                'model.coordinator.session, identity: '
                                                                'model.coordinator.identity,\n'
                                                                '            revision: '
                                                                'model.draftMutationRevision, bytes: bytes, '
                                                                'lease: lease, target: target,\n'
                                                                '            choices: '
                                                                'ProjectEndingConditionChoices.choices(in: '
                                                                'model.draft, operation: "HAS_TAG"), '
                                                                'oldValue: '
                                                                'ProjectStoryConditionChoice.currentValue(target, '
                                                                'in: model.draft))\n'
                                                                '    }\n'
                                                                '    func isCurrent(_ original: '
                                                                'Presentation) -> Bool {\n'
                                                                '        presentation?.id == original.id && '
                                                                'model.isCurrentStarterLease(original.lease) '
                                                                '&& available && original.incarnation == '
                                                                'model.editorIncarnation &&\n'
                                                                '        original.session == '
                                                                'model.coordinator.session && '
                                                                'original.identity == '
                                                                'model.coordinator.identity &&\n'
                                                                '        original.revision == '
                                                                'model.draftMutationRevision && '
                                                                'ProjectEditPendingMaterials.exactData(model.draft) '
                                                                '== original.bytes &&\n'
                                                                '        '
                                                                'block.wrappedValue.id.utf8.elementsEqual(original.target.blockID.utf8) '
                                                                '&& '
                                                                'ProjectEditPendingMaterials.exactData(block.wrappedValue) '
                                                                '== original.target.blockBytes\n'
                                                                '    }\n'
                                                                '    func apply(id: String, original: '
                                                                'Presentation) {\n'
                                                                '        guard isCurrent(original), let '
                                                                'choice = original.choices.first(where: { '
                                                                '$0.id == id }),\n'
                                                                '              let next = try? '
                                                                'ProjectStoryConditionChoice.applying(choice, '
                                                                'to: model.draft, target: original.target) '
                                                                'else { return }\n'
                                                                '        if '
                                                                'ProjectEditPendingMaterials.exactData(next) '
                                                                '!= original.bytes { model.draft = next }\n'
                                                                '        close(original)\n'
                                                                '    }\n'
                                                                '    func close(_ original: Presentation) { '
                                                                'if presentation?.id == original.id { '
                                                                'presentation = nil } }\n'
                                                                '    func retire() { presentation = nil }\n'
                                                                '    func binding(_ original: Presentation?) '
                                                                '-> Binding<Presentation?> {\n'
                                                                '        .init(get: { guard let original, '
                                                                'self.isCurrent(original) else { return nil '
                                                                '}; return original },\n'
                                                                '              set: { if $0 == nil, let '
                                                                'original { self.close(original) } })\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '@MainActor struct '
                                                                'ProjectStoryConditionEntry: View {\n'
                                                                '    @ObservedObject private var model: '
                                                                'ProjectEditModel\n'
                                                                '    @StateObject private var controller: '
                                                                'ProjectStoryConditionController\n'
                                                                '    init(model: ProjectEditModel, '
                                                                'chapterID: String, block: '
                                                                'Binding<ProjectEditBlock>) {\n'
                                                                '        self.model = model; _controller = '
                                                                'StateObject(wrappedValue: .init(model: '
                                                                'model, chapterID: chapterID, block: '
                                                                'block))\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        let original = '
                                                                'controller.presentation\n'
                                                                '        Button(action: { controller.open() '
                                                                '}, label: { '
                                                                'Text("projectEndingChoice.choose", '
                                                                'tableName: "ProjectEndingConditionPicker") '
                                                                '})\n'
                                                                '            '
                                                                '.disabled(!controller.available).accessibilityIdentifier("projectStoryCondition.open")\n'
                                                                '            .sheet(item: '
                                                                'controller.binding(original)) { original in '
                                                                'ProjectStoryConditionSheet(controller: '
                                                                'controller, original: original) }\n'
                                                                '            .onChange(of: '
                                                                'model.editorIncarnation) { _, _ in '
                                                                'controller.retire() }\n'
                                                                '            .onDisappear { '
                                                                'controller.retire() }\n'
                                                                '    }\n'
                                                                '}\n'
                                                                '@MainActor private struct '
                                                                'ProjectStoryConditionSheet: View {\n'
                                                                '    @ObservedObject var controller: '
                                                                'ProjectStoryConditionController\n'
                                                                '    @ObservedObject private var model: '
                                                                'ProjectEditModel\n'
                                                                '    let original: '
                                                                'ProjectStoryConditionController.Presentation\n'
                                                                '    init(controller: '
                                                                'ProjectStoryConditionController, original: '
                                                                'ProjectStoryConditionController.Presentation) '
                                                                '{\n'
                                                                '        self.controller = controller; '
                                                                'self.original = original; model = '
                                                                'controller.model\n'
                                                                '    }\n'
                                                                '    var body: some View {\n'
                                                                '        '
                                                                'ProjectConditionChoiceSheet(choices: '
                                                                'original.choices, oldValue: '
                                                                'original.oldValue,\n'
                                                                '            isCurrent: '
                                                                'controller.isCurrent(original), titleKey: '
                                                                '"projectStoryCondition.title",\n'
                                                                '            scopeKey: '
                                                                '"projectStoryCondition.scope", emptyKey: '
                                                                '"projectStoryCondition.empty",\n'
                                                                '            apply: { controller.apply(id: '
                                                                '$0, original: original) }, close: { '
                                                                'controller.close(original) })\n'
                                                                '    }\n'
                                                                '}\n'}]}}
REPAIR_PRE_SUPPORT = {'Tests/ContractChecks/test_category_roam_registration.py': '80f4cbe6fba6df6ed1604aea7d7dfd20fd957d679a6e450401a49d2b80c5f1fa',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '1cda598881ae8cd6327b8ef322337f78ca40d8f6c29f2a7d8b84b49050de591f',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': 'f9904bbd44d23bcaacd02be0647cf6bc4d7f0d5994371a8f05f2edac868b59ec',
 'tools/club_customer_directory_admission.py': '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297',
 'tools/tests/test_creator_shelf_state_history.py': 'accaa341cf2803a6847c19ee675d7bb9d06b831d300c1a56d9f17d9aeddfb65e',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
 'App/ProjectThoughtDefinitionsEditor.swift': 'dc2bcdecf846d8226db09d96df7ce7688cabc722249add64a114d48721263bd9'}
REPAIR_LEAF_PATHS = ('App/ProjectThoughtDefinitionsEditor.swift', 'App/ProjectEndingConditionPicker.swift')
READINESS_PARSE_CACHE_INVERSE_HUNKS = [('import json\nfrom copy import deepcopy\nfrom functools import lru_cache\n', 'import json\n'),
 ('@lru_cache(maxsize=1)\n'
  'def _parsed_contract(raw):\n'
  '    return json.loads(raw)\n'
  '\n'
  '\n'
  'def contract(root=ROOT):\n',
  'def contract(root=ROOT):\n'),
 ('    return deepcopy(_parsed_contract(raw))\n\n\ndef source_contract',
  '    return json.loads(raw)\n\n\ndef source_contract')]
REPAIR_PROFILE_INPUT_HUNKS = [('        from Tests.ContractChecks.test_category_roam_registration import uncached_readiness_source\n'
  '        source = '
  "uncached_readiness_source((ROOT/'tools/run138_editor_readiness.py').read_bytes()).decode()\n",
  "        source = (ROOT/'tools/run138_editor_readiness.py').read_text()\n")]

def uncached_readiness_source(raw):
    raw = native_readiness_source(raw)
    for after, before in reversed(READINESS_PARSE_CACHE_INVERSE_HUNKS):
        after, before = after.encode(), before.encode()
        if raw.count(after) != 1:
            raise ValueError('Unknown readiness parser-cache source span')
        raw = raw.replace(after, before, 1)
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
    if len(pins) != 1 or digest(raw.replace(pins[0], BASE_CONTRACT_SHA256.encode())) != BASE_RUNNER_SHA256:
        raise ValueError('Unknown complete uncached readiness predecessor')
    return raw


def repair_profile_input_predecessor(raw):
    for after, before in reversed(REPAIR_PROFILE_INPUT_HUNKS):
        after, before = after.encode(), before.encode()
        require(raw.count(after) == 1, 'Unknown exact profile parser input adapter')
        raw = raw.replace(after, before, 1)
    return raw


def repair_predecessor_source(path, raw):
    raw = native_predecessor_source(path, raw)
    if path == 'tools/club_customer_directory_admission.py':
        require(digest(raw) == REPAIR_SOURCE_INVERSES[path]['after_sha256'], 'Unreviewed complete club helper input')
    if path in REPAIR_SOURCE_INVERSES:
        return _inverse_exact(raw, REPAIR_SOURCE_INVERSES[path], path)
    return raw


def repair_predecessor_contract(value):
    value = native_predecessor_contract(value)
    for path, expected in REPAIR_CURRENT_SOURCE_ROWS.items():
        require(value['feature_batch_sources'].get(path) == expected,
                'Changed exact parser/property source row: ' + path)
        prior = REPAIR_PRE_SOURCE_ROWS[path]
        if prior is None: del value['feature_batch_sources'][path]
        else: value['feature_batch_sources'][path] = copy.deepcopy(prior)
    for path, old in REPAIR_PRE_SUPPORT.items():
        require(value['feature_batch_support_sha256'].get(path) == digest(native_predecessor_source(path, (ROOT / path).read_bytes())),
                'Changed exact parser/property support: ' + path)
        value['feature_batch_support_sha256'][path] = old
    require(digest(encode(value)) == REPAIR_PRE_CONTRACT_SHA256,
            'Complete discovery predecessor contract not restored')
    return value


def repair_predecessor_fixture_source(path, raw, current_contract):
    if path == CONTRACT_PATH:
        require(raw == current_contract, 'Mixed current fixture contract')
        return encode(repair_predecessor_contract(json.loads(raw)))
    if path == RUNNER_PATH:
        old = uncached_readiness_source(raw)
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", old)
        require(len(pins) == 1 and pins[0].decode() == digest(current_contract), 'Mixed current fixture runner')
        old = old.replace(pins[0], REPAIR_PRE_CONTRACT_SHA256.encode())
        require(digest(old) == REPAIR_PRE_RUNNER_SHA256, 'Complete predecessor fixture runner changed')
        return old
    if path == PROFILE_PATH:
        raw = repair_profile_input_predecessor(raw)
        before = ("DISCOVERY_HELPER_FINGERPRINT = '" + ADMISSION_FINGERPRINT + "'").encode()
        after = ("DISCOVERY_HELPER_FINGERPRINT = '" + REPAIR_PRE_FINGERPRINT + "'").encode()
        require(raw.count(before) == 1, 'Missing current profile binding')
        old = raw.replace(before, after, 1)
        require(digest(old) == REPAIR_PRE_PROFILE_SHA256, 'Complete predecessor fixture profile changed')
        return old
    return repair_predecessor_source(path, raw)


def _parent_contract(value):
    value = repair_predecessor_contract(value)
    for path, expected in CURRENT_SOURCE_ROWS.items():
        require(value['feature_batch_sources'].get(path) == expected, 'Unknown new source row: ' + path)
        old = PARENT_SOURCE_ROWS[path]
        if old is None: del value['feature_batch_sources'][path]
        else: value['feature_batch_sources'][path] = copy.deepcopy(old)
    for path in ADDED_SUPPORT_PATHS:
        require(path in value['feature_batch_support_sha256'], 'Missing new support: ' + path)
        del value['feature_batch_support_sha256'][path]
    for path, row in EXTRA_INPUT_ROWS.items():
        require(value['feature_batch_support_sha256'].get(path) == row['after_sha256'], 'Unknown creator input bridge support: ' + path)
        if EXTRA_PARENT_SUPPORT[path] is None: del value['feature_batch_support_sha256'][path]
        else: value['feature_batch_support_sha256'][path] = EXTRA_PARENT_SUPPORT[path]
    value['feature_batch_support_sha256'][PROFILE_PATH] = PARENT_PROFILE_SHA256
    value['feature_batch_support_sha256'][CATALOG_PATH] = PARENT_CATALOG_SHA256
    require(digest(encode(value)) == PARENT_CONTRACT_SHA256, 'Complete frozen club R2 contract not restored')
    return value


def _project_contract(value, changes, orders, expected):
    value = copy.deepcopy(value)
    for operation in changes:
        path = operation['path']; parent = value
        for name in path[:-1]: parent = parent[name]
        name = path[-1]; action = operation['action']
        if action == 'splice':
            target = parent[name]; start = operation['start']; stop = operation['stop']
            require(digest(encode(target[start:stop])) == operation['before'], 'Unknown bounded list input')
            target[start:stop] = copy.deepcopy(operation['value'])
        else:
            actual = digest(encode(parent[name])) if name in parent else None
            require(actual == operation['before'], 'Unknown bounded contract input: ' + str(path))
            if action == 'remove': del parent[name]
            else: parent[name] = copy.deepcopy(operation['value'])
    for field, order in orders.items():
        require(set(value[field]) == set(order), 'Unknown bounded contract field domain')
        value[field] = {name: value[field][name] for name in order}
    require(digest(encode(value)) == expected, 'Complete bounded historical contract not restored')
    return value


def _profile_preimage(raw):
    raw = repair_profile_input_predecessor(raw)
    pins = re.findall(rb"(?m)^DISCOVERY_HELPER_FINGERPRINT = '([0-9a-f]{64})'$", raw)
    require(len(pins) == 1 and pins[0].decode() == ADMISSION_FINGERPRINT,
            'Profile frontend does not pin this exact admission implementation')
    normalized = raw.replace(b"DISCOVERY_HELPER_FINGERPRINT = '" + pins[0] + b"'",
                             b"DISCOVERY_HELPER_FINGERPRINT = '<DISCOVERY_HELPER>'", 1)
    return _inverse_exact(normalized, PARENT_PROFILE_ROW, PROFILE_PATH)


def _decoded_external_template(raw):
    first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
    last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(raw.count(first) == 1 and raw.count(last) == 1,
            'Missing/repeated external source template markers')
    require(raw[CATEGORY_TEMPLATE_OFFSET:].startswith(first) and raw.endswith(last + suffix),
            'Moved external source template or changed suffix')
    start = CATEGORY_TEMPLATE_OFFSET
    finish = len(raw) - len(suffix)
    normalized = raw[:start] + suffix
    require(digest(normalized) == ADAPTED_CATEGORY_GATE_SHA256,
            'Complete category source outside exact template changed')
    body = raw[start + len(first):finish - len(last)]
    nodes = ast.parse(body).body
    require(len(nodes) == 1 and isinstance(nodes[0], ast.Assign) and len(nodes[0].targets) == 1 and
            isinstance(nodes[0].targets[0], ast.Name) and nodes[0].targets[0].id == 'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85',
            'External template must be one literal data assignment')
    encoded = ast.literal_eval(nodes[0].value)
    require(isinstance(encoded, str), 'External template must be literal text data')
    value = decode_frozen_source(encoded.encode())
    require(encode_frozen_source(value).decode() == encoded,
            'Noncanonical external compressed source template')
    canonical = first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
        ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last
    require(raw[start:finish] == canonical, 'Changed exact external template data block')
    return normalized, value


def validate_external_source_template(root, actual):
    # This frozen pure-data template is read from the distinct actual category
    # source each time. No current self/profile/contract fingerprint produces it.
    raw = (Path(root) / CATEGORY_GATE).read_bytes()
    normalized, expected = _decoded_external_template(raw)
    require(actual == expected, 'Actual complete admission differs from external frozen source template')
    return normalized


def category_gate_without_template(raw):
    current = (ROOT / CATEGORY_GATE).read_bytes()
    require(raw == current, 'Unknown actual complete category source argument')
    return validate_external_source_template(ROOT, (ROOT / SELF_PATH).read_bytes())


def checked_current(raw, root):
    """Read all actual current bytes on every call, before any historical cache."""
    root = Path(root)
    require((root / CONTRACT_PATH).read_bytes() == raw, 'Live current contract differs from supplied bytes')
    require(digest((root / NATIVE_PROJECTION_PATH).read_bytes()) == ACTOR_PROJECTION_ROW['after_sha256'], 'Changed actual current projection source')
    try:
        runner = uncached_readiness_source(native_current_readiness_source((root / RUNNER_PATH).read_bytes()))
    except ValueError as error:
        raise AssertionError(str(error)) from error
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    require(len(pins) == 1, 'Missing/repeated current runner pin')
    require(digest(runner.replace(pins[0], BASE_CONTRACT_SHA256.encode())) == BASE_RUNNER_SHA256,
            'Current runner differs beyond its reviewed contract pin')
    require(digest(raw).encode() == pins[0], 'Unknown complete current contract')
    value = json.loads(raw)
    require(encode(value) == raw, 'Noncanonical/duplicate current contract')
    album_current_inputs(value, root)
    actor_current_inputs(value, root)
    description_current_inputs(value, root)
    require(digest((root / SELF_PATH).read_bytes()) == IMPLEMENTATION_SHA256,
            'Loaded current admission differs from actual source')
    module = (root / SELF_PATH).read_bytes()
    validate_external_source_template(root, module)
    slots = re.findall(rb"(?m)^ADMISSION_FINGERPRINT = '([0-9a-f]{64})'$", module)
    require(len(slots) == 1 and slots[0].decode() == ADMISSION_FINGERPRINT,
            'Changed current admission fingerprint slot')
    normalized = module.replace(b"ADMISSION_FINGERPRINT = '" + slots[0] + b"'", b"ADMISSION_FINGERPRINT = '<SELF>'", 1)
    require(digest(normalized) == ADMISSION_FINGERPRINT, 'Changed complete admission implementation')
    _profile_preimage((root / PROFILE_PATH).read_bytes())
    # The fixed parent hash and exact finite rows, rather than re-computed pins,
    # determine the allowed product domain.
    # Independent parent input pins protect even freshly imported/rehashed helpers.
    for path, expected in PARENT_INPUT_SHA256.items():
        message = 'Unreviewed complete club helper input' if path == 'tools/club_customer_directory_admission.py' else 'Changed exact parent raw input: ' + path
        data = repair_predecessor_source(path, (root / path).read_bytes())
        if path in EXTRA_INPUT_ROWS: data = _inverse_exact(data, EXTRA_INPUT_ROWS[path], path)
        require(digest(data) == expected, message)
    parent = _parent_contract(value)
    sources = {path: (root / path).read_bytes() for path in FROZEN_SHA256}
    for path, expected in FROZEN_SHA256.items():
        require(digest(sources[path]) == expected, 'Changed current frozen leaf: ' + path)
    sources[CATEGORY_GATE] = (root / CATEGORY_GATE).read_bytes()
    sources[SELF_PATH] = (root / SELF_PATH).read_bytes()
    restore_category_gate(sources[CATEGORY_GATE])
    for path, row in value['feature_batch_sources'].items():
        _inverse_exact((root / path).read_bytes(), row, path)
    for path, expected in value['feature_batch_support_sha256'].items():
        require(digest((root / path).read_bytes()) == expected, 'Changed real current support: ' + path)
    _inverse_exact(sources[CATALOG_PATH], CURRENT_SOURCE_ROWS[CATALOG_PATH], CATALOG_PATH)
    return value, sources, runner, pins[0]


def restore_category_contract(value):
    parent = _parent_contract(value)
    return encode(_project_contract(parent, PARENT_TO_CATEGORY_DELTA,
                                   PARENT_TO_CATEGORY_ORDER, CATEGORY_CONTRACT_SHA256))


def historical_r2_contract(raw, root):
    value, _, _, _ = checked_current(raw, root)
    return _project_contract(_parent_contract(value), PARENT_TO_R2_DELTA,
                             PARENT_TO_R2_ORDER, R2_CONTRACT_SHA256)


def category_scanner_bytes(raw, *, root=ROOT):
    current = (Path(root) / CONTRACT_PATH).read_bytes()
    checked_current(current, root)
    require(raw == (Path(root) / SCANNER_PATH).read_bytes(), 'Unknown live scanner argument')
    require(digest(raw) == PARENT_SCANNER_SHA256, 'Changed current scanner frontend')
    return CATEGORY_SCANNER_BYTES.encode()


_profile_contexts = {}
_profile_origins = {}
_protected_contexts = {}
_creator_fixture_contexts = {}
_profile_context_creations = 0


def _bounded_context(cache, key, contents, prefix):
    if key in cache:
        item = cache[key]; target = item['root']
        actual = {str(p.relative_to(target)): digest(p.read_bytes()) for p in target.rglob('*') if p.is_file()}
        require(actual == {p: digest(b) for p, b in contents.items()}, 'Changed bounded historical cache')
        return target
    life = tempfile.TemporaryDirectory(prefix=prefix)
    target = Path(life.name)
    for name, raw in contents.items():
        file = target / name; file.parent.mkdir(parents=True, exist_ok=True); file.write_bytes(raw)
    cache[key] = {'root': target, 'life': life}
    return target


def _profile_parent_inputs(root):
    global _profile_context_creations
    root = Path(root)
    require(not root.is_symlink(), 'Historical fixture root itself must not be a symlink')
    origin = _profile_origins.get(str(root.resolve()), root)
    if str(root.resolve()) not in _profile_origins and root.resolve() != ROOT.resolve():
        # An explicit historical-only fixture domain, never current admission.
        # Missing files are not filled from the healthy live root.
        checked_current((ROOT / CONTRACT_PATH).read_bytes(), ROOT)
        members = list(root.rglob('*'))
        require(not any(p.is_symlink() for p in members), 'Symlink in historical 47-file fixture')
        files = {str(p.relative_to(root)) for p in members if p.is_file()}
        current_raw = (ROOT / CONTRACT_PATH).read_bytes()
        incoming = {path: (root / path).read_bytes() for path in files}
        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH, ALBUM_LEAF_PATH}:
            # All 54 physical current inputs precede every predecessor/cache reuse.
            for path, data in incoming.items():
                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 54-file fixture: ' + path)
        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH}:
            # Exactly published bb5/53; missing-current54 is never backfilled.
            for path, data in incoming.items():
                expected = album_predecessor_fixture_source(path, (ROOT / path).read_bytes(), current_raw)
                require(data == expected, 'Changed/mixed historical bb5/53 fixture: ' + path)
        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH}:
            # Exactly published 42/52; missing-current53 is never backfilled.
            for path, data in incoming.items():
                expected = actor_predecessor_fixture_source(path, (ROOT / path).read_bytes(), current_raw)
                require(data == expected, 'Changed/mixed historical 42/52 fixture: ' + path)
        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | set(NATIVE_CURRENT_INPUTS):
            # Exactly published 7b51; missing-current52 is never backfilled.
            for path, data in incoming.items():
                expected = description_predecessor_fixture_source(path, (ROOT / path).read_bytes(), current_raw)
                require(data == expected, 'Changed/mixed historical 7b51 fixture: ' + path)
        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS):
            # This is exactly published c2af49, not current51 with missing inputs.
            for path, data in incoming.items():
                expected = native_predecessor_fixture_source(path, (ROOT / path).read_bytes(), current_raw)
                require(data == expected, 'Changed/mixed historical c2af49 fixture: ' + path)
        else:
            require(files == set(PROFILE_CONTEXT_INPUTS), 'Historical fixture must contain exactly 47 inputs')
            for path in PROFILE_CONTEXT_INPUTS:
                expected = repair_predecessor_fixture_source(path, (ROOT / path).read_bytes(), current_raw)
                require(incoming[path] == expected,
                        'Changed/mixed historical fixture raw input: ' + path)
        origin = ROOT
    raw = (origin / CONTRACT_PATH).read_bytes()
    value, sources, runner, pin = checked_current(raw, origin)
    parent = _parent_contract(value)
    contents = {p: repair_predecessor_source(p, (origin / p).read_bytes()) for p in PROFILE_CONTEXT_INPUTS}
    for path, row in EXTRA_INPUT_ROWS.items(): contents[path] = _inverse_exact(contents[path], row, path)
    contents[CONTRACT_PATH] = encode(parent)
    contents[RUNNER_PATH] = runner.replace(pin, PARENT_CONTRACT_SHA256.encode())
    contents[PROFILE_PATH] = _profile_preimage((origin / PROFILE_PATH).read_bytes())
    contents[CATALOG_PATH] = _inverse_exact(contents[CATALOG_PATH], CURRENT_SOURCE_ROWS[CATALOG_PATH], CATALOG_PATH)
    require(len(contents) == 47, 'Profile context escaped its finite 47-file domain')
    key = (str(origin.resolve()), digest(raw))
    created = key not in _profile_contexts
    target = _bounded_context(_profile_contexts, key, contents, 'category-roam-profile-')
    if created: _profile_context_creations += 1
    _profile_origins[str(target.resolve())] = origin
    return raw, parent, target


def profile_history_inputs(data, root, stage):
    try:
        current, parent, target = _profile_parent_inputs(root)
        if data == current: data = encode(parent)
        require(digest(data) in PROFILE_CONTRACT_FLOORS[stage], 'Unknown mixed profile historical input layer')
        return data, target
    except (AssertionError, OSError, KeyError, TypeError, UnicodeError) as error:
        raise ValueError(str(error)) from error


def profile_contract_inputs(value, root, stage):
    data, target = profile_history_inputs(encode(value), root, stage)
    return json.loads(data), target


def historical_protected_root(root, path):
    root = Path(root)
    checked_current((root / CONTRACT_PATH).read_bytes(), root)
    if path != 'Questify.xcodeproj/project.pbxproj': return root
    raw = _inverse_exact(native_predecessor_source(path, (root / path).read_bytes()), PROTECTED_PBX_ROW, path)
    require(digest(raw) == PROTECTED_PBX_SHA256, 'Unknown exact historical PBX')
    return _bounded_context(_protected_contexts, str(root.resolve()), {path: raw}, 'category-roam-pbx-')


def creator_catalog_input(data, root):
    root = Path(root)
    checked_current((root / CONTRACT_PATH).read_bytes(), root)
    require(data == (root / CATALOG_PATH).read_bytes(), 'Unknown current creator catalog argument')
    return _inverse_exact(data, CURRENT_SOURCE_ROWS[CATALOG_PATH], CATALOG_PATH)


def creator_history_root(root, *, live_root=ROOT):
    try:
        _, _, context = _profile_parent_inputs(live_root)
        root = Path(root)
        # Existing bounded legacy fixtures keep their original strict domain.
        # The actual current root and our authenticated parent context are explicit.
        if root.resolve() == Path(live_root).resolve(): return context
        if str(root.resolve()) in _profile_origins: return root
        require(not (root / CONTRACT_PATH).exists() and not (root / CONTRACT_PATH).is_symlink(),
                'Unknown mixed current creator history root')
        # The pre-existing eight-input synthetic fixture can contain the new
        # catalog/gate only as an exact complete current eight-file group.
        # Old fixtures still proceed to the unchanged strict old state reader.
        incoming = {p: (root / p).read_bytes() for p in CREATOR_FIXTURE_INPUTS if (root / p).exists()}
        new_catalog = CATALOG_PATH in incoming and digest(incoming[CATALOG_PATH]) == CURRENT_SOURCE_ROWS[CATALOG_PATH]['after_sha256']
        new_gate = CREATOR_RAW_GATE_PATH in incoming and digest(incoming[CREATOR_RAW_GATE_PATH]) == EXTRA_INPUT_ROWS[CREATOR_RAW_GATE_PATH]['after_sha256']
        if new_catalog or new_gate:
            require(set(incoming) == set(CREATOR_FIXTURE_INPUTS), 'Incomplete current eight-file creator fixture')
            for path, data in incoming.items():
                require(not (root / path).is_symlink(), 'Symlink in current creator fixture')
                require(data == (Path(live_root) / path).read_bytes(), 'Mixed current creator fixture: ' + path)
            old = {p: (context / p).read_bytes() for p in CREATOR_FIXTURE_INPUTS}
            return _bounded_context(_creator_fixture_contexts, str(root.resolve()), old, 'category-roam-creator8-')
        return root
    except (AssertionError, OSError, KeyError, TypeError, UnicodeError) as error:
        raise ValueError(str(error)) from error


def creator_history_sources(root, names):
    target = creator_history_root(root, live_root=root)
    require(set(names) <= set(PROFILE_CONTEXT_INPUTS), 'Creator historical inputs exceed reviewed domain')
    return {name: (target / name).read_bytes() for name in names}


def creator_history_test_preimage(data, root):
    root = Path(root)
    checked_current((root / CONTRACT_PATH).read_bytes(), root)
    require(data == (root / CREATOR_HISTORY_TEST_PATH).read_bytes(), 'Unknown live creator history test argument')
    data = repair_predecessor_source(CREATOR_HISTORY_TEST_PATH, data)
    return _inverse_exact(data, EXTRA_INPUT_ROWS[CREATOR_HISTORY_TEST_PATH], CREATOR_HISTORY_TEST_PATH)

class CategoryRoamCurrentFloorContracts(unittest.TestCase):
    def test_physical_same_size_mtime_and_missing_inputs_reject_after_cached_history(self):
        import os
        raw = (ROOT / CONTRACT_PATH).read_bytes()
        pre_roam_category_inputs(raw)
        profile_history_inputs(raw, ROOT, 'history')
        for path in CURRENT_APPROVED_PATHS + [SCANNER_PATH]:
            file = ROOT / path; saved = file.read_bytes(); metadata = file.stat()
            self.assertFalse(file.is_symlink(), path)
            try:
                file.write_bytes(bytes([saved[0] ^ 1]) + saved[1:])
                os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                self.assertEqual(file.stat().st_size, metadata.st_size)
                self.assertEqual(file.stat().st_mtime_ns, metadata.st_mtime_ns)
                with self.assertRaises((AssertionError, ValueError, OSError)):
                    pre_roam_category_inputs(raw)
                with self.assertRaises(ValueError):
                    profile_history_inputs(raw, ROOT, 'history')
            finally:
                file.write_bytes(saved)
                os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            backup = file.with_name(file.name + '.category-roam-missing-probe')
            self.assertFalse(backup.exists())
            file.rename(backup)
            try:
                with self.assertRaises((AssertionError, ValueError, OSError)):
                    pre_roam_category_inputs(raw)
                with self.assertRaises(ValueError):
                    profile_history_inputs(raw, ROOT, 'history')
            finally: backup.rename(file)
        checked_current(raw, ROOT)

    def test_fresh_import_and_recomputed_self_slot_cannot_bypass_frontend_pin(self):
        import types
        raw = (ROOT / CONTRACT_PATH).read_bytes()
        source = (ROOT / SELF_PATH).read_bytes()
        for replace_slot in (False, True):
            mutant = source + b'\n'
            if replace_slot:
                normalized = mutant.replace(b"ADMISSION_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'",
                                            b"ADMISSION_FINGERPRINT = '<SELF>'", 1)
                mutant = mutant.replace(ADMISSION_FINGERPRINT.encode(), digest(normalized).encode(), 1)
            value = json.loads(raw); value['feature_batch_support_sha256'][SELF_PATH] = digest(mutant)
            changed = encode(value)
            runner = (ROOT / RUNNER_PATH).read_bytes().replace(digest(raw).encode(), digest(changed).encode())
            changes = {ROOT / SELF_PATH: mutant, ROOT / CONTRACT_PATH: changed, ROOT / RUNNER_PATH: runner}
            real = Path.read_bytes
            def read(file): return changes[file] if file in changes else real(file)
            with patch.object(Path, 'read_bytes', read):
                fresh = types.ModuleType('category_roam_fresh_negative'); fresh.__file__ = str(ROOT / SELF_PATH)
                exec(compile(mutant, fresh.__file__, 'exec'), fresh.__dict__)
                with self.assertRaises(AssertionError): fresh.checked_current(changed, ROOT)

    def test_profile_context_is_bounded_reused_and_authenticates_live_and_cached_bytes(self):
        raw = (ROOT / CONTRACT_PATH).read_bytes()
        parent, context = profile_history_inputs(raw, ROOT, 'history')
        self.assertEqual(digest(parent), PARENT_CONTRACT_SHA256)
        self.assertEqual({str(p.relative_to(context)) for p in context.rglob('*') if p.is_file()}, set(PROFILE_CONTEXT_INPUTS))
        count = _profile_context_creations
        for _ in range(10): self.assertEqual(profile_history_inputs(raw, ROOT, 'history')[1], context)
        self.assertEqual(_profile_context_creations, count)
        target = context / CATALOG_PATH; saved = target.read_bytes()
        try:
            target.write_bytes(saved + b'\n')
            with self.assertRaisesRegex(ValueError, 'Changed bounded historical cache'):
                profile_history_inputs(raw, ROOT, 'history')
        finally: target.write_bytes(saved)
        for mixed in [encode(_parent_contract(json.loads(raw))), encode(historical_r2_contract(raw, ROOT)), raw + b'\n']:
            if digest(mixed) == PARENT_CONTRACT_SHA256:
                # Accepted only as the explicitly authenticated historical floor.
                self.assertEqual(profile_history_inputs(mixed, ROOT, 'history')[0], parent)
            else:
                with self.assertRaises(ValueError): profile_history_inputs(mixed, ROOT, 'history')

    def test_new_current_catalog_and_scanner_preserve_whole_club_floor(self):
        raw = (ROOT / CONTRACT_PATH).read_bytes(); checked_current(raw, ROOT)
        current = (ROOT / CATALOG_PATH).read_bytes()
        old = _inverse_exact(current, CURRENT_SOURCE_ROWS[CATALOG_PATH], CATALOG_PATH)
        self.assertEqual(digest(old), PARENT_CATALOG_SHA256)
        prior = json.loads(old); now = json.loads(current)
        keys = {key for key in now['strings'] if key.startswith('roamRouteReplay.')}
        self.assertEqual(len(keys), 7)
        for key in keys: del now['strings'][key]
        self.assertEqual(now, prior)
        self.assertEqual(digest((ROOT / SCANNER_PATH).read_bytes()), PARENT_SCANNER_SHA256)
        self.assertEqual(len(CURRENT_APPROVED_PATHS), 21)
        self.assertIn(PROFILE_PATH, APPROVED_PATHS)
        self.assertNotIn(SCANNER_PATH, APPROVED_PATHS)


    def test_fixture_root_symlink_is_rejected_before_root_resolution(self):
        raw = (ROOT / CONTRACT_PATH).read_bytes()
        with tempfile.TemporaryDirectory(prefix='category-roam-root-link-') as temporary:
            base = Path(temporary); fixture = base / 'exact47'; fixture.mkdir()
            for path in PROFILE_CONTEXT_INPUTS:
                target = fixture / path; target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(repair_predecessor_fixture_source(path, (ROOT / path).read_bytes(), raw))
            profile_history_inputs(raw, fixture, 'history')
            link = base / 'outside-alias'; link.symlink_to(fixture, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'root itself'):
                profile_history_inputs(raw, link, 'history')
            # This explicitly scoped root guard does not ban system ancestor aliases.
            self.assertFalse(fixture.is_symlink())

    def test_complete_four_file_coherent_repin_cannot_change_frozen_implementation(self):
        import types
        raw = (ROOT / CONTRACT_PATH).read_bytes()
        module = (ROOT / SELF_PATH).read_bytes() + b'\n'
        normalized = module.replace(b"ADMISSION_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'",
                                    b"ADMISSION_FINGERPRINT = '<SELF>'", 1)
        new_pin = digest(normalized)
        module = module.replace(ADMISSION_FINGERPRINT.encode(), new_pin.encode(), 1)
        profile = (ROOT / PROFILE_PATH).read_bytes().replace(ADMISSION_FINGERPRINT.encode(), new_pin.encode(), 1)
        value = json.loads(raw); value['feature_batch_support_sha256'][SELF_PATH] = digest(module)
        value['feature_batch_support_sha256'][PROFILE_PATH] = digest(profile); changed = encode(value)
        runner = (ROOT / RUNNER_PATH).read_bytes().replace(digest(raw).encode(), digest(changed).encode())
        changes = {ROOT / SELF_PATH: module, ROOT / PROFILE_PATH: profile,
                   ROOT / CONTRACT_PATH: changed, ROOT / RUNNER_PATH: runner}
        real = Path.read_bytes
        def read(file): return changes[file] if file in changes else real(file)
        with patch.object(Path, 'read_bytes', read):
            fresh = types.ModuleType('four_file_coherent_repin'); fresh.__file__ = str(ROOT / SELF_PATH)
            exec(compile(module, fresh.__file__, 'exec'), fresh.__dict__)
            with self.assertRaisesRegex(AssertionError, 'external frozen source template'):
                fresh.checked_current(changed, ROOT)

# Exact c2af navigation compile predecessor layer.
NATIVE_PRE_CONTRACT_SHA256 = 'd3fedafc9efe917220f4c52cb4c82d742f840a7307546da35e4da130a80d7fdb'
NATIVE_PRE_FINGERPRINT = '8c8eeec9a9120b261cfe3a6c067c25718e7b5a3b3cb41f5f34897fd11523a37d'
NATIVE_LEAF_PATHS = ('App/ProjectEditIssueNavigation.swift',)
NATIVE_NAV_ROW = {'before_sha256': 'ff473e0c1695a05f3b983e0675f0e7cd431f5b8258dad01b6d1a73f0911b0a2b',
 'after_sha256': '6d10281d7c74e6664404ed359902fd3673873bce0ddd519686dbb521cf29319d',
 'hunks': [{'before': '    struct Destination: Identifiable {\n'
                      '        let id = UUID()\n'
                      '        let capture: Capture\n'
                      '    }',
            'after': '    struct Destination: Identifiable, Hashable {\n'
                     '        let id = UUID()\n'
                     '        let capture: Capture\n'
                     '        nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id '
                     '}\n'
                     '        nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }\n'
                     '    }'}]}
NATIVE_HELPER_ROW = {'before_sha256': '1878c5c48f1da07910178409ca0b927be695e92a462497dc8cd9aa7d9a929aaf',
 'after_sha256': '379ada64233f6a51f52d5ca595c9092632f248e23c50825aa989ff0882fcfd88',
 'hunks': [{'before': "FLOOR_INPUTS = ('App/ProjectThoughtDefinitionsEditor.swift',",
            'after': "FLOOR_INPUTS = ('App/ProjectEditIssueNavigation.swift',\n"
                     " 'App/ProjectThoughtDefinitionsEditor.swift',"},
           {'before': 'def restore_evolution_source(relative, raw):\n'
                      '    return _inverse_row(relative, raw, EVOLUTION_SOURCES[relative])\n',
            'after': 'def restore_evolution_source(relative, raw):\n'
                     "    if relative == 'Questify.xcodeproj/project.pbxproj':\n"
                     '        from Tests.ContractChecks.test_category_roam_registration import '
                     'native_predecessor_source\n'
                     '        try:\n'
                     '            raw = native_predecessor_source(relative, raw)\n'
                     '        except AssertionError as error:\n'
                     '            raise ValueError(str(error)) from error\n'
                     '    return _inverse_row(relative, raw, EVOLUTION_SOURCES[relative])\n'}]}
NATIVE_PRE_SHA256 = {'App/ProjectEditIssueNavigation.swift': 'ff473e0c1695a05f3b983e0675f0e7cd431f5b8258dad01b6d1a73f0911b0a2b',
 'Tests/ContractChecks/test_category_roam_registration.py': '0af9b683f459178b3388921bd593dffd5d1ef4e4916df509e464d6620f5fd501',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '03c1954fe6862fe2d4651384ca6b1b3296382cba7896c6202a82520aadb95b98',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '402c5c67484ca946d65ddd7c77352d7075445fa69064e9ffeb3f98f896cab470',
 'tools/club_customer_directory_admission.py': '1878c5c48f1da07910178409ca0b927be695e92a462497dc8cd9aa7d9a929aaf',
 'tools/run138_editor_readiness.py': '3854d1af7783eeb72ea095e53a0330d2919c823ab0fd349ae623be4206f1a642',
 'Questify.xcodeproj/project.pbxproj': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50',
 'tools/run138_current_source_projection.py': 'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727'}
NATIVE_PRE_SUPPORT = {'App/ProjectEditIssueNavigation.swift': 'ff473e0c1695a05f3b983e0675f0e7cd431f5b8258dad01b6d1a73f0911b0a2b',
 'Tests/ContractChecks/test_category_roam_registration.py': '0af9b683f459178b3388921bd593dffd5d1ef4e4916df509e464d6620f5fd501',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '03c1954fe6862fe2d4651384ca6b1b3296382cba7896c6202a82520aadb95b98',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '402c5c67484ca946d65ddd7c77352d7075445fa69064e9ffeb3f98f896cab470',
 'tools/club_customer_directory_admission.py': '1878c5c48f1da07910178409ca0b927be695e92a462497dc8cd9aa7d9a929aaf'}
NATIVE_CATEGORY_PREFIX_HUNKS = [{'before': 'def uncached_readiness_source(raw):\n',
  'after': 'def uncached_readiness_source(raw):\n    raw = native_readiness_source(raw)\n'},
 {'before': 'def checked_current(raw, root):\n'
            '    """Read all actual current bytes on every call, before any historical cache."""\n'
            '    root = Path(root)\n'
            "    require((root / CONTRACT_PATH).read_bytes() == raw, 'Live current contract differs from "
            "supplied bytes')\n",
  'after': 'def checked_current(raw, root):\n'
           '    """Read all actual current bytes on every call, before any historical cache."""\n'
           '    root = Path(root)\n'
           "    require((root / CONTRACT_PATH).read_bytes() == raw, 'Live current contract differs from "
           "supplied bytes')\n"
           '    require(digest((root / NATIVE_PROJECTION_PATH).read_bytes()) == '
           "NATIVE_PROJECTION_ROW['after_sha256'], 'Changed actual current projection source')\n"},
 {'before': '    try:\n        runner = uncached_readiness_source((root / RUNNER_PATH).read_bytes())\n',
  'after': '    try:\n'
           '        runner = uncached_readiness_source(native_current_readiness_source((root / '
           'RUNNER_PATH).read_bytes()))\n'},
 {'before': 'def repair_predecessor_source(path, raw):\n',
  'after': 'def repair_predecessor_source(path, raw):\n    raw = native_predecessor_source(path, raw)\n'},
 {'before': 'def repair_predecessor_contract(value):\n    value = copy.deepcopy(value)\n',
  'after': 'def repair_predecessor_contract(value):\n    value = native_predecessor_contract(value)\n'},
 {'before': "require(value['feature_batch_support_sha256'].get(path) == digest((ROOT / path).read_bytes()),\n"
            "                'Changed exact parser/property support: ' + path)",
  'after': "require(value['feature_batch_support_sha256'].get(path) == "
           'digest(native_predecessor_source(path, (ROOT / path).read_bytes())),\n'
           "                'Changed exact parser/property support: ' + path)"},
 {'before': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS):\n'
            '            # All 49 physical bytes are read before any predecessor/context reuse.\n'
            '            for path, data in incoming.items():\n'
            "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 49-file "
            "fixture: ' + path)\n"
            '        else:',
  'after': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS):\n'
           '            # All 51 physical inputs precede every predecessor/context reuse.\n'
           '            for path, data in incoming.items():\n'
           "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 51-file "
           "fixture: ' + path)\n"
           '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS):\n'
           '            # This is exactly published c2af49, not current51 with missing inputs.\n'
           '            for path, data in incoming.items():\n'
           '                expected = native_predecessor_fixture_source(path, (ROOT / path).read_bytes(), '
           'current_raw)\n'
           "                require(data == expected, 'Changed/mixed historical c2af49 fixture: ' + path)\n"
           '        else:'},
 {'before': '    contents[PROFILE_PATH] = _profile_preimage(contents[PROFILE_PATH])\n',
  'after': '    contents[PROFILE_PATH] = _profile_preimage((origin / PROFILE_PATH).read_bytes())\n'},
 {'before': '    raw = _inverse_exact((root / path).read_bytes(), PROTECTED_PBX_ROW, path)\n',
  'after': '    raw = _inverse_exact(native_predecessor_source(path, (root / path).read_bytes()), '
           'PROTECTED_PBX_ROW, path)\n'}]
NATIVE_CURRENT_INPUTS = ('App/ProjectEditIssueNavigation.swift', 'tools/run138_current_source_projection.py')
NATIVE_PROJECTION_PATH = 'tools/run138_current_source_projection.py'
NATIVE_PROJECTION_ROW = {'before_sha256': 'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727',
 'after_sha256': '7e14668c3ab789f3903971a8de30a828c1cac36c6755d67f81e92ef29356c7f1',
 'hunks': [{'before': "current.contract(root)['entry_contract_sha256']",
            'after': "current.contract_member('entry_contract_sha256', root=root)"},
           {'before': "planning().contract(root)['feature_batch_sources'].get(relative)",
            'after': "planning().contract_member('feature_batch_sources', relative, root)"}]}
NATIVE_READINESS_HUNKS = [{'before': 'def original_source(relative, raw, root=ROOT):\n',
  'after': 'def contract_member(section, member=None, root=ROOT):\n'
           '    """Copy one validated member without copying unrelated contract branches."""\n'
           "    raw = (Path(root) / 'tools/run138_editor_readiness_contract.json').read_bytes()\n"
           '    if digest(raw) != CONTRACT_SHA256:\n'
           "        raise ValueError('Unreviewed current readiness planning contract')\n"
           '    value = _parsed_contract(raw)[section]\n'
           '    if member is not None:\n'
           '        value = value.get(member)\n'
           '    return deepcopy(value)\n'
           '\n'
           '\n'
           'def original_source(relative, raw, root=ROOT):\n'}]
NATIVE_READINESS_AFTER_SHA256 = '1de7d2a1238c7a6057ef592a8a272844df00f239e43cccbcfd136dd5588d77e1'
NATIVE_PBX_REPAIR_ROW = {'before_sha256': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50',
 'after_sha256': '211fe2e6ded15704a582d9340bb45d198620afe118b2add40d60679820b64f65',
 'hunks': [{'before': '\t\t\t\t"4A57125287F6AEF51C738309",\n'
                      '\t\t\t\t"2A4F7E878F7689C47FE34583",\n'
                      '\t\t\t\t"791E6BF02CD332B0299A3459",\n',
            'after': '\t\t\t\t"4A57125287F6AEF51C738309",\n\t\t\t\t"791E6BF02CD332B0299A3459",\n'},
           {'before': '\t\t\t\t"525EE1679C85AA5272DE7DF4",\n\t\t\t\t"8388C7D38F87D95825320119",\n',
            'after': '\t\t\t\t"525EE1679C85AA5272DE7DF4",\n'
                     '\t\t\t\t"547DD20422C04B364B7AAC62",\n'
                     '\t\t\t\t"8388C7D38F87D95825320119",\n'},
           {'before': '\t\t};\n'
                      '\t\t"2A4F7E878F7689C47FE34583" = {\n'
                      '\t\t\t"isa" = "PBXFileReference";\n'
                      '\t\t\t"lastKnownFileType" = "sourcecode.swift";\n'
                      '\t\t\t"path" = "Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift";\n'
                      '\t\t\t"sourceTree" = "<group>";\n'
                      '\t\t};\n'
                      '\t\t"4FF7D0B5D5B04E3FAAE97D5A" = {\n'
                      '\t\t\t"isa" = "PBXBuildFile";\n'
                      '\t\t\t"fileRef" = "2A4F7E878F7689C47FE34583";\n'
                      '\t\t};\n'
                      '\t\t"791E6BF02CD332B0299A3459" = {\n',
            'after': '\t\t};\n\t\t"791E6BF02CD332B0299A3459" = {\n'},
           {'before': '\t\t\t"fileRef" = "525EE1679C85AA5272DE7DF4";\n\t\t};\n',
            'after': '\t\t\t"fileRef" = "525EE1679C85AA5272DE7DF4";\n'
                     '\t\t};\n'
                     '\t\t"547DD20422C04B364B7AAC62" = {\n'
                     '\t\t\t"isa" = "PBXFileReference";\n'
                     '\t\t\t"lastKnownFileType" = "sourcecode.swift";\n'
                     '\t\t\t"path" = "Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift";\n'
                     '\t\t\t"sourceTree" = "<group>";\n'
                     '\t\t};\n'
                     '\t\t"7FEA355EA4D0539C58BA2CC1" = {\n'
                     '\t\t\t"isa" = "PBXBuildFile";\n'
                     '\t\t\t"fileRef" = "547DD20422C04B364B7AAC62";\n'
                     '\t\t};\n'},
           {'before': '\t\t\t"files" = (\n'
                      '\t\t\t\t"4FF7D0B5D5B04E3FAAE97D5A",\n'
                      '\t\t\t\t"19EC95F64576113ABFA6995C",\n',
            'after': '\t\t\t"files" = (\n\t\t\t\t"19EC95F64576113ABFA6995C",\n'},
           {'before': '\t\t\t\t"EBEC019FDEAE55ACE06179C2",\n\t\t\t\t"EF9ECDC20F32FC34BCA977BC",\n',
            'after': '\t\t\t\t"EBEC019FDEAE55ACE06179C2",\n'
                     '\t\t\t\t"7FEA355EA4D0539C58BA2CC1",\n'
                     '\t\t\t\t"EF9ECDC20F32FC34BCA977BC",\n'}]}
NATIVE_PRE_PBX_ROW_SHA256 = '50b8c92d4fce7371b9df3010ae38d0b4372e1b9f4432657dd553dd27c91cb36f'

def _native_category_preimage(raw):
    marker = b'\n# Exact c2af navigation compile predecessor layer.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown native layer source boundary')
    prefix, _ = raw.split(marker, 1)
    for hunk in reversed(NATIVE_CATEGORY_PREFIX_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        require(prefix.count(after) == 1, 'Missing/repeated native source interface span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + DESCRIPTION_PRE_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Unknown native admission fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + NATIVE_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == NATIVE_PRE_SHA256[SELF_PATH], 'Complete c2af admission source not restored')
    return old


def native_current_readiness_source(raw):
    """Current admission requires the entire reviewed member-copy implementation."""
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
    if len(pins) != 1 or digest(raw.replace(pins[0], NATIVE_PRE_CONTRACT_SHA256.encode(), 1)) != NATIVE_READINESS_AFTER_SHA256:
        raise ValueError('Changed complete current readiness member-copy source')
    return raw


def native_readiness_source(raw):
    """Remove only the exact member-copy optimization, retaining the live pin."""
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
    if len(pins) != 1:
        raise ValueError('Unknown native readiness contract pin')
    normalized = raw.replace(pins[0], NATIVE_PRE_CONTRACT_SHA256.encode(), 1)
    if digest(normalized) == NATIVE_PRE_SHA256[RUNNER_PATH]:
        return raw  # The explicit c2af predecessor has no member-copy extension.
    for hunk in reversed(NATIVE_READINESS_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        if raw.count(after) != 1:
            raise ValueError('Unknown exact readiness member-copy source span')
        raw = raw.replace(after, before, 1)
    if digest(raw.replace(pins[0], NATIVE_PRE_CONTRACT_SHA256.encode(), 1)) != NATIVE_PRE_SHA256[RUNNER_PATH]:
        raise ValueError('Complete c2af readiness member-copy predecessor not restored')
    return raw


def native_predecessor_source(path, raw):
    """Exact historical bytes only; current admission remains checked_current."""
    if path in NATIVE_PRE_SHA256 and digest(raw) == NATIVE_PRE_SHA256[path]:
        return raw  # Explicit exact c2af historical input.
    raw = description_predecessor_source(path, raw)
    if path not in NATIVE_PRE_SHA256:
        return raw
    if digest(raw) == NATIVE_PRE_SHA256[path]:
        return raw
    if path == NATIVE_LEAF_PATHS[0]:
        old = _inverse_exact(raw, NATIVE_NAV_ROW, path)
    elif path == 'Questify.xcodeproj/project.pbxproj':
        old = _inverse_exact(raw, NATIVE_PBX_REPAIR_ROW, path)
    elif path == 'tools/club_customer_directory_admission.py':
        old = _inverse_exact(raw, NATIVE_HELPER_ROW, path)
    elif path == NATIVE_PROJECTION_PATH:
        old = _inverse_exact(raw, NATIVE_PROJECTION_ROW, path)
    elif path == SELF_PATH:
        old = _native_category_preimage(raw)
    elif path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + DESCRIPTION_PRE_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Unknown native profile source pin')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + NATIVE_PRE_FINGERPRINT.encode() + b"'", 1)
    elif path == RUNNER_PATH:
        raw = native_readiness_source(raw)
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
        require(len(pins) == 1, 'Unknown native readiness pin')
        old = raw.replace(pins[0], NATIVE_PRE_CONTRACT_SHA256.encode(), 1)
    elif path == CATEGORY_GATE:
        normalized, source = _decoded_external_template(raw)
        require(source == description_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown native complete external template')
        old_source = _native_category_preimage(source)
        encoded = encode_frozen_source(old_source).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
    else:
        raise AssertionError('Unreviewed native predecessor path')
    require(digest(old) == NATIVE_PRE_SHA256[path], 'Complete c2af source not restored: ' + path)
    return old


def native_predecessor_contract(value):
    """Authenticate new bytes, then restore the entire published c2af contract."""
    if digest(encode(value)) == NATIVE_PRE_CONTRACT_SHA256:
        return copy.deepcopy(value)  # Explicit exact c2af historical value.
    value = description_predecessor_contract(value)
    if digest(encode(value)) == NATIVE_PRE_CONTRACT_SHA256:
        return value  # Explicit historical-only value, never current admission.
    path = NATIVE_LEAF_PATHS[0]
    require(value['feature_batch_sources'].get(path) == NATIVE_NAV_ROW, 'Unknown native UUID-only source row')
    require(digest((ROOT / path).read_bytes()) == NATIVE_NAV_ROW['after_sha256'], 'Native current Navigation bytes changed')
    require(digest(description_predecessor_source(DESCRIPTION_HELPER_PATH, (ROOT / DESCRIPTION_HELPER_PATH).read_bytes())) == NATIVE_HELPER_ROW['after_sha256'],
            'Native current club fixture input changed')
    require(value['entry_projection_module_sha256'] == NATIVE_PROJECTION_ROW['after_sha256'],
            'Unknown exact current member-copy projection pin')
    projection = actor_predecessor_source(NATIVE_PROJECTION_PATH, (ROOT / NATIVE_PROJECTION_PATH).read_bytes())
    require(digest(projection) == NATIVE_PROJECTION_ROW['after_sha256'], 'Changed actual member-copy projection bytes')
    require(digest(native_predecessor_source(NATIVE_PROJECTION_PATH, projection)) == NATIVE_PROJECTION_ROW['before_sha256'],
            'Complete c2af projection source not restored')
    value['entry_projection_module_sha256'] = NATIVE_PROJECTION_ROW['before_sha256']
    pbx = 'Questify.xcodeproj/project.pbxproj'
    row = value['feature_batch_sources'][pbx]
    hunks = NATIVE_PBX_REPAIR_ROW['hunks']
    require(digest((ROOT / pbx).read_bytes()) == NATIVE_PBX_REPAIR_ROW['after_sha256'], 'Native canonical PBX bytes changed')
    require(row['after_sha256'] == NATIVE_PBX_REPAIR_ROW['after_sha256'] and row['hunks'][-len(hunks):] == hunks,
            'Unknown canonical PBX inverse extension')
    row['after_sha256'] = NATIVE_PBX_REPAIR_ROW['before_sha256']
    del row['hunks'][-len(hunks):]
    require(digest(encode(row)) == NATIVE_PRE_PBX_ROW_SHA256, 'Complete original209 PBX row not restored')
    for path, expected in NATIVE_PRE_SUPPORT.items():
        raw = description_predecessor_source(path, (ROOT / path).read_bytes())
        require(value['feature_batch_support_sha256'].get(path) == digest(raw), 'Native current support changed: ' + path)
        require(digest(native_predecessor_source(path, raw)) == expected, 'Unknown native predecessor support: ' + path)
        value['feature_batch_support_sha256'][path] = expected
    del value['feature_batch_sources'][NATIVE_LEAF_PATHS[0]]
    require(digest(encode(value)) == NATIVE_PRE_CONTRACT_SHA256, 'Complete published c2af contract not restored')
    return value


def native_predecessor_fixture_source(path, raw, current_contract):
    """Construct explicit c2af49 fixture bytes; never backfill a current root."""
    if path == CONTRACT_PATH:
        require(raw == current_contract, 'Mixed native current fixture contract')
        return encode(native_predecessor_contract(json.loads(raw)))
    return native_predecessor_source(path, raw)

# Exact 7b node-description initialization predecessor layer.
DESCRIPTION_PRE_CONTRACT_SHA256 = '9c26993734c6ba8d4623165187cb0cfcebc1ff20e3c9209da7a2982099ee2cb6'
DESCRIPTION_PRE_FINGERPRINT = 'd6b62d85bd3c184e3b89eb38de69f5d73cf2395b8777b208eaf4d5d677b52d17'
DESCRIPTION_LEAF_PATH = 'App/ProjectEditNodeDescriptionField.swift'
DESCRIPTION_HELPER_PATH = 'tools/club_customer_directory_admission.py'
DESCRIPTION_LEAF_ROW = {'before_sha256': '663f5aa34981ca0e3ec9207e165140b78bb8c8a3858314bf2cda4d836599f2e3',
 'after_sha256': 'c03d2b762a9c339449f799214b356180ead19d9c6bc9065ff2c25e0cabc77053',
 'hunks': [{'before': '        text = source.node.wrappedValue.description; acknowledgedBytes = '
                      'Data(text.utf8)\n',
            'after': '        let initialText = source.node.wrappedValue.description\n'
                     '        text = initialText; acknowledgedBytes = Data(initialText.utf8)\n'}]}
DESCRIPTION_HELPER_ROW = {'before_sha256': '379ada64233f6a51f52d5ca595c9092632f248e23c50825aa989ff0882fcfd88',
 'after_sha256': 'b8c6be27289110f7bf75d01d28fd41d9778b90dd7c32b78cf0ff849aa1916977',
 'hunks': [{'before': "FLOOR_INPUTS = ('App/ProjectEditIssueNavigation.swift',\n",
            'after': "FLOOR_INPUTS = ('App/ProjectEditNodeDescriptionField.swift',\n"
                     " 'tools/run138_current_source_projection.py',\n"
                     " 'App/ProjectEditIssueNavigation.swift',\n"}]}
DESCRIPTION_PRE_SHA256 = {'App/ProjectEditNodeDescriptionField.swift': '663f5aa34981ca0e3ec9207e165140b78bb8c8a3858314bf2cda4d836599f2e3',
 'tools/club_customer_directory_admission.py': '379ada64233f6a51f52d5ca595c9092632f248e23c50825aa989ff0882fcfd88',
 'Tests/ContractChecks/test_category_roam_registration.py': '04ee74c0f01805cc61a87a4019c300d10f829e63d66561a2d830264e4cde5afb',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '67ea1752863c6a805623784675eb3f93b300242d5a303ab4962c038c5499546e',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '17fa92c7b8a10193097c9e6208cd320576bb415d78c046825c51286905cf0a0d',
 'tools/run138_editor_readiness.py': '87c6810802742e1ca8f1978ab77b1db70981f4039a3f6262453a92df58340845'}
DESCRIPTION_PRE_SUPPORT = {'App/ProjectEditNodeDescriptionField.swift': '663f5aa34981ca0e3ec9207e165140b78bb8c8a3858314bf2cda4d836599f2e3',
 'tools/club_customer_directory_admission.py': '379ada64233f6a51f52d5ca595c9092632f248e23c50825aa989ff0882fcfd88',
 'Tests/ContractChecks/test_category_roam_registration.py': '04ee74c0f01805cc61a87a4019c300d10f829e63d66561a2d830264e4cde5afb',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '67ea1752863c6a805623784675eb3f93b300242d5a303ab4962c038c5499546e',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '17fa92c7b8a10193097c9e6208cd320576bb415d78c046825c51286905cf0a0d'}
DESCRIPTION_CATEGORY_PREFIX_HUNKS = [{'before': 'def native_predecessor_source(path, raw):\n'
            '    """Exact historical bytes only; current admission remains checked_current."""\n',
  'after': 'def native_predecessor_source(path, raw):\n'
           '    """Exact historical bytes only; current admission remains checked_current."""\n'
           '    if path in NATIVE_PRE_SHA256 and digest(raw) == NATIVE_PRE_SHA256[path]:\n'
           '        return raw  # Explicit exact c2af historical input.\n'
           '    raw = description_predecessor_source(path, raw)\n'},
 {'before': 'def native_predecessor_contract(value):\n'
            '    """Authenticate new bytes, then restore the entire published c2af contract."""\n'
            '    value = copy.deepcopy(value)\n',
  'after': 'def native_predecessor_contract(value):\n'
           '    """Authenticate new bytes, then restore the entire published c2af contract."""\n'
           '    if digest(encode(value)) == NATIVE_PRE_CONTRACT_SHA256:\n'
           '        return copy.deepcopy(value)  # Explicit exact c2af historical value.\n'
           '    value = description_predecessor_contract(value)\n'},
 {'before': "    require(digest((ROOT / 'tools/club_customer_directory_admission.py').read_bytes()) == "
            "NATIVE_HELPER_ROW['after_sha256'],\n",
  'after': '    require(digest(description_predecessor_source(DESCRIPTION_HELPER_PATH, (ROOT / '
           "DESCRIPTION_HELPER_PATH).read_bytes())) == NATIVE_HELPER_ROW['after_sha256'],\n"},
 {'before': '    for path, expected in NATIVE_PRE_SUPPORT.items():\n'
            '        raw = (ROOT / path).read_bytes()\n',
  'after': '    for path, expected in NATIVE_PRE_SUPPORT.items():\n'
           '        raw = description_predecessor_source(path, (ROOT / path).read_bytes())\n'},
 {'before': '    slot = b"ADMISSION_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            "    require(prefix.count(slot) == 1, 'Unknown native admission fingerprint slot')\n",
  'after': '    slot = b"ADMISSION_FINGERPRINT = \'" + DESCRIPTION_PRE_FINGERPRINT.encode() + b"\'"\n'
           "    require(prefix.count(slot) == 1, 'Unknown native admission fingerprint slot')\n"},
 {'before': '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            "        require(raw.count(slot) == 1, 'Unknown native profile source pin')\n",
  'after': '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + DESCRIPTION_PRE_FINGERPRINT.encode() + '
           'b"\'"\n'
           "        require(raw.count(slot) == 1, 'Unknown native profile source pin')\n"},
 {'before': "        require(source == (ROOT / SELF_PATH).read_bytes(), 'Unknown native complete external "
            "template')\n",
  'after': '        require(source == description_predecessor_source(SELF_PATH, (ROOT / '
           "SELF_PATH).read_bytes()), 'Unknown native complete external template')\n"},
 {'before': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
            'set(NATIVE_CURRENT_INPUTS):\n'
            '            # All 51 physical inputs precede every predecessor/context reuse.\n'
            '            for path, data in incoming.items():\n'
            "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 51-file "
            "fixture: ' + path)\n"
            '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS):',
  'after': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH}:\n'
           '            # All 52 physical current inputs precede every predecessor/cache reuse.\n'
           '            for path, data in incoming.items():\n'
           "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 52-file "
           "fixture: ' + path)\n"
           '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS):\n'
           '            # Exactly published 7b51; missing-current52 is never backfilled.\n'
           '            for path, data in incoming.items():\n'
           '                expected = description_predecessor_fixture_source(path, (ROOT / '
           'path).read_bytes(), current_raw)\n'
           "                require(data == expected, 'Changed/mixed historical 7b51 fixture: ' + path)\n"
           '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS):'},
 {'before': '    value = json.loads(raw)\n'
            "    require(encode(value) == raw, 'Noncanonical/duplicate current contract')\n",
  'after': '    value = json.loads(raw)\n'
           "    require(encode(value) == raw, 'Noncanonical/duplicate current contract')\n"
           '    description_current_inputs(value, root)\n'}]

def _description_category_preimage(raw):
    marker = b'\n# Exact 7b node-description initialization predecessor layer.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == ACTOR_PRE_SHA256[SELF_PATH], 'Changed complete description admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown description layer source boundary')
    prefix, _ = raw.split(marker, 1)
    for hunk in reversed(DESCRIPTION_CATEGORY_PREFIX_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        require(prefix.count(after) == 1, 'Missing/repeated description source interface span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + ACTOR_PRE_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Unknown description admission fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + DESCRIPTION_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == DESCRIPTION_PRE_SHA256[SELF_PATH], 'Complete published 7b admission source not restored')
    return old


def description_predecessor_source(path, raw):
    """Exact complete published 7b bytes; never a current-input admission bypass."""
    if path in DESCRIPTION_PRE_SHA256 and digest(raw) == DESCRIPTION_PRE_SHA256[path]:
        return raw  # Explicit exact 7b historical input.
    raw = actor_predecessor_source(path, raw)
    if path not in DESCRIPTION_PRE_SHA256:
        return raw
    if digest(raw) == DESCRIPTION_PRE_SHA256[path]:
        return raw  # Explicit historical-only interface; current checks require new bytes.
    if path == DESCRIPTION_LEAF_PATH:
        old = _inverse_exact(raw, DESCRIPTION_LEAF_ROW, path)
    elif path == DESCRIPTION_HELPER_PATH:
        old = _inverse_exact(raw, DESCRIPTION_HELPER_ROW, path)
    elif path == SELF_PATH:
        old = _description_category_preimage(raw)
    elif path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + ACTOR_PRE_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Unknown description profile source pin')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + DESCRIPTION_PRE_FINGERPRINT.encode() + b"'", 1)
    elif path == RUNNER_PATH:
        native_current_readiness_source(raw)
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
        require(len(pins) == 1, 'Unknown description readiness pin')
        old = raw.replace(pins[0], DESCRIPTION_PRE_CONTRACT_SHA256.encode(), 1)
    elif path == CATEGORY_GATE:
        normalized, source = _decoded_external_template(raw)
        require(source == actor_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown description complete external template')
        old_source = _description_category_preimage(source)
        encoded = encode_frozen_source(old_source).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
    else:
        raise AssertionError('Unreviewed description predecessor path')
    require(digest(old) == DESCRIPTION_PRE_SHA256[path], 'Complete published 7b source not restored: ' + path)
    return old


def description_current_inputs(value, root=ROOT):
    """Authenticate actual actor inputs before checking exact published42 bytes."""
    root = Path(root)
    require(not root.is_symlink(), 'Description current root is a symlink')
    actual = (root / CONTRACT_PATH).read_bytes()
    actor_current_inputs(json.loads(actual), root)
    value = actor_predecessor_contract(value, root)
    raw = encode(value)
    require(digest(raw) == ACTOR_PRE_CONTRACT_SHA256, 'Changed or mixed actual description contract')
    contents = {}
    for path in DESCRIPTION_PRE_SHA256:
        file = root / path
        require(not file.is_symlink() and file.is_file() and file.resolve().is_relative_to(root.resolve()),
                'Missing, escaped or symlinked description current input: ' + path)
        contents[path] = actor_predecessor_source(path, file.read_bytes())
    runner = contents[RUNNER_PATH]
    native_current_readiness_source(runner)
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete description contract pin')
    module = contents[SELF_PATH]
    require(digest(module) == ACTOR_PRE_SHA256[SELF_PATH], 'Loaded description admission differs from exact 42 bytes')
    _, template = _decoded_external_template(contents[CATEGORY_GATE])
    require(template == module, 'Exact 42 description external source template differs')
    slot = b"ADMISSION_FINGERPRINT = '" + ACTOR_PRE_FINGERPRINT.encode() + b"'"
    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '<SELF>'", 1)) == ACTOR_PRE_FINGERPRINT,
            'Changed complete description admission fingerprint')
    require(value['feature_batch_sources'].get(DESCRIPTION_LEAF_PATH) == DESCRIPTION_LEAF_ROW,
            'Unknown exact description initialization inverse')
    require(digest(contents[DESCRIPTION_LEAF_PATH]) == DESCRIPTION_LEAF_ROW['after_sha256'],
            'Old or changed current description initializer')
    require(digest(contents[DESCRIPTION_HELPER_PATH]) == DESCRIPTION_HELPER_ROW['after_sha256'],
            'Old or changed current description fixture producer')
    for path, expected in DESCRIPTION_PRE_SUPPORT.items():
        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),
                'Changed current description support: ' + path)
        require(digest(description_predecessor_source(path, contents[path])) == expected,
                'Unknown complete description support predecessor: ' + path)
    require(digest(description_predecessor_source(RUNNER_PATH, runner)) == DESCRIPTION_PRE_SHA256[RUNNER_PATH],
            'Changed complete description readiness implementation')
    return contents


def description_predecessor_contract(value, root=ROOT):
    """Admit actual new bytes, then restore the entire immutable 7b contract."""
    value = copy.deepcopy(value)
    if digest(encode(value)) == DESCRIPTION_PRE_CONTRACT_SHA256:
        return value  # Exact historical-only contract; checked_current never accepts it as current.
    value = actor_predecessor_contract(value, root)
    description_current_inputs(value, root)
    require(value['feature_batch_sources'].pop(DESCRIPTION_LEAF_PATH) == DESCRIPTION_LEAF_ROW,
            'Missing complete description inverse row')
    for path, expected in DESCRIPTION_PRE_SUPPORT.items():
        value['feature_batch_support_sha256'][path] = expected
    require(digest(encode(value)) == DESCRIPTION_PRE_CONTRACT_SHA256,
            'Complete published 7b readiness contract not restored')
    return value


def description_predecessor_fixture_source(path, raw, current_contract):
    """Build genuine published 7b51 inputs, never fill a missing current52 file."""
    if path == CONTRACT_PATH:
        require(raw == current_contract, 'Mixed description current fixture contract')
        return encode(description_predecessor_contract(json.loads(raw)))
    return description_predecessor_source(path, raw)

# Exact 42 social ReaderKey actor predecessor layer.
ACTOR_PRE_CONTRACT_SHA256 = '6fa7fd18b5000d3843f4c5809d58cd97f0b40dd0b3b41ad933583aa6250522e4'
ACTOR_PRE_FINGERPRINT = 'c2799c63edc88cd73f5902565bb3ee5c59b757c41dd4db428e664e46e09936f1'
ACTOR_LEAF_PATH = 'App/SocialGuideTemplateSection.swift'
ACTOR_HELPER_PATH = 'tools/club_customer_directory_admission.py'
ACTOR_LEAF_ROW = {'before_sha256': 'f79b53c8f0ab4ecdd4a21c2d23fe6a1c7b1040c50680dd6b6c1093cdcb3f2c5b',
 'after_sha256': '0e14cc76c72416cf152f8edbd02383251b2671952f958a18af078e883f4ffc51',
 'hunks': [{'before': '        init(_ reader: any DiscoveryReading) {\n',
            'after': '        @MainActor init(_ reader: any DiscoveryReading) {\n'}]}
ACTOR_HELPER_ROW = {'before_sha256': 'b8c6be27289110f7bf75d01d28fd41d9778b90dd7c32b78cf0ff849aa1916977',
 'after_sha256': '7b2bba4759677e0091b5149a7fc46096280b95ac2b7e94cd77481a24570afb35',
 'hunks': [{'before': "FLOOR_INPUTS = ('App/ProjectEditNodeDescriptionField.swift',\n",
            'after': "FLOOR_INPUTS = ('App/SocialGuideTemplateSection.swift',\n"
                     " 'App/ProjectEditNodeDescriptionField.swift',\n"}]}
ACTOR_PROJECTION_PATH = 'tools/run138_current_source_projection.py'
ACTOR_PROJECTION_ROW = {'before_sha256': '7e14668c3ab789f3903971a8de30a828c1cac36c6755d67f81e92ef29356c7f1',
 'after_sha256': '3980907d0a3d33e40f229c6f856ac78024b18498ea7c3f4dcd28d34862f8b280',
 'hunks': [{'before': "        if relative.startswith('Tests/AppUITests/') or (stage == 'review' and "
                      "relative == 'App/ProjectEditView.swift'):\n",
            'after': "        if relative.startswith('Tests/AppUITests/') or (stage == 'review' and relative "
                     "in {'App/ProjectEditView.swift', "
                     "'Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift', "
                     "'Core/ProjectEditCoordinator.swift'}):\n"}]}
ACTOR_PRE_SHA256 = {'App/SocialGuideTemplateSection.swift': 'f79b53c8f0ab4ecdd4a21c2d23fe6a1c7b1040c50680dd6b6c1093cdcb3f2c5b',
 'tools/club_customer_directory_admission.py': 'b8c6be27289110f7bf75d01d28fd41d9778b90dd7c32b78cf0ff849aa1916977',
 'Tests/ContractChecks/test_category_roam_registration.py': '7bc7de4110dedfc746145e7a988ab7fad88c9c562fcf524a66596a7d1d8ee2ac',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '5b754f40bd7cb9532edcfce645a1855a9f6a00c5499027de57744411fd95d079',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '8e7db4c7fb4c6f177d4a83afbcc1cf625d36143bba654be8a49db5e4c200c469',
 'tools/run138_editor_readiness.py': '3f29bd3e24bbcaa805f97b5cef98bfed1bf50d511e7bd1ef9759abb952a01f5d',
 'tools/run138_current_source_projection.py': '7e14668c3ab789f3903971a8de30a828c1cac36c6755d67f81e92ef29356c7f1'}
ACTOR_PRE_SUPPORT = {'App/SocialGuideTemplateSection.swift': 'f79b53c8f0ab4ecdd4a21c2d23fe6a1c7b1040c50680dd6b6c1093cdcb3f2c5b',
 'tools/club_customer_directory_admission.py': 'b8c6be27289110f7bf75d01d28fd41d9778b90dd7c32b78cf0ff849aa1916977',
 'Tests/ContractChecks/test_category_roam_registration.py': '7bc7de4110dedfc746145e7a988ab7fad88c9c562fcf524a66596a7d1d8ee2ac',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '5b754f40bd7cb9532edcfce645a1855a9f6a00c5499027de57744411fd95d079',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '8e7db4c7fb4c6f177d4a83afbcc1cf625d36143bba654be8a49db5e4c200c469'}
ACTOR_CATEGORY_PREFIX_HUNKS = [{'before': '    require(digest((root / NATIVE_PROJECTION_PATH).read_bytes()) == '
            "NATIVE_PROJECTION_ROW['after_sha256'], 'Changed actual current projection source')\n",
  'after': '    require(digest((root / NATIVE_PROJECTION_PATH).read_bytes()) == '
           "ACTOR_PROJECTION_ROW['after_sha256'], 'Changed actual current projection source')\n"},
 {'before': '    projection = (ROOT / NATIVE_PROJECTION_PATH).read_bytes()\n',
  'after': '    projection = actor_predecessor_source(NATIVE_PROJECTION_PATH, (ROOT / '
           'NATIVE_PROJECTION_PATH).read_bytes())\n'},
 {'before': 'def description_predecessor_source(path, raw):\n'
            '    """Exact complete published 7b bytes; never a current-input admission bypass."""\n',
  'after': 'def description_predecessor_source(path, raw):\n'
           '    """Exact complete published 7b bytes; never a current-input admission bypass."""\n'
           '    if path in DESCRIPTION_PRE_SHA256 and digest(raw) == DESCRIPTION_PRE_SHA256[path]:\n'
           '        return raw  # Explicit exact 7b historical input.\n'
           '    raw = actor_predecessor_source(path, raw)\n'},
 {'before': "    require(digest(raw) == IMPLEMENTATION_SHA256, 'Changed complete description admission "
            "source')\n",
  'after': "    require(digest(raw) == ACTOR_PRE_SHA256[SELF_PATH], 'Changed complete description admission "
           "source')\n"},
 {'before': '    slot = b"ADMISSION_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            "    require(prefix.count(slot) == 1, 'Unknown description admission fingerprint slot')\n",
  'after': '    slot = b"ADMISSION_FINGERPRINT = \'" + ACTOR_PRE_FINGERPRINT.encode() + b"\'"\n'
           "    require(prefix.count(slot) == 1, 'Unknown description admission fingerprint slot')\n"},
 {'before': '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            "        require(raw.count(slot) == 1, 'Unknown description profile source pin')\n",
  'after': '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ACTOR_PRE_FINGERPRINT.encode() + b"\'"\n'
           "        require(raw.count(slot) == 1, 'Unknown description profile source pin')\n"},
 {'before': "        require(source == (ROOT / SELF_PATH).read_bytes(), 'Unknown description complete "
            "external template')\n",
  'after': '        require(source == actor_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), '
           "'Unknown description complete external template')\n"},
 {'before': '    description_current_inputs(value, root)\n'
            "    require(value['feature_batch_sources'].pop(DESCRIPTION_LEAF_PATH) == "
            'DESCRIPTION_LEAF_ROW,\n',
  'after': '    value = actor_predecessor_contract(value, root)\n'
           '    description_current_inputs(value, root)\n'
           "    require(value['feature_batch_sources'].pop(DESCRIPTION_LEAF_PATH) == "
           'DESCRIPTION_LEAF_ROW,\n'},
 {'before': 'def description_current_inputs(value, root=ROOT):\n'
            '    """Re-read every actual new boundary member before any old value or cache."""\n'
            '    root = Path(root)\n'
            "    require(not root.is_symlink(), 'Description current root is a symlink')\n"
            '    contents = {}\n'
            '    for path in DESCRIPTION_PRE_SHA256:\n'
            '        file = root / path\n'
            '        require(not file.is_symlink() and file.is_file() and '
            'file.resolve().is_relative_to(root.resolve()),\n'
            "                'Missing, escaped or symlinked description current input: ' + path)\n"
            '        contents[path] = file.read_bytes()\n'
            '    raw = (root / CONTRACT_PATH).read_bytes()\n'
            "    require(encode(value) == raw, 'Changed or mixed actual description contract')\n"
            '    runner = contents[RUNNER_PATH]\n'
            '    native_current_readiness_source(runner)\n'
            '    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", runner)\n'
            "    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete description "
            "contract pin')\n"
            '    module = contents[SELF_PATH]\n'
            "    require(digest(module) == IMPLEMENTATION_SHA256, 'Loaded description admission differs from "
            "current bytes')\n"
            '    validate_external_source_template(root, module)\n'
            '    slot = b"ADMISSION_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            '    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '
            '\'<SELF>\'", 1)) == ADMISSION_FINGERPRINT,\n'
            "            'Changed complete description admission fingerprint')\n"
            "    require(value['feature_batch_sources'].get(DESCRIPTION_LEAF_PATH) == DESCRIPTION_LEAF_ROW,\n"
            "            'Unknown exact description initialization inverse')\n"
            "    require(digest(contents[DESCRIPTION_LEAF_PATH]) == DESCRIPTION_LEAF_ROW['after_sha256'],\n"
            "            'Old or changed current description initializer')\n"
            '    require(digest(contents[DESCRIPTION_HELPER_PATH]) == '
            "DESCRIPTION_HELPER_ROW['after_sha256'],\n"
            "            'Old or changed current description fixture producer')\n"
            '    for path, expected in DESCRIPTION_PRE_SUPPORT.items():\n'
            "        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),\n"
            "                'Changed current description support: ' + path)\n"
            '        require(digest(description_predecessor_source(path, contents[path])) == expected,\n'
            "                'Unknown complete description support predecessor: ' + path)\n"
            '    require(digest(description_predecessor_source(RUNNER_PATH, runner)) == '
            'DESCRIPTION_PRE_SHA256[RUNNER_PATH],\n'
            "            'Changed complete description readiness implementation')\n"
            '    return contents',
  'after': 'def description_current_inputs(value, root=ROOT):\n'
           '    """Authenticate actual actor inputs before checking exact published42 bytes."""\n'
           '    root = Path(root)\n'
           "    require(not root.is_symlink(), 'Description current root is a symlink')\n"
           '    actual = (root / CONTRACT_PATH).read_bytes()\n'
           '    actor_current_inputs(json.loads(actual), root)\n'
           '    value = actor_predecessor_contract(value, root)\n'
           '    raw = encode(value)\n'
           "    require(digest(raw) == ACTOR_PRE_CONTRACT_SHA256, 'Changed or mixed actual description "
           "contract')\n"
           '    contents = {}\n'
           '    for path in DESCRIPTION_PRE_SHA256:\n'
           '        file = root / path\n'
           '        require(not file.is_symlink() and file.is_file() and '
           'file.resolve().is_relative_to(root.resolve()),\n'
           "                'Missing, escaped or symlinked description current input: ' + path)\n"
           '        contents[path] = actor_predecessor_source(path, file.read_bytes())\n'
           '    runner = contents[RUNNER_PATH]\n'
           '    native_current_readiness_source(runner)\n'
           '    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", runner)\n'
           "    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete description "
           "contract pin')\n"
           '    module = contents[SELF_PATH]\n'
           "    require(digest(module) == ACTOR_PRE_SHA256[SELF_PATH], 'Loaded description admission differs "
           "from exact 42 bytes')\n"
           '    _, template = _decoded_external_template(contents[CATEGORY_GATE])\n'
           "    require(template == module, 'Exact 42 description external source template differs')\n"
           '    slot = b"ADMISSION_FINGERPRINT = \'" + ACTOR_PRE_FINGERPRINT.encode() + b"\'"\n'
           '    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '
           '\'<SELF>\'", 1)) == ACTOR_PRE_FINGERPRINT,\n'
           "            'Changed complete description admission fingerprint')\n"
           "    require(value['feature_batch_sources'].get(DESCRIPTION_LEAF_PATH) == DESCRIPTION_LEAF_ROW,\n"
           "            'Unknown exact description initialization inverse')\n"
           "    require(digest(contents[DESCRIPTION_LEAF_PATH]) == DESCRIPTION_LEAF_ROW['after_sha256'],\n"
           "            'Old or changed current description initializer')\n"
           '    require(digest(contents[DESCRIPTION_HELPER_PATH]) == '
           "DESCRIPTION_HELPER_ROW['after_sha256'],\n"
           "            'Old or changed current description fixture producer')\n"
           '    for path, expected in DESCRIPTION_PRE_SUPPORT.items():\n'
           "        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),\n"
           "                'Changed current description support: ' + path)\n"
           '        require(digest(description_predecessor_source(path, contents[path])) == expected,\n'
           "                'Unknown complete description support predecessor: ' + path)\n"
           '    require(digest(description_predecessor_source(RUNNER_PATH, runner)) == '
           'DESCRIPTION_PRE_SHA256[RUNNER_PATH],\n'
           "            'Changed complete description readiness implementation')\n"
           '    return contents'},
 {'before': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
            'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH}:\n'
            '            # All 52 physical current inputs precede every predecessor/cache reuse.\n'
            '            for path, data in incoming.items():\n'
            "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 52-file "
            "fixture: ' + path)\n"
            '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
            'set(NATIVE_CURRENT_INPUTS):',
  'after': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH}:\n'
           '            # All 53 physical current inputs precede every predecessor/cache reuse.\n'
           '            for path, data in incoming.items():\n'
           "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 53-file "
           "fixture: ' + path)\n"
           '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH}:\n'
           '            # Exactly published 42/52; missing-current53 is never backfilled.\n'
           '            for path, data in incoming.items():\n'
           '                expected = actor_predecessor_fixture_source(path, (ROOT / path).read_bytes(), '
           'current_raw)\n'
           "                require(data == expected, 'Changed/mixed historical 42/52 fixture: ' + path)\n"
           '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS):'},
 {'before': "    require(encode(value) == raw, 'Noncanonical/duplicate current contract')\n",
  'after': "    require(encode(value) == raw, 'Noncanonical/duplicate current contract')\n"
           '    actor_current_inputs(value, root)\n'}]

def _actor_category_preimage(raw):
    marker = b'\n# Exact 42 social ReaderKey actor predecessor layer.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == ALBUM_PRE_SHA256[SELF_PATH], 'Changed complete actor admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown actor layer source boundary')
    prefix, _ = raw.split(marker, 1)
    for hunk in reversed(ACTOR_CATEGORY_PREFIX_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        require(prefix.count(after) == 1, 'Missing/repeated actor source interface span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + ALBUM_PRE_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Unknown actor admission fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + ACTOR_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == ACTOR_PRE_SHA256[SELF_PATH], 'Complete published 42 admission source not restored')
    return old


def actor_predecessor_source(path, raw):
    """Exact complete published 42 bytes; never a current-input admission bypass."""
    if path in ACTOR_PRE_SHA256 and digest(raw) == ACTOR_PRE_SHA256[path]:
        return raw  # Explicit exact 42 historical input.
    raw = album_predecessor_source(path, raw)
    if path not in ACTOR_PRE_SHA256:
        return raw
    if digest(raw) == ACTOR_PRE_SHA256[path]:
        return raw  # Explicit historical-only interface; current checks require new bytes.
    if path == ACTOR_LEAF_PATH:
        old = _inverse_exact(raw, ACTOR_LEAF_ROW, path)
    elif path == ACTOR_HELPER_PATH:
        old = _inverse_exact(raw, ACTOR_HELPER_ROW, path)
    elif path == ACTOR_PROJECTION_PATH:
        old = _inverse_exact(raw, ACTOR_PROJECTION_ROW, path)
    elif path == SELF_PATH:
        old = _actor_category_preimage(raw)
    elif path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + ALBUM_PRE_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Unknown actor profile source pin')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + ACTOR_PRE_FINGERPRINT.encode() + b"'", 1)
    elif path == RUNNER_PATH:
        native_current_readiness_source(raw)
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
        require(len(pins) == 1, 'Unknown actor readiness pin')
        old = raw.replace(pins[0], ACTOR_PRE_CONTRACT_SHA256.encode(), 1)
    elif path == CATEGORY_GATE:
        normalized, source = _decoded_external_template(raw)
        require(source == album_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown actor complete external template')
        old_source = _actor_category_preimage(source)
        encoded = encode_frozen_source(old_source).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
    else:
        raise AssertionError('Unreviewed actor predecessor path')
    require(digest(old) == ACTOR_PRE_SHA256[path], 'Complete published 42 source not restored: ' + path)
    return old


def actor_current_inputs(value, root=ROOT):
    """Authenticate actual album inputs before checking exact published bb5 bytes."""
    root = Path(root)
    require(not root.is_symlink(), 'Actor current root is a symlink')
    actual = (root / CONTRACT_PATH).read_bytes()
    album_current_inputs(json.loads(actual), root)
    value = album_predecessor_contract(value, root)
    raw = encode(value)
    require(digest(raw) == ALBUM_PRE_CONTRACT_SHA256, 'Changed or mixed actual actor contract')
    contents = {}
    for path in ACTOR_PRE_SHA256:
        file = root / path
        require(not file.is_symlink() and file.is_file() and file.resolve().is_relative_to(root.resolve()),
                'Missing, escaped or symlinked actor current input: ' + path)
        contents[path] = album_predecessor_source(path, file.read_bytes())
    runner = contents[RUNNER_PATH]
    native_current_readiness_source(runner)
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete actor contract pin')
    module = contents[SELF_PATH]
    require(digest(module) == ALBUM_PRE_SHA256[SELF_PATH], 'Loaded actor admission differs from exact bb5 bytes')
    _, template = _decoded_external_template(contents[CATEGORY_GATE])
    require(template == module, 'Exact bb5 actor external source template differs')
    slot = b"ADMISSION_FINGERPRINT = '" + ALBUM_PRE_FINGERPRINT.encode() + b"'"
    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '<SELF>'", 1)) == ALBUM_PRE_FINGERPRINT,
            'Changed complete actor admission fingerprint')
    require(value['feature_batch_sources'].get(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,
            'Unknown exact actor initialization inverse')
    require(digest(contents[ACTOR_LEAF_PATH]) == ACTOR_LEAF_ROW['after_sha256'],
            'Old or changed current actor initializer')
    require(digest(contents[ACTOR_HELPER_PATH]) == ACTOR_HELPER_ROW['after_sha256'],
            'Old or changed current actor fixture producer')
    require(value['entry_projection_module_sha256'] == ACTOR_PROJECTION_ROW['after_sha256'],
            'Unknown exact current review projection pin')
    require(digest(contents[ACTOR_PROJECTION_PATH]) == ACTOR_PROJECTION_ROW['after_sha256'],
            'Old or changed current review projection source')
    require(digest(actor_predecessor_source(ACTOR_PROJECTION_PATH, contents[ACTOR_PROJECTION_PATH])) == ACTOR_PROJECTION_ROW['before_sha256'],
            'Complete published 42 review projection not restored')
    for path, expected in ACTOR_PRE_SUPPORT.items():
        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),
                'Changed current actor support: ' + path)
        require(digest(actor_predecessor_source(path, contents[path])) == expected,
                'Unknown complete actor support predecessor: ' + path)
    require(digest(actor_predecessor_source(RUNNER_PATH, runner)) == ACTOR_PRE_SHA256[RUNNER_PATH],
            'Changed complete actor readiness implementation')
    predecessor = copy.deepcopy(value)
    require(predecessor['feature_batch_sources'].pop(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,
            'Missing actual actor inverse row')
    for path, expected in ACTOR_PRE_SUPPORT.items():
        predecessor['feature_batch_support_sha256'][path] = expected
    predecessor['entry_projection_module_sha256'] = ACTOR_PROJECTION_ROW['before_sha256']
    require(digest(encode(predecessor)) == ACTOR_PRE_CONTRACT_SHA256,
            'Actual actor contract does not restore complete published 42 bytes')
    return contents


def actor_predecessor_contract(value, root=ROOT):
    """Admit actual new bytes, then restore the entire immutable 42 contract."""
    value = copy.deepcopy(value)
    if digest(encode(value)) == ACTOR_PRE_CONTRACT_SHA256:
        return value  # Exact historical-only contract; checked_current requires current bytes.
    value = album_predecessor_contract(value, root)
    actor_current_inputs(value, root)
    require(value['feature_batch_sources'].pop(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,
            'Missing complete actor inverse row')
    for path, expected in ACTOR_PRE_SUPPORT.items():
        value['feature_batch_support_sha256'][path] = expected
    require(value['entry_projection_module_sha256'] == ACTOR_PROJECTION_ROW['after_sha256'],
            'Missing exact current review projection pin')
    value['entry_projection_module_sha256'] = ACTOR_PROJECTION_ROW['before_sha256']
    require(digest(encode(value)) == ACTOR_PRE_CONTRACT_SHA256,
            'Complete published 42 readiness contract not restored')
    return value


def actor_predecessor_fixture_source(path, raw, current_contract):
    """Build genuine published 42/52 inputs, never fill a missing current53 file."""
    if path == CONTRACT_PATH:
        require(raw == current_contract, 'Mixed actor current fixture contract')
        return encode(actor_predecessor_contract(json.loads(raw)))
    return actor_predecessor_source(path, raw)


def actor_predecessor_fixture_helper(root=ROOT):
    """Expose only six literal fixture inputs from the authenticated 42 helper."""
    from types import SimpleNamespace
    root = Path(root)
    value = json.loads((root / CONTRACT_PATH).read_bytes())
    contents = actor_current_inputs(value, root)
    raw = actor_predecessor_source(ACTOR_HELPER_PATH, contents[ACTOR_HELPER_PATH])
    require(digest(raw) == ACTOR_PRE_SHA256[ACTOR_HELPER_PATH], 'Unknown 42 fixture helper input')
    wanted = {'SOURCE_EDITS', 'ADDED_SUPPORT', 'CONTRACT_PATH', 'EVOLUTION_SOURCES', 'EVOLUTION_SUPPORT', 'FLOOR_INPUTS'}
    values = {}
    for node in ast.parse(raw).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
            if name in wanted:
                require(name not in values, 'Repeated historical fixture helper input: ' + name)
                values[name] = ast.literal_eval(node.value)
    require(set(values) == wanted, 'Incomplete historical fixture helper inputs')
    return SimpleNamespace(**values)

# Exact bb5 album chapter actor predecessor layer.
ALBUM_PRE_CONTRACT_SHA256 = '5510daa8a177c8cc51a4459f3db5a4ee53cfda0a48c4cbff5dc8af5b0113d3e3'
ALBUM_PRE_FINGERPRINT = '8a197e11d1c30659e41d5c3e6eadf050a83efb7994557c1817ba3e858f18b8ee'
ALBUM_LEAF_PATH = 'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift'
ALBUM_HELPER_PATH = 'tools/club_customer_directory_admission.py'
ALBUM_LEAF_ROW = {'before_sha256': '3d3c8ef9236f3d5a0c2b99c9eb6ce2b57c3afc36aaabdd701d1597855f024257',
 'after_sha256': '5c74526f40c44327ec68254de76bd4c316e976b5aa1f6a409502774402699054',
 'hunks': [{'before': '        var chapterID: String { editor.draft.chapters[0].id }\n',
            'after': '        @MainActor var chapterID: String { editor.draft.chapters[0].id }\n'}]}
ALBUM_HELPER_ROW = {'before_sha256': '7b2bba4759677e0091b5149a7fc46096280b95ac2b7e94cd77481a24570afb35',
 'after_sha256': '7187f18779f4f44286b50bff6da7bea0ac27cc982eb04dc9ed330df25b959def',
 'hunks': [{'before': "FLOOR_INPUTS = ('App/SocialGuideTemplateSection.swift',\n",
            'after': "FLOOR_INPUTS = ('Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift',\n"
                     " 'App/SocialGuideTemplateSection.swift',\n"}]}
ALBUM_PRE_SHA256 = {'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift': '3d3c8ef9236f3d5a0c2b99c9eb6ce2b57c3afc36aaabdd701d1597855f024257',
 'tools/club_customer_directory_admission.py': '7b2bba4759677e0091b5149a7fc46096280b95ac2b7e94cd77481a24570afb35',
 'Tests/ContractChecks/test_category_roam_registration.py': '693a1f0f3a559838578313f26d2bb3cfeda675161378c81d72f1b084dc206c2f',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '18b2f038512301a8932a399e818179f09964595a77f10e8e990f20d0a2594189',
 'Tests/ContractChecks/test_global_search_category_recovery.py': 'b00adbb5175612d05428065ac8d027027a930ce95c97ad6be36a091356d46d2c',
 'tools/run138_editor_readiness.py': '62e0ca8a7285198b4b59cefeaeb592759325d55e7669aaaabe88a75f070dbc44'}
ALBUM_PRE_SUPPORT = {'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift': '3d3c8ef9236f3d5a0c2b99c9eb6ce2b57c3afc36aaabdd701d1597855f024257',
 'tools/club_customer_directory_admission.py': '7b2bba4759677e0091b5149a7fc46096280b95ac2b7e94cd77481a24570afb35',
 'Tests/ContractChecks/test_category_roam_registration.py': '693a1f0f3a559838578313f26d2bb3cfeda675161378c81d72f1b084dc206c2f',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '18b2f038512301a8932a399e818179f09964595a77f10e8e990f20d0a2594189',
 'Tests/ContractChecks/test_global_search_category_recovery.py': 'b00adbb5175612d05428065ac8d027027a930ce95c97ad6be36a091356d46d2c'}
ALBUM_CATEGORY_PREFIX_HUNKS = [{'before': 'def actor_predecessor_source(path, raw):\n'
            '    """Exact complete published 42 bytes; never a current-input admission bypass."""\n',
  'after': 'def actor_predecessor_source(path, raw):\n'
           '    """Exact complete published 42 bytes; never a current-input admission bypass."""\n'
           '    if path in ACTOR_PRE_SHA256 and digest(raw) == ACTOR_PRE_SHA256[path]:\n'
           '        return raw  # Explicit exact 42 historical input.\n'
           '    raw = album_predecessor_source(path, raw)\n'},
 {'before': "    require(digest(raw) == IMPLEMENTATION_SHA256, 'Changed complete actor admission source')\n",
  'after': "    require(digest(raw) == ALBUM_PRE_SHA256[SELF_PATH], 'Changed complete actor admission "
           "source')\n"},
 {'before': '    slot = b"ADMISSION_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            "    require(prefix.count(slot) == 1, 'Unknown actor admission fingerprint slot')\n",
  'after': '    slot = b"ADMISSION_FINGERPRINT = \'" + ALBUM_PRE_FINGERPRINT.encode() + b"\'"\n'
           "    require(prefix.count(slot) == 1, 'Unknown actor admission fingerprint slot')\n"},
 {'before': '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            "        require(raw.count(slot) == 1, 'Unknown actor profile source pin')\n",
  'after': '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ALBUM_PRE_FINGERPRINT.encode() + b"\'"\n'
           "        require(raw.count(slot) == 1, 'Unknown actor profile source pin')\n"},
 {'before': "        require(source == (ROOT / SELF_PATH).read_bytes(), 'Unknown actor complete external "
            "template')\n",
  'after': '        require(source == album_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), '
           "'Unknown actor complete external template')\n"},
 {'before': '    actor_current_inputs(value, root)\n'
            "    require(value['feature_batch_sources'].pop(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,\n",
  'after': '    value = album_predecessor_contract(value, root)\n'
           '    actor_current_inputs(value, root)\n'
           "    require(value['feature_batch_sources'].pop(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,\n"},
 {'before': 'def actor_current_inputs(value, root=ROOT):\n'
            '    """Re-read all actual actor boundary bytes before any predecessor or cache."""\n'
            '    root = Path(root)\n'
            "    require(not root.is_symlink(), 'Actor current root is a symlink')\n"
            '    contents = {}\n'
            '    for path in ACTOR_PRE_SHA256:\n'
            '        file = root / path\n'
            '        parts = Path(path).parts\n'
            '        require(all(not (root / Path(*parts[:end])).is_symlink() for end in range(1, len(parts) '
            '+ 1)),\n'
            "                'Symlink component in actor current input: ' + path)\n"
            '        require(not file.is_symlink() and file.is_file() and '
            'file.resolve().is_relative_to(root.resolve()),\n'
            "                'Missing, escaped or symlinked actor current input: ' + path)\n"
            '        contents[path] = file.read_bytes()\n'
            '    contract_file = root / CONTRACT_PATH\n'
            '    require(not contract_file.is_symlink() and contract_file.is_file()\n'
            "            and contract_file.resolve().is_relative_to(root.resolve()), 'Invalid actual actor "
            "contract input')\n"
            '    raw = contract_file.read_bytes()\n'
            "    require(encode(value) == raw, 'Changed or mixed actual actor contract')\n"
            '    runner = contents[RUNNER_PATH]\n'
            '    native_current_readiness_source(runner)\n'
            '    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", runner)\n'
            "    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete actor "
            "contract pin')\n"
            '    module = contents[SELF_PATH]\n'
            "    require(digest(module) == IMPLEMENTATION_SHA256, 'Loaded actor admission differs from "
            "current bytes')\n"
            '    validate_external_source_template(root, module)\n'
            '    slot = b"ADMISSION_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
            '    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '
            '\'<SELF>\'", 1)) == ADMISSION_FINGERPRINT,\n'
            "            'Changed complete actor admission fingerprint')\n"
            "    require(value['feature_batch_sources'].get(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,\n"
            "            'Unknown exact actor initialization inverse')\n"
            "    require(digest(contents[ACTOR_LEAF_PATH]) == ACTOR_LEAF_ROW['after_sha256'],\n"
            "            'Old or changed current actor initializer')\n"
            "    require(digest(contents[ACTOR_HELPER_PATH]) == ACTOR_HELPER_ROW['after_sha256'],\n"
            "            'Old or changed current actor fixture producer')\n"
            "    require(value['entry_projection_module_sha256'] == ACTOR_PROJECTION_ROW['after_sha256'],\n"
            "            'Unknown exact current review projection pin')\n"
            "    require(digest(contents[ACTOR_PROJECTION_PATH]) == ACTOR_PROJECTION_ROW['after_sha256'],\n"
            "            'Old or changed current review projection source')\n"
            '    require(digest(actor_predecessor_source(ACTOR_PROJECTION_PATH, '
            "contents[ACTOR_PROJECTION_PATH])) == ACTOR_PROJECTION_ROW['before_sha256'],\n"
            "            'Complete published 42 review projection not restored')\n"
            '    for path, expected in ACTOR_PRE_SUPPORT.items():\n'
            "        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),\n"
            "                'Changed current actor support: ' + path)\n"
            '        require(digest(actor_predecessor_source(path, contents[path])) == expected,\n'
            "                'Unknown complete actor support predecessor: ' + path)\n"
            '    require(digest(actor_predecessor_source(RUNNER_PATH, runner)) == '
            'ACTOR_PRE_SHA256[RUNNER_PATH],\n'
            "            'Changed complete actor readiness implementation')\n"
            '    predecessor = copy.deepcopy(value)\n'
            "    require(predecessor['feature_batch_sources'].pop(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,\n"
            "            'Missing actual actor inverse row')\n"
            '    for path, expected in ACTOR_PRE_SUPPORT.items():\n'
            "        predecessor['feature_batch_support_sha256'][path] = expected\n"
            "    predecessor['entry_projection_module_sha256'] = ACTOR_PROJECTION_ROW['before_sha256']\n"
            '    require(digest(encode(predecessor)) == ACTOR_PRE_CONTRACT_SHA256,\n'
            "            'Actual actor contract does not restore complete published 42 bytes')\n"
            '    return contents',
  'after': 'def actor_current_inputs(value, root=ROOT):\n'
           '    """Authenticate actual album inputs before checking exact published bb5 bytes."""\n'
           '    root = Path(root)\n'
           "    require(not root.is_symlink(), 'Actor current root is a symlink')\n"
           '    actual = (root / CONTRACT_PATH).read_bytes()\n'
           '    album_current_inputs(json.loads(actual), root)\n'
           '    value = album_predecessor_contract(value, root)\n'
           '    raw = encode(value)\n'
           "    require(digest(raw) == ALBUM_PRE_CONTRACT_SHA256, 'Changed or mixed actual actor contract')\n"
           '    contents = {}\n'
           '    for path in ACTOR_PRE_SHA256:\n'
           '        file = root / path\n'
           '        require(not file.is_symlink() and file.is_file() and '
           'file.resolve().is_relative_to(root.resolve()),\n'
           "                'Missing, escaped or symlinked actor current input: ' + path)\n"
           '        contents[path] = album_predecessor_source(path, file.read_bytes())\n'
           '    runner = contents[RUNNER_PATH]\n'
           '    native_current_readiness_source(runner)\n'
           '    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", runner)\n'
           "    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete actor contract "
           "pin')\n"
           '    module = contents[SELF_PATH]\n'
           "    require(digest(module) == ALBUM_PRE_SHA256[SELF_PATH], 'Loaded actor admission differs from "
           "exact bb5 bytes')\n"
           '    _, template = _decoded_external_template(contents[CATEGORY_GATE])\n'
           "    require(template == module, 'Exact bb5 actor external source template differs')\n"
           '    slot = b"ADMISSION_FINGERPRINT = \'" + ALBUM_PRE_FINGERPRINT.encode() + b"\'"\n'
           '    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '
           '\'<SELF>\'", 1)) == ALBUM_PRE_FINGERPRINT,\n'
           "            'Changed complete actor admission fingerprint')\n"
           "    require(value['feature_batch_sources'].get(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,\n"
           "            'Unknown exact actor initialization inverse')\n"
           "    require(digest(contents[ACTOR_LEAF_PATH]) == ACTOR_LEAF_ROW['after_sha256'],\n"
           "            'Old or changed current actor initializer')\n"
           "    require(digest(contents[ACTOR_HELPER_PATH]) == ACTOR_HELPER_ROW['after_sha256'],\n"
           "            'Old or changed current actor fixture producer')\n"
           "    require(value['entry_projection_module_sha256'] == ACTOR_PROJECTION_ROW['after_sha256'],\n"
           "            'Unknown exact current review projection pin')\n"
           "    require(digest(contents[ACTOR_PROJECTION_PATH]) == ACTOR_PROJECTION_ROW['after_sha256'],\n"
           "            'Old or changed current review projection source')\n"
           '    require(digest(actor_predecessor_source(ACTOR_PROJECTION_PATH, '
           "contents[ACTOR_PROJECTION_PATH])) == ACTOR_PROJECTION_ROW['before_sha256'],\n"
           "            'Complete published 42 review projection not restored')\n"
           '    for path, expected in ACTOR_PRE_SUPPORT.items():\n'
           "        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),\n"
           "                'Changed current actor support: ' + path)\n"
           '        require(digest(actor_predecessor_source(path, contents[path])) == expected,\n'
           "                'Unknown complete actor support predecessor: ' + path)\n"
           '    require(digest(actor_predecessor_source(RUNNER_PATH, runner)) == '
           'ACTOR_PRE_SHA256[RUNNER_PATH],\n'
           "            'Changed complete actor readiness implementation')\n"
           '    predecessor = copy.deepcopy(value)\n'
           "    require(predecessor['feature_batch_sources'].pop(ACTOR_LEAF_PATH) == ACTOR_LEAF_ROW,\n"
           "            'Missing actual actor inverse row')\n"
           '    for path, expected in ACTOR_PRE_SUPPORT.items():\n'
           "        predecessor['feature_batch_support_sha256'][path] = expected\n"
           "    predecessor['entry_projection_module_sha256'] = ACTOR_PROJECTION_ROW['before_sha256']\n"
           '    require(digest(encode(predecessor)) == ACTOR_PRE_CONTRACT_SHA256,\n'
           "            'Actual actor contract does not restore complete published 42 bytes')\n"
           '    return contents'},
 {'before': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
            'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH}:\n'
            '            # All 53 physical current inputs precede every predecessor/cache reuse.\n'
            '            for path, data in incoming.items():\n'
            "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 53-file "
            "fixture: ' + path)\n"
            '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
            'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH}:',
  'after': '        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH, ALBUM_LEAF_PATH}:\n'
           '            # All 54 physical current inputs precede every predecessor/cache reuse.\n'
           '            for path, data in incoming.items():\n'
           "                require(data == (ROOT / path).read_bytes(), 'Changed/mixed current 54-file "
           "fixture: ' + path)\n"
           '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH}:\n'
           '            # Exactly published bb5/53; missing-current54 is never backfilled.\n'
           '            for path, data in incoming.items():\n'
           '                expected = album_predecessor_fixture_source(path, (ROOT / path).read_bytes(), '
           'current_raw)\n'
           "                require(data == expected, 'Changed/mixed historical bb5/53 fixture: ' + path)\n"
           '        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | '
           'set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH}:'},
 {'before': "    require(encode(value) == raw, 'Noncanonical/duplicate current contract')\n",
  'after': "    require(encode(value) == raw, 'Noncanonical/duplicate current contract')\n"
           '    album_current_inputs(value, root)\n'}]

def _album_category_preimage(raw):
    marker = b'\n# Exact bb5 album chapter actor predecessor layer.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == IMPLEMENTATION_SHA256, 'Changed complete album admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown album layer source boundary')
    prefix, _ = raw.split(marker, 1)
    for hunk in reversed(ALBUM_CATEGORY_PREFIX_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        require(prefix.count(after) == 1, 'Missing/repeated album source interface span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Unknown album admission fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + ALBUM_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == ALBUM_PRE_SHA256[SELF_PATH], 'Complete published bb5 admission source not restored')
    return old


def album_predecessor_source(path, raw):
    """Exact complete published bb5 bytes; never a current-input admission bypass."""
    if path not in ALBUM_PRE_SHA256:
        return raw
    if digest(raw) == ALBUM_PRE_SHA256[path]:
        return raw  # Explicit historical-only interface; current checks require new bytes.
    if path == ALBUM_LEAF_PATH:
        old = _inverse_exact(raw, ALBUM_LEAF_ROW, path)
    elif path == ALBUM_HELPER_PATH:
        old = _inverse_exact(raw, ALBUM_HELPER_ROW, path)
    elif path == SELF_PATH:
        old = _album_category_preimage(raw)
    elif path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Unknown album profile source pin')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + ALBUM_PRE_FINGERPRINT.encode() + b"'", 1)
    elif path == RUNNER_PATH:
        native_current_readiness_source(raw)
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
        require(len(pins) == 1, 'Unknown album readiness pin')
        old = raw.replace(pins[0], ALBUM_PRE_CONTRACT_SHA256.encode(), 1)
    elif path == CATEGORY_GATE:
        normalized, source = _decoded_external_template(raw)
        require(source == (ROOT / SELF_PATH).read_bytes(), 'Unknown album complete external template')
        old_source = _album_category_preimage(source)
        encoded = encode_frozen_source(old_source).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
    else:
        raise AssertionError('Unreviewed album predecessor path')
    require(digest(old) == ALBUM_PRE_SHA256[path], 'Complete published bb5 source not restored: ' + path)
    return old


def album_current_inputs(value, root=ROOT):
    """Re-read all actual album boundary bytes before any predecessor or cache."""
    root = Path(root)
    require(not root.is_symlink(), 'Album current root is a symlink')
    contents = {}
    for path in ALBUM_PRE_SHA256:
        file = root / path
        parts = Path(path).parts
        require(all(not (root / Path(*parts[:end])).is_symlink() for end in range(1, len(parts) + 1)),
                'Symlink component in album current input: ' + path)
        require(not file.is_symlink() and file.is_file() and file.resolve().is_relative_to(root.resolve()),
                'Missing, escaped or symlinked album current input: ' + path)
        contents[path] = file.read_bytes()
    contract_file = root / CONTRACT_PATH
    require(not contract_file.is_symlink() and contract_file.is_file()
            and contract_file.resolve().is_relative_to(root.resolve()), 'Invalid actual album contract input')
    raw = contract_file.read_bytes()
    require(encode(value) == raw, 'Changed or mixed actual album contract')
    runner = contents[RUNNER_PATH]
    native_current_readiness_source(runner)
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete album contract pin')
    module = contents[SELF_PATH]
    require(digest(module) == IMPLEMENTATION_SHA256, 'Loaded album admission differs from current bytes')
    validate_external_source_template(root, module)
    slot = b"ADMISSION_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '<SELF>'", 1)) == ADMISSION_FINGERPRINT,
            'Changed complete album admission fingerprint')
    require(value['feature_batch_sources'].get(ALBUM_LEAF_PATH) == ALBUM_LEAF_ROW,
            'Unknown exact album initialization inverse')
    require(digest(contents[ALBUM_LEAF_PATH]) == ALBUM_LEAF_ROW['after_sha256'],
            'Old or changed current album initializer')
    require(digest(contents[ALBUM_HELPER_PATH]) == ALBUM_HELPER_ROW['after_sha256'],
            'Old or changed current album fixture producer')
    for path, expected in ALBUM_PRE_SUPPORT.items():
        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),
                'Changed current album support: ' + path)
        require(digest(album_predecessor_source(path, contents[path])) == expected,
                'Unknown complete album support predecessor: ' + path)
    require(digest(album_predecessor_source(RUNNER_PATH, runner)) == ALBUM_PRE_SHA256[RUNNER_PATH],
            'Changed complete album readiness implementation')
    predecessor = copy.deepcopy(value)
    require(predecessor['feature_batch_sources'].pop(ALBUM_LEAF_PATH) == ALBUM_LEAF_ROW,
            'Missing actual album inverse row')
    for path, expected in ALBUM_PRE_SUPPORT.items():
        predecessor['feature_batch_support_sha256'][path] = expected
    require(digest(encode(predecessor)) == ALBUM_PRE_CONTRACT_SHA256,
            'Actual album contract does not restore complete published bb5 bytes')
    return contents


def album_predecessor_contract(value, root=ROOT):
    """Admit actual new bytes, then restore the entire immutable bb5 contract."""
    value = copy.deepcopy(value)
    if digest(encode(value)) == ALBUM_PRE_CONTRACT_SHA256:
        return value  # Exact historical-only contract; checked_current requires current bytes.
    album_current_inputs(value, root)
    require(value['feature_batch_sources'].pop(ALBUM_LEAF_PATH) == ALBUM_LEAF_ROW,
            'Missing complete album inverse row')
    for path, expected in ALBUM_PRE_SUPPORT.items():
        value['feature_batch_support_sha256'][path] = expected
    require(digest(encode(value)) == ALBUM_PRE_CONTRACT_SHA256,
            'Complete published bb5 readiness contract not restored')
    return value


def album_predecessor_fixture_source(path, raw, current_contract):
    """Build genuine published bb5/53 inputs, never fill a missing current54 file."""
    if path == CONTRACT_PATH:
        require(raw == current_contract, 'Mixed album current fixture contract')
        return encode(album_predecessor_contract(json.loads(raw)))
    return album_predecessor_source(path, raw)


def album_predecessor_fixture_helper(root=ROOT):
    """Expose only six literal fixture inputs from the authenticated bb5 helper."""
    from types import SimpleNamespace
    root = Path(root)
    value = json.loads((root / CONTRACT_PATH).read_bytes())
    contents = album_current_inputs(value, root)
    raw = album_predecessor_source(ALBUM_HELPER_PATH, contents[ALBUM_HELPER_PATH])
    require(digest(raw) == ALBUM_PRE_SHA256[ALBUM_HELPER_PATH], 'Unknown bb5 fixture helper input')
    wanted = {'SOURCE_EDITS', 'ADDED_SUPPORT', 'CONTRACT_PATH', 'EVOLUTION_SOURCES', 'EVOLUTION_SUPPORT', 'FLOOR_INPUTS'}
    values = {}
    for node in ast.parse(raw).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
            if name in wanted:
                require(name not in values, 'Repeated historical fixture helper input: ' + name)
                values[name] = ast.literal_eval(node.value)
    require(set(values) == wanted, 'Incomplete historical fixture helper inputs')
    return SimpleNamespace(**values)

# Exact native54 bounded byte-transform performance predecessor.
import base64
from functools import lru_cache
import zlib


MAX_INPUT_BYTES = 1024 * 1024
MAX_ENTRIES = 8
MAX_RETAINED_PAYLOAD_BYTES = 40 * 1024 * 1024


@lru_cache(maxsize=MAX_ENTRIES, typed=True)
def _encoded_bytes(raw):
    if type(raw) is not bytes or len(raw) > MAX_INPUT_BYTES:
        raise ValueError('Encoded cache input exceeds its immutable-byte bound')
    return base64.b85encode(zlib.compress(raw, 9))


@lru_cache(maxsize=MAX_ENTRIES, typed=True)
def _compressed_bytes(encoded):
    if type(encoded) is not bytes or len(encoded) > MAX_INPUT_BYTES:
        raise ValueError('Compressed cache input exceeds its immutable-byte bound')
    return base64.b85decode(encoded)


def encode_frozen_source(raw):
    """Return the original level-nine zlib/base85 encoding of immutable bytes."""
    if type(raw) is not bytes:
        raise TypeError('Frozen source input must be immutable bytes')
    if len(raw) > MAX_INPUT_BYTES:
        return base64.b85encode(zlib.compress(raw, 9))
    return _encoded_bytes(raw)


def decode_frozen_source(encoded):
    """Decode immutable base85 bytes without retaining decompressed payloads."""
    if type(encoded) is not bytes:
        raise TypeError('Frozen source encoding must be immutable bytes')
    compressed = (base64.b85decode(encoded) if len(encoded) > MAX_INPUT_BYTES
                  else _compressed_bytes(encoded))
    return zlib.decompress(compressed)


BYTE_CACHE_BASE_COMMIT = '54f708eb260ad20cdf0fb6355cc4eaedb967019a'
BYTE_CACHE_PRE_FINGERPRINT = '8def02e4117425200af2964a8bbf0ba333867cceb42a669ad0d6ed4a0cf33800'
BYTE_CACHE_PRE_SHA256 = {'Tests/ContractChecks/test_category_roam_registration.py': '74d2da07e15f74ebc17e5f02a1f48d43e650830ed650879fa5c4751ddcfbc191',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '83d2acef192141428f63f08289dd8d1f4899eae9eb8d04e5044427c7064589bd',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '19dfe4cddfd919622e48ce26c626664570e0e4d3547ce085ff2e5cf3b356c8db',
 'tools/run138_editor_readiness_contract.json': '4ebecf51baf56324b9f76307df8faf60385a5a9ae7fcede320a3a0bb06474474',
 'tools/run138_editor_readiness.py': '09ee41899af2584f4f100405ad4aeceaf01edd25cfccd3147356ef1a61720bd8'}
BYTE_CACHE_SOURCE_HUNKS = (('def _decoded_external_template(raw):\n'
  '    import base64, zlib\n'
  "    first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "    last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '    suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  '    require(raw.count(first) == 1 and raw.count(last) == 1,\n'
  "            'Missing/repeated external source template markers')\n"
  '    require(raw[CATEGORY_TEMPLATE_OFFSET:].startswith(first) and raw.endswith(last + suffix),\n'
  "            'Moved external source template or changed suffix')\n"
  '    start = CATEGORY_TEMPLATE_OFFSET\n'
  '    finish = len(raw) - len(suffix)\n'
  '    normalized = raw[:start] + suffix\n'
  '    require(digest(normalized) == ADAPTED_CATEGORY_GATE_SHA256,\n'
  "            'Complete category source outside exact template changed')\n"
  '    body = raw[start + len(first):finish - len(last)]\n'
  '    nodes = ast.parse(body).body\n'
  '    require(len(nodes) == 1 and isinstance(nodes[0], ast.Assign) and len(nodes[0].targets) == 1 and\n'
  '            isinstance(nodes[0].targets[0], ast.Name) and nodes[0].targets[0].id == '
  "'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85',\n"
  "            'External template must be one literal data assignment')\n"
  '    encoded = ast.literal_eval(nodes[0].value)\n'
  "    require(isinstance(encoded, str), 'External template must be literal text data')\n"
  '    value = zlib.decompress(base64.b85decode(encoded))\n'
  '    require(base64.b85encode(zlib.compress(value, 9)).decode() == encoded,\n'
  "            'Noncanonical external compressed source template')\n"
  "    canonical = first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + b''.join(\n"
  "        ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + b')\\n' "
  '+ last\n'
  "    require(raw[start:finish] == canonical, 'Changed exact external template data block')\n"
  '    return normalized, value',
  'def _decoded_external_template(raw):\n'
  "    first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "    last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '    suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  '    require(raw.count(first) == 1 and raw.count(last) == 1,\n'
  "            'Missing/repeated external source template markers')\n"
  '    require(raw[CATEGORY_TEMPLATE_OFFSET:].startswith(first) and raw.endswith(last + suffix),\n'
  "            'Moved external source template or changed suffix')\n"
  '    start = CATEGORY_TEMPLATE_OFFSET\n'
  '    finish = len(raw) - len(suffix)\n'
  '    normalized = raw[:start] + suffix\n'
  '    require(digest(normalized) == ADAPTED_CATEGORY_GATE_SHA256,\n'
  "            'Complete category source outside exact template changed')\n"
  '    body = raw[start + len(first):finish - len(last)]\n'
  '    nodes = ast.parse(body).body\n'
  '    require(len(nodes) == 1 and isinstance(nodes[0], ast.Assign) and len(nodes[0].targets) == 1 and\n'
  '            isinstance(nodes[0].targets[0], ast.Name) and nodes[0].targets[0].id == '
  "'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85',\n"
  "            'External template must be one literal data assignment')\n"
  '    encoded = ast.literal_eval(nodes[0].value)\n'
  "    require(isinstance(encoded, str), 'External template must be literal text data')\n"
  '    value = decode_frozen_source(encoded.encode())\n'
  '    require(encode_frozen_source(value).decode() == encoded,\n'
  "            'Noncanonical external compressed source template')\n"
  "    canonical = first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + b''.join(\n"
  "        ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + b')\\n' "
  '+ last\n'
  "    require(raw[start:finish] == canonical, 'Changed exact external template data block')\n"
  '    return normalized, value'),
 ('def native_predecessor_source(path, raw):\n'
  '    """Exact historical bytes only; current admission remains checked_current."""\n'
  '    if path in NATIVE_PRE_SHA256 and digest(raw) == NATIVE_PRE_SHA256[path]:\n'
  '        return raw  # Explicit exact c2af historical input.\n'
  '    raw = description_predecessor_source(path, raw)\n'
  '    if path not in NATIVE_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == NATIVE_PRE_SHA256[path]:\n'
  '        return raw\n'
  '    if path == NATIVE_LEAF_PATHS[0]:\n'
  '        old = _inverse_exact(raw, NATIVE_NAV_ROW, path)\n'
  "    elif path == 'Questify.xcodeproj/project.pbxproj':\n"
  '        old = _inverse_exact(raw, NATIVE_PBX_REPAIR_ROW, path)\n'
  "    elif path == 'tools/club_customer_directory_admission.py':\n"
  '        old = _inverse_exact(raw, NATIVE_HELPER_ROW, path)\n'
  '    elif path == NATIVE_PROJECTION_PATH:\n'
  '        old = _inverse_exact(raw, NATIVE_PROJECTION_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _native_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + DESCRIPTION_PRE_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown native profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + NATIVE_PRE_FINGERPRINT.encode() + '
  'b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        raw = native_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown native readiness pin')\n"
  '        old = raw.replace(pins[0], NATIVE_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        import base64, zlib\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  '        require(source == description_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), '
  "'Unknown native complete external template')\n"
  '        old_source = _native_category_preimage(source)\n'
  '        encoded = base64.b85encode(zlib.compress(old_source, 9)).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed native predecessor path')\n"
  "    require(digest(old) == NATIVE_PRE_SHA256[path], 'Complete c2af source not restored: ' + path)\n"
  '    return old',
  'def native_predecessor_source(path, raw):\n'
  '    """Exact historical bytes only; current admission remains checked_current."""\n'
  '    if path in NATIVE_PRE_SHA256 and digest(raw) == NATIVE_PRE_SHA256[path]:\n'
  '        return raw  # Explicit exact c2af historical input.\n'
  '    raw = description_predecessor_source(path, raw)\n'
  '    if path not in NATIVE_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == NATIVE_PRE_SHA256[path]:\n'
  '        return raw\n'
  '    if path == NATIVE_LEAF_PATHS[0]:\n'
  '        old = _inverse_exact(raw, NATIVE_NAV_ROW, path)\n'
  "    elif path == 'Questify.xcodeproj/project.pbxproj':\n"
  '        old = _inverse_exact(raw, NATIVE_PBX_REPAIR_ROW, path)\n'
  "    elif path == 'tools/club_customer_directory_admission.py':\n"
  '        old = _inverse_exact(raw, NATIVE_HELPER_ROW, path)\n'
  '    elif path == NATIVE_PROJECTION_PATH:\n'
  '        old = _inverse_exact(raw, NATIVE_PROJECTION_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _native_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + DESCRIPTION_PRE_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown native profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + NATIVE_PRE_FINGERPRINT.encode() + '
  'b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        raw = native_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown native readiness pin')\n"
  '        old = raw.replace(pins[0], NATIVE_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  '        require(source == description_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), '
  "'Unknown native complete external template')\n"
  '        old_source = _native_category_preimage(source)\n'
  '        encoded = encode_frozen_source(old_source).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed native predecessor path')\n"
  "    require(digest(old) == NATIVE_PRE_SHA256[path], 'Complete c2af source not restored: ' + path)\n"
  '    return old'),
 ('def description_predecessor_source(path, raw):\n'
  '    """Exact complete published 7b bytes; never a current-input admission bypass."""\n'
  '    if path in DESCRIPTION_PRE_SHA256 and digest(raw) == DESCRIPTION_PRE_SHA256[path]:\n'
  '        return raw  # Explicit exact 7b historical input.\n'
  '    raw = actor_predecessor_source(path, raw)\n'
  '    if path not in DESCRIPTION_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == DESCRIPTION_PRE_SHA256[path]:\n'
  '        return raw  # Explicit historical-only interface; current checks require new bytes.\n'
  '    if path == DESCRIPTION_LEAF_PATH:\n'
  '        old = _inverse_exact(raw, DESCRIPTION_LEAF_ROW, path)\n'
  '    elif path == DESCRIPTION_HELPER_PATH:\n'
  '        old = _inverse_exact(raw, DESCRIPTION_HELPER_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _description_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ACTOR_PRE_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown description profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + '
  'DESCRIPTION_PRE_FINGERPRINT.encode() + b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        native_current_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown description readiness pin')\n"
  '        old = raw.replace(pins[0], DESCRIPTION_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        import base64, zlib\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  "        require(source == actor_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown "
  "description complete external template')\n"
  '        old_source = _description_category_preimage(source)\n'
  '        encoded = base64.b85encode(zlib.compress(old_source, 9)).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed description predecessor path')\n"
  "    require(digest(old) == DESCRIPTION_PRE_SHA256[path], 'Complete published 7b source not restored: ' + "
  'path)\n'
  '    return old',
  'def description_predecessor_source(path, raw):\n'
  '    """Exact complete published 7b bytes; never a current-input admission bypass."""\n'
  '    if path in DESCRIPTION_PRE_SHA256 and digest(raw) == DESCRIPTION_PRE_SHA256[path]:\n'
  '        return raw  # Explicit exact 7b historical input.\n'
  '    raw = actor_predecessor_source(path, raw)\n'
  '    if path not in DESCRIPTION_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == DESCRIPTION_PRE_SHA256[path]:\n'
  '        return raw  # Explicit historical-only interface; current checks require new bytes.\n'
  '    if path == DESCRIPTION_LEAF_PATH:\n'
  '        old = _inverse_exact(raw, DESCRIPTION_LEAF_ROW, path)\n'
  '    elif path == DESCRIPTION_HELPER_PATH:\n'
  '        old = _inverse_exact(raw, DESCRIPTION_HELPER_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _description_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ACTOR_PRE_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown description profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + '
  'DESCRIPTION_PRE_FINGERPRINT.encode() + b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        native_current_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown description readiness pin')\n"
  '        old = raw.replace(pins[0], DESCRIPTION_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  "        require(source == actor_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown "
  "description complete external template')\n"
  '        old_source = _description_category_preimage(source)\n'
  '        encoded = encode_frozen_source(old_source).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed description predecessor path')\n"
  "    require(digest(old) == DESCRIPTION_PRE_SHA256[path], 'Complete published 7b source not restored: ' + "
  'path)\n'
  '    return old'),
 ('def actor_predecessor_source(path, raw):\n'
  '    """Exact complete published 42 bytes; never a current-input admission bypass."""\n'
  '    if path in ACTOR_PRE_SHA256 and digest(raw) == ACTOR_PRE_SHA256[path]:\n'
  '        return raw  # Explicit exact 42 historical input.\n'
  '    raw = album_predecessor_source(path, raw)\n'
  '    if path not in ACTOR_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == ACTOR_PRE_SHA256[path]:\n'
  '        return raw  # Explicit historical-only interface; current checks require new bytes.\n'
  '    if path == ACTOR_LEAF_PATH:\n'
  '        old = _inverse_exact(raw, ACTOR_LEAF_ROW, path)\n'
  '    elif path == ACTOR_HELPER_PATH:\n'
  '        old = _inverse_exact(raw, ACTOR_HELPER_ROW, path)\n'
  '    elif path == ACTOR_PROJECTION_PATH:\n'
  '        old = _inverse_exact(raw, ACTOR_PROJECTION_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _actor_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ALBUM_PRE_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown actor profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + ACTOR_PRE_FINGERPRINT.encode() + '
  'b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        native_current_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown actor readiness pin')\n"
  '        old = raw.replace(pins[0], ACTOR_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        import base64, zlib\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  "        require(source == album_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown "
  "actor complete external template')\n"
  '        old_source = _actor_category_preimage(source)\n'
  '        encoded = base64.b85encode(zlib.compress(old_source, 9)).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed actor predecessor path')\n"
  "    require(digest(old) == ACTOR_PRE_SHA256[path], 'Complete published 42 source not restored: ' + path)\n"
  '    return old',
  'def actor_predecessor_source(path, raw):\n'
  '    """Exact complete published 42 bytes; never a current-input admission bypass."""\n'
  '    if path in ACTOR_PRE_SHA256 and digest(raw) == ACTOR_PRE_SHA256[path]:\n'
  '        return raw  # Explicit exact 42 historical input.\n'
  '    raw = album_predecessor_source(path, raw)\n'
  '    if path not in ACTOR_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == ACTOR_PRE_SHA256[path]:\n'
  '        return raw  # Explicit historical-only interface; current checks require new bytes.\n'
  '    if path == ACTOR_LEAF_PATH:\n'
  '        old = _inverse_exact(raw, ACTOR_LEAF_ROW, path)\n'
  '    elif path == ACTOR_HELPER_PATH:\n'
  '        old = _inverse_exact(raw, ACTOR_HELPER_ROW, path)\n'
  '    elif path == ACTOR_PROJECTION_PATH:\n'
  '        old = _inverse_exact(raw, ACTOR_PROJECTION_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _actor_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ALBUM_PRE_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown actor profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + ACTOR_PRE_FINGERPRINT.encode() + '
  'b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        native_current_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown actor readiness pin')\n"
  '        old = raw.replace(pins[0], ACTOR_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  "        require(source == album_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown "
  "actor complete external template')\n"
  '        old_source = _actor_category_preimage(source)\n'
  '        encoded = encode_frozen_source(old_source).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed actor predecessor path')\n"
  "    require(digest(old) == ACTOR_PRE_SHA256[path], 'Complete published 42 source not restored: ' + path)\n"
  '    return old'),
 ('def album_predecessor_source(path, raw):\n'
  '    """Exact complete published bb5 bytes; never a current-input admission bypass."""\n'
  '    if path not in ALBUM_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == ALBUM_PRE_SHA256[path]:\n'
  '        return raw  # Explicit historical-only interface; current checks require new bytes.\n'
  '    if path == ALBUM_LEAF_PATH:\n'
  '        old = _inverse_exact(raw, ALBUM_LEAF_ROW, path)\n'
  '    elif path == ALBUM_HELPER_PATH:\n'
  '        old = _inverse_exact(raw, ALBUM_HELPER_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _album_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown album profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + ALBUM_PRE_FINGERPRINT.encode() + '
  'b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        native_current_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown album readiness pin')\n"
  '        old = raw.replace(pins[0], ALBUM_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        import base64, zlib\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  "        require(source == (ROOT / SELF_PATH).read_bytes(), 'Unknown album complete external template')\n"
  '        old_source = _album_category_preimage(source)\n'
  '        encoded = base64.b85encode(zlib.compress(old_source, 9)).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed album predecessor path')\n"
  "    require(digest(old) == ALBUM_PRE_SHA256[path], 'Complete published bb5 source not restored: ' + "
  'path)\n'
  '    return old',
  'def album_predecessor_source(path, raw):\n'
  '    """Exact complete published bb5 bytes; never a current-input admission bypass."""\n'
  '    if path not in ALBUM_PRE_SHA256:\n'
  '        return raw\n'
  '    if digest(raw) == ALBUM_PRE_SHA256[path]:\n'
  '        return raw  # Explicit historical-only interface; current checks require new bytes.\n'
  '    if path == ALBUM_LEAF_PATH:\n'
  '        old = _inverse_exact(raw, ALBUM_LEAF_ROW, path)\n'
  '    elif path == ALBUM_HELPER_PATH:\n'
  '        old = _inverse_exact(raw, ALBUM_HELPER_ROW, path)\n'
  '    elif path == SELF_PATH:\n'
  '        old = _album_category_preimage(raw)\n'
  '    elif path == PROFILE_PATH:\n'
  '        slot = b"DISCOVERY_HELPER_FINGERPRINT = \'" + ADMISSION_FINGERPRINT.encode() + b"\'"\n'
  "        require(raw.count(slot) == 1, 'Unknown album profile source pin')\n"
  '        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = \'" + ALBUM_PRE_FINGERPRINT.encode() + '
  'b"\'", 1)\n'
  '    elif path == RUNNER_PATH:\n'
  '        native_current_readiness_source(raw)\n'
  '        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = \'([0-9a-f]{64})\'$", raw)\n'
  "        require(len(pins) == 1, 'Unknown album readiness pin')\n"
  '        old = raw.replace(pins[0], ALBUM_PRE_CONTRACT_SHA256.encode(), 1)\n'
  '    elif path == CATEGORY_GATE:\n'
  '        normalized, source = _decoded_external_template(raw)\n'
  "        require(source == (ROOT / SELF_PATH).read_bytes(), 'Unknown album complete external template')\n"
  '        old_source = _album_category_preimage(source)\n'
  '        encoded = encode_frozen_source(old_source).decode()\n'
  "        first = b'\\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\\n'\n"
  "        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\\n'\n"
  '        suffix = b"\\nif __name__ == \'__main__\':\\n    unittest.main()\\n"\n'
  "        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\\n' + "
  "b''.join(\n"
  "            ('    ' + repr(encoded[i:i+80]) + '\\n').encode() for i in range(0, len(encoded), 80)) + "
  "b')\\n' + last + suffix\n"
  '    else:\n'
  "        raise AssertionError('Unreviewed album predecessor path')\n"
  "    require(digest(old) == ALBUM_PRE_SHA256[path], 'Complete published bb5 source not restored: ' + "
  'path)\n'
  '    return old'))
BYTE_CACHE_ALBUM_PREFIX_COUNT = 4

# The four changed functions above the album marker must still restore every
# complete bb5-and-earlier source. Pure compression helpers add no fixture input.
ALBUM_CATEGORY_PREFIX_HUNKS = ALBUM_CATEGORY_PREFIX_HUNKS + [
    {'before': before, 'after': after}
    for before, after in BYTE_CACHE_SOURCE_HUNKS[:BYTE_CACHE_ALBUM_PREFIX_COUNT]
]


def _byte_cache_category_preimage(raw):
    """Restore the complete published native54 module by exact finite spans."""
    marker = b'\n# Exact native54 bounded byte-transform performance predecessor.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == IMPLEMENTATION_SHA256, 'Changed complete byte-transform admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown byte-transform source boundary')
    prefix, _ = raw.split(marker, 1)
    for before, after in reversed(BYTE_CACHE_SOURCE_HUNKS):
        before, after = before.encode(), after.encode()
        require(prefix.count(after) == 1, 'Changed exact byte-transform inverse span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Changed byte-transform fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + BYTE_CACHE_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == BYTE_CACHE_PRE_SHA256[SELF_PATH], 'Complete native54 admission not restored')
    return old


def byte_cache_predecessor_source(path, raw, *, root=ROOT):
    """Audit the exact native54 predecessor only after fresh current admission."""
    root = Path(root)
    require(path in BYTE_CACHE_PRE_SHA256, 'Byte-transform predecessor escaped its five-source domain')
    current_contract = (root / CONTRACT_PATH).read_bytes()
    checked_current(current_contract, root)
    require(raw == (root / path).read_bytes(), 'Changed actual byte-transform predecessor input')
    if path == SELF_PATH:
        old = _byte_cache_category_preimage(raw)
    elif path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Changed byte-transform profile slot')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + BYTE_CACHE_PRE_FINGERPRINT.encode() + b"'", 1)
    elif path == RUNNER_PATH:
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
        require(len(pins) == 1 and pins[0].decode() == digest(current_contract), 'Changed byte-transform runner pin')
        old = raw.replace(pins[0], BYTE_CACHE_PRE_SHA256[CONTRACT_PATH].encode(), 1)
    elif path == CONTRACT_PATH:
        value = json.loads(raw)
        require(encode(value) == raw, 'Noncanonical byte-transform contract')
        for name in (SELF_PATH, CATEGORY_GATE, PROFILE_PATH):
            require(value['feature_batch_support_sha256'][name] == digest((root / name).read_bytes()),
                    'Changed byte-transform current support: ' + name)
            value['feature_batch_support_sha256'][name] = BYTE_CACHE_PRE_SHA256[name]
        old = encode(value)
    else:
        normalized, source = _decoded_external_template(raw)
        require(source == (root / SELF_PATH).read_bytes(), 'Changed byte-transform external template source')
        encoded = encode_frozen_source(_byte_cache_category_preimage(source)).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
    require(digest(old) == BYTE_CACHE_PRE_SHA256[path], 'Complete native54 source not restored: ' + path)
    return old

if __name__ == '__main__':
    unittest.main()
