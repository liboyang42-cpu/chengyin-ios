"""Focused result/provenance negative controls for the current-only runner."""
import copy
import unittest
from tools import current_native as native
from tools import current_ci as control


class CurrentNativeControls(unittest.TestCase):
    def fixture(self):
        groups={'core':['QuestifyCoreTests/A/testOne'],'app-unit':['QuestifyAppUnitTests/B/testTwo'],'ui':['QuestifyUITests/C/testThree']}
        plan={'identity':{'sha':'a'*40,'tree':'b'*40,'run_id':'1','attempt':'1'},'groups':groups,'ui_shards':[{'methods':groups['ui'],'seconds':60}],'scope':'current-related-and-smoke','complete_native_ledger_count':11, 'device_only_not_run':control.device_only_not_run({'native_methods':control.device_only_ledger(),'device_only_methods':control.device_only_ledger()}), 'execution_platforms':['macos-host','ios-simulator']}
        receipts={}
        for role,methods in groups.items():
            key='ui-0' if role=='ui' else role
            receipts[key]={'identity':plan['identity'],'plan_sha256':control.digest(control.encode(plan)),'toolchain':{key:'observed' for key in ['xcode','developer','swift','sdk_version','sdk_path','architecture']},'worker_seconds':1,'status':'PASS','role':role,'index':0 if role=='ui' else None,'expected':methods,'actual':[{'method':m,'status':'Passed'} for m in methods]}
        return plan,receipts,{**{name:{'result':'success'} for name in ('controls','secrets','native','ui')},'platforms':{'result':'skipped'}}

    def test_exact_current_selection_union_passes(self):
        plan,receipts,needs=self.fixture();result=native.aggregate_current(plan,receipts,needs)
        self.assertEqual(result['executed_count'],3);self.assertEqual(result['full_ledger_count'],11)
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


