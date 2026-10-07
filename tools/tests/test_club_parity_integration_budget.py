"""Current complete club integration contract; no Swift or Apple execution claims."""
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
from pathlib import Path
import hashlib,json,re,shutil,tempfile,unittest
from tools.tests.story_template_budget_history import before_story_template, materialize_pre_story_ui, historical_pre_story_source, historical_pre_story_module
from unittest.mock import patch
from tools.tests.club_parity_budget_history import before_club_parity
ROOT=Path(__file__).resolve().parents[2]
shard=historical_pre_story_module(ROOT/'tools/run_ui_shard.py','frozen_club_r2_runner')
ci_gates=historical_pre_story_module(ROOT/'tools/ci_gates.py','frozen_club_r2_gates')
FIXTURE=ROOT/'tools/tests/fixtures/club_parity_integration'
PATTERN=r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'
OLD='ClubOperationsFlowTests.testAdminProfileHasNoOwnerSettingsOrRoleActions'
NEW={'ClubProfileScopeFlowTests.testAdminDisplayOnlyReviewCancelsThenSavesOnce':720,
     'ClubProfileScopeFlowTests.testOwnerProfileReviewRetainsOperatingFields':630}
def sha(data):return hashlib.sha256(data).hexdigest()
def declarations(s):return {name:body for body,name in re.findall(PATTERN,s)}
def nontest(s):
 return re.sub(r'(?m)^[ \t]*\n','',re.sub(PATTERN,'',s).replace('final class ClubProfileScopeFlowTests: XCTestCase','final class ClubOperationsFlowTests: XCTestCase'))
