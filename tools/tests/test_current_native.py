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


class UIActiveArchitectureControls(unittest.TestCase):
    def toolchain_fixture(self, architecture):
        return dict(xcode='Xcode fixture', developer='/fixture/developer', swift='Swift fixture',
                    sdk_version='fixture', sdk_path='/fixture/sdk', architecture=architecture)

    def products_fixture(self, products):
        import plistlib
        app=products/'Debug-iphonesimulator/Questify.app';app.mkdir(parents=True)
        (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleSupportedPlatforms':['iPhoneSimulator']}))
        (app/'Questify').write_bytes(b'fixture product, not a native Mach-O')
        bundle=products/'Debug-iphonesimulator/QuestifyUITests.xctest';bundle.mkdir()
        (bundle/'QuestifyUITests').write_bytes(b'fixture test bundle')
        (products/'Questify.xctestrun').write_bytes(plistlib.dumps({'QuestifyUITests':{
            'TestBundlePath':'__TESTROOT__/Debug-iphonesimulator/QuestifyUITests.xctest',
            'UITargetAppPath':'__TESTROOT__/Debug-iphonesimulator/Questify.app'}}))

    def packed_fixture(self, directory, architecture):
        products=directory/'built';self.products_fixture(products)
        artifact=directory/'artifact';artifact.mkdir()
        plan,_,_=CurrentNativeControls().fixture();toolchain=self.toolchain_fixture(architecture)
        receipt={'identity':plan['identity'],'plan_sha256':control.digest(control.encode(plan)),
                 'role':'ui-build','toolchain':toolchain}
        native.pack_ui(products,artifact,receipt)
        return plan,toolchain,artifact

    def test_ui_build_uses_destination_active_architecture_once_and_preserves_checks(self):
        import json,os,tempfile,time
        from pathlib import Path
        from unittest.mock import patch
        for architecture in ('arm64','x86_64'):
            with self.subTest(architecture=architecture),tempfile.TemporaryDirectory() as tmp:
                base=Path(tmp);root=base/'repo';root.mkdir();start=base/'start';start.write_text(str(time.monotonic()))
                output=base/'result';plan,_,_=CurrentNativeControls().fixture();calls=[]
                runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-0';udid='11111111-1111-1111-1111-111111111111'
                def execute(argv,cwd,timeout,capture=False,env=None):
                    calls.append((argv,timeout))
                    if argv[:4]==['xcrun','simctl','list','devices']:
                        return 0,json.dumps({'devices':{runtime:[{'name':'iPhone fixture','udid':udid,'isAvailable':True,'state':'Shutdown'}]}}).encode()
                    if argv[:4]==['xcrun','simctl','list','runtimes']:
                        return 0,json.dumps({'runtimes':[{'identifier':runtime,'isAvailable':True}]}).encode()
                    if argv[0]=='xcodebuild':self.products_fixture(Path(argv[argv.index('-derivedDataPath')+1])/'Build/Products')
                    return 0,b'fixture command success\n'
                actual=self.toolchain_fixture(architecture)
                with patch.dict(os.environ,{'RUNNER_TEMP':str(base)}),patch.object(native,'execute',side_effect=execute),patch.object(native,'toolchain',return_value=actual),patch.object(control,'source_identity',return_value=plan['identity']):
                    native.execute_current(root,plan,'ui-build',output,start)
                builds=[(argv,seconds) for argv,seconds in calls if argv[0]=='xcodebuild']
                self.assertEqual(len(builds),1);argv,seconds=builds[0]
                self.assertEqual(argv[-1],'build-for-testing');self.assertEqual(seconds,native.BUDGET['ui-build'])
                self.assertEqual(argv[argv.index('-destination')+1],'platform=iOS Simulator,id='+udid)
                self.assertEqual(argv.count('ONLY_ACTIVE_ARCH=YES'),1);self.assertNotIn('ONLY_ACTIVE_ARCH=NO',argv)
                self.assertFalse(any(x.startswith('ARCHS=') or x=='-arch' for x in argv))
                self.assertIn('CODE_SIGNING_ALLOWED=NO',argv)
                self.assertTrue(any('tools/check_built_profile.py' in a for a,_ in calls))
                self.assertTrue(any('tools/check_gltf_linked.py' in a for a,_ in calls))
                receipt=native.read_json(output/'receipt.json')
                self.assertEqual(receipt['status'],'BUILT');self.assertEqual(receipt['executed_methods'],[])
                self.assertEqual(receipt['build_argv'],argv);self.assertEqual(receipt['toolchain'],actual)
                products,run,restored=native.restore_ui(output,base/'worker',plan,actual)
                self.assertEqual(native.split404_ledger(products),receipt['product_ledger'])
                self.assertEqual(run.name,receipt['xctestrun']);self.assertEqual(restored,receipt)

    def test_ui_restore_rejects_different_worker_architecture_and_other_toolchain_fields(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp);plan,actual,artifact=self.packed_fixture(base,'arm64')
            for key in actual:
                changed=dict(actual);changed[key]='x86_64' if key=='architecture' else 'different'
                destination=base/('restored-'+key)
                with self.subTest(key=key),self.assertRaisesRegex(ValueError,'toolchain/SDK/architecture'):
                    native.restore_ui(artifact,destination,plan,changed)
                self.assertFalse(destination.exists())

    def test_ui_restore_rejects_archive_corruption_and_changed_file_with_updated_archive_hash(self):
        import tempfile,tarfile
        from pathlib import Path
        for mutation in ('archive','file'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as tmp:
                base=Path(tmp);plan,actual,artifact=self.packed_fixture(base,'arm64')
                archive=artifact/'products.tar.gz'
                if mutation=='archive':archive.write_bytes(archive.read_bytes()+b'changed')
                else:
                    (base/'built/Debug-iphonesimulator/Questify.app/Questify').write_bytes(b'changed product')
                    with tarfile.open(archive,'w:gz') as stream:stream.add(base/'built',arcname='Products')
                    receipt=native.read_json(artifact/'receipt.json');receipt['archive_sha256']=native.digest(archive)
                    native.write_json(artifact/'receipt.json',receipt)
                message='archive changed' if mutation=='archive' else 'file ledger differs'
                with self.assertRaisesRegex(ValueError,message):native.restore_ui(artifact,base/'worker',plan,actual)


class FailureScreenshotControls(unittest.TestCase):
    """Synthetic exporter fixtures only; these are not Apple execution results."""
    def setUp(self):
        import tempfile
        from pathlib import Path
        from unittest.mock import patch
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name); self.root = self.base/'repo'; self.root.mkdir()
        self.output = self.base/'result'; self.output.mkdir(); (self.output/'ui.xcresult').mkdir()
        self.method = 'QuestifyUITests/Fixture/testFailure'
        self.url = 'test://com.apple.xcode/Questify/'+self.method
        (self.root/'fixture.swift').write_text('offline synthetic source')
        common = patch.object(native, 'FAILURE_SCREENSHOT_COMMON', {})
        methods = patch.object(native, 'FAILURE_SCREENSHOT_METHODS', {self.method:{'fixture.swift':native.digest(self.root/'fixture.swift')}})
        common.start(); methods.start(); self.addCleanup(common.stop); self.addCleanup(methods.stop)
        self.plan, receipts, _ = CurrentNativeControls().fixture()
        self.plan['groups']['ui'] = [self.method]; self.plan['ui_shards'][0]['methods'] = [self.method]
        self.receipt = receipts['ui-0']; self.receipt.update(status='FAIL', expected=[self.method], actual=[], plan_sha256=control.digest(control.encode(self.plan)))
        self.receipt['toolchain']['developer']='/Applications/Xcode.app/Contents/Developer'
        native.write_json(self.output/'receipt.json',self.receipt)
        self.nodes={'testNodes':[{'nodeType':'Test Case','nodeIdentifier':self.method,'result':'Failed'}]}
        self.summary={'testFailures':[{'testIdentifierURL':self.url,'testIdentifierString':'Fixture/testFailure()'}]}
        native.write_json(self.output/'tests.json',self.nodes); native.write_json(self.output/'summary.json',self.summary)
        identity=patch.object(control,'source_identity',return_value=self.plan['identity'])
        identity.start(); self.addCleanup(identity.stop)
        self.calls=[]
        self.bind_commands()

    def bind_commands(self):
        result=self.output/'ui.xcresult'
        self.receipt['simulator']={'udid':'11111111-1111-1111-1111-111111111111'}
        commands=[{'stem':'native-test','argv':native.xcode_test_command(native.group(self.plan,'ui',0),'fixture.xctestrun',self.receipt['simulator']['udid'],result),'returncode':65}]
        commands += [{'stem':k,'argv':['xcrun','xcresulttool','get','test-results',k,'--path',str(result),'--compact'],'returncode':0,'stdout_sha256':native.digest(self.output/(k+'.json'))} for k in ('summary','tests')]
        native.write_json(self.output/'commands.json',commands);self.receipt['commands_sha256']=native.digest(self.output/'commands.json')
        native.write_json(self.output/'receipt.json',self.receipt)

    @staticmethod
    def png(pixel=0):
        import struct,zlib
        def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
        return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes([0,pixel,0,0])))+chunk(b'IEND',b'')

    def stage(self,folder,data=None,name=None,filename='image.png',identity=None):
        folder.mkdir(exist_ok=True)
        (folder/filename).write_bytes(self.png() if data is None else data)
        row={'attachments':[{'exportedFileName':filename,'suggestedHumanReadableName':name or 'Failure state – -[Fixture testFailure]'}]}
        if identity is not None:row['testIdentifier']=identity
        native.write_json(folder/'manifest.json',[row]);return folder

    def probe(self,argv,root,deadline,stage,developer,capture_help=False):
        from pathlib import Path
        self.calls.append((argv,deadline,developer,capture_help))
        if capture_help:return 'OK',b'--path --output-path --test-id PRIVATE_HELP_CANARY'
        self.stage(Path(argv[argv.index('--output-path')+1]));return 'OK',b'PRIVATE_EXPORT_CANARY'

    def collect(self,probe=None,deadline=None):
        import time
        from unittest.mock import patch
        with patch.object(native,'screenshot_probe_command',side_effect=probe or self.probe):
            native.collect_failure_screenshots(self.root,self.plan,self.receipt,self.output,deadline or time.monotonic()+100)
        index=self.base/'current-ui-failure-evidence/diagnostic-index.json'
        return native.read_json(index) if index.exists() else None

    def test_only_failed_ui_role_can_create_diagnostics(self):
        for role,status in [('core','FAIL'),('app-unit','FAIL'),('ui-build','FAIL'),('ui','PASS')]:
            with self.subTest(role=role,status=status):
                self.receipt.update(role=role,status=status)
                self.assertIsNone(self.collect());self.assertEqual(self.calls,[])

    def test_exact_failed_offline_test_exports_only_named_app_screenshot(self):
        before=(self.output/'receipt.json').read_bytes(); report=self.collect()
        self.assertEqual(report['status'],'EXPORTED');self.assertEqual(len(report['files']),1)
        self.assertEqual((self.output/'receipt.json').read_bytes(),before)
        self.assertEqual(report['original_status'],'FAIL');self.assertNotIn('actual',report)
        self.assertEqual(report['source_receipt_sha256'],control.digest(before))
        self.assertEqual(report['files'][0]['capture_phase'],'FAILED_TEST_TEARDOWN_APP_SCREENSHOT')
        directory=self.base/'current-ui-failure-evidence'
        self.assertEqual(len(list(directory.iterdir())),2);self.assertFalse((directory/'receipt.json').exists())
        self.assertNotIn('PRIVATE_', (directory/'diagnostic-index.json').read_text())
        self.assertEqual(self.calls[1][0][-2:],['--test-id','Fixture/testFailure()'])
        self.assertEqual(self.calls[0][2],self.receipt['toolchain']['developer'])

    def test_unreviewed_or_changed_source_does_not_invoke_exporter(self):
        (self.root/'fixture.swift').write_text('changed source')
        self.assertEqual(self.collect()['status'],'NO_ELIGIBLE_FAILED_FIXTURE');self.assertEqual(self.calls,[])
        self.assertFalse(native.screenshot_scope_current(self.root,'QuestifyUITests/Other/testFailure'))

    def test_passing_method_in_failed_shard_is_not_exported(self):
        self.nodes['testNodes'][0]['result']='Passed';native.write_json(self.output/'tests.json',self.nodes);self.bind_commands()
        self.assertEqual(self.collect()['status'],'NO_ELIGIBLE_FAILED_FIXTURE');self.assertEqual(self.calls,[])

    def test_foreign_receipt_plan_source_or_index_is_rejected_before_export(self):
        from unittest.mock import patch
        for mutation in ('receipt','plan-hash','source','index','identity-scalar'):
            with self.subTest(mutation=mutation):
                self.setUp()
                if mutation=='receipt':self.receipt['identity']=dict(self.plan['identity'],attempt='2')
                elif mutation=='plan-hash':self.receipt['plan_sha256']='0'*64
                elif mutation=='index':self.receipt['index']=False
                elif mutation=='identity-scalar':self.plan['identity']['run_id']=True
                if mutation=='source':
                    with patch.object(control,'source_identity',return_value={}):
                        with self.assertRaises(ValueError):self.collect()
                elif mutation=='identity-scalar':
                    with self.assertRaises(ValueError):self.collect()
                else:self.assertEqual(self.collect()['status'],'DIAGNOSTIC_UNAVAILABLE')
                self.assertEqual(self.calls,[])

    def test_foreign_selected_method_and_ambiguous_url_fail_closed(self):
        for mutation in ('selected','encoded-url'):
            with self.subTest(mutation=mutation):
                self.setUp()
                if mutation=='selected':self.plan['ui_shards'][0]['methods']=['QuestifyUITests/Other/testOther'];self.receipt['plan_sha256']=control.digest(control.encode(self.plan))
                else:self.summary['testFailures'][0]['testIdentifierURL']=self.url.replace('Fixture','%46ixture');native.write_json(self.output/'summary.json',self.summary)
                self.assertEqual(self.collect()['status'],'DIAGNOSTIC_UNAVAILABLE');self.assertEqual(self.calls,[])

    def test_unknown_help_capability_is_explicit_skip_without_export(self):
        def unsupported(*args):self.calls.append(args);return 'OK',b'--path --output-path'
        self.assertEqual(self.collect(unsupported)['status'],'UNSUPPORTED_TOOL_CAPABILITIES')
        self.assertEqual(len(self.calls),1)

    def test_zero_budget_uses_no_subprocess_and_shared_window_stays_within_deadline(self):
        import time
        self.assertEqual(self.collect(deadline=time.monotonic()-1)['status'],'NO_BUDGET');self.assertEqual(self.calls,[])
        self.setUp(); before=time.monotonic(); bound=before+17;self.collect(deadline=bound)
        self.assertLessEqual(self.calls[0][1],before+5.1);self.assertLessEqual(self.calls[1][1],bound)

    def test_missing_bundle_never_calls_exporter(self):
        (self.output/'ui.xcresult').rmdir()
        self.assertEqual(self.collect()['status'],'DIAGNOSTIC_UNAVAILABLE');self.assertEqual(self.calls,[])

    def test_export_error_never_serializes_arbitrary_error_text(self):
        def fail(*args):raise ValueError('PRIVATE_ERROR_CANARY')
        report=self.collect(fail);self.assertEqual(report['status'],'DIAGNOSTIC_UNAVAILABLE')
        self.assertNotIn('PRIVATE_',str(report));self.assertEqual(native.read_json(self.output/'receipt.json')['status'],'FAIL')

    def test_manifest_traversal_symlink_foreign_identity_and_unknown_schema_rejected(self):
        for mutation in ('traversal','absolute','symlink','foreign','schema','manifest-symlink'):
            with self.subTest(mutation=mutation):
                folder=self.stage(self.base/mutation);manifest=native.read_json(folder/'manifest.json')
                if mutation=='traversal':manifest[0]['attachments'][0]['exportedFileName']='../image.png'
                elif mutation=='absolute':manifest[0]['attachments'][0]['exportedFileName']='/image.png'
                elif mutation=='foreign':manifest[0]['testIdentifier']='Other/testOther'
                elif mutation=='schema':manifest={}
                elif mutation=='symlink':(folder/'image.png').unlink();(folder/'image.png').symlink_to(self.root/'fixture.swift')
                native.write_json(folder/'manifest.json',manifest)
                if mutation=='manifest-symlink':(folder/'manifest.json').unlink();(folder/'manifest.json').symlink_to(self.root/'fixture.swift')
                with self.assertRaises(ValueError):native.bounded_failure_images(folder,self.method,20*1024*1024,6)

    def test_oversized_image_index_count_and_total_caps_reject(self):
        for mutation in ('image','index','count','total'):
            with self.subTest(mutation=mutation):
                folder=self.stage(self.base/mutation);manifest=native.read_json(folder/'manifest.json')
                if mutation=='image':(folder/'image.png').write_bytes(b'X'*(native.FAILURE_IMAGE_LIMIT+1))
                elif mutation=='index':(folder/'manifest.json').write_bytes(b'X'*131073)
                elif mutation=='count':
                    for i in range(2):
                        filename=str(i)+'.png';(folder/filename).write_bytes(self.png(i+1))
                        manifest[0]['attachments'].append(dict(manifest[0]['attachments'][0],exportedFileName=filename))
                    native.write_json(folder/'manifest.json',manifest)
                with self.assertRaises(ValueError):native.bounded_failure_images(folder,self.method,1 if mutation=='total' else native.FAILURE_TOTAL_LIMIT,6)

    def test_wrong_attachment_name_video_or_unsupported_bytes_not_uploaded(self):
        for name,data in [('System screenshot',self.png()),('Failure state – -[Other testFailure]',self.png()),('Failure state – -[Fixture testFailure]',b'PRIVATE_NOT_IMAGE')]:
            folder=self.stage(self.base/str(len(name)+len(data)),data,name)
            self.assertEqual(native.bounded_failure_images(folder,self.method,native.FAILURE_TOTAL_LIMIT,6),[])

    def test_duplicate_image_payload_is_not_copied_twice(self):
        folder=self.stage(self.base/'duplicate');manifest=native.read_json(folder/'manifest.json');manifest[0]['attachments']*=2
        native.write_json(folder/'manifest.json',manifest)
        self.assertEqual(len(native.bounded_failure_images(folder,self.method,native.FAILURE_TOTAL_LIMIT,6)),1)

    def test_partial_write_or_unexpected_upload_file_never_publishes(self):
        from unittest.mock import patch
        original=native.bounded_failure_images
        def poison(*args):
            pending=next(self.base.glob('ui-failure-publish-*'));(pending/'PRIVATE_UNREVIEWED.txt').write_text('secret fixture')
            return original(*args)
        with patch.object(native,'bounded_failure_images',side_effect=poison),self.assertRaisesRegex(ValueError,'Unexpected upload'):
            self.collect()
        self.assertFalse((self.base/'current-ui-failure-evidence').exists())
        self.assertEqual(list(self.base.glob('ui-failure-publish-*')),[])

    def test_actual_readonly_process_deadline_terminates_without_output_leak(self):
        import sys,time
        started=time.monotonic();stage=self.base/'probe';stage.mkdir()
        status,raw=native.screenshot_probe_command([sys.executable,'-c','import time; print("PRIVATE"); time.sleep(20)'],self.root,started+2.15,stage,'/Applications/Xcode.app/Contents/Developer')
        self.assertEqual(status,'TIME_LIMIT');self.assertEqual(raw,b'');self.assertLess(time.monotonic()-started,3)

    def test_actual_process_staging_cap_and_symlink_terminate(self):
        import sys,time
        from unittest.mock import patch
        for kind in ('cap','symlink'):
            stage=self.base/kind;stage.mkdir()
            action='from pathlib import Path; p=Path('+repr(str(stage))+'); '
            action+=('(p/"big").write_bytes(b"X"*4096)' if kind=='cap' else '(p/"link").symlink_to("/tmp")')
            action+='; import time; time.sleep(20)'
            with self.subTest(kind=kind),patch.object(native,'FAILURE_STAGING_LIMIT',1024):
                status,raw=native.screenshot_probe_command([sys.executable,'-c',action],self.root,time.monotonic()+4,stage,'/Applications/Xcode.app/Contents/Developer')
            self.assertEqual(status,'STAGING_LIMIT' if kind=='cap' else 'UNSAFE_STAGING');self.assertEqual(raw,b'')

    def test_original_failure_survives_diagnostic_exception(self):
        import os,time
        from unittest.mock import patch
        output=self.base/'execute';start=self.base/'start';start.write_text(str(time.monotonic()))
        with patch.dict(os.environ,{'RUNNER_TEMP':str(self.base)}),patch.object(native,'toolchain',side_effect=ValueError('original failure')),patch.object(native,'collect_failure_screenshots',side_effect=RuntimeError('diagnostic failure')):
            with self.assertRaisesRegex(ValueError,'original failure'):native.execute_current(self.root,self.plan,'ui',output,start,index=0)
        receipt=native.read_json(output/'receipt.json');self.assertEqual(receipt['status'],'FAIL');self.assertEqual(receipt['error'],'original failure')

    def test_workflow_artifact_is_isolated_and_existing_gate_not_widened(self):
        from pathlib import Path
        text=(Path(__file__).resolve().parents[2]/'.github/workflows/native-ios.yml').read_text()
        start=text.index('      - name: Preserve bounded synthetic failure screenshots')
        end=text.index('  platforms:',start);step=text[start:end]
        self.assertIn('if: failure()',step);self.assertIn('if-no-files-found: ignore',step)
        self.assertIn('current-ui-failure-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}-ui-${{ matrix.index }}',step)
        self.assertIn('pattern: current-result-',text);self.assertNotIn('pattern: current-ui-failure-',text)
        self.assertNotIn('current-native/',step)

    def test_command_hash_result_hash_and_exact_invocation_are_required(self):
        for mutation in ('command-hash','document-hash','other-bundle','extra-selected-test','failed-export'):
            with self.subTest(mutation=mutation):
                self.setUp();commands=native.read_json(self.output/'commands.json')
                if mutation=='command-hash':self.receipt['commands_sha256']='0'*64
                elif mutation=='document-hash':(self.output/'summary.json').write_text('{}')
                else:
                    if mutation=='other-bundle':commands[0]['argv'][commands[0]['argv'].index('-resultBundlePath')+1]='/other/ui.xcresult'
                    elif mutation=='extra-selected-test':commands[0]['argv'].insert(-1,'-only-testing:QuestifyUITests/Other/testOther')
                    else:commands[1]['returncode']=1
                    native.write_json(self.output/'commands.json',commands);self.receipt['commands_sha256']=native.digest(self.output/'commands.json')
                self.assertEqual(self.collect()['status'],'DIAGNOSTIC_UNAVAILABLE');self.assertEqual(self.calls,[])

    def test_existing_diagnostics_are_never_overwritten(self):
        directory=self.base/'current-ui-failure-evidence';directory.mkdir();(directory/'sentinel').write_text('original')
        self.assertIsNone(self.collect());self.assertEqual(self.calls,[])
        self.assertEqual((directory/'sentinel').read_text(),'original')

    def test_successful_slow_export_cannot_publish_images_after_deadline(self):
        import time
        from unittest.mock import patch
        real_clock=time.monotonic;now=real_clock();ticks=[now]
        def exporter(*args):
            result=self.probe(*args)
            if len(args) == 5: ticks[0]=now+70
            return result
        with patch.object(native.time,'monotonic',side_effect=lambda:ticks[0]):
            report=self.collect(exporter,deadline=now+60)
        self.assertEqual(report['status'],'TIME_LIMIT');self.assertEqual(report['files'],[])
        self.assertEqual(len(list((self.base/'current-ui-failure-evidence').iterdir())),1)

    def test_final_upload_count_bytes_hash_and_filename_are_rechecked(self):
        from unittest.mock import patch
        for mutation in ('bytes','name','count'):
            with self.subTest(mutation=mutation):
                self.setUp()
                image=self.png();good=control.digest(image)+'.png'
                if mutation=='bytes':images=[(good,b'X'*(native.FAILURE_IMAGE_LIMIT+1))]
                elif mutation=='name':images=[('unknown.png',image)]
                else:images=[(control.digest(self.png(i))+'.png',self.png(i)) for i in range(7)]
                with patch.object(native,'bounded_failure_images',return_value=images),self.assertRaises(ValueError):self.collect()
                self.assertFalse((self.base/'current-ui-failure-evidence').exists())

    def test_real_exporter_is_reaped_after_traversal_exception(self):
        import sys,time,subprocess
        from pathlib import Path
        from unittest.mock import patch
        stage=self.base/'reap';stage.mkdir();processes=[];original=subprocess.Popen
        def start(*args,**kwargs):
            child=original(*args,**kwargs);processes.append(child);return child
        with patch.object(native.subprocess,'Popen',side_effect=start),patch.object(native.os,'scandir',side_effect=OSError('synthetic traversal failure')):
            with self.assertRaisesRegex(OSError,'synthetic traversal failure'):
                native.screenshot_probe_command([sys.executable,'-c','import time; time.sleep(20)'],self.root,time.monotonic()+4,stage,'/Applications/Xcode.app/Contents/Developer')
        self.assertEqual(len(processes),1);self.assertIsNotNone(processes[0].poll())

    def test_real_exporter_is_reaped_after_diagnostic_interrupt(self):
        import sys,time,subprocess
        from pathlib import Path
        from unittest.mock import patch
        stage=self.base/'interrupt';stage.mkdir();processes=[];original=subprocess.Popen
        def start(*args,**kwargs):
            child=original(*args,**kwargs);processes.append(child);return child
        with patch.object(native.subprocess,'Popen',side_effect=start),patch.object(native.os,'scandir',side_effect=KeyboardInterrupt('diagnostic interrupt')):
            with self.assertRaises(KeyboardInterrupt):
                native.screenshot_probe_command([sys.executable,'-c','import time; time.sleep(20)'],self.root,time.monotonic()+4,stage,'/Applications/Xcode.app/Contents/Developer')
        self.assertEqual(len(processes),1);self.assertIsNotNone(processes[0].poll())

    def test_diagnostic_baseexceptions_preserve_exact_original_execution_exception(self):
        import os,time
        from unittest.mock import patch
        for i,original in enumerate((ValueError('original failure'),KeyboardInterrupt('original cancellation'),SystemExit(23))):
            for j,diagnostic in enumerate((KeyboardInterrupt('diagnostic interruption'),SystemExit(55))):
                output=self.base/f'execute-{i}-{j}';start=self.base/'start';start.write_text(str(time.monotonic()))
                with self.subTest(original=type(original),diagnostic=type(diagnostic)),patch.dict(os.environ,{'RUNNER_TEMP':str(self.base)}),patch.object(native,'toolchain',side_effect=original),patch.object(native,'collect_failure_screenshots',side_effect=diagnostic):
                    with self.assertRaises(type(original)) as caught:native.execute_current(self.root,self.plan,'ui',output,start,index=0)
                self.assertIs(caught.exception,original)
                receipt=native.read_json(output/'receipt.json');self.assertEqual(receipt['status'],'FAIL');self.assertEqual(receipt['error'],str(original))

    def test_stage_and_parent_symlinks_are_rejected_before_reading_manifest(self):
        from unittest.mock import patch
        real=self.stage(self.base/'real')
        direct=self.base/'linked';direct.symlink_to(real,target_is_directory=True)
        parent=self.base/'parent-link';parent.symlink_to(self.base,target_is_directory=True)
        for stage in (direct,parent/'real'):
            with self.subTest(stage=stage),patch.object(native,'read_json') as read,self.assertRaises(ValueError):
                native.bounded_failure_images(stage,self.method,native.FAILURE_TOTAL_LIMIT,6)
            read.assert_not_called()

    def test_exporter_replaced_stage_directory_is_rejected_after_process_exit(self):
        import shutil
        from pathlib import Path
        def swapped(argv,root,deadline,stage,developer,capture_help=False):
            if capture_help:return self.probe(argv,root,deadline,stage,developer,capture_help)
            folder=Path(argv[argv.index('--output-path')+1]);outside=self.stage(self.base/'outside')
            folder.rmdir();folder.symlink_to(outside,target_is_directory=True);return 'OK',b''
        report=self.collect(swapped);self.assertEqual(report['files'],[])
        self.assertEqual(report['methods'][0]['status'],'REJECTED_ATTACHMENT_SCHEMA_OR_BOUND')

    def test_empty_directories_also_count_toward_staging_bound(self):
        import sys,time
        stage=self.base/'empty-directories';stage.mkdir()
        for i in range(257):(stage/str(i)).mkdir()
        status,_=native.screenshot_probe_command([sys.executable,'-c','import time; time.sleep(20)'],self.root,time.monotonic()+4,stage,'/Applications/Xcode.app/Contents/Developer')
        self.assertEqual(status,'STAGING_LIMIT')

    def test_directory_enumeration_checks_deadline_per_entry(self):
        import sys,time
        from unittest.mock import patch
        stage=self.base/'entry-deadline';stage.mkdir()
        for i in range(20):(stage/str(i)).mkdir()
        original=native.os.scandir;clock=[time.monotonic()];visited=[]
        class DelayedEntries:
            def __init__(self,path):self.entries=original(path)
            def __enter__(self):return self
            def __exit__(self,*args):self.entries.close()
            def __iter__(self):return self
            def __next__(self):
                value=next(self.entries);clock[0]+=0.4;visited.append(value.name);return value
        with patch.object(native.os,'scandir',side_effect=DelayedEntries),patch.object(native.time,'monotonic',side_effect=lambda:clock[0]):
            status,_=native.screenshot_probe_command([sys.executable,'-c','import time; time.sleep(20)'],self.root,clock[0]+4,stage,'/Applications/Xcode.app/Contents/Developer')
        self.assertEqual(status,'TIME_LIMIT');self.assertLess(len(visited),20)
