"""Whole-method repair identity, monotonic cost and exact prior-layer negative controls."""
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
import hashlib,json,re,shutil,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from tools import run129_repair_planning as layer,run_ui_shard as shard
from tools.run129_late_readiness import frozen_repair_context
_FROZEN_30CD = frozen_repair_context()
ROOT=_FROZEN_30CD.root
UI=ROOT/'Tests/AppUITests'
class Run129RepairBudgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text())
        cls.contract=json.loads((ROOT/'tools/run129_repair_planning_contract.json').read_text())
        cls.doc=json.loads((ROOT/'docs/run129-repair-integration-budget.json').read_text())
    def run_profile(self,profile,ui=UI):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'p.json';p.write_text(json.dumps(profile));before=p.read_bytes()
            result=shard.measured_weights(ui,p);self.assertEqual(before,p.read_bytes());return result
    def test_live_inventory_and_all_methods_map_once(self):
        counts=shard.discover(UI);self.assertEqual((sum(counts.values()),len(counts)),(736,161))
        original=[self.contract['aliases'].get(k,k) for k in self.contract['current_inventory']]
        self.assertEqual(len(original),len(set(original)));self.assertEqual(sorted(original),self.contract['historical_inventory'])
        self.assertEqual(len(self.contract['aliases']),2)
    def test_every_prior_profile_field_is_retained_exactly(self):
        old=layer.before_run129_repairs(self.profile)
        original=json.loads((layer.FIXTURES/'tools__ui_duration_weights.json.txt').read_text())
        self.assertEqual(old,original);self.assertEqual(layer.canonical(old),layer.BASELINE_PROFILE_SHA256)
        self.assertEqual(len(old['run117_method_observations']),647)
        for key,value in old.items():
            if key!='planning_budget':self.assertEqual(self.profile[key],value)
        for key,value in old['planning_budget'].items():self.assertEqual(self.profile['planning_budget'][key],value)
    def test_four_launch_allowances_are_whole_method_and_only_increases(self):
        migration=json.loads((layer.FIXTURES/'whole-method-migration.json').read_text())
        self.assertEqual([r['launch_count'] for r in migration['methods']],[1,2,1,1])
        self.assertEqual([r['seconds'] for r in migration['methods']],[750,770,750,750])
        delta=0
        for row in migration['methods']:
            bound=self.contract['required_floors'][row['current_method']]
            self.assertEqual(bound['seconds'],row['seconds']);self.assertFalse(bound['measured'])
            value=row['original_seconds']+row['launch_count']*(row['new_launch_reveal_maximum_swipes']+1)*row['new_reveal_iteration_seconds_assumption']
            self.assertEqual(((value+9)//10)*10,row['seconds']);delta+=row['seconds']-row['original_seconds']
            text=(ROOT/row['path']).read_text();method=row['current_method'].split('.')[1]
            declaration={name:body for body,name in re.findall(layer.PATTERN,text)}[method]
            # Published split receipt includes its original four-space indentation.
            self.assertEqual(hashlib.sha256(('    '+declaration).encode()).hexdigest(),row['test_declaration_sha256'])
            self.assertEqual(hashlib.sha256(declaration.encode()).hexdigest(),bound['declaration_sha256'])
        self.assertEqual(delta,140)
    def test_unmodified_method_declarations_remain_exact_across_two_splits(self):
        migration=json.loads((layer.FIXTURES/'whole-method-migration.json').read_text())
        for row in migration['methods']:
            before=layer.historical_source(UI/(row['historical_method'].split('.')[0]+'.swift')).read_text()
            after=(ROOT/row['path']).read_text();method=row['current_method'].split('.')[1]
            get=lambda t:{n:b for b,n in re.findall(layer.PATTERN,t)}
            self.assertEqual(get(before)[method],get(after)[method])
    def test_actual_costs_and_every_forecast_recompute(self):
        live=self.run_profile(self.profile);costs={k:Decimal(v) for k,v in self.doc['classes'].items()}
        self.assertEqual(set(live),set(costs));self.assertEqual(sum(costs.values()),Decimal('104377.381'))
        for key,value in costs.items():self.assertAlmostEqual(live[key],float(value),places=8)
        for n in range(1,162):
            actual=max(sum(costs[k] for k in g)+300 for g in shard.partition(costs,n))
            self.assertEqual(str(actual),self.doc['forecasts'][str(n)])
        self.assertEqual((self.doc['first_deadline_fitting_shards'],self.doc['first_30_second_headroom_shards']),(77,78))
        self.assertEqual(self.doc['forecasts']['78'],'1770')
    def test_delivered_78_shards_and_test_counts_are_exact(self):
        inv=json.loads((ROOT/'docs/ui-shard-inventory.json').read_text());counts=shard.discover(UI)
        groups=shard.partition({k:Decimal(v) for k,v in self.doc['classes'].items()},78)
        self.assertEqual(inv['shards'],groups);self.assertEqual(inv['classes'],counts)
        self.assertEqual(inv['shard_test_counts'],[sum(counts[k] for k in g) for g in groups])
        self.assertEqual(sum(inv['shard_test_counts']),736);self.assertEqual(len(inv['shard_test_counts']),78)
        flat=sum(groups,[]);self.assertEqual((len(flat),len(set(flat))),(161,161))
    def test_missing_plan_cannot_escape_via_source_projection(self):
        p=deepcopy(self.profile);p['planning_budget'].pop(layer.PLAN)
        with self.assertRaises(ValueError):self.run_profile(p)
    def test_profile_cost_alias_inventory_or_old_observation_mutations_fail(self):
        key=next(iter(self.contract['required_floors']))
        for mode in ['lower','missing','rename','inventory','old_timing']:
            p=deepcopy(self.profile);plan=p['planning_budget'][layer.PLAN]
            if mode=='lower':plan['whole_method_estimates'][key]-=1
            elif mode=='missing':plan['whole_method_estimates'].pop(key)
            elif mode=='rename':plan['aliases'].clear()
            elif mode=='inventory':plan['current_inventory'].pop()
            else:p['method_seconds'][next(iter(p['method_seconds']))]=1
            with self.subTest(mode=mode),self.assertRaises(ValueError):self.run_profile(p)
    def test_removed_renamed_added_duplicate_method_or_file_fails(self):
        for mode in ['remove_file','rename_file','omit_method','add_method','duplicate_method']:
            with tempfile.TemporaryDirectory() as d:
                ui=Path(d)/'ui';shutil.copytree(UI,ui);p=ui/'ApprovedReleasePreparationChineseFlowTests.swift'
                if mode=='remove_file':p.unlink()
                elif mode=='rename_file':p.rename(ui/'Other.swift')
                elif mode=='omit_method':p.write_text(p.read_text().replace('func test','func omitted',1))
                elif mode=='add_method':p.write_text(p.read_text().replace('    func test','    func testUncosted() {}\n    func test',1))
                else:p.write_text(p.read_text()+'\n'+p.read_text())
                with self.subTest(mode=mode),self.assertRaises(ValueError):self.run_profile(self.profile,ui)
    def test_changed_local_shared_helper_or_unrelated_method_fails(self):
        for filename,before,after in [('ApprovedReleasePreparationFlowTests.swift','maximumSwipes: 10','maximumSwipes: 11'),('FailureScreenshot.swift','maximumSwipes','otherMaximumSwipes'),('EntryFlowTests.swift','func test','func testRenamed')]:
            with tempfile.TemporaryDirectory() as d:
                ui=Path(d)/'ui';shutil.copytree(UI,ui);p=ui/filename;self.assertIn(before,p.read_text());p.write_text(p.read_text().replace(before,after,1))
                with self.subTest(file=filename),self.assertRaises(ValueError):self.run_profile(self.profile,ui)
    def test_contract_change_cannot_lower_floor_or_raise_method_cap(self):
        for mutate in ['floor','cap','index']:
            value=deepcopy(self.contract)
            if mutate=='floor':value['required_floors'][next(iter(value['required_floors']))]['seconds']=1
            elif mutate=='cap':value['method_limit_seconds']=901
            else:value['source_index_sha256']='0'*64
            with tempfile.TemporaryDirectory() as d:
                p=Path(d)/'c.json';p.write_text(json.dumps(value))
                with self.assertRaises(ValueError):layer.pinned_json(p,layer.CONTRACT_SHA256)
    def test_unknown_current_bytes_have_no_historical_fallback(self):
        with tempfile.TemporaryDirectory() as d:
            ui=Path(d)/'AppUITests';ui.mkdir();p=ui/'ClubOperationsFlowTests.swift';p.write_bytes((UI/p.name).read_bytes()+b'\n// changed\n')
            with self.assertRaises(ValueError):layer.historical_source(p)
    def test_no_old_source_for_new_scheduling_wrappers(self):
        for name in layer.NEW_CLASSES:
            with self.assertRaises(ValueError):layer.historical_source(UI/(name+'.swift'))
    def test_five_930_proposals_remain_unapplied_and_cannot_be_projected_away(self):
        idx=layer.source_index()
        for name in ['ApprovedReleaseRecoveryFlowTests','ApprovedTopicReviewCurrentChineseFlowTests','ApprovedTopicReviewUnknownFlowTests','ApprovedTopicSelectedCoverChineseFlowTests','ProjectStoryAudioRecoveryFlowTests']:
            rel='Tests/AppUITests/'+name+'.swift'
            self.assertEqual(idx['current_ui_sources'][rel]['sha256'],idx['historical_ui_sources'][rel]['sha256'])
            self.assertNotIn('historical_file',idx['historical_ui_sources'][rel])
        self.assertIn('930',self.doc['status']);self.assertIn('HOLD',self.doc['status'])
    def test_historical_tooling_and_ui_do_not_consume_current_repairs(self):
        context=layer.frozen_player_context()
        self.addCleanup(context.lifetime.cleanup)
        p=context.root/'tools/ui_duration_weights.json';cost=context.runner.measured_weights(context.root/'Tests/AppUITests',p)
        self.assertEqual(len(cost),159);self.assertAlmostEqual(sum(cost.values()),104237.381,places=6)
        self.assertNotIn('run129_repair_planning',(context.root/'tools/run_ui_shard.py').read_text())
