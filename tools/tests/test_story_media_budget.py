from tools.tests.combined_native_budget_history import before_combined, materialize_independent_ui, independent_workflow
import tempfile
"""Current native media inventory, exact history, and complete-method shard limits."""
from copy import deepcopy
from decimal import Decimal
from pathlib import Path
import hashlib,json,re,unittest
from tools import run_ui_shard as shard,ci_gates
from tools.tests.story_media_budget_history import before_story_media,source_index,canonical,BASELINE_PROFILE_SHA256,CURRENT_PROFILE_SHA256
ROOT=Path(__file__).resolve().parents[2]
class StoryMediaBudgetTests(unittest.TestCase):
 def setUp(self):
  self.history_directory=tempfile.TemporaryDirectory();self.addCleanup(self.history_directory.cleanup)
  self.ui_root=materialize_independent_ui(self.history_directory.name,'media')
  self.profile=before_combined(json.loads((ROOT/'tools/ui_duration_weights.json').read_text()),'media')
  self.profile_path=Path(self.history_directory.name)/'profile.json';self.profile_path.write_text(json.dumps(self.profile))
  self.plan=self.profile['planning_budget']['reviewed_story_media_replan'];self.methods={};self.costs={}
  for p in sorted(self.ui_root.glob('*.swift')):
   s=p.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',s)
   if not names:continue
   classes=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',s);self.assertEqual(len(classes),1);case=classes[0];self.assertNotIn(case,self.costs);self.costs[case]=Decimal(0)
   for name in names:
    k=case+'.'+name;self.assertNotIn(k,self.methods);self.methods[k]=p;self.costs[case]+=self.cost(self.profile,k)
 def cost(self,p,k):return Decimal(str(p['method_seconds'].get(k,p['estimated_method_seconds'].get(k,p['unobserved_method_seconds']))))
 def test_all_661_prior_ids_and_43_new_methods_are_covered_exactly_once(self):
  old=source_index()['baseline_inventory'];self.assertEqual(len(old),661)
  self.assertEqual((len(self.methods),len(self.costs)),(704,141));self.assertEqual(set(self.methods),set(self.plan['current_inventory']))
  self.assertEqual(set(old)|set(self.plan['new_methods']),set(self.methods));self.assertEqual(len(self.plan['new_methods']),43)
  self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(),self.plan['current_inventory_sha256'])
  self.assertEqual(sum(shard.discover(self.ui_root).values()),704)
 def test_all_method_maxima_and_61_complete_replacements_are_source_bound(self):
  prior=before_story_media(self.profile)
  for k in source_index()['baseline_inventory']:self.assertGreaterEqual(self.cost(self.profile,k),self.cost(prior,k))
  rows=self.plan['full_method_replacements'];self.assertEqual(len(rows),61);self.assertEqual(len({r['method'] for r in rows}),61)
  for r in rows:
   k=r['method'];self.assertFalse(r['measured']);self.assertEqual(self.cost(self.profile,k),max(Decimal(str(r['prior_effective_seconds'])),Decimal(str(r['author_complete_seconds']))))
   self.assertNotIn(k,self.profile['method_seconds']);self.assertEqual(hashlib.sha256(self.methods[k].read_bytes()).hexdigest(),r['current_source']['file_sha256'])
  estimates=self.profile['estimate_provenance']['methods'];self.assertEqual({r['method'] for r in estimates},set(self.profile['estimated_method_seconds']))
  for r in estimates:
   self.assertFalse(r['measured']);self.assertEqual(self.cost(self.profile,r['method']),Decimal(str(r['seconds'])));self.assertEqual(hashlib.sha256(self.methods[r['method']].read_bytes()).hexdigest(),r['test_file_sha256'])
  self.assertTrue(self.plan['fragment_summaries_ignored_and_recomputed']);self.assertEqual(self.plan['new_method_seconds'],32760);self.assertEqual(self.plan['complete_fragment_seconds'],34920)
 def test_six_gap_methods_retain_complete_900_second_allowance_and_300_reserve(self):
  names=[k for k in self.methods if re.match(r'ProjectStory(Image|Audio)(First|Middle|End)GapFlowTests\.',k)];self.assertEqual(len(names),6)
  for k in names:self.assertEqual(self.cost(self.profile,k),900);self.assertEqual(self.costs[k.split('.')[0]]+300,1200)
 def test_actual_64_shard_partition_is_first_fit_without_relaxing_limits(self):
  self.assertEqual((64,64,self.plan['shard_count']),(64,64,64))
  self.assertEqual((self.plan['complete_method_limit_seconds'],self.plan['deadline_seconds'],self.plan['startup_reserve_seconds']),(900,1800,300))
  self.assertEqual(max(self.costs.values()),1500);self.assertEqual(sum(self.costs.values()),Decimal('88454.732'))
  self.assertTrue(all(self.cost(self.profile,k)<=900 for k in self.methods))
  actual=shard.measured_weights(self.ui_root,self.profile_path);self.assertEqual(set(actual),set(self.costs))
  for k in actual:self.assertAlmostEqual(actual[k],float(self.costs[k]),places=9)
  for count in range(38,65):
   groups=shard.partition(self.costs,count);flat=sum(groups,[]);self.assertEqual(len(flat),len(set(flat)));self.assertEqual(set(flat),set(self.costs))
   peak=max(sum(self.costs[k] for k in g)+300 for g in groups);self.assertEqual(peak,Decimal(str(self.plan['forecasts'][str(count)])))
   if count<64:self.assertGreater(peak,1800)
   else:self.assertLessEqual(peak,1800);self.assertEqual(groups,shard.partition(actual,count))
  workflow=independent_workflow('media').read_text();outputs=re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',workflow,re.M)
  self.assertEqual(outputs,[(str(i),str(i)) for i in range(64)]);self.assertIn('--count 64 ',workflow);self.assertIn('--deadline-seconds 1800',workflow)
 def test_exact_prior_profile_and_observation_histories_are_unchanged(self):
  prior=before_story_media(self.profile);self.assertEqual(canonical(prior),BASELINE_PROFILE_SHA256);self.assertEqual(canonical(self.profile),CURRENT_PROFILE_SHA256)
  for k in prior:
   if k.endswith('_method_observations') or k=='superseded_method_observations':self.assertEqual(self.profile[k],prior[k])
  self.assertEqual(len(self.profile['run117_method_observations']),647)
  for corruption in ['cost','inventory','old_cost','source']:
   p=deepcopy(self.profile)
   if corruption=='cost':p['estimated_method_seconds'][self.plan['new_methods'][0]]=1
   elif corruption=='inventory':p['planning_budget']['reviewed_story_media_replan']['current_inventory'].pop()
   elif corruption=='old_cost':p['story_media_previous_method_seconds'].popitem()
   else:p['estimate_provenance']['methods'][0]['test_file_sha256']='0'*64
   with self.assertRaises(AssertionError):before_story_media(p)
