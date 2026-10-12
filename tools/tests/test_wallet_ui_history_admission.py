"""Finite history identity and pure-byte controls; no native execution claim."""
from pathlib import Path
import ast
import copy
import functools
import hashlib
import json
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def selected_functions(path, names, namespace):
    tree = ast.parse(path.read_bytes())
    nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    assert len(nodes) == len(names)
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(path), 'exec'), namespace)
    return namespace

class WorkspaceHistoryIdentityControls(unittest.TestCase):
    def setUp(self):
        self.life = tempfile.TemporaryDirectory(); self.addCleanup(self.life.cleanup)
        self.root = Path(self.life.name); self.relative = 'Tests/ContractChecks/test_merchant_project_workspace_entry.py'
        self.path = self.root / self.relative; self.path.parent.mkdir(parents=True)
        raw = 'def _workspace_fixed_history():\n    return _workspace_history_context\n'
        self.path.write_text(raw)
        self.module = types.ModuleType('test_merchant_project_workspace_entry')
        self.module.__file__ = str(self.path); self.module.ROOT = self.root
        exec(compile(raw, str(self.path), 'exec'), self.module.__dict__)
        self.history = self.root / 'history'; self.history.mkdir()
        self.expected = {str(i)+'.txt': digest(str(i).encode()) for i in range(24)}
        for name in self.expected: (self.history / name).write_text(name[:-4])
        def tree(path): return {p.name: digest(p.read_bytes()) for p in Path(path).iterdir()}
        self.context = types.SimpleNamespace(root=self.history, file_sha256=dict(self.expected), _club_e2b_guarded=True, verify=lambda: None)
        self.module._workspace_history_context = self.context
        self.module._WORKSPACE_HISTORY_SHA256 = dict(self.expected)
        self.admissions = []
        self.admission = types.SimpleNamespace(_club_authenticate_raw=lambda root: self.admissions.append(root), _club_tree_sha256=tree)
        self.names = {'Path': Path, 'sys': sys, 'json': json, 'digest': digest,
            '_WORKSPACE_HISTORY_IDENTITY_PATH': self.relative,
            '_WORKSPACE_HISTORY_IDENTITY_SHA256': digest(json.dumps(self.expected, sort_keys=True, separators=(',', ':')).encode()),
            '_WORKSPACE_HISTORY_METHODS': frozenset({'test_exact_inverse_of_all_five_existing_files', 'test_existing_transactions_grants_sensitive_routes_and_invitation_remain_exact', 'test_hosted_lifecycle_tests_are_authored', 'test_old_summary_and_navigation_bindings_are_id_bound'})}
        selected_functions(ROOT / 'tools/run_static_checks.py', {'workspace_history_identity_context', 'require_workspace_history_method'}, self.names)
        self.modules = patch.dict(sys.modules, {'test_merchant_project_workspace_entry': self.module}); self.modules.start(); self.addCleanup(self.modules.stop)
    def check(self): return self.names['workspace_history_identity_context'](self.root, self.admission)
    def test_exact_finite_context_requires_admission(self):
        self.assertIs(self.check(), self.context); self.assertEqual(self.admissions, [self.root])
    def test_wrong_module_path_rejected(self):
        self.module.__file__ += '.wrong'
        with self.assertRaises(ValueError): self.check()
    def test_changed_loaded_factory_rejected(self):
        self.module._workspace_fixed_history = lambda: self.context
        with self.assertRaises(ValueError): self.check()
    def test_changed_membership_hash_rejected(self):
        self.module._WORKSPACE_HISTORY_SHA256['0.txt'] = '0'*64
        with self.assertRaises(ValueError): self.check()
    def test_extra_physical_leaf_rejected(self):
        (self.history/'extra').write_text('extra')
        with self.assertRaises(ValueError): self.check()
    def test_changed_physical_bytes_rejected(self):
        (self.history/'0.txt').write_text('different')
        with self.assertRaises(ValueError): self.check()
    def test_unguarded_context_rejected(self):
        self.context._club_e2b_guarded = False
        with self.assertRaises(ValueError): self.check()
    def test_wrong_context_membership_rejected(self):
        self.context.file_sha256.pop('0.txt')
        with self.assertRaises(ValueError): self.check()
    def test_only_original_four_methods_of_exact_class_and_module(self):
        require = self.names['require_workspace_history_method']; good = 'test_exact_inverse_of_all_five_existing_files'
        require(self.relative, 'ProjectWorkspaceContracts', good)
        for args in [('Tests/ContractChecks/other.py', 'ProjectWorkspaceContracts', good), (self.relative, 'OtherClass', good), (self.relative, 'ProjectWorkspaceContracts', 'test_server_role_permission_and_current_session_checks_stay_in_place')]:
            with self.assertRaises(ValueError): require(*args)

class ReplayInversePureControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0,str(ROOT))
        from Tests.ContractChecks.test_category_roam_registration import club_predecessor_source
        cls.relative = 'Tests/ContractChecks/test_roam_route_replay.py'
        cls.raw = club_predecessor_source(cls.relative, (ROOT/cls.relative).read_bytes())
        tree = ast.parse(cls.raw); cls.node = next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='project_saved_route_source')
        cls.table = ast.literal_eval(next(n for n in tree.body if isinstance(n,ast.Assign) and n.targets[0].id=='SOURCE_INVERSES').value)
        names = {'_club_hashlib': hashlib, '_club_ast': ast, '_club_wraps': functools.wraps, '_CLUB_E2B_SHA256': {cls.relative: digest(cls.raw)}}
        selected_functions(ROOT/'tools/club_customer_directory_admission.py', {'_club_make_replay_inverse'}, names)
        cls.make = staticmethod(names['_club_make_replay_inverse'])
    def setUp(self):
        self.globals = {'SOURCE_INVERSES': copy.deepcopy(self.table), 'hashlib': hashlib}
        module_code = compile(self.raw, '<exact-replay>', 'exec', dont_inherit=True)
        code = next(value for value in module_code.co_consts
                    if isinstance(value, types.CodeType) and value.co_name == 'project_saved_route_source')
        self.original = types.FunctionType(code, self.globals)
        self.pure = self.make(self.original,self.raw)
    def test_every_exact_table_postimage_matches_original_inverse(self):
        from Tests.ContractChecks.test_category_roam_registration import club_predecessor_source
        for path in self.table:
            raw = club_predecessor_source(path,(ROOT/path).read_bytes())
            self.assertEqual(self.pure(path,raw), self.original(path,raw))
    def test_corrupted_inputs_still_rejected_without_result_cache(self):
        path = next(iter(self.table))
        for raw in [b'',b'bad',b'\r\n',b'bad\n']:
            with self.assertRaises(AssertionError): self.pure(path,raw)
    def test_whole_source_drift_rejected(self):
        with self.assertRaises(ValueError): self.make(self.original,self.raw+b'\n')
    def test_wrong_function_code_rejected(self):
        with self.assertRaises(ValueError): self.make(lambda path,raw:raw,self.raw)
    def test_mutated_nested_table_rejected(self):
        path=next(iter(self.table));self.globals['SOURCE_INVERSES'][path]['before']='0'*64
        with self.assertRaises(ValueError): self.pure(path,b'bad')
    def test_mutated_loaded_code_rejected(self):
        self.original.__code__=(lambda path,raw:raw).__code__
        with self.assertRaises(ValueError): self.pure('x',b'bad')
    def test_wrong_parameter_types_and_names_rejected(self):
        for args in [(0,b''),('x',bytearray()),('x','text')]:
            with self.assertRaises(TypeError): self.pure(*args)
        with self.assertRaises(TypeError): self.pure(relative='x',raw=b'')
    def test_unregistered_path_rejected(self):
        with self.assertRaises(KeyError): self.pure('Other/Path',b'')

if __name__ == '__main__': unittest.main()
