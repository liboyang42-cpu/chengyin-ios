"""Exact joint source/budget proof; all runtime and Apple claims remain NOT_RUN."""
from contextlib import contextmanager
from copy import deepcopy
from decimal import Decimal
import hashlib,json,re,shutil,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import sys

# Match the repository test bootstrap before ci_gates imports test_products.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import branch_history_handshake_planning as layer,run130_receipt_planning as receipt,run_ui_shard as runner,ci_gates
ROOT=Path(__file__).resolve().parents[2]
from tools.run138_current_source_projection import frozen_context as readiness_prior_context
READINESS_PRIOR_CONTEXT = readiness_prior_context()
ROOT = READINESS_PRIOR_CONTEXT.root
layer = READINESS_PRIOR_CONTEXT.load('tools/branch_history_handshake_planning.py', 'run138_retained_handshake')
UI=ROOT/'Tests/AppUITests'
PROFILE=ROOT/'tools/ui_duration_weights.json'

class HandshakeBudgetTests(unittest.TestCase):
 def setUp(self):self.profile=json.loads(PROFILE.read_text());self.c=layer.contract()
 def costs(self,profile=None,ui=UI):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'profile.json';p.write_text(json.dumps(self.profile if profile is None else profile));return runner.measured_weights(ui,p)
 @contextmanager
 def copied_ui(self,folder='AppUITests'):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/folder;shutil.copytree(UI,path);yield path
 def test_all_168_files_736_methods_162_classes_are_exactly_bound(self):
  self.assertEqual(layer.validate_current(UI),self.c);self.assertEqual(len(self.c['current_ui_sources']),168)
  counts=runner.discover(UI);self.assertEqual((sum(counts.values()),len(counts)),(736,162));self.assertEqual(self.c['current_inventory'],receipt.contract()['current_inventory']);self.assertEqual(len(set(self.c['current_inventory'])),736)
 def test_five_line_inverse_retains_every_old_method_and_helper_byte(self):
  raw=(UI/layer.NAME).read_bytes();old=layer.original_source(raw);self.assertEqual(layer.digest(old),self.c['before_file_sha256']);self.assertEqual(len(self.c['added_exact_lines'].splitlines()),5)
  self.assertEqual(old.replace(b'            let close = ',self.c['added_exact_lines'].encode()+b'            let close = ',1),raw)
  previous=layer.previous_directory(UI);self.assertEqual({p.name:{'sha256':layer.digest(p.read_bytes())} for p in previous.glob('*.swift')},receipt.contract()['current_ui_sources'])
  for p in UI.glob('*.swift'):
   if p.name!=layer.NAME:self.assertEqual(p.read_bytes(),(previous/p.name).read_bytes())
  self.assertEqual(layer.previous_source(previous/layer.NAME),previous/layer.NAME)
 def test_490_plus160_is_derived_without_failed_run_timing_observations(self):
  self.assertEqual(self.c['derivation'],{'launch_count':2,'explicit_wait_caps_seconds':96,'reveal_count':6,'subtotal_seconds':488,'rounded_whole_method_seconds':490});self.assertEqual((self.c['previous_method_seconds'],self.c['method_seconds'],self.c['linear_seconds']),(410,490,160));self.assertIs(self.c['measured'],False)
  prior=layer.previous_profile(self.profile)
  for field in ['method_seconds','estimated_method_seconds','method_planning_floors']:self.assertEqual(self.profile[field],prior[field])
 def test_all_old_effective_class_costs_survive_and_only_history_gains80(self):
  prior=layer.frozen_receipt_context();self.addCleanup(prior.lifetime.cleanup);before=runner.measured_weights(prior.root/'Tests/AppUITests',prior.root/'tools/ui_duration_weights.json');after=self.costs();self.assertEqual(set(before),set(after))
  for name in before:self.assertEqual(after[name]-before[name],80 if name==layer.METHOD.split('.')[0] else 0)
  self.assertEqual(after[layer.METHOD.split('.')[0]],650);self.assertAlmostEqual(sum(before.values()),104625.381,places=7);self.assertAlmostEqual(sum(after.values()),104705.381,places=7)
 def test_twelve_exact_receipt_exceptions_and_every_older_profile_value_survive(self):
  prior=layer.previous_profile(self.profile);self.assertEqual(layer.canonical(prior),self.c['previous_profile_canonical_sha256']);self.assertEqual(layer.canonical(prior),receipt.contract()['current_profile_canonical_sha256']);exceptions=prior['planning_budget'][receipt.PLAN]['source_bound_over900_exceptions'];self.assertEqual(exceptions,receipt.FIXED_EXCEPTIONS);self.assertEqual(len(exceptions),12)
  for key,value in prior.items():
   if key=='planning_budget':
    for name,plan in value.items():self.assertEqual(self.profile[key][name],plan)
   else:self.assertEqual(self.profile[key],value)
 def test_79_shards_real_inventory_peak_headroom_and_generated_inventory_match(self):
  costs={k:Decimal(str(v)) for k,v in self.costs().items()};groups=runner.partition(costs,79);flat=sum(groups,[]);self.assertEqual(len(flat),len(set(flat)));self.assertEqual(set(flat),set(costs));self.assertEqual(len(groups),79);self.assertEqual((runner.DEFAULT_SHARD_COUNT,ci_gates.SHARD_COUNT),(79,79))
  peak=max(sum(costs[k] for k in g)+300 for g in groups);self.assertEqual(peak,Decimal('1765.141'));self.assertEqual(1800-peak,Decimal('34.859'));counts=runner.discover(UI);self.assertEqual(sum(counts[n] for n in flat),736)
  inv=json.loads((ROOT/'docs/ui-shard-inventory.json').read_text());self.assertEqual(inv['shards'],groups);self.assertEqual(inv['shard_test_counts'],[sum(counts[k] for k in g) for g in groups]);self.assertEqual(inv['inventory_sha256'],hashlib.sha256('\n'.join(self.c['current_inventory']).encode()).hexdigest())
  workflow=(ROOT/'.github/workflows/native-ios.yml').read_bytes();self.assertEqual(hashlib.sha256(workflow).hexdigest(),self.c['retained_receipt_audit_files']['.github/workflows/native-ios.yml']);self.assertIn(b'--deadline-seconds 1800',workflow);self.assertIn(b'timeout-minutes: 37',workflow)
 def test_missing_renamed_changed_plan_cannot_fall_back_in_copied_sources(self):
  for mode in ['remove','rename','all','490','160','measured','shards','delta','old_floor','exceptions']:
   p=deepcopy(self.profile);plan=p['planning_budget'][layer.PLAN]
   if mode=='remove':p['planning_budget'].pop(layer.PLAN)
   elif mode=='rename':p['planning_budget']['unknown']=p['planning_budget'].pop(layer.PLAN)
   elif mode=='all':p.pop('planning_budget')
   elif mode=='490':plan['whole_method_seconds'][layer.METHOD]=489
   elif mode=='160':plan['whole_method_seconds'][layer.LINEAR]=159
   elif mode=='measured':plan['measured']=True
   elif mode=='shards':plan['shard_count']=80
   elif mode=='delta':plan['additional_seconds']=0
   elif mode=='old_floor':p['method_planning_floors'].clear()
   else:p['planning_budget'][receipt.PLAN]['source_bound_over900_exceptions']['Other.testBad']=930
   with self.subTest(mode=mode),self.copied_ui('renamed-ui') as ui,self.assertRaises(ValueError):self.costs(p,ui)
 def test_current_plan_cannot_be_applied_to_exact_old_sources(self):
  old=layer.previous_directory(UI)
  with self.assertRaises(ValueError):self.costs(ui=old)
  with self.assertRaises(ValueError):layer.original_source((old/layer.NAME).read_bytes())
 def test_unknown_current_or_historical_bytes_never_accepted_by_inverse(self):
  old=layer.original_source((UI/layer.NAME).read_bytes())
  for raw in [(UI/layer.NAME).read_bytes()+b'\n',old+b'\n',b'']:
   with self.assertRaises(ValueError):layer.original_source(raw)
   with tempfile.TemporaryDirectory() as d:
    p=Path(d)/'AppUITests'/layer.NAME;p.parent.mkdir();p.write_bytes(raw)
    with self.assertRaises(ValueError):layer.previous_source(p)
 def test_source_assertion_helper_wait_and_identity_mutations_fail_closed(self):
  mutations=[('XCTAssertTrue(oldRow.isHittable)','XCTAssertTrue(true)'),('oldRow.waitForExistence(timeout: 5)','oldRow.waitForExistence(timeout: 0)'),('Synthetic courtyard','Other'),('apply.tap()','app.buttons["branchHistory.close"].tap()'),('waitForExpectations(timeout: 8)','waitForExpectations(timeout: 80)'),('app.launch(); return app','app.launch(); app.launch(); return app'),('func testLinearSummary','func hiddenLinearSummary'),('final class PlayBranchHistoryLifetimeFlowTests','final class OtherHistoryTests')]
  for before,after in mutations:
   with self.subTest(before=before),self.copied_ui() as ui:
    p=ui/layer.NAME;t=p.read_text();self.assertIn(before,t);p.write_text(t.replace(before,after,1))
    with self.assertRaises(ValueError):self.costs(ui=ui)
    with self.assertRaises(ValueError):layer.previous_directory(ui)
 def test_missing_extra_duplicate_unrelated_source_cannot_hide_in_projection(self):
  for mode in ['missing_history','missing_helper','extra','duplicate','unrelated']:
   with self.subTest(mode=mode),self.copied_ui() as ui:
    if mode=='missing_history':(ui/layer.NAME).unlink()
    elif mode=='missing_helper':(ui/'ProjectSubmissionEvidenceUITestSupport.swift').unlink()
    elif mode=='extra':(ui/'Extra.swift').write_text('// unknown source\n')
    elif mode=='duplicate':p=ui/layer.NAME;p.write_bytes(p.read_bytes()*2)
    else:p=ui/'PlayBranchHistoryFlowTests.swift';p.write_bytes(p.read_bytes()+b'\n')
    with self.assertRaises(ValueError):self.costs(ui=ui)
    if mode!='missing_history':
     with self.assertRaises(ValueError):layer.previous_directory(ui)
 def test_critical_app_p2_cleanup_contract_cannot_self_authorize_changes(self):
  paths=[*self.c['critical_sources'],'tools/branch_history_handshake_planning_contract.json']
  for relative in paths:
   with self.subTest(path=relative),tempfile.TemporaryDirectory() as d:
    root=Path(d)
    for path in paths:t=root/path;t.parent.mkdir(parents=True,exist_ok=True);t.write_bytes((ROOT/path).read_bytes())
    t=root/relative;t.write_bytes(t.read_bytes()+b'\n')
    with patch.object(layer,'ROOT',root),self.assertRaises(ValueError):layer.validate_current(UI)
 def test_missing_critical_source_is_not_regenerated(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);p=root/'tools/branch_history_handshake_planning_contract.json';p.parent.mkdir();p.write_bytes((ROOT/'tools/branch_history_handshake_planning_contract.json').read_bytes())
   with patch.object(layer,'ROOT',root),self.assertRaises(FileNotFoundError):layer.validate_current(UI)
   self.assertFalse((root/'App').exists())
 def test_original_receipt_evidence_contracts_remain_byte_identical(self):
  context=layer.frozen_receipt_context();self.addCleanup(context.lifetime.cleanup)
  for path,expected in self.c['retained_receipt_audit_files'].items():self.assertEqual(layer.digest((context.root/path).read_bytes()),expected);self.assertEqual((context.root/path).read_bytes(),(ROOT/path).read_bytes())
  self.assertEqual(json.loads((context.root/'tools/ui_duration_weights.json').read_text()),layer.previous_profile(self.profile))


 def test_protected_central_inverse_restores_all_original_asserted_hashes(self):
  protected=json.loads((ROOT/'docs/branch-history-handshake/protected-baseline.json').read_text())['protected']
  self.assertEqual(set(self.c['protected_central_inverse']),{'tools/ui_duration_weights.json','tools/run_ui_shard.py','tools/run129_repair_planning.py'})
  for path,expected in protected.items():self.assertEqual(layer.digest(layer.retained_protected_source(ROOT/path)),expected)
 def test_protected_inverse_rejects_changed_current_bytes_before_reconstruction(self):
  for path in self.c['protected_central_inverse']:
   with self.subTest(path=path),tempfile.TemporaryDirectory() as d:
    root=Path(d)
    for relative in ['tools/branch_history_handshake_planning_contract.json',path]:
     p=root/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/relative).read_bytes())
    p=root/path;p.write_bytes(p.read_bytes()+b'\n')
    with patch.object(layer,'ROOT',root),self.assertRaises(ValueError):layer.retained_protected_source(p)

if __name__=='__main__':unittest.main()
