"""Current repair planning retains full costs and exactly reconstructs published history."""
from copy import deepcopy
from decimal import Decimal
from pathlib import Path
import hashlib,json,re,unittest
from tools import run_ui_shard as shard,ci_gates
from tools.tests.run117_repair_budget_history import before_run117_repairs,historical_run117_ui_source,canonical,CURRENT_PROFILE_SHA256,BASELINE_PROFILE_SHA256
ROOT=Path(__file__).resolve().parents[2]
REPLACEMENTS={'ClubStoryFlowTests.testChapterSwitchAndExpansionResetKeepEachPlayInItsOwnChapter': 300, 'ClubStoryFlowTests.testDuplicateChapterIDsKeepDisplaySelectableButAllRoutesDisabled': 180, 'ClubStoryFlowTests.testChineseRoutePlayAndEmptyChapterAreLocalized': 180, 'TopicFlowTests.testReviewSummaryKeepsServerTotalAcrossDifferentRoutesAndReopen': 300, 'IntegratedNativeAcceptanceFlowTests.testNormalRootOwnedConfigurationReadOnlyAndStoryReturn': 360, 'MerchantOnboardingFlowTests.testRejectedBackfillNeedsConfirmationAndReadsPendingState': 180, 'MerchantOnboardingFlowTests.testUnknownSubmissionReadbackNeverUnlocksResubmission': 180, 'CoopRelationDiscoveryFlowTests.testMixedDiscoveryOpensOwnerAndClubProfilesAndReturnsToSelectedTab': 180, 'CoopRelationDiscoveryFlowTests.testPartialIdentityRemainsNoninteractiveAndRefreshDoesNotReadProfiles': 100, 'CoopRelationDiscoveryFlowTests.testClubsOnlyAndEmptyTabsHaveHonestEmptyStates': 90, 'CoopRelationDiscoveryFlowTests.testRetryAndSessionReplacementClearPushedProfile': 210, 'CoopRelationDiscoveryFlowTests.testChineseMaximumTextPreservesTabsAndDisplayOnlyContext': 240}
LEXICAL_ONLY={'ClubStoryFlowTests.testGroupedStopsHaveHoursAddressAndChapterMetadata', 'IntegratedNativeAcceptanceFlowTests.testPhoneCancelLogoutAccountSwitchAndColdLaunchDoNotReuseOwnerState', 'IntegratedNativeAcceptanceFlowTests.testNormalRootIMHistoryDefaultNilNeverDispatches', 'ClubStoryFlowTests.testUnavailableAndInvalidSourcesDoNotOfferTemplateNavigation', 'IntegratedNativeAcceptanceFlowTests.testNormalRootIMHistoryNeverMarksReadOrSends', 'IntegratedNativeAcceptanceFlowTests.testNormalRootTeamReadOnlyJourney', 'MerchantOnboardingFlowTests.testUSIdentityGatePreventsPhotoAccessUploadAndSubmit', 'IntegratedNativeAcceptanceFlowTests.testConfiguredAuthenticationDoesNotGrantDetailMapPlayOrOwnedOrders'}
class Run117RepairBudget(unittest.TestCase):
    def setUp(self):
        self.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text())
        self.prior=before_run117_repairs(self.profile)
        self.plan=self.profile['planning_budget']['run117_repair_replan']
        self.methods={};self.costs={}
        for path in sorted((ROOT/'Tests/AppUITests').glob('*.swift')):
            source=path.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',source)
            if not names:continue
            cases=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',source)
            self.assertEqual(len(cases),1);case=cases[0];self.assertNotIn(case,self.costs);self.costs[case]=Decimal(0)
            for name in names:
                key=case+'.'+name;self.assertNotIn(key,self.methods);self.methods[key]=path
                self.costs[case]+=self.effective(self.profile,key)
    def effective(self,p,k):return Decimal(str(p['method_seconds'].get(k,p['estimated_method_seconds'].get(k,60))))
    def test_inventory_limits_and_complete_costs_are_preserved(self):
        self.assertEqual((len(self.methods),len(self.costs)),(660,102))
        self.assertEqual(set(self.methods),set(self.prior['planning_budget']['run116_repair_replan']['current_inventory']))
        self.assertEqual(hashlib.sha256('\n'.join(sorted(self.methods)).encode()).hexdigest(),self.plan['current_inventory_sha256'])
        self.assertEqual((self.plan['new_coverage_methods'],self.plan['method_migrations']),(0,{}))
        self.assertEqual(self.plan['full_method_replacements'],REPLACEMENTS)
        for k in self.methods:self.assertGreaterEqual(self.effective(self.profile,k),self.effective(self.prior,k))
        for k,v in REPLACEMENTS.items():
            self.assertEqual(self.profile['estimated_method_seconds'][k],v);self.assertNotIn(k,self.profile['method_seconds'])
        self.assertEqual((shard.DEFAULT_SHARD_COUNT,ci_gates.SHARD_COUNT,self.plan['shard_count']),(36, 36, 36))
        self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds']),(1800,300))
        groups=shard.partition(self.costs,36)
        self.assertEqual(groups,shard.partition(shard.measured_weights(ROOT/'Tests/AppUITests',ROOT/'tools/ui_duration_weights.json'),36))
        flat=sum(groups,[]);self.assertEqual(len(flat),len(set(flat)));self.assertEqual(set(flat),set(self.costs))
        peak=max(sum(self.costs[c] for c in group)+300 for group in groups)
        self.assertEqual(peak,Decimal(str(self.plan['maximum_projected_seconds_with_reserve'])))
        self.assertLessEqual(peak,1800);self.assertLessEqual(max(self.costs.values()),1500)
        self.assertGreater(self.plan['forecasts']['35'],1800)
        workflow=(ROOT/'.github/workflows/native-ios.yml').read_text()
        outputs=re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',workflow,re.M)
        self.assertEqual(outputs,[(str(i),str(i)) for i in range(self.plan['shard_count'])])
        self.assertIn('--count '+str(self.plan['shard_count'])+' ',workflow)
        self.assertIn('--deadline-seconds 1800',workflow)
        self.assertIn('cancel-in-progress: true',workflow)

    def test_cutoff_observations_are_complete_successes_bound_to_actual_f128_sources(self):
        rows=self.profile['run117_method_observations']
        self.assertEqual(len(rows),self.plan['all_success_observations_imported']);self.assertEqual(len(rows),len({x['method'] for x in rows}))
        self.assertTrue(self.plan['run_terminal']);self.assertTrue(self.plan['snapshot']['run_terminal'])
        self.assertEqual((len(rows),self.plan['measured_failure_count']),(647,13))
        self.assertEqual(self.plan['measured_shard_count'],35)
        self.assertEqual(len(set(self.plan['failed_methods'])),13)
        self.assertEqual(self.plan['started_unfinished'],[]);self.assertEqual(self.plan['not_started'],[])
        self.assertEqual({x['method'] for x in rows}|set(self.plan['failed_methods']),set(self.methods))
        self.assertTrue({x['method'] for x in rows}.isdisjoint(self.plan['failed_methods']))
        self.assertGreater(self.plan['failed_prefixes_excluded_from_costs'],0)
        for row in rows:
            k=row['method'];self.assertIn(k,self.methods)
            self.assertEqual((row['status'],row['complete_method'],row['run_id']),('passed',True,37456902125))
            self.assertEqual(row['measured_commit'],'f128b1a8bf3de65719e0307f6d883e8a14389417')
            self.assertGreater(row['job_id'],0);self.assertGreater(row['log_line'],0);self.assertRegex(row['log_sha256'],r'^[a-f0-9]{64}$')
            data=historical_run117_ui_source(self.methods[k]).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(),row['test_file_sha256'])
            self.assertEqual(hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest(),row['test_file_blob'])
            self.assertGreaterEqual(self.effective(self.profile,k),Decimal(str(row['seconds'])));self.assertTrue(row['same_declaration'])
            if row.get('known_production_impact'):
                self.assertTrue(k.startswith('CoopRelationDiscoveryFlowTests.'))
                self.assertEqual(row['applicability'],'unmeasured_floor')
                self.assertIn(k,self.profile['estimated_method_seconds']);self.assertNotIn(k,self.profile['method_seconds'])
            if not row['same_helpers']:
                self.assertIn(k,LEXICAL_ONLY|set(REPLACEMENTS))
                if row['unexecuted_changed_branch']:self.assertIn(k,LEXICAL_ONLY)
                else:self.assertEqual(row['applicability'],'unmeasured_floor')
    def test_all_current_estimates_bind_current_source(self):
        rows=self.profile['estimate_provenance']['methods']
        self.assertEqual(len(rows),len({x['method'] for x in rows}));self.assertEqual({x['method'] for x in rows},set(self.profile['estimated_method_seconds']))
        for row in rows:
            k=row['method'];self.assertFalse(row['measured']);self.assertEqual(row['seconds'],self.profile['estimated_method_seconds'][k])
            self.assertEqual(hashlib.sha256(self.methods[k].read_bytes()).hexdigest(),row['test_file_sha256'])
            self.assertGreater(row['seconds'],0);self.assertLessEqual(row['seconds'],900)
    def test_all_twelve_geometry_file_methods_are_byte_preserved_and_only_four_call_the_changed_branch(self):
        declarations={}
        for case in ('ClubStoryFlowTests','TopicFlowTests'):
            path=ROOT/'Tests/AppUITests'/(case+'.swift')
            def methods(source):
                result={}
                for m in re.finditer(r'    func (test\w+)\s*\(',source):
                    end=source.index('\n    }',m.start())+len('\n    }');result[case+'.'+m[1]]=source[m.start():end]
                return result
            now=methods(path.read_text());old=methods(historical_run117_ui_source(path).read_text())
            self.assertEqual(now,old);declarations.update(now)
        self.assertEqual(len(declarations),12)
        for k in (k for k in LEXICAL_ONLY if k.startswith('ClubStory')):
            self.assertNotIn('club.story.chapter.',declarations[k]);self.assertNotIn('tapChapter',declarations[k])
        source=(ROOT/'Tests/AppUITests/ClubStoryFlowTests.swift').read_text()
        self.assertIn('tap("club.gov.openStory")',source)
        self.assertIn('private func gameplay() { app.segmentedControls["club.story.tabs"].buttons.element(boundBy: 1).tap() }',source)
    def test_shelf_and_diagnostic_methods_preserve_all_existing_business_statements(self):
        for case,count in [('IntegratedNativeAcceptanceFlowTests',6),('MerchantOnboardingFlowTests',3)]:
            path=ROOT/'Tests/AppUITests'/(case+'.swift')
            def bodies(source):
                result={}
                for m in re.finditer(r'    func (test\w+)\s*\(',source):
                    end=source.index('\n    }',m.start())+len('\n    }');result[m[1]]=source[m.start():end]
                return result
            current=bodies(path.read_text());prior=bodies(historical_run117_ui_source(path).read_text())
            self.assertEqual(current,prior);self.assertEqual(len(current),count)
            if case=='IntegratedNativeAcceptanceFlowTests':
                for name,body in current.items():
                    if name!='testNormalRootOwnedConfigurationReadOnlyAndStoryReturn':self.assertNotIn('templateAuthor.shelf.loadMore',body)
            else:
                self.assertIn('launch("identity-required")',current['testUSIdentityGatePreventsPhotoAccessUploadAndSubmit'])
                self.assertIn('(testRun?.totalFailureCount ?? 0) > 0',path.read_text())
                self.assertIn('String(evidence.prefix(3072))',path.read_text())
    def test_exact_history_rejects_removed_observations_corrupt_bindings_or_lowered_costs(self):
        self.assertEqual(canonical(self.profile),CURRENT_PROFILE_SHA256);self.assertEqual(canonical(self.prior),BASELINE_PROFILE_SHA256)
        for kind in ('missing_success','duplicate_success','wrong_source','wrong_seconds','lowered_cost','lost_prior','wrong_cutoff'):
            p=deepcopy(self.profile)
            if kind=='missing_success':p['run117_method_observations'].pop()
            elif kind=='duplicate_success':p['run117_method_observations'].append(deepcopy(p['run117_method_observations'][0]))
            elif kind=='wrong_source':p['run117_method_observations'][0]['test_file_sha256']='0'*64
            elif kind=='wrong_seconds':p['run117_method_observations'][0]['seconds']=1
            elif kind=='lowered_cost':p['estimated_method_seconds'][next(iter(REPLACEMENTS))]=1
            elif kind=='lost_prior':p['run117_previous_estimate_provenance'].pop()
            else:p['planning_budget']['run117_repair_replan']['run_terminal']=False
            with self.assertRaises(AssertionError):before_run117_repairs(p)
