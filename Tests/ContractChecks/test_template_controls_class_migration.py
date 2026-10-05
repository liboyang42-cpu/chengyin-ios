"""Intact method/class migration evidence, not Apple execution."""
import hashlib
import json
from pathlib import Path
import re
import unittest
from tools.run_ui_shard import discover
ROOT = Path(__file__).resolve().parents[2]

class TemplateControlsClassMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mapping = json.loads((ROOT/'Tests/ContractChecks/fixtures/template_controls_method_migration.json').read_text())
    def test_every_original_complete_method_declaration_is_byte_identical(self):
        for row in self.mapping['methods']:
            case, method = row['new_id'].split('.')
            data = (ROOT/'Tests/AppUITests'/f'{case}.swift').read_bytes()
            start = data.index(('func '+method+'(').encode())
            block = data[start:start+row['declaration_bytes']]
            self.assertEqual(hashlib.sha256(block).hexdigest(), row['declaration_sha256'])
    def test_helpers_are_intact_and_both_classes_are_direct_xctest_cases(self):
        for case in ['TemplateEditorControlsFlowTests', 'TemplateHistoricalHintFlowTests']:
            data = (ROOT/'Tests/AppUITests'/f'{case}.swift').read_bytes()
            self.assertIn((f'final class {case}: XCTestCase').encode(), data)
            start = data.index(b'{',data.index(b'final class'))+1
            stop = data.index(b'    //',data.index(b'    private func assertHints'))
            helpers = data[start:stop]
            self.assertEqual(len(helpers), self.mapping['helper_block_bytes'])
            self.assertEqual(hashlib.sha256(helpers).hexdigest(), self.mapping['shared_helper_block_sha256'])
    def test_actual_discovery_contains_each_method_once_with_no_new_coverage(self):
        counts = discover(ROOT/'Tests/AppUITests')
        self.assertEqual(counts['TemplateEditorControlsFlowTests'],2)
        self.assertEqual(counts['TemplateHistoricalHintFlowTests'],1)
        ids=[]
        for case in ['TemplateEditorControlsFlowTests','TemplateHistoricalHintFlowTests']:
            text=(ROOT/'Tests/AppUITests'/f'{case}.swift').read_text()
            ids += [case+'.'+name for name in re.findall(r'\bfunc\s+(test\w+)\s*\(',text)]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertEqual(set(ids),{row['new_id'] for row in self.mapping['methods']})
        self.assertEqual(self.mapping['new_ui_method_count'],0);self.assertFalse(self.mapping['runner_changed'])
    def test_complete_method_budgets_fit_separate_classes_without_lowering_the_hint(self):
        plan=self.mapping['budget']
        self.assertEqual((plan['deadline_seconds'],plan['startup_reserve_seconds']),(1800,300))
        self.assertEqual(plan['effective_class_seconds'],{'TemplateEditorControlsFlowTests':840,'TemplateHistoricalHintFlowTests':720})
        self.assertEqual([row['seconds'] for row in self.mapping['methods']],[420,420,720])
        for seconds in plan['effective_class_seconds'].values():self.assertLessEqual(seconds+300,1800)

if __name__=='__main__':unittest.main()
