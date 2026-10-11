from pathlib import Path
import hashlib,json,os,sys,tempfile,unittest
from unittest.mock import patch
R=Path(__file__).resolve().parents[2]
from tools import run138_editor_readiness as current
from Tests.ContractChecks import test_category_roam_registration as repair
class ReadinessContractParseCacheTests(unittest.TestCase):
 def setUp(self):
  self.life=tempfile.TemporaryDirectory(prefix='cache-prototype-');self.addCleanup(self.life.cleanup);self.root=Path(self.life.name);(self.root/'tools').mkdir()
  self.p=self.root/'tools/run138_editor_readiness_contract.json';self.raw=(R/'tools/run138_editor_readiness_contract.json').read_bytes();self.p.write_bytes(self.raw);current._parsed_contract.cache_clear();self.contract=current.contract;self.parsed=current._parsed_contract;self.addCleanup(current._parsed_contract.cache_clear)
 def test_each_call_rereads_full_bytes_and_returns_independent_nested_dict(self):
  original=Path.read_bytes;reads=[]
  def read(path):reads.append(path);return original(path)
  with patch.object(Path,'read_bytes',read):a=self.contract(self.root);b=self.contract(self.root)
  self.assertEqual(reads,[self.p,self.p]);self.assertEqual(self.parsed.cache_info().misses,1);self.assertEqual(a,b);self.assertIsNot(a,b)
  a['current_ui_sources'].clear();self.assertEqual(b,self.contract(self.root));self.assertTrue(b['current_ui_sources'])
 def test_same_size_same_mtime_mutation_rejected_after_warm_read(self):
  self.contract(self.root);stat=self.p.stat();i=self.raw.index(b'current_ui_sources');mutated=self.raw[:i]+b'C'+self.raw[i+1:];self.p.write_bytes(mutated);os.utime(self.p,ns=(stat.st_atime_ns,stat.st_mtime_ns))
  self.assertEqual(self.p.stat().st_size,stat.st_size);self.assertEqual(self.p.stat().st_mtime_ns,stat.st_mtime_ns)
  with self.assertRaisesRegex(ValueError,'Unreviewed current readiness planning contract'):self.contract(self.root)
  self.assertEqual(self.parsed.cache_info().misses,1)
  self.p.write_bytes(self.raw);self.assertEqual(self.contract(self.root),json.loads(self.raw))
 def test_changed_pin_is_rechecked_even_when_bytes_are_warm(self):
  self.contract(self.root)
  with patch.object(current,'CONTRACT_SHA256','0'*64),self.assertRaises(ValueError):self.contract(self.root)
 def test_warm_cache_does_not_hide_missing_file_or_read_error(self):
  self.contract(self.root);self.p.unlink()
  with self.assertRaises(FileNotFoundError):self.contract(self.root)
  self.p.write_bytes(self.raw)
  with patch.object(Path,'read_bytes',side_effect=PermissionError('sentinel inaccessible')),self.assertRaisesRegex(PermissionError,'sentinel inaccessible'):self.contract(self.root)
 def test_key_is_actual_bytes_and_cache_is_bounded(self):
  first=self.contract(self.root);second={**first,'_prototype_only_marker':True};raw=(json.dumps(second)+'\n').encode();self.p.write_bytes(raw)
  with patch.object(current,'CONTRACT_SHA256',hashlib.sha256(raw).hexdigest()):self.assertEqual(self.contract(self.root),second)
  self.assertEqual(self.parsed.cache_info().misses,2);self.assertEqual(self.parsed.cache_info().currsize,1)
  self.p.write_bytes(self.raw);self.assertEqual(self.contract(self.root),first);self.assertEqual(self.parsed.cache_info().misses,3)
 def test_json_decode_errors_keep_original_type_and_are_not_cached(self):
  raw=b'{broken';self.p.write_bytes(raw)
  with patch.object(current,'CONTRACT_SHA256',hashlib.sha256(raw).hexdigest()):
   for _ in range(2):
    with self.assertRaises(json.JSONDecodeError):self.contract(self.root)
  self.assertEqual(self.parsed.cache_info().misses,2);self.assertEqual(self.parsed.cache_info().currsize,0)
 def test_old_and_new_match_for_actual_profile_and_each_error_boundary(self):
  def original(root):
   raw=(Path(root)/'tools/run138_editor_readiness_contract.json').read_bytes()
   if current.digest(raw)!=current.CONTRACT_SHA256:raise ValueError('Unreviewed current readiness planning contract')
   return json.loads(raw)
  self.assertEqual(original(self.root),self.contract(self.root))
  for raw in [self.raw+b'\n',b'',b'{broken']:
   self.p.write_bytes(raw)
   for operation in [original,self.contract]:
    with self.assertRaisesRegex(ValueError,'Unreviewed current readiness planning contract'):operation(self.root)

