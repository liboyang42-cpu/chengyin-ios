"""Exact, scoped batching of the retained independent media/map source gate."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
OLD_TEST_SHA256 = '4c4bbefb8a2743293852e1dd42203d626a9671b75da0ec128c222680614b70d6'
ADDED_IMPORT = 'from tools.tests.player_map_history_budget_history import validated_pre_run129_directory\n'
BEFORE = "   for row in source_index()[branch]['ui_sources']:\n    if 'historical_file' not in row:self.assertEqual(hashlib.sha256(historical_pre_club_source(ROOT/row['path']).read_bytes()).hexdigest(),row['sha256'])"
AFTER = "   with validated_pre_run129_directory(ROOT) as current:\n    for row in source_index()[branch]['ui_sources']:\n     if 'historical_file' not in row:self.assertEqual(hashlib.sha256(historical_pre_club_source(current/Path(row['path']).name).read_bytes()).hexdigest(),row['sha256'])"

PROBE = r'''
from contextlib import ExitStack, contextmanager
from pathlib import Path
import hashlib,json,os,unittest
from unittest.mock import patch
from tools import run138_editor_readiness as current
from tools import run138_current_source_projection as projection
from tools.tests import test_combined_native_budget as gate
ROOT = Path.cwd()
name = 'test_original_independent_source_snapshots_remain_bound'
case = gate.CombinedNativeBudgetTests(name)
@contextmanager
def mutate(path, add=False):
 old = None if add else path.read_bytes()
 stat = None if add else path.stat()
 try:
  path.write_bytes(b'changed membership\n' if add else bytes([old[0]^1])+old[1:])
  if stat is not None:
   os.utime(path, ns=(stat.st_atime_ns,stat.st_mtime_ns))
   assert path.stat().st_size == stat.st_size and path.stat().st_mtime_ns == stat.st_mtime_ns
  yield
 finally:
  if add: path.unlink()
  else:
   path.write_bytes(old);os.utime(path,ns=(stat.st_atime_ns,stat.st_mtime_ns))
def reject(action, allowed=(ValueError,AssertionError,FileNotFoundError), contains=None):
 try: action()
 except allowed as error:
  if contains is not None: assert contains in str(error),str(error)
  return type(error).__name__
 raise AssertionError('Mutant accepted')
if MODE == 'positive':
 with patch.object(current,'validate_current',wraps=current.validate_current) as admitted,patch.object(gate,'historical_pre_club_source',wraps=gate.historical_pre_club_source) as reader:
  result=unittest.TestResult();case.run(result)
  assert result.wasSuccessful(),str(result.errors)+str(result.failures)
  assert result.testsRun == 1
  assert admitted.call_count == 5, admitted.call_count
  rows=[row for branch in ['media','map'] for row in gate.source_index()[branch]['ui_sources'] if 'historical_file' not in row]
  assert reader.call_count == len(rows), (reader.call_count,len(rows))
  for call,row in zip(reader.call_args_list,rows):
   path=Path(call.args[0]);assert path.parent != ROOT/'Tests/AppUITests'
   assert row['path'] == 'Tests/AppUITests/'+path.name
   assert hashlib.sha256(gate.historical_pre_club_source(path).read_bytes()).hexdigest() == row['sha256']
  report={'admissions':admitted.call_count,'old_reader_calls':reader.call_count,'original_test_passed':True}
elif MODE == 'current_before':
 # Warm the real cache, then mutate actual admitted source with unchanged metadata.
 projection.previous_directory(ROOT/'Tests/AppUITests')
 with mutate(ROOT/'App/ProjectEditView.swift'):
  reject(lambda:getattr(case,name)())
 report={'rejected':1}
elif MODE == 'historical_before':
 historical=projection.previous_directory(ROOT/'Tests/AppUITests')
 with mutate(historical/'TicketWalletFlowTests.swift'):
  reject(lambda:getattr(case,name)())
 report={'rejected':1}
elif MODE.startswith('during_'):
 original=gate.historical_pre_club_source;seen=[]
 with ExitStack() as stack:
  def changed(path):
   value=original(path)
   if not seen:
    seen.append(True)
    if MODE=='during_current':stack.enter_context(mutate(ROOT/'README.md'))
    elif MODE=='during_membership':stack.enter_context(mutate(ROOT/'batch-extra-input.txt',True))
    elif MODE=='during_historical':stack.enter_context(mutate(Path(path).parent/'TicketWalletFlowTests.swift'))
    else:raise AssertionError(MODE)
   return value
  with patch.object(gate,'historical_pre_club_source',side_effect=changed):
   reject(lambda:getattr(case,name)())
  assert seen
 report={'rejected':1}
elif MODE=='reader_error':
 original=gate.historical_pre_club_source;calls=[]
 def broken(path):
  calls.append(path)
  if len(calls)==2:raise RuntimeError('sentinel historical reader error')
  return original(path)
 with patch.object(gate,'historical_pre_club_source',side_effect=broken):
  reject(lambda:getattr(case,name)(),(RuntimeError,),'sentinel historical reader error')
 assert len(calls)==2
 report={'rejected':1}
else:raise AssertionError(MODE)
print(json.dumps(report))
'''

class CombinedSnapshotBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from tools import run138_current_source_projection as projection
        cls.lifetime = tempfile.TemporaryDirectory(prefix='combined-snapshot-batch-')
        cls.addClassCleanup(cls.lifetime.cleanup)
        cls.root = Path(cls.lifetime.name) / 'source'
        shutil.copytree(ROOT, cls.root, ignore=lambda directory, names:
                        projection.ignore_context_names(ROOT, directory, names))

    def probe(self, mode):
        result = subprocess.run([sys.executable, '-B', '-c', 'MODE='+repr(mode)+'\n'+PROBE],
                                cwd=self.root, text=True, capture_output=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        return json.loads(result.stdout)

    def test_all_original_gate_bytes_restored_by_exact_two_edit_inverse(self):
        text = (ROOT/'tools/tests/test_combined_native_budget.py').read_text()
        self.assertEqual(text.count(ADDED_IMPORT), 1)
        self.assertEqual(text.count(AFTER), 1)
        original = text.replace(ADDED_IMPORT, '', 1).replace(AFTER, BEFORE, 1)
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), OLD_TEST_SHA256)

    def test_original_complete_case_all_rows_and_both_branch_admissions(self):
        self.assertTrue(self.probe('positive')['original_test_passed'])

    def test_fresh_current_and_warm_historical_bytes_cannot_bypass_admission(self):
        for mode in ['current_before','historical_before']:
            with self.subTest(mode=mode): self.assertEqual(self.probe(mode)['rejected'],1)

    def test_same_mtime_current_historical_and_membership_changes_fail_at_boundary(self):
        for mode in ['during_current','during_historical','during_membership']:
            with self.subTest(mode=mode): self.assertEqual(self.probe(mode)['rejected'],1)

    def test_historical_reader_failure_propagates_without_partial_success(self):
        self.assertEqual(self.probe('reader_error')['rejected'],1)

if __name__ == '__main__':
    unittest.main()
