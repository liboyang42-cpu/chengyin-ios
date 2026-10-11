"""Rejection-only fixture preflight; all acceptance still belongs to old readers."""
import ast
import hashlib
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

from Tests.ContractChecks import test_category_roam_registration as gate
from tools.tests import creator_shelf_refresh_history as refresh
from tools.tests import creator_shelf_state_history as state

ROOT = Path(__file__).resolve().parents[2]


class CreatorFixtureRejectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from tools.tests.test_creator_shelf_refresh_history import TEST_INVERSE_DELTAS
        current = gate.creator_history_sources(ROOT, state.SOURCE_SHA256)
        legacy = dict(current)
        for name in state.INVERSE_DELTAS:
            legacy[name] = state.restore_state_bytes(name, current[name])
        for name in state.STATE_EXTRA_INPUTS[1:]:
            del legacy[name]
        old = dict(legacy)
        for name, deltas in TEST_INVERSE_DELTAS.items():
            raw = old[name]
            for offset, after, before in reversed(deltas):
                if raw.count(after) != 1 or raw[offset:offset + len(after)] != after:
                    raise AssertionError('Independent original fixture inverse changed')
                raw = raw[:offset] + before + raw[offset + len(after):]
            old[name] = raw
        cls.five_old = {p: old[p] for p in refresh.SOURCE_SHA256}
        cls.five_refresh = {p: legacy[p] for p in refresh.SOURCE_SHA256}
        cls.fixtures = [cls.five_old, cls.five_refresh, current,
                        {p: (ROOT / p).read_bytes() for p in gate.CREATOR_FIXTURE_INPUTS}, legacy, old]
        cls.expected = cls.five_old[refresh.MINE_SOURCE]

    def setUp(self):
        self.life = tempfile.TemporaryDirectory(prefix='creator-reject-controls-')
        self.addCleanup(self.life.cleanup)
        self.root = Path(self.life.name)

    def install(self, sources, name='fixture'):
        root = self.root / name
        for path, raw in sources.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        return root

    def assert_old_chain(self, root):
        with patch.object(gate, '_profile_parent_inputs', side_effect=RuntimeError('complete old chain sentinel')) as entered:
            with self.assertRaisesRegex(RuntimeError, 'complete old chain sentinel'):
                gate.creator_history_root(root, live_root=ROOT)
        self.assertEqual(entered.call_count, 1)

    def test_all_four_fixed_git_states_and_legacy_six_require_complete_old_chain(self):
        states = gate.FIXTURE_REJECTION_GIT_STATES
        self.assertEqual(tuple(row[0] for row in states), (
            '334b93752e26bc4f005f7aec3e5bc3fa89a15947',
            '6ae3e545b373dd5cddc47356a57d0cb6ee928e70',
            'b75f7549678caf51a65ec8942b6a6d0c23e887de',
            '7bf858c23374b808c6d932367f96e97d09e9d799'))
        for index, sources in enumerate(self.fixtures):
            if index < 4:
                self.assertEqual({p: hashlib.sha256(raw).hexdigest() for p, raw in sources.items()}, dict(states[index][2]))
            root = self.install(sources, str(index))
            with patch.object(gate, '_profile_parent_inputs', wraps=gate._profile_parent_inputs) as entered:
                actual = refresh.historical_pre_shelf_refresh_mine_bytes(root=root)
            self.assertEqual(actual, self.expected)
            self.assertEqual(entered.call_count, 1)
            self.assertEqual({p: (root / p).read_bytes() for p in sources}, sources)

    def test_current_root_authenticated_context_and_path_alias_retain_old_chain(self):
        context = gate.creator_history_root(ROOT, live_root=ROOT)
        real = self.install(self.five_old)
        alias = self.root / 'alias'
        alias.symlink_to(real, target_is_directory=True)
        for root in (ROOT, context, alias, real / '..' / real.name):
            with patch.object(gate, '_profile_parent_inputs', wraps=gate._profile_parent_inputs) as entered:
                actual = refresh.historical_pre_shelf_refresh_mine_bytes(root=root)
            self.assertEqual(actual, self.expected)
            self.assertEqual(entered.call_count, 1)

    def test_invalid_complete_fixtures_reject_before_any_historical_reconstruction(self):
        for index, sources in enumerate(self.fixtures[:4]):
            root = self.install(sources, str(index))
            for name, raw in sources.items():
                target = root / name
                target.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
                with patch.object(gate, '_profile_parent_inputs', side_effect=AssertionError('reconstruction forbidden')) as entered:
                    with self.assertRaises(ValueError):
                        refresh.historical_pre_shelf_refresh_mine_bytes(root=root)
                self.assertEqual(entered.call_count, 0)
                target.write_bytes(raw)

    def test_incomplete_extra_and_unusual_path_types_keep_old_chain(self):
        for count in (4, 6, 7):
            values = dict(list(self.fixtures[2].items())[:count])
            self.assert_old_chain(self.install(values, str(count)))
        root = self.install(self.five_old)
        (root / 'extra.txt').write_bytes(b'unknown')
        self.assert_old_chain(root)
        class PathSubclass(type(Path())):
            pass
        self.assert_old_chain(PathSubclass(root))
        self.assert_old_chain(root / 'does-not-exist')

    def test_path_errors_and_self_symlink_do_not_preempt_old_source_checks(self):
        loop = self.root / 'loop'
        loop.symlink_to(loop)
        regular = self.root / 'ordinary-file'
        regular.write_bytes(b'ordinary')
        for root in (loop, str(self.root) + '\x00', '\ud800', regular):
            with self.subTest(kind=repr(root)):
                self.assert_old_chain(root)

    def test_special_members_and_extra_empty_directories_are_uncertain(self):
        for kind in ('fifo', 'socket', 'extra-directory', 'unused-known-directory'):
            root = self.install(self.five_old, kind)
            bad = root / next(iter(self.five_old))
            bad.write_bytes(bad.read_bytes() + b'\n')
            special = root / 'special'
            if kind == 'fifo':
                os.mkfifo(special)
                self.assert_old_chain(root)
            elif kind in ('extra-directory', 'unused-known-directory'):
                if kind == 'unused-known-directory':
                    special = root / 'Resources'
                special.mkdir()
                self.assert_old_chain(root)
            else:
                special.write_bytes(b'placeholder')
                original = Path.lstat
                def lstat(path):
                    value = original(path)
                    if path != special:
                        return value
                    fields = list(value); fields[0] = stat.S_IFSOCK | 0o600
                    return os.stat_result(fields)
                with patch.object(Path, 'lstat', lstat):
                    self.assert_old_chain(root)

    def test_inventory_and_read_errors_do_not_turn_partial_membership_into_exact(self):
        root = self.install(self.five_old)
        broken = root / next(iter(self.five_old))
        broken.write_bytes(broken.read_bytes() + b'\n')
        original_iterdir = Path.iterdir
        def iterdir(path):
            if path == root / 'Tests':
                raise PermissionError('injected directory enumeration failure')
            return original_iterdir(path)
        with patch.object(Path, 'iterdir', iterdir):
            self.assert_old_chain(root)
        original_read = Path.read_bytes
        def read(path):
            if path == broken:
                raise PermissionError('injected fixture read failure')
            return original_read(path)
        with patch.object(Path, 'read_bytes', read):
            self.assert_old_chain(root)

    def test_warm_fixture_changes_with_same_size_and_mtime_cannot_hide(self):
        root = self.install(self.five_old)
        self.assertEqual(refresh.historical_pre_shelf_refresh_mine_bytes(root=root), self.expected)
        name = next(iter(self.five_old)); target = root / name
        raw, metadata = target.read_bytes(), target.stat()
        target.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
        os.utime(target, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        self.assertEqual(target.stat().st_size, metadata.st_size)
        self.assertEqual(target.stat().st_mtime_ns, metadata.st_mtime_ns)
        with self.assertRaises(ValueError):
            refresh.historical_pre_shelf_refresh_mine_bytes(root=root)
        target.write_bytes(raw)
        with patch.object(gate, '_profile_parent_inputs', wraps=gate._profile_parent_inputs) as entered:
            self.assertEqual(refresh.historical_pre_shelf_refresh_mine_bytes(root=root), self.expected)
        self.assertEqual(entered.call_count, 1)

    def test_hot_current_source_changes_still_reach_and_fail_complete_old_chain(self):
        root = self.install(self.five_old)
        self.assertEqual(refresh.historical_pre_shelf_refresh_mine_bytes(root=root), self.expected)
        original = Path.read_bytes
        for name in (gate.CONTRACT_PATH, gate.SELF_PATH, gate.CATEGORY_GATE, gate.RUNNER_PATH,
                     gate.PROFILE_PATH, 'tools/club_customer_directory_admission.py'):
            target = ROOT / name; raw = target.read_bytes()
            def read(path):
                return bytes([raw[0] ^ 1]) + raw[1:] if path == target else original(path)
            with patch.object(Path, 'read_bytes', read), patch.object(gate, '_profile_parent_inputs', wraps=gate._profile_parent_inputs) as entered:
                with self.assertRaises((AssertionError, ValueError)):
                    refresh.historical_pre_shelf_refresh_mine_bytes(root=root)
            self.assertEqual(entered.call_count, 1)

    def test_original_successful_function_body_and_all_old_tests_are_preserved(self):
        raw = (ROOT / gate.SELF_PATH).read_bytes()
        old = gate._fixture_rejection_category_preimage(raw)
        before, after = gate.FIXTURE_REJECTION_SOURCE_HUNKS[0]
        call = '        _reject_invalid_historical_creator_fixture(root, live_root=live_root)\n'
        self.assertEqual(after.count(call), 1)
        self.assertEqual(after.replace(call, '', 1), before)
        old_tree, new_tree = ast.parse(old), ast.parse(raw)
        functions = lambda tree: {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
        old_functions, new_functions = functions(old_tree), functions(new_tree)
        for name, original in old_functions.items():
            if name != 'creator_history_root':
                self.assertEqual(ast.dump(original), ast.dump(new_functions[name]), name)
        methods = lambda tree: {(klass.name, node.name): ast.dump(node) for klass in tree.body if isinstance(klass, ast.ClassDef)
                                for node in klass.body if isinstance(node, ast.FunctionDef) and node.name.startswith('test_')}
        self.assertEqual(methods(old_tree), methods(new_tree))

    def test_complete_five_source_predecessors_keep_fixed_published_hashes(self):
        self.assertEqual(gate.FIXTURE_REJECTION_SOURCE_BASE_COMMIT, '7bf858c23374b808c6d932367f96e97d09e9d799')
        self.assertEqual(set(gate.FIXTURE_REJECTION_PRE_SHA256), {
            gate.SELF_PATH, gate.CATEGORY_GATE, gate.PROFILE_PATH, gate.CONTRACT_PATH, gate.RUNNER_PATH})
        for path, expected in gate.FIXTURE_REJECTION_PRE_SHA256.items():
            raw = (ROOT / path).read_bytes()
            restored = gate.fixture_rejection_predecessor_source(path, raw)
            self.assertEqual(hashlib.sha256(restored).hexdigest(), expected)
            self.assertEqual((ROOT / path).read_bytes(), raw)
        # All earlier exact complete-source reconstruction floors remain active.
        raw = (ROOT / gate.SELF_PATH).read_bytes()
        self.assertEqual(hashlib.sha256(gate._byte_cache_category_preimage(raw)).hexdigest(), gate.BYTE_CACHE_PRE_SHA256[gate.SELF_PATH])
        self.assertEqual(hashlib.sha256(gate._album_category_preimage(raw)).hexdigest(), gate.ALBUM_PRE_SHA256[gate.SELF_PATH])

    def test_forged_prefilter_constants_cannot_authorize_invalid_fixture(self):
        root = self.install(self.five_old)
        name = next(iter(self.five_old)); target = root / name
        changed = target.read_bytes() + b'\n'; target.write_bytes(changed)
        rows = list(gate.FIXTURE_REJECTION_GIT_STATES)
        commit, tree, pairs = rows[0]; identities = dict(pairs)
        identities[name] = hashlib.sha256(changed).hexdigest()
        rows[0] = (commit, tree, tuple(identities.items()))
        with patch.object(gate, 'FIXTURE_REJECTION_GIT_STATES', tuple(rows)), patch.object(gate, '_profile_parent_inputs', wraps=gate._profile_parent_inputs) as entered:
            with self.assertRaisesRegex(ValueError, 'Mixed or unreviewed shelf refresh source bundle'):
                refresh.historical_pre_shelf_refresh_mine_bytes(root=root)
        self.assertEqual(entered.call_count, 1)

    def test_mutation_after_prefilter_still_fails_the_original_reader(self):
        root = self.install(self.five_old)
        target = root / next(iter(self.five_old)); raw = target.read_bytes()
        original = gate._profile_parent_inputs
        def change_then_admit(live_root):
            target.write_bytes(raw + b'\n')
            return original(live_root)
        with patch.object(gate, '_profile_parent_inputs', side_effect=change_then_admit) as entered:
            with self.assertRaisesRegex(ValueError, 'Mixed or unreviewed shelf refresh source bundle'):
                refresh.historical_pre_shelf_refresh_mine_bytes(root=root)
        self.assertEqual(entered.call_count, 1)

    def test_current_inverse_constants_reject_changes_after_warmup(self):
        raw = (ROOT / gate.SELF_PATH).read_bytes()
        expected = gate._fixture_rejection_category_preimage(raw)
        before, after = gate.FIXTURE_REJECTION_SOURCE_HUNKS[0]
        with patch.object(gate, 'FIXTURE_REJECTION_SOURCE_HUNKS', ((before + '\n', after),)):
            with self.assertRaises(AssertionError):
                gate._fixture_rejection_category_preimage(raw)
        self.assertEqual(gate._fixture_rejection_category_preimage(raw), expected)


if __name__ == '__main__':
    unittest.main()