class ReadinessParseCacheSourceChainTests(unittest.TestCase):
    """The optimization preserves every complete pre-cache source boundary."""

    @staticmethod
    def admission():
        from Tests.ContractChecks import test_profile_read_failure_remote_admission
        return test_profile_read_failure_remote_admission

    def test_exact_parser_inverse_restores_complete_published_implementation(self):
        admission = self.admission()
        source = (R / 'tools/run138_editor_readiness.py').read_bytes()
        original = repair.uncached_readiness_source(source)
        self.assertEqual(original.count(current.CONTRACT_SHA256.encode()), 1)
        original = original.replace(
            current.CONTRACT_SHA256.encode(),
            b'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053', 1)
        self.assertEqual(hashlib.sha256(original).hexdigest(),
                         'a33058cdac0bfce6fe0c17f02059d0be061c5b3da0cd3df76ace1f856422662c')

    def test_missing_duplicate_and_mutated_parser_spans_are_rejected(self):
        admission = self.admission()
        source = (R / 'tools/run138_editor_readiness.py').read_bytes()
        for after, before in repair.READINESS_PARSE_CACHE_INVERSE_HUNKS:
            after = after.encode()
            self.assertEqual(source.count(after), 1)
            for mutant in (source.replace(after, b'', 1), source + after,
                           source.replace(after, after[:-1] + b'X', 1)):
                with self.subTest(span=after[:40]), self.assertRaises(ValueError):
                    repair.uncached_readiness_source(mutant)

    def test_full_admission_rejects_off_hunk_runner_changes_after_cache_warmup(self):
        admission = self.admission()
        current.contract(R)
        path = R / 'tools/run138_editor_readiness.py'
        source = path.read_bytes()
        mutant = source.replace(b'Active source-bound', b'Active source-bounD', 1)
        self.assertNotEqual(mutant, source)
        self.assertEqual(len(mutant), len(source))
        read = Path.read_bytes
        def changed(p):
            return mutant if p == path else read(p)
        data = (R / 'tools/run138_editor_readiness_contract.json').read_bytes()
        with patch.object(Path, 'read_bytes', changed), self.assertRaises(ValueError):
            admission._combined_profile_contract(data, R)

    def test_creator_history_inverse_restores_complete_published_test(self):
        from tools.tests import test_creator_shelf_state_history as history
        source = (R / 'tools/tests/test_creator_shelf_state_history.py').read_bytes()
        original = history._restore_precache_history_test(source)
        self.assertEqual(hashlib.sha256(original).hexdigest(),
                         '28e14028204276d0277afb29064d0f2ad65bcb05e57aadf226b63d61e606c924')
        for mutant in (source + b'\n', source.replace(
                b'import uncached_readiness_source', b'import uncached_readiness_sourcX', 1)):
            with self.assertRaises(ValueError):
                history._restore_precache_history_test(mutant)
        for row in repair.REPAIR_SOURCE_INVERSES['tools/tests/test_creator_shelf_state_history.py']['hunks']:
            after, before = row['after'], row['before']
            for mutant in (source.replace(after.encode(), b'', 1), source + after.encode()):
                with self.assertRaises(ValueError):
                    history._restore_precache_history_test(mutant)

    def test_central_contract_changes_only_existing_admission_support_value(self):
        path = R / 'tools/run138_editor_readiness_contract.json'
        contract = json.loads(path.read_bytes())
        admission_path = 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py'
        self.assertEqual(contract['feature_batch_support_sha256'][admission_path],
                         hashlib.sha256((R / admission_path).read_bytes()).hexdigest())
        # Authenticate the new repair and published discovery/club inputs first;
        # retain the original exact b75 central assertion after its bounded projection.
        contract, context = repair.profile_contract_inputs(contract, R, 'club')
        from tools import club_customer_directory_admission as club
        contract = club.current_predecessor_contract(contract, context)
        contract['feature_batch_support_sha256'][admission_path] = (
            'df08d6c30bcebd89e901e5ae3a5920b22142dbd8b2cf4a7dfa4c765be5917271')
        original = (json.dumps(contract, indent=2, ensure_ascii=False) + '\n').encode()
        self.assertEqual(hashlib.sha256(original).hexdigest(),
                         'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053')

    def test_full_current_admission_still_rejects_warm_source_byte_mutation(self):
        current.contract(R)
        path = R / 'App/ClubOperationsViews.swift'
        source = path.read_bytes()
        mutant = source.replace(b'artworkRevision', b'artworkRevisioX', 1)
        self.assertNotEqual(mutant, source)
        self.assertEqual(len(mutant), len(source))
        read = Path.read_bytes
        def changed(p):
            return mutant if p == path else read(p)
        with patch.object(Path, 'read_bytes', changed), self.assertRaises(ValueError):
            current.validate_current(R / 'Tests/AppUITests', R / 'tools/ui_duration_weights.json', R)



