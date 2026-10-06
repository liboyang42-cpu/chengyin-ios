"""Exhaustive current planning plus lossless published history; no runtime shortcuts."""
from copy import deepcopy
from decimal import Decimal
import hashlib,json,re,unittest
from pathlib import Path
from tools import run_ui_shard as shard,ci_gates
from tools.tests.run114_repair_budget_history import before_run114_repairs,historical_run114_ui_source,BASELINE_PROFILE_SHA256,CURRENT_PROFILE_SHA256
ROOT=Path(__file__).resolve().parents[2]
class Run114RepairBudget(unittest.TestCase):
    def setUp(self):
        self.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text())
        self.plan=self.profile['planning_budget']['run114_repair_replan'];self.methods={};self.costs={}
        for path in sorted((ROOT/'Tests/AppUITests').glob('*.swift')):
            source=path.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',source)
            if not names:continue
            cases=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',source)
            self.assertEqual(len(cases),1);case=cases[0];self.assertNotIn(case,self.costs);self.costs[case]=Decimal(0)
            for name in names:
                key=case+'.'+name;self.assertNotIn(key,self.methods);self.methods[key]=path
                self.costs[case]+=Decimal(str(self.profile['method_seconds'].get(key,self.profile['estimated_method_seconds'].get(key,60))))
    def test_current_inventory_has_660_unique_methods_and_102_whole_classes(self):
        self.assertEqual((len(self.methods),len(self.costs)),(660,102))
        self.assertEqual(set(self.methods),set(self.plan['current_inventory']))
        self.assertEqual(len(self.plan['current_inventory']),660)
        self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(),self.plan['current_inventory_sha256'])
        self.assertEqual(self.plan['method_migrations'],{});self.assertEqual(self.plan['new_coverage_methods'],0)
        self.assertEqual(sum(shard.discover(ROOT/'Tests/AppUITests').values()),660)
    def test_all_617_complete_successes_have_exact_published_source_and_log_provenance(self):
        samples=self.profile['run114_method_observations'];self.assertEqual(len(samples),617)
        self.assertEqual(len({x['method'] for x in samples}),617)
        for row in samples:
            key=row['method'];self.assertIn(key,self.methods)
            self.assertEqual((row['run_id'],row['status'],row['complete_method']),(37333534698,'passed',True))
            self.assertEqual(row['measured_commit'],'f2140d9c488bb4f7a27534963f40eec5ccd79d17')
            self.assertGreater(row['job_id'],0);self.assertGreater(row['log_line'],0)
            old=historical_run114_ui_source(self.methods[key]).read_bytes()
            self.assertEqual(hashlib.sha256(old).hexdigest(),row['test_file_sha256'])
            self.assertEqual(hashlib.sha1(b'blob '+str(len(old)).encode()+b'\0'+old).hexdigest(),row['test_file_blob'])
            for field in ['log_sha256','declaration_sha256','helper_declarations_sha256','reachable_helper_declarations_sha256','candidate_reachable_helper_declarations_sha256']:
                self.assertRegex(row[field],r'^[a-f0-9]{64}$')
            effective=self.profile['method_seconds'].get(key,self.profile['estimated_method_seconds'].get(key,60))
            self.assertGreaterEqual(effective,row['seconds'])
            if row['applicability']=='unmeasured_floor':
                self.assertNotIn(key,self.profile['method_seconds']);self.assertIn(key,self.profile['estimated_method_seconds'])
            else:self.assertTrue(row['same_declaration'] and row['same_helpers'])
        self.assertEqual(self.plan['failed_prefixes_excluded_from_costs'],35)
        self.assertEqual(len(self.plan['started_unfinished']),2);self.assertEqual(len(self.plan['not_started']),6)
        excluded=self.plan['started_unfinished']+self.plan['not_started']
        self.assertEqual(len(set(excluded)),8);self.assertTrue(set(excluded).isdisjoint(x['method'] for x in samples))
        self.assertEqual(self.plan['observation_cutoff_utc'],'2026-10-05T18:04:22Z')
    def test_full_unmeasured_estimates_bind_final_source_and_never_lower_prior_costs(self):
        rows=self.profile['estimate_provenance']['methods'];self.assertEqual(len(rows),len({x['method'] for x in rows}))
        self.assertEqual({x['method'] for x in rows},set(self.profile['estimated_method_seconds']))
        for row in rows:
            self.assertFalse(row['measured']);key=row['method'];self.assertEqual(row['seconds'],self.profile['estimated_method_seconds'][key])
            self.assertEqual(hashlib.sha256(self.methods[key].read_bytes()).hexdigest(),row['test_file_sha256'])
            self.assertGreater(row['seconds'],0);self.assertLessEqual(row['seconds'],900)
        old=before_run114_repairs(self.profile)
        for key in self.methods:
            before=old['method_seconds'].get(key,old['estimated_method_seconds'].get(key,60));after=self.profile['method_seconds'].get(key,self.profile['estimated_method_seconds'].get(key,60))
            self.assertGreaterEqual(after,before)
        for row in self.plan['complete_success_based_full_replacements']:
            self.assertGreaterEqual(row['teardown_variance_reserve_seconds'],30)
            self.assertEqual(Decimal(str(row['complete_work']))+Decimal(str(row['teardown_variance_reserve_seconds'])),Decimal(str(row['whole_method_unmeasured_seconds'])))
    def test_minimum_34_whole_class_shards_fit_without_relaxed_deadline_or_gate(self):
        count=self.plan['shard_count'];self.assertEqual(count,34)
        self.assertEqual((shard.DEFAULT_SHARD_COUNT,ci_gates.SHARD_COUNT),(count,count))
        self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds']),(1800,300))
        groups=shard.partition(self.costs,count)
        self.assertEqual(groups,shard.partition(shard.measured_weights(ROOT/'Tests/AppUITests',ROOT/'tools/ui_duration_weights.json'),count))
        flat=sum(groups,[]);self.assertEqual(set(flat),set(self.costs));self.assertEqual(len(flat),102)
        maximum=max(sum(self.costs[c] for c in group)+300 for group in groups)
        self.assertEqual(maximum,Decimal(str(self.plan['maximum_projected_seconds_with_reserve'])));self.assertLessEqual(maximum,1800)
        self.assertLessEqual(max(self.costs.values()),1500)
        prior=shard.partition(self.costs,count-1);prior_max=max(sum(self.costs[c] for c in g)+300 for g in prior)
        self.assertEqual(prior_max,Decimal(str(self.plan['prior_count_forecast'])));self.assertGreater(prior_max,1800)
        workflow=(ROOT/'.github/workflows/native-ios.yml').read_text();outputs=re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',workflow,re.M)
        self.assertEqual(outputs,[(str(i),str(i)) for i in range(count)])
        self.assertIn('--count 34 ',workflow);self.assertIn('--deadline-seconds 1800',workflow)
    def test_play_presentation_impact_tracks_actual_fixture_callers(self):
        old=before_run114_repairs(self.profile)
        samples={x['method']:x for x in self.profile['run114_method_observations']}
        reference={'testKnownProgressAndCurrentTaskReopenPreserveServerZero','testUnknownTotalShowsPhaseWithoutPercentage','testChineseServerCompletedHasNoCurrentAction','testFailedTaskReadCannotShowAProgressBarOrCurrentAction'}
        for method in self.methods:
            case,name=method.split('.',1)
            if case=='ReferenceChatTaskFlowTests':
                if name in reference:self.assertIn(method,self.profile['estimated_method_seconds'])
                elif method in samples and method not in old['estimated_method_seconds']:
                    self.assertEqual(samples[method]['applicability'],'applicable_completed_observation')
            if case=='PlayPreferenceFlowTests':self.assertIn(method,self.profile['estimated_method_seconds'])
        self.assertEqual(sum(x.startswith('PlayPreferenceFlowTests.') for x in self.methods),2)
    def test_previous_profile_reconstructs_exactly_and_all_corruptions_fail_closed(self):
        digest=lambda x:hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        self.assertEqual(digest(self.profile),CURRENT_PROFILE_SHA256)
        self.assertEqual(digest(before_run114_repairs(self.profile)),BASELINE_PROFILE_SHA256)
        for mutation in ['missing','duplicate','stale_source','stale_seconds','missing_method','lower_cost']:
            p=deepcopy(self.profile)
            if mutation=='missing':p['run114_method_observations'].pop()
            elif mutation=='duplicate':p['run114_method_observations'].append(p['run114_method_observations'][0])
            elif mutation=='stale_source':p['run114_method_observations'][0]['test_file_sha256']='0'*64
            elif mutation=='stale_seconds':p['run114_method_observations'][0]['seconds']=1
            elif mutation=='missing_method':p['planning_budget']['run114_repair_replan']['current_inventory'].pop()
            else:p['estimated_method_seconds'][next(iter(p['estimated_method_seconds']))]=1
            with self.assertRaises(AssertionError):before_run114_repairs(p)