class CoreSerialEvidenceControls(unittest.TestCase):
    def transcript(self, methods=None):
        methods=methods or ['QuestifyCoreTests/A/testOne','QuestifyCoreTests/B/testTwo']
        stamp='2026-10-12 14:00:00.001'
        lines=[f"Test Suite 'Selected tests' started at {stamp}.",f"Test Suite 'QuestifyCorePackageTests.xctest' started at {stamp}."]
        by_class={}
        for method in methods:
            target,cls,name=method.split('/');by_class.setdefault(cls,[]).append((target,name))
        def summary(n):return f'\t Executed {n} tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds'
        for cls,rows in by_class.items():
            lines.append(f"Test Suite '{cls}' started at {stamp}.")
            for target,name in rows:
                lines.extend([f"Test Case '-[{target}.{cls} {name}]' started.",f"Test Case '-[{target}.{cls} {name}]' passed (0.001 seconds)."])
            lines.extend([f"Test Suite '{cls}' passed at {stamp}.",summary(len(rows))])
        lines.extend([f"Test Suite 'QuestifyCorePackageTests.xctest' passed at {stamp}.",summary(len(methods)),f"Test Suite 'Selected tests' passed at {stamp}.",summary(len(methods))])
        return ('\n'.join(lines)+'\n').encode()

    def test_serial_command_keeps_exact_filter_skip_build_and_original_budget(self):
        import re
        g={'methods':['QuestifyCoreTests/A/testOne','QuestifyCoreTests/B/testTwo']}
        argv=native.core_serial_command(g);pattern=argv[argv.index('--filter')+1]
        self.assertEqual(argv.count('--skip-build'),1);self.assertIn('--no-parallel',argv);self.assertIn('--disable-swift-testing',argv)
        self.assertNotIn('--parallel',argv);self.assertNotIn('--num-workers',argv);self.assertNotIn('--xunit-output',argv)
        self.assertEqual(native.BUDGET['core-test'],180)
        for m in g['methods']:self.assertRegex(m.replace('/','.',1),pattern)
        self.assertIsNone(re.fullmatch(pattern,'QuestifyCoreTests.A/testOneExtra'))

    def test_actual_native_events_and_both_summaries_match_complete_selection(self):
        methods=['QuestifyCoreTests/A/testOne','QuestifyCoreTests/B/testTwo'];rows,summary=native.validate_core_serial_evidence(self.transcript(),methods,0)
        self.assertEqual([r['method'] for r in rows],methods)
        self.assertEqual(summary['suites']['Selected tests']['tests'],2)
        self.assertEqual(summary['suites']['QuestifyCorePackageTests.xctest']['tests'],2)

    def test_missing_duplicate_extra_skipped_unfinished_or_reordered_methods_fail(self):
        methods=['QuestifyCoreTests/A/testOne','QuestifyCoreTests/B/testTwo'];raw=self.transcript()
        first=b"Test Case '-[QuestifyCoreTests.A testOne]' started.\n";last=b"Test Case '-[QuestifyCoreTests.A testOne]' passed (0.001 seconds).\n"
        changes=[raw.replace(first,b''),raw.replace(last,b''),raw.replace(first,first+first),raw.replace(last,last+last),raw.replace(first+last,last+first),raw.replace(b'testTwo',b'testForeign'),raw.replace(b'passed (',b'skipped (',1),raw.replace(b'passed (',b'failed (',1),raw[:-20]]
        for value in changes:
            with self.subTest(value=value[-80:]),self.assertRaises(ValueError):native.validate_core_serial_evidence(value,methods,0)
        with self.assertRaises(ValueError):native.validate_core_serial_evidence(raw,methods+['QuestifyCoreTests/C/testMissing'],0)

    def test_forged_pass_counts_wrong_bundle_or_truncated_summaries_fail(self):
        methods=['QuestifyCoreTests/A/testOne','QuestifyCoreTests/B/testTwo'];raw=self.transcript()
        for value in [raw.replace(b'Executed 2 tests',b'Executed 1 tests'),raw.replace(b'0 failures',b'1 failures'),raw.replace(b'0 unexpected',b'1 unexpected'),raw.replace(b'QuestifyCorePackageTests.xctest',b'OtherTests.xctest'),raw[:raw.rfind(b'Test Suite')],raw.replace(b'with 0 failures',b'with 1 test skipped and 0 failures'),raw+raw]:
            with self.subTest(value=value[-100:]),self.assertRaises(ValueError):native.validate_core_serial_evidence(value,methods,0)
        with self.assertRaises(ValueError):native.validate_core_serial_evidence(b'',methods,0)

    def test_nonzero_timeout_and_boolean_returncodes_never_pass(self):
        for code in [1,124,-9,False,True]:
            with self.assertRaisesRegex(ValueError,'returncode='):native.validate_core_serial_evidence(self.transcript(),['QuestifyCoreTests/A/testOne'],code)

    def serial_artifact(self, directory):
        plan,receipts,_=CurrentNativeControls().fixture();receipt=receipts['core'];g=native.group(plan,'core');raw=self.transcript(g['methods'])
        rows,summary=native.validate_core_serial_evidence(raw,g['methods'],0)
        receipt.update(core_evidence_format='darwin-serial-v1',host_target={'sdk_path':'/sdk','sdk_version':'1','triple':'arm64-apple-macosx'},actual=rows)
        (directory/'core-test.stdout').write_bytes(raw);native.write_json(directory/'core-native-summary.json',summary)
        commands=[{'stem':'core-test','argv':native.core_serial_command(g)+['--sdk','/sdk','--triple','arm64-apple-macosx'],'returncode':0,'stdout_sha256':control.digest(raw)}];native.write_json(directory/'commands.json',commands)
        receipt['commands_sha256']=native.digest(directory/'commands.json');receipt['raw_sha256']={p:native.digest(directory/p) for p in ['core-test.stdout','core-native-summary.json']};native.write_json(directory/'receipt.json',receipt)
        return plan,receipt,commands

    def test_aggregate_reparses_raw_serial_events_and_rejects_self_consistent_tampering(self):
        import tempfile
        from pathlib import Path
        for mutation in ['none','count','command','rows']:
            with tempfile.TemporaryDirectory() as tmp:
                d=Path(tmp);plan,receipt,commands=self.serial_artifact(d)
                if mutation=='none':self.assertEqual(native.reparse_actual_result(d,plan)['actual'],receipt['actual']);continue
                if mutation=='count':
                    doc=native.read_json(d/'core-native-summary.json');doc['suites']['Selected tests']['tests']=99;native.write_json(d/'core-native-summary.json',doc);receipt['raw_sha256']['core-native-summary.json']=native.digest(d/'core-native-summary.json')
                elif mutation=='command':
                    commands[0]['argv'][commands[0]['argv'].index('--filter')+1]='.*';native.write_json(d/'commands.json',commands);receipt['commands_sha256']=native.digest(d/'commands.json')
                else:receipt['actual']=[]
                native.write_json(d/'receipt.json',receipt)
                with self.subTest(mutation=mutation),self.assertRaises(ValueError):native.reparse_actual_result(d,plan)

    def test_execute_builds_once_uses_one_bounded_serial_process_and_preserves_timeout(self):
        import tempfile,os,time,json,sys
        from pathlib import Path
        from unittest.mock import patch
        for code in [0,124]:
            with tempfile.TemporaryDirectory() as tmp:
                base=Path(tmp);root=base/'repo';root.mkdir();start=base/'start';start.write_text(str(time.monotonic()));out=base/'result'
                plan,_,_=CurrentNativeControls().fixture();calls=[];g=native.group(plan,'core')
                def execute(argv,cwd,timeout,capture=False,env=None):
                    calls.append((argv,timeout))
                    if argv[:2]==['swift','-print-target-info']:return 0,json.dumps({'target':{'triple':'arm64-apple-macosx'}}).encode()
                    if argv[:2]==['swift','test']:return code,self.transcript(g['methods']) if code==0 else b"Test Case '-[QuestifyCoreTests.A testOne]' started.\n"
                    return 0,b'/actual-sdk-or-success\n'
                with patch.dict(os.environ,{'RUNNER_TEMP':str(base)}),patch.object(native,'execute',side_effect=execute),patch.object(native,'toolchain',return_value={k:'observed' for k in ['xcode','developer','swift','sdk_version','sdk_path','architecture']}),patch.object(native,'core_bundle_ledger',return_value=[['bundle','file','hash']]),patch.object(control,'source_identity',return_value=plan['identity']):
                    if code==0:native.execute_current(root,plan,'core',out,start)
                    else:
                        with self.assertRaisesRegex(ValueError,'returncode=124'):native.execute_current(root,plan,'core',out,start)
                self.assertEqual(sum(argv[:2]==['swift','build'] for argv,_ in calls),1)
                self.assertEqual(sum(argv[:2]==['swift','test'] for argv,_ in calls),1)
                self.assertEqual(next(seconds for argv,seconds in calls if argv[:2]==['swift','test']),180)
                receipt=native.read_json(out/'receipt.json');self.assertEqual(receipt['status'],'PASS' if code==0 else 'FAIL')
                self.assertFalse((out/'core.xml').exists());self.assertTrue((out/'core-test.stdout').exists())
                if code==0:self.assertEqual(native.reparse_actual_result(out,plan)['actual'],receipt['actual'])
                else:self.assertIn('returncode=124',receipt['error'])


