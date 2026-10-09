"""Strict batch admission preserves all historical readers and raw-byte guards."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROBE = r'''
from contextlib import contextmanager, ExitStack
import hashlib, importlib, json, os, shutil, tempfile
from pathlib import Path
from unittest.mock import patch
from tools import run138_current_source_projection as entry
from tools import run138_editor_readiness as current
from tools.tests.player_map_history_budget_history import validated_pre_run129_directory
ROOT = Path.cwd()
CONFIG = [
 ('story_template_budget_history','materialize_pre_story_ui',(),'pre_run129_source'),
 ('club_parity_budget_history','materialize_pre_club_ui',(),'historical_pre_club_source'),
 ('creator_pending_budget_history','materialize_pre_creator_ui',(),'historical_pre_club_source'),
 ('combined_native_budget_history','materialize_independent_ui',('media',),'historical_pre_club_source'),
 ('combined_native_budget_history','materialize_independent_ui',('map',),'historical_pre_club_source'),
 ('player_map_history_budget_history','materialize_pre_player_ui',(),'pre_run129_source'),
 ('story_media_budget_history','materialize_historical_pre_media_ui',(),'historical_pre_media_ui_source'),
 ('reviewed_feature_budget_history','materialize_historical_pre_feature_ui',(),'historical_pre_feature_ui_source'),
 ('reviewed_map_budget_history','materialize_historical_pre_map_ui',(),'historical_pre_media_ui_source'),
]
MODES=[(importlib.import_module('tools.tests.'+m),f,a,r) for m,f,a,r in CONFIG]
@contextmanager
def change(path,kind):
 path=Path(path);old=path.read_bytes() if path.exists() else None;stat=path.stat() if path.exists() else None
 try:
  if kind=='delete':path.unlink()
  elif kind=='add':path.write_bytes(b'// Unreviewed file.\n')
  elif kind=='same_size_mtime':
   assert old;path.write_bytes(bytes([old[0]^1])+old[1:]);os.utime(path,ns=(stat.st_atime_ns,stat.st_mtime_ns));assert path.stat().st_size==stat.st_size and path.stat().st_mtime_ns==stat.st_mtime_ns
  elif kind=='crlf':
   assert b'\n' in old and b'\r\n' not in old;path.write_bytes(old.replace(b'\n',b'\r\n'))
  else:raise AssertionError(kind)
  yield
 finally:
  if old is None:
   if path.exists():path.unlink()
  else:path.write_bytes(old);os.utime(path,ns=(stat.st_atime_ns,stat.st_mtime_ns))
def rejected(action,contains=None):
 try:action()
 except (ValueError,AssertionError,FileNotFoundError) as error:
  if contains is not None:assert contains in str(error),str(error)
  return
 raise AssertionError('Tampered historical batch was accepted')
def call(mode,target):
 if target.exists():shutil.rmtree(target)
 module,fn,args,_=mode;return getattr(module,fn)(target,*args)
def output(target):return {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in target.glob('*.swift')}
report=[]
with tempfile.TemporaryDirectory() as temporary:
 target=Path(temporary)/'output'
 if CASE=='counts':
  for selected in MODES:
   module,fn,args,reader=selected;index=module.source_index()
   count=sum('historical_file' not in row for row in index[args[0]]['ui_sources']) if args else len(index.get('baseline_ui_sources',index.get('baseline_ui_filenames',[])))
   snapshots=[]
   for _ in range(2):
    if target.exists():shutil.rmtree(target)
    with patch.object(entry,'previous_directory',wraps=entry.previous_directory) as prior,patch.object(current,'validate_current',wraps=current.validate_current) as admitted,patch.object(module,reader,wraps=getattr(module,reader)) as historical:
     snapshots.append(output(call(selected,target)))
     assert prior.call_count==admitted.call_count==1,(fn,args,prior.call_count,admitted.call_count)
     assert historical.call_count==count,(fn,args,historical.call_count,count)
   assert snapshots[0]==snapshots[1];report.append([fn,list(args),len(snapshots[0]),count])
 elif CASE.startswith(('current:','cached:')):
  where,kind=CASE.split(':');cached=entry.previous_directory(ROOT/'Tests/AppUITests')
  directory=ROOT/'Tests/AppUITests' if where=='current' else cached
  path=directory/('Unreviewed.swift' if kind=='add' else 'TicketWalletFlowTests.swift')
  with change(path,kind):
   for selected in MODES:rejected(lambda:call(selected,target))
 elif CASE=='dependencies':
  for relative in ['tools/club_parity_planning_contract.json','Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift','App/ProjectEditView.swift']:
   entry.previous_directory(ROOT/'Tests/AppUITests')
   with change(ROOT/relative,'same_size_mtime'):
    for selected in MODES:rejected(lambda:call(selected,target))
 elif CASE=='during_each':
  for selected in MODES:
   module,fn,args,reader=selected;original=getattr(module,reader);seen=[]
   with ExitStack() as changes:
    def altered(*a,**kw):
     value=original(*a,**kw)
     if not seen:seen.append(True);changes.enter_context(change(ROOT/'README.md','same_size_mtime'))
     return value
    with patch.object(module,reader,side_effect=altered):rejected(lambda:call(selected,target),'Current inputs changed during historical UI materialization')
    assert seen,(fn,args)
 elif CASE=='boundaries':
  cached=entry.previous_directory(ROOT/'Tests/AppUITests')
  for directory,name in [(ROOT,'README.md'),(cached,'TicketWalletFlowTests.swift')]:
   for kind in ['same_size_mtime','crlf','delete','add']:
    path=directory/('batch-unreviewed.txt' if kind=='add' else name)
    with ExitStack() as changes:
     def run():
      with validated_pre_run129_directory(ROOT):changes.enter_context(change(path,kind))
     rejected(run)
 elif CASE=='copied_root':
  copied=Path(temporary)/'copied-source'
  shutil.copytree(ROOT,copied,ignore=lambda directory,names:entry.ignore_context_names(ROOT,directory,names))
  assert output(copied/'Tests/AppUITests')==output(ROOT/'Tests/AppUITests')
  # Even a complete clean alternate root is unsupported. It must never borrow
  # admission of the module's original root, including after a dependency edit.
  for corrupt in [False,True]:
   if corrupt:
    dependency=copied/'tools/club_parity_planning_contract.json';dependency.write_bytes(dependency.read_bytes()+b'\n')
   def run():
    with validated_pre_run129_directory(copied):raise AssertionError('Alternate root reached historical reads')
   rejected(run,'Historical batch root differs from current admission root')
 elif CASE=='reader_errors':
  for selected in MODES:
   module,fn,args,reader=selected;original=getattr(module,reader);seen=[];returned=[]
   def broken(*a,**kw):
    seen.append(True)
    if len(seen)==2:raise RuntimeError('Injected historical reader failure')
    return original(*a,**kw)
   with patch.object(module,reader,side_effect=broken):
    try:returned.append(call(selected,target))
    except RuntimeError as error:assert str(error)=='Injected historical reader failure'
    else:raise AssertionError('Historical read failure returned a successful projection')
   assert not returned and len(seen)==2,(fn,args)
   index=module.source_index()
   expected=len(index[args[0]]['ui_sources']) if args else len(index.get('baseline_ui_sources',index.get('baseline_ui_filenames',[])))
   assert len(output(target))<expected,(fn,args)
 elif CASE=='historical_pins':
  club=MODES[1][0];row=club.source_index()['historical_sources']['Tests/AppUITests/ClubOperationsFlowTests.swift']
  cases=[(club.FIXTURES/row['historical_file'],MODES[1]),(ROOT/'tools/tests/fixtures/run129_repairs/source-index.json',MODES[0]),(ROOT/'tools/tests/fixtures/story_template/source-index.json',MODES[0])]
  for path,selected in cases:
   with change(path,'same_size_mtime'):rejected(lambda:call(selected,target))
 else:raise AssertionError(CASE)
print(json.dumps({'case':CASE,'passed':True,'outputs':report}))
'''


class HistoricalMaterializerBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from tools import run138_current_source_projection as entry
        cls.lifetime = tempfile.TemporaryDirectory(prefix='historical-batch-regression-')
        cls.addClassCleanup(cls.lifetime.cleanup)
        cls.root = Path(cls.lifetime.name) / 'source'
        shutil.copytree(ROOT, cls.root,
                        ignore=lambda directory, names: entry.ignore_context_names(ROOT, directory, names))

    def probe(self, case):
        result = subprocess.run([sys.executable, '-B', '-c', 'CASE = '+repr(case)+'\n'+PROBE],
                                cwd=self.root, capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout)['passed'])

    def test_one_admission_all_original_reads_and_exact_repeat_outputs(self):
        self.probe('counts')

    def test_current_and_cached_raw_bytes_and_membership_are_revalidated(self):
        for where in ['current', 'cached']:
            for kind in ['same_size_mtime', 'crlf', 'delete', 'add']:
                with self.subTest(where=where, kind=kind):
                    self.probe(where+':'+kind)

    def test_current_dependencies_cannot_bypass_warmed_cache_admission(self):
        self.probe('dependencies')

    def test_every_materializer_rechecks_current_bytes_after_its_reads(self):
        self.probe('during_each')

    def test_current_and_cached_dependency_changes_are_rejected_at_batch_end(self):
        self.probe('boundaries')

    def test_copied_roots_cannot_borrow_original_root_dependency_admission(self):
        self.probe('copied_root')

    def test_historical_reader_errors_never_return_a_successful_projection(self):
        self.probe('reader_errors')

    def test_original_historical_hash_pins_are_still_required(self):
        self.probe('historical_pins')


if __name__ == '__main__':
    unittest.main()
