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
            file.write_bytes(repair.native_predecessor_fixture_source(
                path, (R / path).read_bytes(), self.raw()))
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


class NativeNavigationCompileAdmissionTests(unittest.TestCase):
    """Current51, exact historical c2af49 and original47 remain separate."""

    def fixture(self):
        life = tempfile.TemporaryDirectory(prefix='native-current51-')
        self.addCleanup(life.cleanup)
        root = Path(life.name)
        paths = set(repair.PROFILE_CONTEXT_INPUTS) | set(repair.REPAIR_LEAF_PATHS) | set(repair.NATIVE_CURRENT_INPUTS)
        self.assertEqual(len(paths), 51)
        for relative in paths:
            file = root / relative; file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(repair.description_predecessor_fixture_source(
                relative, (R / relative).read_bytes(), (R / repair.CONTRACT_PATH).read_bytes()))
        return root, paths

    def test_exact_native_leaf_and_contract_restore_published_c2af(self):
        raw = (R / repair.CONTRACT_PATH).read_bytes()
        before = repair.native_predecessor_contract(json.loads(raw))
        self.assertEqual(repair.digest(repair.encode(before)),
                         'd3fedafc9efe917220f4c52cb4c82d742f840a7307546da35e4da130a80d7fdb')
        path = repair.NATIVE_LEAF_PATHS[0]
        self.assertNotIn(path, before['feature_batch_sources'])
        value = (R / path).read_bytes()
        self.assertEqual(repair.digest(repair.native_predecessor_source(path, value)),
                         'ff473e0c1695a05f3b983e0675f0e7cd431f5b8258dad01b6d1a73f0911b0a2b')
        self.assertIn(b'nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }', value)
        self.assertIn(b'nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }', value)

    def test_native_source_mutants_and_missing_inverse_spans_are_rejected(self):
        path = repair.NATIVE_LEAF_PATHS[0]; raw = (R / path).read_bytes()
        after = repair.NATIVE_NAV_ROW['hunks'][0]['after'].encode()
        mutants = [raw + b'\n', raw.replace(b'lhs.id == rhs.id', b'lhs.capture.location == rhs.capture.location'),
                   raw.replace(b'hasher.combine(id)', b'hasher.combine(capture)'),
                   raw.replace(b'let id = UUID()', b'var id = UUID()'), raw.replace(after, b'', 1), raw + after]
        for mutant in mutants:
            with self.subTest(mutant=repair.digest(mutant)), self.assertRaises(AssertionError):
                repair.native_predecessor_source(path, mutant)

    def test_canonical_pbx_preserves_exact_c2af_and_all_original209_hunks(self):
        path = 'Questify.xcodeproj/project.pbxproj'
        raw = (R / path).read_bytes()
        self.assertEqual(repair.digest(raw), '211fe2e6ded15704a582d9340bb45d198620afe118b2add40d60679820b64f65')
        before = repair.native_predecessor_source(path, raw)
        self.assertEqual(repair.digest(before), 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50')
        value = json.loads((R / repair.CONTRACT_PATH).read_bytes())
        old = repair.native_predecessor_contract(value)
        self.assertEqual(len(old['feature_batch_sources'][path]['hunks']), 209)
        self.assertEqual(value['feature_batch_sources'][path]['hunks'][:-len(repair.NATIVE_PBX_REPAIR_ROW['hunks'])],
                         old['feature_batch_sources'][path]['hunks'])
        for mutant in [raw + b'\n', raw.replace(b'547DD20422C04B364B7AAC62', b'547DD20422C04B364B7AAC63')]:
            with self.assertRaises(AssertionError): repair.native_predecessor_source(path, mutant)

    def test_complete_current51_reads_precede_projection_and_missing_leaf_has_no_fallback(self):
        root, paths = self.fixture(); raw = (R / repair.CONTRACT_PATH).read_bytes()
        original = Path.read_bytes; reads = []
        def read(path):
            if path.is_relative_to(root): reads.append(str(path.relative_to(root)))
            return original(path)
        with patch.object(Path, 'read_bytes', read):
            _, _, target = repair._profile_parent_inputs(root)
        self.assertEqual(set(reads), paths); self.assertEqual(len(reads), 51)
        self.assertEqual({str(p.relative_to(target)) for p in target.rglob('*') if p.is_file()}, set(repair.PROFILE_CONTEXT_INPUTS))
        for path in repair.NATIVE_CURRENT_INPUTS:
            (root / path).unlink()
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        # All49 must be authentic c2af predecessors, not repaired current49.
        for path in paths - set(repair.NATIVE_CURRENT_INPUTS):
            (root / path).write_bytes(repair.native_predecessor_fixture_source(path, (R / path).read_bytes(), raw))
        repair.profile_history_inputs(raw, root, 'history')

    def test_warm_current51_same_size_mtime_and_missing_navigation_are_rejected(self):
        root, _ = self.fixture(); raw = (R / repair.CONTRACT_PATH).read_bytes()
        repair.profile_history_inputs(raw, root, 'history')
        file = root / repair.NATIVE_LEAF_PATHS[0]; saved = file.read_bytes(); metadata = file.stat()
        for mutant in [bytes([saved[0] ^ 1]) + saved[1:], saved.replace(b'\n', b'\r\n'), saved.replace(b'\n', b'\r')]:
            file.write_bytes(mutant); os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.write_bytes(saved); file.unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')

    def test_current51_navigation_symlink_and_unknown_extra_file_rejected(self):
        root, _ = self.fixture(); raw = (R / repair.CONTRACT_PATH).read_bytes()
        file = root / repair.NATIVE_LEAF_PATHS[0]; saved = file.read_bytes(); file.unlink(); file.symlink_to(R / repair.NATIVE_LEAF_PATHS[0])
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink(); file.write_bytes(saved); (root / 'unknown.txt').write_text('not an admitted input')
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')

    def test_native_helper_and_full_central_mutations_rejected(self):
        path = 'tools/club_customer_directory_admission.py'; source = (R / path).read_bytes()
        for mutant in [source + b'\n', source.replace(b'App/ProjectEditIssueNavigation.swift', b'App/ProjectEditIssueNavigatioX.swift')]:
            with self.assertRaises(AssertionError): repair.native_predecessor_source(path, mutant)
        value = json.loads((R / repair.CONTRACT_PATH).read_bytes())
        value['feature_batch_sources'][repair.NATIVE_LEAF_PATHS[0]]['hunks'][0]['after'] += '\n'
        with self.assertRaises(AssertionError): repair.native_predecessor_contract(value)

    def test_complete_native_source_interfaces_restore_exact_c2af_files(self):
        for path, expected in repair.NATIVE_PRE_SHA256.items():
            with self.subTest(path=path):
                source = (R / path).read_bytes()
                self.assertEqual(repair.digest(repair.native_predecessor_source(path, source)), expected)
                with self.assertRaises((AssertionError, ValueError)):
                    repair.native_predecessor_source(path, source + b'\n')

    def test_projection_exact_full_inverse_and_missing_duplicate_changed_spans_rejected(self):
        path = repair.NATIVE_PROJECTION_PATH; raw = (R / path).read_bytes()
        self.assertEqual(repair.digest(repair.native_predecessor_source(path, raw)),
                         'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727')
        for row in repair.NATIVE_PROJECTION_ROW['hunks']:
            after = row['after'].encode()
            for mutant in (raw.replace(after, b'', 1), raw + after, raw.replace(after, row['before'].encode(), 1)):
                with self.assertRaises(AssertionError): repair.native_predecessor_source(path, mutant)
        source = (R / repair.RUNNER_PATH).read_bytes()
        for row in repair.NATIVE_READINESS_HUNKS:
            after = row['after'].encode()
            for mutant in (source.replace(after, b'', 1), source + after, source.replace(after, after[:-1] + b'X', 1)):
                with self.assertRaises(ValueError): repair.native_readiness_source(mutant)

    def test_actual_projection_old_missing_same_size_mtime_and_coherent_repin_rejected(self):
        path = R / repair.NATIVE_PROJECTION_PATH
        contract = R / repair.CONTRACT_PATH; runner = R / repair.RUNNER_PATH
        saved = {p: (p.read_bytes(), p.stat()) for p in (path, contract, runner)}
        for p, (_, metadata) in saved.items(): self.assertEqual(metadata.st_nlink, 1, str(p))
        raw = saved[contract][0]; source = saved[path][0]
        repair.checked_current(raw, R)
        def restore():
            for p, (data, metadata) in saved.items():
                p.write_bytes(data); os.utime(p, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        try:
            for mutant in (repair.native_predecessor_source(repair.NATIVE_PROJECTION_PATH, source),
                           bytes([source[0] ^ 1]) + source[1:]):
                path.write_bytes(mutant); os.utime(path, ns=(saved[path][1].st_atime_ns, saved[path][1].st_mtime_ns))
                with self.assertRaises((AssertionError, ValueError)): repair.checked_current(raw, R)
            restore(); path.unlink()
            with self.assertRaises((AssertionError, ValueError, OSError)): repair.checked_current(raw, R)
            restore()
            mutant = bytes([source[0] ^ 1]) + source[1:]
            value = json.loads(raw); value['entry_projection_module_sha256'] = repair.digest(mutant)
            changed = repair.encode(value)
            path.write_bytes(mutant); contract.write_bytes(changed)
            runner.write_bytes(saved[runner][0].replace(repair.digest(raw).encode(), repair.digest(changed).encode(), 1))
            with self.assertRaises((AssertionError, ValueError)): repair.checked_current(changed, R)
        finally:
            restore()
        repair.checked_current(raw, R)

    def test_current_runner_cannot_reuse_historical_memberless_body_with_new_pin(self):
        path = R / repair.RUNNER_PATH; saved = path.read_bytes(); metadata = path.stat()
        self.assertEqual(metadata.st_nlink, 1)
        old = repair.native_readiness_source(saved)
        self.assertNotEqual(old, saved)
        # This predecessor remains valid only at its explicit historical boundary.
        self.assertEqual(repair.native_readiness_source(old), old)
        try:
            path.write_bytes(old)
            with self.assertRaises((AssertionError, ValueError)):
                repair.checked_current((R / repair.CONTRACT_PATH).read_bytes(), R)
        finally:
            path.write_bytes(saved); os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        repair.checked_current((R / repair.CONTRACT_PATH).read_bytes(), R)

    def test_current51_missing_or_old_projection_never_uses_healthy_live_source(self):
        root, _ = self.fixture(); raw = (R / repair.CONTRACT_PATH).read_bytes()
        file = root / repair.NATIVE_PROJECTION_PATH; source = file.read_bytes(); metadata = file.stat()
        repair.profile_history_inputs(raw, root, 'history')
        for mutant in (repair.native_predecessor_source(repair.NATIVE_PROJECTION_PATH, source),
                       bytes([source[0] ^ 1]) + source[1:]):
            file.write_bytes(mutant); os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')


class ReadinessMemberCopyTests(unittest.TestCase):
    def test_every_member_call_rereads_full_raw_and_nested_results_are_independent(self):
        source = R / repair.CONTRACT_PATH; original = Path.read_bytes; reads = []
        def read(path):
            if path == source: reads.append(path)
            return original(path)
        with patch.object(Path, 'read_bytes', read):
            first = current.contract_member('feature_batch_sources', repair.NATIVE_LEAF_PATHS[0], R)
            first['hunks'][0]['after'] = 'caller contamination'
            second = current.contract_member('feature_batch_sources', repair.NATIVE_LEAF_PATHS[0], R)
            full = current.contract(R)
        self.assertEqual(reads, [source, source, source])
        self.assertEqual(second, full['feature_batch_sources'][repair.NATIVE_LEAF_PATHS[0]])
        self.assertNotEqual(first, second)
        self.assertIsNone(current.contract_member('feature_batch_sources', 'unknown-member', R))
        with self.assertRaises(KeyError): current.contract_member('unknown-section', root=R)

    def test_member_bad_raw_is_rejected_before_unknown_key_and_after_cache_warmup(self):
        with tempfile.TemporaryDirectory(prefix='native-member-copy-') as directory:
            root = Path(directory); file = root / repair.CONTRACT_PATH
            file.parent.mkdir(parents=True); raw = (R / repair.CONTRACT_PATH).read_bytes(); file.write_bytes(raw)
            current.contract_member('entry_contract_sha256', root=root); metadata = file.stat()
            file.write_bytes(bytes([raw[0] ^ 1]) + raw[1:]); os.utime(file, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            self.assertEqual(file.stat().st_size, metadata.st_size)
            self.assertEqual(file.stat().st_mtime_ns, metadata.st_mtime_ns)
            with self.assertRaises(ValueError): current.contract_member('unknown-section', root=root)
            file.unlink()
            with self.assertRaises(FileNotFoundError): current.contract_member('entry_contract_sha256', root=root)


class DescriptionInitializationCompileAdmissionTests(unittest.TestCase):
    """New current52 is admitted before exact published51/49/47 history."""

    def raw(self):
        return (R / repair.CONTRACT_PATH).read_bytes()

    def fixture(self):
        life = tempfile.TemporaryDirectory(prefix='description-current52-')
        self.addCleanup(life.cleanup)
        root = Path(life.name)
        paths = set(repair.PROFILE_CONTEXT_INPUTS) | set(repair.REPAIR_LEAF_PATHS) | set(repair.NATIVE_CURRENT_INPUTS) | {repair.DESCRIPTION_LEAF_PATH}
        self.assertEqual(len(paths), 52)
        for path in paths:
            file = root / path; file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(repair.actor_predecessor_fixture_source(
                path, (R / path).read_bytes(), self.raw()))
        return root, paths

    def test_exact_one_hunk_reads_description_once_without_published_self_access(self):
        path = repair.DESCRIPTION_LEAF_PATH; source = (R / path).read_bytes()
        row = repair.DESCRIPTION_LEAF_ROW
        self.assertEqual(row['before_sha256'], '663f5aa34981ca0e3ec9207e165140b78bb8c8a3858314bf2cda4d836599f2e3')
        self.assertEqual(row['after_sha256'], 'c03d2b762a9c339449f799214b356180ead19d9c6bc9065ff2c25e0cabc77053')
        self.assertEqual(len(row['hunks']), 1)
        self.assertEqual(repair.digest(source), row['after_sha256'])
        old = repair.description_predecessor_source(path, source)
        self.assertEqual(repair.digest(old), row['before_sha256'])
        self.assertEqual(source, old.replace(row['hunks'][0]['before'].encode(), row['hunks'][0]['after'].encode(), 1))
        body = source.split(b'    init(source: ProjectEditNodeDescriptionSource) {', 1)[1].split(b'    }', 1)[0]
        self.assertEqual(body.count(b'source.node.wrappedValue.description'), 1)
        self.assertIn(b'text = initialText; acknowledgedBytes = Data(initialText.utf8)', body)
        self.assertNotIn(b'Data(text.utf8)', body)

    def test_complete_new_contract_restores_7b_then_unchanged_native_and_repair_floors(self):
        value = json.loads(self.raw())
        old = repair.description_predecessor_contract(value)
        self.assertEqual(repair.digest(repair.encode(old)), '9c26993734c6ba8d4623165187cb0cfcebc1ff20e3c9209da7a2982099ee2cb6')
        self.assertNotIn(repair.DESCRIPTION_LEAF_PATH, old['feature_batch_sources'])
        self.assertEqual(value['node_description_sources'], old['node_description_sources'])
        self.assertEqual(repair.digest(repair.encode(repair.native_predecessor_contract(value))), 'd3fedafc9efe917220f4c52cb4c82d742f840a7307546da35e4da130a80d7fdb')
        self.assertEqual(repair.digest(repair.encode(repair.repair_predecessor_contract(value))), 'b72d9b1024daadb5273a4de24c0175d42c04516b1f89c6c53c0f9c40dd7a77b6')
        for path, expected in repair.DESCRIPTION_PRE_SHA256.items():
            source = (R / path).read_bytes()
            self.assertEqual(repair.digest(repair.description_predecessor_source(path, source)), expected)
            for mutant in (source + b'\n', source.replace(b'\n', b'\r\n'), bytes([source[0] ^ 1]) + source[1:]):
                with self.subTest(path=path), self.assertRaises((AssertionError, ValueError)):
                    repair.description_predecessor_source(path, mutant)

    def test_description_inverse_rejects_missing_duplicate_and_edited_hunk(self):
        path = repair.DESCRIPTION_LEAF_PATH; source = (R / path).read_bytes()
        hunk = repair.DESCRIPTION_LEAF_ROW['hunks'][0]['after'].encode()
        for mutant in (source.replace(hunk, b'', 1), source + hunk,
                       source.replace(b'Data(initialText.utf8)', b'Data(text.utf8)', 1),
                       source.replace(b'let initialText', b'var initialText', 1)):
            with self.assertRaises(AssertionError): repair.description_predecessor_source(path, mutant)

    def test_old_leaf_and_coherent_leaf_contract_runner_repin_never_admit_as_current(self):
        path = R / repair.DESCRIPTION_LEAF_PATH; source = path.read_bytes(); raw = self.raw()
        runnerpath = R / repair.RUNNER_PATH; runner = runnerpath.read_bytes()
        for mutant in (repair.description_predecessor_source(repair.DESCRIPTION_LEAF_PATH, source),
                       bytes([source[0] ^ 1]) + source[1:]):
            value = json.loads(raw)
            value['feature_batch_sources'][repair.DESCRIPTION_LEAF_PATH]['after_sha256'] = repair.digest(mutant)
            value['feature_batch_support_sha256'][repair.DESCRIPTION_LEAF_PATH] = repair.digest(mutant)
            changed = repair.encode(value)
            replacements = {path: mutant, R / repair.CONTRACT_PATH: changed,
                            runnerpath: runner.replace(repair.digest(raw).encode(), repair.digest(changed).encode(), 1)}
            original = Path.read_bytes
            with patch.object(Path, 'read_bytes', lambda p: replacements[p] if p in replacements else original(p)):
                with self.assertRaises((AssertionError, ValueError)): repair.checked_current(changed, R)

    def test_current52_all_physical_reads_precede_cached_history_and_missing_leaf_cannot_be_51(self):
        root, paths = self.fixture(); raw = self.raw(); original = Path.read_bytes; reads = []
        def read(path):
            if path.is_relative_to(root): reads.append(str(path.relative_to(root)))
            return original(path)
        with patch.object(Path, 'read_bytes', read): repair._profile_parent_inputs(root)
        self.assertEqual(set(reads), paths); self.assertEqual(len(reads), 52)
        leaf = root / repair.DESCRIPTION_LEAF_PATH; leaf.unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        for path in paths - {repair.DESCRIPTION_LEAF_PATH}:
            (root / path).write_bytes(repair.description_predecessor_fixture_source(path, (R / path).read_bytes(), raw))
        repair.profile_history_inputs(raw, root, 'history')

    def test_warm_current52_rejects_same_size_mtime_old_missing_symlink_and_extra_inputs(self):
        root, paths = self.fixture(); raw = self.raw()
        repair.profile_history_inputs(raw, root, 'history')
        file = root / repair.DESCRIPTION_LEAF_PATH; source = file.read_bytes(); stamp = file.stat()
        for mutant in (bytes([source[0] ^ 1]) + source[1:], source.replace(b'\n', b'\r\n'),
                       repair.description_predecessor_source(repair.DESCRIPTION_LEAF_PATH, source)):
            file.write_bytes(mutant); os.utime(file, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.symlink_to(R / repair.DESCRIPTION_LEAF_PATH)
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink(); file.write_bytes(source)
        (root / 'unknown-input').write_text('unreviewed')
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')

    def test_club_fixture_producer_is_exact52_and_its_complete_7b_predecessor_restores(self):
        club = repair.actor_predecessor_fixture_helper(R)
        paths = set(club.SOURCE_EDITS) | set(club.ADDED_SUPPORT) | {club.CONTRACT_PATH, repair.RUNNER_PATH} | set(club.EVOLUTION_SOURCES) | set(club.EVOLUTION_SUPPORT) | set(club.FLOOR_INPUTS)
        expected = set(repair.PROFILE_CONTEXT_INPUTS) | set(repair.REPAIR_LEAF_PATHS) | set(repair.NATIVE_CURRENT_INPUTS) | {repair.DESCRIPTION_LEAF_PATH}
        self.assertEqual(paths, expected); self.assertEqual(len(paths), 52)
        path = repair.DESCRIPTION_HELPER_PATH; raw = (R / path).read_bytes()
        self.assertEqual(repair.digest(repair.description_predecessor_source(path, raw)), '379ada64233f6a51f52d5ca595c9092632f248e23c50825aa989ff0882fcfd88')

    def test_all_original_test_methods_preserve_complete_source_spans(self):
        import ast
        source = (R / 'tools/tests/test_readiness_contract_parse_cache.py').read_text()
        prefix = source.split('\nclass DescriptionInitializationCompileAdmissionTests', 1)[0]
        lines = prefix.splitlines(True); methods = []
        for node in ast.walk(ast.parse(prefix)):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith('test_'):
                start = min([node.lineno] + [d.lineno for d in node.decorator_list])
                methods.append((node.name, ''.join(lines[start-1:node.end_lineno])))
        self.assertEqual(len(methods), 32)
        self.assertEqual(repair.digest(json.dumps(methods, ensure_ascii=True, separators=(',', ':')).encode()), '4b409b92c48e2ff34c0a51234e15345b28e7796b80f854e4495c7cf0798a0403')


ACTOR_TEST_INPUT_HUNKS = [{'before': '            file.write_bytes((R / path).read_bytes())\n        return root, paths\n',
  'after': '            file.write_bytes(repair.actor_predecessor_fixture_source(\n'
           '                path, (R / path).read_bytes(), self.raw()))\n'
           '        return root, paths\n'},
 {'before': '    def test_club_fixture_producer_is_exact52_and_its_complete_7b_predecessor_restores(self):\n'
            '        from tools import club_customer_directory_admission as club\n',
  'after': '    def test_club_fixture_producer_is_exact52_and_its_complete_7b_predecessor_restores(self):\n'
           '        club = repair.actor_predecessor_fixture_helper(R)\n'}]

class SocialReaderKeyActorCompileAdmissionTests(unittest.TestCase):
    """Actual current53 precedes exact published42/52, 7b51, c2af49 and 47."""

    def raw(self):
        return (R / repair.CONTRACT_PATH).read_bytes()

    def fixture(self):
        life = tempfile.TemporaryDirectory(prefix='actor-current53-')
        self.addCleanup(life.cleanup)
        root = Path(life.name)
        paths = set(repair.PROFILE_CONTEXT_INPUTS) | set(repair.REPAIR_LEAF_PATHS) | set(repair.NATIVE_CURRENT_INPUTS) | {repair.DESCRIPTION_LEAF_PATH, repair.ACTOR_LEAF_PATH}
        self.assertEqual(len(paths), 53)
        for path in paths:
            file = root / path; file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(repair.album_predecessor_fixture_source(
                path, (R / path).read_bytes(), self.raw()))
        return root, paths

    def test_exact_actor_hunk_changes_only_reader_key_initializer(self):
        path = repair.ACTOR_LEAF_PATH; source = (R / path).read_bytes()
        row = repair.ACTOR_LEAF_ROW
        self.assertEqual(row['before_sha256'], 'f79b53c8f0ab4ecdd4a21c2d23fe6a1c7b1040c50680dd6b6c1093cdcb3f2c5b')
        self.assertEqual(row['after_sha256'], '0e14cc76c72416cf152f8edbd02383251b2671952f958a18af078e883f4ffc51')
        self.assertEqual(row['hunks'], [{'before': '        init(_ reader: any DiscoveryReading) {\n',
                                         'after': '        @MainActor init(_ reader: any DiscoveryReading) {\n'}])
        old = repair.actor_predecessor_source(path, source)
        self.assertEqual(repair.digest(old), row['before_sha256'])
        self.assertEqual(source, old.replace(row['hunks'][0]['before'].encode(), row['hunks'][0]['after'].encode(), 1))

    def test_complete_actor_contract_restores_exact_42_and_every_older_floor(self):
        value = repair.album_predecessor_contract(json.loads(self.raw())); old = repair.actor_predecessor_contract(value)
        self.assertEqual(repair.digest(repair.encode(old)), '6fa7fd18b5000d3843f4c5809d58cd97f0b40dd0b3b41ad933583aa6250522e4')
        self.assertEqual(len(value['feature_batch_sources']), 135)
        self.assertEqual(len(old['feature_batch_sources']), 134)
        self.assertEqual(len(value['feature_batch_support_sha256']), 521)
        self.assertNotIn(repair.ACTOR_LEAF_PATH, old['feature_batch_sources'])
        self.assertEqual(value['node_description_sources'], old['node_description_sources'])
        for reader, expected in [(repair.description_predecessor_contract, '9c26993734c6ba8d4623165187cb0cfcebc1ff20e3c9209da7a2982099ee2cb6'),
                                 (repair.native_predecessor_contract, 'd3fedafc9efe917220f4c52cb4c82d742f840a7307546da35e4da130a80d7fdb'),
                                 (repair.repair_predecessor_contract, 'b72d9b1024daadb5273a4de24c0175d42c04516b1f89c6c53c0f9c40dd7a77b6')]:
            self.assertEqual(repair.digest(repair.encode(reader(value))), expected)

    def test_complete_actor_source_interfaces_restore_exact_42_bytes(self):
        for path, expected in repair.ACTOR_PRE_SHA256.items():
            source = (R / path).read_bytes()
            self.assertEqual(repair.digest(repair.actor_predecessor_source(path, source)), expected)
            for mutant in (source + b'\n', source.replace(b'\n', b'\r\n'), bytes([source[0] ^ 1]) + source[1:]):
                with self.subTest(path=path), self.assertRaises((AssertionError, ValueError)):
                    repair.actor_predecessor_source(path, mutant)

    def test_review_projection_exact_single_hunk_restores_42_then_native_predecessor(self):
        path = repair.ACTOR_PROJECTION_PATH; source = (R / path).read_bytes()
        row = repair.ACTOR_PROJECTION_ROW
        self.assertEqual(row['before_sha256'], '7e14668c3ab789f3903971a8de30a828c1cac36c6755d67f81e92ef29356c7f1')
        self.assertEqual(row['after_sha256'], '3980907d0a3d33e40f229c6f856ac78024b18498ea7c3f4dcd28d34862f8b280')
        self.assertEqual(len(row['hunks']), 1)
        before = repair.actor_predecessor_source(path, source)
        self.assertEqual(repair.digest(before), row['before_sha256'])
        self.assertEqual(source, before.replace(row['hunks'][0]['before'].encode(), row['hunks'][0]['after'].encode(), 1))
        self.assertEqual(repair.digest(repair.native_predecessor_source(path, source)), 'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727')
        value = json.loads(self.raw()); old = repair.actor_predecessor_contract(value)
        self.assertEqual(value['entry_projection_module_sha256'], row['after_sha256'])
        self.assertEqual(old['entry_projection_module_sha256'], row['before_sha256'])

    def test_review_projection_actual_old_missing_same_stat_and_coherent_repin_rejected(self):
        path = R / repair.ACTOR_PROJECTION_PATH
        contract = R / repair.CONTRACT_PATH; runner = R / repair.RUNNER_PATH
        saved = {p: (p.read_bytes(), p.stat()) for p in (path, contract, runner)}
        for p, (_, stamp) in saved.items(): self.assertEqual(stamp.st_nlink, 1, str(p))
        raw = saved[contract][0]; source = saved[path][0]
        repair.checked_current(raw, R)
        def restore():
            for p, (data, stamp) in saved.items():
                p.write_bytes(data); os.utime(p, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        try:
            for mutant in (repair.actor_predecessor_source(repair.ACTOR_PROJECTION_PATH, source),
                           bytes([source[0] ^ 1]) + source[1:]):
                path.write_bytes(mutant); os.utime(path, ns=(saved[path][1].st_atime_ns, saved[path][1].st_mtime_ns))
                with self.assertRaises((AssertionError, ValueError)): repair.checked_current(raw, R)
            restore(); path.unlink()
            with self.assertRaises((AssertionError, ValueError, OSError)): repair.checked_current(raw, R)
            restore()
            mutant = bytes([source[0] ^ 1]) + source[1:]
            value = json.loads(raw); value['entry_projection_module_sha256'] = repair.digest(mutant)
            changed = repair.encode(value)
            path.write_bytes(mutant); contract.write_bytes(changed)
            runner.write_bytes(saved[runner][0].replace(repair.digest(raw).encode(), repair.digest(changed).encode(), 1))
            with self.assertRaises((AssertionError, ValueError)): repair.checked_current(changed, R)
        finally:
            restore()
        repair.checked_current(raw, R)

    def test_review_projection_current53_old_or_missing_never_uses_healthy_root(self):
        root, paths = self.fixture(); self.assertEqual(len(paths), 53); raw = self.raw()
        file = root / repair.ACTOR_PROJECTION_PATH; source = file.read_bytes(); stamp = file.stat()
        repair.profile_history_inputs(raw, root, 'history')
        for mutant in (repair.actor_predecessor_source(repair.ACTOR_PROJECTION_PATH, source),
                       bytes([source[0] ^ 1]) + source[1:]):
            file.write_bytes(mutant); os.utime(file, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')

    def test_actor_hunk_missing_duplicate_and_off_hunk_bytes_fail_closed(self):
        path = repair.ACTOR_LEAF_PATH; source = (R / path).read_bytes()
        hunk = repair.ACTOR_LEAF_ROW['hunks'][0]['after'].encode()
        for mutant in (source.replace(hunk, b'', 1), source + hunk,
                       source.replace(b'@MainActor init', b'@MainActor  init', 1),
                       source.replace(b'ObjectIdentifier(reader)', b'ObjectIdentifier( reader)', 1)):
            with self.assertRaises(AssertionError): repair.actor_predecessor_source(path, mutant)

    def test_old_actor_leaf_and_coherent_contract_runner_repins_never_admit(self):
        path = R / repair.ACTOR_LEAF_PATH; source = path.read_bytes(); raw = self.raw()
        runnerpath = R / repair.RUNNER_PATH; runner = runnerpath.read_bytes()
        repair.checked_current(raw, R)
        for mutant in (repair.actor_predecessor_source(repair.ACTOR_LEAF_PATH, source),
                       bytes([source[0] ^ 1]) + source[1:]):
            value = json.loads(raw)
            value['feature_batch_sources'][repair.ACTOR_LEAF_PATH]['after_sha256'] = repair.digest(mutant)
            value['feature_batch_support_sha256'][repair.ACTOR_LEAF_PATH] = repair.digest(mutant)
            changed = repair.encode(value)
            replacements = {path: mutant, R / repair.CONTRACT_PATH: changed,
                            runnerpath: runner.replace(repair.digest(raw).encode(), repair.digest(changed).encode(), 1)}
            original = Path.read_bytes
            with patch.object(Path, 'read_bytes', lambda p: replacements[p] if p in replacements else original(p)):
                with self.assertRaises((AssertionError, ValueError)): repair.checked_current(changed, R)

    def test_current53_all_physical_reads_precede_history_and_missing_leaf_is_not_52(self):
        root, paths = self.fixture(); raw = self.raw(); original = Path.read_bytes; reads = []
        def read(path):
            if path.is_relative_to(root): reads.append(str(path.relative_to(root)))
            return original(path)
        with patch.object(Path, 'read_bytes', read): repair._profile_parent_inputs(root)
        self.assertEqual(set(reads), paths); self.assertEqual(len(reads), 53)
        (root / repair.ACTOR_LEAF_PATH).unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        for path in paths - {repair.ACTOR_LEAF_PATH}:
            (root / path).write_bytes(repair.actor_predecessor_fixture_source(path, (R / path).read_bytes(), raw))
        repair.profile_history_inputs(raw, root, 'history')
        self.assertEqual({str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}, paths - {repair.ACTOR_LEAF_PATH})

    def test_warm_current53_rejects_same_stat_crlf_cr_old_missing_symlink_and_extra(self):
        root, _ = self.fixture(); raw = self.raw()
        repair.profile_history_inputs(raw, root, 'history')
        file = root / repair.ACTOR_LEAF_PATH; source = file.read_bytes(); stamp = file.stat()
        for mutant in (bytes([source[0] ^ 1]) + source[1:], source.replace(b'\n', b'\r\n'),
                       source.replace(b'\n', b'\r'), repair.actor_predecessor_source(repair.ACTOR_LEAF_PATH, source)):
            file.write_bytes(mutant); os.utime(file, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.symlink_to(R / repair.ACTOR_LEAF_PATH)
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink(); file.write_bytes(source); (root / 'unknown-input').write_text('unreviewed')
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')

    def test_current53_helper_and_explicit_historical52_helper_are_separate(self):
        club = repair.album_predecessor_fixture_helper(R)
        def paths(helper):
            return set(helper.SOURCE_EDITS) | set(helper.ADDED_SUPPORT) | {helper.CONTRACT_PATH, repair.RUNNER_PATH} | set(helper.EVOLUTION_SOURCES) | set(helper.EVOLUTION_SUPPORT) | set(helper.FLOOR_INPUTS)
        current_paths = paths(club); old = repair.actor_predecessor_fixture_helper(R)
        self.assertEqual(len(current_paths), 53); self.assertEqual(len(paths(old)), 52)
        self.assertEqual(current_paths - paths(old), {repair.ACTOR_LEAF_PATH})
        self.assertEqual(repair.digest(repair.actor_predecessor_source(repair.ACTOR_HELPER_PATH, (R / repair.ACTOR_HELPER_PATH).read_bytes())), 'b8c6be27289110f7bf75d01d28fd41d9778b90dd7c32b78cf0ff849aa1916977')

    def test_42_contract_is_historical_only_and_cannot_enter_checked_current(self):
        raw = self.raw(); value = json.loads(raw)
        old = repair.encode(repair.actor_predecessor_contract(value))
        with self.assertRaises((AssertionError, ValueError)): repair.checked_current(old, R)
        mixed = json.loads(raw); mixed['feature_batch_sources'].pop(repair.ACTOR_LEAF_PATH)
        with self.assertRaises((AssertionError, ValueError)): repair.actor_predecessor_contract(mixed)

    def test_direct_current_reader_rejects_foreign_rows_even_with_exact_historical_argument(self):
        raw = self.raw(); value = json.loads(raw)
        old = repair.actor_predecessor_contract(value)
        runnerpath = R / repair.RUNNER_PATH; runner = runnerpath.read_bytes()
        changed_value = json.loads(raw); changed_value['unreviewed_actor_boundary'] = True
        changed = repair.encode(changed_value)
        replacements = {R / repair.CONTRACT_PATH: changed,
                        runnerpath: runner.replace(repair.digest(raw).encode(), repair.digest(changed).encode(), 1)}
        original = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda p: replacements[p] if p in replacements else original(p)):
            for operation in (lambda: repair.actor_current_inputs(changed_value, R),
                              lambda: repair.description_current_inputs(old, R),
                              lambda: repair.actor_predecessor_fixture_helper(R)):
                with self.assertRaises((AssertionError, ValueError)): operation()

    def test_all_original_40_methods_restore_exactly_with_only_declared_reader_adapter(self):
        import ast
        source = (R / 'tools/tests/test_readiness_contract_parse_cache.py').read_text()
        prefix = source.split('\n\nACTOR_TEST_INPUT_HUNKS = ', 1)[0]
        for row in reversed(ACTOR_TEST_INPUT_HUNKS):
            self.assertEqual(prefix.count(row['after']), 1)
            prefix = prefix.replace(row['after'], row['before'], 1)
        self.assertEqual(repair.digest(prefix.encode()), '17972c390160fc43ee60ab9aad05446081b9346423a8f77a237c3d38e7839c68')
        lines = prefix.splitlines(True); methods = []
        for node in ast.walk(ast.parse(prefix)):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith('test_'):
                start = min([node.lineno] + [d.lineno for d in node.decorator_list])
                methods.append((node.name, ''.join(lines[start-1:node.end_lineno])))
        self.assertEqual(len(methods), 40)
        self.assertEqual(repair.digest(json.dumps(methods, ensure_ascii=True, separators=(',', ':')).encode()), 'f88736ab97604bbe3aeb8d63e91d4434e8114febe2b4d82720d8652e183d44e4')


ALBUM_TEST_INPUT_HUNKS = [{'before': '            file.write_bytes((R / path).read_bytes())\n        return root, paths\n',
  'after': '            file.write_bytes(repair.album_predecessor_fixture_source(\n'
           '                path, (R / path).read_bytes(), self.raw()))\n'
           '        return root, paths\n'},
 {'before': '    def test_complete_actor_contract_restores_exact_42_and_every_older_floor(self):\n'
            '        value = json.loads(self.raw()); old = repair.actor_predecessor_contract(value)\n',
  'after': '    def test_complete_actor_contract_restores_exact_42_and_every_older_floor(self):\n'
           '        value = repair.album_predecessor_contract(json.loads(self.raw())); old = '
           'repair.actor_predecessor_contract(value)\n'},
 {'before': '    def test_current53_helper_and_explicit_historical52_helper_are_separate(self):\n'
            '        from tools import club_customer_directory_admission as club\n',
  'after': '    def test_current53_helper_and_explicit_historical52_helper_are_separate(self):\n'
           '        club = repair.album_predecessor_fixture_helper(R)\n'}]
class AlbumChapterActorCompileAdmissionTests(unittest.TestCase):
    """Actual current54 precedes exact bb5/53, 42/52, 7b51, c2af49 and 47."""
    def raw(self):
        return (R / repair.CONTRACT_PATH).read_bytes()

    def fixture(self):
        life = tempfile.TemporaryDirectory(prefix='album-current54-')
        self.addCleanup(life.cleanup)
        root = Path(life.name)
        paths = set(repair.PROFILE_CONTEXT_INPUTS) | set(repair.REPAIR_LEAF_PATHS) | set(repair.NATIVE_CURRENT_INPUTS) | {repair.DESCRIPTION_LEAF_PATH, repair.ACTOR_LEAF_PATH, repair.ALBUM_LEAF_PATH}
        self.assertEqual(len(paths), 54)
        for path in paths:
            file = root / path; file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes((R / path).read_bytes())
        return root, paths

    def test_complete_album_contract_restores_exact_bb5_and_every_older_floor(self):
        value = json.loads(self.raw()); old = repair.album_predecessor_contract(value)
        self.assertEqual(repair.digest(repair.encode(old)), '5510daa8a177c8cc51a4459f3db5a4ee53cfda0a48c4cbff5dc8af5b0113d3e3')
        self.assertEqual(len(value['feature_batch_sources']), 136)
        self.assertEqual(len(old['feature_batch_sources']), 135)
        self.assertEqual(len(value['feature_batch_support_sha256']), 521)
        self.assertNotIn(repair.ALBUM_LEAF_PATH, old['feature_batch_sources'])
        self.assertEqual(value['node_description_sources'], old['node_description_sources'])
        for reader, expected in [(repair.actor_predecessor_contract, '6fa7fd18b5000d3843f4c5809d58cd97f0b40dd0b3b41ad933583aa6250522e4'),
                                 (repair.description_predecessor_contract, '9c26993734c6ba8d4623165187cb0cfcebc1ff20e3c9209da7a2982099ee2cb6'),
                                 (repair.native_predecessor_contract, 'd3fedafc9efe917220f4c52cb4c82d742f840a7307546da35e4da130a80d7fdb'),
                                 (repair.repair_predecessor_contract, 'b72d9b1024daadb5273a4de24c0175d42c04516b1f89c6c53c0f9c40dd7a77b6')]:
            self.assertEqual(repair.digest(repair.encode(reader(value))), expected)

    def test_complete_album_source_interfaces_restore_exact_bb5_bytes(self):
        for path, expected in repair.ALBUM_PRE_SHA256.items():
            source = (R / path).read_bytes()
            self.assertEqual(repair.digest(repair.album_predecessor_source(path, source)), expected)
            for mutant in (source + b'\n', source.replace(b'\n', b'\r\n'), bytes([source[0] ^ 1]) + source[1:]):
                with self.subTest(path=path), self.assertRaises((AssertionError, ValueError)):
                    repair.album_predecessor_source(path, mutant)

    def test_album_hunk_missing_duplicate_and_off_hunk_bytes_fail_closed(self):
        path = repair.ALBUM_LEAF_PATH; source = (R / path).read_bytes()
        hunk = repair.ALBUM_LEAF_ROW['hunks'][0]['after'].encode()
        for mutant in (source.replace(hunk, b'', 1), source + hunk,
                       source.replace(b'@MainActor var', b'@MainActor  var', 1),
                       source.replace(b'editor.draft.chapters[0].id', b'editor.draft.chapters[1].id', 1)):
            with self.assertRaises(AssertionError): repair.album_predecessor_source(path, mutant)

    def test_old_album_leaf_and_coherent_contract_runner_repins_never_admit(self):
        path = R / repair.ALBUM_LEAF_PATH; source = path.read_bytes(); raw = self.raw()
        runnerpath = R / repair.RUNNER_PATH; runner = runnerpath.read_bytes()
        repair.checked_current(raw, R)
        for mutant in (repair.album_predecessor_source(repair.ALBUM_LEAF_PATH, source),
                       bytes([source[0] ^ 1]) + source[1:]):
            value = json.loads(raw)
            value['feature_batch_sources'][repair.ALBUM_LEAF_PATH]['after_sha256'] = repair.digest(mutant)
            value['feature_batch_support_sha256'][repair.ALBUM_LEAF_PATH] = repair.digest(mutant)
            changed = repair.encode(value)
            replacements = {path: mutant, R / repair.CONTRACT_PATH: changed,
                            runnerpath: runner.replace(repair.digest(raw).encode(), repair.digest(changed).encode(), 1)}
            original = Path.read_bytes
            with patch.object(Path, 'read_bytes', lambda p: replacements[p] if p in replacements else original(p)):
                with self.assertRaises((AssertionError, ValueError)): repair.checked_current(changed, R)

    def test_current54_all_physical_reads_precede_history_and_missing_leaf_is_not_53(self):
        root, paths = self.fixture(); raw = self.raw(); original = Path.read_bytes; reads = []
        def read(path):
            if path.is_relative_to(root): reads.append(str(path.relative_to(root)))
            return original(path)
        with patch.object(Path, 'read_bytes', read): repair._profile_parent_inputs(root)
        self.assertEqual(set(reads), paths); self.assertEqual(len(reads), 54)
        (root / repair.ALBUM_LEAF_PATH).unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        for path in paths - {repair.ALBUM_LEAF_PATH}:
            (root / path).write_bytes(repair.album_predecessor_fixture_source(path, (R / path).read_bytes(), raw))
        repair.profile_history_inputs(raw, root, 'history')
        self.assertEqual({str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}, paths - {repair.ALBUM_LEAF_PATH})

    def test_warm_current54_rejects_same_stat_crlf_cr_old_missing_symlink_and_extra(self):
        root, _ = self.fixture(); raw = self.raw()
        repair.profile_history_inputs(raw, root, 'history')
        file = root / repair.ALBUM_LEAF_PATH; source = file.read_bytes(); stamp = file.stat()
        for mutant in (bytes([source[0] ^ 1]) + source[1:], source.replace(b'\n', b'\r\n'),
                       source.replace(b'\n', b'\r'), repair.album_predecessor_source(repair.ALBUM_LEAF_PATH, source)):
            file.write_bytes(mutant); os.utime(file, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink()
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.symlink_to(R / repair.ALBUM_LEAF_PATH)
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')
        file.unlink(); file.write_bytes(source); (root / 'unknown-input').write_text('unreviewed')
        with self.assertRaises(ValueError): repair.profile_history_inputs(raw, root, 'history')

    def test_current54_helper_and_explicit_historical53_helper_are_separate(self):
        from tools import club_customer_directory_admission as club
        def paths(helper):
            return set(helper.SOURCE_EDITS) | set(helper.ADDED_SUPPORT) | {helper.CONTRACT_PATH, repair.RUNNER_PATH} | set(helper.EVOLUTION_SOURCES) | set(helper.EVOLUTION_SUPPORT) | set(helper.FLOOR_INPUTS)
        current_paths = paths(club); old = repair.album_predecessor_fixture_helper(R)
        self.assertEqual(len(current_paths), 54); self.assertEqual(len(paths(old)), 53)
        self.assertEqual(current_paths - paths(old), {repair.ALBUM_LEAF_PATH})
        self.assertEqual(repair.digest(repair.album_predecessor_source(repair.ALBUM_HELPER_PATH, (R / repair.ALBUM_HELPER_PATH).read_bytes())), '7b2bba4759677e0091b5149a7fc46096280b95ac2b7e94cd77481a24570afb35')

    def test_bb5_contract_is_historical_only_and_cannot_enter_checked_current(self):
        raw = self.raw(); value = json.loads(raw)
        old = repair.encode(repair.album_predecessor_contract(value))
        with self.assertRaises((AssertionError, ValueError)): repair.checked_current(old, R)
        mixed = json.loads(raw); mixed['feature_batch_sources'].pop(repair.ALBUM_LEAF_PATH)
        with self.assertRaises((AssertionError, ValueError)): repair.album_predecessor_contract(mixed)

    def test_direct_current_reader_rejects_foreign_rows_even_with_exact_historical_argument(self):
        raw = self.raw(); value = json.loads(raw)
        old = repair.album_predecessor_contract(value)
        runnerpath = R / repair.RUNNER_PATH; runner = runnerpath.read_bytes()
        changed_value = json.loads(raw); changed_value['unreviewed_album_boundary'] = True
        changed = repair.encode(changed_value)
        replacements = {R / repair.CONTRACT_PATH: changed,
                        runnerpath: runner.replace(repair.digest(raw).encode(), repair.digest(changed).encode(), 1)}
        original = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda p: replacements[p] if p in replacements else original(p)):
            for operation in (lambda: repair.album_current_inputs(changed_value, R),
                              lambda: repair.description_current_inputs(old, R),
                              lambda: repair.album_predecessor_fixture_helper(R)):
                with self.assertRaises((AssertionError, ValueError)): operation()

    def test_exact_album_hunk_preserves_all_nine_swift_tests_and_assertions(self):
        import re
        path = repair.ALBUM_LEAF_PATH; source = (R / path).read_bytes()
        row = repair.ALBUM_LEAF_ROW
        self.assertEqual(row['before_sha256'], '3d3c8ef9236f3d5a0c2b99c9eb6ce2b57c3afc36aaabdd701d1597855f024257')
        self.assertEqual(row['after_sha256'], '5c74526f40c44327ec68254de76bd4c316e976b5aa1f6a409502774402699054')
        self.assertEqual(row['hunks'], [{'before': '        var chapterID: String { editor.draft.chapters[0].id }\n',
                                        'after': '        @MainActor var chapterID: String { editor.draft.chapters[0].id }\n'}])
        old = repair.album_predecessor_source(path, source)
        self.assertEqual(repair.digest(old), row['before_sha256'])
        self.assertEqual(source, old.replace(row['hunks'][0]['before'].encode(), row['hunks'][0]['after'].encode(), 1))
        self.assertEqual(len(re.findall(rb'(?m)^    func test', source)), 9)
        self.assertEqual(source[source.index(b'    func test'):], old[old.index(b'    func test'):])
        self.assertEqual([line for line in source.splitlines() if b'XCTAssert' in line],
                         [line for line in old.splitlines() if b'XCTAssert' in line])

    def test_projection_and_node_description_contract_members_remain_exact(self):
        value = json.loads(self.raw()); old = repair.album_predecessor_contract(value)
        projection = 'tools/run138_current_source_projection.py'
        self.assertEqual(repair.digest((R / projection).read_bytes()), '3980907d0a3d33e40f229c6f856ac78024b18498ea7c3f4dcd28d34862f8b280')
        self.assertEqual(value['entry_projection_module_sha256'], old['entry_projection_module_sha256'])
        self.assertEqual(value['node_description_sources'], old['node_description_sources'])
        self.assertEqual(repair.album_predecessor_source(projection, (R / projection).read_bytes()), (R / projection).read_bytes())

    def test_all_original_54_methods_and_assertions_restore_exactly(self):
        import ast
        source = (R / 'tools/tests/test_readiness_contract_parse_cache.py').read_text()
        prefix = source.split('\n\nALBUM_TEST_INPUT_HUNKS = ', 1)[0]
        adapted = prefix
        for row in reversed(ALBUM_TEST_INPUT_HUNKS):
            self.assertEqual(prefix.count(row['after']), 1)
            prefix = prefix.replace(row['after'], row['before'], 1)
        self.assertEqual(repair.digest(prefix.encode()), 'b6e48dc88dc38df042e12e7a55d9ffe45773a20e098c380064baf0d3abf262a8')
        lines = prefix.splitlines(True); methods = []
        for node in ast.walk(ast.parse(prefix)):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith('test_'):
                start = min([node.lineno] + [d.lineno for d in node.decorator_list])
                methods.append((node.name, ''.join(lines[start-1:node.end_lineno])))
        self.assertEqual(len(methods), 54)
        self.assertEqual(repair.digest(json.dumps(methods, ensure_ascii=True, separators=(',', ':')).encode()), '3d20a7b91f754887e6da0734f1e94a2ec2b5b87093b20ece6692c59ce2931d9f')
        def assertions(text):
            return [ast.dump(n, include_attributes=False) for n in ast.walk(ast.parse(text))
                    if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr.startswith('assert')]
        self.assertEqual(assertions(adapted), assertions(prefix))


# Fixed predecessor source/fixture assertions use their exact published e2b root.
# The 7 parser and 2 member-copy tests above retain the actual current runner.
from tools import club_customer_directory_admission as _club_history
_CLUB_PARSE_HISTORY = _club_history.club_original_current_context(R)
_CLUB_PARSE_TESTS = _CLUB_PARSE_HISTORY.load('tools/tests/test_readiness_contract_parse_cache.py')


def _club_bind_historical_parse_class(case):
    from functools import wraps
    for name, original in tuple(vars(case).items()):
        if name.startswith('test_') and callable(original):
            def bind(function):
                @wraps(function)
                def checked(*args, **kwargs):
                    with _club_history.club_authenticated_transaction():
                        _CLUB_PARSE_HISTORY.verify()
                        try:
                            return function(*args, **kwargs)
                        finally:
                            _CLUB_PARSE_HISTORY.verify()
                return checked
            setattr(case, name, bind(original))
    return case


ReadinessParseCacheSourceChainTests = _club_bind_historical_parse_class(_CLUB_PARSE_TESTS.ReadinessParseCacheSourceChainTests)
UnifiedRepairCurrentInputTests = _club_bind_historical_parse_class(_CLUB_PARSE_TESTS.UnifiedRepairCurrentInputTests)
NativeNavigationCompileAdmissionTests = _club_bind_historical_parse_class(_CLUB_PARSE_TESTS.NativeNavigationCompileAdmissionTests)
DescriptionInitializationCompileAdmissionTests = _club_bind_historical_parse_class(_CLUB_PARSE_TESTS.DescriptionInitializationCompileAdmissionTests)
SocialReaderKeyActorCompileAdmissionTests = _club_bind_historical_parse_class(_CLUB_PARSE_TESTS.SocialReaderKeyActorCompileAdmissionTests)
AlbumChapterActorCompileAdmissionTests = _club_bind_historical_parse_class(_CLUB_PARSE_TESTS.AlbumChapterActorCompileAdmissionTests)