class XCTestDiagnosticControls(unittest.TestCase):
    def document(self):
        warning={'nodeType':'Runtime Warning','name':"Adding 'UIKitToolbar' as a subview of UIHostingController.view is not supported and may result in a broken view hierarchy."}
        case={'nodeType':'Test Case','name':'testOne()','nodeIdentifier':'Case/testOne()','nodeIdentifierURL':'test://com.apple.xcode/Questify/QuestifyUITests/Case/testOne','result':'Passed','children':[warning]}
        return {'testNodes':[{'nodeType':'UI test bundle','name':'QuestifyUITests','children':[case]}]},case

    def test_plain_runtime_warning_preserves_exact_passed_method(self):
        data,case=self.document();expected=[{'method':'QuestifyUITests/Case/testOne','status':'Passed'}]
        self.assertEqual(native.parse_xcresult(data,'QuestifyUITests'),expected)
        case['children']=[];self.assertEqual(native.parse_xcresult(data,'QuestifyUITests'),expected)
        del case['children'];self.assertEqual(native.parse_xcresult(data,'QuestifyUITests'),expected)

    def test_warning_cannot_hide_nested_case_failure_skip_repetition_or_identity(self):
        data,case=self.document();warning=copy.deepcopy(case['children'][0])
        bad=[None,{},'warning',[None],[{}],[dict(warning,name='')],[dict(warning,name=1)],
             [dict(warning,nodeType='Test Case')],[dict(warning,nodeType='Failure Message')],
             [dict(warning,nodeType='Skipped')],[dict(warning,nodeType='Repetition')],
             [dict(warning,nodeType='Activity')],[dict(warning,children=[])],
             [dict(warning,result='Failed')],[dict(warning,nodeIdentifier='Other/testTwo')],
             [dict(warning,nodeIdentifierURL='test://com.apple.xcode/Other')]]
        for children in bad:
            with self.subTest(children=children):
                case['children']=children
                with self.assertRaises(ValueError):native.parse_xcresult(data,'QuestifyUITests')

    def test_warning_never_converts_failed_skipped_foreign_or_duplicate_execution_to_pass(self):
        expected=['QuestifyUITests/Case/testOne']
        for status in ['Failed','Skipped','Expected Failure']:
            data,case=self.document();case['result']=status;rows=native.parse_xcresult(data,'QuestifyUITests')
            with self.assertRaises(ValueError):native.validate_outcomes(rows,expected,0)
        data,case=self.document();rows=native.parse_xcresult(data,'QuestifyUITests')
        for code in [65,124,-9]:
            with self.assertRaises(ValueError):native.validate_outcomes(rows,expected,code)
        data['testNodes'][0]['children'].append(copy.deepcopy(case));rows=native.parse_xcresult(data,'QuestifyUITests')
        with self.assertRaises(ValueError):native.validate_outcomes(rows,expected,0)
        data,case=self.document();case['nodeIdentifierURL']='test://com.apple.xcode/Questify/QuestifyAppUnitTests/Case/testOne'
        with self.assertRaises(ValueError):native.parse_xcresult(data,'QuestifyUITests')