class ClubParityIntegrationBudgetTests(unittest.TestCase):
 def setUp(self):
  directory=tempfile.TemporaryDirectory();self.addCleanup(directory.cleanup);self.ui=materialize_pre_story_ui(Path(directory.name)/'ui');self.profile_path=historical_pre_story_source(ROOT/'tools/ui_duration_weights.json')
  self.profile=before_story_template(json.loads((self.profile_path).read_text()));self.plan=self.profile['planning_budget']['reviewed_club_parity_replan'];self.prior=before_club_parity(self.profile)
  self.methods={};self.costs=defaultdict(Decimal)
  for path in sorted((self.ui).glob('*.swift')):
   s=path.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',s)
   if not names:continue
   classes=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',s);self.assertEqual(len(classes),1)
   for name in names:
    key=classes[0]+'.'+name;self.assertNotIn(key,self.methods);self.methods[key]=path;self.costs[classes[0]]+=self.cost(key)
 def cost(self,key):
  p=self.profile;v=p['method_seconds'].get(key,p['estimated_method_seconds'].get(key,p['unobserved_method_seconds']));return Decimal(str(max(v,p.get('method_planning_floors',{}).get(key,{}).get('seconds',0))))
 def test_exact_712_methods_147_whole_classes_and_only_two_new_ids(self):
  old=set(self.prior['planning_budget']['reviewed_creator_pending_replan']['current_inventory']);self.assertEqual((len(old),len(self.methods),len(self.costs)),(710,712,147))
  self.assertEqual(set(self.methods)-old,set(NEW));self.assertTrue(old<=set(self.methods));self.assertEqual(set(self.plan['current_inventory']),set(self.methods));self.assertEqual(sha('\n'.join(sorted(self.methods)).encode()),self.plan['current_inventory_sha256'])
  counts=shard.discover(self.ui);self.assertEqual((sum(counts.values()),len(counts)),(712,147));self.assertEqual((counts['ClubOperationsFlowTests'],counts['ClubProfileScopeFlowTests']),(11,2))
  groups=shard.partition(self.costs,67);flat=sum(groups,[]);self.assertEqual((len(flat),len(set(flat))),(147,147));self.assertEqual(set(flat),set(self.costs));self.assertEqual(sum(counts[k] for k in flat),712)
 def test_observed_27351_is_retained_but_actual_runner_uses_300_floor(self):
  self.assertEqual(self.profile['method_seconds'][OLD],27.351);self.assertEqual(self.profile['method_planning_floors'][OLD]['seconds'],300);self.assertEqual(self.cost(OLD),300)
  costs=shard.measured_weights(self.ui,self.profile_path);self.assertAlmostEqual(costs['ClubOperationsFlowTests'],1465.141,places=8);self.assertEqual(costs['ClubProfileScopeFlowTests'],1350)
  for key,value in self.costs.items():self.assertAlmostEqual(costs[key],float(value),places=8)
 def test_all_old_observations_and_unaffected_costs_remain_exact(self):
  self.assertEqual(self.profile['method_seconds'],self.prior['method_seconds']);self.assertEqual(len(self.profile['run117_method_observations']),647)
  for key,value in self.prior.items():
   if 'observation' in key:self.assertEqual(self.profile[key],value)
  for key in self.prior['planning_budget']['reviewed_creator_pending_replan']['current_inventory']:
   v=Decimal(str(self.prior['method_seconds'].get(key,self.prior['estimated_method_seconds'].get(key,self.prior['unobserved_method_seconds']))));self.assertGreaterEqual(self.cost(key),v)
   if key!=OLD:self.assertEqual(self.cost(key),v)
  for key,value in self.prior['planning_budget'].items():self.assertEqual(self.profile['planning_budget'][key],value)
 def test_source_loop_formula_and_complete_method_assumptions_are_explicit(self):
  expected={**NEW,OLD:300};self.assertEqual(self.plan['whole_method_estimates'],expected)
  for row in self.plan['complete_method_derivations']:
   self.assertFalse(row['measured']);self.assertEqual(row['timing_status'],'UNMEASURED_ENGINEERING_PLANNING_ASSUMPTION');self.assertEqual((row['launches'],row['maximum_swipe_iterations_per_reveal'],row['swipe_query_iteration_seconds_assumption'],row['other_whole_method_overhead_seconds_assumption']),(1,28,3,90))
   self.assertEqual(row['formula_seconds'],row['explicit_wait_caps_seconds']+row['reveal_calls']*28*3+90);self.assertEqual(row['seconds'],row['formula_seconds']+row['round_up_seconds']);self.assertGreaterEqual(row['round_up_seconds'],0);self.assertLessEqual(row['seconds'],900)
   path=self.methods[row['method']];self.assertEqual(sha(path.read_bytes()),row['test_file_sha256']);self.assertEqual(sha(declarations(path.read_text())[row['method'].split('.')[1]].encode()),row['declaration_sha256']);self.assertEqual(sha(nontest(path.read_text()).encode()),row['all_non_test_source_sha256'])
  self.assertEqual([(r['explicit_wait_caps_seconds'],r['reveal_calls']) for r in self.plan['complete_method_derivations']],[(30,7),(25,6),(15,2)])
 def test_every_current_estimate_keeps_source_binding_and_no_fallback_for_new_tests(self):
  rows=self.profile['estimate_provenance']['methods'];self.assertEqual(len(rows),len({r['method'] for r in rows}));self.assertEqual({r['method'] for r in rows},set(self.profile['estimated_method_seconds']))
  for r in rows:self.assertFalse(r['measured']);self.assertEqual(sha(self.methods[r['method']].read_bytes()),r['test_file_sha256']);self.assertEqual(self.cost(r['method']),Decimal(str(r['seconds'])))
  for key,value in NEW.items():self.assertEqual(self.cost(key),value);self.assertNotIn(key,self.profile['method_seconds'])
 def test_new_methods_all_helpers_setup_teardown_preserved_byte_exact(self):
  authored=(FIXTURE/'authored-ClubOperationsFlowTests.swift.txt').read_text();left=(self.ui/'ClubOperationsFlowTests.swift').read_text();right=(self.ui/'ClubProfileScopeFlowTests.swift').read_text();record=json.loads((FIXTURE/'whole-method-migration.json').read_text())
  a,l,r=map(declarations,(authored,left,right));self.assertEqual((len(a),len(l),len(r)),(13,11,2));self.assertEqual(set(l)|set(r),set(a));self.assertFalse(set(l)&set(r))
  for name,body in {**l,**r}.items():self.assertEqual(body,a[name])
  self.assertEqual(nontest(authored),nontest(left));self.assertEqual(nontest(authored),nontest(right));self.assertEqual(sha(nontest(authored).encode()),record['all_non_test_source_sha256'])
  for source,key in [(authored,'original_candidate_ui_sha256'),(left,'remaining_ui_sha256'),(right,'new_ui_sha256')]:self.assertEqual(sha(source.encode()),record[key])
  self.assertIn('final class ClubProfileScopeFlowTests: XCTestCase',right);self.assertNotIn(': ClubOperationsFlowTests',right)
 def test_original_eight_non_ui_upstream_postimages_are_exact(self):
  rows=json.loads((FIXTURE/'upstream-source-paths.json').read_text());self.assertEqual(len(rows),9)
  for row in rows:
   if row['path']!='Tests/AppUITests/ClubOperationsFlowTests.swift':self.assertEqual(sha((ROOT/row['path']).read_bytes()),row['post_sha256'])
 def test_66_is_minimum_and_67_preserves_30_seconds_without_class_splitting(self):
  self.assertEqual((shard.DEFAULT_SHARD_COUNT,ci_gates.SHARD_COUNT,self.plan['shard_count']),(67,67,67));self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds'],self.plan['complete_method_limit_seconds']),(1800,300,900));self.assertEqual(sum(self.costs.values()),Decimal('92687.381'));self.assertEqual(max(self.costs.values()),1470)
  for count in range(1,148):
   groups=shard.partition(self.costs,count);peak=max(sum(self.costs[k] for k in g)+300 for g in groups);self.assertEqual(str(peak),self.plan['forecasts'][str(count)])
   if count<66:self.assertGreater(peak,1800)
  self.assertEqual({n:self.plan['forecasts'][n] for n in ['65','66','67']},{'65':'1826.149','66':'1797.226','67':'1770'});self.assertEqual(self.plan['remaining_margin_seconds'],'30')
 def test_actual_workflow_and_all_completion_outputs_require_67_shards(self):
  w=historical_pre_story_source(ROOT/'.github/workflows/native-ios.yml').read_text();outputs=re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',w,re.M);self.assertEqual(outputs,[(str(i),str(i)) for i in range(67)]);self.assertIn('--count 67 ',w);self.assertIn('--deadline-seconds 1800',w)
  indices=[int(x.strip()) for x in re.search(r'shard:\s*\[([0-9,\s]+)\]',w)[1].split(',')];self.assertEqual(indices,list(range(67)))
 def test_new_method_budget_floor_and_inventory_negative_controls_fail_closed(self):
  for mutation in ['missing_floor','lower_floor','floor_nan','floor_true','missing_new_estimate','fallback_new_estimate','bad_file','bad_declaration','bad_helpers','removed_plan','missing_inventory']:
   p=deepcopy(self.profile);row=p['method_planning_floors'][OLD]
   if mutation=='missing_floor':p['method_planning_floors'].pop(OLD)
   elif mutation=='lower_floor':row['seconds']=27.351
   elif mutation=='floor_nan':row['seconds']=float('nan')
   elif mutation=='floor_true':row['seconds']=True
   elif mutation=='missing_new_estimate':p['estimated_method_seconds'].pop(next(iter(NEW)))
   elif mutation=='fallback_new_estimate':p['estimated_method_seconds'][next(iter(NEW))]=60
   elif mutation=='bad_file':row['test_file_sha256']='0'*64
   elif mutation=='bad_declaration':row['declaration_sha256']='0'*64
   elif mutation=='bad_helpers':row['all_non_test_source_sha256']='0'*64
   elif mutation=='removed_plan':p['planning_budget'].pop('reviewed_club_parity_replan')
   else:p['planning_budget']['reviewed_club_parity_replan']['current_inventory'].pop()
   with tempfile.TemporaryDirectory() as t:
    f=Path(t)/'profile.json';f.write_text(json.dumps(p))
    with self.subTest(mutation=mutation),self.assertRaises(ValueError):shard.measured_weights(self.ui,f)
 def test_ui_declaration_helper_and_source_changes_require_new_budget_binding(self):
  for filename,old,new in [('ClubOperationsFlowTests.swift','for _ in 0..<14','for _ in 0..<15'),('ClubOperationsFlowTests.swift','launch("admin"); tap("club.ops.openManage")','launch("admin"); tap("club.ops.openManage"); tap("club.ops.openManage")'),('ClubProfileScopeFlowTests.swift','name.typeText(" edited")','name.typeText(" longer edited")')]:
   with tempfile.TemporaryDirectory() as t:
    dest=Path(t)/'ui';shutil.copytree(self.ui,dest);f=dest/filename;s=f.read_text();self.assertIn(old,s);f.write_text(s.replace(old,new,1))
    with self.subTest(filename=filename,mutation=old),self.assertRaises(ValueError):shard.measured_weights(dest,self.profile_path)
 def test_delivered_plan_recomputes_from_actual_current_sources(self):
  data=json.loads((ROOT/'docs/club-parity-integration-budget.json').read_text());self.assertEqual(data['plan'],self.plan);self.assertEqual(data['class_costs'],{k:str(v) for k,v in sorted(self.costs.items())});groups=shard.partition(self.costs,67);self.assertEqual(len(data['shards']),67);self.assertEqual(sum(r['methods'] for r in data['shards']),712)
  for row,g in zip(data['shards'],groups):self.assertEqual(row['classes'],g);self.assertEqual(Decimal(row['projected_seconds_with_startup']),sum(self.costs[k] for k in g)+300)
 def test_r2_full_old_profile_is_lifted_by_three_source_required_floors(self):
  with tempfile.TemporaryDirectory() as directory:
   f=Path(directory)/'old.json';f.write_text(json.dumps(self.prior));before=f.read_bytes()
   actual=shard.measured_weights(self.ui,f)
   self.assertAlmostEqual(actual['ClubOperationsFlowTests'],1465.141,places=8);self.assertEqual(actual['ClubProfileScopeFlowTests'],1350);self.assertAlmostEqual(sum(actual.values()),92687.381,places=8);self.assertEqual(f.read_bytes(),before)
   self.assertEqual(shard.partition(actual,67),shard.partition(self.costs,67))
 def test_r2_same_source_cost_and_self_reported_allowance_deletions_fail_closed(self):
  for key in [*NEW,OLD]:
   p=deepcopy(self.profile);p['planning_budget']['reviewed_club_parity_replan']['whole_method_estimates'].pop(key)
   if key==OLD:p['method_planning_floors'].pop(key)
   else:p['estimated_method_seconds'].pop(key)
   with tempfile.TemporaryDirectory() as directory:
    f=Path(directory)/'missing-cost-and-plan-item.json';f.write_text(json.dumps(p))
    with self.subTest(key=key),self.assertRaises(ValueError):shard.measured_weights(self.ui,f)
 def test_r2_low_high_future_observations_take_max_and_remain_unchanged(self):
  keys=list(NEW)+[OLD]
  for values,expected_new,expected_old in [([17,19,11],1350,1465.141),([780,690,330],1470,1495.141)]:
   p=deepcopy(self.profile)
   for key,value in zip(keys,values):p['method_seconds'][key]=value
   with tempfile.TemporaryDirectory() as directory:
    f=Path(directory)/'future.json';f.write_text(json.dumps(p));before=f.read_bytes();actual=shard.measured_weights(self.ui,f)
    self.assertEqual(actual['ClubProfileScopeFlowTests'],expected_new);self.assertAlmostEqual(actual['ClubOperationsFlowTests'],expected_old,places=8);self.assertEqual(f.read_bytes(),before)
    saved=json.loads(f.read_text());self.assertEqual([saved['method_seconds'][key] for key in keys],values);self.assertEqual(saved['run117_method_observations'],self.profile['run117_method_observations'])
 def test_r2_missing_or_tampered_trusted_contract_fails_for_current_and_historical_source(self):
  from tools.tests.club_parity_budget_history import materialize_pre_club_ui
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);historical=materialize_pre_club_ui(root/'history');p=root/'old.json';p.write_text(json.dumps(self.prior));contract=root/'trusted.json'
   for kind in ['missing','corrupt_floor','corrupt_binding']:
    if kind!='missing':
     body=json.loads(shard.CLUB_PARITY_CONTRACT_PATH.read_text());row=body['required_floors'][OLD]
     if kind=='corrupt_floor':row['seconds']=1
     else:row['declaration_sha256']='0'*64
     contract.write_text(json.dumps(body))
    with patch.object(shard,'CLUB_PARITY_CONTRACT_PATH',contract):
     for source in [self.ui,historical]:
      with self.subTest(kind=kind,source=str(source)),self.assertRaises(ValueError):shard.measured_weights(source,p)
 def test_r2_no_new_class_is_insufficient_and_historical_bytes_must_be_exact(self):
  from tools.tests.club_parity_budget_history import historical_pre_club_source
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);ui=root/'ui';shutil.copytree(self.ui,ui);(ui/'ClubProfileScopeFlowTests.swift').unlink();p=root/'old.json';p.write_text(json.dumps(self.prior))
   with self.assertRaises(ValueError):shard.measured_weights(ui,p)
   old=ui/'ClubOperationsFlowTests.swift';old.write_bytes(historical_pre_club_source(ROOT/'Tests/AppUITests/ClubOperationsFlowTests.swift').read_bytes());actual=shard.measured_weights(ui,p)
   self.assertEqual((sum(shard.discover(ui).values()),len(actual)),(710,146));self.assertAlmostEqual(actual['ClubOperationsFlowTests'],1192.492,places=8);self.assertAlmostEqual(sum(actual.values()),91064.732,places=8)
   old.write_text(old.read_text().replace('for _ in 0..<14','for _ in 0..<13',1))
   with self.assertRaises(ValueError):shard.measured_weights(ui,p)
 def test_r2_custom_profile_cannot_forge_source_or_helper_bindings(self):
  for file,old,new in [('ClubProfileScopeFlowTests.swift','name.typeText(" edited")','name.typeText(" changed body")'),('ClubOperationsFlowTests.swift','for _ in 0..<14','for _ in 0..<15')]:
   with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);ui=root/'ui';shutil.copytree(self.ui,ui);path=ui/file;text=path.read_text();self.assertIn(old,text);path.write_text(text.replace(old,new,1));p=deepcopy(self.profile)
    for row in p['estimate_provenance']['methods']+list(p['method_planning_floors'].values()):
     if row['method'].split('.')[0]+'.swift'==file:
      row['test_file_sha256']=sha(path.read_bytes())
      if 'all_non_test_source_sha256' in row:row['all_non_test_source_sha256']=sha(nontest(path.read_text()).encode())
      if 'declaration_sha256' in row:row['declaration_sha256']=sha(declarations(path.read_text())[row['method'].split('.')[1]].encode())
    f=root/'forged.json';f.write_text(json.dumps(p))
    with self.subTest(file=file),self.assertRaises(ValueError):shard.measured_weights(ui,f)
 def test_r2_unrelated_custom_profile_support_is_preserved(self):
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);(root/'Example.swift').write_text('final class Example: XCTestCase { func testCustom() {} }');profile=root/'custom.json';profile.write_text(json.dumps({'version':1,'unobserved_method_seconds':60,'method_seconds':{'Example.testCustom':17},'estimated_method_seconds':{'Example.testCustom':700}}))
   self.assertEqual(shard.measured_weights(root,profile),{'Example':17})
if __name__=='__main__':unittest.main()
