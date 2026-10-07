"""Current source-required floors plus exact preservation of the 73-shard layer."""
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest
from unittest.mock import patch
from tools import run_ui_shard as shard, ci_gates
from tools.tests.player_map_history_budget_history import (before_player_map_history, canonical, source_index, materialize_pre_player_ui, historical_player_source, frozen_story_context, BASELINE_PROFILE_SHA256, CURRENT_PROFILE_SHA256, PLAN, MARKER)

# Preserve all original cases against their exact reviewed 78-shard source.
from tools.run129_repair_planning import frozen_player_context
_FROZEN = frozen_player_context()
ROOT = _FROZEN.root
shard, ci_gates = _FROZEN.runner, _FROZEN.gates
UI = ROOT / 'Tests/AppUITests'
PROFILE = ROOT / 'tools/ui_duration_weights.json'

class PlayerMapHistoryBudgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile = json.loads(PROFILE.read_text())
        cls.prior = before_player_map_history(cls.profile)
        cls.plan = cls.profile['planning_budget'][PLAN]
        cls.contract = json.loads(shard.PLAYER_MAP_HISTORY_CONTRACT_PATH.read_text())
        cls.new = cls.contract['required_floors']
        cls.migration = json.loads((ROOT / 'tools/tests/fixtures/player_map_history/whole-method-migration.json').read_text())

    def run_profile(self, value, source=UI):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'profile.json'; file.write_text(json.dumps(value)); before = file.read_bytes()
            result = shard.measured_weights(source, file)
            self.assertEqual(file.read_bytes(), before)
            return result

    def costs(self):
        result = defaultdict(Decimal)
        trusted = {}
        for path in [shard.CLUB_PARITY_CONTRACT_PATH, shard.STORY_TEMPLATE_CONTRACT_PATH, shard.PLAYER_MAP_HISTORY_CONTRACT_PATH]:
            trusted.update(json.loads(path.read_text())['required_floors'])
        for key in self.plan['current_inventory']:
            old = self.profile['method_seconds'].get(key, self.profile['estimated_method_seconds'].get(key,60))
            floor = self.profile.get('method_planning_floors',{}).get(key,{}).get('seconds',0)
            result[key.split('.')[0]] += Decimal(str(max(old, floor, trusted.get(key,{}).get('seconds',0))))
        return result

    def test_live_inventory_is_736_methods_159_whole_classes_with_18_additions(self):
        counts = shard.discover(UI)
        self.assertEqual((sum(counts.values()),len(counts)),(736,159))
        old = set(self.prior['planning_budget']['reviewed_story_template_replan']['current_inventory'])
        self.assertEqual(set(self.plan['current_inventory'])-old,set(self.new)); self.assertEqual(len(self.new),18)
        self.assertEqual(len({key.split('.')[0] for key in self.new}),6)
        groups = shard.partition(self.costs(),78); flat=sum(groups,[])
        self.assertEqual((len(flat),len(set(flat)),set(flat)),(159,159,set(counts)))
        self.assertEqual(sum(counts[name] for name in flat),736)

    def test_all_previous_observations_estimates_provenance_and_plans_remain_exact(self):
        for key,value in self.prior.items():
            if key not in ('estimated_method_seconds','estimate_provenance','planning_budget'): self.assertEqual(self.profile[key],value)
        for key,value in self.prior['estimated_method_seconds'].items(): self.assertEqual(self.profile['estimated_method_seconds'][key],value)
        rows=self.prior['estimate_provenance']['methods']; self.assertEqual(self.profile['estimate_provenance']['methods'][:len(rows)],rows)
        for key,value in self.prior['planning_budget'].items(): self.assertEqual(self.profile['planning_budget'][key],value)
        self.assertEqual(len(self.profile['run117_method_observations']),647)
        self.assertEqual(canonical(self.prior),BASELINE_PROFILE_SHA256)

    def test_full_method_assumptions_count_launches_waits_and_repeated_helpers(self):
        self.assertEqual(sum(row['seconds'] for row in self.new.values()),6150)
        self.assertEqual(self.plan['complete_method_derivations'],list(self.new.values()))
        for row in self.new.values():
            d=row['derivation']; subtotal=d['app_launch_count']*90+d['all_explicit_wait_caps_seconds']+d['reveal_call_count']*(d['maximum_swipes_per_reveal']+1)*2+60
            self.assertEqual(d['iterations_per_reveal'],d['maximum_swipes_per_reveal']+1)
            self.assertEqual(d['subtotal_seconds'],subtotal); self.assertEqual(row['seconds'],((subtotal+9)//10)*10)
            self.assertFalse(row['measured']); self.assertIn('not observed durations',d['limitation']); self.assertLessEqual(row['seconds'],900)
        multi=[r for r in self.new.values() if r['derivation']['app_launch_count']>1]
        self.assertEqual(sorted(r['derivation']['app_launch_count'] for r in multi),[2,2,3])
        self.assertTrue(all(r['seconds']>=90*r['derivation']['app_launch_count'] for r in multi))

    def test_all_18_test_declarations_and_helpers_survive_scheduling_wrappers(self):
        pattern=r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'
        seen=set()
        for row in self.migration['methods']:
            oldclass,method=row['authored_method'].split('.')
            raw=(ROOT/'tools/tests/fixtures/player_map_history'/self.migration['authored_sources'][oldclass]['historical_file']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(),self.migration['authored_sources'][oldclass]['sha256'])
            old={name:body for body,name in re.findall(pattern,raw.decode())}
            current=(ROOT/row['test_path']).read_text(); current_methods={name:body for body,name in re.findall(pattern,current)}
            self.assertEqual(current_methods[method],old[method]);self.assertNotIn(row['authored_method'],seen);seen.add(row['authored_method'])
            helpers=re.sub(pattern,'',current).replace('final class '+row['method'].split('.')[0]+': XCTestCase','final class '+oldclass+': XCTestCase')
            expected=re.sub(pattern,'',raw.decode())
            self.assertEqual(re.sub(r'(?m)^\s*\n','',helpers),re.sub(r'(?m)^\s*\n','',expected))
        self.assertEqual(len(seen),18)

    def test_every_partition_forecast_is_recomputed_and_78_preserves_margin(self):
        costs=self.costs();self.assertEqual(sum(costs.values()),Decimal('104237.381'));self.assertEqual(max(costs.values()),1470)
        self.assertEqual((shard.DEFAULT_SHARD_COUNT,ci_gates.SHARD_COUNT,self.plan['shard_count']),(78,78,78))
        first=None
        for count in range(1,160):
            value=max(sum(costs[name] for name in group)+300 for group in shard.partition(costs,count))
            self.assertEqual(str(value),self.plan['forecasts'][str(count)])
            if value<=1800 and first is None:first=count
            if count<78:self.assertGreater(value,1770)
        self.assertEqual(first,77);self.assertEqual(self.plan['forecasts']['78'],'1770')
        self.assertEqual(self.plan['remaining_margin_seconds'],'30')
        actual=self.run_profile(self.profile)
        for name,value in costs.items():self.assertAlmostEqual(actual[name],float(value),places=8)
        self.assertEqual(shard.partition(actual,78),shard.partition(costs,78))

    def test_workflow_requires_every_shard_without_lowering_limits(self):
        workflow=(ROOT/'.github/workflows/native-ios.yml').read_text()
        self.assertEqual(re.findall(r'^      shard_(\d+): \$\{\{ steps.completion.outputs.shard_(\d+) \}\}',workflow,re.M),[(str(i),str(i)) for i in range(78)])
        self.assertEqual([int(x) for x in re.search(r'shard:\s*\[([0-9,\s]+)\]',workflow)[1].split(',')],list(range(78)))
        self.assertEqual(re.findall(r'run_ui_shard.py[^\n]*--count (\d+)',workflow),['78'])
        self.assertEqual(re.findall(r'--deadline-seconds (\d+)',workflow),['1800'])
        self.assertIn('-maximum-test-execution-time-allowance 120',workflow);self.assertNotIn('continue-on-error',workflow)
        self.assertEqual((self.plan['deadline_seconds'],self.plan['startup_reserve_seconds'],self.plan['complete_method_limit_seconds']),(1800,300,900))

    def test_old_profile_still_receives_every_current_source_floor(self):
        actual=self.run_profile(self.prior)
        self.assertAlmostEqual(sum(actual.values()),104237.381,places=8)
        self.assertEqual(self.prior,json.loads(historical_player_source(PROFILE).read_text()))
        self.assertEqual(actual,self.run_profile(self.profile))

    def test_erased_profile_markers_and_estimates_cannot_erase_source_floors(self):
        value=deepcopy(self.profile);value['planning_budget'].pop(PLAN)
        for key in self.new:value['estimated_method_seconds'].pop(key)
        value['estimate_provenance']['methods']=[r for r in value['estimate_provenance']['methods'] if r['method'] not in self.new]
        self.assertEqual(value,self.prior);self.assertAlmostEqual(sum(self.run_profile(value).values()),104237.381,places=8)
        empty={'version':1,'unobserved_method_seconds':1,'method_seconds':{}}
        actual=self.run_profile(empty)
        for name in {k.split('.')[0] for k in self.new}:self.assertEqual(actual[name],sum(r['seconds'] for k,r in self.new.items() if k.startswith(name+'.')))

    def test_lower_future_observations_do_not_shadow_floors_or_mutate_input(self):
        for seconds in (1,60):
            value=deepcopy(self.profile)
            for key in self.new:value['method_seconds'][key]=seconds
            actual=self.run_profile(value);self.assertAlmostEqual(sum(actual.values()),104237.381,places=8)
            self.assertTrue(all(value['method_seconds'][k]==seconds for k in self.new))
        value=deepcopy(self.profile);key=next(iter(self.new));value['method_seconds'][key]=900
        actual=self.run_profile(value);self.assertGreater(actual[key.split('.')[0]],self.run_profile(self.profile)[key.split('.')[0]])
        self.assertEqual(value['method_seconds'][key],900)

    def test_claimed_current_plan_rejects_partial_or_rewritten_evidence(self):
        for mutation in ('plan','estimate','cost','inventory','hash','count','classes','methods','derivation','reserve','deadline','limit','record','record_cost','record_measured','record_derive','record_source','record_file','record_helper'):
            value=deepcopy(self.profile);key=next(iter(self.new));plan=value['planning_budget'][PLAN];row=next(r for r in value['estimate_provenance']['methods'] if r['method']==key)
            if mutation=='plan':value['planning_budget'].pop(PLAN)
            elif mutation=='estimate':value['estimated_method_seconds'].pop(key)
            elif mutation=='cost':plan['whole_method_estimates'][key]=1
            elif mutation=='inventory':plan['current_inventory'].append(plan['current_inventory'][0])
            elif mutation=='hash':plan['current_inventory_sha256']='0'*64
            elif mutation=='count':plan['method_count']=718
            elif mutation=='classes':plan['class_count']=153
            elif mutation=='methods':plan['new_methods'].pop()
            elif mutation=='derivation':plan['complete_method_derivations'][0]['derivation']['app_launch_count']=0
            elif mutation=='reserve':plan['startup_reserve_seconds']=0
            elif mutation=='deadline':plan['deadline_seconds']=9999
            elif mutation=='limit':plan['complete_method_limit_seconds']=9999
            elif mutation=='record':value['estimate_provenance']['methods'].remove(row)
            elif mutation=='record_cost':row['seconds']=1
            elif mutation=='record_measured':row['measured']=True
            elif mutation=='record_derive':row['derivation']['app_launch_count']=0
            elif mutation=='record_source':row['source']='unknown'
            elif mutation=='record_file':row['test_file_sha256']='0'*64
            else:row['shared_helper_source_sha256']={}
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):self.run_profile(value)

    def test_changed_new_file_or_common_helper_cannot_be_rebound_by_profile(self):
        files={Path(r['test_path']).name for r in self.new.values()}|{Path(p).name for r in self.new.values() for p in r['shared_helper_source_sha256']}
        for name in sorted(files):
            with tempfile.TemporaryDirectory() as directory:
                ui=Path(directory)/'ui';shutil.copytree(UI,ui);p=ui/name;p.write_text(p.read_text()+'\n// changed source\n')
                value=deepcopy(self.profile)
                for row in value['estimate_provenance']['methods']:
                    if row['method'] not in self.new:continue
                    if Path(row['test_path']).name==name:row['test_file_sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
                    for helper in row['shared_helper_source_sha256']:
                        if Path(helper).name==name:row['shared_helper_source_sha256'][helper]=hashlib.sha256(p.read_bytes()).hexdigest()
                with self.subTest(file=name),self.assertRaises(ValueError):self.run_profile(value,ui)

    def test_each_missing_new_class_fails_with_old_profile(self):
        for name in sorted({Path(row['test_path']).name for row in self.new.values()}):
            with tempfile.TemporaryDirectory() as directory:
                ui=Path(directory)/'ui';shutil.copytree(UI,ui);(ui/name).unlink()
                with self.subTest(file=name),self.assertRaises(ValueError):self.run_profile(self.prior,ui)

    def test_renamed_current_sources_cannot_disguise_the_additive_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            ui=Path(directory)/'ui';shutil.copytree(UI,ui)
            for path in list(ui.glob('PlayRouteMap*.swift'))+list(ui.glob('PlayBranchHistory*.swift')):
                text=path.read_text().replace('PlayRouteMap','RenamedMap').replace('PlayBranchHistory','RenamedHistory').replace('playRoute.','renamed.').replace('playRouteCamera.','renamedCamera.').replace('branchHistory.','renamedHistory.').replace('--branch-history-scenario','--renamed-scenario')
                target=path.with_name(path.name.replace('PlayRouteMap','RenamedMap').replace('PlayBranchHistory','RenamedHistory'));path.unlink();target.write_text(text)
            with self.assertRaises(ValueError):self.run_profile({'version':1,'unobserved_method_seconds':1,'method_seconds':{}},ui)

    def test_missing_or_corrupt_trusted_contract_fails_closed(self):
        for mode in ('missing','cost','helper'):
            with tempfile.TemporaryDirectory() as directory:
                file=Path(directory)/'contract.json'
                if mode!='missing':
                    value=deepcopy(self.contract);row=next(iter(value['required_floors'].values()))
                    if mode=='cost':row['seconds']=1
                    else:row['shared_helper_source_sha256']={}
                    file.write_text(json.dumps(value))
                with patch.object(shard,'PLAYER_MAP_HISTORY_CONTRACT_PATH',file):
                    for profile in (self.profile,self.prior):
                        with self.subTest(mode=mode),self.assertRaises(ValueError):self.run_profile(profile)

    def test_exact_73_source_and_profile_replay_original_totals(self):
        with tempfile.TemporaryDirectory() as directory:
            ui=materialize_pre_player_ui(directory);actual=self.run_profile(self.prior,ui)
            self.assertEqual((sum(shard.discover(ui).values()),len(actual)),(718,153));self.assertAlmostEqual(sum(actual.values()),98087.381,places=8)
            with self.assertRaises(ValueError):self.run_profile(self.profile,ui)
        frozen=frozen_story_context()
        try:
            self.assertEqual((frozen.runner.DEFAULT_SHARD_COUNT,frozen.gates.SHARD_COUNT),(73,73))
            historical=frozen.runner.measured_weights(frozen.root/'Tests/AppUITests',frozen.root/'tools/ui_duration_weights.json')
            self.assertEqual(historical,actual)
        finally:frozen.lifetime.cleanup()

    def test_historical_projection_requires_exact_bytes_and_no_contamination(self):
        with tempfile.TemporaryDirectory() as directory:
            ui=materialize_pre_player_ui(directory);rows=source_index()['baseline_ui_sources']
            self.assertEqual({p.name for p in ui.glob('*.swift')},{Path(r['path']).name for r in rows})
            p=ui/Path(rows[0]['path']).name;p.write_text(p.read_text()+'\n// tampered\n')
            with self.assertRaises(ValueError):self.run_profile(self.prior,ui)
            (ui/'PlayRouteMapForeign.swift').write_text('// foreign\n')
            with self.assertRaises(AssertionError):materialize_pre_player_ui(ui)

    def test_inverse_rejects_old_or_new_profile_changes_and_omissions(self):
        self.assertEqual(canonical(self.profile),CURRENT_PROFILE_SHA256)
        for kind in ('new_cost','old_cost','plan','new_record','old_record','old_observation'):
            value=deepcopy(self.profile)
            if kind=='new_cost':value['estimated_method_seconds'][next(iter(self.new))]=1
            elif kind=='old_cost':value['method_seconds'][next(iter(value['method_seconds']))]=1
            elif kind=='plan':value['planning_budget'].pop(PLAN)
            elif kind=='new_record':value['estimate_provenance']['methods'].pop()
            elif kind=='old_record':value['estimate_provenance']['methods'][0]['seconds']=1
            else:value['run117_method_observations'].pop()
            with self.subTest(kind=kind),self.assertRaises(AssertionError):before_player_map_history(value)
        self.assertEqual(before_player_map_history(self.prior),self.prior)

    def test_unrelated_custom_profiles_keep_original_measured_semantics(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);(p/'Example.swift').write_text('final class Example: XCTestCase {func testOne(){}}')
            value={'version':1,'unobserved_method_seconds':60,'method_seconds':{'Example.testOne':17},'estimated_method_seconds':{'Example.testOne':700}}
            self.assertEqual(self.run_profile(value,p),{'Example':17})

    def test_only_live_absence_does_not_masquerade_as_historical_projection(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);ui=materialize_pre_player_ui(root/'Tests/AppUITests')
            with patch.object(shard,'ROOT',root),self.assertRaises(ValueError):self.run_profile(self.prior,ui)

    def test_delivered_inventory_and_budget_are_recomputed_from_all_source(self):
        doc=json.loads((ROOT/'docs/player-map-history-integration-budget.json').read_text());inventory=json.loads((ROOT/'docs/ui-shard-inventory.json').read_text())
        self.assertEqual(doc['plan'],self.plan);costs=self.costs();groups=shard.partition(costs,78);counts=shard.discover(UI)
        self.assertEqual(doc['class_costs'],{k:str(v) for k,v in sorted(costs.items())});self.assertEqual(len(doc['shards']),78)
        for row,group in zip(doc['shards'],groups):
            self.assertEqual(row['classes'],group);self.assertEqual(row['methods'],sum(counts[c] for c in group));self.assertEqual(Decimal(row['projected_seconds_with_startup']),sum(costs[c] for c in group)+300)
        self.assertEqual((inventory['total_tests'],inventory['total_classes'],inventory['shard_count']),(736,159,78));self.assertEqual(inventory['classes'],counts);self.assertEqual(inventory['shards'],groups)

if __name__=='__main__':unittest.main()
