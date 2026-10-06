"""Complete run116 evidence, conservative live planning, and immutable history."""
from copy import deepcopy
from decimal import Decimal
from pathlib import Path
import hashlib,json,re,unittest
from tools import run_ui_shard as shard,ci_gates
from tools.tests.run116_repair_budget_history import (
    before_run116_repairs,historical_run116_ui_source,
    BASELINE_PROFILE_SHA256,CURRENT_PROFILE_SHA256)

ROOT=Path(__file__).resolve().parents[2]
def canonical(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

class Run116RepairBudget(unittest.TestCase):
    def setUp(self):
        self.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text())
        self.plan=self.profile['planning_budget']['run116_repair_replan']
        self.methods={};self.costs={}
        for path in sorted((ROOT/'Tests/AppUITests').glob('*.swift')):
            source=path.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',source)
            if not names:continue
            cases=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',source)
            self.assertEqual(len(cases),1);case=cases[0];self.assertNotIn(case,self.costs)
            self.costs[case]=Decimal(0)
            for name in names:
                key=case+'.'+name;self.assertNotIn(key,self.methods);self.methods[key]=path
                self.costs[case]+=Decimal(str(self.effective(key)))
    def effective(self,key):
        return self.profile['method_seconds'].get(key,self.profile['estimated_method_seconds'].get(key,60))
    def test_every_660_method_remains_in_exactly_one_of_102_direct_classes(self):
        self.assertEqual((len(self.methods),len(self.costs)),(660,102))
        self.assertEqual(set(self.methods),set(self.plan['current_inventory']))
        self.assertEqual(len(self.plan['current_inventory']),660)
        self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(),self.plan['current_inventory_sha256'])
        self.assertEqual(self.plan['method_migrations'],{});self.assertEqual(self.plan['new_coverage_methods'],0)
        self.assertEqual(sum(shard.discover(ROOT/'Tests/AppUITests').values()),660)
    def test_all_610_successes_bind_exact_published_source_and_job_log_evidence(self):
        rows=self.profile['run116_method_observations']
        self.assertEqual(len(rows),610);self.assertEqual(len({x['method'] for x in rows}),610)
        for row in rows:
            key=row['method'];self.assertIn(key,self.methods)
            self.assertEqual((row['status'],row['complete_method'],row['run_id']),('passed',True,37402870623))
            self.assertEqual(row['measured_commit'],'68c5f96da128b1e31c443476f66c54a883246ba8')
            self.assertGreater(row['job_id'],0);self.assertGreater(row['log_line'],0)
            old=historical_run116_ui_source(self.methods[key]).read_bytes()
            self.assertEqual(hashlib.sha256(old).hexdigest(),row['test_file_sha256'])
            self.assertEqual(hashlib.sha1(b'blob '+str(len(old)).encode()+b'\0'+old).hexdigest(),row['test_file_blob'])
            for field in ('log_sha256','declaration_sha256','reachable_helper_declarations_sha256'):
                self.assertRegex(row[field],r'^[a-f0-9]{64}$')
            self.assertGreaterEqual(self.effective(key),row['seconds'])
            if row['applicability']=='unmeasured_floor':
                self.assertIn(key,self.profile['estimated_method_seconds']);self.assertNotIn(key,self.profile['method_seconds'])
            else:self.assertTrue(row['same_declaration'] and row['same_helpers'])
    def test_failed_prefixes_and_unexecuted_methods_are_not_successes_or_coverage_removals(self):
        self.assertEqual(self.plan['failed_prefixes_excluded_from_costs'],25)
        self.assertEqual(self.plan['all_success_observations_imported'],610)
        self.assertEqual(self.plan['started_unfinished'],['GrowthCenterFlowTests.testChineseAndAccessibilityLayoutsRemainReachable'])
        self.assertEqual(len(self.plan['not_started']),24)
        excluded=self.plan['started_unfinished']+self.plan['not_started']
        self.assertEqual(len(set(excluded)),25);self.assertTrue(set(excluded)<=set(self.methods))
        self.assertTrue(set(excluded).isdisjoint(x['method'] for x in self.profile['run116_method_observations']))
        self.assertEqual(610+25+len(excluded),660)
        for key in ('CouponCommandRecoveryFlowTests.testV1ReadOnlyReceiptRecoveryAfterRestartAndNotFoundKeepsJournal',
                    'SocialAccountFlowTests.testSyntheticAcknowledgementIsLabelledAndDoesNotInsertPost',
                    'IntegratedNativeAcceptanceFlowTests.testConfiguredAuthenticationDoesNotGrantDetailMapPlayOrOwnedOrders'):
            self.assertIn(key,self.profile['estimated_method_seconds'])
        self.assertGreaterEqual(self.effective('CouponCommandRecoveryFlowTests.testV1ReadOnlyReceiptRecoveryAfterRestartAndNotFoundKeepsJournal'),540)
    def test_complete_estimates_bind_current_source_and_no_prior_effective_cost_is_lowered(self):
        rows=self.profile['estimate_provenance']['methods']
        self.assertEqual(len(rows),len({x['method'] for x in rows}))
        self.assertEqual({x['method'] for x in rows},set(self.profile['estimated_method_seconds']))
        for row in rows:
            self.assertFalse(row['measured']);key=row['method']
            self.assertEqual(row['seconds'],self.profile['estimated_method_seconds'][key])
            self.assertEqual(hashlib.sha256(self.methods[key].read_bytes()).hexdigest(),row['test_file_sha256'])
            self.assertGreater(row['seconds'],0);self.assertLessEqual(row['seconds'],900)
        old=before_run116_repairs(self.profile)
        for key in self.methods:
            self.assertGreaterEqual(self.effective(key),old['method_seconds'].get(key,old['estimated_method_seconds'].get(key,60)))
        # These unchanged methods retain larger prior complete allowances.
        self.assertGreaterEqual(self.effective('CouponRuntimeFlowTests.testChineseNormalRootLabelsAndReadOnlyConfirmation'),232.858)
    def test_all_35_live_shards_and_the_full_completion_gate_fit_the_unchanged_hard_limit(self):
        count=self.plan['shard_count'];self.assertEqual(count,35)
        self.assertEqual((shard.DEFAULT_SHARD_COUNT,ci_gates.SHARD_COUNT),(35,35))
        self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds']),(1800,300))
        groups=shard.partition(self.costs,count)
        self.assertEqual(groups,shard.partition(shard.measured_weights(ROOT/'Tests/AppUITests',ROOT/'tools/ui_duration_weights.json'),count))
        flat=sum(groups,[]);self.assertEqual(len(flat),len(set(flat)));self.assertEqual(set(flat),set(self.costs))
        maximum=max(sum(self.costs[c] for c in group)+300 for group in groups)
        self.assertEqual(maximum,Decimal(str(self.plan['maximum_projected_seconds_with_reserve'])))
        self.assertLessEqual(maximum,1800);self.assertLessEqual(max(self.costs.values()),1500)
        prior=max(sum(self.costs[c] for c in group)+300 for group in shard.partition(self.costs,34))
        self.assertEqual(prior,Decimal(str(self.plan['prior_count_forecast'])));self.assertGreater(prior,1800)
        workflow=(ROOT/'.github/workflows/native-ios.yml').read_text()
        outputs=re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',workflow,re.M)
        self.assertEqual(outputs,[(str(i),str(i)) for i in range(35)])
        self.assertIn('--count 35 ',workflow);self.assertIn('--deadline-seconds 1800',workflow)
    def test_exact_prior_profile_reconstruction_rejects_omissions_and_corruption(self):
        self.assertEqual(canonical(self.profile),CURRENT_PROFILE_SHA256)
        self.assertEqual(canonical(before_run116_repairs(self.profile)),BASELINE_PROFILE_SHA256)
        for kind in ('dropped_success','duplicated_success','wrong_seconds','wrong_source','dropped_inventory','lowered_cost','missing_prior'):
            value=deepcopy(self.profile)
            if kind=='dropped_success':value['run116_method_observations'].pop()
            elif kind=='duplicated_success':value['run116_method_observations'].append(deepcopy(value['run116_method_observations'][0]))
            elif kind=='wrong_seconds':value['run116_method_observations'][0]['seconds']=1
            elif kind=='wrong_source':value['run116_method_observations'][0]['test_file_sha256']='0'*64
            elif kind=='dropped_inventory':value['planning_budget']['run116_repair_replan']['current_inventory'].pop()
            elif kind=='missing_prior':value['run116_previous_estimate_provenance'].pop()
            else:value['estimated_method_seconds'][next(iter(value['estimated_method_seconds']))]=1
            with self.assertRaises(AssertionError):before_run116_repairs(value)
