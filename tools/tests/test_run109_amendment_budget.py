"""Current exhaustive planning, real observation provenance and exact older history."""
from copy import deepcopy
from decimal import Decimal
import hashlib,json,re,unittest
from pathlib import Path
from tools import run_ui_shard as shard, ci_gates
from tools.tests.run109_amendment_budget_history import before_run109_amendments, BASELINE_PROFILE_SHA256, CURRENT_PROFILE_SHA256
ROOT=Path(__file__).resolve().parents[2]
class Run109AmendmentBudget(unittest.TestCase):
    def setUp(self):
        self.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text())
        self.plan=self.profile['planning_budget']['run109_amendment_replan']
        self.methods={};self.costs={}
        for path in sorted((ROOT/'Tests/AppUITests').glob('*.swift')):
            source=path.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',source)
            if not names:continue
            cases=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',source)
            self.assertEqual(len(cases),1);case=cases[0];self.assertNotIn(case,self.costs)
            self.costs[case]=Decimal(0)
            for name in names:
                method=case+'.'+name;self.assertNotIn(method,self.methods);self.methods[method]=path
                self.costs[case]+=Decimal(str(self.profile['method_seconds'].get(method,self.profile['estimated_method_seconds'].get(method,60))))
    def test_all_660_methods_execute_once_across_102_direct_classes(self):
        self.assertEqual((len(self.methods),len(self.costs)),(660,102))
        self.assertEqual(set(self.methods),set(self.plan['current_inventory']))
        self.assertEqual(sum(shard.discover(ROOT/'Tests/AppUITests').values()),660)
        self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(),self.plan['current_inventory_sha256'])
        old=before_run109_amendments(self.profile);old_ids=set(old['planning_budget']['reviewed_native_functional_replan']['baseline_inventory'])
        old_ids.update(old['planning_budget']['reviewed_native_functional_replan']['new_methods'])
        mapping=self.plan['method_migrations'];self.assertEqual(len(mapping),4)
        self.assertEqual(len(set(mapping.values())),4)
        self.assertEqual({mapping.get(k,k) for k in old_ids},set(self.methods))
        self.assertEqual(self.plan['new_coverage_methods'],0)
        for before,after in mapping.items():self.assertNotIn(before,self.methods);self.assertIn(after,self.methods)
    def test_all_successes_are_complete_exact_commit_evidence_and_changed_source_is_not_measured(self):
        seen=set();samples=self.profile['run109_method_observations']
        self.assertEqual(len(samples),self.plan['all_success_observations_imported'])
        self.assertEqual(len(samples),599)
        for row in samples:
            self.assertEqual(row['status'],'passed');self.assertTrue(row['complete_method'])
            self.assertEqual(row['measured_commit'],'ffb3e811def6f683e4e8b70d65f53b4e5efff4cb')
            self.assertEqual(row['run_id'],37297613111);self.assertGreater(row['log_line'],0)
            self.assertNotIn(row['method'],seen);seen.add(row['method'])
            method=row['current_method'];self.assertIn(method,self.methods)
            effective=self.profile['method_seconds'].get(method,self.profile['estimated_method_seconds'].get(method,60))
            self.assertGreaterEqual(effective,row['seconds'])
            if row['applicability']=='unmeasured_floor':
                self.assertIn(method,self.profile['estimated_method_seconds']);self.assertNotIn(method,self.profile['method_seconds'])
            else:
                self.assertTrue(row['same_declaration'])
                self.assertTrue(row['same_helpers'] or row['changed_helper_branch_not_called'])
            for key in ['test_file_sha256','declaration_sha256','helper_declarations_sha256','log_sha256']:
                self.assertRegex(row[key],r'^[a-f0-9]{64}$')
        self.assertEqual(self.plan['failed_prefixes_excluded_from_costs'],55)
        supplemental=self.plan['supplemental_same_tree_success_observations']
        self.assertEqual(len(supplemental),1)
        row=supplemental[0];self.assertEqual(row['method'],'ProfileEditFlowTests.testIncompleteSnapshotCannotBeEdited')
        self.assertEqual((row['run_id'],row['job_id'],row['status'],row['seconds']),
                         (37311058178,111771715082,'passed',9.208))
        self.assertEqual(row['source_commit'],'4e7349186d21448354d3bf4c6b4ab6adfc25fc1f')
        self.assertEqual(row['source_tree'],'7e5f4e692e0ee0f253a615f12276610eabdfa07a')
        self.assertEqual(hashlib.sha256(self.methods[row['method']].read_bytes()).hexdigest(),row['published_source']['file_sha256'])
        self.assertGreaterEqual(self.profile['method_seconds'][row['method']],row['seconds'])

    def test_every_effective_unmeasured_record_binds_current_source_and_no_old_cost_was_lowered(self):
        records=self.profile['estimate_provenance']['methods']
        self.assertEqual(len(records),len({x['method'] for x in records}))
        self.assertEqual({x['method'] for x in records},set(self.profile['estimated_method_seconds']))
        for row in records:
            self.assertFalse(row['measured']);method=row['method']
            self.assertEqual(row['seconds'],self.profile['estimated_method_seconds'][method])
            self.assertEqual(hashlib.sha256(self.methods[method].read_bytes()).hexdigest(),row['test_file_sha256'])
            self.assertGreater(row['seconds'],0);self.assertLessEqual(row['seconds'],900)
        previous=before_run109_amendments(self.profile)
        for old,new in [(k,self.plan['method_migrations'].get(k,k)) for k in set(previous['method_seconds'])|set(previous['estimated_method_seconds'])]:
            if new not in self.methods:continue
            old_cost=previous['method_seconds'].get(old,previous['estimated_method_seconds'].get(old,60))
            new_cost=self.profile['method_seconds'].get(new,self.profile['estimated_method_seconds'].get(new,60))
            self.assertGreaterEqual(new_cost,old_cost)
    def test_decimal_plan_live_runner_and_complete_gate_agree_without_relaxed_limits(self):
        count=self.plan['shard_count'];self.assertEqual(count,32)
        self.assertEqual(shard.DEFAULT_SHARD_COUNT,count);self.assertEqual(ci_gates.SHARD_COUNT,count)
        self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds']),(1800,300))
        self.assertEqual(self.profile['unobserved_method_seconds'],60)
        groups=shard.partition(self.costs,count)
        self.assertEqual(groups,shard.partition(shard.measured_weights(ROOT/'Tests/AppUITests',ROOT/'tools/ui_duration_weights.json'),count))
        self.assertEqual(set(sum(groups,[])),set(self.costs));self.assertEqual(len(sum(groups,[])),len(self.costs))
        maximum=max(sum(self.costs[c] for c in group)+300 for group in groups)
        self.assertEqual(maximum,Decimal(str(self.plan['maximum_projected_seconds_with_reserve'])))
        self.assertLessEqual(maximum,1800);self.assertTrue(all(x+300<=1800 for x in self.costs.values()))
        prior=shard.partition(self.costs,count-1)
        self.assertGreater(max(sum(self.costs[c] for c in group)+300 for group in prior),1800)
        workflow=(ROOT/'.github/workflows/native-ios.yml').read_text()
        for i in range(count):self.assertIn('shard_'+str(i)+': ${{ steps.completion.outputs.shard_'+str(i)+' }}',workflow)
        self.assertIn('--count 32 ',workflow);self.assertIn('--deadline-seconds 1800',workflow)
    def test_every_previous_profile_restores_exactly_and_corruptions_are_rejected(self):
        self.assertEqual(hashlib.sha256(json.dumps(self.profile,sort_keys=True,separators=(',',':')).encode()).hexdigest(),CURRENT_PROFILE_SHA256)
        previous=before_run109_amendments(self.profile)
        self.assertEqual(hashlib.sha256(json.dumps(previous,sort_keys=True,separators=(',',':')).encode()).hexdigest(),BASELINE_PROFILE_SHA256)
        for key in ['method_seconds','estimated_method_seconds']:
            mutated=deepcopy(self.profile);mutated[key]['Unexpected.testOmission']=1
            with self.assertRaises(AssertionError):before_run109_amendments(mutated)
        for mutation in ['dropped_observation','stale_duration','duplicate_observation','stale_supplemental']:
            changed=deepcopy(self.profile)
            if mutation=='dropped_observation':changed['run109_method_observations'].pop()
            elif mutation=='duplicate_observation':changed['run109_method_observations'].append(changed['run109_method_observations'][0])
            elif mutation=='stale_supplemental':changed['planning_budget']['run109_amendment_replan']['supplemental_same_tree_success_observations'][0]['seconds']=1
            else:changed['run109_method_observations'][0]['seconds']=1
            with self.assertRaises(AssertionError):before_run109_amendments(changed)
