"""Whole-union coverage and mechanically reversible independent planning history."""
from copy import deepcopy
from collections import defaultdict
from decimal import Decimal
from pathlib import Path
import hashlib,json,re,tempfile,unittest
from tools import run_ui_shard as shard,ci_gates
from tools.tests.combined_native_budget_history import before_combined,canonical,materialize_independent_ui,source_index,CURRENT_PROFILE_SHA256
from tools.tests.story_media_budget_history import before_story_media
from tools.tests.reviewed_map_budget_history import before_reviewed_map
ROOT=Path(__file__).resolve().parents[2]
class CombinedNativeBudgetTests(unittest.TestCase):
 def setUp(self):
  self.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text());self.plan=self.profile['planning_budget']['reviewed_combined_native_replan'];self.methods={};self.costs=defaultdict(Decimal)
  for p in sorted((ROOT/'Tests/AppUITests').glob('*.swift')):
   s=p.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',s)
   if not names:continue
   classes=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',s);self.assertEqual(len(classes),1)
   for name in names:
    k=classes[0]+'.'+name;self.assertNotIn(k,self.methods);self.methods[k]=p;self.costs[classes[0]]+=self.cost(self.profile,k)
 def cost(self,p,k):return Decimal(str(p['method_seconds'].get(k,p['estimated_method_seconds'].get(k,p['unobserved_method_seconds']))))
 def test_actual_inventory_contains_each_of_707_complete_methods_once(self):
  self.assertEqual((len(self.methods),len(self.costs)),(707,143));self.assertEqual(sum(shard.discover(ROOT/'Tests/AppUITests').values()),707)
  self.assertEqual(set(self.methods),set(self.plan['current_inventory']));self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(),self.plan['current_inventory_sha256'])
  media=before_combined(self.profile,'media');mapping=before_combined(self.profile,'map');old=before_story_media(media)
  ai=set(media['planning_budget']['reviewed_story_media_replan']['current_inventory']);bi=set(mapping['planning_budget']['reviewed_map_alternative_list_replan']['current_inventory']);oi=set(old['planning_budget']['reviewed_native_features_replan']['current_inventory'])
  self.assertEqual({self.plan['method_migrations'].get(k,k) for k in ai|bi},set(self.methods));self.assertEqual(ai&bi,oi);self.assertEqual((len(oi),len(ai-oi),len(bi-oi)),(661,43,3));self.assertEqual(len(self.plan['method_migrations']),1)
 def test_all_effective_costs_are_the_maximum_complete_allowance(self):
  inputs=[(before_combined(self.profile,'media'),'reviewed_story_media_replan'),(before_combined(self.profile,'map'),'reviewed_map_alternative_list_replan')]
  reverse={new:old for old,new in self.plan['method_migrations'].items()}
  for k in self.methods:
   prior_key=reverse.get(k,k)
   values=[self.cost(p,prior_key) for p,key in inputs if prior_key in p['planning_budget'][key]['current_inventory']]
   self.assertEqual(self.cost(self.profile,k),max(values));self.assertGreater(self.cost(self.profile,k),0);self.assertLessEqual(self.cost(self.profile,k),900)
  rows=self.profile['estimate_provenance']['methods'];self.assertEqual(len(rows),len({r['method'] for r in rows}));self.assertEqual({r['method'] for r in rows},set(self.profile['estimated_method_seconds']))
  for row in rows:
   self.assertFalse(row['measured']);self.assertEqual(self.cost(self.profile,row['method']),Decimal(str(row['seconds'])));self.assertEqual(hashlib.sha256(self.methods[row['method']].read_bytes()).hexdigest(),row['test_file_sha256'])
  self.assertEqual(self.costs['SearchMapAlternativeListFlowTests'],810)
  names=[k for k in self.methods if re.match(r'ProjectStory(Image|Audio)(First|Middle|End)GapFlowTests\.',k)];self.assertEqual(len(names),6)
  for k in names:self.assertEqual(self.cost(self.profile,k),900)
 def test_independent_profiles_and_shared_base_restore_exactly(self):
  media=before_combined(self.profile,'media');mapping=before_combined(self.profile,'map');basea=before_story_media(media);baseb=before_reviewed_map(mapping)
  self.assertEqual(canonical(self.profile),CURRENT_PROFILE_SHA256)
  self.assertEqual(canonical(media),self.plan['source_inputs']['media_profile_canonical_sha256']);self.assertEqual(canonical(mapping),self.plan['source_inputs']['map_profile_canonical_sha256']);self.assertEqual(basea,baseb);self.assertEqual(canonical(basea),self.plan['source_inputs']['base_profile_canonical_sha256'])
  for key in basea:
   if 'observation' in key:self.assertEqual(self.profile[key],basea[key]);self.assertEqual(media[key],mapping[key])
  self.assertEqual(len(self.profile['run117_method_observations']),647)
 def test_original_independent_source_snapshots_remain_bound(self):
  for branch,count,classes in [('media',704,141),('map',664,108)]:
   with tempfile.TemporaryDirectory() as tmp:
    sources=materialize_independent_ui(tmp,branch);found=shard.discover(sources);self.assertEqual((sum(found.values()),len(found)),(count,classes))
   for row in source_index()[branch]['ui_sources']:
    if 'historical_file' not in row:self.assertEqual(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest(),row['sha256'])
 def test_64_fits_and_65_is_chosen_for_30_seconds_additional_margin(self):
  self.assertEqual((shard.DEFAULT_SHARD_COUNT,ci_gates.SHARD_COUNT,self.plan['shard_count']),(65,65,65));self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds'],self.plan['complete_method_limit_seconds']),(1800,300,900));self.assertEqual(sum(self.costs.values()),Decimal('89264.732'));self.assertEqual(max(self.costs.values()),1470)
  counts=shard.discover(ROOT/'Tests/AppUITests')
  actual=shard.measured_weights(ROOT/'Tests/AppUITests',ROOT/'tools/ui_duration_weights.json');self.assertEqual(set(actual),set(self.costs))
  for k in actual:self.assertAlmostEqual(actual[k],float(self.costs[k]),places=9)
  for n in range(38,66):
   groups=shard.partition(self.costs,n);flat=sum(groups,[]);self.assertEqual(len(flat),len(set(flat)));self.assertEqual(set(flat),set(self.costs));self.assertEqual(sum(counts[k] for k in flat),707)
   peak=max(sum(self.costs[k] for k in group)+300 for group in groups);self.assertEqual(peak,Decimal(str(self.plan['forecasts'][str(n)])))
   if n<64:self.assertGreater(peak,1800)
   elif n==64:self.assertEqual(peak,Decimal('1797.226'));self.assertLess(peak,1800)
   else:self.assertEqual(peak,1770);self.assertEqual(groups,shard.partition(actual,n));self.assertEqual(1800-peak,30)
 def test_live_workflow_runner_and_completion_gate_use_whole_union(self):
  workflow=(ROOT/'.github/workflows/native-ios.yml').read_text();outputs=re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',workflow,re.M)
  self.assertEqual(outputs,[(str(i),str(i)) for i in range(65)]);self.assertIn('--count 65 ',workflow);self.assertIn('--deadline-seconds 1800',workflow)
 def test_each_inverse_rejects_corrupted_current_data_and_historical_identity(self):
  for mutation in ['inventory','new_cost','old_cost','source','observation','historical_run','migration','media_plan','map_plan']:
   p=deepcopy(self.profile)
   if mutation=='inventory':p['planning_budget']['reviewed_combined_native_replan']['current_inventory'].pop()
   elif mutation=='new_cost':p['estimated_method_seconds'][self.plan['new_media_methods'][0]]=1
   elif mutation=='old_cost':p['method_seconds'][next(iter(p['method_seconds']))]=1
   elif mutation=='source':p['estimate_provenance']['methods'][0]['test_file_sha256']='0'*64
   elif mutation=='observation':p['run117_method_observations'].pop()
   elif mutation=='historical_run':p['run117_method_observations'][0]['run_id']=0
   elif mutation=='migration':p['planning_budget']['reviewed_combined_native_replan']['reviewed_map_method_migrations'].popitem()
   elif mutation=='media_plan':p['planning_budget']['reviewed_story_media_replan']['current_inventory'].pop()
   else:p['planning_budget']['reviewed_map_alternative_list_replan']['current_inventory'].pop()
   for branch in ['media','map']:
    with self.assertRaises(AssertionError):before_combined(p,branch)

 def test_migrated_720_second_method_preserves_exact_body_and_every_helper(self):
  fixture=ROOT/'tools/tests/fixtures/combined_native';row=json.loads((fixture/'whole-method-migration.json').read_text())
  original=(fixture/'media/ProjectEditPendingFlowTests.swift').read_text();remaining=(ROOT/row['old_source']).read_text();moved=(ROOT/row['new_source']).read_text()
  for source,key in [(original,'original_file_sha256'),(remaining,'remaining_file_sha256'),(moved,'new_file_sha256')]:self.assertEqual(hashlib.sha256(source.encode()).hexdigest(),row[key])
  def declarations(source):return dict((name,body) for body,name in re.findall(r'(?m)^    (func (test\w+)\b[\s\S]*?^    })',source))
  old=declarations(original);left=declarations(remaining);right=declarations(moved);name=row['old_id'].split('.')[1]
  self.assertEqual(set(left)|set(right),set(old));self.assertFalse(set(left)&set(right));self.assertEqual(right,{name:old[name]})
  for key,body in left.items():self.assertEqual(body,old[key])
  self.assertEqual(hashlib.sha256(right[name].encode()).hexdigest(),row['whole_method_declaration_sha256'])
  def nontest(source):
   for body in declarations(source).values():source=source.replace(body,'',1)
   return re.sub(r'(?m)^[ \t]+$','',source.replace('final class ProjectEditPendingRestoreFlowTests: XCTestCase','final class ProjectEditPendingFlowTests: XCTestCase'))
  self.assertEqual(nontest(original),nontest(remaining));self.assertEqual(nontest(original),nontest(moved));self.assertEqual(hashlib.sha256(nontest(original).encode()).hexdigest(),row['all_non_test_source_sha256'])
  self.assertIn('final class ProjectEditPendingRestoreFlowTests: XCTestCase',moved);self.assertNotIn(row['old_id'],self.methods);self.assertEqual(self.cost(self.profile,row['new_id']),720);self.assertEqual(self.costs['ProjectEditPendingFlowTests'],780)
