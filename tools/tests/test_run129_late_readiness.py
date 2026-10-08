"""Bound current bytes, retained history, and full-method late readiness cost."""
from copy import deepcopy
from decimal import Decimal
import hashlib,json,re,shutil,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from tools import run129_late_readiness as late,run_ui_shard as shard
from tools.run130_prepared_readiness import frozen_late_context
_FROZEN_5A7FD = frozen_late_context()
ROOT=_FROZEN_5A7FD.root
UI=ROOT/'Tests/AppUITests'
class Run129LateReadinessTests(unittest.TestCase):
    def setUp(self):
        self.profile=json.loads((ROOT/'tools/ui_duration_weights.json').read_text())
        self.contract=late.contract()
    def run_profile(self,profile,ui=UI):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'profile.json';p.write_text(json.dumps(profile));return shard.measured_weights(ui,p)
    def test_only_two_launch_reveals_raise_existing_complete_allowance(self):
        rows=self.contract['required_floors'];self.assertEqual(sorted(r['seconds'] for r in rows.values()),[720,770,900])
        self.assertEqual(sum(r['seconds']-r['historical_seconds'] for r in rows.values()),50)
        row=next(r for k,r in rows.items() if 'Cancellation' in k)
        exact=row['historical_seconds']+row['new_reveal_calls']*(row['maximum_new_swipes']+1)*row['per_iteration_seconds_assumption']
        self.assertEqual(exact,764);self.assertEqual(((exact+9)//10)*10,row['seconds'])
        self.assertFalse(row['measured'])
    def test_whole_inventory_and_old_costs_are_preserved_once(self):
        context=late.frozen_repair_context();self.addCleanup(context.lifetime.cleanup)
        old=shard.measured_weights(context.root/'Tests/AppUITests',context.root/'tools/ui_duration_weights.json')
        new=self.run_profile(self.profile)
        self.assertEqual(shard.discover(UI),shard.discover(context.root/'Tests/AppUITests'))
        self.assertEqual((sum(shard.discover(UI).values()),len(new)),(736,161))
        for name,value in old.items():self.assertEqual(new[name],value+(50 if name=='ProjectStoryImageCancellationFlowTests' else 0))
    def test_previous_profile_and_source_restore_exactly(self):
        previous=late.previous_profile(self.profile)
        self.assertEqual(late.canonical(previous),self.contract['previous_profile_canonical_sha256'])
        for key,value in previous.items():
            if key!='planning_budget':self.assertEqual(self.profile[key],value)
        for key,value in previous['planning_budget'].items():self.assertEqual(self.profile['planning_budget'][key],value)
        for row in self.contract['required_floors'].values():
            before=late.previous_source(ROOT/row['path']);self.assertEqual(late.digest(before.read_bytes()),row['before_file_sha256'])
    def test_every_current_source_file_and_helper_is_bound(self):
        self.assertEqual(late.validate_current(UI),self.contract)
        for name,expected in self.contract['shared_helper_files'].items():self.assertEqual(late.digest((UI/name).read_bytes()),expected)
    def test_unchanged_review_methods_and_only_reordered_helpers(self):
        for row in self.contract['required_floors'].values():
            if 'Cancellation' in row['path']:continue
            after=(ROOT/row['path']).read_text();before=(late.FIXTURES/Path(row['path']).name).read_text()
            self.assertEqual(re.findall(late.PATTERN,after),re.findall(late.PATTERN,before))
            restored=after.replace('let target = app.buttons[id]\n        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70), app.debugDescription) }\n        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)','let target = app.buttons[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)\n        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70), app.debugDescription) }')
            restored=restored.replace('let target = app.staticTexts[id]\n        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70, requiresHittable: false), app.debugDescription)\n        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)','let target = app.staticTexts[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)\n        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70, requiresHittable: false), app.debugDescription)')
            self.assertEqual(restored,before)
    def test_cancellation_original_full_journey_and_maximum_text_are_preserved(self):
        name='ProjectStoryImageCancellationFlowTests.swift';after=(UI/name).read_text();before=(late.FIXTURES/name).read_text()
        insertion='XCTAssertTrue(revealFixtureElement(app.textFields["projectEdit.name"], in: app, maximumSwipes: 10)); '
        self.assertEqual(after.count(insertion),2)
        self.assertEqual(after.replace(insertion,'').replace('estimate: 770 seconds.','estimate: 720 seconds.'),before)
        self.assertEqual(after.count('app.launch()'),2)
        self.assertEqual(after.count('assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")'),2)
        self.assertIn('UICTContentSizeCategoryAccessibilityXXXL',after)
    def test_forecasts_and_current_inventory_recompute(self):
        doc=json.loads((ROOT/'docs/run129-late-readiness-budget.json').read_text())
        live=self.run_profile(self.profile)
        cost={k:Decimal(v) for k,v in doc['classes'].items()}
        self.assertEqual(set(live),set(cost))
        for key,value in cost.items():self.assertAlmostEqual(live[key],float(value),places=8)
        self.assertEqual(sum(cost.values()),Decimal('104427.381'))
        for count in range(1,162):
            self.assertEqual(str(max(sum(cost[k] for k in g)+300 for g in shard.partition(cost,count))),doc['forecasts'][str(count)])
        self.assertEqual(doc['forecasts']['78'],'1770');self.assertEqual(doc['first_30_second_headroom_shards'],78)
        inv=json.loads((ROOT/'docs/ui-shard-inventory.json').read_text());groups=shard.partition(cost,78)
        self.assertEqual(inv['shards'],groups);self.assertEqual(inv['classes'],shard.discover(UI))
        self.assertEqual(sum(inv['shard_test_counts']),736)
    def test_omitted_lowered_old_timing_or_missing_plan_fails(self):
        for mutation in ['missing','lower','old','extra']:
            p=deepcopy(self.profile)
            if mutation=='missing':p['planning_budget'].pop(late.PLAN)
            elif mutation=='lower':p['planning_budget'][late.PLAN]['changes'][next(iter(p['planning_budget'][late.PLAN]['changes']))]=1
            elif mutation=='old':p['method_seconds'][next(iter(p['method_seconds']))]=1
            else:p['planning_budget'][late.PLAN]['changes']['Uncosted.testExtra']=60
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):self.run_profile(p)
    def test_removed_added_or_duplicated_complete_method_fails(self):
        for mode in ['delete','add','duplicate','rename']:
            with tempfile.TemporaryDirectory() as d:
                ui=Path(d)/'AppUITests';shutil.copytree(UI,ui);p=ui/'ApprovedTopicReviewRequestFlowTests.swift';s=p.read_text()
                if mode=='delete':p.unlink()
                elif mode=='add':p.write_text(s+'\n    func testUncosted() {}\n')
                elif mode=='duplicate':p.write_text(s+s)
                else:p.rename(ui/'Renamed.swift')
                with self.subTest(mode=mode),self.assertRaises(ValueError):self.run_profile(self.profile,ui)
    def test_changed_helper_wait_maximum_text_or_environment_assertion_fails(self):
        changes=[('ApprovedTopicReviewRequestFlowTests.swift','maximumSwipes: 70','maximumSwipes: 71'),('ProjectStoryImageCancellationFlowTests.swift','timeout: 5','timeout: 6'),('ProjectStoryImageCancellationFlowTests.swift','UICTContentSizeCategoryAccessibilityXXXL','UICTContentSizeCategoryL'),('ProjectStoryImageCancellationFlowTests.swift','assertFixtureEnvironment','removedEnvironment'),('FailureScreenshot.swift','maximumSwipes','changedMaximum')]
        for name,before,after in changes:
            with tempfile.TemporaryDirectory() as d:
                ui=Path(d)/'AppUITests';shutil.copytree(UI,ui);p=ui/name;self.assertIn(before,p.read_text());p.write_text(p.read_text().replace(before,after,1))
                with self.subTest(name=name,before=before),self.assertRaises(ValueError):self.run_profile(self.profile,ui)
    def test_unknown_current_bytes_cannot_project_to_old_source(self):
        with tempfile.TemporaryDirectory() as d:
            ui=Path(d)/'AppUITests';ui.mkdir();p=ui/'ProjectStoryImageCancellationFlowTests.swift';p.write_bytes((UI/p.name).read_bytes()+b'\n// unreviewed\n')
            with self.assertRaises(ValueError):late.previous_source(p)
    def test_contract_tampering_cannot_lower_or_raise_the_method_cap(self):
        for seconds in [1,901]:
            c=deepcopy(self.contract);c['required_floors'][next(iter(c['required_floors']))]['seconds']=seconds
            with tempfile.TemporaryDirectory() as d:
                root=Path(d);(root/'tools').mkdir();(root/'tools/run129_late_readiness_contract.json').write_text(json.dumps(c))
                with patch.object(late,'ROOT',root),self.assertRaises(ValueError):late.contract()
    def test_six_930_proposals_remain_unapplied(self):
        old_index=json.loads((ROOT/'tools/tests/fixtures/run129_repairs/source-index.json').read_text())
        for name in ['ApprovedReleaseRecoveryFlowTests','ApprovedTopicReviewCurrentChineseFlowTests','ApprovedTopicReviewUnknownFlowTests','ApprovedTopicSelectedCoverChineseFlowTests','ProjectStoryAudioRecoveryFlowTests','OwnedTopicCoverRecoveryFlowTests']:
            rel='Tests/AppUITests/'+name+'.swift'
            self.assertEqual(late.digest((ROOT/rel).read_bytes()),old_index['current_ui_sources'][rel]['sha256'])