class UnifiedRepairCurrentInputTests(unittest.TestCase):
    """The new current layer is complete before any historical fixture is exposed."""

    def raw(self):
        return (R / repair.CONTRACT_PATH).read_bytes()

    def fixture(self):
        life = tempfile.TemporaryDirectory(prefix='unified-current49-')
        self.addCleanup(life.cleanup)
        root = Path(life.name)
        paths = set(repair.PROFILE_CONTEXT_INPUTS) | set(repair.REPAIR_LEAF_PATHS)
        self.assertEqual(len(paths), 49)
        for path in paths:
            file = root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes((R / path).read_bytes())
        return root, paths

    def test_two_leaf_inverses_preserve_complete_parent_and_original_ending_history(self):
        value = json.loads(self.raw())
        parent = repair.repair_predecessor_contract(value)
        self.assertEqual(repair.digest(repair.encode(parent)),
                         'b72d9b1024daadb5273a4de24c0175d42c04516b1f89c6c53c0f9c40dd7a77b6')
        ending = 'App/ProjectEndingConditionPicker.swift'
        self.assertEqual(value['feature_batch_sources'][ending]['before_sha256'],
                         '188e81782efb8117c5dc669021c228c425c050996b0e6727aa325b00ea6eb418')
        self.assertEqual(value['feature_batch_sources'][ending]['hunks'][:-2],
                         parent['feature_batch_sources'][ending]['hunks'])
        for path in repair.REPAIR_LEAF_PATHS:
            raw = (R / path).read_bytes()
            row = repair.REPAIR_SOURCE_INVERSES[path]
            self.assertEqual(repair.digest(repair.repair_predecessor_source(path, raw)), row['before_sha256'])
            for hunk in row['hunks']:
                after = hunk['after'].encode()
                for mutant in (raw.replace(after, hunk['before'].encode(), 1), raw + after, raw + b'\n'):
                    with self.subTest(path=path), self.assertRaises(AssertionError):
                        repair.repair_predecessor_source(path, mutant)

    def test_real_same_size_mtime_and_missing_current_sources_reject_after_warm_admission(self):
        raw = self.raw()
        targets = list(repair.REPAIR_SOURCE_INVERSES) + [repair.RUNNER_PATH, repair.PROFILE_PATH,
                                                         repair.SELF_PATH, repair.CATEGORY_GATE]
        repair.checked_current(raw, R)
        repair.profile_history_inputs(raw, R, 'history')
        for path in targets:
            file = R / path
            data = file.read_bytes(); metadata = file.stat()
            self.assertFalse(file.is_symlink())
            # The source-only tests run in a private, unlinked mutation view.
            self.assertEqual(metadata.st_nlink, 1, path)
            try:
                file.write_bytes(bytes([data[0] ^ 1]) + data[1:])
                os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                self.assertEqual(file.stat().st_size, metadata.st_size)
                self.assertEqual(file.stat().st_mtime_ns, metadata.st_mtime_ns)
                with self.assertRaises((AssertionError, ValueError, OSError)):
                    repair.checked_current(raw, R)
                with self.assertRaises(ValueError):
                    repair.profile_history_inputs(raw, R, 'history')
            finally:
                file.write_bytes(data)
                os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            backup = file.with_name(file.name + '.unified-missing-probe')
            self.assertFalse(backup.exists())
            file.rename(backup)
            try:
                with self.assertRaises((AssertionError, ValueError, OSError)):
                    repair.checked_current(raw, R)
            finally:
                backup.rename(file)
        repair.checked_current(raw, R)

    def test_complete_49_real_reads_precede_projection_and_missing_two_never_falls_back(self):
        root, paths = self.fixture()
        raw = self.raw(); reads = []; original = Path.read_bytes
        def read(path):
            if path.is_relative_to(root): reads.append(str(path.relative_to(root)))
            return original(path)
        with patch.object(Path, 'read_bytes', read):
            prior, context = repair.profile_history_inputs(raw, root, 'history')
        self.assertEqual(set(reads), paths)
        self.assertEqual(len(reads), 49)
        self.assertEqual(repair.digest(prior), repair.PARENT_CONTRACT_SHA256)
        self.assertEqual({str(p.relative_to(context)) for p in context.rglob('*') if p.is_file()},
                         set(repair.PROFILE_CONTEXT_INPUTS))
        removed = {}
        for path in repair.REPAIR_LEAF_PATHS:
            file = root / path; removed[path] = file.read_bytes(); file.unlink()
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        # The genuine previous 47-file version remains a separate historical input.
        # New-current 47 bytes above were rejected, rather than repaired from ROOT.
        for path in repair.PROFILE_CONTEXT_INPUTS:
            (root / path).write_bytes(repair.repair_predecessor_fixture_source(path, (R / path).read_bytes(), raw))
        self.assertEqual(repair.profile_history_inputs(raw, root, 'history')[0], prior)

    def test_current_49_root_and_leaf_symlinks_are_rejected(self):
        root, paths = self.fixture()
        raw = self.raw()
        link = root.with_name(root.name + '-root-link')
        link.symlink_to(root, target_is_directory=True); self.addCleanup(lambda: link.unlink(missing_ok=True))
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, link, 'history')
        path = repair.REPAIR_LEAF_PATHS[0]; file = root / path; data = file.read_bytes()
        file.unlink(); file.symlink_to(R / path)
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink(); file.write_bytes(data)
        self.assertEqual(repair.digest(repair.profile_history_inputs(raw, root, 'history')[0]),
                         repair.PARENT_CONTRACT_SHA256)

    def test_club_baseline_reader_keeps_full_old_test_and_rejects_parser_span_forgery(self):
        path = 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py'
        data = (R / path).read_bytes()
        old = repair.repair_predecessor_source(path, data)
        self.assertEqual(repair.digest(old), 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1')
        self.assertIn(b'reader.write_bytes(uncached_readiness_source(reader.read_bytes()).replace(', data)
        source = (R / repair.RUNNER_PATH).read_bytes()
        for after, before in repair.READINESS_PARSE_CACHE_INVERSE_HUNKS:
            after = after.encode()
            for mutant in (source.replace(after, b'', 1), source + after,
                           source.replace(after, after[:-1] + b'X', 1)):
                with self.assertRaises(ValueError): repair.uncached_readiness_source(mutant)
        for mutant in (data + b'\n', data.replace(b'uncached_readiness_source(reader.read_bytes())', b'reader.read_bytes()')):
            with self.assertRaises(AssertionError): repair.repair_predecessor_source(path, mutant)

if __name__=='__main__':unittest.main(verbosity=2)
