"""Current 736-method proof, exact two-method migration, unchanged historic floors."""
from copy import deepcopy
from decimal import Decimal
import hashlib,json,re,shutil,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools import run130_prepared_readiness as layer,run_ui_shard as shard,ci_gates
from tools.run130_receipt_planning import frozen_prepared_context
RETAINED_PREPARED_CONTEXT=frozen_prepared_context()
ROOT=RETAINED_PREPARED_CONTEXT.root;UI=ROOT/'Tests/AppUITests'
class PreparedReadinessBudgetTests(unittest.TestCase):
 def setUp(self):self.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text());self.c=layer.contract()
 def run_profile(self,p,ui=UI):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'p.json';path.write_text(json.dumps(p));return shard.measured_weights(ui,path)
 def test_all_current_files_and_exact_736_methods_are_bound(self):
  self.assertEqual(layer.validate_current(UI),self.c);counts=shard.discover(UI);self.assertEqual((sum(counts.values()),len(counts)),(736,162))
  self.assertEqual(sorted(self.c['aliases'].get(k,k) for k in self.c['current_inventory']),self.c['previous_inventory'])
  self.assertEqual(len(self.c['current_inventory']),len(set(self.c['current_inventory'])))
 def test_original_two_journeys_and_helpers_are_exact_after_approved_inverse(self):
  self.assertEqual(layer.retained_family_source(UI),(layer.FIXTURES/'AppUITests'/layer.OLD).read_text())
  for name in [layer.OLD,layer.NEW]:
   text=(UI/name).read_text();self.assertIn('requiresHittable: false)); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5))',text)
   self.assertIn('current.range(of: text)',text);self.assertIn('Array(remaining.utf8) == Array(original.utf8)',text)
 def test_three_actual_launches_and_new_menu_wait_are_fully_costed(self):
  rows=list(self.c['required_floors'].values());self.assertEqual([r['launch_count'] for r in rows],[1,2]);self.assertEqual([r['new_menu_readiness_seconds'] for r in rows],[5,0])
  self.assertEqual([r['derived_seconds'] for r in rows],[867,674]);self.assertEqual([r['seconds'] for r in rows],[870,680]);self.assertEqual(sum(r['seconds']-r['historical_seconds'] for r in rows),80)
  for key,row in self.c['required_floors'].items():
   text=(ROOT/row['path']).read_text();[(body,name)]=re.findall(layer.PATTERN,text)
   self.assertEqual(len(re.findall(r'\blaunch\(',body)),row['launch_count']);self.assertFalse(row['measured']);self.assertLessEqual(row['seconds'],900)
 def test_all_previous_profile_fields_are_retained(self):
  prior=layer.previous_profile(self.profile);self.assertEqual(layer.canonical(prior),self.c['previous_profile_canonical_sha256'])
  for k,v in prior.items():
   if k!='planning_budget':self.assertEqual(self.profile[k],v)
  for k,v in prior['planning_budget'].items():self.assertEqual(self.profile['planning_budget'][k],v)
 def test_actual_class_costs_never_reduce_any_original_method(self):
  old=layer.frozen_late_context();self.addCleanup(old.lifetime.cleanup);before=shard.measured_weights(old.root/'Tests/AppUITests',old.root/'tools/ui_duration_weights.json');after=self.run_profile(self.profile)
  self.assertEqual(before.pop('ProjectEditPreparedNodesFlowTests'),1470)
  for k,v in before.items():self.assertEqual(after[k],v)
  self.assertEqual(after['ProjectEditPreparedNodesFlowTests'],870);self.assertEqual(after['ProjectEditPreparedStoryOrderFlowTests'],680)
 def test_79_is_first_with_30_second_headroom_and_all_methods_run_once(self):
  doc=json.loads((ROOT/'docs/run130-prepared-readiness-budget.json').read_text());cost={k:Decimal(v) for k,v in doc['classes'].items()};actual=self.run_profile(self.profile)
  self.assertEqual(set(cost),set(actual))
  for k,v in cost.items():self.assertAlmostEqual(actual[k],float(v),places=8)
  self.assertEqual(sum(cost.values()),Decimal('104507.381'))
  for n in range(1,163):self.assertEqual(str(max(sum(cost[k] for k in g)+300 for g in shard.partition(cost,n))),doc['forecasts'][str(n)])
  self.assertEqual(doc['forecasts']['78'],'1778.391');self.assertEqual(doc['forecasts']['79'],'1765.141');self.assertEqual(doc['first_30_second_headroom_shards'],79)
  inv=json.loads((ROOT/'docs/ui-shard-inventory.json').read_text());groups=shard.partition(cost,79);self.assertEqual(inv['shards'],groups)
  self.assertEqual(inv['inventory_sha256'],hashlib.sha256('\n'.join(self.c['current_inventory']).encode()).hexdigest())
  flat=sum(groups,[]);self.assertEqual(len(flat),len(set(flat)));self.assertEqual(len(flat),162);self.assertEqual(sum(inv['shard_test_counts']),736)
 def test_current_workflow_completion_and_runner_use_all_79_shards(self):
  self.assertEqual(shard.DEFAULT_SHARD_COUNT,79);self.assertEqual(ci_gates.SHARD_COUNT,79)
  source=(ROOT/'.github/workflows/native-ios.yml').read_text();self.assertIn('shard: ['+', '.join(map(str,range(79)))+']',source);self.assertIn('--count 79',source)
  self.assertEqual(re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}$',source,re.M),[(str(i),str(i)) for i in range(79)])
  self.assertIn('--deadline-seconds 1800',source);self.assertIn('timeout-minutes: 37',source)
 def test_missing_or_duplicated_method_and_unknown_helper_fail_closed(self):
  for mode in ['remove','duplicate','rename','helper','extra_file']:
   with tempfile.TemporaryDirectory() as d:
    ui=Path(d)/'AppUITests';shutil.copytree(UI,ui);p=ui/layer.NEW;s=p.read_text()
    if mode=='remove':p.unlink()
    elif mode=='duplicate':p.write_text(s+s)
    elif mode=='rename':p.write_text(s.replace('func test','func changed',1))
    elif mode=='helper':p.write_text(s.replace('maximumSwipes: 10','maximumSwipes: 11',1))
    else:(ui/'Unknown.swift').write_text('import XCTest\nfinal class Unknown: XCTestCase {func testNew() {}}')
    with self.subTest(mode=mode),self.assertRaises(ValueError):self.run_profile(self.profile,ui)
 def test_deleting_original_input_or_exact_saved_node_assertions_is_rejected(self):
  tokens=['XCTAssertEqual(saved.chapters[0].nodes[1].description, description)','let description = try insert("Edited "','XCTAssertEqual(choices.count, 1)','XCTAssertEqual(chapterMenuResult, .completed','filter { $0.isHittable && $0.isEnabled }.count == 1']
  for token in tokens:
   with tempfile.TemporaryDirectory() as d:
    ui=Path(d)/'AppUITests';shutil.copytree(UI,ui);p=ui/layer.OLD;s=p.read_text();self.assertIn(token,s);p.write_text(s.replace(token,'REMOVED',1))
    with self.subTest(token=token),self.assertRaises(ValueError):layer.retained_family_source(ui)
 def test_only_failure_path_can_emit_fixed_frame_diagnostic(self):
  text=(UI/layer.OLD).read_text();block=text.split('if chapterMenuResult != .completed {',1)[1].split('        }\n',1)[0]
  self.assertIn('PREPARED_CHAPTER_MENU_READY exists=',block);self.assertIn('String(describing: arrange.frame)',block)
  self.assertNotIn('chapter.name',block);self.assertNotIn('debugDescription',block);self.assertEqual(text.count('print('),1)
 def test_profile_floor_alias_inventory_or_historic_observation_changes_fail(self):
  for mode in ['missing','cost','alias','count','old']:
   p=deepcopy(self.profile)
   if mode=='missing':p['planning_budget'].pop(layer.PLAN)
   elif mode=='old':p['method_seconds'][next(iter(p['method_seconds']))]=1
   else:
    plan=p['planning_budget'][layer.PLAN]
    if mode=='cost':plan['whole_method_seconds'][next(iter(plan['whole_method_seconds']))]=1
    elif mode=='alias':plan['aliases'].clear()
    else:plan['method_count']=735
   with self.subTest(mode=mode),self.assertRaises(ValueError):self.run_profile(p)
 def test_contract_mutation_and_901_cannot_authorize_unknown_budget(self):
  for value in [1,901]:
   c=deepcopy(self.c);c['required_floors'][next(iter(c['required_floors']))]['seconds']=value
   with tempfile.TemporaryDirectory() as d:
    root=Path(d);(root/'tools').mkdir();(root/'tools/run130_prepared_readiness_contract.json').write_text(json.dumps(c))
    with patch.object(layer,'ROOT',root),self.assertRaises(ValueError):layer.contract()
 def test_historical_preimage_and_new_wrapper_do_not_hide_mutation(self):
  with self.assertRaises(ValueError):layer.previous_source(UI/layer.NEW)
  with tempfile.TemporaryDirectory() as d:
   ui=Path(d)/'AppUITests';ui.mkdir();p=ui/layer.OLD;p.write_bytes((UI/layer.OLD).read_bytes()+b'\n// unknown\n')
   with self.assertRaises(ValueError):layer.previous_source(p)
 def test_previous_78_shard_input_and_six_holds_are_preserved(self):
  old=json.loads((layer.FIXTURES/'ui-shard-inventory.json').read_text());self.assertEqual(old['shard_count'],78);self.assertEqual(old['total_classes'],161)
  previous=json.loads((ROOT/'tools/tests/fixtures/run129_repairs/source-index.json').read_text())
  for name in ['ApprovedReleaseRecoveryFlowTests','ApprovedTopicReviewCurrentChineseFlowTests','ApprovedTopicReviewUnknownFlowTests','ApprovedTopicSelectedCoverChineseFlowTests','ProjectStoryAudioRecoveryFlowTests','OwnedTopicCoverRecoveryFlowTests']:
   rel='Tests/AppUITests/'+name+'.swift';self.assertEqual(layer.digest((ROOT/rel).read_bytes()),previous['current_ui_sources'][rel]['sha256'])
 def test_exact_64_shard_source_compatibility_requires_both_profile_and_file(self):
  from tools.tests.combined_native_budget_history import materialize_independent_ui,before_combined
  with tempfile.TemporaryDirectory() as d:
   ui=materialize_independent_ui(d,'media');profile=before_combined(self.profile,'media');p=Path(d)/'profile.json';p.write_text(json.dumps(profile))
   self.assertIsNone(layer.weights(ui,p))
   bad=deepcopy(profile);bad['unobserved_method_seconds']+=1;p.write_text(json.dumps(bad))
   with self.assertRaises(ValueError):layer.weights(ui,p)
   p.write_text(json.dumps(profile));source=ui/layer.OLD;source.write_bytes(source.read_bytes()+b'\n// unknown old source\n')
   with self.assertRaises(ValueError):layer.weights(ui,p)
