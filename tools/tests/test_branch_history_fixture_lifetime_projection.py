"""Exact byte reconstruction and fail-closed adapter component regressions."""
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch
import hashlib
import json
import tempfile
import unittest

from tools import branch_history_fixture_lifetime_projection as projection
from tools import branch_history_handshake_planning as historical

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = 'tools/branch_history_fixture_lifetime_projection.py'
CONTRACT = projection.CONTRACT
SOURCE_PATHS = tuple(projection.SOURCE_PREIMAGES)
SUPPORT_PATHS = (
    'Tests/ContractChecks/test_branch_history_fixture_lifetime.py',
    'tools/tests/test_branch_history_fixture_lifetime_projection.py',
)
COMPONENTS = (ADAPTER, CONTRACT, *SOURCE_PATHS,
              *(row[1] for row in projection.SOURCE_PREIMAGES.values()), *SUPPORT_PATHS)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


@contextmanager
def copied_components():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for relative in COMPONENTS:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())
        yield root


class BranchHistoryLifetimeProjectionTests(unittest.TestCase):
    def assert_rejected(self, root):
        with patch.object(historical, 'ROOT', root), self.assertRaises((ValueError, FileNotFoundError)):
            historical.critical_source_bytes(SOURCE_PATHS[0])

    def test_both_full_current_files_reconstruct_full_original_bytes(self):
        old = historical.contract()['critical_sources']
        for relative, (expected, preimage) in projection.SOURCE_PREIMAGES.items():
            raw = projection.historical_source(ROOT, relative)
            self.assertEqual(raw, (ROOT / preimage).read_bytes())
            self.assertEqual(digest(raw), expected)
            self.assertEqual(digest(raw), old[relative])
            self.assertNotEqual((ROOT / relative).read_bytes(), raw)

    def test_each_component_change_is_rejected(self):
        for relative in COMPONENTS:
            with self.subTest(path=relative), copied_components() as root:
                path = root / relative
                path.write_bytes(path.read_bytes() + b'\n')
                self.assert_rejected(root)

    def test_each_missing_or_moved_component_is_rejected(self):
        for relative in COMPONENTS:
            with self.subTest(path=relative), copied_components() as root:
                path = root / relative
                path.rename(path.with_name(path.name + '.moved'))
                self.assert_rejected(root)

    def test_crlf_duplicate_truncation_and_assertion_removal_never_normalize(self):
        for relative in SOURCE_PATHS:
            for mode in ['crlf', 'duplicate', 'truncated', 'removed-assertion-or-guard']:
                with self.subTest(path=relative, mode=mode), copied_components() as root:
                    path = root / relative
                    raw = path.read_bytes()
                    if mode == 'crlf': raw = raw.replace(b'\n', b'\r\n')
                    elif mode == 'duplicate': raw += raw
                    elif mode == 'truncated': raw = raw[:-1]
                    else:
                        token = b'XCTAssertTrue(current.recorder === original.recorder)' if '/Tests/' in '/' + relative else b'fixture.handshake.cancel()'
                        self.assertIn(token, raw)
                        raw = raw.replace(token, b'', 1)
                    path.write_bytes(raw)
                    self.assert_rejected(root)

    def test_other_current_file_must_validate_before_any_projection_is_returned(self):
        with copied_components() as root:
            other = root / SOURCE_PATHS[1]
            other.write_bytes(other.read_bytes() + b'// unrelated edit\n')
            with self.assertRaises(ValueError):
                projection.historical_source(root, SOURCE_PATHS[0])

    def test_mixed_old_and_new_pairs_cannot_self_authorize_a_downgrade(self):
        for relative, (_, preimage) in projection.SOURCE_PREIMAGES.items():
            with self.subTest(path=relative), copied_components() as root:
                (root / relative).write_bytes((root / preimage).read_bytes())
                self.assert_rejected(root)

    def test_changed_inverse_range_text_duplicate_or_missing_span_is_rejected(self):
        for mode in ['move', 'text', 'duplicate', 'missing']:
            with self.subTest(mode=mode), copied_components() as root:
                path = root / CONTRACT
                contract = json.loads(path.read_bytes())
                spans = contract['sources'][SOURCE_PATHS[0]]['inverse_spans']
                if mode == 'move': spans[0]['current_byte_start'] += 1
                elif mode == 'text': spans[0]['current_text'] += 'changed'
                elif mode == 'duplicate': spans.insert(0, dict(spans[0]))
                else: spans.pop()
                raw = json.dumps(contract).encode('utf-8')
                path.write_bytes(raw)
                self.assert_rejected(root)
                # Independently exercise exact inverse validation even if a future
                # reviewed manifest were pinned; a pin alone cannot repair an inverse.
                with patch.object(projection, 'CONTRACT_SHA256', digest(raw)), self.assertRaises(ValueError):
                    projection.historical_source(root, SOURCE_PATHS[0])

    def test_complete_historical_checkout_accepts_only_original_critical_bytes(self):
        contract = historical.contract()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in [*contract['critical_sources'], 'tools/branch_history_handshake_planning_contract.json']:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                entry = projection.SOURCE_PREIMAGES.get(relative)
                target.write_bytes((ROOT / (entry[1] if entry else relative)).read_bytes())
            with patch.object(historical, 'ROOT', root):
                self.assertEqual(historical.validate_current(ROOT / 'Tests/AppUITests'), contract)
            # Missing all new adapter inputs never admits even one current file.
            (root / SOURCE_PATHS[0]).write_bytes((ROOT / SOURCE_PATHS[0]).read_bytes())
            with patch.object(historical, 'ROOT', root), self.assertRaises(ValueError):
                historical.validate_current(ROOT / 'Tests/AppUITests')

    def test_partial_adapter_deletion_cannot_fall_back_even_with_old_sources(self):
        with copied_components() as root:
            for relative, (_, preimage) in projection.SOURCE_PREIMAGES.items():
                (root / relative).write_bytes((root / preimage).read_bytes())
            (root / ADAPTER).unlink()
            self.assert_rejected(root)


if __name__ == '__main__':
    unittest.main()