class DeviceOnlyAggregationControls(unittest.TestCase):
    fixture = CurrentNativeControls.fixture
    def test_device_methods_are_explicit_not_run_and_not_counted_as_passed(self):
        plan,receipts,needs=self.fixture()
        plan['device_only_not_run']=control.device_only_not_run({'native_methods':control.device_only_ledger(),'device_only_methods':control.device_only_ledger()})
        for receipt in receipts.values():receipt['plan_sha256']=control.digest(control.encode(plan))
        result=native.aggregate_current(plan,receipts,needs)
        self.assertEqual(result['executed_count'],3);self.assertEqual(result['selected_count'],3)
        self.assertEqual(result['device_only_executed_count'],0);self.assertEqual(len(result['device_only_not_run']),8)
        for kind in ('false-pass','partial','foreign','executed','entire-ledger-omitted','empty-ledger','platforms-omitted'):
            changed=copy.deepcopy(plan);copies=copy.deepcopy(receipts)
            if kind=='false-pass':changed['device_only_not_run'][0]['status']='Passed'
            elif kind=='partial':changed['device_only_not_run'].pop()
            elif kind=='foreign':changed['device_only_not_run'][0]['method']='QuestifyAppUnitTests/A/testOther'
            elif kind=='entire-ledger-omitted':del changed['device_only_not_run']
            elif kind=='empty-ledger':changed['device_only_not_run']=[]
            elif kind=='platforms-omitted':del changed['execution_platforms']
            else:
                method=changed['device_only_not_run'][0]['method'];changed['groups']['app-unit']=[method]
                copies['app-unit']['expected']=[method];copies['app-unit']['actual']=[{'method':method,'status':'Passed'}]
            for receipt in copies.values():receipt['plan_sha256']=control.digest(control.encode(changed))
            with self.subTest(kind=kind),self.assertRaises(ValueError):native.aggregate_current(changed,copies,needs)
