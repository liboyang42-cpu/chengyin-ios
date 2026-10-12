"""Focused result/provenance negative controls for the current-only runner."""
import copy
import unittest
from tools import current_native as native
from tools import current_ci as control


class CurrentNativeControls(unittest.TestCase):
    def fixture(self):
        groups={'core':['QuestifyCoreTests/A/testOne'],'app-unit':['QuestifyAppUnitTests/B/testTwo'],'ui':['QuestifyUITests/C/testThree']}
        plan={'identity':{'sha':'a'*40,'tree':'b'*40,'run_id':'1','attempt':'1'},'groups':groups,'ui_shards':[{'methods':groups['ui'],'seconds':60}],'scope':'current-related-and-smoke','complete_native_ledger_count':10}
        receipts={}
        for role,methods in groups.items():
            key='ui-0' if role=='ui' else role
            receipts[key]={'identity':plan['identity'],'plan_sha256':control.digest(control.encode(plan)),'toolchain':{key:'observed' for key in ['xcode','developer','swift','sdk_version','sdk_path','architecture']},'worker_seconds':1,'status':'PASS','role':role,'index':0 if role=='ui' else None,'expected':methods,'actual':[{'method':m,'status':'Passed'} for m in methods]}
        return plan,receipts,{**{name:{'result':'success'} for name in ('controls','secrets','native','ui')},'platforms':{'result':'skipped'}}

    def test_exact_current_selection_union_passes(self):
        plan,receipts,needs=self.fixture();result=native.aggregate_current(plan,receipts,needs)
        self.assertEqual(result['executed_count'],3);self.assertEqual(result['full_ledger_count'],10)
        self.assertEqual(result['scope'],'current-related-and-smoke')

    def test_missing_duplicate_foreign_or_nonpassing_evidence_rejected(self):
        for mutation in ['missing','foreign','skipped','failed','zero','wrong-index','build']:
            plan,receipts,needs=self.fixture()
            if mutation=='missing':del receipts['ui-0']
            elif mutation=='foreign':receipts['core']['identity']=dict(plan['identity'],attempt='2')
            elif mutation=='zero':receipts['core']['actual']=[]
            elif mutation=='wrong-index':receipts['ui-0']['index']=1
            elif mutation=='build':receipts['ui-0']['status']='BUILT'
            else:receipts['core']['actual'][0]['status']=mutation.title()
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):native.aggregate_current(plan,receipts,needs)

    def test_failed_skipped_cancelled_or_missing_job_is_not_success(self):
        for outcome in ['failure','skipped','cancelled',None]:
            plan,receipts,needs=self.fixture();needs['native']['result']=outcome
            with self.assertRaises(ValueError):native.aggregate_current(plan,receipts,needs)

    def test_original_native_outcome_validator_keeps_exact_identity_requirement(self):
        method='QuestifyUITests/Case/testOne';rows=[{'method':method,'status':'Passed'}]
        native.validate_outcomes(rows,[method],0)
        for bad in [[],rows*2,[{'method':method,'status':'Skipped'}],[{'method':'QuestifyUITests/Other/testTwo','status':'Passed'}]]:
            with self.assertRaises(ValueError):native.validate_outcomes(bad,[method],0)
        with self.assertRaises(ValueError):native.validate_outcomes(rows,[method],124)

    def test_original_xctest_command_uses_only_selected_methods_without_rebuild(self):
        group={'name':'ui','target':'QuestifyUITests','methods':['QuestifyUITests/Case/testOne']}
        argv=native.xcode_test_command(group,'run.xctestrun','device','result.xcresult')
        self.assertEqual(argv[-1],'test-without-building');self.assertIn('-only-testing:QuestifyUITests/Case/testOne',argv)
        self.assertIn('900',argv);self.assertNotIn('build-for-testing',argv)

    def test_actual_raw_core_reparse_rejects_modified_transcript(self):
        import tempfile
        from pathlib import Path
        plan,receipts,_=self.fixture();receipt=receipts['core'];receipt['host_target']={'sdk_path':'/sdk','sdk_version':'1','triple':'arm64-apple-macosx'}
        transcript=b"Test Case '-[QuestifyCoreTests.A testOne]' started.\nTest Case '-[QuestifyCoreTests.A testOne]' passed (0.001 seconds).\n"
        xml=b'<testsuite tests="1" failures="0" errors="0" skipped="0"><testcase classname="QuestifyCoreTests.A" name="testOne" /></testsuite>'
        with tempfile.TemporaryDirectory() as directory:
            d=Path(directory);(d/'core.xml').write_bytes(xml);(d/'core-test.stdout').write_bytes(transcript)
            g=native.group(plan,'core');argv=native.core_command(g,'/fresh/core.xml')+['--sdk','/sdk','--triple','arm64-apple-macosx']
            native.write_json(d/'commands.json',[{'stem':'core-test','argv':argv,'returncode':0,'stdout_sha256':control.digest(transcript)}])
            receipt['commands_sha256']=native.digest(d/'commands.json');receipt['raw_sha256']={p:native.digest(d/p) for p in ['core.xml','core-test.stdout']};native.write_json(d/'receipt.json',receipt)
            self.assertEqual(native.reparse_actual_result(d,plan)['actual'],receipt['actual'])
            (d/'core-test.stdout').write_bytes(transcript.replace(b'passed',b'failed'))
            with self.assertRaises(ValueError):native.reparse_actual_result(d,plan)
