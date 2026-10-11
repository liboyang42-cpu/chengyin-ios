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
ADMISSION_FINGERPRINT = '9bd4ce8d5dfa9ffee65b9443ab0efa900dbfce4d353dc0fe5a39d0ea77846928'
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
    club_authenticate_current(raw, root)
    require((root / CONTRACT_PATH).read_bytes() == raw, 'Live current contract differs from supplied bytes')
    require(digest(club_predecessor_source(NATIVE_PROJECTION_PATH, (root / NATIVE_PROJECTION_PATH).read_bytes())) == ACTOR_PROJECTION_ROW['after_sha256'], 'Changed actual current projection source')
    try:
        runner = uncached_readiness_source(native_current_readiness_source(club_current_readiness_source((root / RUNNER_PATH).read_bytes())))
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
        if files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH, ALBUM_LEAF_PATH} | set(CLUB_PRODUCT_SHA256):
            # Every actual P045 member is present before any predecessor/cache reuse.
            for path, data in incoming.items():
                require(data == (ROOT / path).read_bytes(), 'Changed/mixed club current fixture: ' + path)
        elif files == set(PROFILE_CONTEXT_INPUTS) | set(REPAIR_LEAF_PATHS) | set(NATIVE_CURRENT_INPUTS) | {DESCRIPTION_LEAF_PATH, ACTOR_LEAF_PATH, ALBUM_LEAF_PATH}:
            # Exactly published e2b/54; partial current inputs are never backfilled.
            for path, data in incoming.items():
                expected = club_predecessor_fixture_source(path, (ROOT / path).read_bytes(), current_raw)
                require(data == expected, 'Changed/mixed historical e2b/54 fixture: ' + path)
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
        _reject_invalid_historical_creator_fixture(root, live_root=live_root)
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
    raw = club_readiness_source(raw)
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
    require(digest(club_predecessor_source(pbx, (ROOT / pbx).read_bytes())) == NATIVE_PBX_REPAIR_ROW['after_sha256'], 'Native canonical PBX bytes changed')
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
    raw = club_predecessor_source(SELF_PATH, raw)
    marker = b'\n# Exact bb5 album chapter actor predecessor layer.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == CLUB_PRE_SHA256[SELF_PATH], 'Changed complete album admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown album layer source boundary')
    prefix, _ = raw.split(marker, 1)
    for hunk in reversed(ALBUM_CATEGORY_PREFIX_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        require(prefix.count(after) == 1, 'Missing/repeated album source interface span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Unknown album admission fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + ALBUM_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == ALBUM_PRE_SHA256[SELF_PATH], 'Complete published bb5 admission source not restored')
    return old


def album_predecessor_source(path, raw):
    """Exact complete published bb5 bytes; never a current-input admission bypass."""
    if path in ALBUM_PRE_SHA256 and digest(raw) == ALBUM_PRE_SHA256[path]:
        return raw  # Explicit exact published bb5 historical input.
    raw = club_predecessor_source(path, raw)
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
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Unknown album profile source pin')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + ALBUM_PRE_FINGERPRINT.encode() + b"'", 1)
    elif path == RUNNER_PATH:
        native_current_readiness_source(raw)
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
        require(len(pins) == 1, 'Unknown album readiness pin')
        old = raw.replace(pins[0], ALBUM_PRE_CONTRACT_SHA256.encode(), 1)
    elif path == CATEGORY_GATE:
        normalized, source = _decoded_external_template(raw)
        require(source == club_predecessor_source(SELF_PATH, (ROOT / SELF_PATH).read_bytes()), 'Unknown album complete external template')
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
    club_authenticate_current((root / CONTRACT_PATH).read_bytes(), root)
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
    value = _club_restore_contract(value)
    raw = encode(value)
    contents = {path: club_predecessor_source(path, data) for path, data in contents.items()}
    runner = contents[RUNNER_PATH]
    native_current_readiness_source(runner)
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete album contract pin')
    module = contents[SELF_PATH]
    require(digest(module) == CLUB_PRE_SHA256[SELF_PATH], 'Loaded album admission differs from current bytes')
    _, frozen = _decoded_external_template(contents[CATEGORY_GATE])
    require(frozen == module, 'Changed complete authenticated e2b album external template')
    slot = b"ADMISSION_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'"
    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '<SELF>'", 1)) == CLUB_PRE_FINGERPRINT,
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
    if digest(encode(value)) == CLUB_PRE_CONTRACT_SHA256:
        club_authenticate_current((Path(root) / CONTRACT_PATH).read_bytes(), root)
    else:
        album_current_inputs(value, root)
        value = club_predecessor_contract(value)
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
    raw = club_predecessor_source(SELF_PATH, raw)
    marker = b'\n# Exact native54 bounded byte-transform performance predecessor.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == CLUB_PRE_SHA256[SELF_PATH], 'Changed complete byte-transform admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown byte-transform source boundary')
    prefix, _ = raw.split(marker, 1)
    for before, after in reversed(BYTE_CACHE_SOURCE_HUNKS):
        before, after = before.encode(), after.encode()
        require(prefix.count(after) == 1, 'Changed exact byte-transform inverse span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'"
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
    raw = club_predecessor_fixture_source(path, raw, current_contract)
    current_contract = encode(_club_restore_contract(json.loads(current_contract)))
    if path == SELF_PATH:
        old = _byte_cache_category_preimage(raw)
    elif path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'"
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
            require(value['feature_batch_support_sha256'][name] == digest(club_predecessor_source(name, (root / name).read_bytes())),
                    'Changed byte-transform current support: ' + name)
            value['feature_batch_support_sha256'][name] = BYTE_CACHE_PRE_SHA256[name]
        old = encode(value)
    else:
        normalized, source = _decoded_external_template(raw)
        require(source == club_predecessor_source(SELF_PATH, (root / SELF_PATH).read_bytes()), 'Changed byte-transform external template source')
        encoded = encode_frozen_source(_byte_cache_category_preimage(source)).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
    require(digest(old) == BYTE_CACHE_PRE_SHA256[path], 'Complete native54 source not restored: ' + path)
    return old

# Exact published7bf rejection-only creator fixture predecessor.
FIXTURE_REJECTION_SOURCE_BASE_COMMIT = '7bf858c23374b808c6d932367f96e97d09e9d799'
FIXTURE_REJECTION_SOURCE_BASE_TREE = '94f43a19209607d403b47f3cdada1cfadf9c9aba'
FIXTURE_REJECTION_PRE_FINGERPRINT = '1593f471ec9335da9f0c9e72db12061f037ae7ae3a1fe4b00c8431f4641ae3b3'
FIXTURE_REJECTION_PRE_SHA256 = {'Tests/ContractChecks/test_category_roam_registration.py': '5c72f6dd5b8dbe54413e9351272418968c637dae78133e48946ed365e1442597',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '65e3f5cb35be878a8ed78afb4357e8588d9bb778ae33d4f95d6ba504ef031dd7',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': '664c7d0b0e8166687c0bc0814a9c2a801518dde1be3692dc59c5957a53d3d22a',
 'tools/run138_editor_readiness_contract.json': '4f1ca536a2e6f2b0bc8a77a9849cbe49325cc508e44cefb0363a59d75db5b151',
 'tools/run138_editor_readiness.py': '9beed44a6cde9dd4db65a7e721e92702cc7f86eb4209061bdf3777fa6b173b95'}
FIXTURE_REJECTION_SOURCE_HUNKS = (('def creator_history_root(root, *, live_root=ROOT):\n'
  '    try:\n'
  '        _, _, context = _profile_parent_inputs(live_root)\n'
  '        root = Path(root)\n'
  '        # Existing bounded legacy fixtures keep their original strict domain.\n'
  '        # The actual current root and our authenticated parent context are explicit.\n'
  '        if root.resolve() == Path(live_root).resolve(): return context\n'
  '        if str(root.resolve()) in _profile_origins: return root\n'
  '        require(not (root / CONTRACT_PATH).exists() and not (root / CONTRACT_PATH).is_symlink(),\n'
  "                'Unknown mixed current creator history root')\n"
  '        # The pre-existing eight-input synthetic fixture can contain the new\n'
  '        # catalog/gate only as an exact complete current eight-file group.\n'
  '        # Old fixtures still proceed to the unchanged strict old state reader.\n'
  '        incoming = {p: (root / p).read_bytes() for p in CREATOR_FIXTURE_INPUTS if (root / p).exists()}\n'
  '        new_catalog = CATALOG_PATH in incoming and digest(incoming[CATALOG_PATH]) == '
  "CURRENT_SOURCE_ROWS[CATALOG_PATH]['after_sha256']\n"
  '        new_gate = CREATOR_RAW_GATE_PATH in incoming and digest(incoming[CREATOR_RAW_GATE_PATH]) == '
  "EXTRA_INPUT_ROWS[CREATOR_RAW_GATE_PATH]['after_sha256']\n"
  '        if new_catalog or new_gate:\n'
  "            require(set(incoming) == set(CREATOR_FIXTURE_INPUTS), 'Incomplete current eight-file creator "
  "fixture')\n"
  '            for path, data in incoming.items():\n'
  "                require(not (root / path).is_symlink(), 'Symlink in current creator fixture')\n"
  "                require(data == (Path(live_root) / path).read_bytes(), 'Mixed current creator fixture: ' "
  '+ path)\n'
  '            old = {p: (context / p).read_bytes() for p in CREATOR_FIXTURE_INPUTS}\n'
  '            return _bounded_context(_creator_fixture_contexts, str(root.resolve()), old, '
  "'category-roam-creator8-')\n"
  '        return root\n'
  '    except (AssertionError, OSError, KeyError, TypeError, UnicodeError) as error:\n'
  '        raise ValueError(str(error)) from error',
  'def creator_history_root(root, *, live_root=ROOT):\n'
  '    try:\n'
  '        _reject_invalid_historical_creator_fixture(root, live_root=live_root)\n'
  '        _, _, context = _profile_parent_inputs(live_root)\n'
  '        root = Path(root)\n'
  '        # Existing bounded legacy fixtures keep their original strict domain.\n'
  '        # The actual current root and our authenticated parent context are explicit.\n'
  '        if root.resolve() == Path(live_root).resolve(): return context\n'
  '        if str(root.resolve()) in _profile_origins: return root\n'
  '        require(not (root / CONTRACT_PATH).exists() and not (root / CONTRACT_PATH).is_symlink(),\n'
  "                'Unknown mixed current creator history root')\n"
  '        # The pre-existing eight-input synthetic fixture can contain the new\n'
  '        # catalog/gate only as an exact complete current eight-file group.\n'
  '        # Old fixtures still proceed to the unchanged strict old state reader.\n'
  '        incoming = {p: (root / p).read_bytes() for p in CREATOR_FIXTURE_INPUTS if (root / p).exists()}\n'
  '        new_catalog = CATALOG_PATH in incoming and digest(incoming[CATALOG_PATH]) == '
  "CURRENT_SOURCE_ROWS[CATALOG_PATH]['after_sha256']\n"
  '        new_gate = CREATOR_RAW_GATE_PATH in incoming and digest(incoming[CREATOR_RAW_GATE_PATH]) == '
  "EXTRA_INPUT_ROWS[CREATOR_RAW_GATE_PATH]['after_sha256']\n"
  '        if new_catalog or new_gate:\n'
  "            require(set(incoming) == set(CREATOR_FIXTURE_INPUTS), 'Incomplete current eight-file creator "
  "fixture')\n"
  '            for path, data in incoming.items():\n'
  "                require(not (root / path).is_symlink(), 'Symlink in current creator fixture')\n"
  "                require(data == (Path(live_root) / path).read_bytes(), 'Mixed current creator fixture: ' "
  '+ path)\n'
  '            old = {p: (context / p).read_bytes() for p in CREATOR_FIXTURE_INPUTS}\n'
  '            return _bounded_context(_creator_fixture_contexts, str(root.resolve()), old, '
  "'category-roam-creator8-')\n"
  '        return root\n'
  '    except (AssertionError, OSError, KeyError, TypeError, UnicodeError) as error:\n'
  '        raise ValueError(str(error)) from error'),)
FIXTURE_REJECTION_GIT_STATES = (('334b93752e26bc4f005f7aec3e5bc3fa89a15947',
  '09334269bacd076a5cdb4da03a5da1b4ec0156ea',
  (('App/TemplateAuthoringMineView.swift',
    '882bdcf7b5467e0f57dc28c21b3e7c38e32b956f4c19a2713a1d88b31e4cb85d'),
   ('Core/TemplateAuthoringShelf.swift', '079a78c9ca829f79bf35fff0eb3c9dc575baddd7332ae20e092b3eba22a4a5f6'),
   ('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
    'd0a7f13f6f66fdf29d2db630d5aefc5f97113921d7c3977d5a0e1f9793123224'),
   ('Tests/ContractChecks/test_template_shelf_read_bridge.py',
    'efe2ba8a755453f86964af41c5335fb41abb7423d5d173500a7df8e9502347b2'),
   ('Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
    '95bb75ebea6aa3b76314843463ca7e09e2bab68366281b4e99b1cbbcb8155baa'))),
 ('6ae3e545b373dd5cddc47356a57d0cb6ee928e70',
  'dc1573c54487cb5402b083b0ff91d3a98025eca9',
  (('App/TemplateAuthoringMineView.swift',
    '91d2c740529dd2970568cacfcd68409618c6e2d1d6cda007daccfdb3dc8164d7'),
   ('Core/TemplateAuthoringShelf.swift', '3d8865b315f1712f0056d1b376f0f7f2b1aa01e8417dab95f438c200cefe2e91'),
   ('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
    '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673'),
   ('Tests/ContractChecks/test_template_shelf_read_bridge.py',
    'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8'),
   ('Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
    '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6'))),
 ('b75f7549678caf51a65ec8942b6a6d0c23e887de',
  '6d5a1e4a1486b3e97ed2f1e995ac5194e568bc20',
  (('App/TemplateAuthoringMineView.swift',
    '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f'),
   ('Core/TemplateAuthoringShelf.swift', 'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a'),
   ('Resources/Localizable.xcstrings', '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995'),
   ('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
    '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673'),
   ('Tests/ContractChecks/test_template_shelf_read_bridge.py',
    'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8'),
   ('Tests/ContractChecks/test_template_shelf_state_projection.py',
    '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4'),
   ('Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
    '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6'),
   ('Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift',
    'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87'))),
 ('7bf858c23374b808c6d932367f96e97d09e9d799',
  '94f43a19209607d403b47f3cdada1cfadf9c9aba',
  (('App/TemplateAuthoringMineView.swift',
    '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f'),
   ('Core/TemplateAuthoringShelf.swift', 'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a'),
   ('Resources/Localizable.xcstrings', '901ba5a72ab2748c171483dff7743c63a30552ab9ded21b2c3379ae410f2a898'),
   ('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
    '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673'),
   ('Tests/ContractChecks/test_template_shelf_read_bridge.py',
    'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8'),
   ('Tests/ContractChecks/test_template_shelf_state_projection.py',
    'f229a3c1447956510c42368847e70a3c94d0935b838828bb959e124507b51595'),
   ('Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
    '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6'),
   ('Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift',
    'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87'))))

import stat


def _reject_invalid_historical_creator_fixture(root, *, live_root):
    """Only reject definite invalid complete legacy fixtures; never admit one.

    Current roots, authenticated contexts, unusual paths, incomplete inventories
    and uncertain reads retain the original complete admission chain. Every
    preliminary member and byte read is fresh; no health result is retained.
    """
    if type(root) not in (str, type(Path())) or type(live_root) not in (str, type(Path())):
        return
    states = tuple(dict(state[2]) for state in FIXTURE_REJECTION_GIT_STATES)
    five, eight = frozenset(states[0]), frozenset(states[2])
    directories = {parent.as_posix() for name in eight for parent in Path(name).parents
                   if parent != Path('.')}
    try:
        root = Path(root)
        # lstat precedes resolve so even self-referential symlinks are uncertain.
        if not stat.S_ISDIR(root.lstat().st_mode):
            return
        resolved = root.resolve()
        if resolved == Path(live_root).resolve() or str(resolved) in _profile_origins:
            return
        pending, files, seen, actual_directories = [root], set(), set(), set()
        while pending:
            directory = pending.pop()
            # Unlike rglob/Path.walk, iterdir does not suppress scandir errors.
            for path in directory.iterdir():
                name = path.relative_to(root).as_posix()
                if name in seen:
                    return
                seen.add(name)
                mode = path.lstat().st_mode
                if stat.S_ISDIR(mode):
                    if name not in directories:
                        return
                    actual_directories.add(name)
                    pending.append(path)
                elif stat.S_ISREG(mode):
                    if name not in eight:
                        return
                    files.add(name)
                else:
                    # Symlinks, FIFO, socket and device nodes are uncertain.
                    return
        if files not in (five, eight):
            return
        required_directories = {parent.as_posix() for name in files for parent in Path(name).parents
                                if parent != Path('.')}
        if actual_directories != required_directories:
            return
        identities = {name: digest((root / name).read_bytes()) for name in files}
    except (OSError, ValueError, RuntimeError):
        # Only preliminary path/inventory/read errors fall through. The original
        # implementation owns their final exception and current-source checks.
        return
    if any(identities == state for state in states):
        return
    if files == five:
        raise ValueError('Mixed or unreviewed shelf refresh source bundle')
    if (identities[CATALOG_PATH] == states[3][CATALOG_PATH]
            or identities[CREATOR_RAW_GATE_PATH] == states[3][CREATOR_RAW_GATE_PATH]):
        for name in CREATOR_FIXTURE_INPUTS:
            if identities[name] != states[3][name]:
                raise ValueError('Mixed current creator fixture: ' + name)
    raise ValueError('Mixed, incomplete or unreviewed shelf state source bundle')

# Both older complete-source inverses retain their original boundaries and
# checks. The new finite creator call is removed before their old hash checks.
BYTE_CACHE_SOURCE_HUNKS = BYTE_CACHE_SOURCE_HUNKS + FIXTURE_REJECTION_SOURCE_HUNKS
ALBUM_CATEGORY_PREFIX_HUNKS = ALBUM_CATEGORY_PREFIX_HUNKS + [
    {'before': before, 'after': after} for before, after in FIXTURE_REJECTION_SOURCE_HUNKS
]


def _fixture_rejection_category_preimage(raw):
    raw = club_predecessor_source(SELF_PATH, raw)
    marker = b'\n# Exact published7bf rejection-only creator fixture predecessor.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == CLUB_PRE_SHA256[SELF_PATH], 'Changed complete fixture-rejection admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown fixture-rejection source boundary')
    prefix, _ = raw.split(marker, 1)
    for before, after in reversed(FIXTURE_REJECTION_SOURCE_HUNKS):
        before, after = before.encode(), after.encode()
        require(prefix.count(after) == 1, 'Changed exact fixture-rejection inverse span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Changed fixture-rejection fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + FIXTURE_REJECTION_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == FIXTURE_REJECTION_PRE_SHA256[SELF_PATH], 'Complete published7bf admission not restored')
    return old


def fixture_rejection_predecessor_source(path, raw, *, root=ROOT):
    """Restore exact published7bf source bytes only after fresh current admission."""
    root = Path(root)
    require(path in FIXTURE_REJECTION_PRE_SHA256, 'Fixture-rejection predecessor escaped its five-source domain')
    current_contract = (root / CONTRACT_PATH).read_bytes()
    checked_current(current_contract, root)
    require(raw == (root / path).read_bytes(), 'Changed actual fixture-rejection predecessor input')
    raw = club_predecessor_fixture_source(path, raw, current_contract)
    current_contract = encode(_club_restore_contract(json.loads(current_contract)))
    if path == SELF_PATH:
        old = _fixture_rejection_category_preimage(raw)
    elif path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Changed fixture-rejection profile slot')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + FIXTURE_REJECTION_PRE_FINGERPRINT.encode() + b"'", 1)
    elif path == RUNNER_PATH:
        pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
        require(len(pins) == 1 and pins[0].decode() == digest(current_contract), 'Changed fixture-rejection runner pin')
        old = raw.replace(pins[0], FIXTURE_REJECTION_PRE_SHA256[CONTRACT_PATH].encode(), 1)
    elif path == CONTRACT_PATH:
        value = json.loads(raw)
        require(encode(value) == raw, 'Noncanonical fixture-rejection contract')
        for name in (SELF_PATH, CATEGORY_GATE, PROFILE_PATH):
            require(value['feature_batch_support_sha256'][name] == digest(club_predecessor_source(name, (root / name).read_bytes())),
                    'Changed fixture-rejection current support: ' + name)
            value['feature_batch_support_sha256'][name] = FIXTURE_REJECTION_PRE_SHA256[name]
        old = encode(value)
    else:
        normalized, source = _decoded_external_template(raw)
        require(source == club_predecessor_source(SELF_PATH, (root / SELF_PATH).read_bytes()), 'Changed fixture-rejection external template source')
        encoded = encode_frozen_source(_fixture_rejection_category_preimage(source)).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
    require(digest(old) == FIXTURE_REJECTION_PRE_SHA256[path], 'Complete published7bf source not restored: ' + path)
    return old

# Exact e2b P045 public-member route predecessor layer.
def _club_fixed_constant(encoded, expected):
    raw = decode_frozen_source(encoded)
    require(digest(raw) == expected, 'Changed exact club constant payload')
    return ast.literal_eval(raw.decode())

CLUB_PRE_CONTRACT_SHA256 = _club_fixed_constant(
    b'c-jrixdFf+3<R)oX#K(Aas0&lj}R(VT6>foq@4#%xQvP#IUgo-v$;)Q;pDLNhZ$s(zCb~)wSGuR5iI'
, '2f2cc6f30dcaa4d01c0ade90fad3079f5b8b1c125afe1a5cc803a0e82ff65982')
CLUB_PRE_FINGERPRINT = _club_fixed_constant(
    b'c-jTQ!2!S^2m`=z{0auC<3JksAHlnU&80K<QGji>JP&0`;l{*nT0|Sxhxo&@=mktse#=wi0YM`XnE'
, 'beefdbff26b1885bc79bb2c4376a6c4327e68e79ce62efb03e88f1e2eb927d59')
CLUB_PRE_SHA256 = _club_fixed_constant(
    b'c-oDXTW{n<5QYEBzRe3ts_)&rp-2lzfCK_wt?IfYW@pBc?b#$k{CCRPY%UP8JlNwId;05Bbx!%u-8a|Q=NJ1^|91K)^AV3E@5kHq'
    b'G|P9>vYstBqprKJ-|c$KAvSVcT2BQts*4#N^;E@`q~4>{PA>QyT=6aml#)AV1`uVx`|8~*sNYAqS)L&3Th9<%sGNeaLM!SRTWHw{'
    b'ip#}gg&tFf)G2_=$&Or@atc9pgZzAwWgYeI?3N~$>v{U)d^-uPXV?99yWB|LITbINg<UETF;&kkMCi6UyH>LYRB^6$kIWG`LoTg)'
    b'=s9Xm8|haAE$1fcx9>k)ZrXkjWSRSfGyf=uF7x~SbaQ|EQRYw6QC|H0IIeFj@XK^s<&70CrsFyztru59AC~jgejEr_xt!*^VV>|X'
    b'%yKy{_RKm?$Fu9ZO+Sm|mbHY6SyF|TT((9gMUCo8q#iXo&6>PaBz0g#kF_e1=a}8@ZM^9i=(McULFVCu+}%tw4=jB;S<@f3;IkL@'
    b'>e;#ExZ8eOgjfyW#GKP=X-z3a%#~0&rbbX(ED0)A$@D+Auz#xMaJVn#aKw+}<+DnBv6PqlspEcF1ZTQ>R#>6U#di;4TC+@$?~w(p'
    b'h|vzPNE9#HOLe4{9xBZ$92_MAHAyi829qnzeL;-5R>!><6nRh__ZCn4a+p>bkPqXsJnL-W?#P>A#YJeLC(Dj@R~V`nzopo=njKUC'
    b'->P#Ew3^{NVDjAWoxM)eemQ^HMIKG^x=H^hvAAk6t)(>cPK>_ho}jB{#?l1=$rmEaj&z7jO*jN#^{KbiSoDcFpN=k6W6rZ2*I}7X'
    b'Gs*A}-zQ*bW>_#m7;GttVAH2j)|xU>so-OGHMS~PD5xRXR}RrKtrq7B{{jk+rtH4F<58C7vqQZ#(kRVK^eKphgdA<?^xnL;;l^2e'
    b'4Z%v9sN3iu&f6m;qGa>(6KB0|?I&XzWrJN=B)4knr)g{Omm(oQ>^-K;ttzBy!BpJrk}wCf6j~ljRBgQ!pkyO0HD46`cJo#Eqr!n6'
    b'Y&KluyomXlu097dn<=z&Nv@&IcMB;-=d&}bX0-lhJBPr{H6IJP8ZdaZHv$$&#n`WtU$&OU!9E`2<3*wZBjo@#2nsu3$f+fC=AKkI'
    b'0mr6IG}?5~ra&&mCP{5>Db%-+|Iu7qxLPO*6tprjyJ8{ms%GDix#m*H(qKM9Bm@Y~-b9crPPU~OIPL!W8}pb@+5'
, 'ad73c7727c4a68788772da4dfeae8f5bd0d21bc30cfbfc3b28db3a92b98d29e0')
CLUB_PRODUCT_SHA256 = _club_fixed_constant(
    b'c-noDO^*{X42J*8-g-f8zU;)@P^ASVIDmj_6*~?LbZ4rWbh|6We<!mXD$t6HW!X}m$8UaaUY$<6{qfANr+b~pJc@o9^s;Q1%TU|q'
    b'<;|u#bTI&l*60m+MYJ&xL{lgfDrf@uOdw*aO*xUpBrFMPqU^zLUfetbxg8$bdDb`6(yplf79oUWeDq|atr7tXRb;HiDg>tyD6%G$'
    b'%-sf4Rs+5y6HCZ-MSaqxExQi<{Ps_~a^Gn#I`fq0@?P&)=iB3Sd0JoLF}RXVFo2#?W%Nk|yk@l!0!8uOF$spQW^#<^5TS&^F<R(?'
    b'<!|^nwEy5gPUoio@X2OttaSwBeR5qUg5#WPkHU#0^$1{@6;jW@gDbW6jJPHtbk1G*`)O=*mbU+<@?+VxK0HX*I2^AYhr1_{!<g@f'
    b'uelA=xII0t8j0Cu1>)>PQ{a$o?Qz@n@6iAQ5lJjD0ekcTj8gGV88xcu!K@k|&K)__$L)hmMNjkeeYX~swmtE~+O8y5Oy)vh`)!;k'
    b'R^}Rl^F8(`nXsao^*92oT&%Y$j-9iP)rY>@{Q3=>CfLL'
, '900c639d22d354aa3db730a338200c43fc72b69e2f6e082c2c77f3e52982f81b')
CLUB_CURRENT_INPUTS = _club_fixed_constant(
    b'c-oDUK~KXl42Ay+w}FIOAue3eqyZ8fK)^Lh6SvFO#+B`^>%YhCCc24^?b0Ug_w4uLT+bfsI-QqI_JkXtXrqHg*h)k2j4TPaA(z?h'
    b')dcn(pyd&GZ-6D_U9xrPp(b3V{R5mNb++x7J@u&&r&{dmWw-2WzJm2Y8CvphP-Q@i65HYTSbh}7Apb}|uo0Nl&M^vEC-Wt^HK(E<'
    b'jk5v;QfCNlWeAGE%1FSN)ZH1Wb~mnJ!3xN%p=*)6@sMGohjW>{9Nn90uy3N>gyJ#>MTwa$4TB}OJct6WpHX*KuQSO*2`aGO<TjK#'
    b'blp@aV63kK^XNhlOHPk7`=G6)Z#hj<6YuUHlqZ5HhOr?BW`8M8z~F;c94v(h%$G36?ZYK2#yH|KB;TF3!o6mx^X(1iyDP3Wro0>o'
    b'|28qTB?diiw}g|b<K!+Fef>`46h4*x<_D{*V2l'
, 'e9865c7234736f0a349e6bdb50dfaa5a03328c28db3963bef6c41793f779760a')
CLUB_SOURCE_ROWS = _club_fixed_constant(
    b'c-ri}3zr+$btU{)5KdN1uAy7^QTIiUqx93_#Ih7ocD}VFEv@?`F={qC0GblV@qhpJE&$zCK%qq|o;aS7oJb^4s8jde^Vs{`b5H&8'
    b'7pJ$kADv&{rQa;x)#XjR$@Oaf!}@MnKUu8SC#&!0ZT*WEvp@bK)wWpHZ&z=kG8UiwA_c3vkY#Zp85eDAva?a<WPFv*G^JwoDNC)a'
    b'mQG1ig>yC)TZE{ss9!vv{UWw?T@LP9tO(Y0UTCL-bh2e<YzfUK+ls8FQ`MQ^QuQ{+<g~CpR$+AU!j&#I-t*1f&37x@?5o`~^Tz*e'
    b'-ewn<XTSf=*EjRGw~OU^_KG9>{mZX!zP|aVPviXNG_M!S*=oJK%j?<E33)O5!@Pb!`{UO)GyL;Uuhwy0KTH3s;y1U;`8)h=_Ac@^'
    b'kURVJ^nG6O%csvax8T)jQQp6ptrl<V=<fUnkNx>_k?U&p@}@0LZU=vk%hz{r>&<#~k{35?j9~Tj$uEDIA@P?K|NfV&TyNrXzIgI%'
    b'_Q(E7DER$gFi)S&{`4TKUa#s;l-Fu4hvKgA>EqJ=IJ>T|V}5^z3D|wP{m*bVA1*pFOTUZn=C9*=zPQ1H<nM-G@t@z$SL^-H_|KR1'
    b'hxOAZ9Kp%!#k-T$`<wNfx}N7J&rV|IxaVnpJzu|nSupH*o7d&^)nDJ->++B2+V=0CrBz+N>mT@M{rfBG-%pcvU1O=sw1~^G(6NI3'
    b'p;yJHtJ|38H?LpJx@S`=cy_m5FK&iv_5FOE-<;;WxVu^RL+RIY{P}n&!+$<NaR-lo(l*nxz5A1Ahd0F(Z5{xV)8^Opi~iRqZx+{O'
    b'_4)3j)$QVDRaa93<UgNGTIGQyLQNBF;_ZvstMw9d_H;_{Y8{vBTFyBQ&z>E><9}c>wgO*mBt3cdmw4>kdQ<S-f5KybzLE5odF*Ay'
    b't#AHQru&Pns6XSuAA91hrM$d2c^hw^ZiaX=znQO}%|8Bk_T*-9Q=j~w8PDDm{DsEzX?>gO@~=3Y%>x`0a>O0&+}jrww}!)gQ?JWx'
    b'JHUZ++aGd&@m7(yPG)u7=k<dt^HogOwfv~{&3^ssnRsNXe)2SJ9(p&nLje;{{{U>p-wiJP)BkNq=}*sRLts9sOtb5l>NQx$M(}SJ'
    b'IbP5IcP$&e|L6LCaQ7#(|2|vX)@47alV$w=5Api0K7+P=z@zO}@5oI)Xc2#U2>+0|8{g|gq|e{pT|*y!fAihV;`^I{{Ef7e@0as+'
    b'y^8beyB;E*+-)v=`W9ct*Y(BhW`6yF54SIBPmBMI1z0W?7~aXvy?TB*Utib3h2Jlh-w{iVOzXiA{xm|-JCkVhn|M9T*KxIa1PZ^{'
    b';c@tnEtcMzz;#{EHe)!3rBC~BcVPND{_pp_9p=Si36B%`F#EqefB5d{=H@T9LbiALr_b-w^?dcFmi}Jze%{uwXx@h&?dA59kGXsd'
    b'0=&;A+P#=LA)n9c?IOQ<F_YUn_ScN?CvW_YI(}?mtCRlgrzh*h?L2>mZ{NX{JUdxzCI~_2s~6vl@0Z`iTTmd*RsY+sp6ouMTY2)$'
    b'#{kvK_`d(`HzSHM_%(jK`xTU9xmtg`6S?P>wpV@i<R-qYPrl()tTsUA$#w|4OP)OY)%`uc68)8%TRz=>dZ<yGAx(^dKki4d`|S!h'
    b'-x?ODaEaCGeaBbhi5p6NH}EZ6dF}2d&-VSpV8B$wWxc(I{*#n!7j38uBNYhYUIm`+)aT=q{u9o=cm{VT2czB&V0S5QKM;05z9qyB'
    b'{02ODniu@!S3`9_$yB22FDgg<6q7T3)1l%1H%8~SN1}g@3qQw&pB@)Z>dm|Pa&bddd;0a)C%pXfX1Tb&<|kW__Ix}30i4@@^X$J`'
    b'T&e5X2+?k0!EYZPeEYM{hZjBkcJ*&}ak>2z5?}Ry-Tq|r=}yvag#6WDUS4g}96Pf3@k8?HaP~G2cQD=Oi<>p9_T!;ndyNMvQ-WrH'
    b'_v_h{w{s}TJp*{ML&6(ILUkOP-S*Q>JX~&PX*6liNAvJv^tZ7){@aP;y(aBaRk+QMrnAOBo!^xD1Ag|9?doIhOMd)x(O%3R&v^}R'
    b'cDRJU-rWAA!54fQZ?SR@V(`rz5BHE<`+L#Hq}j(07k#z)?3>w({k0w~>vmy&#2B7VW~^RJKR9%cOm%|Hjd|rDwjHeBu^WF6x3p8~'
    b'o&UzDolvvsMc-niWB1z{$u2+eWFIF@gOkDC2AJln9Yg`Dn&<C&WcA_!SN$F)eYd7Nn{EB`?Cmxy@D2WV1V#M}G=Bz~f4=z)9^&Nw'
    b'<9lJlZ~Kq_%YfOhZ$A3yquFPzUC(doFBdo0?`KO~wlkQM+39W)aEFZ-nq@37En&8P!%zS1uCCV5ui19on_F&DCbQMu>bBmjfP`l8'
    b'roh9l`9urg5lEW9zFF`-o5#NH0n-e3fcNCBfB$l}O;fEl_nfa!W?#OUulPvs@H@oN`Es-Hi-!B-3D$Q&Is|i&+|S(e8MNmO{J`vc'
    b'$V7Bl<nQ_+u1-c+>7O3J&r#g;BR(5wW0B|adaJ4Ykkj(V2k<dikI|)*$~xg&`xv+aGHLVIkX~?~_42L`zuYe6<qz@g?R7o4;7C|G'
    b'TP&_ei0bL8uAgo9<{ox1a6572vQg^&1Fk!L80pKK^~XPQ^)6gYT)f+Z9OqvToy2CWyEW>uPTpQTzLYV3eskArBf!s_n!n?)9zOgZ'
    b'6SsIi`(1@g`^TfH&TUTj#q6u!|DNL*KQ7(iecTva-p^(~Xuy%}XD9u{?aSbkH)wcbnsiUS#?ZM3G0?XmNP9#rdg4{D+mSuAUr(#l'
    b'$bsJuXX@$O;aWbM#npRUvVOB%e7~Cg@*k(x=MaKV%iI9&aX8$~$<V>>{y4sJi^$i@_p|tYoIgzG$+73({b@Q*_PVrjm1Q9G`Oam&'
    b'yuhbahNsWQKT7Y{{lxM~{^zUDe)p;_=S&=ISbd4>_>?}4Uu}3Al<LX6Jb8Ga=i`wL(b1Dn274N_wp_g3`R&=)Uq9VF??VjR#KkAy'
    b'Je#(s!DC+3yy&UfN$LOebYdk>s7cRzu`f2`9Nc&0Y5x1KXL4U;9}75_oAu!&OqeJ1_33}ehM&PE#uK=;ysz$8?wflI@ZeZ>e|o;>'
    b'L56>u))a)ci^c3_0e#_<j^p8*N@~t{h(#;#bo{X2CwY6f;;i%_aE-7yx*-hYVUhYYRez7|tuc$M#oZEtejQie@j`Hz)h=eXJ4EM`'
    b'eXct2*#x5pn)0gyZ;i`#8u_ce05M+Pt?BJn_z(gf-DBHx^VAE*++XjOY=Gsq-V=ZU;NkT8dT4gQDm$~p;_q&=f%>bS!}s5v4A=5x'
    b'Giy&b58wOt-DSIpf3~;x)sJNkg1da%--6ir>7fh!YNMPlA1?f6IMByj+OHmQV+VpCeKr8(M?Li5>HfkG*Grz4$;W#)U-#F1GVhCa'
    b'p5FGUzDFMuKdIZx|1u9c{S5r~voW;3&lLaZn?F6DO_VOuj8~5pEjAUB6<yH27@cL&!8KW8(80<YtF%r<FH&ccFez&xt-=3WSF$x)'
    b'w>DL@*pyYSGa=XJv<SLdD_s|i6D4#d6v#6=29vXB(nlYp^*Lp4nh#MMd9-M8XN30|=ofnw`qR7hwutOL)0c7a{$;QD;R6&})e3$1'
    b'YLm&^zqaR;_vopg^~stvVjs@-UP0RBVczw#+truzxAiKL7QBBp0&$DccgOE>4$r)JTbEyw>aNE3$fNI$-(!$@zyyr%!2+^ve)9MY'
    b'`tr3eD`-GuoINPGd-(2QJ&rCN=Wk-m<G;XilNg>3(@irtfZ5ylo)302>nSZGU;Saep{W}*H=wmWx$lYP=5F=&4M^n@)Q|b2I=dk%'
    b'Kx|C-{rZmB?EH&QXT)JMgpJqB$Xw?3cE9B95Nnowo(n-@q>lpvxrvcqP{51XClThEh(LC`3q21Vq~GUd4=nP-5t4rRIBzs#Y6(Y5'
    b')33-)yj{IntbbE)?pN{mxSQ<`>BR;y94z1V4u{uor{v{*B6*VY9{nBD7^_DgXq29L5VHZr5BoF|BN?R9|NP&*+GsIX<Lj+*4-yGP'
    b'g&#kK4o>Rs^ZOY;Hjg9h{^Lve{E;Ob-Rky3b~~OOQmySHoZOo^)40Qg?DP9en5(*7ub%Fn=-KoAjXq8ylT({~=Jsa~%xLq~$$a%{'
    b'{u)s6<;~;`=-f6KbbEu|t(<H=e!lzqA7|p=*SiNhc`(q`$0vyFfDBI$r+8F3_3)GDJ3ls(|BUm(WXpln?aZHSJ<TwI^P|^pr)I#%'
    b'AZ0sE4|&E9y~`%k`EZB+?~`-<_5s2}mA`tj{d;-x4FC|7?x{REISJni;l7n2e5*|Nt?R_MA;@PBn<V%A_&`K|&wil_bH`Aq8*q-<'
    b'zyJIA8_MFh+ohd)&>rpm`e9{z$i7KMKkvVMcpUs~@=2IbzeZ4d`p4Pdi~XTe{QYG7>De~<f)C~6`+I%L<n0s@>c82l&Vv$fKR-0)'
    b'!QdV~9LU+wxQB~=weNRHhNkslBGJ8ZxraZw1*O4{df~gPj^xP)a`!#z)A3!0+<(F&KX!xBX6Ubmj(PCx!;3aXI-(Q<r@dhptMj|%'
    b'k_hU@eDuf9Kg2Un7HvM_tv}R7gWE7MH+0owow`@5*+2ZlakZM#tNsVuPx~u2+Vv0raIn@>-i*IKqH4U^zFt0Z*C}-y+~WSD;Vphl'
    b'*+#z~>DdR}Wu$Ta+)SzLU<MAg@8MUk4wP}l!RC!3;<BgLZ&m<IeYR}5`{Q8gXZZevpzzoHntvMd<Tt>RPvN{4{hzoqF~8v!$S3{Z'
    b'n9<#Q4wZSE<~J3L``JBf{SWe|1HFB=SMs}GfAKRF`$<%6qA+;_{_nQ~UmULh8J@=)Kh2MMz90SN`HworAHT<;b9~rQn)umh9XEn^'
    b'%f8Lg^xyPk>$vcKCGpc2_ouP?z2qPN(WkY{<1Y3LIoj~T<-_<NnVO+b-{hAEYH<I@djQ)1=lP&iXCF#GaHuhS=VQ-49xCt2_y@BW'
    b'pwK@&9b3rWHP82Sckk;%tQGIpZx+k#M#gZBx0~EYzJGos@$j>%|5R1K-p@n4cqBdXv&H;PTFfH{SN5uZ=WX_P*Nbhj!eJ%uvNoWx'
    b'H+==}m)tG-<2EJE-?0AogDPYn?((O}J+OnC*){(?U<fAwEOq^KzOHXy%>Et<gqh?cZE|$;o5Qn02R`BL+jvv17R$F!mz%s>|DS1X'
    b'7?(&sA3K}DU;6P+4&$OPi`njIY@T|g9DMk7T)yt>8V^>44z4`hfkbhvS%WX}bX(%Gx!>f`-NE(S%Qlr*pyz;(yN~X-U8c@<JyP@j'
    b'vr7GyRO-N$KcZH@!Nc87>Bd&yb}8{+PoVS<(lP!sv9V6dFesbYs@i?A!fdbnc}v)yA3yXsE{vWcT%2uA)9T^t?FWyYrF_H=Mu!{E'
    b'7uT$|!z?ZLHGl7~AAPi`SR0!1vc6?Ls(-?Fb@u%m&N;UzhMO4pO{SjJa&mCTFZ#N-P5E7~s;m*1#ntTldVLMu1BK%*#G<dleb<-f'
    b'-OLbkz)x@Q`T}omR_@*RWN~x;Cf>ZReIfPUVn6TG+E~{YeTtJh_U&_4g3il<mhJ4n|MvMI*7$hKTkmJOKP|d<5p-}bp?2tu{$KIA'
    b'6OnxCkOztX)_-oc!pD6v#&BjgFcvrL{`}AN{r7M}7d0(#uez-!9Uo+VJxCR?hT~V;(wzIe;ll-+uj&uCHLph%P`?`PQuU>&dmB^3'
    b'JlRGOel=_N#jpKecfn;?-#Gl)`TgDd%SY>Yf6Fak9sd0&GJV((*^TJq!9K+<_kVx-`Tp@*#3#eYKUwv^`Rs0eUuCdYf4;cgdae)J'
    b'1pS~T-rkbGd9q1%4+`ZsAHc?+e7Dhn!FStFo_#ZX$OBQmQlC%C8+~=vOFG$o``9gqzHt2ftHpAC_I~h;{9yBd2k_))JNawa$q{e<'
    b'vmyQM7}62;h`TQb>G*+`A1u{g>Dw_&oZs{~0e>fO8&~xGAGF4OvpHf9d)Bm}2!9D<dF<TAWDR*gSv$z_?H0sLBwi-BhlaZ_`{zym'
    b';UDfl+S|%Gn3ItU8ts}4(;`Cz^>-T>H@tKQdL}m8c7Gb|t}TD8(&6y4XGdu2&$|1crn^5H1U_83r*o2%TE2-YkJPC=Vg}ErjNoYf'
    b'$h1W~|4|aXS28ftwc!zjpKK!I2mUa78SFdX?w=<=SfuO8<-nR9D|qTx>XGE~pS6I)inZrIwi^43_h+yEpSzrop77@M;9tY~ufO(M'
    b'uIe@L*TK4cpaK4Ibll){_HTFf4sl~0Z?~sPcKM5sHpletPaMEu@Tfz7+5=bJ)bIPO#L4J>pFw}N$%^NFqGSH{?e;A1rpk=>+xfxo'
    b'YQ5c@MjXZ-xaN1mB*($w{heFt{nAu)8Hb5O#y?*EKRxdIHb43~w*QA?`v-L78Z@+o7QF8F;$Lih38FlN?Ydn0XOFdc<Uf0dz++y2'
    b'!D7L_%xr7XZC<a->cx>uPgZwt-$phP<yAk@^zOH881wW=kM%LxYlQG8c-;4^b$$EtZGX<-Nq$q`EqVN8{`$@OB+r-m`q5^3N7~SR'
    b'NQQlf5;nZ#<m<2Zvsh0a$&yZs{R_`0Cg;uK`)%iz7mrY%fB*NrFBf@Zak;KOtU=CkMECrmM0=uGlJIhV^WD??>z{99!ltTmyC->H'
    b'zWR_SpO<IPjy%Zr6g?!L)OT38O@8v5hg!$`Cw;d6aP#}e`hXTjKO53t-;lP6>22Ej*T*0jt6Tp%M%V8MJl0TibAoshYwSYlL$9pk'
    b'^S@owRlmWsYngels!;qD7Bw#yw?DF`e>zG1<GotHzphVD5;#p=UOzO%`3tn$-0eL*Ecks*^v|yIZ`*Zl&h-6D-~6JzKly=2p0V8j'
    b'>m&XPx_)w-e&8Rc5B4c3TUFJTTBLEJi^i)GbSF~kOp(D`C1R^m`lMnhohVjV7rYY5cFmfpgMF%qm`X4*`<i@kEv43VO6P1`j=?rt'
    b'Me{iXV_Pax%bHbEN~%<KhwqLa?E8AX`QH=ot(VqaoOY+ddoR4zS3!yH3CPO*Md#Xv3oFm<skl5plU|;yOX-y!T@-9M^WEv$l?>v-'
    b'S$B0Rl{&jPA6;~2u1+sh=Y=sBxI~?KC(eU%ql+$NcX=+tg+CXk^75h!`U1~%W=9uEJn7jPX4)tr17_g-RGnSwv(ZJ~tM1}T7<;9('
    b'H1^!t)63H<Iew<|i{P%#&xGl^%QHN-cCORvZ2U~h+Q9M2?&4Bj2&2R4MR(!U_#$b~%&Btv(yJ?TCLQi5rR*nj6qx_^r~e8w>)h3u'
    b'b4G;otMgN*jlDQK|Jz=pJtFcjCHl1U9c=Yn`P1{W&W20xgC9TRsl5^yg49B2VJ?inymXkq@iV$`<%PU7{#>7)U!0zvb?V$;GDjB~'
    b'WiBtF7UA5R(^I3Iy0~-~S7WU(ox8Yzswj0Xx-)INGk1D=ZpU}>+WT{Nq5YM27Xcp0Xe@;cql<*}muJeKX~?miJ(u0NvFgf?#fgja'
    b'?o0)73N3S|m&#mqP$MzciZd^4cWLeU8B|TFONBKtYCKQjQhDVrFOAig!9geFnXu;U>bRBs%})On3<ooC;mlbVls;3ZT6FmH-}V|!'
    b'SjnG$wfXTAJlaKfD$Zbv=la~hy*Xv&rGJ8m`^TMtC-YV02Twjf`~S}F=GWzlu<uv*UvCa{wEmK#-e`OIz2u|L=9uKGjg;EMo`Ll1'
    b'xLW@+5fm@@^8Ib?f3Qh)5fW@p_YZz>8`p38YrX_>SbcPQd;9yBn?Dk?eHw27V@b2Ft{30;pC8;|bMr5kbtCJ4yk=R~Kk|YDgZM8n'
    b'(?@;(UwNhvxX4eL@X<(3=q}EI(7e$?o}W3m7NfN5e)1e2ox1-=wE0+o^;cJ&zA%_#e|~;(bxve*4yQYIZ&IC_Ga&`Mawo7dLK<Ku'
    b'Ge!!=*(-M?_0>6+O~QwXQ*&{?hZK~(x;i)Korj>)?(zzM3sRhpE;?#pql->YaifcHs`RCG=0Y3q<i*wa!7t9wPyJ<gb*iqk2$$L_'
    b'{Kfh)fHSr`_2*~iJe*p0exaS#h<1Ab&Zw&^c<ys|dVY?Pp2>50d3m}Q2`@o9F0Z;%-6;Sohq={fojcQyz|g<d=|5_qf75F;X(b=('
    b'v)t9?sW#^FwCf=-X721%ouA8}?6Zy{oqfqify`gSXWh)#4_>Q3t@lv+z2~+jY~sKEWFLi=fAz_p-d_9<#bIxaxza@Q;rv2D!A?zg'
    b'dU>IKdK^ABd;izy^sz`QPtQP;I(0>^Y|gB_f}>J;%<i4PAQIH4;0o|!!Jf)14^A<5tKB)=>8XK}^G2PXUAZ8^P4@iU88D>`R~MJ3'
    b'm&Tl)UkWR+h+~>`)QU!Tx(b))7w1Y`X?1n3yR-At;N00h2|PDv+Mihu9w;R!-lYO}8Q)2sBk~A;5w0$;ygh}lH(KLQ;~1rb#-|FN'
    b'`$FimQ+MIvq|e6D4)!T7z@9)h!<qDF=O*aj!o~4O`!_rNM@{f=dW|+I-=D-LCbPi5Tin!%Jg)0hi2_{Q>fl?l+UIOE+r62t3oZjj'
    b'q>ydrbP&-wOGaM0lAM#qCR;{%+`UKs^L+20^VC5`i3L&tGp4=55Wq%Kj7<lra`qLAVq{7c3K&3SRB25*nV6BbN~vQ{%?g2K%<I01'
    b'=jx+1KKzym|8IAD0^e>+YrieKGP>LMN0RPV)uNgzQW{xOg;fEXVs@3R&Zgj92rcU_TAyQ0(S$5~=)k@_p5NxFq`L?q=IWZ#)fWWf'
    b'pi)gn=+0=9Fm#0ITC2<<R`0yZNjHN5S1D}NN}FRz_b1zTuijzBIOeZ!zWD63FZs#@c>1T`e#`ju?YGa^YI1S?u0DNsavPWZYY5ag'
    b'U*CLw`sF9M_D5O{etq*~;C2or_H{h##o~H3+kQ8m_%dJCzWu_tv21%I@f6Z#dERV}BY%DK?fGwifA;NfU;g3p+dpRr+iOQR>vwwY'
    b'*Lzz?@^nwYvp-|_`*H8)q1pHObdBat9am3x^K?QzJ&&vU?8Uwxzxk($$LE<{ZX4#fuH}9(8@<L|{sPbNrw=io!4BWIn~k$?AI?!7'
    b'God54?^9B-nvkN()px0jvU!^&`%7A3k_jPXSDc4QSeS;Wp=ec;t*#3AutVGLweF)IRkx$2?xc4O|L;QUxC!Phj54)m;g(X3B4*`s'
    b'4jvC7x{^aJT8q+@N$_8#PBzZ0@EkE1fq|IRvcvF9=WVqZwDv)2+f**uBp0f;t%abn^f4Ei6^2|NZJfC+B1>39_HW<yP@XDgK7MK6'
    b'baZz41J-+1RpONqSCqahA^rfhVi*2xso5{_|I7EYB|GlFt?YnUSG8{(4E?Li{-6NwSL!M+=czw%IA6|2`a8RQ^L~XtUe9iq6%PUt'
    b'i{<le%S2Y>vAhof?IUTs+3#PT+`m&AKmK99esC9?zu$kI0Lj<=A<5kZyHB=mX>0uN;_}`(ZEMN?5SRV0dIP%uX!|pk+KoKg_se)Y'
    b'kkbG4{wX&9xt^z!JHC|Q{;JLA-}1wUYj0LO&N8@Y^TGWEi-DNMgN)Vt!RPqP{TJ){_O`Dwz5jOi$<8x_7u=8I(|CKkX^s5DdlH8G'
    b'DHwk7eD>+0+-(@e!v+0E&u6dZd}F}x;@jH4pz8kn`%kD{8(({=&b~eW?9)$Q(nEj!3#giss#DImuIpO!Fz>8<=Nxq3tC$0<t@-lx'
    b'FNQbx@{7yM{^uUyv&mS5K=6fWA&mOyVO-JW7GnoUieD=^{`sp<PGOflvHHcy>-qZ4UHXV`*J^C$_YrFp-_>8v7ps%^Z?C_G>3sc*'
    b'E=L=1`|NFWrI{9GMDS05j>-eEKps3pk;&r9l;A#yX<+PNb-G3MH7xP#KBk-wi$J#B^*`I3tl7ktt-#<U0a<_xGP>h-dl1$*sY)u!'
    b'S*s)PLIZenss`h%#0-cocrBBQwT=X`@7(zUOElk$V;fmAhNPnxG3r#bjU1F|Isr9j%wYhW$+d;(Wx^1FgcNXEvDvE-Fd5-M79|V?'
    b';K?)a3RtaGLYI_7F_=zYQnQc@59(YK8DPqp)|F1sS$YzIq@9dnC;)4Ni922Or9AK=pI^uKt5>x@pgojn8^c9%-X~(V1Uh1B?vkzm'
    b'Qx5)C_$G_UY*5@>08_#R&<axvCNb$lnHPO2*#6kSXLJ@ubv5R$DbGx$%oY;{)wYNU2v)ut5e3E;Q}meL3h5Ga8nQM6Ik&f5q{V99'
    b'w=P>O)<ZdnGPP-An+Ix-!UmCYD=ik^s=)&QILp$Y3|S;AfTw+Q4UrT7ZlzQ?lJlx=Lg3*32Ds7_smk2E5C}Tab}Duis9WPEMS$O!'
    b'A_|tqYLjtwNUnz1;Tzq==>B}iO8H{<p5O{>)<c8+xq~uc?lWvlSCP9eCh2Hi&^3i2#Fh$F+2H>?Tmaxf4S2Tf0Gu1<qddr@vpIcv'
    b'QF*R!Uy2A&tiYkDSX#jY`%<-1LaJIt1E3ZKvuUDr5yUAHYZn8qq;yNp$gz}3Jh&0`AMLn37WCP!mS}Zou${&7*4p{xwF@pKz$DPT'
    b'6q~Hz2r=UBDR!<@A*&7sj;Je8Q`lbsY#9hz+}$p2&Vd2;XU!L27oZ%cU@1v9+${z&N@Ky)APyriI>8+}4X3C&9aFHrfCx2GnFkpc'
    b'^HpEY|9<;co1qjuvGZ{BcuEUr=Ae1dG~3zQ85d<pB5Jq?7*J6X!&bHel-Z);=YmWFH+T8N?KLn_@8;^1vH@&qfiYy<(1TjVl0pX;'
    b'owU%HFkhpr9b7BCyQ7U^T7ypT!z$Vg0{S58YFX<>+`U%s=|Kl)C!s>Yx*%cgP1s^>2Rp>)@Tf5cxW8(oQa-@(LLX$SRcC0wbq|t$'
    b'bG=CM`c;j~{APbVrs3wvX$eXXObL>R>5HKY7Op56teMQ*H!vmPu0X9dld^(U!hdAv2U3=c@7Hh60nF-hUrH+oq&54*CrrX??_htv'
    b'isaxob%joVpzBWiXjCg+8w|+Dn1scwsjx3)kT*E=q@~aow+=rJ5{MaEhUku%ftw-35-BI3|IR}tgn(~A&{IK6i-1)J8uw|%e8rpf'
    b'DWPu$F}!@oa}BvNvoe}PQ%u&?Wdwl^(Jgk`I&TZ&f~fEm9d|@Ic*Ks5?A~d(TzFL_F{!y8iafhp^<eq3KQcEmT3C3{00k1pTM(_K'
    b'$S_<9uM`oqZF9+B@oEH)fh{AX6bUU&7WNj~(82D@`T`(+Go2$fRLx<otjH1(AbU(`fP*d2LPHpnsr?aAN_498aKrE<9lWq@0AC$E'
    b'%5i~*8V?1BD=Q85+~t7#tHwBsTLxiZz8F?eR>lO)X%SFQgSs`uoLXTJ?oibE7oT46a3s5md_K?L)zMrw0i(6BmsW#vh)F<45yVNA'
    b'4h~gVC-4M-EHz;<;j*+Yx)sbQ{JaL!nvjP8|1Woob$qp{a~(>HWT09=FTJ$|jsw^Xt{0vo0PUGh1P$XB2rgYnh=~>|?sW~qbzqBa'
    b'YIK{|C><(^%^<d+Go2!SC|!cuORHgh@PG!f#ma1Qrz|9QppMchfIy+JpvG#Kj*2>1vJP4YpKaiOTTQ?%SsDZ?=y<g7`$|F$0KqW9'
    b'6`&{+g2L5+u;Lk7wrxVvmTXfZSmeY+N({#sJTD9k>&EaH8l$eTiFvhz2vSUkPz?1^m}{bf(qWZLj?mWQGB4SohIYU>Gl2#*oJfZ_'
    b'31Wb$s|LC#36H8J5QU929iWH-UK6?k=mh*>B9ta~UcoXBCG(X<%P-^W!!-m=kisD1BN7TYU#ye?O6~$&M^wNv@K<okj$l2sf(tRt'
    b'(zKL|V1DyZ*5%FXZ7syXGCGD8xQA3_4ZgF0>eeOz9P3C58cbi|z7?TNRR<dkFcbl`1!zPZ_lLr+YV6<6vxB{d)>o3W5~hHs1}4my'
    b'K#+H>WEW%sX7ZqMAs2)ICzAwY5U!|ZyN&@-h?<VeJZD>^KJB!)9uWv)o9ZMUIkgN^u-O4)`7S31L=3&eqj&)T38x0|gE%f=tr$0q'
    b'0$lA-;wR9WgNSN%Gl(V)(Gx}vD-2583^)>G2QZa9Y`@D04IoSwjy%ElP@fRCau+88(94?@4~U$u*UNdj>zjccT7^MCfEQ+zF2P1!'
    b'R1gS25v+-NqNIi&(FusFQ}A8zHCSzgLRe%@zB?{<d(?D7WT#z*3nsJk*<hWpGAejO{@oejfrtP};8mo6y^9KV2u)H2bgcslut!D0'
    b'1bZ!A(I}>9S*?m`a>$47SS6V%M^uVbp41AA(0j%u8<GSYtnk{<Z;}&)d&K_7Bro2=M9QY|^I|U+cCt#<6>H$=G*CtreJn}^U{!R6'
    b'=FtQlL?yQ9iUff}um&9IK!hg-{ApZ%SNT$qLl`3?@5fyggry)AIBX!l4$wvXy8%C?4hmGe3Ppzh?tm_w4-WpQc88*V_xbsT7_!~t'
    b'_9d7j9{@xoh0x$FiVhkSG=eI5stBgIdDte@rh%-(^Th(+<RwBqm;u~GvPUG|z?ZIuZ!0>)hC(5{Iq1KFpR*vraO4~eB9zR*i3DBA'
    b'ULY2Gt7Uc}0^th9Oh)I;q}**vWM3A1S!z+}0#IqX%77ra!Bs$T;ATQnDh3(ISWGA+_1-1mNyIH68|f!y{RTjO-6y#E76c<bg_qQ!'
    b'2zUYwc!UukW~FRZ1BpOnhcbmy;rW2uB;dTqV6$+rBt+^FX&lJow)}N1uPZ1Kv(Rzm<YI^ak!Xhq+)KCy&jX@U$%t!Km}C%NZ5muG'
    b'0DK0p$+f_ma&IK=M?@}TJ4nnlPys-_#Pl>-gUYURfJyZ2aBdMHq~-+5sy(I=EWMDmWC?|iE{QfNau<d_A2ebgF-rvng}wraf*LEB'
    b'VI-uo08Xt_(P)rwCp63vxGJTt3ousjOz4;dT-1|7zg)%}rkZcpuQHp6j|6s^7%@cv4%ZQY09Ygqh^s7!oopEt6zCs;3+q@A6>UtU'
    b'g<S_^WW}VwgGd~ipYc`etiZ8ie^^HHSPf`Wj#wn687qOimDa*IAiUCCbOta#=Q3dppWXC42@3kj;%+%XDSR+YEqEg|0u*jm9FTEs'
    b'm`<M&JHRnTqOZv{F?D0D0Zs>=1MFyk0FQ}0FhGtWMof-Jtn;bp)Qrka3QVL>!sp^ZJwc7Sgk=QD#MiM_0iz%do{)8);5Zx^mc;@x'
    b'm{y?a&<WSFFnHp~y^{!EfRGF9>%mS<i9!aOVJ4s!5{sBpeN5WH%2~yPWEMaW$^vi}pEGnH5y}TZE68mKmOe!YKn&EnLM=4)MLFrU'
    b'J|=9je0l%EHwH#1=l-l_@H=B^N(g<7c}aUFF2VgOh-k(t72lN#A_`6or)mN9z&HSAc}!tqRzKeyAzSTBs=5P@)H;R^FcfGTzO4ax'
    b'+H9l)=k6Ln2>x7xbQ&bC1B;<M3Lx<|)d?fm^lj<=$`}2%(g?A6COoot607JD5}gM<(Hd;MGvH#HX>yV=8$3Xl)g+K0QwWeC`Nkd-'
    b'_xYQ}dhwfheO<?hrU2_g<8kYZQ3VTsTo4OzV~s#pB8Ci<nn2<+)X5qL-=1m$*RlWrb%I*FT5n%>_^wXn$3jrGw#HfjER0hCZs1RF'
    b'AYMruv81p|m^^$L08Q<Hqu|mk6sH3%&N3Vo_=;~g&$WL;L4VkCq%R1w1%MmFjR6ZJ0VAx1YqW^{z)zW$4d@*Zj2fsu{3-qe7V4l*'
    b'5Pw|iUE1!8zU()J4u<QQy0+W{MLaYJzZicrjieih*$Dx#MA(cKS756k=)n9&gA_N$jYGk^PS&T8x>~<tJKYgt<9@J(R0+#t&=1CN'
    b's~EsV0--`@A%+>+1P+Jc;UO4`!CwtbBZ}h!U){Za&6Agl8~U9C!KPtuMN|dhUqKxc=v)OG23W#hgJ{OU?*iv2s1NsmVY5Mr4D3#2'
    b'(jOvttIP4GjslfyE#uJ{7y$N*!_*c`tYDrxfCAXc?U!JoP5_p<K)b6ia2B>hn9>8CB7l1n*B5ae5AvWe6z2?6Sy~|UWu;~5tpd{w'
    b'vID*WFA$y8g(*G6F-$R-Ec{doKKPN4f4KuY+#F<G+?>TRO)P-<%uSY1GQv&(9MxWW%#+98WkZ}O^rQhS0M4F?l>|NqtqBsuZXl@N'
    b'k-OxU^KawLRCH<x1u3{r0i*!i12sTdlNX3S+Q$Yu4wD29v~&#IRRb)R2-dD9m*SARZC>JX76F+K0tGm)>;N-UP&qMVIB-#n44w-L'
    b'NUIDyVv8pTK!U7d5DFw9%UFoO2XN`L*5*8le#v9Rt24ey>M-}pnxB@U>a#R3w2nEUPO(BDGam%|OVXFlcOJ1_7K0$K1p*0}u?|C)'
    b'_SyIBcE~g8gB_+(W=5I}uve5v3^ia{67d|y2d@d7*%5qeo-k(21Aqe9l?d|@v{gFRs!oa8BKc1itC4*LtcXh{2tWo`vjd?Itas8b'
    b'^cxs(UacRD@^Ee)_<afRuFMq1PSiXWwd~{15mE57si+EKtxAvZ@IPrHH;rRQ6JSM`N2GT_K~lw{k;_POVu0NEAd0(;XMmXb&6W#o'
    b'CBC}5rMDc}m#COWID){`5nQB!qe2X9nq*M;*ujjUJS78hL@=Y~iWPy|O~6rEKO%HrK@@1QLEHvJS6*_Thp%1*hK1FFCg30NXbb36'
    b'MRQF;XW&u;=#v3uNP17y<qtqD^Sa&H+S>~Pf`sP-N$y+$lWU2ab=>BTOz>J50RG6s-~p7PBEIRQi$}Pq08?W*?ApG~NgNEQ1N2V;'
    b'o~Z(a$)0?%a;DM=io~KB>j2RjfG&J~ab3(tRp}!nXFqU&+uX<LJ9xm2j!YyY0?39|)^q<4fEgN~n0)~{3OO}pttwS1g?OFd_d5Uu'
    b'*JW;3+bFEm=|CI<%0WJW?1tGQ4ey4S;=u9{rQuvFxJ?0KF4i?}NHtR>7`sfdgOh|ucK~DMKuB*~2lx(-8zEAK3~bW@XW49{2UgdW'
    b'MV~~_PDs^~hDIdcA)pFOm~aN;Zo-R^7`njI>vXs2jB(n(DWV4>BcGd?t^x$%(;6&WP7H}Y@x*jSc*LW~3KZBEWPnq_GHRkJmedf&'
    b'rzQ3P?+d<YJ6>;EfQ&csRORk70+ptQ#ga{R26F}iiP2agl&e|<2UZ}uRuS3|h60|E$k!amJV#u94bz&~V~7=K!oVYWO=rL~l<Zp0'
    b'8B1miov^_i2MiZ++Z9@&=%gcnMU=~jqTa;YbzPp`mHA>brTc3LXU8gB_(80oXack@;Lgn2(CISG!?>k^_^`kVTv#*-WmPcmD2GvO'
    b'Lgc~vDWAbBROs{KSQOJDJQMfGX<>Z@Dwfm2EKCE11k-E$q&Rp|iSYBNv}5ESN|0Dgl9R4jlaiQ0Nv?F{7#Yw?04Q*~FF1q<*__WH'
    b'n^w8vFt6Dh6S~!yV`5Fk+DR34W7^Acx2+G*$$7T2@FsbqVS<^%tf5-?a25g-h>f{SjCH<#zd0BIZm<=;O<Z4(^~fvNfr1x-yLTXv'
    b'tQyL&)hGhoKirs>-ht9GMG*ilEq51{#nN|(^~xTK-j-h<vI9o{1R4v?X)th2jG~CvLBSD>5YswM0+F*fA@{Hy_)Bravx9>V2cmk%'
    b'$q|0`j;v&?tq5eGJn&NiKrVDxBx$g2LOUnGQk?=7Yoc_C<s)FxEMP9+1ubyTVpx$fl-5t`HX(NahyZ^CE24x0rwUAXlB)J4l2JoX'
    b'5LyvuYsugzEoQJjkNDrL0{8Ky9Z00V<~HM@^<#0G3MB$EIzUr$Wk8)us0}CvRwY7pfXuNb_`uc_EI(AZ3joa$oR}8XR}k@)ALDWk'
    b'Z2^2hNMmh?c;3Lvd4MgjIb%!&a)o*(03hI(>I2J)SRISVuezpMn3Q!Kpwt|=(*{zmfsHeGQ>YofGJr<{3>g*-Rc1Dtq?T0Z4)Z+l'
    b'v>jruO_SnYu2y&T;gHbCXBSC$Qe1Y3Zdm(HbhT&`0w^Ll4Dq0bQxNn)64c!mrse=LxVIn5q&zC+McrilAn(ArAwCpfZ-5aXD?qUh'
    b'jx-SEB^I!F=u5$^5iL_@HW~{EErJJ%DMNjYo)r3d?a9Y6CnLH4<>5th7cF-IfnYMM&ijHD%S=^w_!@M|H$ZjR1N0Nq4%miYm^v-9'
    b'FP~yH)xQ0eBDx;x!N15_I(Qjy8w95)d^K2L2EI;Y?Fu}uYY8(A9Tspu9UT9(iheQAZ+a6v&{D8(X5WD4q6(Ik&xk<W0t6Q7fc(Ib'
    b'8<p1xAgTbw0l)^=1~2X^h|9D%fHEp61oEvSLukh2MF!^qVu6(jCU+u?URQ2}dpLl|-3F?aYzWh)h{`>jPRj;DtEQ!~Z)jZ}TR+g!'
    b'C;=l96GG0o3Qbiq0k#xaL=afj1~8+21sm}am@T*Jx&q)1k2K+_r{G{NvVx_CzP<^H-)V3J1rLw`HCSZ{s^Fr^0Zd30$ATIYK)`DZ'
    b'_^#ziA&dK<`|cpaujwM-ogHXav=I@(%ZxR|1kzt(z6!TYnrB8A7MWS}(gC$`PjX^Ry$K-Hm7YW%dQOSR*=fKQ4^*zmAT>gRDlLPo'
    b'0MPd3ab85vbShAj#Y7@DdyG{%>-~Ymmz&qe>^4#BM7lWO4glp9cSaxsG~x+v(0X{uDB-+15G<HpVO;^BI3gF~ac6C2NtCwon9Tka'
    b'bQ9U>3IZf8pkc@kN(yiR1B83w1}z={<FX;b_W<X@XE)L1#DhHwkH><8199|byW*NY*MH#8DndG3NMbdVjmbi9u&Rxfx|W9{VA|Br'
    b'(m;{m+QG>>;JXg&6aH2?H!1SsZj%x}kVa>zG@LcCFC3);3<J^y5DW@Y58M)N)f5DI+2LzXAX@mZlzEmTmq}^AiEryI_}>;S9SVi>'
    b'MEt2Dh>)_SwPk@o;3~IC0A3Qpq9Jc*w%WmABPv-Zz<jEZQBDdS5SV>SjQnW<l6M5pw(Bb?!TUN7Fb0K$BEdHUE7=4mU9yLZ!>Vc~'
    b'IV<q~ae1RMUTExSlvzM0V9X7Rqgj}TI0c_6G2ar9lctcl(MRtFe`djkiLZbFcyhQsB9(0mM{EKB8a^|%?BSXf;yhpxmNX{7FIy9a'
    b'Z6xb&6%8>JR#PC>n*=@cp*t?=m;+V7NC*d6cxM2XT2gEm2eXIwa!Ik?1n@Hf`@(G+5d6%_!Vo+dH+Z3$lsF`W2Rc&_5dhFZYE@?H'
    b'Ac8L-{1k58fGTm*JuwXd$c8YiGnJ`v9|Ddy2|2B(pI^s30SO~!2#zsl<GaXh8TiZKp?&zTQ_u}&a5@Wr1OJd%wq-$5JyeFpFC|aP'
    b'>h)uL&f?I~07ht5c3P+?^ioNP0Cob*ges7?;dvMXK>-1pFqh6J<~S`LtY9W4Mefqk=gT^6{cxli_^8i1W>$!>`yc!oAPr(gU!mEb'
    b'Kh)L3u|{sHsJ?jIz*50;9+mp4@8&rrme8pQOeXxYmk9%xnc073g;b8ExELH9U2PI^Dy3qWipf}BR@di4v0J$I$dYnb81S=;VBWAx'
    b'Zlr+J>jDVDQps3YbVJl=U?_;42+SBPFdGyoy9o+B5cw!6Oae>@il4Du7&VhgAS+dY_JW6DxCOLKY35ly;D~D`dN2}1YYkvv4}&D7'
    b't?M7^a<!>`8Lg-58h24jVsX2KM}P(ck^v1iR)IQG3(KpU1%QJ0Mv(OIbKuGr@G%`u>^(?)d9yw2b(pEqrU0cuVE}9z$b3>*KTvHT'
    b'9gNn1Z$O=^0fBMQWM&`W^M!zOwcN8lWEs7{N0KM3%>v)8q6^WnLKA^R=c2pJ&G6iyK}rMR!C;vdidgX~jNx$<=#dfA0w0MVEZEtQ'
    b'PTOknh)t2%e@tVGV1_{fbzy)AQ>I$zYZ8PBEGmaf_vtZ#M@uIx^aInzjm26s0z3XvGMso<fbZe&EjWlLHkS#`!Wy>i1eeprHj~V>'
    b'$en2(lM0{Kb-){)2Xw`_fYq`E1OgjOp4DkE6u2W`VVwmlD}}WJh#&q{!FapJrS4B_0-S<N0TKXjaey5{mCB+~0FTyFHL2kj@C;IB'
    b'I7URz#$#RxB>?ObENUz5hxMVO!+I!iAqRNI`UZuW%nA@E8>VRyEbuwZ5l{}?9%#<w#@+Y^UL5f_$3;D27{PaNrJh8pR(e%L-v;Ur'
    b'ECTe1iOX=Na56kx3R~5>gFo;tRB&c%WSkcIhq#>c6$ghtuBw2zk7&>084yIcS=RK24sb)6PJn!RNo)fy41$i(hDXtwj+PZjhcV<~'
    b't9Vydf3Q(zXjt6)0GlZV4o-_~pcDy^0Mr*Cqcs+cyWl|&v_QZFBb6or048q^-P@NnzTLfrAnvwq$FY(nk)#?8p0vP`fCm!Gz^A|='
    b'gb0VNz!DRbR4I5}$HIT5nAWf!Vdu~`zI?N|d;Mm8QCt54%gH*G3MNw-iGd@bGCT%caWm%GLtknOXXl+0U|g2vsbKvAfJmx<=;kJz'
    b'PTx|ve{s(KW>#UA8IA++H|5r<(Mnp-P9X76VHOpbE5%YUOgM!K?rpV$n#CHk3pqa`>gDFR>3C=kLsL2!ZcQN^b1#HP+yE~EH-a^Q'
    b'5GYB<!`V<Eo~;Yu9tvZYHHQ=*k$0%1)Vip>g1NblM@tagp*J#tz(I#9*Z@H>Q(j<nP-8eGgP70ZM+C^ngdOv0EYZXou)Ga1N*8Gm'
    b'6ai0p!m_Wq0cg!qK~;f8z(z8VP&EJ@JijpFsr?IUAFC|pCT)X8dQ6w`5{@h~j(6Mu1UJq)2k!49d_-p6K?PK1Zh`HagAQ^}*6Ix~'
    b'#_7vVzI4BS0n`^!4q>1GoQcR%1(p+ma4T+xOLp4Ou_D-4-W#D9z6NaF6agOP?6j=S*@(j}G|&}TxCUa0wBiQ#SplvQ24dmXzvI?E'
    b'iwC*?)YnrXas>n<1FeL_DQVl2*Pq0jvS{sa7araV=)J<+xs9fQ9#~BqnN!4+*`^FM(!inMy4clRV09XNQ6N;hGzdq#4&3<jXiO?I'
    b'i_T)!!t+!bKt}WIV}!RhU=S?&khrsLJmpey2d`E_RCtySG5%1%MZEzXd=H#ILZ67(B-jYnPIBklJKLq$pzWHQfp8Iqols!;tUiei'
    b'P>|LA&hd26kY(@W^x)yLe}T(6d&mzx6(}s`2Z*6X()40ugEE42!*d}_Cjg_0>9Spb?g)qgAT-7Zn}aKEV%A`3ua`VX`mUZ`-z`s<'
    b'Yo4JVnHZt1alp$0P7xdrv`=|0g(wK@uEHCOPT~<tiU`3x7-u@r2qmiKR_24u`$kuoLXPZ6l`x23shS5YC68P*kxXVlb($rZ0Q10@'
    b'!FyP{gWKqYV@g|ji!khf6WvhYrv1UD^kf6d4z~zd|K&u@JT(9hX@EMR0~zCX62J>i3J}a;)Ecfc2Sgo!UYLtB{rQ1`xJ7(>qzVKi'
    b'jGO6oYcg0IOi)EMWw-VOf@oPBUzw89JVpXk3k(B#28C~8coLjK9ya;=B*hKOPewWkbO-mrZ7TSz!hQ7ykYxaG3xE-PRV8v~rCU%4'
    b'MZN@(rXaCwaK<eillIA7I@}mH34~FB>}2Uf1(I~K)m8vjff0BJ01jD+(jO2oh|^L)h|xT%)D0`>C~8n5F|PcNU9mhND+G8QkCvJc'
    b'uoRM&2@1ByG-n8vmF$sOT_1S5qJ!qL%1n)=yj<6})91it2cyxzH$W7nIYg?|fCezO!oK^~wTwy1xG}I%4W+V}tstsGDJlZcgPhHA'
    b'&tB1Q-o@4UAiaXpGS>)54&v`Z<3>0LztcRKl|b7QPr2jfcm!|)*jlW{!MSvB{1Za9=VlMt4bVmmm@&<Lj7+u`i*hVcMW7B2(-jOi'
    b'q?vql2yC6|=vx|A3Ut{|h}yh)^dMjrc8L!m!PB*jK*egw1S|l3#@eS$xY0bO5|Pru{WSzHfZ<L+!FgtKLeg*JdkETP8pauw!albJ'
    b'kqBI~8A+5@a$=<`V7Te9^sN8s5Ir3t3^a~KU)-CHF!X^syn3^^J$_!H+5qK>z?dvm^n|!YagSTWN2OdNPcj<|+E!fQemKl5i^NSb'
    b'@YNyb-pbh(*?m#(R`rlocn^99M1lE|O0(RR?#Kc~v9=is$8*8(y;jMjvvxKCihx?cxj4YAav<+jzqMA&Z|>%Y#jg^?67&lQtd-gy'
    b'BA|5NVQN_@q*x}$R#}LlffyUQ7+9gB*d<H)bSQ1pkYFG4X3um1U{@}Q6+cisEE?o_%pyAlfTDGl1toB?)&~h?L9DFVRh<A=59A#9'
    b'AjCT%y<yQH46CupSk>TnJg65sCyj&-=m?)1S!WT!p)7kmfL>>y>w$p&)iV8TJ*2u0)K63v`#bLO14(E2Yt=mBAdryuS^>c;>mX9K'
    b'U_3}}Y{L1<9wJ?9d3da3An(BE0l$J)CI<Q@xUo|-Xe5wX$1?faW!t|n#5X{j0!p8O<9#l=0^@2sJfQdL-|phF{wv~o-^S&jmb7Eu'
    b'x??(**&+mc!yQ{4*+D5H2*H>v04c11CEjo#pj;hvBVfMuaOe8I8n{oj00bW2zlN)$!|3|VYQ}US7*(>O)=K9(I&cHRgNb!1BLoA|'
    b'H)bg@w}79+&IAWSKSjttD69f!#;E9b;rtl9lLyXCK+;)&6>!rIsEoDXx<wY3M(2~|N!mVF_=vazvjRlY67)_Apt2wWR!AD(v0Vww'
    b'h}nD}bQS^hfk!&Q_yW6P2y#B4#DOScmG!@}PJVqXUcsC3NHll)K?va8E%%c;L|zZ}*mZEmw(-~~)FLstrJ*UpS~i~<HYpg&`gBqD'
    b'N}5?yrv<4+soq%Cw_r&wMqN74R0(>Jc@{p2g7xu{|JLvm&B7RmY-A{g>3{=MR+#?`Hv@kS{VRpX7#rLW-+<%$Gpkkt{;~T*D~6{N'
    b'SoZ|j7Gc}%h@^uoqw^wX4de`*(m8}!sA04b$U5klVpR>CN<iOvHYXHrCg)sv6oSQ)!)YT!J%ahbI9kWtFDq8*rP&1m^vx&V*fR&V'
    b'1(pSDR6!lQ0l9+F87v>q`KjS1QE$5NeSNZjvE1gTj~iDfJSYgTf^FPfU>gxFf&@;(qJbb|i9k|;1$d4U(O)O8fPXzuA+Fe=%}uIi'
    b')HU+thn)LQ@7vh`Ux?%d_&{OVG!LC3E&{Dp+&*NV;ax(8M*?kd9*(ILmw^0A@VgWITRCTORrl`C#yijirePv*82~@{1sj(DJ;6GY'
    b'Fz|}mxy)W56*vi4lqZatx-oVa=ePIgAZqD1gZIb5esvLwCxI7&V!y`9y>qaAcy0jJ3^^<ha-eR42Sb(GYzXuCFs5!NXIT#$HJuM$'
    b'l{^fJ{JALsPzkzCHUJo5>GN~o))cW5&qyg4TH&6%@fnzzHJ4uD(H;}IJ$y1|!=76~z+w(7<>A-0kIGZA5te`f`&K=8B7`+y3AWF$'
    b'ibp=#$Im>>WG`;mNonL{x#wz4@kaP!O9zMDU@<Zwz?cjus;J$TXCf*a=}G86Ys?Hh72<H35b{O+x4Zdr^9s~SC<u;QB%5~nz?wtg'
    b'HN|cSEKUQtX4RKskPO_X!7ApEgk?pP2KHrn!BFP5<xy|byS_(#R;W)qonM0kjm#{y3KIvi0q1EvQ2?^dhmnY+-1n-s-&wB$QNO??'
    b'du}OumW8++VQT}~!`4Up{Y`{xU<4XUZ7nxt4Uc2-9B1zM#;?ExGkh&DK!5HX${Be;P=j*$*zHR6?#1l7Eo`~gX0-bo-0-XtPF5Gl'
    b'V(%fS0yG|!idc)8bO~DkCh>+9UY%x{jb@cH*g5m@domyTE#0@S9O3!G6jn7ng)4yMU{|4V`v71BkN{Yei5f*63GAog5|EFib+&>S'
    b'G?aGGL1<DSjK~#9V+R7(wL>HUJ`4RpXN5p*z#>HhO*Od`ur=^8V5GwR4DQ-=j|pUhq;X0c7@JsK@MI|u2v*Y>p7;U2L15+f8Oak1'
    b'ph{)CCna4I1Ou3mG}O>xC!t+#<BPhwyWX45)ReERDb5+1Prt@fw`|e@GXaTph&(V1=to~T3*=D|sY2*026pw;y+qKk{*3%`oBSGy'
    b'>073Ne^<d`ZK!&V2%n(#0K%b0Xe=BvaFzfyrW1gUDpm{u@WlIrG#fE{y=jg(O#}i5Owb_`!zsoXDkv>50iYZ}9H0sAt)YMsR1=!Z'
    b')<U2vOc}5hT?mgz{Pb>W%Pef0`FLjqw_g!!x_~%<ATCIhJ@+KweOP<Ju6`A8N2-W<c8K{C;)We@#&c;gEsixRnulR|Qe7724t>*3'
    b'v5i{b4i^)kZ27@mIiBzg(J&fxQ=*tZypHp?|2kj4Da-i%_@H_!+zZDOE0$3qX!Gp7_1*#*!<L~k-UN75-$&I}Knl69#a$)~MCp%6'
    b'>{HC+#6S}Q_65=i_Q2B<AY$yr1LO_x%f?R%^g8kUXiRL_0+>)kPIPPc<;-I_n{GHTxwrAA?2#tHEmMzB36|1Imh4Li#e^lWks8Y>'
    b'8Hzy1lxM!8L)?=*ATC*DX^u;q2&yhrOp2~Rk5CK2ZbAwg3hvben=uxXEIo)(I^#)<3Wg5O3FhbSk^WfNxc$!2Z4V%Uh=F+a5#T-n'
    b'^RK|F2(SpNKqZ^1=A44(PBZs@dFlnBNx7^-_lV?C6P^)GOc-I5PP4JMl}#iCil{4V8(U<@bmoK=^Lso54IT&9VYKMs9#ncl=C1ut'
    b'zXvi-yyV6rNBH&x$jY4-ChFmR5pF?K0ib!7$77<662d@b8oLd<1YeqWr&30;_B-NCwCg0zz_Y{5GtJw0fC&ZFX)Urd3;-gc9XORI'
    b'H!f^X3JO(=;FcNqc%6`X*gIxi-^@NuEEZ$pvO0x05CDc05Buf<Ux}s79h8QpElrc=DNq9zWFj`H;{wMmTt=!>GO%|iSTL$3U2>=4'
    b'Yg)BN)#wv~p)(?ZgL@Fg%u@)i!1w6JotI!Al{skMGLi{c9+?IP!%loTsp2twR}k90Qx5(UW&v2wJRw`ag7QPN!1oxVW1EtB-?^nH'
    b'tK&`pt%4Bh>KX!20rc`P0&sBaz{rJV7oyBg8O-u0a!f1%Xe{w+2|`ZI>ZX;-A&y{sO~e8Af3PAs5j()7&{(X-dR2$$YY}lXTNHvx'
    b'vS_Ykr8EG)XV2H8qV~JCjGH)AtwNB%?7$ONYX?xmj`ASlPz=plE7x~CsRf80@E%hR1<O3;4gh*g=zYjt?d>2dg}b#1Kd0DEzzP9E'
    b'DFN(Zi%nQ-5^O(r1U7gy7@`NMVOG8=b7VF@`SQ!p$9*>pp5HPv*tG<#+}J;buV<3%nVTKRG|*@<ShbL0B0>PM$xMF_gmXm7xNph`'
    b'-@;`Aw>G{g5{wwnE;T}h11e*Ms%m5{jV06?+zWod@jMeAhdaqurVo*K48%D01;jo0It!v~!6NNe0rG`O8Xs3gL<O&>*@B>gEx=rb'
    b'i88yEcFmKHivB~qo*!Bu8>3-~0C3rm5qhCx*A-wTZcQtXposq!SPl#)8t(wJJkS0Mww{byP6&PIGBRlz%tkgNLWM;|3s23>UKond'
    b'AkaM2$i4H_cUx#uC+kaKpCi7K%dp|{l*Ie)AJZ(N@+BF-PVA@v{%pO_ij}fJe;^KQ`;L)zeIo!H38*A@xM35P?*LVgN}OnWDmxy)'
    b'45?OPi`Z}F=#B@$xa|oi9oV+G&@SO`!0%Otdxib8;JG^UsJscdA-KoeA!fh|9VmQIfG<gLmol@!(81pn#6n5PZ<+x;H9VmZcsRzo'
    b'bX4B3#mUiQ6%yP83&W!A0{?~adM}dUAufOocxtBwupXR6$L^PK;ZWgHxuKY{oQnQm0K>oC9{k~+(g-yQIOmX}CFRsuva;ErEG0zG'
    b'%rRU=2cW?=2k>w_Xs4`p3|Li61DtJ-j7ilo9ovO9I4m}Q2InOM^XxNXGk{u#rh<FRBr;Fddlwt@m&eTE4}G@sxVX>b-Kw6yS?ohc'
    b'cx`}f*#QYd71#mRsN9hnD#U-5h<1^ikQGdjVK=h2+vcFW^Dvd;0=J6uuk)L-S3t_6reH25aZ4Qm7!jlOP1<Rqpb-f{g;`I8Oj`w}'
    b'Ut`@QxVUl9pY({x`&zQ|`&UzK_iY1|9k!Jb4Fwa%oJ-5C81@~veV<Qm%BaNRH5Oo7E+{)OXm%i-kU8!+vY#ty2(HOlga@K}_^trM'
    b'kbDb-1ftN~f{bvh(ZS(&78YVzl3YvyqK3J2j|d!h92p;Y&ml2IjS<-DJey#H#IY-_N-SXM3Y&2U#1|0Z<`5PU{5#!AR$nUnK|&9Y'
    b'j;X*_!O9or<GpO8QXLN=B*g*@A=z}k^8BP$nnnAG<-+|-<de;5NIwRhMn?OQ2EZn>^*B?N&{6?1&sK0Sybe0rRZb#YQ0hB=vs7PK'
    b'5F(};JH6YF+?Q}HF4~M6#AF@ooixw!vzL))^|4Bd2RQ(}bzsszk!yh5h>j;4OW(wJENs-%WZd@>w{fs)!`7F8-WncKc*`PnI2{ND'
    b'K<gOeJ%B!(D(f#IVl`(t$)T80|Bp$(!s8|YG9BB97h4hwVt62wZK@L#fK}7XR)deSp#|oZdh1<+u{IF=fv|%<630AsLzv-dXqNfs'
    b'mI0{XNMQJ~z_>lo3|}wBT&aRh!qu?ngA=Sq23j`WJSOwi`<wL}!0x==dl*-pc<5UxoA-1DXaN}-kJf_&BMt)n@|<R@o}FWif;$uJ'
    b'NP=~(!bY_}*kO^&q{0B;JJoayO-Z<FkTP&?1LFn&XKO)F3t(>$Q!rH-h)5etl?);$CfN9+@}{W1?Xpa8$PH0fvBnV!*$R8dU^Nx@'
    b'>0^;Bz-NasL?a$;gkc~cYQ(Bx_!~8~*!N$g(GiTx0^VZE*g61omL4DE8`#tc<174G0gMv32rvT<+{(-r1677&a{lMyZh13K0KxG#'
    b'76etmz>Y;U?EV_rlp}#TVY!q8x(328S#-9M+9ON}2WH4N#r~M6-``#@#u-rOnEXH>w;~6=HNp$FL=fOzKuF%O0c4Ee?->}CC(B7V'
    b'*dC3&CPJDR)TFT$1-<UGNSbXzL0`Mn(^|g%!UuL-<}1G{yJLr<3s2v4RWugfo1ny@7&`hR`C|(vWjbqtLJItXaFQ?&N(ay>TyQ!W'
    b'L~P9_dL4TL8|DfntFTJd<(Q~x#|V%Pe*n-fxk5aH!51K~k(H>hus)#*aLM;oNS4PTm?c+XVL-ZRx5>LNY(mM|7^@lwE*6_nJRWGl'
    b'$7r)4##}(QJ!bpy)S&MO1E#UHe~auRqoNuM8kQA)9+&ZL1;!gE>k#=tgaylID>-Bg?4j#ft;mfV3=fLUh7nA#h<=}(^&Ey}hobDw'
    b';<))p-(O{<?j2tY65#l20A`C>ksxaT<k}J&)-`RR51CufrD&isMK0DnQwh4L$AoQ935^{FhT#GnfrfU2R<asR6i{2}AwCHL{0=vd'
    b'!Z!FWm4PT-lgyJ^?vx#h8#d+`VOL#TP>O(?L?DA-=}vh7FGT)O*!KoT;rq5Y4#5u)$!H1Zg}KyG9hdY)&C9#_njNdp<8t|)?IXsS'
    b'0R#=hMnr~XX6(~YnP_!7R2~Tk6)`+|Rl8hRpao-BnpLO>JH}P<h~R_igx>%>6;Me4Zb_ex+vh%DGhr6^-W;oVUM||46Z-~MCeT<Z'
    b'4RkvtYohnZC}$-L-(rIm5z%4N5XZf#pdOv7EL!2&T`*O{3_W;YWr=bYtZPfj3o|8g+wx;vpjXL&xn~aEM%>$J=tYw7y|nIN*jvE?'
    b'7xAELwtdqKmgA%hP&C@x+wb<V{rmpuPT-Kp8UVOfcp`7%e@zVRu>ghjg0E%a$%+o&fDHuWK(`_@a~8xam?Hv*4L`<vm+YU6r*55v'
    b'wzP`)Sb=+(eap-a8&)F%7Xf9lUo>pAGW+S6lCW7HiW~am(ZG^n{kvhdSXXx7u+AcsCKl1MPER+Ur?LzSvI#hq!bp(0|Iw=Q$0SX<'
    b'WRMp&p6FOP3~mnqWg@^+*EjVg1^|=7ya5mJZFqbeN>b1u&r_}<M>8$#VtBH0WNC?qjZ5xy0DUw45nOIVF?&n~AuVTFvN>poO#VyE'
    b'JG?k+_l?{Sp!eeTlVW{ef7_9=(aEMJGT$^peFiOL$&?ms=)lfvtPeCzbb$c?d@@+!ro}MTH&u~<h{@M<@B}|B%mV%M9bAaqN=m?{'
    b'$ZianJI%uAfap#B$a7ta&4#3!7S?w#`RyVfpklC-$XA&dKo4y~0~<;fk>9Zrx&aMpc;9LgTfr9wS=I?+LHTbvu1y$-qoix<ejWF{'
    b'h1=!p1_jF=vX`(o_QwNFi`gMQ1C-`ORn!`4TG`!3!0oF76l_PVchqI$U=FFt!S!uPac}qx!Lx48Nz3$FVX-gVBlONfTfnRuh)1v<'
    b'PXyR=-#p|%5N&zN#6bT*RSMsBz-HYQ%n%ZVt8C{6jR+bs1#vSlal+he$4=o1gp;S7)e&QUlv5P82ybv8t#aQJ5=|qYuGAYS2Ph8s'
    b'JS(+YS4%UR1<33&txA@$o6-{QZ`~j9n{fPIsMHL55qO@5H1Nk-w#_zq22SkTmjD>(lxixlOdxcvT=m|<HP<OC7<b#)WP`@TbkP6?'
    b'WwwxG?L*L>t+hLV5>qRPzK(o{mW_plTDsp($?!hJE8NCBlzGr^WBeL2*+6dr-?VnPuVnuRtR6-fbOT`ETe}Pb3`We>gZPXmL=_MI'
    b'AzGQE;`-{Uk%mGolY|yn)+Zx|X`7RV8N;+#(kH-YfJQV_l6`}-05H$lK&@Lg(N37%L6?m&r_t<x4h&KY-#-M3FFF@}U;~=0EZbdU'
    b'#SnpD4G0Gvo1h2oxp!=FqNl~}I&6$q3_R8=Fm~3zVFe;zl9Qnr(e<x1wG3mH?+5F0>{ya(SZHlY^;>LtTGC#3jnU9pVF1boJ76U}'
    b'AXcH~!^=eAfL0@0*0bdea3s6IWRv)or<MZW#nR%m!2V3kJ_*G@1b$g8ODe&Q5_jSO;xHsAC*NZX=!0Q{e_I}51RKt5-CtOqUW|K0'
    b')C3RZ%UO8Jm?e)PJ7HpMqCbeiBopph65?GaD^VmMi*bBc9^W%9!N)~-MB0~e`FeazAp#O8cn|j7x3F2hdny7uvwvv};5CTbd>ORn'
    b'F_UWH>2hLEDHx&Pp1~u+4tX#8Mn?kzAS)}s0PQMk6|-kco4~gyY9IqRXYTkGU{?0=QNW!U{<6g*BRk4C$Z2>~FUG!)GTcewPD|em'
    b'1j-IfY1m1G?wV>-U0@?JPyoIz#2gt~-*aISlw?-c`x*f{aPJJ4!roB@t^&cc075`dLgXj1u(&pXU;*Z`Y!}|enrV5%RvP1XDgh!e'
    b';*=hX0^b?QV{l}rEC6B^Of47@yngcJrj?Bk`93S>Y%0^z4*FS)CbWQ)!QDZ}v3k~JnFP-OC&IkuD#ji8wi6+-#Lyb}ejXOK9<EEI'
    b'spxvxSYlk%0SpIq>{#)Nfa5g5zs{xKeduB!n?q25n+^yU+F_){1SWlTjdo%I4_iEpv%3bKB1<3~fNvgXKosEX%DW;{FOA2XfsrwM'
    b'37FK_J(b-pH8^>k3Um+M9S+{nhM?B6i$Ennah6?4`0k{@^+enRmgI|}5pFn<Fbc#r!{z}Y@MT~^KPGF!r&KceqFH3kmwd3cC(6!w'
    b'?o<VU)rfG=#s1(}U=j?xwPO!-mKy?o%E!bVI+ZG6Pl`q59?aguG2y9skicaRFa{-+nmI4N8m^|!Co7az#e=58uS9i3+8$sSm&x}>'
    b'pA<Ng!$e9F(B|;`CbbsWm6J__*;E>Mkj*m?aD{Fp{=jYWn8YJalcmql@v2#x$amR+<g)>?S4FcUGgt@T#M<{)<Lf{84isSkdO^NH'
    b'zK$*4sKvr)bcyvo(MvLImWi<w2KWbC)d4XV1POM8#!xYpEHh-n4JaD?*f821k+<uvFex+GxB)%*Z|6Zh!4Q}kwd|1vDr8uW-LZ+b'
    b'fzM;Jfy_2J9eX<3;3nevLAQgE^R(>NSR-4y@P!vVu-ms*uS~@9;AF>lWJG2)oPm1bVfZ2dzQa)2FkyR#jSj{eoa{Ky?FMD($&@R#'
    b'unQ&oZuBoFw=Ttg>mLg0OpYb6I~RPmHItNNbMoP?KvyQSL!K*x<*$7sT=*EK#~T4H$YT{64kTm5MX)iL4%z!C_=Z>ot!BmQ5s61a'
    b'Z2&1yi6_*#u@V3a*fp+ro*J>h3;`S&cqU~wAgIhhBl>liYp{e`$AtW#5y1GB&N6{#E52t>>1=cd8mu~ICJ}oC-+~IT2XD~9p?J)>'
    b'E{XZttfd2j%KL(bT>uU?Gd*ih!DQIiA4DJIkc}skjt$xndC1a4m^K_q5PZ*>P>TIo`DP5}r3SKi>~%7eEf7yh_F*|Z0LX2AS=kN)'
    b'0k8DuyZUx_tXXvIh=*v(cR+RQktt#edoud1unX?G-5j<M1xahHpN<5kcwD~kmPY}ZxRhOEkCez4Z7{KzTL5N|EYC<5Ap>AzU)246'
    b'&8KnwX1s~QbNA%9f~SR`)27+Jp&;|i7XNCjmY4LNIdS(La|_A}K%M-UbWqTK<=`Y(U=<Aj2;1j^uYqd>W|esA1#Sh@zLK9aY2GSA'
    b'k|7CD$>*#Ux4uRNHk7$jzj1~uVw!+#SV0EA8olAGj<t_GK8Z+Y8(Sp6sx|bEM^x}Em^m`?I8G^31oynyMsxFexv4SrciikoB`9-a'
    b'ev7P3vr|&n_%fzk8?YQEFPhM*FOJP%NrXcfZIx2sL&f^u_K>%1=nDMmK(gt0EM@W(if7Y6SSi-Vv;2^UlG%wIt80oQ`A(xeaxaDm'
    b'viB87^pLNFiY(9RC$Jg?Gvh1kF_2_KmfXKDJSHs=(qV1Q^IdldbTz^?*<m>Q;_hZWe|w*BnohYocH_icvL_l`I}0GX##cI54bXr%'
    b'#`k7tHm2*W4jOF7@_h}MT*o6~!)Y9!jb?f0<`wiKHK~DJF8CrB2j9Sg3xF+|Nbq60{W*ZdG625A4de|JC>ds<L2|$n%#^r^>L<Pj'
    b'%RvSn*wmExpxN_{RGsCfue4URj@u33H=6HnEqo)cXMhHWjAcs9M2d?&e-U{Nn{D9+a8i*+QEcuId$q(88J;nBnBT&}^sM+&#Dtmj'
    b'fOy^HXn0VMN9HD#-e;awW^y>OCzj+Js!C+y&|$XNQN2aPv<$;$C!L%t3-ehr%=YSe=%u#Dl_&kKiv9c872G;dQfDgAZdX`--#HPi'
    b'0DA0r%$zUXlk8psT}XX1WbltRssg+hGkwrZ!E&u&$04==tbA3sVdXTGJ8<s=fh21-Nh!cJ8N?+E)~<j~#WJpUm^#EhuHXQr0IGn~'
    b'GXTS2=QgqI$HWA%!>l_LFLB2@Z^}`DJSyKSK*H+t#F$3s*T>w9I|ib<N{`OBlV<j$jNEX_JddwHSlFh{vEasss=(<hqZj58tY;wV'
    b';6U$@i3AF^+>HbU1Qb(j)ui|$L`(DpJd95}zAv={4Xu1Polnre#ut(SBRcz-$XD@QEeH8{rmJkH0~lK2Ndjj>7aRZ$7`{nZQUY%{'
    b'VV<#J_RRFJji{L1(7!VJQHc}vg~2h}k~SmwTgCG{d|O-a;{WID&D!)zuH)Q)B;`C@QcX(cW09gs9r+SZj@_`(09*h_(ZBx0yT2+F'
    b'Q1wla>7LL~XIAdawIVXtiWr@SPT|!;-l@EtSH#o>4Vt6iFvMc64)@D?x4*Yzc67Z`Bx&fO54cq$zta_CqkzWlsEqE|ur7+Is4DSQ'
    b'Oboi{RJ%IZYbENr2(GAITER4Nh$_<Dj+)Fh#gPOwKt9SQQJ>KWt~yEtDpx@*<nMmAZyJlw#6=!M^453iVx6%$+J>S+I_2is=flXR'
    b'EKDD1G8fD#^x+f}%%QCI2n3$wdH&(Q#)r8+DzE(G$5V3ohmZZg_}j-YV(rFFLulR#q$#hJLlpq?Bq8o9QY)0UEcK!7XrjhgyB1WT'
    b'!+yGiIWyXSjZeRzSU%h5#y^Z-*01Z+KYsH&Prvl_u~cvlPa{<C%tV(*TcU=fC_^161>2||mgrEHMRDJjjQQnZ{C=9opMUq8-~Qou'
    b'|M2U4YGbQB^HLvOY2=)t>t{)r=~k-se5GeK>60}c{<x{p7sG&Fqu2h3cmBLSefaV)H1{X`_M1<ikX=w%0RnwG-f-Ujzf;-mKWyzB'
    b'UcCR||9txJ{^>bKr(xTX2E01hNRuVyHt38iBM8z_Mz(nnS-jPTG=xwZ55qdS>(V^F?QOj|i8ze@%UFdT&-<0eXv()E8UiS}51KW*'
    b'qoyrtJB(^$(B@N8@k;dh<s@FUE#90#9w^3+(m<L@C7xCTgjhQID?|C;&5fp(KDE+kooFr;txgn-tF^zJ!MDwfzkL#}{Cs;MDn*o4'
    b'xwbpr*2Eiy0Yr=h?{!+U5WP`^U)5+ml$VomL!zad@}RZdwP}1c=Dj%!Ou7`AOW>Ny4!k+JK?-ZnUS@Gfa>QsjcDPFDU~WS%)XE4{'
    b'KBez(X7TXhZ=ZjmI$%8<W%ZBW=jKG_q|``fs~!)IH1?O;bEaL^AuC1CKuXo|Bw!s6E|H5a*S)@{f3+{32JG)>#{cx0c>3w-S-|4+'
    b'EIi&FQX}Fqn7?eygZ<Ec@cM7-Un>7kickk`U=5RkEw1w9Irlu&6UX_@{;a=Ku=(v8Z$I6$`bZX`nzRz_&Kvp3iN)^Lcmf6{X}js?'
    b')v9P^`aXnBxGL^Qn-1e{&g4lG^X5zdJHBwuu<_MtMle*MfCoygLPLB_T(@hX5VTMNpT@5u>M0hiM6oW-<grimq*iuw7E5^sV(YZh'
    b'yfB=ai_lVyT%^&8=k27@D2KyVf<_NfH8FhwrLiy0;&lt@&ABvN7h+w8@;fCSZO2(qe+(-wi^yMDNEC)9f+H-0esPX12-GfogRafx'
    b'XfD0|O$Hg*Y&5#)B<0B<+U#vrz#4+3u?(;`-ms|%LM`DPLv2zY&0qN@A3l8iseNqYSQQ0~n={!K|DLvnN3)ejwT^IE*Ab+8shTPT'
    b'J1JQY!lgsVyy184`HZ4g<?2j+;hy$%HGKP{;GE@p5R>j$`;e`;vz-WJV}P4Sa=7D)qPk8;2cpRE<XyE~{o+KvZ&$rJ51yP4&rPq$'
    b'I4P62h<-b4;;cc%TAxR7w?$OZ1p_VBvls|sTs+dPd3@KrdOM?K90^6UsO<{Vavg|-QlFw<TwBJ&^F)gmnh929T9JLEkXG6XDEZQC'
    b'p4wV(PM{)v*69{f{03MUjNLaL>AcGvrDju+t%M>lPR9t^X_Wi59fmQNCh+pc>NdnFts$n5n6KsXbi!IHPPdp%kHZ3EpytNgv(o-3'
    b'M-7Q)hWO;ZHIe&{iwjVi73e`b-k@|)wdhMo1N-03g^e-dSvufUW-7@G_VGN-p@|oF>FXxk+XqIJBO%1+kEFS}0(#!5nzUjC=@{`y'
    b'pV%H2RfjGPSoCY998cNv##Da)UWw-8!+LZlzCD{6k1Nt5L}LyuCe)lJ9*R0IQwL-!<7+Nu4Z7$;)rr>H__~FQ+l|>gJ3if<i8)G@'
    b'a1PFh3GR^4JP9Z!cP)nqPxIP60)j+gT5Yr-sBDbmqV3kYJl;m$k?;m$*o!NFN)^5FKs^f91wF#-@wjPNV&h)yO+dUOqqynhMj_zF'
    b'G@kmVZ^J+(RNUDY4J&3N<rR46^NJz633pGyz1pooEz~8X^9pYcBC^`!_2NAK_@|%lj$&QtmyCygGxe}MY<ircg4Gx;n&D`6LJU(A'
    b'EOiSBbY)&zA+$j*ev&_a_$+$x@Nl{!yE%;!oXg-#@$89lX&g&TzGNMv?!+40(PER95K2Au1_p}bE4P8sU&Lh3ZKg-H&mHsVbVJ3N'
    b'l<=&>bR}|fan7T$2UzM|Pl}~exfe~>K7CF4y-wWW;wQQ227eo(i;F0`i?m|TE~qh)&<S}NxIx5@nJ4dLu#GJGY*wENOFmQ<1m7;r'
    b'=<&AstFGT|V1y&1n7YWR_>zKnQjjRPDG72YQfN}BQ*b-SRoaZaX^EYSh9~cyI)h$M<Ygo0&55KiYU0*M$guHXEyOWUO|HTx+4197'
    b'-k9To4Vo$XY-xr_Uu1J;UY^JcGyB^RAZQm-S+1QR(2DJ-Xbz6oY|2E!M+3qrD~H|c-pV^E@p=H=e$r#VG?Q<A?r(zuhng7rTaZ<c'
    b's;qdWNANMsq2MnzGp2IO9`v@9LNCh_PC%<J+Kbumu}Sk^-~M&co_RY93mEJ3E2%hI3zDFEndnX?I|@fhNhLQ3g)+YmusEkEKdKu#'
    b'Q)Q<c^Eet}Z=V@kbR03G$kvG4CLlB=h_&E;Y-5CU3B9JN-Pt?8(7WQizUKNW0CI5>kGG%y{`hutJ=d6}G}n}ABF$c1%rmTHoH2%b'
    b'Hr}n8(9*z#MY#scltLw0N?7v7d}}ISn`eLjD~}Sl<GtcTJo=Ud>UW-vr$sRrG}I<Ngh{lb8HHW%he(%4mp-><Db3K&@^U`kc%^fx'
    b'`LFHoAHLk4g+e`rl?lJeZAB=w6X-X@{x~O>X<m+*CNdEZOI?~yF2eXpNyyn(tMXk7+3g@dHzp~fFjiSKDV;%JsL4R-cSnlo3axFH'
    b'hj;<Wkh0ey5m1Un6zsz2N7K;he)r^4e-oIE+DA{zhNBG^Wo^Mfq0tQh5$H*N2?|-NV_e_?D|UU1jVD@Y*597TU&b$Mez^k@SwYl@'
    b'b)|?BM$Lj9*)Z<GTxKHOM<qud;c|(N`#K%q;b~19?$VO{c~NTd+qa*FlJIRFkvE-~`cIQ%>K<4>2r~MUtY$?*WNe)qfWb_>n2U1E'
    b'+>hJxeQpxxT&!Q;Oo=m~@auFI_o{vuIvQJPS*ScX+g4oE>WN9LL;D}~@t#G76=`j_HtaXuWG_a|t}aC>YW@n%7tZ8_sGERiCq1mg'
    b'7rxbu_J!#J!6Mk+nlK3C>Gr5kHG(h3J?c|Sfpzr2+j7w2Qj$CQRe=jG!Vn{?QAm(-$fz_Mt%lXHd<{C!n`pmW;?e6gO4Vb5c|)t1'
    b'D=cecF_>Xgx|pL41M>vsir}VQ9p_yaXE&F=>~~FVFNSQLJDD(rDGitZ_0;9Ed5cAMrWfv(DIm=FXfIcevR<vVV$Rp{m)Ap{Yy5gK'
    b'v=BfNgjAkg$nc4E`_)BoB5Ik6IF3|TGcVm%00DL^2$RspF6e?^82Ysn^NVq{YZTVAPU&GJn5jw+88I&&iu7@hdJ$u(8raQ_ty5JO'
    b'Z9w!S&vb3v?^?88jB6ZT&W`)rfgicslTC!k>MGhnzCgDyAKFHrQ$V2VcY5X9LvPhx825!U^NT_8#6v-Y7QyNgR!RzxfqpmC(S$3Q'
    b'lwI0R8mLuXe=JbI8Nyh*GUy8{)fWQ`ifgaVL$QCSIfW=QjnKU*ZfFRl(20EovVq1UMvdY~(0saZ{KY7B-c<F)*vbk=8DHRPxF-bv'
    b'b({+I<xOalcbm45B`PB(RGhnjuV&$j7n$3aR{C|j$BS`==d+;~NUX!hl=-<L4c**^iY9ZN#7n5C>av|?h=hyua!a2=nE3j*r@oI@'
    b'-}lf>Rz%u!gXNrSW$;#XXu#4e&{je-ROeTDlWwm%o5Jc&3T*kpkgpp+UdD|a4*5MV#ENg!<XRlFUrz@ZhPF}Ecwv!=NlH0(b1wWo'
    b'bk6LRaldwgyj<PAX6-@Xd>N7J?F==Kak}ac7c^Uj@ZeE5+OZL_vChHYr-;AEwIN@&guF_9!a%ex)2bP$D&B{V8YTk5&C2?YnhufA'
    b'W`v5g0$#YyW^^=!8tavjuOwXIn8o{^z85MzA)Smk1C6hW*&gw8UzGtoo@fzC)uK}@M3P;*oabM)H@p}Y#eQ_bmROpi#qQg5d_fLN'
    b'D-r%qQMFxeibdv1rp3`m7z5wuUdpv$zwwrQIV!%DlShj!tbG`g8Qje=foQnJ=$N#qY{eT;N2e%TFOrBriLEVM8TGqvhnKlP+h^gp'
    b'=(tkiX@VRexF4y~m;t|wrT93qEs7J$N&WCbQ<$Jlz+4&jrFrP9^f$YJ3{r=chV4l?`^I9=A8tE|r%X-CIC`u@F2xAmyEGQA#lFWo'
    b'hJLQSdNFpY$6c8g?$kEhMKEfqVb&eRUIcmy;?zQOcwuAlWY9ZNdZK)DTuOmwS}$J0xuK=TaH4_@xeMx)Kw-sROEzwhc<JTrT${CN'
    b'tS!+{hh{g*t#=Q68_J8(iO$lRFmS?FAd6Pp69bZNL?p@~x<0TU#Ye*{k!jOub!Jq49v5bErW@qtcjo~JFuDBEKvB05?m~E+CuVcp'
    b'+SJCgVzBzj>2^+T@PHM$J@Xd^e&OBta?mCc8IB^s!+0BIMt$EBQQqowGbQoa>V&bxV4U~c6^o^Gs3S~QZw-3+r#&9S0Cm`R;H8GE'
    b'0s1D>j}`)tGj)e7#wLhMD}KxZf&oc%h0%F!;MctdF9%0dUSAQNmpweq<Tayysf>(Clqgw2C{r25E5w(*cnWJqIkg~bbz$(=O$RTJ'
    b'SE2qIAG=b}cEU9^;eoK7FjemD@XFa?bEJ4NoROP^7I8vyeq9>(b@#!`fpIk#@Zr3!h64gkj7I<C29l%JqtzGQyOY3i%5q2TTM{Na'
    b'_XEEw(|-a52N=11!=$rS5LXcL(^o}BYGF7@{h~EZ_*46%)}zJ^SdbgdhN6~&Q3}VeQuev(_uG>|I~2b&m#o0%Mj$6{gtD#e=yp!6'
    b'8piWQnRYmDc^2+Ai{uKqMt^P+FO{wDTaLkHfYWg<Kya)E4`o!KzsO{7E(u?xm2wgHP{gg&dw8V5l$wHR=Vo%`R7&KS!k2prt%R?u'
    b'5hF+DT~TdRSczw^__eh%!j2013PYG-R?(g=kg7Ej^(j7Hn8S0G`|Z2FCa&2!WiB)0zN4Klq!Ijdg_h#E1*$wQ@?9ZM2UD<i`s1M%'
    b'Il!~4@NL=q?TP`)4F#9Oh^ufCiw`=5Y3oN8N)?l~2wMwDiu>w2aMQD}vOy|b+41EBE)|U5@v?;^p0?!V4q88~;NF2~#K*Ttu~s~$'
    b'p}CywW(7eqW~oEmTj%%ntJ16D>)Us0iiFBUTk*nU{Co)BYS9sxoY4w$Rh@w5aZ=R@7CEKqGnD47$V7g%8_sw;-ToZ2VCSRkH*G>)'
    b'ir#J>#UU(|N_YLVf!8hyeCj}WKVx-=^1Pti%Q?KXzq#W{9BS6xZYiN$P7~U(+p13A#J{K{{Kk>xZF~d$Q}Xs`gwldMPT=rvIgDI>'
    b'|M<6KAkK8!3*QRK(Smexdik!@zgs1EOT}Hp`<nI~lwt;Apn+~zuSK#Q>AIwEa9s4dusb$w+gzT+$+zU)lbQUv!CPLnAe>w)4`?_q'
    b'W;1KeLP9j3EFoe=AarUs5}L!&HM;n{`g0D~2R{n0|McP0tyxT(QKtSMZ<r#qmWm$zoJ(l67aWhR4kzlzI*4|P0B9cD7iW$-r+sl2'
    b'rvi<$W3EB#nu!0vl8|Bt!Qfbx1vV(HR0Jgjgb~x-7T+Z8RiCpr1(0@e*&l6Ao*Ygd*2i|j3P1fq!dPb~lSQI!o=CZxnfUQU3b?eH'
    b'F&H#^@V~Rc3$YNSouh#g({wG2`PxAE1Cu$w6P1~D3^hWkG(%a`=LHyz4!uWSE7C!s4WJ}`5?atCgl)8gD!S2k&f?kh<?Jj59-2GS'
    b'OP_><M>s66sJSmuST2p84;5OQvSz5osutlWafk-6zH=6j&&yAB0B2`X7KP>^TW)7D@km2}Tu~AZ3Uq2{<)iC5l**K;3vZfA=-AW<'
    b'P2N3|%Ts8H+Wn%v5Sr^%UtEh5@fVAm>z$2kwQ{7$v2`f@ZKUp(4QAj3zi&+8Xyp3mhY$a6z5j_x-1;_I;E@^wv|==z_QX>1M9`x0'
    b'-kqF|$QTA$ahp~X&i6u9C3TTUt(y74>73qq&(6eQj#BXkXfbbX*rcqfSm0}Kow7rP>m7$kWD;{Ob5$zKv$qJ|>EGTnlhg1&eR+65'
    b'r0vS_#i9+xCMUdRmXMQTRJP4x@*{-f1GZQ6f0%>!*d(yG74k%I3;FMdCv$cdsZu|N7jZ!;Eo13scp>qK4l1q27PmHZk6yn#jUmG?'
    b'agvax@K?Hj7Jpg~$OBWudv+#Of!Tzf9Zi@z!R@H(^GQrY0W3D_wVlCxIAeL<_JUIIM!df{{U6;w6RP~zr}OJ!v5G2KcPgvSkP=G%'
    b'G|nl)mMU^6V2h^}t%DtvKqrFk8en)mH>%z<i~sNaf4=|lxARBFa$n~4UAV1UhkBFHR^1d;b=vxMUfKv%6h9=>z@!6jn$eUFO}%TQ'
    b'p00b=JPysZjk+TxW6Exk@;;r)V7B5nQZuC2>J<8gxf15|n>y<vFz7HkPD;?l{_teZpIz~f;^~D-`vkG3cY&L!m8l3E6Jz7nMn$pW'
    b'IL`ye*BuPcFqf9(aQV6nGSHECK8S5m@PdDFpgn4#E@TD5L;(^NTXieiD(i?V4@J9;K0sPe4<ctr#VhBFnEBryfAM?I9E7DPlaC@('
    b'qEo#nsUdBzUmxMnDH8zARQ#1BXwB6VP>(j!YR8pffA{`Dxa!wS@qmt7(K^Rl@iKLF(-uW^ksH8<w&Fy!d^)T=Owj7kS={}ubSJuS'
    b'W#oTeC&qPt$LqUl72P(db}jL%=_|e1NEUPJic_932?4G`^?2W?wWH3?+uOV{?z7X`*^yC{47gWiF@F)8Y!kK_Q-h4s#3v1EQu^j@'
    b'bfL`5`^bu=<!Lc}T~|i_LwnzTUKiKeIn-MbKFQPZqN#vm1_Cez)c{4If;vyr!U)dBe28!;T?<SOkzjXa<Y(7{^Q*1Iil2pD;*3S#'
    b'StR>l6vl}jbRMM?RK%<eH6@rC`;8cX5zx2QUE9|G_P6)s;Qi(O`43&ZwQln^to3Zd(JLmg!=09XJ&4hVpf$0|gs22J9!jDS)m4(z'
    b'>95z$@l)gc`0(-kr!J%E!wL+-1H@2<(u(*S{=kSEQ|+f+ruon%9ja2Ecea?S$bWP~UK#tiVmu#0MAK73g{frjN&To6C#67(bV93$'
    b'Y&Vr^kB2v|9HR?@1(<Ot5#1W}xm5W4Cc}-p=jiDQ6B|bbe03%J7O_vQo@cO*Xo1^2&#i>Qa5zf3OL}UHdOiGy4<Cg^k8vqQxr{~?'
    b'#B2x|rT;^8Kb@=_%EHoVBI~D=zl<Wx(i#aYW<331DhjP5xGNJ_S9l4k*;tx1B}R|<py);uy6Z}s-QXOKqEZO74_X|f+)mRTI+qS1'
    b'?E8j26T3yZ+A!4^pCY~13Qn|`@!BOCKrj24QAxUI8s>WFF&z#0N@QXO`|{8G<s)tmhr!xa_^%KpA|_;{xLmuCUGwPib~Im&P>dB1'
    b'Z}?uD(nAzyANmzDnhu$5Un>?aOyEXH8;i&3*h>sbh{|A!oIrUR!ZnkyJ^ma$kE7*>>FtuW*-hBEAN#9gKT11X!z#Swhcd>YxE&N*'
    b's6wRCj&<hdOo>E5p>#^L4^8?|1Jd1z=baty8UF%2(Q<R&C0JU$>B4M&iDpzx{lxw#oJhj8ogU*#L!7ocXVYqrIv4L5_)yhafB!z3'
    b'R>M2Z5K}+~9QUPcat(BH?bB6NG<YJmte?H$Hy10-y2w{P`K-Sl_T*~(=(Be|ZQ3pDOKZ;I-G_kiR65q-MTP={!ck4m)v?cU3}3O^'
    b'?i2vTF|^YzjQraVAIKi-;i0`d2aLoLMXiaTDG8pW6rA^HhEMz&^BSmr?W!%+uy}1lu?-7v6wJH7l&p`^!t>V~iqgF93HpmP^OW7_'
    b'7}qk^AdH7(P7_@n1*7&dGKvw3Hbd~h`xY*d*MDwr-(eIz9@cvQ>6Z^LL|qmB@@_U*S9mX9MYM#9bl1_*(ee!eq(J@J8a!0!gIY5y'
    b'YBwv?OJknITz~ieuWuhdyypo2=F{U-*!RLzBF4pJXD0ec+OQD`P%)8^@!P-+7Pe8bOV^gS)1otm`75e-`_i8Jmj~_TKM8xD`>gtb'
    b'_Ykt(B6&)bqW`p6X-kbYMR69I5#4FC8~sV-!o-CmvW}4gc}bUt{M+YWep<BloKF%Xb8M|QA~IfVMW=Cvf?{GWVWpZnZtBWiB3?<P'
    b'rz&qNju_!Sq%tmy%hMNV_k4J6Bie8P_>f%|pT=?)p>!-@9DZ>$)~&`*jpe#W(FciO+G#GLzTf}hcmMTKsbS5t$3__r_2|BYXLd(S'
    b'Y$M8xj1_LhPJl4u3zE6d-bOeCa~=h-X1u?|YU!E!`GL0mr(09rb{@mj*&kk?4nMv$qv%|#^!{`wXg%}TX;@@^vD;{C(2rZ45J@dU'
    b'2go<;EZ3V8`R#iDmg$W3@$*H<k7bu4^m108xeXEAO3T)o6{Z-g4|{RY56^kLZ%V<qH#xym{T_RB7Jn2#`0Khc3;43ZQr0Uc2&OE4'
    b'`W|yO3RH?_q2U#eIR)oIGwX=nE4k&C>}6#3xct{*w*Uyh^JxA>rP}jDZQ*VmC*&~bx$t4>7d5qllXu{>wb2fzzj1x!KYw_){^QaW'
    b'TpRiU0@`aSIWJZR0vt_e8x8D;TD6A~t>WqNGg(nPR2@^H^pP*Vp1gcvJ%86llf*V#8LF&}hXrjVN=N4C#*U_GMW|s)*x8#V?BAMj'
    b'!w8K=`f+1y5czc|9M(qR1F2)mbxX}9+e506+iKH;kcke6)iyAsR9dA1U0j+i&pfv#aOIN=+c*6e2ja&LA&jQXrjT|bL^j~n69kx*'
    b'G@T#|n$2J+ae(0Kyt(ebd;jw_SV(e0c+H9E=2m-(iN-FZ70sw2p=qtZER^BQT#XMt(3un|+kKiFqknZCJs0|VQA!yR9&HzXe^?zV'
    b'e0QPUA+Qj)0J<M>jKhp1IHfd{VHATD4(E-b|M;h$&c9CS_~tx&!CF~BNg-rwxo5`QVJYkEKwFA&8>}qorXRF*G#?RDo9@Q2&n<Z8'
    b'Ip;=)L1znXbbWY%ZLc3u02k4o(9kd{INWlDX|eB0TPQ+!*=dioTRZ*6?E+~kne8Giy4uQ0F1?O|in;#KkBfO8YRVRKX?+(|l(HC@'
    b'@7j>&);51_H}`4=W($o4LF}x#1nST&xn!Ub3GZo&%pOA`3b@Sh-DULgP)<_tzj(>;hY$39oE@<vQ)rE+b1s)jfwH38L_<>%<ro#K'
    b'V#X6b$1Ipz<}N6p4CwQvH<wc)xp8Ng^<PJ8Qz&h9Ev1eQ*XB&aFIYEs`PQ1FMJhEMoC3C$E5b~2ygK&t^}@3-&6#5+8i#sQ(AEve'
    b'>u!!6N?Zzaf~1RErGgL3GzR9OKZF*!LRUEU7gNe<4nh^5_lJjH&#%1TaRveF0C|Nu9zu66yzF&K$&kD@blkQ>rZp8nWK_QMqNlBe'
    b'>mz^j5dWw4Svd0iZ9|!<y2AaLR$jRc@1p2^M0|c>%7KfkugfNfLhx2_NQfFL&RgN=a&;1aS)U1RpAL1m^ZT9Q;;u$GQG4Gvq~w~u'
    b'H_Ud@AV{pSTf}%M8Y;Ig5n@z{6ylTvt`7en>*4Lb_P{6PY_-}6O41Jb=&q3>`nZKlE;5Tkd~+SQ)ve!hXw6dNru}#ECH{}AJ@mg*'
    b'lW}IhWjxrruz$dPr>xWp8c0R7n{s{+oH1M}ZtY0=C^mjf?I;eOzFz{8f7CW_pMLrC`kSKb`QR2PP3*|1SLBr=kN%N?yN;n!2<i|D'
    b'cU_|_1iZQF(_{|?QnxSNA)Z?Pe!4WOYeE4&8KuRE6JZlDN@8GBL{UHmTjnAZzXhu|))-1Q*a%PCauhAQbiAJI5>GE6XO<aOhy4uB'
    b'cY?m2w&|E@K#8JVNe6sWqL<s@nBF^)G;0kk+^v>&W89-U?>u7g<<QLKaVf;3TT!V)J61<ph@pzmD2dbS7?acI7M9mH-a+g!BAa+='
    b'V7kWs_3d8c@8jJ%^8-W4^6=52fUX}hCa#JsLI%rsLv!KsJUCYDel5Y?qgqo0BgGLeAr)@L=hGG5e7eawGybY(%z?*&=#EpkboA@z'
    b'7Q-qI`%7w^1!uGe=p(~2KwE8z6j#mHhHK*=Km2)QEL5+9Xd68fh;1utbS+ZUH`a9McM(q4$U~eg0g8oD_e5G*P_d<JqaN>jk1z9A'
    b'uyG|NXeZGZP{uN=^=fOuSwb_K3EfCRCA6|onpolR<n;9Cqn7ROo5I%`_Y1Fm%GJJf)49J99}qObf)}dqcy)1AF-+7+*_CoHjCy^o'
    b'Xcpw{F9Mh2N#tnw`lp8vfBSUlE+RX0DQcY5S!N|^v#`Ndu$g#5j5;TcDa8rPh>~!vEJ|OJRori_+#LMTF!aKmu{a)@?jjtfV<PWq'
    b'eb-7`L>{xgw*CpBmo-97T76SS<P|3i!kBS$@W;}b^FO)4R(4Z2e^^_VVDxd(&T#&CTAoIjQS1OQjfyW*X_l*cI#ji5FAV<5D)s!<'
    b'r(OMc+EkXFt_U`}B>3P(c$G(BK(p~Ila=OZ-SJj&ybhpU)?e=(oS<{@_IM(0P^+QOikPbP5J3=mD7A4%V4%z>R!ni_WV>xayOG{c'
    b'ho;uNG6_&yd$>?RCIpIQx}Asq#>Q!S>4Wl)U1rUKR(;|vrZdhp!I(Bhu{VXILI3KNVSoD;m68t+0#M>L=SLUC783;mD^-duh@u7x'
    b'HP@s7C5}o<T+|#J7dGMt^l>TGDCG#irYoaA3z46XHA2XE1LmBC$GT{dj*wVz&Vg$$Dz&Oo><$UX@jiRtK}yK=U<|8X8JVAVJzN}F'
    b'F)ND?X$z<3kJKEdwW2_=&^)UDXG05C=dLgM4QMkFN2HWuyJqv1k)Iluermspo&9rr_f9F~KhNJoXyb^NMf~W<+1gP7Bqg42xN>Ph'
    b'P)d=|d4r*fBA|;?WVuZ@#1_Z>vpBoiJzd%&3^~}5o5H#voDeedbbB?cQ6t}2h*rT4Ih0NjFa9cla*TUM|L|Uj`O9U<+C+s!gDu&e'
    b'Xd9L@s0JvkIolHM2U}qwPa(QFm=nrdP2YlIYM1Vq!+El@F(kH&JLjntK%IjU4}J73V3QVBRY9C=D%YD_i=85l-3M+b#mp~_`|$R!'
    b'V#LS2^Vucu!RuV>5K|j0XuSNk@o?9hNq-d)8rqRZ>kuNQd6-2#z{Z7Ao8<Pe`hicadgsRvbYCi()a;Pu3c(3W4pFk6^`lo%3@Sk`'
    b'i-NbKsfcpO+(g~PDlf*jXYbtetBpkd+W4_d6hPx%Nz5d%vGgTp#`<Oz6P0HLCF)TwlsOB-rqb8tVV}C1&*w8SOvIli!vA4rkzk)E'
    b'C8wdXi4{Ll9#(=y4PLCV44V49qa35hetX!*4z}}KyDN0*2sK^=&Bo!QiH!{%^@3uqj#t~W4uyQ4HZ0G-)P}FYnz#E$|MMcTo!@Xi'
    b'Vf%&;lQ97!0j<QYV!vjXW|c`RkMIcDIYpUfOPf&QxW$}O4Ev5r9CgWS(#7}b0x4$KX?J_&3kA=Lg%QPRI`Aet8lJTQMOnSWY9ddo'
    b'ebEGTh2_&q>Haw!br_e?^}-ueNxegSDV-dvD7CLfpLGzz?Q|v2L_IqdBB9uR^lsu79Qz$#<f*O^>FZ0k-^gz&jpyyep9=O=%DbiM'
    b'*gH2T4}8K~M`KBMW$!Lxy>{~1={E`O-mx5CyBRM${p2796Js&09ug=q8|;-4cBuMBE847pgByqy+!X}I;)gN{g$#SgVf@SI_HgN?'
    b'4<PI2QH7vAk=u4A(Yq|<Q|ThnHV8WlN>wX_qdXjURLC8Zr%f%__0bQOaZ))rzXJ^Yds&F5479UM5qfT>aaD!|P!-$t<|N#=9A(*5'
    b'0Sg*50qio;9i#t2=isLgA1^#S><}@xP%7PmHx-X}cdBkJRJ0}@9#RmN6r{B{DWw%rbE?&%E^>YRr+(V?w@2-e3pb>BDyCZfmuFlW'
    b'tLQ&0xT{S@^WpY%3oH9h-%RCBzIas9p&eY4rn~0wz1`XCbtsMg>4qu~qzS2oD6-vRZBBpKjAJA3>%yfNtLdW+PYYgB>L2m`Iec|-'
    b'e0>gZfEkPHnYIPLGR5CmxVUX5tvm_>vG^{^Gc$sK3R6pzWTTN0>y2~pya2y@KmX+d3ek!Sz&kCwc0ln$H$lV$g^e_LF&M$a`eQ&('
    b'vVi_D1wwJtR6ODDox(rAefaeG;v|&q*YWmd%^Z&IErFgi1h5nrv<@5b>|m!pgAoX|TghDO;;;*_&D}kTv$>&CXt=EjS^TD87As1D'
    b'$Vsc>+_i~<>h#g~jzWZX2``2^LW-2x-8zuZga6^}obT49B~ZTOI^OArQUVs)F$)h}JSdCH7~v>Zif&;VJepF{TmYwy<+8%q-LtrQ'
    b'@seXV)=?E129XeH5H5^Moh|Mb6cMNRi709%Tl0m6{#BylS@>$)F^S_a{KP}}yLXo{Inp)*4?@gRwdr{tMoYbjgQbL%jiIAU--gy~'
    b'Zm%hd6^>h33s&pB6S;CQsNfG&AEZPbQO-5gk_Cvd`9Rmzh1mDVvHAoj8E6%vchqr!H|yRhTs;^CnW2f`ixU&pcGuAp9mkkRe``?F'
    b'$as%iOIMkpVZ0(5o<ydVOYZ(47np+Lu7HqHIw-bzk4QDLhWZP|AV&Bcw+^8<BN*3_o7IUx+}jj0)4hXVKNvO)-U^k6gb-%$h=>hT'
    b'7Q?_q-UuQnZ+i}C(^tXDvAX2Y_nK5^-!Y3ntogP*j{lc0AL)Pn?!rCuX4D#TfwWDH&U1}lP%`Ahkw-6KdTmImfs7Cy){$*D#Yl7U'
    b'9`<`BgvWPG)Wv>xp<J3bOyTB{Ce<<MwM|@-^Py?nj)xR(%YyjJRP;KM6+R0z;LRQ4kIv)Rndjp*y1~3v?<xT4mi}27Y7i0jTpO(>'
    b'WpTC&@M1QemW_yz4y$linLj#{(+;^nCk2kG;H>r5YWPBPI!2RS$krm!66v?4&|p!6sD(Q&FoiPha3=r2R4#0fo^&|E+}N6I?)}%c'
    b'%Iaf_Qc$sgmU;@SDTt35#K`dUR-lJhDuk^cm;q`-mv#rlwPH}N|FlbHx-t<WkEL;&I>w>v*ez4cs2=$y#<9kZIDp$yesCI>H-{*t'
    b'c%8ttqh$=m8?1av@7&lb%UVw<_SD%)b{k~jHs6ZeE-1R@4^HID-snL*Q<NSl*d2y4*NJZp9bbX!%pHT9CDKD<xLv2Yz=fa#GjrXy'
    b'V8vHy(BBN&x8ALJ^oL*V(^Z&i=pSttQp?^oV|j?AGk=SA@UQ{ytXQ`Uq^h+`Fu9+Gnu7e_o6!XpB#?ueOO0IpR39DYw_LeWmOfYX'
    b'7N60e&FgcZ0$)T$kzOGmNyB@m@?_R=`VD8!Pf!+j-13Ws4Qwe~QToR%eH@-T>#&{gR3th((8Lr?(wY>7HtLoxP2`mV$%T&8$&~|l'
    b'kbPoR5-WOvO8pCwa&2A2?W4g-M(3usO>w3f*0mfJ>+c%<u@Ci-U%v3-C3;tU7LxNvbt8Sc6=hf<ad9=yOEe}f%HwjXA`VLs2z*$?'
    b'72MTXa1;4-Vs5GlOz<S<H5$(~N$I(<SNl<`Rfob0tufjG7VrAP4Yf0l@Fx~|V<u0t_${Iv@6N9T!gm=(+`jdZgGUtJO}gE%IKne$'
    b'DcN~Ed<68?LJbC4yoAQ*<?F$do9p!l-x8IbaE<NRB{82hmp(>_#SXgZ_F<tkg}g$V4R>B7r*g5r8tvf`u8%D`_=k%ZR0`VoKW8+I'
    b'6qqADI-z2hB)FxZgz2w>xDZc`3a>bET0eohP2uZeXUw0UULeHAKmU9Cbp8!sVm`c*GDYsD`_#hr{&?%uk1J$@Lm*B1u5~TQ!Uxn9'
    b'9z8`wxjnx%`0)mCp_)OgyV|~JuHw;i4ijnQ8-e0i%Z0efUa10Q0r4NVkulK>6fJFCHeMY2XYKIz?s7H1cs?$~bqNF%kw`Bpw>r`h'
    b'6SGRXD5kd8VN{$uj}O|0q0u^!+_e?|`R%9Ar;@n;-QIrIm;ZcR2c9c1;Pp<RQQ#md>i}ePA@=L2Q}9|QH8X42a5#o`QUBl#<vK-_'
    b'Jd_`p!kN)i$L@fNynsZTmNO|WVx76gF`}g{rSKGmU*y2hBHOGZF!12B7dzmd1a(eU(65J$NjpbrSD83q^PGk2g;B+Ld4L&S+Yf7k'
    b'KJ`1Qt&W?i(9J9g_0wL&^WS?8UqDDapqtL?>YhD{B4mV9Ncg27M=+;YQ}fz=4cAiGrA|N&!g0b$7e@Z7o%0*Q`}?C#>R&HaBgVX~'
    b'Qk)gkP+rq<qVU)%z=$rCsGre|qpzJBf{BxJ&58y_xOq15ymo627qkxc&W=tS(+O$x0s%gC%-4XxE2nOxrxjCTEU{H%XgCi=p<rAT'
    b'X?dzeJC%lA;IGS}ysWXt;LRg(o>1hC8E$RFu?J#yrS6S&s_oj~2B*ZvHoG+P$$#`bOVZSFsTnQmoMsG?9P**tiMwU70D9KV(a0@='
    b'px+&{UpnU^ZK5$3t8M@C_GdQr`^UoSD;dmYZtsMl0C>G=mnmWt?H{wO_=g~R>pl6QEw()y!Rd?(*#zwamf_L_KAftv4q=@0H<}%5'
    b'aN>7On|cUm5DG@qGbLedoaJ)cN?^+DV)J<7nw7RtN7J%g0#bkZzh5pD4YX;Mne-p&*nx*kXHpPIDLPRW6XQYa<5u=q=pty16}q$?'
    b'vSL6t7b{&)Bi`uMra;&)WV;=vHlmu^Hkr#RN4=6r*<1lfU=&azomka4?F3V;AZ9OD$NuvIrCxyW^pk04iQ5ts>%f{L4=!d)QXCs@'
    b'X%=2wqqRvcwVR4lg}5zPSFeuy)h*;apUEfLXRV^umL52<W9R5fP>im4sA)uf(ZoYvh~rRn-C#-6x4U#3L|Nr|EEYnl)>VwrOzb#K'
    b'*ckOaF>;7S88~4sZr#W&uE|>g@_1T$tL?q~#qnM^!d}pH+RNg<YFo!9a|(Bc=3K!0yCevM4y;m!_FWhlk0fOaB`sli_~ebjsfGFQ'
    b'>FwoSX^nwZh1=Uy9*C_tQqrj^c5}s`eLo0U=y51rU<)@DM1&w|6|c8`_R|B=;XVD~-33T!?WD<H*dIGUxA9=9T3DrHr=+xLRS3E8'
    b'6}0nW(zkXKMOrb;(%p?2oNAHYj`r?<yuCyblcTXQcA8WW)hv8uMb1!bb^1px#f3x^x{#w5IY<ZzXub%t*m`3I$F<uPiJpQsF_H*7'
    b'<Yw~GyP&PiV|A&HYMD&W;TBau8+35*5z)cI-ZS`ebNJ5<|J+j@;D?7#7hvMS)0H%L%c$zD;oTBCsRD@+X;n?nFU$+59pLeZM`Ma{'
    b'0}n+vCh>27dw-ZOpAT_B|0Luyli04|%3E<P#+m8ZwP+z0(Z;w1nj_G0P5jVA5v%~(MLn%=xZoo|Kg#m1yjfPq%LnptSnalwIsY3s'
    b'Ive)VzT-kgIG%^Bm?oDgTM@^yLgK6D#zg+I-hcXVstvrb4=WcTqcy8!iKl~pX7K?etn{(14uIl=D4`qT$tz9aL?t6syhGUa5-0pt'
    b'?(aNUt1IAvt`OgiFsoH~A2nsn-=|K5Lh7mkBMV%bqJXhT9QZt%HRr{fiIYmz+1w&vG(7qT8mCqT_Kvi@rHw-wl(w1H&B>y&$6a|1'
    b'uMHtRmjxsJwE>?N`;YC{b%Ki*YTB1@xG+pulpXh>J;KSaI14Gwi<r(av<+x;D3qI0l*@~;0L5iVL#^_E@-BQ`ph9p^KVvKCtBi`?'
    b'$Wp2?u_(Qub!*U9HdG-w7oFBWg&BMd6khXAad~ikV)PQ$!==<JM2by1w;UQVI0uOH9dskal<~FTkO`>M#MFc%+7f?AmWoMx377xx'
    b'gLvx~$aNR^@8SA_mXaW^IBq)0zeN3~n~ptgGJ8d=(ga_*Mz=ik;O{K{c9Di2Ktd?_v3vjVIr=gi-k259@tGDfE1SYEv0-C9M5&eF'
    b'2CY2gSdt({+CB?59-e99;XgEu>xy+=UtIxa9d*8?i~jjl7f}Vd*Q#AFIxNU+C)$lwgjuJem5%PIjpheuaxwd0O2f65EnAy`D-fzr'
    b'@(?>#0JL*1D~RKAOc~h@p=e6jn#j6{y291VdAxu7`FmB#7e?o_$-WM}sCQ^58f6}rhvHclA5Fz@#Xm%1^IS`?b}(1&zc$Sw;*et<'
    b'?#nkP@vY1G*Mj)7Q^^KdDTQ6c)@$6bQiYztNnPaq3VW?|=JH@UiVlo;t8#;YxX{AIsT{IfzyIy}B!=}<(`QjqUSGYwUmqB1L2%3^'
    b'#pyr3Q&3b=Ue@*y3U1apKO^qBcn;x4-ttOF7%4uR*Gciac|1AQ{?GOIzkPU^zg=ByYpmDk5Yb!xV9iev9!H<3pLjM5+XWAmka{fR'
    b'sN3v&Rw2T$MfeoV#BcrUYU!_&ILQ<oc3+Pk<7Yp{#<HSD@er@zqw|NLM-m(uipn~n1~n{781;!VS9Vz>_-J-MT!Z_K@n1WgpPj{w'
    b'PC0g#mT(~u`z%!ND;o}-4~!G%VbU^ku~p>PbnIcY7nDJeBDs7-E_#nEn!f*eor&H>@QYV^FM2Odx@^KPki%+9MnFk96d@Y%7=>*-'
    b'B5K3IDCpeUdH+P7UNbHr_AnQvIZ9%vWqB@fdZa~Yb2rU9hSF9Z&G>H7H>9d23P10$&Pc+(n#K!5=f8aU_1DI0*sIXBOKFJnQRC=&'
    b'6kpbH(K%5|Tz2%H92IC&ziVKmi}hrs(Au6+f_XKMCky3MneS`hzS9b&P%Td#fM|pOvpq_Ro$@Bijd+YIY;eV#+(cbOv_Yx7@xXL*'
    b'{Fe^O7v`aWJyUSPFir~|DXZ&><Vs)0Clq0|_6~guYY;d?3L`1GkBKF2F!Szt90tmdWbRA>1Kq~Rm2ZKo7I=vELTw7?u7y<#x9ibn'
    b'8<vkIA)XV^fx}%(fPUYc#rN*Kmo~*=-F#q|(VdbfPUB4xL<qw+8@YL<2AwTpyU?8IrjooMEp)=Ye%yF9jX(bBrxU5ByX#W)?#kcd'
    b't#O$~<PJIRg1NjR!df8-Is<eJ{X~jqRdY*5{|j{4c%7&FX7OI=;?n^$A3JVdBTb=+z`d(Ubq6G8$=y+ZD6475mLQgeVc|rF&r=qb'
    b'=mV^Dkhj+ri09_<FAwWbB6#$<I-`Ujpl6gT>Fu(E*Z6jbLR3sU<3uJYXY^0>>xJH`?rjhbtEndC+I!~kKOdig*Kgl`;z72(J2#D^'
    b'_>_w*Hb_F`Q6Z{|<-0M)veEW~`qN>Q6)<NW3;B8Rt7i6(O#_m5Hkk;{?y7yCB4&Xr_jL%VA9k)v<~tj4Ow&d10|tIM*POig$E3Nw'
    b'?R?KPo`C1Kub^kzKC9Clgfkm=Nwm2r$JbQ^YxMQ)P$F@-Fq9!EUYZhI_reyDYwd8~LHYCg^zp;{PwV%SbMpD`XHu&&YBAi+?j%ex'
    b'^aCrAHz%Hg+26Jap}M?HAgh++4Pgj!6rmv#?%Esw{?Oik8V_$je*ViqRN#y#B~IB<L3_|2FocF1oz}H;MuLE`@;nyOVubn)2-0?C'
    b'RS<xFrQM#y3-{>1tfOM!%nmivWbr@&eRGtT^<BNyE={vg(t&b}-!@>(;7~Ro*RzM0l3=p8=W)qB`pk8Z5r8{fv=tru(WTk4xLR1Y'
    b'il|X&lSB(m><TE#YRCiI9efqbvv<U=m$uOdWqXY@(h|mUyeKGy&4F}H5wL0#=kS)|(i|1o3SDb^mXtA#vf__LdC=SrU$4BHUq{ej'
    b'c%(|D;;cIIEJN8UH<awGkX6H1j7B}|nzvV!QC1O+8!Vp5^Uf)JYtsDsf@WgE?Tk*U8FeEJyX<kj-}GJb<n6v0Bl_r_vg)McD8{+n'
    b'cG^4b_Sbmf&V1%&P3*$Dj6gJk-P}buE(8%~7V_-4zXf4D<&Gs5Z@sgV*8Huk^409~_5@zq5Wgmha4m0bL#Nvg9`Y5NLc)Ml=cZL3'
    b'MOcIY1Fj&`^uF6hVrCSbp>aEUe!Z*v^7GGF=zMt3ec`$OUGM{5lr7Qdr2m;Ba3$1d+R!&p#HOP<X*VYA4ipb{ej9D`=}HtQum95U'
    b't8C}#sk0PiA9Z~->-6_R16@f7$y2b~?Zi~lAjqM-LaRklB<;%RW7>Lc;Q#eS`0{^!IsMrG)E>^rVsrh3LU2+BQy6yo1799-)J`{_'
    b'PNh(fcLtkKu{BQzl(HIKw6kAMp=aHn&j`0C%7FB9FFF{6WxT6+`6^GKnyg5@6AGu5?l;~iwI5dY%_DF1x`yd__;0ltP7UjaU(wkw'
    b';P#|KMTee8W{2^Ha|zoIVuC40p*j{VZpJ|Es<8j4ShyIB8ZOV`b@TQ~z3_ju_w&;)?LS{1ON)Y(2|Uy&^wnVZrp1s7)ribL?KdGV'
    b'om4uXuyJjpR(Oh*?~EeI^Hjd|!M=_n!~u8q<ZVHP+RL`u<iiNkdW$j#6{3O@;$!;P(MQT13hkJpDcSa0Q~1V&`uS4z%*Na_G3(Qd'
    b'{^R}=4_iRfv>ugT^t@t;IHydBb<}SzUI3`+1D16KMqIYSKD#%>a_~J7fG}Zc{c&mECE^x`a7J^YX!;f?9UM-pKubj_%4vhRfw?u0'
    b'?|iV&fc=hR-qAsz^M+Gb2*^0E))!@5gdnO8(8euPst!ePbeftD)V9|~KWBh_rt$<~TMXVQ99Oy!!QcT4)dqccO==0v_ShgrEtnd)'
    b'%m_hX9Cy2L*94xeu&-`RK@>$KCywWL=c>*rRb(+>6!$X4o-xu><HnxaE?XfAM{u9%xtXcmKbJ>C#jCSv35!Y*Q7o(6-dj;4K)(!<'
    b'_fz|@i46r!LUU;z$LBc&KXF~6S^U;)zPHVOeM$unn;@iUm_pD@1@jsbc13E`Q89#Bl?{0+E+7H8Fy^xe?b<WFKd*-W#z6b9S3Gl9'
    b'B0g0GqsuDVr$r$d^#kfRQWTnq7M(owxse|f@fc{;;m0wTLi_xY8C?AmVqRgzRN8=w;`Nt~VBPf7if>`<=z)_?Jj0Ud{BBf(3190d'
    b'4}WtaXN<kCPN-@$?m~+G?E4VH6LK2JwTW~NDlVv)(TTwUbn+ItJZ{w^Bhc?}9-3En-)G((TeU;~(O&W8nFg_2DnUD*@|(isv2}(i'
    b'MpTANm_cdFOy9BEt@q8~TjTGm>#>!&aYM!?r#3M{(eQM1?nR-Dp_CGpK_>m|L+L+a%N5+*)W+C#J)^v~1Al!|mBI}w`2vpBEQ}T#'
    b'&*2W0L^Q^$0=Ek~&|Q>c=Y?KQ@?F2puG!r^!~gETngYm|&mTUuzn%fx!th(1n41y-eg!gH1hBx}Vt#Hbm0@Y@+e%)!T!7L=SG8ta'
    b'kiYbH&kTP5>C=~WC80ulhr?@z7eM8eFtB@1)o4~q@R8iAm9RrlzY5f%F{fpiVQt&0zh@4ImGwF?b6!f%#tn#_aFsCER<hKFNP?M_'
    b'XEWUAGg^A$poa3GrNmp0`e<zrWL%xQy*Iz@Y5(*2`zs7lbu_s#OaTEoM`2W?rJ#<sC?Ze#_Gw{+Ec`L?XfA?6D1_~@?wP{(R`F-#'
    b'4k^82#H373%dq3bnwrGJsAUGwQ7xbxh5<77zbQx4MbeX*`{oqRnZ}=yn8Z6ADMfnJxxVx!Vnf`$;<Ppe<$e~VVF!*iCJo#fF&krV'
    b'-aHzw?BlNoa_m}nS6sr~PRFAQRMAkPfKA08a*xgg9s%~zQ&-WEE8PnTE^+ibXLAsN(<geJR@))50L2YKybFPoWN7{gX;#;@5fz}6'
    b'K76cZ2VT#F^kU4Osm*a~3a?D&FMv*+I5)k9)iKyWJ{nC%7T8lVbE(BV1oJv-^#&Cl?OQU-jQgA`;JH~mS<YYmB8HcRyn~;!P&N|r'
    b'9_ZqPK4U3M!vW&)+K)$fSnLrAVEUlFTP2!%Ci23F{(R8T=dcbmb2u3(5YXD5u#y%XD(jF58C3T0?vVGg2ANd-|3-tnN%u_T8V<Im'
    b'X;@3<Y!qx!K|yVa__y}K+D@OyjhQgpfu5(dvUaLPD0mGQ?-~DF=y`Tq6zxV|C!I|P@l-N#f;U3oDC+Zoo6EqxKpRqcUEw5ahZxg$'
    b'A7zhq*Cd|(>d$l>DN7EGR&p5VW9s7@>iK$BWWp9h+@KgEL=g{{#O#KF7a46FbDf-?bFRN|Mr{g0lsc2B)h4A7%p)~5v0+84xVnx8'
    b'?>}0E)xcHSn64C$;$zva+%t`rPWG=)#>l>UB`{^og(rt%mRID80_4^Sie_!R;D~7G^Ry-I(uBViG;skMKQf80<qcQQYP5*HU=eY&'
    b'4C1d`J6B4X>Mkne=b=(1tdX}M`V^OoMqkk;+uh2yX7r8W{IyLo4v&tENskhX7xcxcPy|Jouf-w)B*M@Ri_Ph*C_G+0mTN_tvE%rG'
    b'X*`~l$LGs;=O$A{JKD0z@PdgxO34)5PTrN5kgmoSgCECpVnuS*Az9&ve)ranxiy)uVliL+*sl`<<T-+)DonVFH-X^G(8m&i77NH!'
    b'PkCeUk*P)b*a#eZg)@8&1lw-L^<yfxa=zDw6balNonf?vwC;lD+&30M-nc~a#RV`qF%AcViK>zJDKEucd*3Afef`(x^N~Cb#OMq~'
    b'@D(8;(P)M8jD6?i5&_dj#q>nOB=$N}QN1*ZhTWza<L=?Vev*Is^7->QRzjgEs4Ij{|Nl%rZ0dlykEM$YJqE44Z#+mSwHSp~o@@$o'
    b';I`d0k^g89Z(DzN>9BOHK%7xJ(J5`iI6T^*K^_;U=2txApM#IuvLaCNuqe-_PyJ1CH|Icsy!OL>`|~~7{!nAJ6+$lpHog84Wy8%w'
    b'nip@=>Udb=a?$H3=P?yhH#(BF(O!0QHotuM^7AjBf4lbE_s0(XbRoi%(h!O?0sRb|<&^npTur$yp7t_0G(<aSf)+jwLV+|L?M0{Q'
    b'&1<ittn?`2zPcWEDmL^QXa-42>)spml(bJAg%H{_n`(N+xI<nrDZ1FQ`^H~xRDUJWyz20M!i1MEskJj~O-@??y_+r+0$mu&dZ>2r'
    b'@-9xNKQ-RsnO!~Ps4yb*X<z#|Uz<FC^ZSF>-%-luh9Xu^6m)NcJCre2RH<(2eB1H7nW{ES!60fTYNiB4=>3RDC#}0C^S{1)pvHZi'
    b'ox#xN(<F>REMN&1)o5z*T7$#>j^;Q4;}y0`Zfr~kM-7^)Men(-%ireoTC)GHt@85&&$@qI|Mc$5!*3ow|Lw!Wf1aV$+9g&SqG^9L'
    b'L6AWgGIbvjI!%Ld>s&Or-5u(bHd~<+T;X`jxV%-5w!pt04O^Pe`*yLs5%WLM!-d%<*P&ggT&Sy%L}<)6$|R;b9GaJ6tut-t6zzaY'
    b'veHeuI)j(>O4lnbT}OcjQ7q()6*#Ib_{3F|D-`FpK#3Jsnk!@qv5OAMTuMAl*{^<eDqkgN|9atRIR%05wT*(*7=xyQ6a>QrigyxJ'
    b'SA-ZCsO@^FK(~fIkT+d(iF3BKu8#iFo8|IB1!D-v2zZ6A?Cz~I!t6T;VT7TGrIV_SA|4~on4(20Hq$R!ns4ZWU!BH*ypYIa{4eL('
    b'<3>TIi@%4Wu$YwF^&uLH*CMl2Lx<E3Lo*HBXVV@v{-hok9Ad4vCh&Le=}#3~S9gO}T4Nz<g8m+_o52T)!v(&CfQkT*S327%dwdtP'
    b'7(Tg>t+LNr&V;M;cxu*VEza*ngr~}mI)FW5IEwNBK7l3-8ok!SNPx~OSGRzfHe<vM*sQq~Pt5hvVJSxzxpg`XN_^XItU-dAby@8L'
    b'rFcaO+neUbGXl-MI+!)>9F^c`Uo8$CurH&nuZ^?6eG*4F-O8TP1NWHg3fa>7hcu(*l1-FI5xfVjA8mQ7j-gQ6baupW6}gJS7b>#h'
    b'_6+`&E%6_3KfUd5-zi3%-wZ);iXAsc)BzFNaXNlg*lr(gj=qg;oI^zerR2Cbstw92&24_y?O8A^6$Uqo!Alx~ak#WZZF(L>(Cw&p'
    b'Rf>bgaGV0g>ufF7gTh%sc(A5SU0=U^Iv+cG5lVP?|8HMD4`uZ;me>?j7;&%4tvd{Wpp0{>N4{mY)F<virpGRJa#((F|G9TUzw*}T'
    b'Pfz`a$;KHI*NTzEZm75jO(9Sqc*i?gZIny4y?eJ213ZOf&1q5Mijmk7al84m|K+&&UGrbQyggTOA{L0T;xIaQt~D*V;B|@J2XXa*'
    b'8^NN(T!1QZ%~kRt(}XR6e%HEu0e$K(ejN0~n9o4D(TA87)&I!RAN^h%)A~+r+A7MR_<LegxRl1@ECb!HMiop*m$%<nj!rKe!RVXz'
    b'%rlq1)=t8|z>$7jOMOG#hC%|ZxFExrr6AtHdr8xT3RfAZ=@=cCe0d4JZ3sK0!_OwjmbmqH%~gswYlzset*%szJcUBPj^Gen+esS_'
    b'ygAK`RTBWiW$W%59?Ef6F0x0SJ-9TXpdIP47-;}&$TJK9I3;g8shvH<TBnX&c692BnSVR-LH8T)gKPZfr+*y$<qZuoZ{B|#|M2ne'
    b'PxVa-ry>eeO-$5rO|+E1YIF6udPD_pw<Samxq`iL8`0X)2bjaP5%;Nx<I_KWJh6#4>tHc&9-fqI|Kb09`tbg#+)dGa^WxK#4p+bj'
    b'L{X&@ffe{%78ftWYI)GTQcgxbUW*bPebC=ih)dIW`10O*^XAjnN~<^PvDW{aiGalCup3iAFjxpKXq)+=G(gV-?tO%tjtLRhd6{lu'
    b'#lEDY621pVS0_^5e0dw)oB1G|_VCRFnmL@ZM=P%5#T{}GLP-Ri712l)%S+Al61iPH?1oauh{?OG|I=$L@#`Ztdov!p4BqHae*XKL'
    b'w?{Sg`no5S-_6ncqX3xnAx5zX71t(=G-~WTeXc=6j;O=Y-Vi$lU>P#3FnMJPpY@Ax`cdlh=9d#tee<|3Z+>~I_IaL2Q`!NN$DplO'
    b'qEoV2$autPeRa9*Y&(iB*aqaL5V>0}sOhgF2)+KB6M6UO-tcuEhia4(!dkeOdj)6ZUnGs~It;DE+$iZlPFl#RirN(Kv_{>Cy0l(z'
    b'&0{>)FuZvXX43h1R(JV2g?aej?2L#rN}*K*u`C-8b7z|a(i%#@X;W7(jG&kauq^^_X#d)qQ+Ugk{Iz{Nj^~H>@BaQ~z2`<|ew_k#'
    b'YQoE7`8kHgP%;O_JrRTLVJWD}D*dfWdo<F&$a>8g=q*5P|Gp`(6*-#^AO7~{(}yn)<M}hV4gyo6vm$1;nz?Q1nMc|va7LMvg-$f3'
    b'su-G1^6;41qkq;*zZxV?6L|NfKc9{HXlkLavVQ&WdA(`#F>ZXFka%*Wl)_bo3B?6}GEYgg@wb8l6isS12*zp~_aa1t0549Ll(DWK'
    b'o6vurTGrmo$DXz4bxC6ON=%qb*olCrAT-9<z_Zk8psaiNpd&QsV2pJbt)zli8R9YH$ENXdJv^?%r>`@}%GgC;zfOKaee#K(SajII'
    b'b)6nT!Z}ho%D|#Qa9E7nPeU=QuvEJ>gLUdrdo#Ye(jD9M>-akT7%Pk_5af}O2pI6`gN%@bjEll!NmQX~OS*`+6LsZ>%aE`3dlCL~'
    b'<Ny5bLvQcid^#}nH^=p{+u-Xwgw&KG1&!x2$m!}2f%PU#toT^0IGhjMDp>lAqi~bHM@R+>V7IEh`6a$a@b=WMrrmIAoO?5l&bjAJ'
    b'5p^7j)}9ARosWt3zdKs<QnOeA3q0jCU5q%jDbb73B!b8k&-%W6;LfQ$rPDY2-G{$@orn&IwgnYC1$9~M5^%&ofH{OZ^QJaa*=-8('
    b'Hu8&N3~lk&YpwR}$n|w1{qf4-4HZQC%j+<X@^qP0%@h%qYztD~0$RAIci@b82Uetu7iC0H(9?-lYeP+=xqBu<>`teqz5Vsg-`;-y'
    b'Wj?gOwRg|cpbNbS+zDJ#=!RU5Rov!YooWu@e$<2n>4#DtH&(T2b*A=HA<F#NH2yEQgU@68V7c!@ccU6gihQLrQJgL$?=_0SX-&wV'
    b'ipgQzfP_y<-LZz9_mBNSKy$Q@?Qt!1a-P$=u$*YFaGa8dF+tD)RoNa%^i$t~`&ozaIBjD!S>bB!U59Aa(gyj#N&M0tepcxC<-^-='
    b'Vy3T@kgbl2$IR4EpKK8@7}HJ+bj65MD8ma0`b0J0ESw)xHL-pFt{e})zTuMi&Bx<u<2jp_fMQS;v7^mfEGJT16b1DRZgbJ%8>wu6'
    b'FdK`5aW9HlLi`QSlKUs{6u8H!r}XO#)~?Cv%n^Yp6W3SX<&ec})57D$LJOCXM>94C0+ZVq`W`gxS$}*6C%E}4Y6{f&E^v(y4mZI1'
    b'nQ<Qz<-?v&aZI~%3POm2^sEn{vpHzD(Vv~d$G&?aldje`pWDwbKgL)=KO>#^!qLktErU3>P>$a#;eMtJB6?yD506!&rqUoOE}6qC'
    b'?d}=u$9rPMsMAI9%bEBRs?I~)-F4Qv0d1m1sbj)BYxJU}PH;o}qSANk!QyD4VOsXzn928N(}-I+oxL?M^Bh^&c2ln`aFLH9lFaQ>'
    b'5+eZ)_pl&p{qR0Tzw!PU`S#S)`ldbBJbjC+@WIIR*$cr5)Z?}(uB%jD4;_?U!d6UFO654j9``^c9V=_?W-ZzePvY%+<*<(r>+|=Z'
    b'n`#iHgP`3f+7q4E23clk^fklMpAhZ915@;)l$o??mF(yb*+H9W{qQ{Af2~XWItSq=9ugILqW(vDh(1eGIAlmnA{^#?rXieOR!2oN'
    b'V|tXg_Q`VLhv)F|bZ0I2|M{CUS}Gz%4W*Jzy%2?Efl}_mJA%T87u+AIPg<Taz&3&0X*#Y4{WijSH4Q}x&EU;n1#XaTdQKi2wGi*U'
    b'X<QB3s^KZ+)-QMKknN|O7`=KWw%lv)yvHiAXPs;t?hoAW!TgFB52ssFt;_Qh=<^OqVL*DVVzr2<!`w}D#2W>zIM$jiFSo=D>zbJ_'
    b'HmV>-I7(Zo@xFgHAIIy!X^m~$>PJS8ZiA;r!)nWtto7q>E82*%t%9iU9d+Zaf1HRdD~8;kLq2?M<9zcA)p(CrInPmRR^&nG9<GWL'
    b'U3ApU7=nK6ly?xk93o_jSlSX*Ti7B8X;(}-v$cHRg>ro&kA0lnSv)p!9y{gj$LG9;iG|L@<{@d5ERm!@=C?$zfEE<GC>T*BU8|0X'
    b'EUuCZ6lN`b7k~F;p6<2&_SDMx;>?UFWJ_a`2x%$H3-pVUXwL%Y6gL<5ib)G3wt6I)xTmF{RFez7-yg;l#!0O##y%vdpCc*NE2x?&'
    b'p$q~3(yPv^_%Ks)$hPlcyU<T=)rn5)^sY=9v#kne!Ti7!DBpcEd0Npw&`|n3iP#mA2E8Ys8QgHh|5B%jh}UmtJr&=M6kkM_U5Wf&'
    b'E?DBsIsfP+K2jj~=I2vO>GNU9)CnI|yw>#8jJ~@U1dTn7E{u<oht5$|q^KfeZY!G%v1IS5Eo%3pj8BjI^4;6N5<up+7i(fz;(E<!'
    b'^o?nD@znFTP*H4EpcshjBwO~fn0f0H&8=Uo!(om2!&CThYzi^g{pb++yc$cPLb);^>gdzK0i8DtD3acrCP68lv4@9cR_fClr7{dj'
    b'KNS1JQ~5*-hK|U0j7-3Pg*uesJi2;10E+3haivE$S;`Z(tURO8qL@<gTqr^s;_-qAJ^c7Ao-cpj9(}gYz(-IjMPz-1c9bb_Zd5kc'
    b'=Me^k)-%1V9Ws{BG@BWG?spXgO}nm}%;>|>==rA8>G?)<@ZFntN3ZAe4IdS<`p^xL$Gm)B8c2|n3xtFsfOwi9$e{aPUx9F6n}~W6'
    b'YYofaJgOfaTRlb7*TIcWzvVfzHkMalU%RnYkuha3Wz>q+XT#US4J`>yD7h6up4l^Z&=i9SBbVy$p1{YivV?EGyyd#{VZFFd8h|N9'
    b'3EXjpO;ziQ^kSl3Kv0b5Mx7T;m{Rl9MN>!NDJ=OFwM%cW1tw~5KF~^c+$lXiL_MdFES{_lR)js<rg~hfpp?~xCKN0@P7YhRqYHcM'
    b'm`;5uk(Pm}Bv|q0>3G6e?PxQ7-h<v^5qRjrY-0s;6ajq~{9jsY<X|;uEIJ{@LksbAKnQ9Y0bx7)y~A>MrjYRV9k<;VZ#So(9S4<}'
    b'gqw6GdQ?o<UHScJ^-Vr-ERu4qF~>GBehZP7ZjiaVO^TjpLu==odFt(aUW~vZ1Uj5>)vRL3*;kqr6|Z#+@$Bx@l_S`fkxWbNsMi&1'
    b'-fgx!hCfbZqn+_FXB<1?`Brfmvy<|p$ZynO^jJ@&48cka$>AbGw!OJV3s5#u5H!|sSkfzg?*GmV9!|Bo&nZKo-YHvnWX**nY~D%<'
    b'wT4j?EsQNn9GE6x<V0py2KPo-r+cMPcl$>1X%5FV&FLBBy;9bzc_5V24Hk`6oFh}2A!?Y9@*(Ia$`}HE7H`>tLfM+G(*~cjW_g<z'
    b'KF#9<AWjqcc*^Hr=a3rrGUx#8%$=??t5MKDu^#mz;>gt1MkR^(KvZfm_?szC=R?Hh-Z=nn&&0=qXSbOnp?21bb6cE<Is_XAP8KQR'
    b'o1zRA&|_<XcCnEbKm%8W`9s5heC*6RzQ#9mm|!$5yD<Wc!&1rL#J05Pija1riW=CLEr^aqeJ0!msR87-t^PxEc!X05Qg7e2Q_aeA'
    b'=C(LyauZ`)^J3l>mqA|R6_XvF<y$ma<F=+Fq8*cW?v{2Pibb;dk%@fwX8biewHdVPJ+mbc_*c>n1F`euVmC?^mb=b?%6-EAATL9S'
    b'u;mp$Y<uqn-kzGFzTQ)O^DzWYM0L#6%F|GvbDLap$A(fOe$z@#v=Y*&S*YPExHr*%MB#M4J3<`?^6TyPiGY27YvV>u_*^JfC^oo)'
    b'MVLVv+|g2k39Zg2TICp%CdH>HxMMWk5Os*#kIiI$dGR)xME|hP4)hWUEQ#O>p=5CwG2c`73+|F`@dV;1or;R3T*gl^vpRlg^p8~b'
    b'y}UJBN<MR=*6UnUbfR8UdD4s7Ev>%`N*0JG_f#V_29>uDuHkD#RjJ-PgO8`Cifc1T%7nsX#+sU~6S)+CK*ljq&5Gm!R9H}MDI`^z'
    b'yqhSF^+(mEPj_$2hqvRG$1wT!seu0(+>2i~F{)6uz}p5hDOuRn7uwQ1&-JQ*-Nis`2%<d#I9?xWHib)H?oM2vSNoMf`CK>uoV~~9'
    b'VI{68f)}}z+uTZUWc?EH6Y&Xi?dnAFs*X`|is!=K+PT$qfA<&pOmU$Ohfp=|=noHn=ZfT;c&Q_oP@EGiOk5JRki}v`6BYIy-TA%p'
    b'riV5}jm(!Y%ju(3On~~2P2*Qe<=?cAAHO}AptnVlIYQHBB{Nrc+|=aArMvfs^^rm%E-jPV%XPSRr`_Dm8^ohv;HiG$Ae`S{K^#AY'
    b'PJU4Q4PEO@1I0G6J4>Hp>-^Y4H`<rn)a<Q;sr{l%i(z*Rca8r*m8U{9-HG44G)*&v7<9tdNKP9p21O|Voz95!Vh>_eE(&02HP$c)'
    b'0c*?bz6yOcH%I>RUgYGcSm;ONil*`InOSnbBMy(x$S_!!ib`m0H64oBsCjj?gqDRNH>HhB%nz+MgP82?i@C?)pD%2MU)#^`KYaT9'
    b'c6{?L-m+4U)slx1J#EZ!Po&nVg3n4`RC6WkQsu+ca`eBY-d6CnhzZ^^iwh-9&rchQD!nYTjY2cUy&fi`U5;UkkbKckY$*H^N<fMj'
    b'&QXN37e<@6Vf5n^zC8e^vJEkcLzv=uM<^d6?p>qVqBXG{9YZw=AXtMIb?meWYcm8ViivF1KE%0OP3Z96n#tqqJUim_;C2-IK7Wj0'
    b'734<UJ{W4prdY0>m=as+{Wcd;7>pv6qvTk)0a>D&iV6ZwqQE!Df2^%Ly(T<-`S@Kxj2#H-{1!5z1!duTE+`pYMS^hzalU>SP$4oa'
    b'7$q=+rY${qJKcVHJ*1}Jz4@8)P6g&uwdFU!k^Rr@O@b;+lef)%DC~9I3bi4Tty<oUl~Fa*M?s9=*@eJS+c#@xo<`IvtatmwF#E&X'
    b'`AtQFaF6J8Os$}U>V;5_65>e7P)Bn?z?IvmlS+!EbEOO34PP-@9X~n+u6)*0fd2MNP*U3b&_>G&ywREwoc4M_m7G!x+J?!@N>Mr;'
    b'U8%Azynv0CMcm?MX!v|oc^-E>`U^qvMNk%o4<d_600H4|YsKoiVv~-avT#CED=1h}aUBwOLWkI}2$vG7ws8Kj2^^o|RV@UX_5#F3'
    b'c`;IV8Q32&a|gI*GOY|H1@?c(I1IH~F)bl_aZ3z6(~r#opzsYe5GE0`E(S3%qo^mqWEUp0qS8&<BPvA~SH-CJ8e-gN4S1Bbt$6Q?'
    b'bNH~XimspYP!b%ahH)o5d{K590x25>Cm}a+Mf`|!#)ZMhS$GvNT;wZhty0VN(a)-_pQ&&5y%~5s)PcrU=XEZSt9COBw}#w&(!q2h'
    b'bSqdZUgg5^5?Q<t>--#kP-b0GunlZ&P;Uvm^&$+ctsp|LJe=_s5=`|%kRe6Eq@7o@ql)h=t;V=Ki6;^3KYgtfJ7e4$qGAhPmuT8Y'
    b')G6%1Y{ZGT?%~DNB9fz4P#_7#iahS5jUm9OGiWXk{%k7sr-u*o%Y_e+F)dpj=e?K_?XpTSt_l&aCH5+=K!ccL<rR*RT338lmZCk!'
    b'n09{nM<w;2z80xb=l)vwRjJl4a7iu7e~XsUT0)5%)fqxR#bZi@%E_3(H|p#+R$g;h@#*tp|I1OKc53o?lEiuv!#$(kk?{je`tc`g'
    b'yY2CWnj`2?aClSOur2jR+pSOwmn}M~LdZCjuiI02Zaez)<=y8`XW9XcfWF{YN3%m@G>gCK@MFMUdqv%FCLw~U!)k5PKcV;^O`yd8'
    b'MYGNG48E$U|M?Ge`~3N=lstx-TOk)O%Ff!Z*15im!haf5pIqFPo3^A}fHA8!rglhogZhTlZVas;@Dr6^|NCp<*Xzx{&;viIL}sV2'
    b'Pn;DPF&JSX3OAJ*fr6rM0`Aiw0<b4S(wKL~+cP*?LSOHC1gNJlXTkKP(kWpThS}#a9fdywvNX)W*R6?VYY+OMA$P60-x&AgoA;Cq'
    b'Uax!Cj_Y>S!8aENEYm8GU|(0}P!7V+4UY@!Hg%%IA|*7H`DjP9>(=NWKK}GrZgz;ZzwU%pw)L1Zw?nMQ3ULZ=?rwTalhOdCgV?M7'
    b'eG(0_4VfiNu}grvg?-2PN2S?MN1@s4Gp87<*xAql=Rpa%NZ#(z2NVz!Sw}Y?{k`ByOUi#*h!mXQAbxxE#_-?!23&8~F4ncl^+%Yc'
    b'BjwtV8^e5*KF1kxlq=}C;wI^e__~M^a$h+qah3aK@;hq1E=C|HD2#wt!NPr7U$^K7C74u9bUU>1bqEn569!v(DFQVwW|*A<(+dm5'
    b'*K>GsFF4=m7Yrt+Ergnoa%)PiI(iuk94BTV5S9{6<8#ySkg*q!xSCV?Gkm)-_RCJ-e>-Tv>j+p}f`?O*owLnzBEMscGlFD7gEkV4'
    b'1eA|H&$2SguJPo6hefQvZx+wK1!s?>a0j;N#ddw`qH`{8lnt$C!CNjzbo$I;|7=(uMMxao5BDZKEw9hv(Y4?=&jns*tbl~_GPf;G'
    b'EZ8(anaD<?+;MM|CMwzqi7ueYJwX*b6<`T-_TI+0YXZOjuDI)UDw=Hj;!rgyNCHiVR8<<3>IkJJU$hB*gtum+1F7#&2W1*tF}k?B'
    b'=J4mEn(03ti<w^ceJKR)j80ZYZ)Q}DTbf^uxGYM%hZ5yH^{fjiJ7eg?K@eu;6z=>G9L8UNUGL|Gupla&x_+|W`!*=GcFM2C(%Xpc'
    b'Xvixu(}HOaozSUsgJ-iQxI?&gB=2->5Gmh6K9i}GsziVhcBbRfra-B_K^D+zv!K%FaLCa~7A}rT<7W7qllb1J;C1UK3M2EV2v=Sd'
    b'5_gpM342;@#*!k2K4fi~+?+jGEN3yI7A;~erQRI>59`yXc4>4iv35ST*j*{dthAD`K>$QlP`Q#iovEPV(c}!gdHJp-P_WL2XH&m9'
    b'`b}4YR!0jvTki!9m4%ZSihyqtD5cvQ7ZU}eSb6!(+jm6rQEZxu8$vGa<_ykQ>QHbJ>Ta=_sc+uVm^b5qK1c)Stq-iAD5$)})44JT'
    b'ek`Gfpm=d>#19yOKGpDDO^cnDl!|u?#hxLpg&WACEz+khLN<NHJSFF44v|_ejMK;%2O>RmeIn0B2p6Mq6w(e{`-=WgOM~qaHWu@w'
    b'@s?H+*NpNd!uFzJg`2cGtkBBpj;p<UCvfQLz21APuEu-2mS9qlBV58W!NA@~>4~m0x;6wEm9VO-38>Oy6_C<tO*ckA>h{hi!laOr'
    b'kT)`E@RBsdin<G2`h}5|sH4t;vJ*z?D3mm-siE-g@OiG`o`JtLez>{`aIc=Q-c~Bo`c%a8u*TB_!uCo+3O-y2B%GW}5hovwo6|Ot'
    b'Be*`9m(~w|86Q5LL5hkziaow*=~J>6`#s~Q74>&hvs+eiiBeLIjjI5LqRg#5pp+5*|MuRsxs4-B6aFh`_Xm+ZB$aiqQU@bemgQ~l'
    b'*p@<;XJSKEAo40<1p*uZw8ZJx|NVWQ%&I~aPz92*-M2ySjx3?7@_H`MIeGFNd4~*q)y4{b?L!3z$_UXtnhRI(f+w$*W})s^%HV3+'
    b'|2(1q8l<~22Ny>EE(@<A!;Fr^;qG_qEzAaP|3j=Po@XXi#b93sykwc<RW8t{g&4}|u{2CVK_LVv3;dwdlDFh}AM{=$cqwnzV_02-'
    b's3pCDu41UH%e)a#@+6zNd_)1O95{@Z{c{V1t{7ODYL<MjvNDeEHGm&NK-_=M7G|*cwFLTM;or#DMuZIvSmdw6FsY@BnUsLh)rMJ8'
    b'Sf&p@hay9;pYKuydqpP(YhP5@*MgZ}WvO6(E9PgGS;~6TlBwyE3VKo~$I3xi7j08$1}5e$31W&nIP;$MCQQytT9E?Jr7q!RP625v'
    b'Xpdw<^KKuW<X94*63xT3yfDnduXFFe9MKP*ViN<`|4UdoknW|^($HHDtB`f@csU-N2)msJbull7C%hAz3BhWJLPcejq~ksIs!Z%>'
    b'K#7^)y2_y869Gibil|Dl+z+oVGS)&wk+w1cG8Mw=*s=aC)SzL4FEi3@ufW4VZt{v(et4Z(7fI$Ec8%wS%wQ%m78rs3UufoAiF4qQ'
    b'v~cu8xX4Btf^P(O_G&2XQ+Ap#xm8sqg^XB4q5?maRaHi4pI!-8c*eq7qHY+RvH$>#=>lVfZhW}UK@!SYk0D8wq=bS22k-`&0;HiK'
    b'!eRf2lBaK}VuIAHgpmb+=Y8!$gUC{Su*ZP{2?GV<(u#%~7@7egaV&u_L{UP+%8HfQ;)32k$QMh$7}GFWup2ABfTVUE{+$7IGjF|='
    b'D|uxh(Fe>6o^@c8B~*oQGJ(y&#O4{)u1qOoGpnG~m`On!1Et0!N7w|d=@dG!00X57_R}ocjD=uWmnSQjLm`1UX9fe7mE=iGs#s6a'
    b'NSWu<DzLUxq6-*cAnrV??%8>r<Z@qr_(%^{he7MHc4Y#&&a_ub@|qEVzG5tyv!E^}6re_9uyq7O7bbaju={TA{Q+Q8#vm$7Pa0jA'
    b'Jj!6&NElbCjT3<R2y_N~3kyFjwAN9@`^l^u1FLvUgb(!m<23^)_n8||6^4PWQdlfGtEN+jLqt_6h>_qT1-`AM0lh)pgBX*FwIX0o'
    b'ro0h&xc`A<{{tz$SaveuC08c!iReaR7zTuCUR7Btb6!VqJpIcfR#U~3qGD+X2nm@Srn@$~|I7A>Z-4U@I9LN*I>ms4G8a-x<&1J#'
    b'6%1`<s^lz!WeWgri-^Ts9R@;90RonH51^aee;_|KgBe(_R$^~W!RytjvM`!m%F6OUx3H>!;V@mm%ETC_VgEqUiY#{VVG3xn`Hvqn'
    b'l>qEMBe&N69;bpG%Mc%Id732<36O^XI+0|aQIRRw^qB+Za1qo1q}83>`&|0pF7+^$)+KAZ<VM6PAUpUxg5cE|n2~`W^gP7?&<0a2'
    b'qr$idxCM3|#~}&7#hu;n(;IJwIi0~!OB~Z8C0WT*i)9wa8Ym?tS_N7bmYJT@ob_|loHcO(CE_eT+#?;DZPwH=l4pQNp<s{+fCgwb'
    b'Q88~&716Q>Tfwl595gAjv;sbgBw_^+79ux<ICqfzPO|!dUiZa)647JMl6owWoHNEK26#}6zo~dj4mgtHT|}nP!ZOa<7GQ;#DMNOW'
    b'aPN&_FID}3f7L>VS|&Xp7x}x(aV{%}Tw|E<fpxRuETNwFiNFD#SVj$YESMom?$f<bD>$I&EfYkQEdN%pd^NXS0i-fTj!m_zDq;*M'
    b'KCA%*9&DQg8m4pwN1Gnzx4o3~1IVVJM~qZnNC`~?R!X4DOa>H(?S*Jz;RFS~PoZIWB}zi-8=z&#22<YIeUpoR|753PWhw1aR!0VK'
    b'Vm>%@A2Bsa!m_hP!gDn&H*A!uD6sc}p2JuHVBx`?J?|u+AIKZVEDuG=Or|kpZN@-o7C~lNY|NaoH_Yl)TA)eBeUw!Ul4BWC@M9I-'
    b'IRKw@eqX>QOiY&)jzC!Cyygjc3$qMTrpR+}TFx|muw{9E?V$geLymckGTt7@@9g#<v|#w8W%{`c7>cqM22%wAt5|N9#dkq)vA@LT'
    b'3zaY%t%E(CNM)lKX3O2ZGs1LSzN->OXOuB-D@LL+rVq&IG>08jF*Q%bv}GxH0VV{X4GekS5-wOm5@Pc1Mein=-`{d4!Cz<<5)~Rd'
    b'ieY*}x+f;(3d0bMU=6}D<lHMT8BC>|cNwhVD0F;h?|W(8_fL@urt(b~s3Cot#v*Z55kum}4oZ(<Z#j)sKwcqvi-=C!g2yM0HOq^G'
    b'L)cHCJ|t+fh#3JB7P}S&>yiLaiAVy_`4UgDDuDnCshFt}APW{06A0#5x6-(S{qN^Y--p()U|6pTqMa8z3z!vvwNmP&VnKn-#QvZH'
    b'j~yO5mW@;xaiI)L^2x)Jwx1+@#8V<*HNXI^a?0+Q4nxP1!Qe}vX<!Q*Q4BFXAOI&eDlb_cPWyOF0O0cO5ezfFV^Jzb$WVr$Ggj5p'
    b'7z2HWE`uGzoVGFgRy;O@@Z-(aqy*S>S!@b%cfY;V==%cKrlt0$l7KRX#i`N)*g}>JEG;0`(FsHh>}8M$b9j`%)f$#pQGpSay1V}-'
    b'Bl`Flz-}bH5)+H#IA>PrLeS8F$;jCo#roe7b3B7MWM&}lf%YuxekCG4Ed2H|qVF$34&xQJgN8WA4gg<khTDpaUi&Dv6&40!C}C<+'
    b'zcwP}1qBG<BxmKh!`<(tK;L)M#Dr5ZFf%wlsdCIS=drecg=Z;-BG?w(`UG7UOc#*y!fPyxoS9b4;r<!U`lXL5f5xD4RuCH~kZTCu'
    b'1&!+h6lru;0l30$G@__74Wn1^Vu<qB4ZxXnY`csnxLmB_?h$z6A2IJDfQE!OHcKpm;>Dnd8C+mO$k^!u#tp+7vn)>-bRNZ!(oQnt'
    b'k!10(bi_M%N6Phm9pr>hFa@+7se<*(jpY#`L=jXI-~i8#Jmw?d%M`F*R<VXv4g)W*;sc|2V6JtWGi_DI1c@?Y`D#-^+bfe|=M&y9'
    b'E*OKJVVxZ0LxR=7s^lsL67<<s?jDJcsu_&wqJxRS12FQeVse8Lx<(tVQ^j2Tur8_?IA2#X1=NnQD-c%|j6DDXSP3J0F_hYT;LI?A'
    b'erHUBw7i-N2@80~kme+FkhhB0XpM!8$XsG7*hH|d3YO2%CKg39-t}ls^L@mx6WFwAML(&jeDaZuT%e$i(R->zDKg18Bj*6V$^-~m'
    b'uz)tW0qdg2$1s>qe4v(klEyhxUc_8rz^<}H#{g$Jb9jQ(SOC>k00&SJ-~ug)SYUS3$seil{&(_-4^%^rn5Wl)wM^xm35l#KmTzQE'
    b'8VFh}c$V-$UxN-HdlSaj2$<K>!7z;u_B@b4e89!RQbNJY6v6DVtj24h1sKsEQ97x-;*}o_9ho`+Fw2B|QEsqgSzeA0pqn{-pV<g1'
    b'A@+=pAmE~c=}Ey~K%oYc2T_-dZ%s?bDs~lX+AzHVU91j5(;k?&$DFUcu`v)h$6#2YA|Spr#)`snV(dY}8+ArTysrS52SZlTy-D;P'
    b'Gn<vj(=@VUVVk3g%J)@Hn(=;=0NtiZ%Hp;WC@e(GR`fAMri2R0_;(nfKst0|(aDquj&->IHZ%9#ahoty4R4KLLo3!=#$Lvy1^}Xp'
    b'1Hi<8ON<EMQVKvom!a#DVb!TjjWl=l4<-+AcVNe<*Xb^Hd6ks85)d|Vj{n1U!pdTLJY9&AN;ZQf57|~S`y^wgV2P)Ba!21gxzYEh'
    b'UN9{`mOT~;7|wWBVxbuxiX;{9GE|{v0WTMnMVc}TYl&eMRcyv|?RZl3{lhTJ>yiLA^dahuAway%<ZJ4J;+!MWiFrH;;h&p=nOBH;'
    b'nEMo?8Qc4i5&WCZjgfst4>gihHmz8<D`kM1E>*-^v<gxc_P*e?1XdU;<3vNQfy*G~6DBT$6__3D`EVX~*bBTEk<uURnBp~)gqu0*'
    b'r~u>x)Hv)1mH^0_&QzoE59obZys<59da&!mN!VdKFv+n5u9eLH>oUldDq;O~Cc1~h%PoVIY{^S(5T?Z3l6S~>dNg(tf3FPe=tgS`'
    b'b50gznyA!b2NW|lWx1*fp0w*2Mim&mV3p?t;D$GAlaiGu3tb%Sdf>3REHb9mHLOk?vm&!)BFc#2$2{XN7z9z|1r1ylnHQQK2K+-x'
    b'Ue6istudZMojyi=yng+10K>DYsil9$@M>^k09+*Hm80jLx5`V9w)N#WBw0`7ObeHnDZ^9pd-nZ<{Mnk}kSE6*H8Rz(-W-eNRJ_Lz'
    b'sG`8Li4%F|d|hn-Yu4Cwr39R}IczGxNv^@+5xn@g@CoNVY&dXEpknG2;AueEloy#3V}1HCn9*Q31)YOEPZG@lIj9-zwKL>>ptwqn'
    b'ITHHm-go7R5RP?a%7O{@SgIcAT`B{Bz#QksRZMA;J619TfJ~)^4okG6TQLQ43tgI}UOx_Ltk3IfpyzcO>+|-`&y{IHP9w&##LVqd'
    b'z#7RJ#>G2<F^h@u>Mtub0iIyKMoRE{4$%cR7Fe4s&BnWIQ+G4h`v!|_&AF0mI|qR1<Tht2o65$y0RjfoRy=r3e1`v&$#x8VrMYEx'
    b'Z>GzIEkTr2FaaX(rZqV){Q&gre08%Ziu0S<`BE{tPzW#TrgD!NDr)mQml;&F@tz-@=K@k1y=%kNZ82-ms5DAt#5?(#C$kPata{T$'
    b'Z|G;Uyk5?i?{3dGFwN)fvc`E{W|52%rdrbqG|OlJ%{)3e^L_ziX3XZIC@z4;3V>vmIRZ;F4BYhkf#^Ed%bV-v;(YyIHxk=;?JY7t'
    b'yYrAO{=CUe(VeW;V2ZS)V;_5)(ZjD?s$c>*2Z_ntQW#g^E1m;B2n-qe3N~WN60vD_5c3;#-sJ2&ud_~{w^^r~Y169{%aZz6MJm>e'
    b'!vPU%Q@Y3jVT;0%ynqQ{ozfwzS*NxH2B#ZF*wG%l38tIQ94qfcEC9!hE3txYovSDT6k(hMGxw&f6T-SMSX9UmZ2>w;$}khTsLL%O'
    b'm-BhJEqdPMaz1a9>$ThhOBtkE@nR^*G=f>f`b!SxizzgC72E1V8Cc#DR$k;!?pezdYSA?JbbOah8mjX)SMqt2w)ydlmxZp{#DY!l'
    b'6)PPH2DI4vl7z0ZvSd{Xh6VC|D6eZ<VzG*uUSh#OBwx2A!e|cn-rN!%>s_+2bVhG(n!A+g^3ahH6(mLq9tN`%EP5<Bo}8{#NMgad'
    b'T6v^)Bt_dhZ)TkPq{!#nq{w3fh@sJ$>6VKM%Zi89<Vi@tyikfI;Zqh8Wj&UX{!grlEdX>S&z578j}E}6LmunZ@zMo^Vr&5+VhxE1'
    b'yblvH0pbEx$)d8XNeP>kt}bZ&g0-;;LW>-$F9v&EF0ap<M9AkpZO2&m5b{<V4K$qrKVtTk6LFcBIt2bga>NM+$S6@>8RoG9^k&Hr'
    b'O&vpUk9Y4crksZq$fLb0NXb|@7gJb(jw@T1lE*late`M7>wq##9n^xLrql$6qF@jj=w*=J_3G-JUYqlfC1b2>Kme7{bt1rNz*Zn5'
    b'7J`Za0TTMp%GmH4J%i3z@F>f3=4n(3ovc{+c(Ch6oYZNL$NDa#3hJ$Z00+KTCdzpl${cf$8UWMU`lAvIP{xF`bX_o=rsWkKUKcvp'
    b'w@-N7ik4AsGa0lnI)gz6SRkTYM6yVkm>wDt5ESr_&w#sPo@HULd0x+`IMxFloW4(We7=$I?pXSWQEf62OeDn0Mlf8<2<VDwOd01U'
    b'74HSY<YX}>o|Q8OE)!6bF`;lZ)OV9w_`FGSe8(8l!j`a-5^MvAObA1Nw)0k#5;Sac4KTzc9uSEz?F#msVl)-YE12lu7!GnAqcx+H'
    b'sVQM>Kqb?C2@Jp@JlYu6cn5RSpDbwz#1Zd1kmgbeX$v7Z)N`G{_PmqWc&vM?lbHEPp%9^15+*l~sEwHmF=w!yBH9)pxg1tBgUDbN'
    b'v4Xp)05eo|sQZ3O<FOIw6h=I+TUAvWr?QYmp&(Y7VXPE%A!e+KNu-iyJ{3N_c#sINcoeS-9vZ<mH^x}+g()G=3lMvpGb2CHMCxK!'
    b'sXXH4udIYXX0WsHP9(@$p0Z?CVO)4aA6))AyWF|IdOs@jBErH1hP08e-?J)WDbOf|0T2nRB33zJ&abq<^FjkMiVVP<5rY|Q{^ZaA'
    b'LIUISCV}zT5R8Q8kR=l(VG&q#N&5@Yu=W$EJ3#&zQqM0F_`gyKlV2xU3>=>emFS@%Fm>_yHg)kR@1tSuY|eYe*k+!Z3zq0)j1Hu%'
    b'U_oxBnORyVu+B=Dqe)8ZSHsrMY&z8SHdFAqPgFI!@(CSuDc!)bWNHIC#<9`DrbPn78+)Revlr8jSr?m^fHed_Rz!5HxS_tcX>iX&'
    b'8r)HtFJf&alaE4$nkr8iQXNMw_b$Vfr6+}C*;>mA!wOK@WGv*H0oO5RXsGi#!{|Aa@SHR2>!`A$OWLI=OEt3yF7UV(1+QMwZI-A?'
    b'xvb>PW9w5?XsnSn5JC=i3S@44sPk(EwLfmMzMi*PUt58rWDY%7B&A<nRlpRgShk84y;ROp<WUYX6aM@%hxo}^<FNqHi)5zLLw(l?'
    b'Ue9TAjxs!^#`|qB6QDaHB?=V)O;qx7CvY8gJ46s9L&n2uSy3y-APW{*>cYBf?;k(ElGm*jN|E<2oK~KPj8I(ziA6@!3ag$f-tJ{e'
    b'10YD64MmXx%SWs@VOUw5{!(WAW$7F!9K~BN-92wa3o~n+*J(8O?FZ%tE%9;4g$~hSV!)}&^6D0|gbBb3-mi=$45bu`)~gjd0#pJO'
    b'FZ&(Rb8*gOc<1w_mh;(v@0q*GD!_q^C_PGT$wgz9T%WB{`E!9nl_r5wgHFNZrPE+}YlLJnsJt5MkD10sJFRSz>Wr1}m~YZ$ST$OM'
    b'xnWpkB7x#c-su)mr7W*58g!Z$ahx;$LHDFr(`netCYcNE?!CQ)bRYwllJ(aB_ysj1fS@aw>#P8=;tlPHXEbkxRI%e-9TFJNK8L32'
    b'^B0}_{6*(X;MI!f(n$f%$PzG$D`|5<Y}z<Zk_7S#n6WS>0{?{KwUCSzFl#KT42Cxh)=pQ<m38iOWu4c#vRaX#QwrP2Na!I(*n1aT'
    b'$wc=#6p^S>okmc>z<Z!z%TOPBcVmV1PLryug+pGdbH8+L(!~801m??G-BB|h9EcC<G-aec=)Yv@fsB`|4OC6U8(z#52OGYGEv#ZF'
    b'>Yja7_sD#ev(;f9<mnJ&Y?<(>O4AZ_12!-$pa2^lh$r=BuuCiHiv#A7P_me8O57jEW~bLgoHuDQ56#tNLL{kCOaq4AS$9Q3oX3!?'
    b'M!6hdr-ZEs(Zf(dx<dtPf5O0ofMmhZPOl)wHEbz!&XRcx5^9$hd}3t7{EEz|=W9V&qS;&}&>)Ucw@`8#awh_6EppgUy!Q<=LICI1'
    b'q_SBq=Z$}Dv@+dLS|f<;Jhm|2fFzjDyWrJ<j4>GC1s*~GwgI<6nZU>_d8J7)t&p!f3@KlIUiZ@hUz7xnhN?2UNP$vP%_~fXm6r@)'
    b'MFA5h&FM~|uS7TqK96akUi>FjQ)zo}B(0;7d6gCmz>IAT0xUBKMR*@>l>@UY2P*}9#00(teHUB^XjGLl{0k;FgGP9<wq(B#>UC(^'
    b'nM-JsL$ewM<1n=vK;0CExp<lDf>ae%ur_kR$P^gRv@Rfl6V@;(d(#fpItTMLw>`HhCsSUOMz2ib2QC7<h$90-5)-eYn95$Jyni8}'
    b'*#NC24-r|-QN>XDrQGj#ts#Y$^KLF?$J)M$judqjWj9Ypcs0v1d4`B0W5`;Wh*+=_e3NO*f^WRv&?oIs<}dg-r@_ZL?f5vGikR)}'
    b'4CDDSa3>D{m;#7*(pV=o=RQK;IbPtm5^x<tDrNQXQbZUZ_&0B&$h%!*X7lAo^t9d9f!(yO0_I@6M9D~rGGbA3=8z4wxl+N)3M8@;'
    b'Bx{{3Xe?(8C`o8Qmk0VCVBS3Cb)>S$eTm_McfEYwqby=te#N3cz}(swJq2FK1T*&-Q!?DHOq-DHrnl+4UhcO@0aU`MrFoGsE=2-*'
    b'vKpb!r|x7DVZV5bK6A{82pob5VL>y?EzWeW@sS#d`{~0We+q~HD=Nop4<Hp4a%eNdhm}IIPz~=f!^lrrx{uhzIKUs)xv_4qR|tAv'
    b'FzEmbIt{g)GTx{v83jS#S;1S2KwO4pB8yak39)RIt{9pMc`u;W%gk39E4qEYvkP7wZiQX9SX2Z>0a@>*Z4x;~JTOUj#*>7~Wfnj|'
    b'Rt11VLIQ=w3K3W`Pe5v#DD%)sui)m8Oo7p#@&+<<=2W~EVG0(8ilJXXjv2TMyB8Zj3IY1aDh0&FJE4F`a=fqIny&z8Jo<@ZC<;qp'
    b'2s6RJ9LX5d2nvH(QPTO7PmoLrv()fRHq)@5f!%x3GeC2nh_R8Nhc*pR$}!_=X$6bu+6c&4RnjqJHjb*IVzFNXu`V%lUcs+e>`M8>'
    b't+I7>hpt!lO3r*ob>iqCP1ZyGLhI4tBcL=up$fABg}~wllx4soVHT(aaL(o+P-4xflBtX#;V_CMxmUlt>&zR=DZRIl(aih`6u>J3'
    b'jHLhuQLNX=a)U_>!43S7G10q{ECP^1SypAg)4lxMgY$&;;}urGN|ykCM?wR~X@fsg7$hJtSYj1D&oR>vFm5%DZAQXVI?AHEy4;<j'
    b'$~0P!6PByj2@Eb>0CdOxx@QI10?ExQZm_SaxblhFl`{1E!g^ty%wB&X&8ko9xSs>OkaUsDL|VtFixLzmYznK9hxP!s^q<9fQEDHP'
    b'k~<!<V@|M&Y@SQ)?(Au3Ia3isT$CP`O8SOm#^MjW91K!{s3t@=bmtT_i3-+dfOdr5;JtNI4s;r@^FE}(#}Js1HfR^7s<f<m2W*8&'
    b'^0ZV+v}l=MI_8~S2x}4hoSHEIF#En{AMR>U^TnBD39XEUR7s^g<A%i{f#C%6>&JjFahm4}(6w;P+YCg&Gh0!X?fvI%uZh@Zv)|vt'
    b'$nl~n0C1@>CCF<u?nK6Xy#A6L?{_=UrYr!KA$HP?oeK@PXuuKqy?Ps(CNsUkQWn;yU>24ocw)|@1VF<sV%E&74~w;eb;24}u$5p2'
    b'Vk=|WI$wJo*OjRDH<Cfhth$u~krqrA!JMXL<ul2!W&rVNEMrWQb(=vp4CZ!4%Ai>YeS43-hNg(6)2s~wf&~`E?nuLOf-!5l^K2i+'
    b'v$MQ-3Y!JHmlzj8X_Tz>LIWil==M;mVVJEYlhB(O_!3qWFFinrF<grGy$UAxE`d0iD?TyI%x<7Ib3BkluGwC9fQhq^J9SXmSCT=s'
    b'EM>(i_Ke7ZCahqKmj#9jkQ6JX@PuKl7$umOK3#&PAcXpghq}92tymnV&R{$M)RL-Xns7D&y0MTrG2>)h33EmlrHE4%(OC`Xq!R~R'
    b'1L$ZHRv&gHZRdebM@t;=q!sW%R<Q-dORP<>duha@nJSK1YcJ<%v`>nld3FZFoUhQRz;>ti=xfA|fz|~z016P)GwGyu5HXDM%>3~q'
    b'X^1r*U|%RYDP!hkVm)V3C3>LSPO1BS<e@4@k2}ba?i3hDQd!Ig+{uuB){cfShg}6Q0;!!sxWN<=EZ$ZK)dV%R-Gx$5dg?8iPI05W'
    b'j3B8XK$Qg-7gP(dhXHRLC@^7SzKVWFkzuu=q+=aPOtW+aU|byS?i&jic~8Jr>uE-Tl5eprv4D{YOjcN5N;S`8*x^v(DgJcO1{o78'
    b'L{#rEfc*hTkHyz@+3}w(3s0=DZuswzDq;yUN+wGfYv{ogOyQs){1X5rS%CvVKPgG5bgaw+9nY&_*t|H3?(B09y`&lMF)`0aPCUZm'
    b'z*168C`KSez}z-YGJs;JjD%h~-m%0m3yBFUx!+-%wD}-H)M>=K_z7!DCcf&5%hIg$p^1=^5u+4%a1_~$mtQ3B_5$(K&k&iS#|TZ@'
    b'ex`=)Ac=~VJY=Mq0uPoR{d$1ZQ6gDk$r2N$3FE#jOPj+wGQ9N`IhNIvsg}Dv^i7t!JV6bHJ0*Zw=#N4AfDF7c0F;eIME|9~stTi1'
    b'&>`ZA+<`uUMsouj4(J~mNag83r^_qFnC&S8n18lo9rHq<=GCCM1fdAl^bx7Qn}Bu9Q>Oo>6a~xkawT8~krR`fXw8(|$w0@DC=@JB'
    b'fsB!kSr`a*xe#R`V%nGher04KWn%2Gtt<;i!DwS)WL94Wib`Na!IlRJyS_r|cif~McPqPozt=C1F=I=2J7h@gu^US(Gns5=Gv3Gp'
    b'T+>-<3d(E&Fq|Ynq>jhZ48^#s-;is3w^xJq$&Y{&CU)UY6fb6{{6}P63^Gl#D9fS!cp2UCRvZ(MvowJccE8u!5qGD9?(x&>>*<tN'
    b'2)^_$*6H@X4zK-ibL~st`Dnz8&8Ox*8U2*jGU2AJpifP%qXc*z<EyGjQ;`BcFcqM1ti4>Z{8V8=eIsGAUol)C9XXw1)ITojd;R0X'
    b'|4ZYx>BLlSXJJ7$ta(sKSO(7G4=4+mt*|?&VwktcG3Tdc`~>TA0<|+ai_Boy#(lrd&MbC_{Bb}D=d*>epSse@fkQJ1WXyco5F`;('
    b'dVl~ESkRDL1#|DmbjKK|HIQS>$|Q!D^>|@X9T>sBW&K$CAX{tB_m^wl%PX~ABABtc!D2AeJkPgE6KNLG^2ZAq6a<8+qr)Z^fTT=^'
    b'Z-8oYKvxA+*f*OVIKbvc@iTd4S8{ZO=o2c<V(Wm(VUM!Tx2mcbc(`PlLLa1SN>(n2d{$1!qQe=?OQN7C`3*)mIyM%`be2&Xk&?V%'
    b'S*0=0$3Z?4re$SHdPE>dlwzW3DP#_{UkWBohwc>*8(YVjw;e(e<-BcPu}($`=w%Xs4`VDZ`d9Rz<Tlq8fPY1s5uh9bJz>%T=~7+*'
    b'de{(xE;*kq*B7@}^X(`o$AFuR%^>G^54z;d0H+d4jY<Ia#4Z6wt(fc|0s`BosI3zK1Y6qTVWYU$@nC0(ev>1@`wngg5q6}JWXd1N'
    b'QV5+`$e5RLQkUf#mWjjC2nUXX5CU#y78(eQiq)#EN1oW)hYe#yAi*eMo(;va;k-DLrAf%8o&yBNkmnW5*;qgYvgof<aV`r1@~&VZ'
    b'^R)V5gBUp@>xds8Z@|3oMW$V3E08JgZz+#0RKcrTGE&SokL62zii3*zBD7#UwR-4q+Ja@%kCu@+>z(mv)&T|<ixknT1~g)Z^omI`'
    b'SU68Ikx7&(U0EiX%UF^o<%YqkmQfo9bKmiNe7~IA^D7IHW6rN;^;v26^b7(d<!Pac7;6+eSar;`=NO8CLAivfOt2<~)$g!Fu<c<+'
    b'7mQG(C;Px~27O$_3ajPM*7)mhue^irS+Ik5WMCtkEienq>@m!M8CRH3Ev7r1Vb_NFZXf`1>kNz6fS^s4WfhD7m_}_?%wIP?mf66k'
    b'gX6QXxE0f@Cn=UhU@)34L6|Cz+4gf-b`|hV0kjDi3K_1A^Q8ccE*W_C;PLHcD|p806Z5&>*uf!2v@QV+jAk-2CijJ1YDx7*CfG#B'
    b'djtyhBQMfNF-*$>#wAZ3;@p5TA3Vf^=hilXbY!ZQs3>7f;{V4k5(!jRMn4BQRGNy_FVZqov5(hb6{CVR5lZ~~?$HFN<NEQ%yV>SF'
    b'%pzYg-C<>b^2W4F$xNrRQ~+tv?AE}>)iAp990oxN9tAFCuvkTn2a}L@&_IteO=ZmDht>T@#gqN%^iHt_yE<o`K~=D5x`Bw6pn0b8'
    b'VKsq@x0EUsGmn#lprY#urZ?S133Oz8)BQdJ8WH0WPq0kpD6A?bH507Sgwfavs1i^JD4oKJNsN_Xs^rKgRkk+H7%qPQ0r+>O(?RSZ'
    b'>Hl`JlIWVbL?nxY$CXc~pXvl~8;T~fn&nGG##~Pk4@+S_(rnMl2ajT0w_>{BUCr8YWd;+D<!7NgDzFZgAjW<%a^L1qs)glQW(KXs'
    b'5+5p!?LqTucqDhL5<t`>&QhzDW$ALqEZwlNqk>oP3m8?ZVjecbBQ_04s2KZY(vr6-g%<k$Ljt)ra`Ba&Te-F`z1Mq4=yb3vZx_(%'
    b'%W8X~%30vK<c$hgeYvCaOQhIXRs({Vhryav04$~B<)Jc-#jhIQ_KbgYd^`xMB4{?rw3jeD5)F_K96((Hac(UHB3-RuskngYE~Ry>'
    b'XD69$s>*-O_+ABvdUN@Dbd0QjU|7He;{eikx^%!SfWNtOxn_=HNYm1?`Y-RBMYLpiNdxfP!LqiWHAb)dzFsZ=+b*7Qc=uUMNCZGC'
    b'>GL6JYk?7<;3}O0i5GDhK~7bMrLeL}S{}cbU>l=Zk<Y0tcI9s}(4enJ$Cxp}sAHY?%vmN~Cr(b7Wf(A-_t-P0W0V?`NE64q+z_!G'
    b'wv8(bYX1B&hMV5j_)(6I51KE>uJO`C!2>A^;g`C+V4xVmbj<WO0y>D<#r#1zZ|?wZ!yJXNS3GEZEMK)vls-BpAQzLzFus%(8c4bV'
    b'RYi;puqAf3r0Hj%9}R{M%O*AcQhEwuowJsojvh3o@0QGHJ31EFp+yPma+X&HasiDO0T@G7xss8CLS+y%8B6}DMCPpgD{_YU8=np<'
    b'eb885d|Yt97&ydy)&B=-a$#?O{APG$GD|db3dVWn93*g(!4A(Uc$pBZ#I70<ixP5I^7=<wvbF;Rw6S@mtK#7!^JL}8sm&rVx^4u0'
    b'%ml+Cm{<=BRAqSKkhfYi&*Y%wU765H3*u+0Yt}@t5v&ma)(4KRlQQ#VeKg86591UDv&Ya@F9Zu!GLsHAjF)0F4O7vk0N5Hl0QJRc'
    b'x=HHO2{ZUn3C(;HpEEkYgwOr))HpXngGR7+oG$2AgAuD0>y#>{(d6H#=d;X3w3*VFh0)7QNRtVjWo_NOhmEUA0|%ohq})9qZ&TQb'
    b'5KKj7WG;#bcq}Sl(n1Y5KrjX3OCm>RHL~R0eUbZUcWB{A$LZ&cZfkUm4hzE6!g7dUTt|6qWkuSGE2aTW3f`!QE8d)SJdp*w&k~<F'
    b's)E9R<sp;mvxn7O!sp0FT+Yk}=VI8n1@L_iffWnpvrpoP<uw>j4X{GzUcw9ssRE=<REfpSGN$PLEH>CCy??4d)YV|F_Kn@`Aeo&L'
    b'@>7(+mMWKtOH~Dd=1qaJVrqg?nnW^uNb#sQt4i3DlJ#q<)Rhm=QFr<Vs@yx@Ei)(?$;t>!dI`#h9^!3zfNds?hmuMX=9T5OIa4wR'
    b'3=16VyM{6tJ3;%qma&iTDM@O3Metg*U^y!X)K;ZAR?<M)vaBpjG*|={P*3s99EJo`e3oSvN(;sm4AAtm27Ap2rRB{!M8N;f;XC&p'
    b')j|6^WddYoLxniAOid~bR1qlL6*`xI5*5r&dZ)mYOl=H#R<cqkxB%#>5_gZNi4|GfE4g5S>c$d(+#2FLUfw1|#t3G0bWwyZAsgto'
    b'V~PacegH{jhW?YtfzX{YP-3~#0GI_c)j%NUpEI(*PjvrhjPc-}YRTlr*i{i(z%DFUUN9pP0Co&Gsae&`Un#Rfl7kZ%jyg$lXotcn'
    b'`B|g-$8{|n819%&UCTS*B3&ef4+bmfSpcdQz;gnUmih9T))$~7V%&+;wCfFwu{egAJ?sk|h)o?itG0Q;NV`nZ@fufDNqLo5QYK7U'
    b'UHDTxh+~G~h$v5CPRF`XmS(AyMK$2(48fBS4E5#Yv7QT{`G`}rrI5_yOl{5kpB2+DFc(xJ(>yEa)__T(GG^N?G1xdZ71Zg0o;mN4'
    b'UL})UB!Z;?V&)TLf%2Tys0-lw!c-c3!(2zqAIA(|EC{FQZDD#Q(9C|XVR=JM__2Th#!(q&5V4j-7Ksu@Re=S{B*PqS!4%>=K}(H{'
    b'ct4PqgD!aBlw_qF>$D9k8R@s;1>+)NxulF~3t3^ANm^r;7}8Kbu&z9FLh#EtQwG2Zpw8DAN|SN`N&2{w&$zZjcY&^0YE8u~@yc7@'
    b'8FoBo>OclrDu`9=cEwz;6$=w55D`#dEENvAyx&N+R~>2r+SY}ySXB=uCHA)jcqoBUGazbJ0LVyhg_y+g=*n7{MJ3QrmO*2i)JN~;'
    b'Bi%pnl1Bjuz(k3RI8S*JFF|#XK8j^`MCqejHB8&6$}^oXP=iS#AXtTjl1%KuQMC6iI(O5ygn;SVNEjG3N>l|e(a=z2_-n+IyVNBR'
    b'a+>1MmtSNBE+PgV{nBC_?Rn=8h6Bil(urAHR>4k+EC3Oc*(vGJHFzANH;x1&!*dm7Ih|S#oiU}l7Uft!bx6W4#jWfvor%1TM@$*d'
    b'Q94%ljd(W)oSey=5+(A7j?S@U0W78{Vy@bP;YKpe?-)Q6__MxUY~EW2;Bi2(OZHf=G^r}BP)rtFFiBs|8oLZH$fZkiK-ZM9ewem_'
    b'>}C2|2kRW5wqPcuq`G4uhXa9P-sv^qV!)I<Glr;`#UOYb%&0b~vnXML6T$3)EH5c4;Qcb8AP{+Uug-^~f#OnNE>Xes+fbqgLNw1='
    b'ZdnPDTSn4>{-uO9!6Hkh;?;(Vg{G)|Q{_gwZg$)*ex9wC3tBP*SHwWfFzJoTqr~NfOJ!_|LRDFmYY1CdHIS$&lMT@!>|lcBFymRj'
    b'Cgc55Inp;k<lM>+K8kdkDSE3>h-eK%jSCnpOyvWi&cFyrat)y)gw!_8rO?bsWf>Alw;mJU2(1z^(rX>tHXP@vQr>%vSuGD{8a6eC'
    b'QO*i+sb#{oh=qQ@xrVn(Du*3OQ^@{=8Of}LrWxsTKVX)zeQP@f>Uh76kA&?K0SQBPRIJ_y+#p%SInpeEk@6M|Qx6-)8>NMgSX>-n'
    b'GzZjT$mxOJhi{i`uOwwfQ8J2Du}Wvetcb!Wn9~t+_yAf0$(IHKR!OF-&C?X%D3co2Hz18lNBh0|wg)TKFkr2yvLa`tM8oWlz`q8d'
    b'g;~2Y!wkfh0SJasoXlz!G1xIFDpAB^UH1dBn>g?-H(4fqG(3IdZF&&5Fd}Cz!HCHzU`@fat6T+ughg<yFCDRjD8rm`H!4r>3du&}'
    b'ELKwp&`=331v^*FkO(Q3uxw^gu#9yCD@0-m1Vc!%0tq1+c77;E&UZT$eA~GpVH6X*I~ipx{z+V@l2r3X0Ru)MtSc#?HFE&Ml6aZ<'
    b'nV7{zG3oyp8wHqfvoLew66@v!-`j{u2J;JDSSC(aB~83aL_lGMi8YM8xFFb68S9p0F_S4fpzu6#U~!<)9tJ&(@#CrxOuxvS3l-B&'
    b'f`p4y6_K$ygU)SUvYH3rzYmJcm^PYad?eG5;MJX;nrpIqw-cBNm{pZnJrU^9mP}aeRKi=U25P1(Q^7PRFlwQG63OV-LNUc_5<wS$'
    b'Vt)B)F@5&!k6%u|eevw+x6{`zUVJ<K{^@tmf0$fOPIy*ert2k(?M-{>62buG_4WLAy0CJkZl@ntGirz>Ly_f1zYnk6A3YAfzkf@)'
    b'e(h#9H&Y*v{Ept~1;Y~{xHfXW?7y-EXr7Hf^<WO>8??GtGXt{>uLj6(wwaXILk%_=L_mZgx%Z(4>sKj#@94UDbG5ua*sEQ<yT?T8'
    b'm#^gN12zE?`0jUG+e5C`*qZS#mWtbnL9Wc;0$qpP^V2K3*oIzM&#rFf9(a7Px9EJf@H7=(30JwnCCeMXaLwL!pR$=vbIrW_KnGv<'
    b'bQ9_@5Z3A5bAJtZd3ANOfKnKE!o}xafrRCJ@A;MvdynePHOv${mDjT=Q%)MWy4`!rH#_y7tNycPbAERCVVkCOYG&&W3pQ`=kb3u_'
    b'S$fUj>}u7Y*}M71fms(Htl9fH_+7d`&#tES(=}MO|MrZ&{OOG^`7mvA%5-1&f8o@tS*-3O8uyZUk7|Sj;^{x%W6S>29d;aiIMnSv'
    b'M-4u1d1&zI4%ZC6^E2}oPS=vjg?huQCu|oh*m}DIs2^S}{muhR(fhR;`hJ_SEbxon%G%z0*pr#7P1)Y#Al)}sUXf{U`aIRh{x<pL'
    b'6gYBc9$obie0JT(U4ha2y)N=Pm3nVmxu|Zry5i2QZ?1MGPIp*KW}_@uzx5IQPL(w8>_8h3GSpF&KYLFhNE)(T!&I_6BP87M>hQ|;'
    b'e?O4@qW5A~P7XXk_aVf4M^tSeQ^o3A-QTZOT>zox$-SBNpZ6X$2{d}Y`Gm7%(&1mH#$SW-nG*YNY{)e0n)rH;-b2hTuJxYOuRSiq'
    b'V%8tgctc%&>i+J@cE6L2&tlyg_)8Xf?Qlx>)sH^awbu)FEAH;)3hKT)kSL>h9K0&^zwSy!QNM=P$Ta|9Q);W}T;32iK^DGSVBKcA'
    b'ZV%#kx!N$wtHF-V@4?_}H)3wzHIjcfNksT{cI8_FFZZ?fPzHwZq(135tkLgEGSIx`JKt)!#u4M09DiwE8@27~7ltB9dyjVRl5d|4'
    b'9)k5A@7`YSJsh}W+<AWBmTvE@T^p|VaNt5}`@HX2*#5j>65UOExo-QQiB1f^9J)wZ+bZ2Fh~cLJ!{w((r;WYwJpOX}?8W!5Up;;H'
    b'diuj(p2k@YljFCzsoV7M?8jHHo`3&(`s&4t*J%2s+`K=TPQCb@o?fi%dO82uo}6BAPZyi@o9OM<7JB;C^RK3VdH(Io=dZSdGcy)-'
    b'KiO*tqFmi#0ZvXiyBaKdKo?vo`1Jeb!tOp}R>d`*y+ObHf5y5=c*A}oZ#E>cS}r#y{Nwb=Pm2lu$G<ld^1ok5g~{A(Fq`nk%=wot'
    b'W^2gAE8@44)5&rbzWl>wc-XE$_sRa!)t&l|<!o&y{~_l$_W5eHT){y6ap9FKo2YxTX2MBK>fuiUMf(o?_WOn`tiVP1ZD;N)`wmbk'
    b'K-!aL#($i=hDA6DGH9agd<mH~*(@g;tS;6Hz`5=3y`2LRpG}rGn>DD;zY@$zNauOeUTDg$E+*e>)|2JO#l*7)IH74r0aBq$JSA?$'
    b'tor#MCw|K>LVIqtyqbhyfoHWcf95%@8FKKb)_K{d%$nDm=tQn3-GBF2srO)qQesup-pbBB3!h<^KA!bHYF3d{QNK00yqvV$_wwoM'
    b'zjSxma<MSs%U&xN;r1^Rk^<qaA%+^<a^eGqxk?y@{CIl0Z3|t_fV?4n!2Ksp%V%IE-IDV_zoA8Qb9KG$d_;`9*j&bE6QC`M6}i^4'
    b'+2z-AzP6{6e}nM&39Iwy^a7#=u<4{T4m%$k38r^oAkANQnzZQgb5<<yLVvHeEV}>;4vx|9uxHa+1T~LNw=7F}8YI=5runyrS@$`m'
    b'%mfrPp$M~R+!7FBrni15O(%3TVRf5UcUZW7X_qhwPFd8BG(UAW^SPH)m;2)7Z1ShGNsVXft?Y}r!y+-fx>?;m=@DJMPX3+A<4G;a'
    b'N$5KQd%J)`LVuSq_80NnARD~I+e(><TFqcmU>FWI^*YFhR<PW9xOdv6pN=TF92A7zo&4Bx9$BTHVvn2qliYs$$H~{&idtfxHv?+H'
    b'<>U&;bMhXj(n7vjm{@kQMIw)bGGoh)+}j=e#f}g?=??a6(%G>cw)yKX+_jnvJbTqDvw7E1M>WE0w%8;3ot?UdZkz-?hqY-w?7xE!'
    b'`P!b6^gnKuBM5}Q>~t_f4nMRy&=>i%?WTJInJunwHpA@H+1<%yGlZcn<o{rWZ5iWU8enhc^->Sbs@|2Y7(rjO`#Mzgl_d_J$nEsr'
    b'%LVBD3d}J1_#Vi}tKE7H{Iu7Tj~3*lEReCMq5G21JqUb&vUY@%7uuh+z1~btUi{#9>umCLU6-Nt|30M>w*1>+vH5IoN9(CkW_HD1'
    b'BRDa$6W=bRjTZ#|A3xQ){Ew5T5MOe!4t@?O01WgRmgEer0a$r>1$qM50Ygmaw0yr>E|xdziKc0~dc2YA4}>xJl+F2JO!R8GUZ3-g'
    b'4ts}#y~%SrMlf`kd5!3Y$%r@K%k_IeQrU_Kw%2TNnChQvx$xK*UYXP`CEMvlf!ASNV;bm<D2&bP<+a6z2RRt<?|h~jbX5Nme3L8g'
    b'Lk}s}zyGwTUzc2j*>d|{{X_f0=6$e`-fdrLe`-*;uj62+-KD1{z@ulO*Z+{*?LB1{tUtPuw_noUf$Ebt^UWp2)@ffCcHW!<Y1&nb'
    b'YpJ&;+`pEc>#1BcnvM@!)DZ~yRd7prdThVmO3Rw|PeOak^#u&P>zN^!>?{SJOlg>H_>c`97<ix!&x~hYKCPQc{7mjxdm&z<;T>7+'
    b'-|jHgUBdZS3FZNgeLA1XHI;Nt$vt*EERw_AdZMs~7JDMPkBh>G{pGBEPut#4d{jjTo|AX|Z*P8j6bSUEM{m7tRsZP8hrj*d@=oF!'
    b'g?-mEDqXZnMxMP}1W{H?f*x6)-Vcd2qYF0P+byEKgN&N*Jb~~-POEJU&|&>vLbv0|;VC`sTY%J|eqU>~WG3c@CHoG}a}>Oywci!H'
    b'`uT48e@`rtOFMRbcpX}T9RFlb<sCxb+p*UF-D!2ZgN={i@UnkhlaHUQmJ3qv4PKIqz8(zgK15iD`J%^Av>01L>)2F*Zid0*PmBLG'
    b'tVp=k1CqTvgpn=(j16wW_wT>Q?HAZ)F6z!!ciuR-Wh2}6J;WCQ>OGnN&^|T8=)BrD#rVJ5neC!SfI<L_-IpHFLm-HDZCgUvuJ0Yx'
    b'|9W+^C9Zo~US34ujm-`4&dHj-BXhFGuI(Bkr<4D0!ryzCwns+aeE;&t*FT)L3Zs>C4FLHL1{lQE%hmGJ?a93~agUvbr@td@{<>8#'
    b'PbORt@A&nk^kfp6Zne#maaD7+V?VUA{7D#@Z?z-HpLC`>@NJK+pA4)<_l?sUZfuqx?BWn}aXY#arB9+A^4urQeQLgs$m+j)a6iU5'
    b'Vjl-wPP~p8>|=k{07{s*Uz|NyXKlR)hyBWTJCplx>~58@Zy)bCPHIWr@f5FtsypD4)8MfJ*e@7WcloC&+N7G>yL;?eXAO{T&)@)8'
    b'ZdCKHnFVR{1Yqr*5e?M-DCZw)#)QabLziK!-BGgDg}n06xZfl&sBiPhp1B?l9on&+0yndX)83{$$VI{4@3{w_8hZnM^Mus+#?Ruw'
    b'bcksA<PSX9nNF{7y#YF%f|!SwV`%oZwJ^K@dyZQW%bOaS2gp9%ESp1;_4InVo_#twy+4c(EpBb~7mN9A*R|2uzvscT`}pY(ug|Y('
    b'S)0lA&B}sW^}J4CvG(T{A1CVeTCTmNUMpSvXDcDdxs%uL?QFGs-T-7plmFV601T~PuVz;>PI7(bEq@EcesXoQ@#Nmw&=9vV2~}d('
    b'<XyQ^GYE^-ZS6#ugfI;H^;#o)(>1U+?E|VG+V1Vc`iJK5?B$QIo&zfVCnE^|da|t`-8~jLc(bI9`SW3pzD|wbE70Q;>a7p6MN^K7'
    b'Th{6pf98zEzQTU2nnHA&I{vsmSKaC%hJz~RKX8sk8<Z(zQL!McVT5bW{0(VU6oty;G*T7Is_B%4%M;6r@VTyYcA>><uSCE2`exxJ'
    b'?^o8HkTx$t^V}xBCs*&*m-yp``?)>=9rC=~|N7=_{rC<3Ji-6*J8wQ>!g%)KWAD`uAE&jeA^f}Z4;b-kX>Kpyyz<0*;v2bqh7CS('
    b'7~AF3x_YC%^U3!Z{>jW>B+cex4tn$HlJ0Ks2u6%AF8%E5weLUmqusXB%%}GnCld-W*MqOyd~ZKB8$Q_V&UdGN5%hB9Lkt)n=3m*|'
    b'UfZcB2mjU=zno1D665&c+^;7?V4hJbWT8M_or%iK@gh!@CL$3LYc%t!RvHT_D_uz@M9!7v?dPm4BnVenlQmURj#T(Rh6=+;<USSh'
    b'$dreT8zyJIZ6k_yNU>dlL1K(Dmn5;Ud1f*Vx|C^Z@<NLu)k#&vStg{Fg{mS^36%?zm`XV2Iu@pgWmf&u6XTb&#f$5cxpkX+(PfDE'
    b'A0|qFdi@*FWc{~#8M-Im{HmVN(jOXc>H!8<)M?vF{cSiuAN?vu$M|M>efiXQckznX8g}2}A$vGx-%hn5$-gC|_^7&G@R?l@_n14y'
    b'_07hWhotpk7SWnjq>F;3mIRA-XU4fwXIUI4PRm?7-qOmmM5MgT$+9A)WP!-a*WApH^7;;WeV_IRx#oW4xJS+)hx4*tv<{vAgXslN'
    b'?u@td@!rdibtuW5#O@=_KAYG}Q-ZjwJW4e0LFG)Uor}~amZhYH(J_k&SCYj_GUXBgnF2_f)rN&lljun7e_vw%$EN9#Sm%|!TJp|B'
    b'uln8*e;@Jp-<&4v4zSdW!qE2jrNm6cM#<9UF0-o2B@1iWT*p~tQ>Fw>tT0BhoIT!TE){E?W`*3OlrpN0{)m4mO5DFmDz)|(O6#k$'
    b'zgqQo@9z!Sf-GATS1Hr!MTKPLNRvucL^7{({LN_L>%2%-&MZo;S<#Q#qN7SX6DLP<JnH_tse2u~+x{}dl(YHuGFFXC*jx#l<dL*_'
    b'R3@1#M55E8tVG1()m5ya?PL7^$W|_m9T2XzLd#McrDR?lN%~((!VccW{O!T#9Tt}JmK2R8MX!M?oyjs5u@$b&6RB8LH`g+YODFP('
    b'1*@2TUIT+NFQz<_<i8k6`rFWhxmtdWt`FzABQ(eaGFnwaW@*8q$-Z1#X<3sJbSEJRi^xT#b5UAFEZUbyZ8E6;BGJO;N8owX^y4Jm'
    b'=0ND?5!=Zb_`6ZIE?lK}iL?}ev!y7lj1vj*YD^rNlqq>L!DOq<Gi6+^lhhT=cg5t@ae1WdBV~sqOb<+gdGuBt;ll4rf%}QEj)Zq4'
    b'yuUBuX}MS~{3ZK6+G`(uzNM7MEb5RaWu9e8rIWmhn5WMut*wqTVXMd$u+xn$(<Cp2&{0&zsdmio?3zLu|3nnHrHF$&{Od^eZy&+H'
    b'*m-)^*Q0?5K0bdhdSM+(fh|{^4`2IeeCyY9?_l=~8*(<;`}s-Or_Nwc-~J|W<TH5d0V$=AlKm*ze`CqsOXz)PXc<GD+azTVlH94w'
    b'R8^+<cV$J97O{3tsx(eho3j#LnW$70&Q{L3M2ILgtiEidO_MAw@_+u2nWMPf5x1X1taoKbJ4(r;l>9xU<WPdUBdr~2?f0OyyRso3'
    b'>F!8(zYpCVE{bp@xg*K_)+9HSiuFirM`HWi6Wh^mdGuQz{g$7>Pdmx7kN35Y;`{d$-(%!<l;21BeU#r1WvIb|2EQ)=kD{okqBu><'
    b'DvOk>giF&R5iY5c!c-Atx-)>{xvB)-QvmBSj|$@yuzBM2@$T$DwFEy*aKBcFFUP}MWmHJenn;Q)wV8^XGkNY3!CDf)5F*jB1d3qw'
    b'h_n!if;p&lDXgWS*V$2k9|ib7r~uzBIrDp7o=J6<r^ZShr8+TAmypeAo@8ZOmfErgYm&0yb7|wWa8VZ9JaS1=XyK|ji;AQ0{wEjS'
    b'qr~>B@%OmsRuI{#&XYW|rbzOHMZHz2_(PfqTgCzw9*fW_2h3f>I*I726HeK}X5~?IA4T^+r06ame#PhL`aTNp-+|nY&Xc16KML^A'
    b';HZIei$@uLl;OXV4DT24d{D&hHd)|9<903c+X)rv+}KFVByuD$qvKd>O;U?YYU8quqQX>4s@w>Z=GK|KR4OsYxZQs(iM!j?y>d~8'
    b'QU1ncf0VCB`T85m*F)uvk2H6rx!;54Ha=rQs1Pex47gM`h6UN`i<S>F&}NG{%(~CF)2suvLCJ$2by_Nui6l#%h%1|wpv2NiSY%mT'
    b'l`6pxGP6lxqO#B;k5#2?dZfe8PLyzjAAeJW?{ClI%PR%mG}A?>NAmY%^CT6K%yel~s-r}Sw5(Jdmo_a#k>^Z|hW{#)<W4A4*+ivM'
    b'7KyQ$kgBSZW45Uyn;+SHgw0phf5H;#yufqR=0`R^viZL(n|HIB?eh51QaoCUzd7Mu&*iOM`HCk^DxRZ?IjWeWiuspQG2t>U3`Pf4'
    b'LkIhj&yRe5<nw=BKBrDU^7xU*k39Y_$KwI0Us*GgzcY(}8f9<Te>RWOGFBx_Lz!DyrIpIS?iH-VR1|SpYRwdEWv+9RimHsu$QdPL'
    b'C6nmr^gXiok-ZPGcbnq=sKk$4e&q6hIWG5gERGcbj(*^O1V3;nQ@L~4xV~L%-dhGrk~-zP-|$T0n3Cm4jQ1nPa3r>}Ze`c+kB4GM'
    b'`un@k-|<NHNPWK#_5JeGV*2dcAHSTw{PETE=?{N-`ttb?lS|T5pNft<`47I6XS-$Pjyv{0tFjvj;AZ2>BLV#V2w=}&fDJh>>qYy!'
    b'QpWzZ_v6L$qZjM%bn*P`kdyc*wvGh;Kh;fpwpW+xc*FdEPGzXGksJp{8aQSdcnJAiuk40bZ)w2)b5hTjv&D<+leu-9e^3&;*ZzGi'
    b'=j#D7n=K5Mdi1L}=&I%Q<x_)EoK04<ckefsdsOxl{)btArfqs({}8&saNT4YO4Ti|Z>L=CFp9GYhNM4Se!pDU(<eVICioxSke6&G'
    b'ymA_TojLztGFwbe)|=JYY_U0W^QGLJspWEh=HK_NoIY835(#V5|9G+7_y#!Ivke*Z%*^x#pUBzTPF|yt=d0Cnb@J1rm)M;Nz@@&K'
    b'`=X;0skOb{tS9yp1ncDg{P5!YiMpB1H?zfhLMp~WhR(u_)^>Ap%8va%C$sg0qnlW4X!xle+04`v<<R`2dN}{VUz_nfo2@vMRp@!P'
    b'xW3u+d%Td??6$4?$!2w1uWD}%*Aq^=^Q3+%7q=&VC9%<`?P?uf?ulEjNEm!I^gXbec=g;5oI+!AC9kh%i+B90okR1#dh`B@XHRxX'
    b'X11|cXMVD6uV?(N?fQcMTA!T$vTbu^*AO9>Z|-WV*UsDS_kKK{SWZG?r`?7055l&Fr{PmKTR`mGJ_%d1vRBKWZEttFOmXGwMq_2X'
    b'm?E`-XO|!Ghr}O$I-5)h{V&7IwH0s?;69#t`E<!iUHHE?e6(3vTYn?hn+x#d8Z(d|Pyf6ClY=`Ke&P$xn(tmvz<PpQ&%C72_GEFk'
    b'ZJ?tAPC+T)rVFnME}KDLOsD)|I(^&H_S`N`d~c_JxQvF#`stOLy}Mc7thr*?gFqmVD|0H+8KrVfAZ+H+xAjK6{WA@|^(AI=K^bK1'
    b'$?3)VdOq9u-%q^W`*S#(prCtn@&A^y#fg9ThHYH%uZ!h*^u+(mF3dFi^7iy12*H!B-0@3(5?VXGXmR@q=7e2(vv&ycc94JH%f&lu'
    b'CPZd)duXD61Rl6zKJdxYA6`$S+t`&CFq6&u<^#0T9>_dymj9fKk7Zh2$@%QReVZ5U9Q-u<;(CJ3Z}#VcBHsVOjpCE-uN{Tnf3Vfw'
    b'{ojAa&{pqu-`)GE(eCZ9fz@^z;~&`Y3%P(e@{<}`-EXdTmvge7y<7N;BJIMqOLjTX{OVnJ2@R|%tHUbVlP&#!kB?rj<YEo3xw5O%'
    b'j`$=i{|vU-Og$i2+qpYiobJol#Rag!Wjl^1{@+{dFenKZ9rE7}>-56+=Ql4f^hF<+{dsVXd!6}XwvLpb1o4eR;^RjHgwlYfbqz;a'
    b'n)2VaJP^+7-g5Wq2Ybgt7w@1H!|UO!@$Kn>&0J$Xfu<V@$C9|4wKeUIl2N<jhyR{V|LhS&ub=Sx{|fW`xRTfFR@Bx_aSOc&{u7t$'
    b'>`#C46uUm{tIxf@r~;@b`7chr^Fl-4+m}27=)d&g<M3;TL<rQdp#<O}HBI&OXf1gC_%FfEvW7lkN>2j*tEpo9m7RMzvGH)ve?tsY'
    b'FT>^KUt6;MrEVcSdei>iYin%>V8AyEd^xL!-UV0t%-X>#mzR5IiF=&Y!HX?!@!y>BPq|vj+aX-?+=Ds35+D^Q?7wbis}70naAVK~'
    b'zU4-jcQwKQ)>`<}`R=*e+0HS`>EY?rQ~?w=IsrESpa}%DRBO8JA;ZXA!gdb=_~G3eG9v5#PXb=4;eXc(3gYD~7&kCt{*4w2342E)'
    b'd;0Rfn9E*ct<~=B-m|SSetF^-{VW*P{Z2hp7~8giRKExO&aLGU*0>&HJNkPO%1%xBVRug3QQbuct?o;W9~U1M%a4m5z6w&Y9z@-i'
    b'R~tQ8`tC-q4EkP>yiV%>HpKeH7him{UNXLWGP}CQ$_J6r$fLDKmG42j^>@$^wdr*I{&vmfn^3l|F)w@ZQ?2B_Urw%9OKsQd^LO*5'
    b'!aE_X<u$`vCRa;y1B-1korWH#Q<#sp04Q?v{%rEn|4HdOn_K)0JRcfeUfUWHU^FYMmNyG?F?lZa`$>q0@q-DCPq1?^1%N@YVxgDT'
    b'%DZSM-fBSTGpfgCZRkG<OK0PH`K(X(85C!S&Fc>?ezvQbyX}%gy&KJ{ExK>7mXHINex@hg-%c;2!d}p^QMY72U0c0@lDPDiUi&uJ'
    b'rl!{pzV$<<2~a=kH$M5pW!v79gQWI#AhFJ>GO;$`>y^DycC~&#yXGDMS=1o7qsaHhhoMiOVPM|{WAWu``RVqg8AoFiG!%rFyG#Gm'
    b'qshNbYF1ls_orU0mLcCfiPKtXh3#K6aHTdL>+PFvDSH3em0ZYom{{i#W<8%eYQ$y&&qC+_A-P0;h-vJmVP(Qd+iA2euiy}AV5|Os'
    b'Ue+O~=BGz>N3`8mcJ8xhk=X{e2z%SSK@(^FaR$PHF~sn%U8MtAxnUR02XCI7CvSsIg-;&usS|c@gV<UTmYhUq9(4G2PIp`H&ciz@'
    b'Fp9=1^IyDqg2vvSw)^UHg4GOoSyO1sh+6^B2o4XxYhLPfUE|stSWb%#2$FS9<;NZA`+4Mlm<8Bmmk;U|Cpthlzna^T2SFR$2en%5'
    b'^z_FG1sqI%|6hu*jr79R&Q@D<5*@vx&mkyliqXwdFXtD%sdg;;+WkgZvb$OP{<HdX2uCmO>TiE~#0A1!yyPe0OEtGAjZkdgB3`8w'
    b'tle|Nuw+2v>;eoL#{S7yjU78_rUT^@5TzdiMD}KKb+g{=u2n~-h6ZZ}-Y!?r3!oMl*7nnE^VoFy`gy5kZHKTRJvCmpu`ZpNM)Y}g'
    b'BUiU)lVDKM?`1#Hm57G0UF>At-=*=DoKF47K=<u(-m&)h0v&We*jfLz{MoCCU6JN(wOw~&XOQ8$u3_UX2L1}Gf)D(c19G6=@$hQ&'
    b'w*P{kUo)Im_SSf{o&L^n<`!)o_{guo&NubGj(v98+lcxn@8#oM`%MLxK~0-q*84p$@#%CuUwT9Da&mII|J)<5W{Td4FeFAhOXy!c'
    b'(2}2b@J4vZcQ&yUQ)iRS3d%;&_j$Mjzpy7GpN@6wHDJ?iu%;(N=JXChwHs2q%17SZ%H6IR^p|~6+pu;`qH=p!v8T&+X5EbBWOwj8'
    b'8k2|wTe-9GyZf=rSZ`XUdP_Q}In_6Ik1xY}{!9PY;V&CV&qrMe6%Nnng`6*G1Fg@3d;&n*ykDAiPnb-WidVOQyXEafSug)Sbd8Na'
    b'*3QXVx-#CJ(ybPJMAD={SU{7P=*q6ZqjX_H1GiFfMDW%8*7z-ga)7|47QUFRJ;UuQ%FfIOS$Yp-*BWkD5x1YUE}~8+yYjMyhmF8&'
    b'KkB25yX9r`;qZ+1#pNMyRx=@=Al{mjJJ_(nt6T8uXR||9OBfidtL2)AEPPS3>Yj3F-yC4#eUoQ*6hOJK69E8u^z2P}7P9=f2$v5U'
    b'xF#2C>8CvPk9vnb&Hpwa*hPO{^lACO?F^vxe))%QwnOk9&F05?6mJO%M+Y*b^Y)SA^H10G)A-hxD?59)7%-eT@X-05(Ao^@m;fTV'
    b'K@AZf7Gljg)qYENY-77&y`{Pgrta|Ton4?j*qr$78Ii@qWYS~r8Zg&~a$ULf@77*V$YW%VYvQ|lExlZu(ZMv^^dOm>bH#7Zy<qA#'
    b'6*gl1=ZRT*^4P41E7_J^onPH-e2cAv`bw@opsTIVyd&WDB*vSrwD2N*d;C{3?&%$$H?R4x>wgS=+;|njgRaOUIQPePCv%|N`HsKa'
    b'|3(|HwvUHpQ~mIbf4g^fTAQbrp&@Mh^&IdaSbyYd+LbVXYn!yw^?F*Hi_NzjL}NjA-h;Kpso&K+{<58phjFx|!!uZu3j(FxA-K*c'
    b'_U7GA%#VQY`u}dt@FB41WlZ~R?WR6xTYl$P_WR}LYtm&SI>N7H&oyYd@$A`HZ9NIRh=tjOJ>9naUpEqCn0XDhb)Nj&BrI9;!O&7|'
    b'+o(NdjeExb>!fXX??nLcdJ#SF-HxEQz@ex1;l+wxfteRzerTt?ql!a&)9H2d-go(C*9A0re25-T-|kMKp=`7je%SRe&<okT+RkC<'
    b'^=4uBoi7kcXOk&;cQ!X$hS^<)9pkMw_qI$NS~{)UIjaY7I_MMXoi~jvqIbw~5eL?=Y3Fq0+s0qxzi+;6e%z(@k6wa}bZ|i_98MBW'
    b'_D#{+(Z|q+uCwM%^ZDERDdgsOZO2Q!=OeCJYh?EJlhr5m%FO0I+Tv_?Eq#3|yyPSQ+Gq6A?%AmHv9+qC4)*eXbsvoKvs|rD>ium3'
    b'UrvV=`7VIowRH(a8*4eV$UW;Y>zJ9i{OILCd(Qjn#earV-jil|&bBi+9Z~f`Nt@Qsw+)A>jiV+O#vA4AvkRlW;J5?t5AjTMn$TI`'
    b'dLXBxHtJ5_2TasKZQZo*wRQcEp<a7xwXdvs?Bp4pf9xo0e^!3k5$wa-n&N!#yNmUPZdmUj?ka{Lb%q<_dvAOMN%H{}YV_po;Hc^='
    b'%HSQwckFaoKV)Cc<M53?`5F7hKRi6X&XEg<d}e~jr@1cOdfy*_OkAg>1M0h3>t<ecM+e6<^xAHJ4F($SuYGl3gKJlQtxVZgVBBwC'
    b'JbU`>^!1Au-%h`O`rY#%9soo-ZWm5qay478iKg9ZdDVp_{%Cq#3(iH~_^L-9kkXdaXW?+s)UJL{V`r0aD!BH?BWHmfnt!lQABD<@'
    b'*SY=K&M!rmFq$JW@?I?u!y&@WW=14{r$5`kTLBFHDYR0L_-vThPwEkoK>zy7sh53(lr7{5)I?Yj!ZO&R7g;;Y5b)Mzm&KbApAJFt'
    b'K_^*j{q+t|`fJxL+jhn3<=Vv-KB$eJj#^-b#)DHisIu0nyzd<jA5*XR)5<1zu3qL7D6I9gQ4!P4@+6Srvmal*dj9=usF4@1$Ia+('
    b'{H)qQ-Tr~GzF83gH7K?9{&m#2u}lzS7y5RXB0E&s4e9J*-(9n*A0<>T?2~<U9!^5Zd?PP;(a^<!jS$9vn~!_wJp4GQ_UrfmKmqe7'
    b'w7~5+35|Co2}#%gc$X0Din}pK?si>#lcxvl#jch8o!sd6lb5%f_Y7rPcaHcw2jV}|Y+r_`)i3I^!5}w3eevgRYl??K@B6Z8-G(VN'
    b'5xw4P38)8*Q?F-@#&!a!$gu=sH8*~arW`N>hMMcB!Lvz6y^XZGUF&UQeIb7rrq~7LO}K!Emi<H5({9|w<&JdTImHjY8#EUF(swp='
    b'kfD!Q?1ugiJAMur%^_BFbN^%R0o?zWy&#Ys!y52xwfxz8&2JiA)-%OgvAf-o{xSNNu^xx5^}Bj#&I9tNSzUHg_tk%}7kYxX=spc^'
    b'ZO7KJ=Xaw`ngAf*Qgfs{tz~L^FiZ37a$I76@x>Qkf@;iTE%p20^KXKW8l$QO1tGFIoFfEYJZ~g;UEH*dx2Xku6Ncu8GWA{5a|zKg'
    b'^(xSaYX{Cpe$=}`FTG|)p#8v`<8eC&M)z^uj&3g^fn$TszMRiN*4>!2KTe)`S7SJZf$cJR{oTv2zIg?i2666>oUu*+jlF*L^t*GO'
    b'%lQD&a87-}fGW`5a?L9Dw@r)hK^*hh;sYQ+v(^rs@Z(8{nIv1O73pmI^@Nds{+RvRuC8Vq9_-YVHFLI|8nb>99bCM&6b*89`_*iP'
    b'Nuh<4>y>r0PnRJI<{UI|9=xmPEj>aO0&X-hPHfnRHJ?r%x4DKIFy8lnhYv5VKA2hWM6??v<84SEu!6m4EaoS>$HHq!yKu^X*$ijv'
    b'i5PwPA~;^^0fc|lafmzxTW_Yz54*93yG?vt&6q9KdpT(B-Vvn|2IpNKfft|0Uoy}d&+Zm_A#St-(OcFGY-wiB*;QZ6H7BdJ=kNPQ'
    b'`2~3phI2M)Qa@huFK6Qxa_0!5jrqFt+Glq*r^9175Tkfkpj`;Sn0zVM_IVSF(OEN3cY1E+;^w-?<6Ot^&pw~eK^p4|n(+(csrGc}'
    b'tsrDB`*A1-C2%jIWE#?XVazA|qa$s@aYqvX#MgLPa%LH7x8XihBkqb<FyrIvrGM3*#p3m?taY`$eYQQ?==+`g2!^~)1O5btKV#%g'
    b'pwOr@YUsGNK@N11oHSD$0-wFp(DudQ7=?SDinjhKuHMjoY>)m<P7nBk?v6s+JGUG>+Z%v@%|!1w<-6aB-{*~a_h@Oz*G6hNs|m{Q'
    b'<nAGP>%Lgqzyfvu8%7WSKD~nkwX2i4yi!I!nY`(9s3%vig=UK(&U|~i!&hpyFl~aom8~<>PS=~&jpi+cT?YG-0ov^ytd`T-FVB4y'
    b's!99(M6TC%<=F;$IyjUeWZO9B*K7q%F?M3M+E}}2BQQc}*<|Srl*T;SF=~C}fLDgi`Qp<)Z+G_1->%rq=5sQ<w$L{dSTs=Q!-vhg'
    b'LC(PwH>p{;MTF}cO{3f0%v%rVl-CER7}}J_yvuozSL-QMA+G}X_z%-4?{*1cBW%S9ohKbz+`GQkw!Kyu4B2O4+rAE&hF>*X&~+3J'
    b'gp9O8W=Mt{h?)<3SCh)%29uU%i+8Q2JS2$jDSSRh;A|D+VeEc7_}RtqaeIeGE_?RJp@fsWxu9Dv2?p7YPoz;VTR+pb(~CoUeKzE_'
    b'84HT=(&bl&L<}$1kdW)2!0$-6KTe*1f}O5so5@R&rrlMp{bucbg4!_Zu=C<wS1{oFEL?cFXk=!6N54fI!LizZ=A|M}M&CBc8~^?J'
    b'|NYMwufCdo^Zm;oU)T8?pI%=-CeZueFn(7HhS~nd%mO(>tGi9e_37eD<sz+;(qxH_Oi~ptGO|jlJhIY8c@fJ}s5Da|Q#uh*p5g!U'
    b'!st9p66ZROj>qWkN5IkW4<9&xgLS#GtA7up{>oq7&^EY5I)jLHq8&PyiHXuIjw2f-rpoe2N6M)R{i&?fWm<|tIa4JfNu8F?rK!T-'
    b'W#&Wbd-|bW!}}S$J<GJW{tvcH57>wMS38EbZpXmwQ^T-<+ZtV?6S$8J^57Wx4%ydT4u;9^Uc~o3Hhe`~uxhNeFud-M4U2xJg<22m'
    b'JdNGmChCw?+P6NhXA8z&cHCDZMrfnPFDEAtI0+AD=-ugG`1xW^#!_1|8L*cx9T!~P)xHPcJKDC_1^h|2@75pC?Hsv>ncef4y}7Z_'
    b'Y<g#WjoEqli2a|_M*l7OW5_zckL37mtlpj$8MS(M^-!O2d%S$W=51OTwtbIgYVR7tfaV%81P>dSpJ!a&ZCKuSg#VZ(WsmG>Qa<|S'
    b'?JsAO8VIj$7Ew~Rdc95w(kp)gu=3YO$}-xwmJj&lQBswn5`__fFG*rk;o`W`xhu0=>Y@~Js-iNjN-GPUxYTG9mnKQeJa(muO92G+'
    b'$iu`=n>vefnO9ky7KuX3LRDFrCy|Sa445cRM4721GXO}1kv7qZbTXFCBr+{TW!dKYo5hDU8hg`>nR&oM$_RgAPIoXxUG2MW+<&uo'
    b'3%q+7mKB1k)~sQxAlSq6);{;Y)=lib-0bA;O-KFaQCkC+=Z5uSuOBhc>x*VN{%*tNH4CQu**XmR7sGhLJsd!90)GGToB9fo51WAH'
    b'+{pRHy7%OFGwUk54rcyli<rOlhP+zJmHEz}{eC@Pe(d1oM=d(+XAwH7d+4Ey-hFjyFsyq+-Z!)DqQ7}`udd%7GPw8C<M^{SuFUe<'
    b'2a7H?%Yh4(?fv0;{5QOj|Ka4b2&c=<4>W6sIa}m4!=_nos?v$91OtN6Y!ziP2e0K(S-K*1u2MxIz_pRfs<?0>=EEV*b|TW5NL>+S'
    b'*22g#E~<=$Wh3Llrb!&7vCwG(3rK+9O<p<`RWTkU&T26IC};n)Ab@E+Eti**N7E@iQPb(8U9O@9`(n=-Hsl)ta?-1rg00C{+r9PY'
    b'4O`TA!3Lks=UZo3@QpPtu@7`__m1lufc%a@QB>Bn#?XvspzdjZAPij_lGB!Dr_%UXCFXTo*YdsI;GY(Uybi4u(Uj7-pFi<XleKg5'
    b';PQ{qCfSuat=3*Zt!P;KG+*^8<rrb+B?wI!=z>aWm01(ZG>Ty_>o}Kb8t3>kfeB5@DRfjOGKrncr7T2NfHa2)Q;G~asZ3)N$7xy='
    b')@h-u2#>XZ5uRpcnU!&sStatS%qyJ~Rh(2J$)m(2N{kWaqpjkfyNf_t&l#6`(vsQwL>hU`pp>&o=f_~nQ7S*$)d|0{z2L;bX4<~>'
    b'62!^lT0(Tbo!qQ#O~G|^@r|0#*6$f@3|^o<@k~I!a53>)xbk!z*D*Zj{_xfB{6s1$m+j5wU8VpMS=iNY#tn6J@6%U5JfHsMn;%}k'
    b'c=dmWnPAlA`0BLZ%IoJpco)+^%fY$$IfUME@lUrrxz!lW`~K=+&xY`^iUg0{mGS_6*T`sP-RBz_!N%CVGCyW9a5kLBsLkO`iqRW@'
    b'zxK>)V3R-d1Z-fZ$L|3?_!R7(j@{2V1$)rAA8NMvoo%;%%xrnpkp4>&@H5i;4_?jyGR=0B(jl7P<G_o1w2VRhxbQasUfF9oTRjV`'
    b'{S9LTeofbh8%3|*d(ig1{CW1yJ6@iJ8x>C*LG^1ozgOEB!&e@?csI#6i`iz@rd9kc2lKE_FsdJx8ZW)_aQolw?Ndtd-*Q0rZXaWL'
    b'I#)MWpcW|0)o(tK`!#-g03G#Bay?^i1z-Ja7#79WrcM~C^F-LZDoiAd$g?Vwk<@Wkm`s?oa+P&y99dU6p`$FVZ02BYJ5dh7qDsZN'
    b'i3%9`aVkYAqNqsABG;yfg($SQ2a?JrxyWo)mP!`<r%Vd;6**xK;Poc;)x~T<oN*$~{3R{#mTn@nyAjv5!}Cq#)9eg@gV~gL8uAkh'
    b'=Pf)2iV+b6L^1SDy~Nhc0`jc|3O}ls{lHhFz7l@!x5~>uK>NnqerQ_pTga+!@TUJ@z(RhsXU6=N0O@)B<pW{SJ!W)DQ0RjX!p3ji'
    b'oKWfX5_@pDUe?$W4{I};{`gfJ@eKTNTVE)|aQpZ2+R=Az<~5Yid)!54%?mZ~3iL7hc9)#$FSaKfqn`}XRsFT6jk~@*=!rY+P}a5;'
    b'pU&uRB7(5_Y|FXUb<e(e&N&<~DaS&;1{(M^2ITlU4~j?#!ZIpMAqrWR&Oow7kZjJyWuD}w%!@)Bl|^MLrIv#AZX+YIL{WsMiOGgU'
    b'WE$zxx;QVS6Gf$+tYQg?Dr0Re-IZ|y`Dx26vPl`4N)|;@swgXq*p<Si)u`q8K!N3Bc({;{j#A=2QX<4WeI5t@N-lck8-MQG-lEvK'
    b'Tr6gbcb~yjcei&>9{c702XipKeg'
, '97502560749976debb528781974087f2011c4983fba24a32151108ebaba967fc')
CLUB_FEATURE_ROWS = _club_fixed_constant(
    b'c-rkeiE`UUvcH0GQ!!af!?+K69R&xG=xrS5S@zbevQ#b*7>HPt02cryYaRXj>zM(F861@Cc-Qf+n2Jo!(bLn{boVsy;gPf3J@GdC'
    b')sOiVDzY$(P>{Z__67PWFDtRUPLt}<Liq4#SD>pj-<NNT{Q7OV4i(*i_FwW0&4owkeTA|z%`-A|g_68L?Vv|1+fX$-l4H|e>1Jqz'
    b'iL4o+9IbQ<$)=ttN{FmgB&&*{%BCXgNHR@h6&tZ6p(Iuw!4hFop@M-K8<K74nkA{GYRjgaM5b=Uc4DlIB$kn`Dah1qbA>D;3Rk8o'
    b'8CHlSU5zctjI}VqFxUI+T?xS6G&p0xe@YX<U%Ib<JkQeYE-xzK3=`q?>3MdZ{qQ_YGbgI@LMW?ZA63FA?H0n{QgkhRIL`$5{BTx<'
    b'6?(DyJAyg8BE5oN!c~aDz`DY-VK`^Fb2_6S@aR<@-z<bO-y#k={s7v)7I}oq@-$0wamRcQi_85MWmPFgc~-#=%IW0s;|NxKjF-Q8'
    b'Tt+Ahi!`6igbxH0yzmXPndwZpZI?ou5`E%&2|{syxd2*^ul7OMpvy42ae)9$XZ;UL&34cTm3|4Y(#x;{Q3ZxX@7ON<`8h4CZX5o*'
    b'0tuf^@D9Yw{7NiuvTBX0G@8uBFv9yzSLr6LZcby^cABK97#@9|9c1|qS*w4)Se2-_A_zao-xrj>Pg`w+!Wb2+JS_M{c>((y5yfe_'
    b'3!^l<TnO51NCe$|Rpl8gR@Z42t(_>!_gO`@LU_ry^IKs*_YhnLeKDcrsi9A1eV{-hiU1HNNjK;vnJupKO<exkG?lwND^WSLLHzk?'
    b'P%C?y2x7Vdo!Bmfv#J1^O@|gPtFWk0>|rv@X5$cl2Qlge&*(~%+2=rehq4&@{tamVN>}<kXcq`TXa5#*zpR(~2*i(JTx-gyFK)x#'
    b'lx|T>v$UECCnv%r0~crVuh~xrgU_^|=V-e^#TVQTMPO`^5p&d-x0eV&gTY;+O)S(KWQ<#P%VcmZ$hDCv$88?jT%4BSYJ=iCwNH5V'
    b'OpuO{>XXStk#6?ZUtj?H*0JIHn4!1-X`a&UTwopZL17X$;R<aa>Yxk%oJZj%{U?g4-2WBbFwiH$pM`vf3bHA&2(SMZZuV#f(sB>f'
    b'8t#n%xfc^Z{RqDg?RZ%CSv}qEHy{tMvv*m3oiXdv)x_%}txyoAn>}$6#XTK3-9l%0i55bZZtjU(cd3pPe*^=HJcsRx*+D#CrPT&8'
    b'1F!Sq9rmR-)oK;tmh++;l}OSo+z8PoEXyOV@S^d@!G6@fbgcp#R0(tsW4^RQdK+hY6aMpt=wX!S1z4OABh#JfwS7|xd{Hk_L;2y?'
    b'{c4kzYZMb$DWO{h8jay#i*{PKoM86hLjc2}r`<v@C3!BOT^_9$f?Pu+V>tg41HQsCKDMz^B;8Z7%6Dn>0(!5&l+47O5(o~RH;W4%'
    b'UbGH(5CUOZk-2XsO$#<FlZz8@s*CW3%)Q`33}!Y=Zf1dS6lHbNEZH$j^{6+KEZm~W1tvvF9hphJg=WZP_VfVrjYLLLkkh)gFHv+$'
    b'1AD-e$u63?B>=A#3zM(_ZV}t@h9?}m>J?*K>h+R+771PZz-$-`Vu5xWkbfMM)J$V#ffE7SK8V1y5uX#0v|#E>Gcb2Dv+H^T%}@Z('
    b'EOyvm0n0IV11$I|jbX}DR@}u13(@8!!n>XVafX4iiu)&gIwzeV`r%x7I2S(sTo6%ql@@u1MQwV1F5=<KtjIST+)_Jf^Lqb`J6HG2'
    b'{%Ge4sszrXrDws<E#mdGU)e$J-0~m$u&7&M#WV7=o<dujm6{#mSqxpy>NH0aES|K<qdxU0ay@c;c~*hep0IZ95)g@p781UBCQP;|'
    b'2+1J=m^7X+jYzOKvT9ei((|yWsl*X&&e37P{o>8>*K>{&NorD60Orng7C$x3V)P!Swb?Fm=APo_X`U>E<2f%DSf7Q@D0ndeTkt&G'
    b'0q5FfpeF_7+T_}|5;>EElXlP>+IAr<y1eGtS~KPjWta|TtQNzFgY4l*bs(7I<4Wdi>+x?4@HLpFMx-124ZAiaMHps!?IVrBtCgh5'
    b'4@|m#(y(*FKx2HGH;sz|UR4^sBc9cw^{ZZkO7AOd&V<@N3)?y?Z~^~~cu^0I=7Xd8@#@1MAs(6!i?O|==?~+~o@Y;<JP}?b$tKOv'
    b'<2>8k2n7sl6h;)Bh6n(GS|K3<24hVSsx@x?#~zgx$d^#>n}Vb%6QSIfJ9;ZCgjoz0w!#?Y;E%vc>1CE<I27#-ahL>v0M-+Oetjy`'
    b'X{wUKOe;}%wN6Wn(iO~uGc+wI<MRaI0|wO|JRR)J!ODbka{;7h4R%1dhBe`I$fI{;i>1i<N<XyD&#2#Yhs_3WBahN>Q%fpt#ANx<'
    b'Iv)%_xS@l>I$&GL8CZg6lBAcgdJJ%?VvpF)nw87<;dZw{y#XV~iks&f&ZC-^sG8MxbL|ZVfRjdsajExvjC0zZo@Uj_9iyA$VqkD{'
    b'2g&DO`$mH9wc!!*b)tGOKNO$wX|^ZQ2+q$MMep#o+Qz>OfS3!vATVj)kES~7obEz+^ZGU32ahf`gNJj28BVB4HVy7b-6j&kb=Sa{'
    b'Cm`V~oF?sv7w<X~CkEt=b<&QA1qr;+CK<Uydp0amoB`jll$vf?Ue1KDyn!Lry2!6f;qmuF{OP;k!)sE9n?DX4ny?18`O1&1J@Tr!'
    b'5yI;*ZOJK);op24J|~GRQBxT+i_RO9dFn$e7KZ7JpR~HE2w^cM|8w@@morqPIB`Iu`Z%n@DYj|2i^gdnRFgEGv<S`low450<R|7%'
    b'Lr98z+t_X4{CwKr+n!<cT%26YhV_X-(??NGLNhTY-=+hc6tN`D$+8Q&PX;b$Y5x37kh@EgvjEeQ@&^-PKs`ZTr@u>wXP^^20c*{B'
    b'bKu;?!3Ss!OY?2su^{ZPVM&3b&Ci7_2YJDm^5@|i;m{nPhrqNLEFEqn_axhWiK#-IzzU8<4j?E<%OsMfA~0&uK*ciO7jV#5VfhXZ'
    b'gczo5&dg*Fr?c3NRT-O&ozb48JndO)7}iMS)6N0Gv$s~ghQoaqaP*F?W9G43;4}AG!!pK~tF0$E4B$LCn+>aW;Hxxh3CwT6P*=Ys'
    b'F+AxLSzd~iYEz0lvF**UhVZk_-51$Q3IT4hB_OcxJnfsnH&i%J+kqGCMvs}ar$@|KZ{ef3frEV1LNnNXX5`4qX*`JDRa%iTKc%E-'
    b'XSyS)zN2Wu6jTrYJcthCfd9^T*ZPntzP-4;oeKkHj#!V&I}02iMTV-c62n;8mTKye78|ylBuQ*Zy1cTbRU&J8g7gT67?vDIcC5#m'
    b'p+vE5N650#qr1x^6UAN`l4h$`tgDe6tG1cQacHZyA)^q<hN*;>w9@pIq^}}Xk_{dHH_SLPbX84~q4LN?F%(nN0f)p?C0j*?A)A`5'
    b'n^J6Ru^q#Dx*FPg6iJC}g_bQFR<w#NJ+bUi)#cIh$VS}{x$Z?LSbx5+>T<P1PBDVP-C<|Av30sigh2A%(41j+EQwwZej4HLVD%gJ'
    b'vM^garEklAhWEv;e3fod5aIyjX2!XTIoCH1!-F#*-=g9b4ysEYM#S}v!(eh8KmZ;FE>){Dq2mBZq1-D30Y`{W^j>LS+t>1Aly#VX'
    b'1D7j*0CwXL)L|1_0%)nQ4R0`FnLvVPe8!^pDGi9J-^c{eB#l5qSPBj8))2lH5M<&^6%sP+f50icg89`Rdx74|=K}Wl1UR5Bix6i`'
    b'YjBS-I5^b`l2L=>h?7SqRHdi!OT55B_$dVSTw!0QxyK+8FO%p`<BnU38#$l7ZH}m946%?C8p4q*+?DIR`VnOZF1`k6hSm>csBh9^'
    b'Uk#x@z9z}(A!R)nU60Pg36t_DLR=!KU52{f?TygDPMD<q$Im;XQjEEAUJEyqvcUf5$rNO8P<H1BijUEeixTc;<@^W>IZ(U%+^fv`'
    b'L0yf4cu;ekFlJM~^TQCF728$iw83aL?_MclBH}a{&79WL+8B&>iD`M3UV>A4nhgTL#*KQrH2`8(MA|%Wy1y5s-s}c3u~pFWL<AoK'
    b'oRevv#9WP5J7wP3F>d`CrVCE%^j57YFV>cZO%>fawk8b|`N1kRnc9rzeWB2tY72q<9;ETM4HiI@-%RS?@#F$rEfBh?EQ+H2R+7xO'
    b'vTeUrbnUIFNpEdip0(F8he*7)1c6By72_;52vi2qjquxVd=Fj=_tvZ(LX`NG&sxrs;D9E*=cKbm2YwA=f>ZY!IMk*egm0zpR`K!&'
    b'V%*N^G!Hb&$8Qoza%MXea*>`|bXp;<+xyDQY_4r&)}aAoJLqZG?&7d(SRMva>eS@+r+^Dw!X&bIGioFw&#c?Es8b#)n`IcV$j1P1'
    b'*RD@l!_45$4x&oR1uu-zrg2Q^?TZ3?P<Pqrllgrt^I&=C5o>*46Ae)mP64u}nwP1APzm3CH!fB~az!T8tz-n1uJ69<@p{Ob;n^di'
    b'hJkhE@(9!+abrLnnphBb2^%+`le2q4;UtdGW=Lci3iPF~opsg|#u9HfqJjv+rkiyM4im}C70p+M^#b&Z*eQI5yYV+RB42|)IR)dD'
    b'lW+JAB+c+;%TMGN&K=Ws5Si^N%@D-)vqOCRJL9LG+|D}1#obDehfwU3La~7oXzKhQE*=--wI=M7UpzK<S-v}GdUqPeyJ7T=V|#Zs'
    b'Fpc9QUASR;oed&AB-k2XoNyARE)LIqkz4D#Cp|}T8a8JS8>6uUi+2A<NW<E6n#pFw;PCa}fRcaaOi@tRm2P7w-hIbt3n#4biu?p&'
    b'0U`AJDX$@&G4qb>cDnn%R=BU$c~M`Pusp7>(?|N}BZ-FxQU6p?-*od3izDfY2aWkEHRi}8GMzf(G!eep<aJp@zvj0<33y{`QtSH)'
    b'-%EX{lka#At~9<^Ep7|tcJQ{XSDjnozf6Q6g2RHUX<DJ}LiiR02q=kBqB*)W>pzv$vkBX6n8iU}Y^MdyyODo}rGYQTob$$p`9bzS'
    b'xDB5a;M8{~6l+d6F!EJcT#^dP9!Ic&i(3ddP~;_x=>+WRz=gsad`OrXUk{@-Ul5*y``9!cE_jBXB0ExD{~%IdNThnE{D@fn2*~Y*'
    b'WTTe1CMEuCz)QcEjN#9~6+R9bm;#Mj)DC44LZ{HW4%p`7k5}>~*h2vqrZy&1*>=|r$DZ0eq6ge#lwQ8Ub$vjkqAU5GpHH69+BjB~'
    b'3$(@gD1zY?60X;n=J<+&y~Kby5tcI)i#>=hNrfFP^dq8*s}Y2-6t2-`1F{Dp9KMCfNxknCDFVy{ICCIA-R(&!IldO{z!me%TZh>t'
    b'A|=}$X3t4l8~C~)DNZb7Z|At?G>v;w*62U!o%el>lR9oaP?|iK+8G2g*h#4MjnRLL%^f(&haM-vfq!j3>7_gW1`ghxX*Pz-D4Oqo'
    b'MK{-AgnYEh0T!z3R{2M!FPT&kt`>P(7XcmehV1~_h2HN_RB^RdPuW{4QUu$%m}2u}R1lsD$)U`a{A>;vwvv*a<{hAu;T#_iAZv$}'
    b'{XOcLwihDJj!u|+iYE7ec+UEOUJ^nJi@sQrIWP9rp`M{r>7MUu%XP0y(0j4C28riPXtJ9r$)^pV<CAw(0+_zKWp=?L*;|STwKupP'
    b'*A<YJ#HRNcNY)ne_?LN6xi<`sxPc<rb59=h<V)zuh&6vuq_0PjMxsZ6UNGr+M#_7v>J-_HX=0iYKLLJY$BnNY{1<9tS8Yc0p`%SS'
    b'MED%aa_k9_!D@9vtj6VdTRSlWiI>6aA@&xg`((>^-yNDdS2;bJa3+YmHDS{ttOxZCb>rBfjngx5+17kxZr6&tDjoW5vym|ML3aOb'
    b'vU}$taDU+*&PfhRIXzX5)Tta%gZYpWjMk3~YsCD{Ai7gBz{wi>u)`;-2#@gn^o6;1-gTc`?=fjJ$PVDySiuwF)RE-!M=_ACSexI)'
    b'jV|*(n)@Hi&ZEzgWAeZsw*Ko&^Rh%6@V|O|xu*ht;2vyngn#VO9?p#_+||#oH2I4s^nt*`vkhP{@Iw{kxe^$ap=*+r5IJ}+Kz{0E'
    b'#hfHM((Sf>YM54;VR(%le237EKKIC;Jz$!z*d#~qH35xTB6ex$bm5PQe#FnS|Ms};qmv%a_TPQB-{ak1%&Rj&3NFcA{DRsNIOSon'
    b'=6#yh?AQw>@u%~+c^FkMaj_sNGpjW^Nzo=Q7b8Q(a=+b%_?4x2)E%$a`x(EQW;!9hJ`lTtBYXnr-jo&Eo^Ht#4U=e%t_u91OM1Dk'
    b'#3(JI&C%EPjlA&gJ{k7LOQ3Oycz)i^Voi=@Nr#vH%=84}tn=&o9Wjd|q0eu>bvpBiYFvcM`@M>1+@qVfCE5eUlGwdWvv<?O_<4OM'
    b'(5lAzPV!K`+UCjAcs3hBq<&r>Ru<6}FplOYFWOqi1E#Ysa_IrBd%P^^L6N?^BGrlMI&J-I%mu^MtzSmz$c@0US9j89l?Q!|<|u97'
    b'$~8{^nx`eXU}|2@+2bk*ehEyCihOqmPjAH)LGP@(*`TSof|v#soA%W^pW(%x&D~SW@Iy`XgX#RbO=tb|;Qx~MY$P}0d;D}Y@cZvi'
    b'@E;I%akqMpzaD#pFfk-WHN!+*=?aooD_b@qO+$%fNRgb_Mud_Og{Bf3HcGS@tt{J&RoRS@lE{)F-{TQNMV1q!AR|VxtecV+>Xs7Q'
    b'ss^iRdMw+Pp-5qZWZ7CNVH|5xY)FP_TZ*(Yw8YSd9wAg>DO|<2E=LwYDOs%&O;gk;(#<Hejl@7wVnw#C8_6n`RT)LfN>OBGg;Wjt'
    b'Mjs(Oujqdh%Q7t4FnvdJY|FAF%TNPbk+cbfMTbG2YS_LZdxj$|Jy*75Pg%;AqH=?5!*(sraRb?weA6%kM^+Tq_qai>9yq?DS(2{%'
    b'Fhp@JQ}S%Z<Ocb&w)7<1w>-&_m%e7JKH%gU+#ne+bzPveu1K;C6!09yU8*iO$g&j84<y|P6jjy@&orE+6UaPHo^P9h=SsS!EnPrc'
    b'HBC)bTplOIFl@X(S@V~&FX^i7_?mAj{2<wIbw@GPrKJSAE1LjOmSsXr&IS1T$sYh^O*3#!Q<rQn@ElXs4d3;?ZXR_)o|Yu4qgfj0'
    b's;5|v=W2$%v@F}=adeCTjEpR+lB7zyuUpHd3H0M}H0{8W<fU$Ts^j^N<7$eh12MTlx}q<aAQrY~>5ii-rs6M6Kj5W8*G%6BQBf36'
    b'(p=ThT+?wpgNJ0PmgSkgY6X_*+hCD&6<8tL+#pG|mabyCDy(B@h9_&DZYY7pFDLn)<|?-2fRvfeQqcnq#7N?$!nGtrTN;Mvf~YCV'
    b'QURXm3Qs3{saT4+T<V6pv`vr+*_9044aT+Pt0jK`iUSnzP2JUOMRgTNl{EPNb@OOIOKzXi$rC`$*Br?ORrFL(2lHkshP<>UaJGMF'
    b'7MP@Eh#Mxqy8q|y(@h*;2lMHnn?5>{kRhYis2+Y;dDPg9tsKx*5OJ`W)i+^T{T2Iac)+Wh9U>EGQVsha^o0e?gk4yz$(UE*qLfdZ'
    b'-R|`%{fgbg=V1m8GY;s2O@2+<dk`q_R|TSL{pAuDkbRE_^c3O`K<QE2|Ai^ti+VnV;M`7iTk}2e&@5e*WY0ChwCLbRYM)HwQPTaF'
    b'Nb}eMYXyO(`Z|!<@;pEAuxH|d(dEsXtT?(W$r4y)O#;qHvJO6z&U*^FX#{2<tAPh>lfi~bj_!LMPeCz)z|%d=f`uGy8Ne@FmK<)-'
    b'sDg2W90vgTwxg&^!_<9Mw@ld&c*K3rbF8HnI7*;O_EI$z_+ePQ1E(9BV|lLb*^Xg)zG|u}oOT@tPFI2eEVpMmo(DU1Wlvr%oz6+P'
    b'grH*?XpX8W;8>YJTh-M}S3Tl}ey!vmRnV`RM}t~&Uz=qHOGnl9rK1rS7%1mDis#9nY_mo^o$kt`j?9;^Sy@`OR*O6r*cO?0%+`QT'
    b'{PBrB>RNtrVh>+r{;qS_GITvqu{Upfz5)W~=$f<il}|s1$Ef!oBhzCit?alECTU85V`ben<NyqnqVmzbY5CX_R2_&Fz>3+1BL^15'
    b'6uep0JTRw@4o1$>6~_%sTZY)AW9MA(DP=qGm(Ehx9d9WaGBA-3lSZ|OgA~|H&-WB5P?f+_HP>@&({#H*pr^a4<r)^mfwBxC-co_s'
    b'g@+`2aPml&ZwJf3G90k=x~jrA{)|#>6<QUr+`go`j_F%qq+R~B1O1eIh@K$Wv|ZV9J>6Dq)Aq+t+OL-Uqbm4S^9U!GZ~q_SAJ&o'
, 'f15d0458f5f62be10f4ffb536d19e207596fe451d0ed8cb1cefe3f3c34fb85fe')
CLUB_SUPPORT_BEFORE = _club_fixed_constant(
    b'c-oCp%We}f6#bR%vO%rw@sk~@goFev5Uefx`Z_V4j3e9A5F!2@Pf}>wMbd>e&vVb~{$72@+Unhh-R{Sy)9w8@`_JeC7N1=SUvTTO'
    b'd>r%s`1!W(Q*5jEH(&FF?{3cEQ)(9me9Lpg3lr}1)QW?4zd?AYcdfs);2N%TIoOij))ri++W%=OPq({6AFv9D(#WU=?Ia3KjG$5@'
    b'712c=sp8;y<TT1C7-|QR5-vQ~Is&l3C0$*n?>;QdwdE}q`+$diF2M%$d7c2DBrwS^u*d?Xf(GC97*4qE1QeC@Mk`|?4BSZ#4!siw'
    b'h&EgaqCumCH%J(tv$We|n09iHX?>Q&)hO3v_HMKlU4hM6un74P%i+n4G0I6`o(Cj7MBWc!%qfP^D@`HFfrBzV;emnx61ycXi5t3I'
    b'H1vv@UCA+x*hyWm(WP-N%fmJ|v@UE@t!K>+!Bb!)NTi&Y!3#;d2&w|n3|ZH)NR^amLYUE%k|Anpv?orm;Kib(<viBAmo0|WEw{z`'
    b'Yeq%2iv1|lcZYMPr5D7<D1%cT9dW=Efa&a>@BjwGFpv<L@J5(`@tLvA6CHHtECr`#Yn}_>;{Io+eqGrK(vG2>D(~@hfp*iEebE`y'
    b'uXYORP4Fe$G-0h4o+_|AS1R_-VS`t&FNH(0{qk=)u7EJ4MfHFBXV9O&bpM3U'
, '6b9f9901aab5908da80c8411189d86e6ab0d3cf76067a156b59e8c8f52cb627e')
CLUB_CONTRACT_FIELDS = _club_fixed_constant(
    b'c-rlpTXS5;v8DgYdBe+uUH8kp$rNRKMx+>|WIrP6D)tCK<8%X}H4gpv`EoZPG|1hs{cvW^#OVl$648yFyDBqRu9bE9`$g$}^vk>L'
    b'UAem4kG8$(`-}hnZ-2kI-Ho3&+k5$oH}-egrT_MC7wvwx8#j0SOh^6r!&3MB?6Quz-3>nard;jEuk!73(>J}`jmvgb_WM(h|NF(e'
    b'-S&TtcK5n(?!LL&e)@jw@8kn*t>Q69pT6gp#;5nA^v%uK@1K1+%Xh!Jz1?kp9{v06?WTPgSNz`SulULC)kpc2ar`TX*MIga2LrDT'
    b'!(9E9z^}X+yY{i%+`TEgpT^zh=EooY{P+cD)9-A~Pp|#qZoB*C&)4P0=g(38$n<+&wCu-w=7%@^<+(w}7r*;-^YDVpSk}L2J~R5&'
    b'ecx<XznawJGhc1*Z?`wEwtf7M?fvd%{PHvso4%OPZ+6@NJ#Lm)cz0i~Hm%%kwl~k;LVoGPzu%YL`0IA})Bd)!X9G7b|4!%l>$6}w'
    b'N5Fr*2;fVvuI}r%cyjFOw(R<wab3smnMZNyuP-9Zf-7x%&!=VHjos(iqJw=7Tfx2jy!(22_4G=Y*ULLy*8BeBxcmI!Z?`w&vpC-0'
    b'mAmD$iyz*;dHvOgAKt(I`ttqjSKqz;@csKAUVYEsK79AX`&X|o|M1-pZ@<2L_x`(g-+lP%+Y6p^O$6NUMt^)EdGz-B_G+vEs6GVy'
    b'_}eW$*xX%yD*SQuag_P}IIjBTZtU^zejH|ru`FM0<?2elDB*uy{<gWkzrNgm+T4!)<t^V~jH6u1gVfO%Br$HcySvNrbGf=-JpcLE'
    b'HDBKoM{Qj0KNjP|GAo48@5R}Fl(@MmHw47yZ+DFKPuu<7@31>%_AYu*Ie3?pjW$zYW{W=bJVOn$>*1Xl(dSr43a!*=RY+whZ+lX)'
    b'yE0`Gm(ck=1|P!s_b&(8lkw<GFUlz&Y)-QVn_BaBl%c(IIW}ue%`G@yO_dmf3Bh;QYmD0Sg8iiNqd|XZ)pe&`aHGd)ifT6M5c2T7'
    b'd*4z~Au3fp**Z*P5_BA4wBb{UUAGa(Shf01*<3NXAKGq=oBhY_(G*AJYl*XHr%h_J=aKZ({M$|S(~sU&tGrM(*lFDa0?ljHa~eGi'
    b'moI)@0`>0W_Mwj7VeyOUJwO9UG&fh{52gL|)eQ)@y&X5p@AN@9@0R#^ijs?%sxn#`TS_giPUBT@I?UQr7&V&Idq^&1{2lXfRw=8j'
    b'v90x)G;eSsg-)f&0#k>;J!He>r_J5R%d747_LAQzH+x=BK#;FpZRTjdw5xFmqq&@i={<VZl8aA?@VS+~*@4KH<!_hR*?y8xIL=l1'
    b'%Kgob^b{ucTgpFu!vuAV1<yVZe|+YHuiBF89~e*j_@3$n1pH;Q-_)z|%rP(cBFy5N3C=eaYE?Pv=yKQ78Pc<qY@0D8%ye;jRqRwY'
    b'Th)9Tt(IAM#=qtZ`%n79{3q~*KIIF&=8J<9zP{f<5gw-f+if8kq(<+*g&V)aJ5-Ow121@_)M0?aq`XcoTR-(6`bR7wMVDgANw?NY'
    b'&?WP;;!0Mgw+uA;JblRjqDO-HPvQ~tk3HhezmgqqHv9dPGu|&B{Le9N_wv8r-CX_hO=)-g7d$bm&QPsk{jlIt&ZXIzq*~NOkx+X2'
    b'Hcd`FgVkVb&NdG3N5*47xcL`7q5VJS3H|>*H?;Tbp3tW}ab3uc(I1@g09>!i&CT}iJF3N@n!MnP6pNx_jOtVH4S>q7rB+)}0$Od3'
    b'F&w2FCy^N4#gglAbLOTY8OGHAUwz^Ku`5o%6d#;Uio<;W`RjuRUhM|>^flky-25YW^1Vd3k(<C#2v8Rj3$-AXsv%}p=P|VLUUyyE'
    b'1gN5e*x5z_(cM=4U(^x5u8EuPclYB+9$#*5e&#=@xno9sq(UyLO4G*{nhqLzR7r|bP4lWZZ;I0`LhF(@l#Agg-ZPp?iSXJ@Yu(Tn'
    b'&os=1%Cq^BMuG_sQ)~>@`ZNbzKtUL%iO^yVLyS;JJ>%59T4$o2EmV^hd^;_$9tL&4xje{(m2MC)fU@7z&DG}am*eud!k?|H+H0d{'
    b'HL%y3?U-$<sB&`?O~52n%lql72Z8B_Gp@L49IR51TFJ{k!p`<eng#22N*p=C#7oZE^8np@gcT!3R3CHJ(aWgKF;jhd(;!bC&>8Yw'
    b'{*3O(&WD1SeuwaR(IEMhV7$E-tx~6M*c=saKQj4}YDz`>UfZysnbtjOD4Cx&8RekQZ5|BXZGL7BR~|naq}rNf8-8PQvQOFhY^<I$'
    b'*h10DBL<$7Qkq)hTg{&l&6TKk=`e54dlz`>_5m0^Z<`$H52H{qytpo^2YKn-oe3j#kMtVGF`HRCTaj0}!7|&dg;*X8R{`-a+g%F~'
    b't%~W2hlN}evWL2zx*M=oZFvVOM+y;VrHqakvxvROq^63q+gLNW()f5X*dS%ZVo8p8Bl#Rupn!EQBtM%Ct;RW&$vQ+{hADs-1m&YL'
    b'g;#TH2H&H_Hn(?QG;*GdCZt)cfN86_n=xHz!8EvHhq`Og$<8K7NzSbfTWd=;q&@*(jl3@E;-6?m9VJ5mw_U<-u81i1gCY9>@cUU%'
    b's1wMU-KsvJJ4j>2tfE!5Q;p;d^WtCZDjkJSp>Pb4M?<kHFWyI(SvA!%BSw@Hq^%(%P1RwP#;~o9Dbzxd=~=yG`Ox@VF=}iG!s5Iu'
    b'J_2$%c&G!cFV|9&&U}arf>L-YACU~x^LW=n{hH^~i+`!bc$A~MPGvCGdsQRD?R$*6pvdzmIa!wts1(ak&Z)?NeGC)S@Tw&+&%bPU'
    b'#bC&_5)LiLr0OgHToT{qXk)RyQooCz#98&0A9p3)8n{<c6!R2EIAQSJ*zGs_yRqH@$sm?;=zCLBBV9_s!@-8>yR=w}wnSO4z^XIK'
    b'0)>D#0ocKYVjd{miqZGu-|sQBVo)QUA~jN1>P2^f?4MXN6Ff>8;y4jnDw|MesLgg`Qk@18Gv-JooHF>s%}+PmPisM|4Ulb_SYo9N'
    b'14WhoR-RVbM(ytKAyt~o+87s9A=qrw9g<o=f0e(CpBKB@Pj-=g1)5uuPXIhA;M4@z;*3EGM>b%hg$Xo1n-SzqqZ8S!^+4%K`enOo'
    b'iIPoE7RpCbCY^#|;Kos~;)o2%K+rqHqqJ;VNK5jx2GCBYlIe#;k&f9{r-~v~D;n!GWr-R*Y;x$_L~i6l0fgyO)w0cy6tD^8^>Yf-'
    b'oL*5phA)o>UTv?h?{BD#4;`~73$-(8z0MK6_uZ3u2@JQ!XMWzWkg7GLMx4o{pmZc?m2it#ZOFPkT6hg7yt=wx&$C&Ht?a?+kcY~n'
    b'sxoHu+S>?WgC%>SoI+0>LQkUZO-L?RJ2SMb824!8n;~dj`dZB41L0~@jU??eGSpH}Ev0ZeDujnCD5XMoX;OQ=uS7*kc~FLRH2u-U'
    b'e|Ym!jJzo~<;QVivJ5Yqbg9<Ij?|BVoK;Pl!-@1KAWCYZ_`+~uMLt@P%TjY7D$SN`9*v+U4<uo~HeFPQVQSQ)2cPf>vT|XT%0Lq<'
    b'>IL`>vr?r|kr~*vOd}Z$3)I>C7Fe>PLLr&Rfwd}awKl}<;Jv9I(GDMUQ!@;H?qKQ8F;Wf269xqht06tQLsH1%nt#iW2f6&AZEx4y'
    b'l3KwD5DnpjkkST<Hlqn*T^vsLM4#nPIDB?4dugMhhcoC`YtO$8W?4d7%fhZG^`-OlIFSIhWlcHou1W-eomz0bQ!nth_2_V7-FazW'
    b'=?d;Xd;Z(<^XA7><=&(+eMN5=0x5ZBee_W&PQ|wo90D?gP^D#WfagHW2gsId5Py}3_{9>M5K6O{_<FNHNoq)W?Oe0~wd;x0XuK_0'
    b'JQ{SD>LY1kh9XG^BZr7YV%!Tk1#`ffM_c106`dW_NB|`0P9mBP!z?g|3i4MKlO@s$9&sQXfk+9Op+mdLP&1<nD;B=MFSv7QDl27!'
    b'uTH_s`k;6d%;1zy<YDWcqEcgpSyxv*Pz`1R(Xhn%Fp9&9;PrKpw*AQ&BcWl`lwz<cS6D-V3_yyo%iHRt5kF<RIaR98Ba|9HQLPZs'
    b'8crUbY`q8o4V05vO5TC$U^9>+l#c(`7)8WVC?OEcstk}fnJE%(%FO_euuo>*qrNuR<8;L&aEwc>kp|8?(o=iS-1j6CRc5c?CN(To'
    b'Vv=!>PStj^7eLTU8T-Q2YLR5V^dLSdjaF6ofJK)348;l3-K7u*m{9GcQuYKQ!6u2I2_0kn7d9T2ZI59lqjyjmki$$hZk2>pF*`7)'
    b'qkW-^=;Bl)`WR7a<fYF#d+@SQ$`%XK``PYZZEx<@z2fwQ7^Q}ko9HHsAn242lEMNw+Sk#tiZL6Bw8X!|qrwe|1+63i#K_m%t$^j&'
    b'?aI}cl^7C_o)KsXfg%}#GuA>|9Hc1pIH38IVN@&JY_?t+NMIzzNZo3e;_~|DZZ&eDV-ZJ3*d9tHL0Aeu7|cUPg(`?OY{}}DoF#Z$'
    b'^o)&!ZB#C6!BBbjf8-*YJpQmi`ugVQ&2D=msqxi*KXyw2d$QzFBS|5uyN<Ym;-#Ql@JyuO%vCA9a7pMaG+qzn9(1!K@{<F{=Hlu<'
    b'?ue#$u$3=ez%XWm_Dnc9XpfRY-gG?OMu)2oM8~X#a8vvNbwt4zQj?ek%u;xG`lq{(uZAo=uVG?~k`CG`7^#JJ66M43k|NvOKx>hT'
    b'Xm)G>_ORDXogoz!^Z|D-+3=?=i3UilK~!m8yM?p4Xd-&0MXGO39UvsaO3?+uIEsuV=)!D`Nm&Q-k&_4V@aH$LrK3o;uf!-YO*K_@'
    b'P(Ww(AQ4g_ng)%_j0G9mBVg+z1(>&{8e+qe?nPO<NQpl)Ge3gpqd&H5-d&Yn9+G-xNKCV%T!ijn+XcVkcLT-hu_4_wVLJgW61mA*'
    b'YBtoxoG4uIrbv$D=Qh6{Hyg3s#_in+mS-rYpwvKH$5fguCV_!r^emj+XY1yW1fm3I8x@3{_-ic~X**`4pBsEj?fQAVXi)SB0Zj}5'
    b'ffUOjW2!zzMOu^lNW@ul>|=>YUZPS2NVFD_$PZQjVg63z7iCbWiYF(WX-->t)d~M1c7cMz+e>qlAMzGyHnfI>c4<YrLbV+kdB43H'
    b'e_3xGl*Vh3E*55NETmhAL@VSBAqLGKepunQBiXJ9=m>JTOisYoT2xCxdE9FBhx`5WEl)?nea1o*POvu(grm0_JOgMIHOoRG3*#iR'
    b'YcM`aLrfDOlr+>f+~Ckvdo&}=>?NM$1|=Qc?~rezzA{=Gl9I!eK9{PF`bdasT&AQhka;Lx2X~rTTC~q>opjHXoflLRrCmdB5zt^Z'
    b'0B~To+Sv{c!=^xfL*axT8!6h*K8OB$K5?&aemu=C1a>VP$)GM|c_{dR6SQ=`Rm(1zmIMD``aCpn6mbqk3EHkm_^vKq*bH_A6g7dM'
    b'&5KUa$e{$C0O&@oP@zU0^An<Gn{N%)EOZjEh80-S81U%FR^GmQwbm~tEn-Bj+Cn6oL>5lwt0PdoAAsz1*28Pf6e0yJ;Pp!#BScpc'
    b'V?Va=-OaKn#6Z^A|D+U80y!Hua1x};^5U=`m=X~&g9FE@$<jN~p0XV#1r9QWa;KO)GxU-s695is8egT!2iU_Oa!b%X<V#}^c!sE_'
    b'uA!ej6N@x-5!P%Gn~0}lL*I|<TO`1shHh4yLTXa!9aJk~mT@6#1Uf-&Z-u}X0LvoMD1hkZW~-q*WnO@yLdGuA?9H~{U#$Te-pB0<'
    b'{a#_NxFQ9xptr<h$6O3dPk!=fcp5b+N`I<Sy1;fDmwxF1H(zWkL>@G$4KRRFnG51n+Gt|Y4pBAI#?xAjpo|JdA!;3E9A+lGGx{ep'
    b'PonJAVd0AZ`y!@c+1?g(E6+gI)+sR#@%MlNBxZ<iPDFS@iwm#hUr2|v)W9iwK+uCZ3f|q^?ylFS4(=3%9uch;P>>aa8Iv^2t3~6$'
    b';gIUhgfdLXF(lz49wfI21u*W&$k9U5yK)B|S<`5#hisDQex?r8R>YgPveaMV@Pr663mF+Yz;-(7reL!<2i9pwR(i7cVcZE6?B9?3'
    b'Rjsi++0TsphdMwjCtff3M&txEHZ19?Cu*dD9TbRx3UO2|00A6)vh<g++sxBFb7+-jx`Gf+m~t1T(tx7Tg&0LGKnlzi15dBA00K=Z'
    b'BL*lvVR2YVdOOOl{__1O*I$G|Yz}<~-E(9F`4I|LIkbeVvFIr)MO8_IV-hGs8#3C&S_*}Th^z}Ac}t*`{m1v?6R@)e1ym72DHpOG'
    b'{)%RiWjL`>iFpvS_r#+RIu_j#`Kx!8_cDCRP(H-QcU89ByjnM43I)mr1-8QsDgRXB0Bi2>c*>=RxFy&e(i4`W=Kx!wt>9aU9xA=W'
    b'@^=#_Y|7Q4d-=sY3F$_{Oh^&$mm#!K`$$?iv{(ov&KycfU)l+8tO7Bz{ZR|wrnDZLc>VK<VrG*MK6>fwI<Mh`)D+&2kPQ^G3|*z@'
    b'K&pAL!8LF?{4pKm9=bXXHg<jNzI|LX|6&+Iqhqt)ge3dJq?rW0)u5&<EKxG0wJe?aoKRC*0MB}8X@ZSF3zvHN;=bdfN|ROV&_C&w'
    b'1p|&4(mllD-AE=O5|s2t8bcvFU9BTZ1fUS{QgGV+W@;JI8f}8e5#X9s$Q7C30m;h1J^sLQ=ngvXG1B1CK^POPX7(;p4yhb2{)v6r'
    b'N39t_Kpf1lTxvs&QW4!LPEp3L2WTu{$&BJcs?A`OXc7Pue2@rSv36+4pX!xUTWqRGTx2U0kOB#f&!U=)G)E08moY-zyv>DdCs;DH'
    b'+E8)qp?ogw%&&K4-u(d?w_jIq5nopjx>I%>vMj67g0kdmPuZ51dv{J^nu-eHl!g?NDFp;7FO{C#`4i=Nd!pL}1;;5GI;ofwUJ^MA'
    b'hixR5mxl1<Z$yk6&1GaXbKSf&TO);3wdZyomQ>fqqYMNM5r~ePT?nPZ5s-CC!m?h{71RSlC>tO1R5_%grAx;gID$#+h=TjW4tewO'
    b'^mqbO@0WHzRi&E*r!pbR-seQ%3H43ANcS`X;0ldmHCUFL(1yr=SM5mNp6EMu1L)=qCe8(H7$uw#zL;_mxury>fJv<@*+y7(aRiBi'
    b'vjCvV_eXoe2+D4CZ9mFxA7G`+UTMmw8u+?-S%*nIM{0TPZA8f(QCzL-;9=ZkbR#$XqlK@R9XHz@6&s4WW(Wy`CJ=rE-a`-(3(gCh'
    b'?Xp_wTaHYl=XHvRS12J#fJ6eg6_h7D8ba4oI!~=jLZ1e+9c8aKc#P`F3h5D}6Adp5>zO(+9UQ@dJJm@y7_PIB#E~D3$SB6{gb^}4'
    b'LTm}5Q0!7lT-O>d>(eZ<p%bZ7oF>TYNX<}Pg_=xRp_>Mt_-N$)_Wo|XDYvi6HH`Y3a&-k}{<Nmv@F!f_Tc%5D432hEx{*vu<Y#fz'
    b'Zg9g`rD50Lh4E-`Q@Ux8`F6tKO1N1Ab%P^D*??4lHs}HL2~W5=ipGE!f53r&1|V0a*rWo`Ia%fV!Vpq%b8~-+<P<n9+Cxh<5*TvB'
    b's8+)O1dJ|BZf=uwiygMmo0tb8YGE=XDQ&{%=GLev$ZxbB(yi)@3xO46kq`$(%4-+^sB-Y=PHj>#C*9%o=y~atpnMh+yUowYkfmd_'
    b'GH2CU@`dD(olEehVW*azzFs<ez}ut{Qiot`-2z3isUfRW6XI)d=w}uf#=A}XX%)3Q?nWuYsiHv$z}yU!q(P%Af)MsjEp2cp6OlLt'
    b'+UbpK6+s~v*x_M)@L?J1*_o}Q=}N@tfYjCqJ2Td!8{wTn{LQTQ2)Tm(C{MAV%H?GpI7&1&9U!6?&(D3WAvIi|IY>Pwv}lhg4;#De'
    b'r*T=r2w*`$%N~~~t?I+ZX}(}&m9P5xnT2=b=7i)0Ss1lK*ofL745sKo-$<bZ^J&C#nLW!95$RQGS?G{mX2?e-t(-9Qeh6f*#eoe&'
    b'*87x>N}<{rBD6CjIaE_cQx3AM7kNd@lc+_f(nW{(DF;-%o1fcTHb{;B7Ou5lRU#4$#FqsgK^6E3F_(taa}}XdOfA~27Hg<N(wxGF'
    b'1!@GR3nPRR=9cBXQ`8HAU11)kirSDJB&c6X(I`;M=-@=P6OcW~COBDRbcu>&fTltb^Y!y7J#{MZxU3@wON-M$gcAiLP&|<3gtzHk'
    b'dgc`PW}WPFNpn`z%s_)h!<XPkpAYi=rhPoMKI-LY1W@jiD$<M6#z#dW^R%EdlRQw{<Sc?!p}rcVX@Y;UWJfCM&m;fCUD>TS&xQJ!'
    b'zAS^`zgQ-+J~2_$-)w}YRH6_O*R!V1QcV2xU{UL`2EZg78Cr;?Slh083%<aUsJp2Z36})5DyoR?AJL<PlD8_rj$vO$c74enB}y5p'
    b'Jf;>tH}r-`e6_t@Z7)tI`|2(A01Xc+q?*iOmrjzMIYHWs=wTF^$<TiV@KQIK>8u;t@5t0cp1mEPUVSXL>r+U%=zxvpA>9uin|KBU'
    b'3Ez)G9Do;vcY)Fr<UQOq*@>7HrYZfI@TIw@gO_WgL+*h=#cRSF_G?k&9)(kUMrCFy`tZy87(Z!-TFk6B3*bYS2~U5*-1EbwN0I2^'
    b'Uu}p~Et7g5Wg8jn!kVeN?3N|DJjxkD+oN)5z!(NBbT+Ww=i^9x8rJKZ{>Rk<$&^9l5YHlKlcmNwxMt{R#U{<d=B%hH@0ib-gjskr'
    b'5t$C`@D^p&+Bcis{_cc5s?%6{+*<X95v3@-p;6JvH%2$*6oAv6c~o#2J*h~H)@bQR6tiw`1s}8Q%$Qoa2zyOdcHM!A)SZ$MI=P?_'
    b'2=xwuD_Fpz(u607!Ify9MgNnXH=EwC#`?fOa%s;QUX>~Wl~oXnP_3QBe&iED7I-r@2^|o)4=LZ%!0ADPb%QS`)99<xMs|$2Cb$u1'
    b'mtDX<<zD<O4*cj)QWQj%k|R@$s*_!yCQ#+u#oAftSF*Zub#;ocjZ}FIWCP*GG%c$m{MRPPv>YIqsCzFvBwX%!>3hlM9*Dz;OheAA'
    b'Hcy78?Avp)CKiIM8poI&${Pw5vYcz{+Bje3xM@aj%UY5f&hZYuqFjR-tJYo!%``Nk8-9rZrG9~%WuSpDjr5j{Jwtk6Sk|(iS~X-#'
    b'=3^LA@!;wDjIJ_90Eu#}fW)MWwQ#dK0>T8f2SO{z+ki1Z7Zkh!h9#RwO{5yCq<UDj^HOMP*QEUp>?+y!Urj5rsh~MWH5FZ%v6HQ2'
    b'Lt$ENNV1a>+!Wp4hX35)o6$Gr!PJNQTRB~P)Rl|U+C`n>dD&Xrs<c||5N=&@CM3%x*DY}(3&ILYL8=V2A&8<54WMIVzpVmX)%)w$'
    b't6Q{W1pubiLYJk~GDv;?B1BC0P?pZ9^aC7}wF3YPHZ$a9LwToky=Za?m^C0PNhw*CnYqcyGX72_Z<1-V5B{lAio~r_4ttT66$SSt'
    b'GpPQlzi9N}%~c6NiO#ShZMDV{vj+xv*cAjx8$<_{2}OuPAF`8!=~#L!Fc{s8il?luy0Qks(;?5RlU)`Fm#HaDsB(~Q)~*>>aHD{3'
    b'tvmR39K(Zvq6I*Kamv^q(Vy#{6kS0PgOEd#gX$)A$Svqxq_@+^b)#d|@;0cBM*V?#jy63+v+0yxvUtjo$N&gBbj-+RX#=?<9}zQE'
    b'T1C_kZDspcCwhaPilW}8Otus#XwK*_**xjTil#?Wd7`mRbS5lvVbkb02Mvp&;Y?3n_O2@F%gL5P;~XK22%FE!;C;Q8lVIDMubS*;'
    b'z8d|<>lgQ^OAR8|E4<o;60IppOK%?!$0^6SMfeXnUJ;~&P`!9`@@H4FCKmq*<EzA%`b*BC^F$kG>rHh`^BA(Pqxa#hZlz1F2Sx2<'
    b'haQ9#2m}kAeJ04BtiJwv)1^&w=tF-I!H!a7q!kFqZWV285;cs63Slg5j3!%es%-W!x-nRA3chU<=pakii_PV5!{egli7r57Mv-*V'
    b'JE??<x1JbPmHIVewUvlcP&!X}OohnJWy)?A)wC(m1A<=~dN|pzxmxGIplP9uM5u#Z_K3)N4v;8ExEoAdBGxPAhiqJkA;T&M)maEh'
    b'f=HStgVI5HjM;y1aH|Vfk>o(Bi{eZ*773xcEW+nT+R8pvyanROp>szqRYnj5IdE+B(cstPu57N>#us4^G0UmAi9?*7_{((J(jCbd'
    b'Zv!f}NY5*Em<19{6{Jp=!#U18^g6`U{^Lt4Bgq5Cwt14l1jz2_gV}UG=_b3w=iue#)EN}D7Z3u~tEI7Qvm&&bJ2E3jF;9qf&}<sn'
    b'C>}vhIFsy+bveccNEY%sMTA3>Vw^o-1W<$TT^LgV0S?<#-#>OF(M5OPm;G9!P);w$5kSjWRkfkWVZmkjKrUo(-BX3+kd!HvVNxe>'
    b'PLg#5#Dg^Bp4nL%g{up1=%1|XkPXPPj?kO(vIo66+3usIzow!EF69sxl-JBmY+wv*(RpZpF!LiZR<2I%_Cs7{t8gquD?$7%oP1O{'
    b'Q3vnDV<X3o*ZE43?Gnf=qQe#0MHtL)Q}*L#e|Old@Yk}r!%KHdZ{y1aGHIPdNGN6=kQF`@li(jIBwKt^msQu%wClJA%)*3KvbLKL'
    b'M=qVR_JyHPd1{eu5da*ysdE7EhcwvXnqJGs(Ijo;A=}U3PCX(oO>e$SVJHVf<P3s*;eB6NkgHJOH=T0gRLm+u`k*=p5^1wGOH{O>'
    b'Z0&p_Ya|}J&s9Via3}Y*EEcxq`o%uGZ?aURs;o`SUOiMX%85=XP$|hFuioLr#S#>VSj01oofwP`;y|?)BOgWq>4>tg1mbR%Rq=1v'
    b'H+uLuHQ=qOf*>}rD|@9hISOq=xLJ~CIcy|rV4ch*x5zRD)9MAnUY?m-JuEh7G_u20RRI9mZYvyy^chW56NO<`(w4OJNX3$slA}Q`'
    b'kz(y|Q1o%@z+riRRbC9^B$}D{Chg83!D}cJK8ngwsGUaiwUp;X)xp{bF{NbRp?H5W@^O2+zLiLL6A!Jec;Y{1a@0gQ9%&%q5jH3X'
    b'iPUlq2cpQgeYAu8fqlbV4_k>oY<`rmx_Q{)brPF(lvV^qTgXF2&lZvn4J{HK$_alfwFcYp{IudUL+(&t9X^x6Ew;9YW%uQD?OM|X'
    b'kwk(KtvSf$4a^*zTF$Hxun;jusbiTyGnEJl)e=FB6r&&(2D?=5!+ln3;DUCfP%GJ;fCr=O^L3QUMED|qga|2%*#`boW0)io9oHc~'
    b'!P3Ltp2NdmJZd9*n(Q#L=@}|%Q37}~ibglGWDUFSgTe-Phje+_t(=v?Ybwi0?V6s<ydT1AR;irqq{iW>3_*(w7cNvt=?JAj);IL2'
    b'g^mzLrAtB3Q#RfJ2ouVXFJ8Fz>xivVD`p(Bbwd+W(C{HAk-SN6x!egC@Ni~7NSEFDR-=;hv``X-GH-_qkILF!q3m49+VD*3g|87}'
    b'jWlNNCs^VW6(a;$Ml~%KKf3e|{e;jYIW$^^Jv{nBI^ExW-0s$w1A3W5Pubs4sz-iyn2IaLxPrh>K{z6b074QDu4(vM033m1xSY`a'
    b'V>_~%y4`P1oqyqRL-w)EiJ&#HYshXOgp;14)`+|&2`)zpLB}p<ZplN4h#cz4&qj1;?n*xHwpXjnLhCL^r=WXs-IAG9Bg9?<jsdjj'
    b'rfg7jG08L%5I*1+(<?xP0DuS_8#^pVZ(6zf(`KE)2O~S}eU)vbfl`vhAwY`DIUD{e?KJ8ki5`mg@WCL*vv@T*|Ecq_v89J_^7Jlx'
    b'hq$iRPlvdS%Z^2YN!DsoHnQFtWoJA(SdPOG<fuh2hty$%q*Qut=?-#!R}T9ww!8f*+gNlE$UjTO5po8~3~FSCYj|V5=1nZB-WFN='
    b'lE$wrq{vPqCr#dCd*6M!`S5XE%{4#}wukt)Js>fZG|R|(j|!AS99k*n6;|&jjLHiG8NEr5FMCb#Z{yg^(-QTvH{#?n0Qy<h^kfrG'
    b'Aox?1yqaK~)@}~MK@=x^PWsJ0bWxj=q}4KRl!H39`C;7bw}-tLtKpGFDYk-|#v$-dMgj$t^W`{36N2O&jNKsf(g+>8A$L(hARTh}'
    b'a2cDdect`GTwRS-B9MnOUN-bj<T)h(h-*1SI~~qQ0jwDrq)Yf`1P^P1cneSSYV>~4bB813D^N-$ZdT5U@yMJ3w~7}CZrM{{itJ%6'
    b'6-EjV2-VLl>pr>2MG+>#M(l6Tew?kh<$4@g$Lj950Ux81x*<EIYQvk7QP2u%47{IcYz>#m=EfwuZe+)itfEls#$m5C)AW<9mArHs'
    b'4_3jOmn6qITb6^617uamP(J`4ub_UY0F;3--Y|i|b!WYk9bnR;e6WK%<ZKz*bhSRfVJv7ZGLVO(zl0#zDm9i89rZL>A{xRbTY?KE'
    b't_&z6T8%i<3qSkoB5c08y%iK+6&)}@K&2v}ibq(4!@*L|Qwr%MdsgRwgdz@SlwO;b7HtqM8uLLAEHw@a^>9$?VKwHI1ewXo`C1W%'
    b'a;kI6;yn^XA<aPRlALL>g;olMz&qq*+6en_Q;5akik5YYFJ04M@enyWmi<bp!p`l;LlSdX=r(bO27yoME?0(RR0?rf5`4lN?bS<0'
    b'Pk?QarX5v8r-|c4Bg&#?Y)BH|Liav2h1Nurx12nLV#$t!f*3*wk?|Lw-wS)b3+8+m%=s>u^Ib6KyI{_D!JO}cIo}0yz6<7j7tHxC'
    b'nDbpQ=euCecfp+Rf;ry>bG{4ad>735E|~LOFz35q&Ue9_?}9ns1#`X&=6n~-`7W6AT`=dnV9s~JobQ4;-vx8N3+8+m%=s>u^Ib6K'
    b'yI{_D!JO}cIo}0yz6<7j7tHxCnDbpQ=euCecfp+Rf;ry>bG{4ad>735E|~LOFz35q&Ue9_?}9ns1#`X&=6n~-`7W6AT`=dnV9s~J'
    b'obQ4;-vx8N3+8+m%=s>u^Ib6KyI}tB-v#q<H1u20ZS0m^=x@e#U2R)Lhv$@&)1O2&Br!F_H~6k$zFFjn+)WW&L|_-$#1jJCx7P^K'
    b'2{rWP-kDORNpV@n-0lWX{ia;)hkP)^lb5%LCK35?dA;oJzTAH-l>6nLn%f=Iu)W_eaGar9DkABCC0RG0vR8|glVjtuUm3cSTuwx4'
    b'lcU2;`jHmW5BSTexQl0Z;9SVkVhM6=7FNtdRn0y@ASg>-LxZeJo{|Qn*VviSW()9Gq^QUi_yyfh4()otZTjUxmp>m!wBgyCFv%w$'
    b'_3Qrude@;X'
, '5044904061a0a785d7aa18eea802deebe14bc659e08cefb9be7a808274ecef86')
CLUB_RUNNER_HUNKS = _club_fixed_constant(
    b'c-rM!dvn`168|b_`v;{~kqN%(n_MSxls0pz?eQa>8(XIVfn~%CMXG$*&Sdi4Zvl`Z^>os^OVc}#9~8J)EcUlgz&9U^2;#f|<CuI)'
    b'@arACFGqx@tSq4<Pf3#9L009(`+-Ob;PPpBn@P$fCW92Rft)cU-#jJ0?UB47a;%xJhN)-k3GElsaF*p+!dcqQ<~Ihfivky$t=62C'
    b'b7r}oF&!RvEDDyCK;E#lhDlN6#lSex^OOKQUo2CofGnVz=b|L60FvbuSr$-2aR<U^<i}l;0#a5bcQ7LGu*BVgzzs`L;yg|B`#hVK'
    b'^>UdP)k>0aQo*7eNP)f`5rf4Q6#og`Io597IbTY5D8QH0-NzBxG`;>FZ;aKNvw2eDhUAWC@W5eNC3#jFQ@QaECqKVBom@_iNoWQm'
    b'a&mofF*&`OT}<A*n*1sUy%D*Xyq-L}oZ#Te*_+A5-{r7_wDQB+p!IQE*Ea?e0%fT33YRZ|=b32Mb}f4xIzdAwfQdB8V4a2rrn!r0'
    b'S+Sz3m$PP%>yvELY{}-V5Hp_FS*2h3;bAl<t$s+!^Cd!~q$l@z@oq$##U$@mTEgcnd)wh!KvfqA;tu2flc7U>`o9Oy9ZM6zDwy%K'
    b'j%F!RK@sIrh^Q8Cp&IZJS%n(pnCI0tum?PETjHNr=<2wJF`}$mv54k^%$Y!G@h#&@8%g%Iv#7F8D-4Dr;nhG-7#=XM|AGh@Y-JEz'
    b'uxdU|N}lE=G=hw!&WsaO=1=(@6dB7nyu{db1!YwlBl3g}N5r$dF?B)&D=N{_(x()jJc9FCk-SYZ6!?Cgr-&jh(8wOAxwM^4uiLGo'
    b'9Y|@?8{_h~8iVt%XgKAP^@W}y8yb#j=#w7^rKbFCnO)ZTkg)|Ew|wM>sfy<Esfpj1U_@(XD0651AKP5Bk6_D}w)9@si-BHyd?yu#'
    b'*<eVX5INjHvKk(>5q3@U{_wEsPvM@#b(%iWIZXK$xo0KG7fB^^6iUT1lBYu3kpPaiQ))1_tn%MdcRN|y*Xzz#e}P2=#X5`M@7RAf'
    b'Oxw8p1wq~EMk*YBkdeNsOB~iwUp`Nz5pY@A%y=>@>MVm|w#Y>iC&=)aTopA)k|owknDT(vl^TD^(h^4N>N2#zO^!I06)H~E8g9o_'
    b'&4*H#sGYTxg5=>QzkM(rAH;Bz%dV_>+_{^v`9?yiMC>8Cxl#6zEb7HfZ=jos<AXG3LhY_4x=*V4Y+sV?&p~&>bUWJVnST(1j`j5-'
    b'*g4nN2;qUkLu*Y=y!l`xnScj;RDWA#gM9h6$m^xl@oF8l#*L!HP$q+3GfR=m;0IZ~fC5!IP($T#iiPBX0_4k!@*O!h9e34zwLwlt'
    b'{&GyN=BQp$=5@j0NrZ+a2$LO_tX6c7c76H_7SY!ilNaOLY<BYc`uXhn^^2b-SD0FQ9%6KKs<b}6yt=qPxx!DEXV(`eliBmL>(dvr'
    b'^NX|dv&(0%4GA}f(Yok)2kM}abIX1y4NZKH-C&yVq?+9`{M9#3AK%U)71Cao*d>5=6Ld~RiWOce34@-QmG{XK%GnZW3b+H7N=9an'
    b';4XoC)ntOSYo@x74RR`BQrc@f(PPxgv*q$=qw-50Fs8uI=p|!ZH<tcu2+s^X*9lD9w?p)=nES3L!q|(vSWs{s3w$^9BM3asBHuQ>'
    b'fPv}SA~1d7uvjWl<@qCA@cNa0JX{fUi({}6%ydlGv%?^cJUigrwSfV39Vhg;ZCg>uJqJZIneStz>bb%Zk?&I%1r&Q1-%;*%t2)A='
    b'j^}{zeT$jg_NnKE;0ocoJYc5hn`Y#Ofe98zB~Twc;NS+#7nFk!uyfUyEJ;zhmzbC#E9ZGn#lGoA%#Rs$s1@*7gb>h};*YQ*H+De?'
    b'lSe2}WZ^noSRNXhOHC05AUtqF<Kw6e)1`v8!WFmFdtOIqmghwtCn-E<{N1xmTmW`qnVN$oL&^$eKb@5reh`@!H7%R5h&fSgxu)k('
    b'FOEduLF8M35MJPTA>!?a;9#J$P1~|L7jZyQf;}#@&qW+*+1hZmH|Q{nJ;M_7)RJW-iidPIlBG!u{5{7EhB;#vYxVYcDPQayVRIE-'
    b'P0rZEY!yrTzA8!TtdPM5WHxJDzN4@_vmXoAUPwGPFnFfBvP;|#pI<<QtCw$*GKo@H1Lgo0Ud$YBd5+6XFN)02r@j*k8ao!cCu5<_'
    b'EejnccKp~inH`&UXq(&(fJZE5$m8>{us;zC>np&5?!$ua!a{@aqAsvUZq)u7bJqp@6Qw9$V}3f92|cS60tXOb5m*=s1Jk7e4{bN5'
    b'fYuK_^8()q{2&Y{=bU+zg*e6>7MhmeA%;dbj9oAMOhi2ED?!A191++09PjugDa#Iw3-#h}0LxN7o@MF#msrl02at#(8itsPY!_^d'
    b'OJT^k9S1U7L;)rVlg2KOtuPQF#%heMVQBl{x)35_7{aa3M1s1Xh6MfNeS^C0ZY1bFB(S&Ta}W&}P2f6V8TP$rm@RZRIe<mrGZQlg'
    b'L~h`@90OG7@PJ30nKEec7yukh<p>fwhH!iqM&QJ8$SD>XmKFV3v2Y)UVo#XD7yF$;>-*IUjlc=^^%cB8$|QR%Jh_7TSQ|Mph9l3z'
    b'(#7%_=7NAl6bmz(h5*!ZT`DN!F$OB%!NShwm_VqoBl>>|#7EVW+~VB$cO6SL2RWJm`wy-US+_VW6s`@U-cfBc@tdcl-^d(19=gs@'
    b'P1py3=&rETnQL!7vc8ZMwI@5udCsc&K<!|ppLg8Zt%k-dD)Y3)PEOswsd?mRyX-ZFJ<7xPa8ll8?~A&u)QL8!=GgevOEfs#8|Hvo'
    b'9)dSFcGs^uc^<!))2wec8lnD`Tr1lWH?Pj3TiqNrx@q_h$NF3`Uad4%=K!TN_rZ4MZwv{b=a5E6?WAr&rP#MfJCI9{<;G{x`%0f9'
    b'qITPD9Iu~O?9gFzC!nxbNAK&sbkjp)XdpkV<Y+Wk!GpBcL4VuEC-rGVEwN-U=uAbP2^BDolT4tG4hm!N<6`&^g;AYxvJvZUZ|{G&'
    b'y&Yi0k!<v~y~Fm>?sd)J(I%Q5ukL|c(`dD*!j`<9zLB9sR=KjSlEF*=OgG4N1X2^Q?Xc80)!&<>>_Jk=oGgE=<}Y&HV#?W4aa3J|'
    b'DqqzTRli*QtC^z?tt9QVGx20Z2GR&+$hjY`AFZ^8-Zq3Q6Ytx&%JIk)5h{Tde7*&cHjy!uC@QGM<VjXx+}=hvx3}f(?dA0Q9~Jq>'
    b'7PU2t)+;0>In6VDr>9L^jgQs&&tN!)jOPLxJIB4;>`G<RPdEHEV`wa)$5C6p+Dyk%+Jn4(R4|W-0&(3~Zj$L}%OKVV*#my=cz%Z&'
    b'45hh)q9iFpea??$OHmzFP%N6vO)&M5CiM~2vOIhF3ju~|(@XT(@i{Br%G0hi#b|=BGt!>?klx9U;#n_Al_Mk>ks3#?<+x+DN{qP6'
    b'P+r%_9V)D~nSYNN7C*9wZpuolPxZYAha??ze2&n{hd7U#YX&e-aIWfysk8-ob)w1$X%OoD?qWh+Cd-j^;F}8=HSy6xL-A;KwV%!5'
    b'LPYTh&HdANlqhPBW3EUJ)hdd%uj)<y2g(>VclCZhi`^4fn9AGO_PLj9RD@bH>HdERv=jb{$}xwJyQlQVo%dH#_CnkC>Na>4^u}z7'
    b'{e~E{%k^&jR;T&;zl3P0^eso%Jy*Z>{jEzp8L-Bxvl$ruK+wxcC;Du5U??WR7K=8}?l}*hwvz3gxW_j>p-xh|)EDY2qmrEE;qsFL'
    b'eyh>%iOzGo|G`DeCGRAr{{o`myMF'
, 'e7b5e2559b7d327291c6dc2a4da1ba30b9512fcec28dfa65ed7fef951ee3a93e')
CLUB_RUNNER_AFTER_NORMALIZED_SHA256 = _club_fixed_constant(
    b'c-jTQ$pOG12n4`#{IZ}N<rrl9FCjCF`^haJUPAJIS3@nK<znQaWz(z!g=rgt({;88Q`<e(4@LPAcK'
, 'b97f86e52a7759570c8b340898e94836fe7e8e9b09da1f95b57cbfbed038e2b9')
CLUB_PREFIX_HUNKS = _club_fixed_constant(
    b'c-rk<4OiPpmi;Rlde5;vG2~;C=^lF7Jq~daW(cqbdV3nPI<hT;5?l64b`qvH|9#)952;Ej$%a6hB$v~t1GZH4>V4I{uS%t}-y4H)'
    b'JWImHw$~ViV{dpF4&Q|%f4EGNFkUp1;6vL>X0t_WyB~Y>v$3(!3xkmtOeS71Tr7i$r>^w|SBo(9X0aE(50fizNSCxd*}NCTSKeim'
    b'E@nwI<XZyjXp7pCjdBOxj&~F+E}Nn=^>O&W%P0w(;xq4|w|jVS((CM=_(z?S*R8FD<nTqO&6c;b;|W>&js56-n8`Gp#fyaG^hVKm'
    b'944tZPG(atUC!r|C>%+V`;9_>qv#?`7g@Ilos+#^y8cn`@bBH-lfA<ONB=?q678^OUe`PP@3Vd*7%#%aPcMTf&;HtPoU@F(mqC0%'
    b'{TDPiPiAk!;UXd(rn6--3^UOd$(1sI5Of*GVL}>P#zK=LpJj>SFim}VV>1pGqz7%s^7ndhz0-q(ZqGF$)pPi97|s{oFTrFPc9Ue5'
    b'ctPrg{EI125T&8lNz*W4>BV);bdfa0g`^#!cJYV2X&%KX$)AK<<0u}Hr!<qnM)N<Xt^di4eEhmY3Zskqjpo^-&A$bk<MZGD`t(z)'
    b'-}twUw$eeta+5G_a?`>bk6F`iqBM=-i-$=#4}%4%T<cotkgl$>zr2E!GM@ybF>d$l5t;9K=eX+^#M}zw;cOJL+PG_RiBhe+pq(p='
    b'f5-)FIkbNc!mC+4@}fmb;=GT-4=l2F;yPi253NiH79kV2-#Crm#j_7FwKJVh!bLecvPR#tl}Y7q(^<SVnFXU%G;H^%dJ)%}fp;(?'
    b'Z;WR#NBG0hk|Jyv)O8k22Fq#Yp;0_vE>hX5N;&GXA!Uu#myN=7m_&1SzttC4MEY@e|7BHh@4Y$N@4o3CoODEJS6FqQbY?hNFq*Re'
    b'Q9N7uM}>VM#;3E<a>CkQAx>thXhiz;!;h3+;$Wg8+h2raW%@$2(pIgio6^Z_Q4x2Y7jO2Ck9lY>_YPildq=&!gOkeWvsyKyPxK(e'
    b'kCOgK_DFuXH41azboNz_5S1j$$|Tt@!epLA^eK0csW6@;Q_{=7=&l_lV-~-Ijp`w8cn>m3>DR#qeMECt%^m;F#`zC%*<-g;<+9X_'
    b'*&L>h&U~B^e=?=92kh3_D1DkI#?d6Cf5T`RT;$oD=AM^(`(2k0%Ugf&PA)^z-$&|j9tgEw2I-|RRrrx}4Cyu^A(GjLltPAPWJ*p8'
    b'5|M_t$s#T}iE?sj>lQ~ObTXycg{})37|b|nk&L4yPrS2f5XD>i;=Oo8nV9~^)14GRM5&w+=%xitfQ%r>%1M}BPOexBvxIu39L};*'
    b'+n3>FPQj!aC4fOqEiT(Mf;rty7eujl)ag;M`g;dQr&*GwflWyl#>6$HDUlQ?OnMp{8CPe@$#S5&lXCVOUNjcnu~GYt#cVc7AM$0C'
    b'bqL=~X{sNQ7jV+L@-tIz&9CUra6+?WZgHt_r3Ff&vWIQDf_#v>$mOI+4@BI~gD7FUQ#g_6lo-`~E)}5tfd6vZpMSLcq@?bzG>Iu4'
    b'5m-6i)*VsmBoLQ!b|D#?{As&%^%*xqGmPlX00VX$@Vz1ev~}8A>*^k*0P0l!=Ifb4O))BUiE(oB`knjRt{H3Q5j@0~y~E$SI$wXP'
    b'^BC(&hp!aIr38{nC=9TiyeRMgi+p+#24lm(_SnvLJ15;&hrNILujrR^V<xb^aLop~g>1?=Uw0m%AR|{Lq)1c71^es;&mC@wT1E9y'
    b'mSD{ZI}y?y6U16lTZ3RRyi}e^@cP`L%z}ee8&h;*`Iy^!6*3Ugr{s~N@6~p#iJ>YZ(?vOmS6!B^To|&U;?DlzD`~a1w|m+XiR<|A'
    b'w71)paaO#<_%pL24O%Iot-V2m<hBNbjkYJ*$i1X{B8dh|nndD-fQ}BaKny_)K@33*K@33*K@33*K@33*K@33*K@2~S7=CJd_j)N1'
    b'+z{Ll+z{Ll+z{Ll+z{Ll+z{Ll+z{Ll+z^X~Uk5Q1f;w`rn<(a4c`YIdCJ819CJ819CJ819CJ819CJ819CJ82qRYs6WkV%k9kV%k9'
    b'kV%k9kV%k9kV%k9kV%k9EK7n(f=SxntGVyyJQG9{L=!|4L=!|4L=!|4L=!|4L=!~wn_IP1Jfg%9826cMb2=lMHj61AbC#E>YZ^`m'
    b'VM5cw{K}gV^qNNh5;Iks<)N%k)3msH!W55W$hqb%;QtJlQa;OZ|DOnWl!!@AUYa=?mIL>)fxBV0g(#@cG9Ae1V>KzrF#^fzh6hF~'
    b'^5!#xnw?wTDlE;@g__ODBME9pgs`6kl-l#Tfv0vFfMq5|i?NuI@?g4L#_u?Ul2G{PNHgYMxAS7}pnH7mzdk+q$FUhRg7Ri{g&om^'
    b'X2Kk0`N-8b@=Eh7YeHhp4rj}F(G*RT?6|^~(j9YCnj@C}?4|P{x2kOJL&2ohpj<Zl9Q%tQt#9S>Sa&l_!e(}l)ii!QTj=CIGFYSb'
    b'o>I~2k4Xg53Iabldq%oIx<I<P2kF8A9b^Hgl8o4iqbqct5v%!fFo^`28w{Swy6(?j%pT<h8cJ<SW|;Hg!PPuS(>!@-Cd0CmLw5F`'
    b'pT04)<qQLdkt9Da+$?c@Wh8ZV6y^2wO_3C%n7m?4CjU9Fd~rEH)i{$z`9ThN%N|80#D2FU@w(CbY%(g-GEsOl?jf*fA?0vVYWsC}'
    b'|42E|HCk79)wZ9pjB>lG(x(|lR<_8KvelAV#V{J<0u8k`*m$vbynFadmsp9C%T>;C)?4xlsVef6SwNmzxWBxRtaFDLi>E3uI$M}i'
    b'Kt66W{<*RC+OlW9SSNd)axCo`DZ)_Rs^x;*6t_L!*4O84wdQGRwMMgynrmzIglcKZBDbclvbk1MDRyF6z#QfE*1XW_9IL*QczEyd'
    b'@T8iDm(`GEN!^#H`zq?h&*iHMGI@n@o74)cQ~u`5+JyFmywz4#w9RiGM@cH8u;1wS;~#Pz_6|F5d|g73-1T|))!qSJMVDsxPXc{='
    b'{k`3T7lk|1<#-%@6bXR7Av5}Z985#smxVar=Q^YB_Z!=NdDAkE7Np?C7Jorw=*JsHf66U=w!JCJ*P@da7lGwSAF!xOv>uJ;m>f(l'
    b'07yB1+uwWc^K#Em&$!|uWR^Ge8(VK@)Ul09Xl9nxZMuj&IZ>-AqqAr`dhpYubB=DITC#K=@eI2nfw{Qg(0tSu5LVqv4)oKbR!jEU'
    b'(h>+oKTulJ&Yy;>7VWGusLpjcN)T1aiX|vgY0XS3>Lu>kU-__!K+4q<HT_a2CFXK(aEJqgh|2mcK@C+ewj?%|^M#aKC0bRh7vL!1'
    b'DBvjIDBvjIDB!5?3`aRiI<-@b8uK(r-igg=+IJ<SVhL2(T?X?711Meuw}w3luEJ!?aLC(pM#p}r>TNsDZ5KlJ9OM;t=alC)sRv`P'
    b'3x5^Hqx3_xxYQ9)PD(-t+ExQ<X%r+^SvRCDx~=W`DodvXk91dg`gN9JrN3m!fE?%L-miCDi`80@V%s&@$}M<O4@v_W&MTK(Wuqjb'
    b'YJElFHN!Ra`+TkgXq>~V!!v8_QIZ+6FeD9YR*1efo+)Ikbu&!9eV``I6hox8bnN15-&~T}-9LR^qef&JWEy0eFOg}!2SkHpgJgqb'
    b'16YGhgG}>>WSYz^kZAreRD&fiEO}wc3rk*D^1_lAmb|d!g(WX+9RiL5j=EPk>Ka55FbXgVFbXgVFzRdFIRqpHBn2b|Bn2b|Bn2b|'
    b'Bn2def)rpBU=&~!U=(0f5k^&Ivn*iRtB@9;7N8cO)~yt+s*j7_;TW_|Kif<S=kCkF>TQVX_<iHNeNzqe-+E{6YZZyH(Z^d6W#y~s'
    b'B#Pfjj@6L?ug?(YR-%+pp1LU0H6Kz&SBPU%3x}VsKu2OO+wqLUFpaq&NJNuDY<W(m_^6!mc%I-vWCs-U9e)-VpKXWn=)Bdk#wMf-'
    b'<5BLkkEPR!Ti972Q|7Z{Lk7mNY(gZ#SuD>L)_GB>sd&7uBSW*SJaSto#=ZJe{@477TyHjcPapA@NjQ;{>S88FoPX;UTJ7v?dto{Z'
    b'=H%Bjdev<fM{7v0tt>-^45K6~p7pAatn+Q-TJLEnJD_z}Suv%rrH1U`mM>geZ#3e)Se$llhg^34o;sJgWwC`qU*%J8>(8>+o14iV'
    b'Q*l_fv+KN5{l13G66Qf|>S(}KaLat5!54Wyg0PChOxF4A1`Tq)KcHX$6PRU(*k_u^_ryBWzdA|2_E}wZs(x{cuyv-s_5Ks{g$6e}'
    b'CI60|xKL-(7ukf#tP981uin{g9YueW^YyDX@EcpOOOyA?BcCtAMYBL%TLn7H)Uha(eMF;_h)<-C7;lL)MLoqxD_;Yn9k0;)xubi>'
    b'%Ug;99Zp0R7#3efU`xh3|JM@7;M%4@Ihp=kkqEZ2LDc#ChFtDrvke4rdUSNyJE=J!d)*_p+4N$DGIEJMMY(6gUFU!*&(n4&dqwrE'
    b'AcTFMw@adm%%?;$v7HNft|yu?Q)F4&4T#M-W!-4b>2t-)BusqDS$lp(Q$aZAU##=@jYm23^>yJtpUrO){t6J;)2#}4J_!C6yt#G&'
    b'MPJSkmF~r9Tb1*TmWviF%-W@Kcbv#(Gz(Lc-_(|Ri%*VdXRjzR-#^k*{i3loUMS{#y$|RU=o9D@=o9D@=o9D@=o9D@=o9D@=+m|6'
    b'(^s@?1O^2L1qKBM1qKBM1qKBM1qKBM1qKBMg#{?kC(tL*C(x$~`Xuh>-SFx~#3I@G`Z9YO67pI7mP3{8xV_?$C1M3Z%a}&^Z}xfJ'
    b'j-EL_f#HGSf#HGSf#HGSf#HGSVT}wV4<rvH4<rvH4<rvH4<rvH4<rvH4<rvH56gI9cwl&7cwl&7c;7I?tA8^kXdY-DXdY-DXdY-D'
    b'Xdc$`!1TcM!1TcM!1TcM!1TcM!1TcM!1TcMu%L$pJ<vSRJkUJQJkY#vlIHnsPrjz8{&h{6#Mb+t&I>BkE$yhGww>t8n5RZw_++5O'
    b'u6`#ISS45`SS45`SS45`)(=4}K`cQmK`cQmK`cQmK`cQmK`cQmK`cQmv0RDeO0Y_>O0Y_>O0Y_>%KObKGZleUf>eT3f>eT3f>dI)'
    b'61)<;61)<;61)<;61)<;61)<;61)<;61)<Nl^~TMl^~TMl^~TMl^~TMm8R{$DZwehDZwehDX~^rTB|gj(FSmCa@nDoVWCYEhaY6W'
    b'ZI5TyOho#_<H?qOji%G(A{Y<=VIg%7Ik(hMvfAmQv1hATep#<vD{~1|$d0@pysns4E+ZC|;J{>a7Ei7+$$qAk8V-q$_!--jc1~?5'
    b'vn4xN#m%ofV}54H6axQtgJ#Xtf30v?$Cl+Z=Z=6p&1J!3#LcJ}8=~uqVhf_;v!bF-xD1w7%T`lZ%4<;9C@+PRG&GuDGiEJ26sf73'
    b'>mthUX_PyrKSlm)jB13p;fw2pcP{bpNicTAcU^!SbWZku>8=;PuKXaQc|M7Tl#(Qc5>n)`EtRrmr<zfi4wGokxNx<n-<JGF`cVQG'
    b'GmwhQI3yp>Nr9%PY7C;joAsQ<)bZJ)^BXYMjJBxu4m!Vxa5T7pbRO^Ybnk@}Q#N6RU?CKmJY}fTvYo3OeK`mq^?o3G)mk_R-bWXb'
    b'4$FeRB7;>DR9RSYkQd$K-QM1jc<-sfP}`oCyyAkwV9e26i_sQF$0;`>vLZ=Wj!#>aZcDCcXtTGJk$9A{ijwzfx#!{EySrj6>xpL<'
    b'CA5^&a5@N+O%6XV@7Sup86WR3L?Dejv|kp>R=)fDg6^GW&--s(XZ!}8RJf*MtVQBsb?(TrD+X+cTPv^3<~0V(<`0qm41rawI%kb*'
    b'xYF8^DK{8=6otC~T2i0U_-gATCr<9+q3ULfF5zGM4ZZBfrSnxO>x}MFU0g2Xcc~%R^I!d5_o%a{BT#&w2~?Gz1|O@_Q>n?CEEUAF'
    b'Sj;wb(~1N|BQ3Xejc!HdR5qf=c(%!vb@5kgTeKy9uMBHjTn(wXIvl5FsiZ>GN=e<$FbXHN^45VVy00|Rif#}8+jw7f=KVC8UPN&)'
    b'dGhFQVrcADPS<xsMx&FO;-FaMSuwxJwri%r+buTgrINz5qRV#571ydLRwpqzChp3vBbK3pSz@cLW_}+2X2)8YF<dz5d`<jbjqciR'
    b'%x)pz8xV5fbl`O0bl`O0bl`O0^hL9Bm(1X!fv!p*9w;6t9w;6t{tKaayWqaTK%TQSZ%_2+fw}M^R$P=9UQA{Kirwr=v3&h;;Sb5f'
    b'*df!}{m3hJ5jS4vz*^%Kxs!O2hLf>3U8ZtmgD~G&tOqCKk9VtS+2kjw@Y-~dl=pEOk`WAdTp~K7MvG0VJZN6){b|SJkjp<Y;`Rrx'
    b'!*HhpnCqdAX44>wS0QxSo?d8TsYskePQvupgj_*v>thmi83vQZ<&`(#$Pn@xOL+EjVTP(}m+Zu%YTky#F+5R{6E2kY*hQL+KQ~$x'
    b'yP1RdsyQ$3v7WP{RfFscdiykeYVfV6KW>Vx!b)e2mc2h*>{Vq$&bNv?cw6Oe*y{6qgYYLqIeNpXNVsdLCcibJP@b}BvR$)HW6QdI'
    b'm$mg>$ZyC%!l@zccqzFsp`(|3`!XGLe?9T{4vtPwj$7XUiEq_pnCBY(g-Rs5r@dbHz`W~slZ9mWwLKc(VbA)&UI+cOZO`rG+>?p-'
    b'?5Q`uyh??UtPSERr{p0eWslw3dXV9vc#46XW0{6qcBAE8#9FV8X|Xh&@GUz#HFF^OmxAOE<!)*%^0TLwe{Fk?nIoLs6VsF}A@&GR'
    b'O0gDXA3pob&)!rfj7>FAGFOzUOfv|E?_}n<4I^ZrX2-EpL#cILsM0nAv9;RZIW8!e*T^7JA@|b2>)7+@lZVfql+F2<FJaCS<Gu&x'
    b'6#Doht+|HHejGe|TsGO0FJQ7Ns&Ees$4a?lyOm6HLjAMW!;*;@JwN?hTc9XypvT^ah^A&`H#M8xvVk0w=N{NbYGZ|UtQ}j{(;jQs'
    b'%nkMhz-LN9I5;!X(;t=U8!fl)S?lg@>UE!l^C0>n2~GQiCX==M+4WDgc`|N9=u|y~=de&lh**5{QLm=@W(`2A)(jM<)f?a2T$SZL'
    b'cLfR|9#xZ#>x!))l7f^;O6gn!u^u$rcG*SSqiqO3FV_Auc<*+GPsQ>JS7_*Jx}w*S*Klp;I1AkJQ;fc<SNXy>3r|ak2HU0;@`s~L'
    b'J)h@K+exJquQnebU^f*y&mJ_IGetb=h$*O08OR=LDz>N<qMOW#eiBC0;3911YBjHQ7LLqEzB>Ddukuzav}0Y@_VoODe0bX1?FyBb'
    b'E;0UeJdLMY7KM_hKT<9^lH>7IIU;*{H6o`P^W#5Z#vCQf*16<ec*POHlu>HHDi9bYE<JdzbBOH0cNWV7s(V!gSp>;ND4btB*3E$;'
    b'zi*aqXmfM<lP@$PULd`gC0CotESPSp>o*&Dxk5>@T~mwk9_)CJ)#H4H3dR|aSPE#2n5`%;unI;ZuBETG)u=X%MPSs9P&-2H2(_bi'
    b'YDcPJ^@zdYi_>iKau6v|FH%dUM~|L9Q@UpaPZL)vo@sENka3?1OT755<MFGgDy>oQD^uL?$>8C$r$38>IHGb1P$ZeVrMjh6*L%RD'
    b'q*hQ&L@^P?L=+QIOhhpe#Y7YnQA|WJ5yeCl6H!dm#YD%$-|Qy7pz*c)0o&f6E6#gZj-rKpl0<AXmvbZUQZWzG<Pw@FV|rr}{L)c4'
    b'TXn={cHoYhJD&gZgmOh^_jT7e6NtC$J*NR}Qo4#$8s^jz!*;Ou;ilSGExjv0I#W##*(SdoZ;fL-)xCx6T5QXC7K+I5J2f>Z$JX{i'
    b'^)T&Y5xIUQ9yZzWvNP+9DRwp)31`pUKs#}sXYzScz&qWXnRJX6v(w^U>>ckO{?hIJQ$JPlx$jLb=&W>XoT;Xgeq^rUi~A-fk>lsq'
    b'iYLsiC4RvT>&C#x(K)neOdRI1OrL+oq6KblcF1DUds{UcR>w@5&yl$GtNLrZL%1;QW?HP!o^|zh`M8p|Ddm>QEEuItw?eAU0X>+-'
    b'`4;-ZP)nzPYKRgCQ-1QtYi5xqrp5fg#<o3ES77mVw@h<)=Z3j-0^!dKD4+teR$8;Ly<BbW77g1iT~pQyql<5gPUAQ#wLoBE5>=cx'
    b'IMQ&p{uE8O3+OxZ44j#-It>@}RXRLV$z!>Q98f+qU!K>gC)@fYEH7%cvN$zYRgzSs+<v3qkAKKru6NjZ<G<`3{?<Lv$nAOe)!qSJ'
    b'r61YhpGlx^ufMl@@S<>Mx*QX)5!s%;p}6#YHl^>gHv0|V=ZV$#`;G0sylF|Wj&!-$;xA|n{dl8j_S~pv+u|V-*$LsC2Wq4bSX3oi'
    b'kH&LMDL@qEl$^iq?>+aQcaFP1J>$7s$SiN_H@4o+sAJoQoAk8^2D*r{RHBl?=q%cf9{lv^oKv_^Em<>9>m2Y=eq8k<d0e%+m3-x='
    b'N3E9ZwWTExihiK9=6pbbR3NgDJ4_U1F`i4v;FjYNG1noC0vb{$rH6}w1HW+`sE)^8YxPDLx-|J$YDI-a#TnSf6kKYu1&|7m3Xlqr'
    b'3Xlqr3XlqrYJ*hND}hsiQ-M=~Q-M=~Q-M=~Q-M=aOa({<Nd1aI>NQ>y2aF1g3XBSj3XBSj3XF<cDqt#LDqt#LDqt#LDqt#LDqt!~'
    b'slcefsKBVesKBVesGosRt6nC<*R{PG1PcfY2nz@c2#ZQ9P%Ka^P%Ka^P%Ka^P%Ka^P%H|ufUtnDfUtnDfUtnDfUx%g!dB_mu=Wa+'
    b'3z!R-`z;r1HR4Iax8bn<?eBGfw<o(-a5p=({Kvsq3n}91E->%Qy<bmGNnO3}-@CiQBW&pVQjTyl8{s#Le#f;Vy~#<bW$*Ylp7D2S'
    b'>Tcks+dID})LGW`^?_$yjNeQASswJaxL?&V%DaM@wI1;G6->*TyA?3GPQC`F{GKpnZQPWhr3<;;xQYsF`F&!`Z=kpe;0xdj;0xdj'
    b';0xdj;0xf3x+<_QurIJLurIJLurIJLurIJLurG?f0KNde_kCk6a4&E#a4&E#a4&E#a4%}UfWCmffWCmffWCmffWCmffWCmfDER{S'
    b'0`~&<0`~&<ep|Tr4v$y>ECwtFECwt_MHt8!$QZ~N$QZ~N$QZ~N$QZ~N$QT7<z+%8+z+%8+z+%8+z~VbUofps<(D{2PDz85IzYLN2'
    b'RTRULK>10+)7fY_VZ5xsG)<lnhs!*O(;OU6gXA5}Q@JyD?YCPD2w{vINBM^d{~N?Ka3kEe41c{nUoF^-)xmA-y*b+NzUdyEC}+%&'
    b'y3QV%b_&909HE#y%Fs%x$3O`DRTz)b4-v5m6)D{3Y5XppeTa))Y0|=443ev?C(;?++4g*e2GaQ?(!J%AI=j4dl(r%}?Ec~VFiFEv'
    b'(>PmN1>)<|gMS>Glc#<2j{4hx58{jL?{a3Baw=tri_1V$x>sS~Q7ohs?q=m?*&@lJn$|c-G~Ui6)+)%LwDSmw8yzs=9NStiu%HmS'
    b'2$Ojd@$_zjXqib1BhnbUUh-?cyyA0?9nWUminGV_xG-~>5gnE6ANlJB`77gnZu20CA&DW0-C+^~4nrP89zz}j7()_65<?QZ@v01R'
    b'*qvapb=T##Ym<*vs>_<%6bs11Bn(I-U1t6YDp}=%_+6%+a&LE;eabc1dys_6D)=_QRC!!?k&AA&GJFdq`-;qDC4<jESl>@-x+X3{'
    b'enNgie)`h+>H9`cNKr^pNKt@L$WO>mUuAx}n^F_f6V?JzMn@SPWppeBe)$|$@mx@OJ9xgM9BB_}4`~l+537gZm*AJ+mneVb>FM_1'
    b'6fznz8ZsI(+Fex4g2`Yxy%EkD44!%7Zf|%Q%-MnIQwj|8;E73a72fMSBnNPpxkvUO6mbh#=W-dpvyx3`|M}?~KYJvZMotb@&NNo+'
    b'QZL-jSzk_Y{f2ouf%-;XX?}IR?DK{d8ecr5K%)tY4=NFQP#U1%43jYh;MbXbY}@AEa~HWs8u<3|P2S#`IYtJ0AwsT?p4Lb-w}+UJ'
    b'n~<B3n~<9-aM1bx16^ak5d'
, '1dc205c0cb82f3525dd33b95105407b318f9ccb932166ab0ae2d1b9686bdf52a')

def _club_inverse(raw, row, path):
    require(isinstance(raw, bytes), 'Club source input must be complete bytes: ' + path)
    require(digest(raw) == row['after_sha256'], 'Unknown complete club current input: ' + path)
    require(row['before_sha256'] is not None, 'New club source has no historical predecessor: ' + path)
    return _inverse_exact(raw, row, path)


def _club_readiness(raw, *, current_only=False, preserve_pin=False):
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", raw)
    if len(pins) != 1:
        raise ValueError('Unknown complete club readiness pin')
    normalized = raw.replace(pins[0], CLUB_PRE_CONTRACT_SHA256.encode(), 1)
    if digest(normalized) != CLUB_RUNNER_AFTER_NORMALIZED_SHA256:
        if not current_only:
            return raw
        raise ValueError('Changed complete current club readiness source')
    value = normalized
    for hunk in reversed(CLUB_RUNNER_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        if value.count(after) != 1:
            raise ValueError('Missing/repeated complete club readiness inverse span')
        value = value.replace(after, before, 1)
    if digest(value) != CLUB_PRE_SHA256[RUNNER_PATH]:
        raise ValueError('Complete published e2b readiness source not restored')
    if preserve_pin:
        value = value.replace(CLUB_PRE_CONTRACT_SHA256.encode(), pins[0], 1)
    return value


def club_current_readiness_source(raw):
    """Require the complete new postimage before restoring its member-copy body."""
    return _club_readiness(raw, current_only=True, preserve_pin=True)


def club_readiness_source(raw):
    """Historical reader only: exact new body or unchanged native historical input."""
    return _club_readiness(raw, preserve_pin=True)


def _club_category_preimage(raw):
    marker = b'\n# Exact e2b P045 public-member route predecessor layer.\n'
    suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
    require(digest(raw) == IMPLEMENTATION_SHA256, 'Changed complete club admission source')
    require(raw.count(marker) == 1 and raw.endswith(suffix), 'Unknown club admission source boundary')
    prefix, _ = raw.split(marker, 1)
    for hunk in reversed(CLUB_PREFIX_HUNKS):
        after, before = hunk['after'].encode(), hunk['before'].encode()
        require(prefix.count(after) == 1, 'Missing/repeated club source interface span')
        prefix = prefix.replace(after, before, 1)
    slot = b"ADMISSION_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
    require(prefix.count(slot) == 1, 'Unknown club admission fingerprint slot')
    old = prefix.replace(slot, b"ADMISSION_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'", 1) + suffix
    require(digest(old) == CLUB_PRE_SHA256[SELF_PATH], 'Complete published e2b admission source not restored')
    return old


def club_predecessor_source(path, raw):
    """Restore complete e2b bytes only; this function never admits a current root."""
    if path in CLUB_PRE_SHA256 and digest(raw) == CLUB_PRE_SHA256[path]:
        return raw
    if path in CLUB_SOURCE_ROWS:
        return _club_inverse(raw, CLUB_SOURCE_ROWS[path], path)
    if path == RUNNER_PATH:
        return _club_readiness(raw, current_only=True)
    if path == SELF_PATH:
        return _club_category_preimage(raw)
    if path == PROFILE_PATH:
        slot = b"DISCOVERY_HELPER_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
        require(raw.count(slot) == 1, 'Unknown club profile source pin')
        old = raw.replace(slot, b"DISCOVERY_HELPER_FINGERPRINT = '" + CLUB_PRE_FINGERPRINT.encode() + b"'", 1)
        require(digest(old) == CLUB_PRE_SHA256[path], 'Complete published e2b profile source not restored')
        return old
    if path == CATEGORY_GATE:
        normalized, source = _decoded_external_template(raw)
        require(source == (ROOT / SELF_PATH).read_bytes(), 'Unknown club complete external source template')
        old_source = _club_category_preimage(source)
        encoded = encode_frozen_source(old_source).decode()
        first = b'\n# CATEGORY_ROAM_FROZEN_SOURCE_BEGIN\n'
        last = b'# CATEGORY_ROAM_FROZEN_SOURCE_END\n'
        suffix = b"\nif __name__ == '__main__':\n    unittest.main()\n"
        old = normalized[:-len(suffix)] + first + b'FROZEN_REGISTRATION_SOURCE_ZLIB_BASE85 = (\n' + b''.join(
            ('    ' + repr(encoded[i:i+80]) + '\n').encode() for i in range(0, len(encoded), 80)) + b')\n' + last + suffix
        require(digest(old) == CLUB_PRE_SHA256[path], 'Complete published e2b external template not restored')
        return old
    return raw


def _club_restore_contract(value):
    value = copy.deepcopy(value)
    if digest(encode(value)) == CLUB_PRE_CONTRACT_SHA256:
        return value
    for path, descriptor in CLUB_FEATURE_ROWS.items():
        row = value['feature_batch_sources'].get(path)
        extension = descriptor['extension']
        require(row is not None and row['after_sha256'] == extension['after_sha256'],
                'Unknown club feature postimage: ' + path)
        hunks = extension['hunks']
        require(hunks and row['hunks'][-len(hunks):] == hunks, 'Changed exact club inverse extension: ' + path)
        if descriptor['previous_row_sha256'] is None:
            require(row == extension, 'Changed newly admitted club source row: ' + path)
            del value['feature_batch_sources'][path]
        else:
            row['after_sha256'] = extension['before_sha256']
            del row['hunks'][-len(hunks):]
            require(digest(encode(row)) == descriptor['previous_row_sha256'], 'Original complete club source row not restored: ' + path)
    for path, old in CLUB_SUPPORT_BEFORE.items():
        require(path in value['feature_batch_support_sha256'], 'Missing club support registration: ' + path)
        if old is None:
            del value['feature_batch_support_sha256'][path]
        else:
            value['feature_batch_support_sha256'][path] = old
    for key, descriptor in CLUB_CONTRACT_FIELDS.items():
        require(key in value and value[key] == descriptor['current'], 'Changed exact club contract field: ' + key)
        if descriptor['absent_before']:
            del value[key]
        else:
            value[key] = copy.deepcopy(descriptor['previous'])
    require(digest(encode(value)) == CLUB_PRE_CONTRACT_SHA256, 'Complete published e2b central contract not restored')
    return value


def club_authenticate_current(raw, root):
    """Read all six actual product files before any inverse or historical cache."""
    root = Path(root).absolute()
    require(not root.is_symlink() and root.resolve() == root, 'Symlinked or aliased club current root')
    paths = tuple(CLUB_PRODUCT_SHA256) + tuple(path for path in CLUB_CURRENT_INPUTS if path not in CLUB_PRODUCT_SHA256)
    contents = {}
    for path in paths:
        file = root / path
        require(file.is_file() and not file.is_symlink() and file.resolve() == file,
                'Missing, escaped or symlinked actual club current input: ' + path)
        contents[path] = file.read_bytes()
    require(contents[CONTRACT_PATH] == raw, 'Actual club current contract differs from supplied bytes')
    value = json.loads(raw)
    require(encode(value) == raw, 'Noncanonical or duplicate club current contract')
    for path, expected in CLUB_PRODUCT_SHA256.items():
        require(digest(contents[path]) == expected, 'Changed actual club product: ' + path)
    for path, row in CLUB_SOURCE_ROWS.items():
        require(digest(contents[path]) == row['after_sha256'], 'Changed actual club support/source: ' + path)
    runner = contents[RUNNER_PATH]
    pins = re.findall(rb"(?m)^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner)
    require(len(pins) == 1 and pins[0].decode() == digest(raw), 'Unknown complete actual club contract pin')
    club_current_readiness_source(runner)
    module = contents[SELF_PATH]
    require(digest(module) == IMPLEMENTATION_SHA256, 'Loaded club admission differs from actual bytes')
    slot = b"ADMISSION_FINGERPRINT = '" + ADMISSION_FINGERPRINT.encode() + b"'"
    require(module.count(slot) == 1 and digest(module.replace(slot, b"ADMISSION_FINGERPRINT = '<SELF>'", 1)) == ADMISSION_FINGERPRINT,
            'Changed complete club admission fingerprint')
    validate_external_source_template(root, module)
    club_predecessor_source(PROFILE_PATH, contents[PROFILE_PATH])
    for path in CLUB_SUPPORT_BEFORE:
        require(value['feature_batch_support_sha256'].get(path) == digest(contents[path]),
                'Missing or changed actual club support registration: ' + path)
    _club_restore_contract(value)
    return value, contents


def club_predecessor_contract(value):
    """Return exact e2b contract; current input requires physical current admission."""
    if digest(encode(value)) == CLUB_PRE_CONTRACT_SHA256:
        return copy.deepcopy(value)
    raw = (ROOT / CONTRACT_PATH).read_bytes()
    require(encode(value) == raw, 'Changed or foreign club predecessor contract argument')
    club_authenticate_current(raw, ROOT)
    return _club_restore_contract(value)


def club_predecessor_fixture_source(path, raw, current_contract):
    """Construct genuine e2b/54 fixture bytes, never backfill a partial current root."""
    if path == CONTRACT_PATH:
        require(raw == current_contract, 'Mixed actual club current fixture contract')
        return encode(club_predecessor_contract(json.loads(raw)))
    return club_predecessor_source(path, raw)

if __name__ == '__main__':
    unittest.main()
