"""Current run129 wrapper/Chinese readback negative controls."""
from pathlib import Path
import unittest
from tools.tests.test_fixture_environment_contract import reviewed_run129_display_family
ROOT=Path(__file__).resolve().parents[2]
PAIRS={'ProjectSubmissionAcknowledgmentFlowTests':'ProjectSubmissionAcknowledgmentChineseFlowTests','ApprovedReleasePreparationFlowTests':'ApprovedReleasePreparationChineseFlowTests'}
class Run129DisplayFamilyTests(unittest.TestCase):
    def sources(self,name):return {key:(ROOT/'Tests/AppUITests'/(key+'.swift')).read_text() for key in [name,PAIRS[name]]}
    def test_both_exact_two_method_families_share_original_real_observation(self):
        for name in PAIRS:
            text=reviewed_run129_display_family(name,self.sources(name))
            self.assertEqual(text.count('    func test'),2)
            self.assertEqual(text.count('assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")'),1)
    def test_missing_extra_and_duplicated_wrappers_fail(self):
        for name in PAIRS:
            for kind in ['missing','extra']:
                data=self.sources(name)
                if kind=='missing':data.pop(PAIRS[name])
                else:data['Unknown']=data[name]
                with self.assertRaises(AssertionError):reviewed_run129_display_family(name,data)
    def test_omitted_added_or_renamed_method_fails(self):
        for name in PAIRS:
            for replacement in ['    func skipped','    func testNew() {}\n    func test','    func testRenamed']:
                data=self.sources(name);data[name]=data[name].replace('    func test',replacement,1)
                with self.assertRaises(AssertionError):reviewed_run129_display_family(name,data)
    def test_indirect_chinese_call_and_helper_or_wait_change_fails(self):
        for name in PAIRS:
            for before,after in [('chinese: Bool = false','chinese: Bool = true'),('timeout: 5','timeout: 6'),('let app = launch(','let flag=true; let app = launch(chinese: flag,')]:
                data=self.sources(name);self.assertIn(before,data[name]);data[name]=data[name].replace(before,after,1)
                with self.assertRaises(AssertionError):reviewed_run129_display_family(name,data)
    def test_chinese_environment_deletion_or_downgrade_fails(self):
        for name in PAIRS:
            for change in ['', 'XCTAssertTrue(true)', 'assertFixtureEnvironment(in: app, dynamicTypeSize: "large")']:
                data=self.sources(name);key=PAIRS[name];old='assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")';self.assertIn(old,data[key]);data[key]=data[key].replace(old,change)
                with self.assertRaises(AssertionError):reviewed_run129_display_family(name,data)
