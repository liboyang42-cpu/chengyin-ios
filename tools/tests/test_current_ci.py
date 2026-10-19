"""Small current-only planning controls; never imports a historical loader."""
import unittest
from tools import current_ci as ci


class CurrentCIControls(unittest.TestCase):
    def test_swift_lexing_preserves_real_methods_not_comments_strings_or_helpers(self):
        source = '''// final class Fake: XCTestCase { func testFake() {} }
final class Real: XCTestCase {
 func testOne() { let s = #"func testFake() { }"# }
 func helper() { let s = "\\(call(\"quoted\"))" }
 func testTwo() {}
}
'''
        self.assertEqual(ci.swift_methods(source, 'Target'), ['Target/Real/testOne','Target/Real/testTwo'])

    def test_python_method_ledger_never_imports_module(self):
        source = "raise RuntimeError('must not import')\nclass Cases:\n def test_one(self): pass\ndef test_two(): pass\n"
        self.assertEqual(ci.python_methods(source, 'tests.py'), ['tests.py::Cases.test_one','tests.py::test_two'])

    def test_duplicate_or_unclosed_declarations_fail(self):
        for source in ['class A: XCTestCase { func testA(){} func testA(){} }', 'class A: XCTestCase { func testA(){}', '/* unclosed']:
            with self.assertRaises(ValueError): ci.swift_methods(source, 'Target')

    def test_deleted_method_requires_exact_explicit_review(self):
        old={'native_methods':{'a':'p'},'portable_methods':{},'sources':[{'path':'p','sha256':'a'*64}]}
        new={'native_methods':{},'portable_methods':{},'sources':[]}
        with self.assertRaises(ValueError): ci.audit(old,new)
        with self.assertRaises(ValueError): ci.audit(old,new,{'a':' '})
        self.assertEqual(ci.audit(old,new,{'a':'Reviewed rename to b'})['removed'],['a'])
        with self.assertRaises(ValueError): ci.audit(old,old,{'x':'extraneous'})

    def test_all_complete_ui_methods_appear_once_within_original_budget(self):
        costs={'a':900,'b':700,'c':600,'d':10};groups=ci.partition(costs)
        self.assertEqual(sorted(m for row in groups for m in row['methods']),sorted(costs))
        self.assertTrue(all(row['seconds']<=1500 for row in groups))
        self.assertEqual(sum(row['seconds'] for row in groups),sum(costs.values()))
        for value in [True,0,-1,901,float('inf'),float('nan')]:
            with self.assertRaises(ValueError): ci.partition({'a':value})

    def test_related_select_uses_explicit_transitive_sources_and_keeps_smoke(self):
        ledger={'native_methods':{'QuestifyCoreTests/A/testOne':'Tests/CoreTests/A.swift','QuestifyCoreTests/B/testTwo':'Tests/CoreTests/B.swift','QuestifyUITests/Smoke/testLaunch':'Tests/AppUITests/Smoke.swift'}}
        deps={'dependents':{'Core/A.swift':['App/A.swift'],'App/A.swift':[]},'test_sources':{'Tests/CoreTests/A.swift':['App/A.swift'],'Tests/CoreTests/B.swift':['Core/B.swift']}}
        groups=ci.select(ledger,['Core/A.swift'],['QuestifyUITests/Smoke/testLaunch'],dependencies=deps)
        self.assertEqual(groups['core'],['QuestifyCoreTests/A/testOne']);self.assertEqual(groups['ui'],['QuestifyUITests/Smoke/testLaunch'])
        all_groups=ci.select(ledger,['Core/Unknown.swift'],[],dependencies=deps)
        self.assertEqual(len(all_groups['core']),2)

    def test_modified_test_file_and_full_mode_never_drop_methods(self):
        ledger={'native_methods':{'QuestifyCoreTests/A/testOne':'Tests/CoreTests/A.swift','QuestifyCoreTests/B/testTwo':'Tests/CoreTests/B.swift'}}
        self.assertEqual(ci.select(ledger,['Tests/CoreTests/B.swift'],[])['core'],['QuestifyCoreTests/B/testTwo'])
        self.assertEqual(len(ci.select(ledger,[],[],mode='full')['core']),2)

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(ValueError): ci.unique([('a',1),('a',2)])

    def test_pbx_pure_registration_does_not_select_every_ui_method(self):
        before='{"objects" = { "g" = { "isa" = "PBXGroup"; "children" = ("a",); }; "a" = { "isa" = "PBXFileReference"; "path" = "App/A.swift"; }; }; "rootObject" = "g"; }'
        after=before.replace('("a",)', '("a","b",)').replace('}; "rootObject"','"b" = { "isa" = "PBXFileReference"; "path" = "App/B.swift"; }; }; "rootObject"')
        self.assertTrue(ci.pbx_registration_only(before,after))
        self.assertFalse(ci.pbx_registration_only(before,after.replace('App/A.swift','App/Changed.swift')))
        renamed=before.replace('App/A.swift','App/Changed.swift')
        self.assertTrue(ci.pbx_registration_only(before,renamed,{'App/A.swift':'App/Changed.swift'}))
        self.assertFalse(ci.pbx_registration_only(before,renamed.replace('PBXFileReference','PBXGroup'),{'App/A.swift':'App/Changed.swift'}))
        ledger={'native_methods':{'QuestifyCoreTests/A/testOne':'Tests/CoreTests/A.swift','QuestifyUITests/A/testUI':'Tests/AppUITests/A.swift'}}
        self.assertEqual(ci.select(ledger,['Questify.xcodeproj/project.pbxproj'],[],registration_only=True)['ui'],[])
        groups=ci.select(ledger,['Questify.xcodeproj/project.pbxproj'],[],registration_only=False)
        self.assertEqual(groups['core'],['QuestifyCoreTests/A/testOne']);self.assertEqual(groups['ui'],[])

    def test_missing_tracked_file_is_explicitly_rejected(self):
        import tempfile
        from pathlib import Path
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory,patch.object(ci,'git',return_value=b'Core/Missing.swift\n'):
            with self.assertRaisesRegex(ValueError,'Missing tracked source'):
                ci.snapshot(Path(directory))

    def test_same_and_cross_file_test_extensions_are_not_silently_omitted(self):
        declaration='final class ExistingTests: XCTestCase { func testFirst() {} }'
        extension='extension ExistingTests { func testAdded() {} }'
        self.assertEqual(ci.swift_methods(declaration+extension,'Target'),['Target/ExistingTests/testFirst','Target/ExistingTests/testAdded'])
        self.assertEqual(ci.swift_methods(extension,'Target',ci.declared_case_names(declaration)),['Target/ExistingTests/testAdded'])
        with self.assertRaisesRegex(ValueError,'Unresolved test-bearing extension'):
            ci.swift_methods(extension,'Target')

    def test_daily_actual_diff_rejects_deleted_test_even_if_current_manifest_is_updated(self):
        import tempfile
        from pathlib import Path
        from types import SimpleNamespace
        from unittest.mock import patch
        before=b'final class A: XCTestCase { func testOriginal() {} }'
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);p=root/'Tests/CoreTests/A.swift';p.parent.mkdir(parents=True);p.write_text('final class A: XCTestCase {}')
            with patch.object(ci,'git',return_value=b'Tests/CoreTests/A.swift\n'),patch.object(ci.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=before)):
                with self.assertRaisesRegex(ValueError,'Actual diff removes tests'):
                    ci.audit_changed_test_declarations(root,'a'*40,{'native_methods':{},'portable_methods':{}},{})

    def test_readonly_project_equivalence_preserves_settings_and_duplicate_rejection(self):
        import ast,json,copy
        from pathlib import Path
        tree=ast.parse((ci.ROOT/'tools/check_scaffold.py').read_text())
        function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='semantic_project')
        scope={'json':json};exec(compile(ast.Module(body=[function],type_ignores=[]),'scaffold-helper','exec'),scope)
        normalize=scope['semantic_project']
        old={'objects':{'f':{'isa':'PBXFileReference','path':'A.swift'},'b':{'isa':'PBXBuildFile','fileRef':'f'},'p':{'isa':'PBXSourcesBuildPhase','files':['b']},'c':{'isa':'XCBuildConfiguration','buildSettings':{'SDKROOT':'iphoneos'}}}}
        renamed=copy.deepcopy(old);renamed['objects']['x']=renamed['objects'].pop('f');renamed['objects']['b']['fileRef']='x'
        self.assertEqual(normalize(old),normalize(renamed))
        changed=copy.deepcopy(old);changed['objects']['c']['buildSettings']['SDKROOT']='macosx'
        self.assertNotEqual(normalize(old),normalize(changed))
        duplicate=copy.deepcopy(old);duplicate['objects']['p']['files']*=2
        with self.assertRaises(AssertionError):normalize(duplicate)

    def test_display_only_impacts_require_exact_reviewed_before_and_after_bytes(self):
        from unittest.mock import patch
        row={'kind':'reviewed-existing-localization-only','before_sha256':ci.digest(b'before'),'after_sha256':ci.digest(b'after'),'test_files':['Tests/CoreTests/A.swift']}
        with patch.dict(ci.REVIEWED_DISPLAY_IMPACTS,{'App/Example.swift':row},clear=True):
            self.assertEqual(ci.reviewed_display_impact('App/Example.swift',b'before',b'after'),row)
            self.assertIsNone(ci.reviewed_display_impact('App/Example.swift',b'before',b'changed'))
            self.assertIsNone(ci.reviewed_display_impact('App/Example.swift',b'changed',b'after'))
            self.assertIsNone(ci.reviewed_display_impact('App/Other.swift',b'before',b'after'))

    def test_named_source_rows_preserve_hashes_and_reject_duplicate_or_unknown_fields(self):
        rows=[{'path':'App/AuthChannelModel.swift','sha256':'a'*64}]
        self.assertEqual(ci.source_hashes({'sources':rows}),{'App/AuthChannelModel.swift':'a'*64})
        for bad in [rows+rows,[{'path':'A','sha256':'not-a-hash'}],[{'path':'A','sha256':'a'*64,'extra':True}],[['A','a'*64]]]:
            with self.assertRaises(ValueError):ci.source_hashes({'sources':bad})

    def test_ui_workers_require_successful_same_run_build_artifact(self):
        source=(ci.ROOT/'.github/workflows/native-ios.yml').read_text()
        native=source.split('  native:\n',1)[1].split('  ui:\n',1)[0]
        ui=source.split('  ui:\n',1)[1].split('  platforms:\n',1)[0]
        self.assertIn("ui_build_artifact: ${{ steps.ui_build_upload.outputs.artifact-id }}", native)
        self.assertIn("id: ui_build_upload\n        if: ${{ success() && matrix.partition == 'ui-build' }}", native)
        self.assertIn("if: ${{ always() && needs.controls.result == 'success' && needs.native.outputs.ui_build_artifact != '' }}", ui)
        self.assertIn('needs: [controls, native]', ui)
        self.assertNotIn("needs.native.result == 'success'", ui)
        name='current-ui-build-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}'
        self.assertIn('name: '+name,native);self.assertIn('name: '+name,ui)
        for section in (native,ui):
            self.assertIn('max-parallel: 20',section);self.assertIn('timeout-minutes: 45',section)

    def test_missing_ui_execution_or_failed_units_still_fail_current_aggregate(self):
        from tools import current_native as native
        good={key:{'result':'success'} for key in ['controls','secrets','native','ui']}
        good['platforms']={'result':'skipped'}
        for part,result in [('ui','skipped'),('ui','failure'),('ui','cancelled'),('native','failure')]:
            needs={key:dict(value) for key,value in good.items()};needs[part]['result']=result
            with self.subTest(part=part,result=result),self.assertRaisesRegex(ValueError,'required current worker'):
                native.aggregate_current({}, {}, needs)

    def test_failed_ui_build_retains_small_raw_diagnostics_only(self):
        source=(ci.ROOT/'.github/workflows/native-ios.yml').read_text()
        step=source.split('      - name: Preserve exact command and result diagnostics\n',1)[1].split('      - name: Transfer one same-run UI build\n',1)[0]
        self.assertIn("if: ${{ always() && (matrix.partition != 'ui-build' || failure()) }}",step)
        for suffix in ('*.json','*.xml','*.stdout'):
            self.assertIn('${{ runner.temp }}/current-native/'+suffix,step)
        self.assertNotIn('products.tar.gz',step)
        self.assertNotIn('ui-build/',step)
        self.assertIn('if-no-files-found: error',step)
        self.assertIn("name: ${{ matrix.partition == 'ui-build' && 'current-diagnostics' || 'current-result' }}-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.partition }}",step)


class DeviceOnlyClassificationControls(unittest.TestCase):
    def actual(self):
        sources={row['path']:('QuestifyAppUnitTests',(ci.ROOT/row['path']).read_text()) for row in ci.DEVICE_ONLY_SOURCES}
        native={method:path for path,(target,source) in sources.items() for method in ci.swift_methods(source,target)}
        return sources,native

    def test_actual_eight_remain_in_complete_ledger_but_never_simulator_groups(self):
        sources,native=self.actual();classified=ci.classify_device_only(sources,native)
        self.assertEqual(len(classified),8);self.assertEqual(classified,native)
        ledger={'native_methods':dict(native,**{'QuestifyAppUnitTests/Simulator/testLive':'Tests/AppUnitTests/Simulator.swift'}),'device_only_methods':classified}
        for mode in ('related','full'):
            groups=ci.select(ledger,[],list(ledger['native_methods']),mode=mode)
            self.assertEqual(groups['app-unit'],['QuestifyAppUnitTests/Simulator/testLive'])
        rows=ci.device_only_not_run(ledger)
        self.assertEqual({row['method'] for row in rows},set(native))
        self.assertTrue(all(row['status']=='NOT_RUN' and row['platform']=='physical-ios-device' for row in rows))
        self.assertEqual(len(ledger['native_methods']),9)

    def test_guard_method_path_source_or_module_mutations_require_explicit_review(self):
        import copy
        sources,native=self.actual();path=ci.DEVICE_ONLY_SOURCES[0]['path']
        for kind in ('guard','method','outside','extra','missing','module','path','source'):
            changed=copy.deepcopy(sources);current=dict(native);target,source=changed[path]
            if kind=='guard':source=source.replace('!targetEnvironment(simulator)','targetEnvironment(simulator)')
            elif kind=='method':source=source.replace('func testRealExclusiveCiphertextFileBoundedReadAndCleanup','func testChanged')
            elif kind=='outside':source=source.replace('#endif','')+'\n#endif\nfinal class Extra: XCTestCase { func testOutside() {} }'
            elif kind=='extra':source=source.replace('#endif','final class Extra: XCTestCase { func testExtra() {} }\n#endif')
            elif kind=='missing':del changed[path]
            elif kind=='module':target='QuestifyCoreTests'
            elif kind=='path':current[next(iter(current))]='Tests/AppUnitTests/Foreign.swift'
            elif kind=='source':source+='\n// unreviewed change\n'
            if kind!='missing':changed[path]=(target,source)
            with self.subTest(kind=kind),self.assertRaises(ValueError):ci.classify_device_only(changed,current)

    def test_foreign_or_partial_classification_cannot_hide_a_simulator_method(self):
        ledger={'native_methods':{'QuestifyAppUnitTests/A/testOne':'Tests/AppUnitTests/A.swift'},'device_only_methods':{'QuestifyAppUnitTests/A/testOne':'Tests/AppUnitTests/A.swift'}}
        with self.assertRaises(ValueError):ci.select(ledger,[],list(ledger['native_methods']))
        sources,native=self.actual();partial=ci.classify_device_only(sources,native);partial.pop(next(iter(partial)))
        with self.assertRaises(ValueError):ci.device_only_not_run({'native_methods':native,'device_only_methods':partial})


class ExactBaseMigrationReviewControls(unittest.TestCase):
    MAIN = 'a'*40
    DEV = 'b'*40
    TREE = 'c'*40
    METHOD = 'QuestifyCoreTests/CurrentTests/testReplacement'
    PATH = 'Tests/CoreTests/CurrentTests.swift'
    HASH = 'd'*64

    def manifest(self):
        return {'comparison_base':self.DEV,'audit':{'retirement_review':{}},
                'snapshot':{'native_methods':{self.METHOD:self.PATH},'portable_methods':{},
                            'sources':[{'path':self.PATH,'sha256':self.HASH}]},
                'additional_base_test_reviews':{self.MAIN:{'base_tree':self.TREE,'retirements':{
                    'QuestifyCoreTests/OldTests/testOld'+str(i):{'reason':'Reviewed identity migration '+str(i),
                    'replacements':[{'method':self.METHOD,'path':self.PATH,'sha256':self.HASH}]} for i in range(27)}}}}

    def git(self, root, *args):
        if args == ('cat-file','-t',self.MAIN): return b'commit\n'
        if args == ('rev-parse',self.MAIN+'^{tree}'): return (self.TREE+'\n').encode()
        raise ValueError('Unknown exact reviewed base')

    def review(self, manifest, base=None):
        from unittest.mock import patch
        with patch.object(ci,'git',side_effect=self.git):
            return ci.retirement_review_for_base('.',manifest,base or self.MAIN)

    def audit(self, manifest, base, before):
        import tempfile
        from pathlib import Path
        from types import SimpleNamespace
        from unittest.mock import patch
        review=self.review(manifest,base)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);p=root/'Tests/CoreTests/OldTests.swift';p.parent.mkdir(parents=True);p.write_text('')
            with patch.object(ci,'git',return_value=b'Tests/CoreTests/OldTests.swift\n'),patch.object(ci.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=before)):
                return ci.audit_changed_test_declarations(root,base,manifest['snapshot'],review)

    def old_source(self):
        return ('final class OldTests: XCTestCase {'+' '.join('func testOld'+str(i)+'() {}' for i in range(27))+'}').encode()

    def test_exact_main_27_and_dev_zero_use_distinct_reviews(self):
        data=self.manifest()
        self.assertEqual(len(self.audit(data,self.MAIN,self.old_source())['removed']),27)
        self.assertEqual(self.audit(data,self.DEV,b'')['removed'],[])
        self.assertEqual(self.review(data,self.DEV),{})

    def test_missing_or_extra_old_identity_never_relaxes_exact_removed_set(self):
        import copy
        for variant in ('missing','extra'):
            data=copy.deepcopy(self.manifest());rows=data['additional_base_test_reviews'][self.MAIN]['retirements']
            if variant=='missing':rows.pop(next(iter(rows)))
            else:rows['QuestifyCoreTests/OldTests/testUnreviewedExtra']=copy.deepcopy(next(iter(rows.values())))
            with self.subTest(variant=variant),self.assertRaisesRegex(ValueError,'Actual diff removes tests'):
                self.audit(data,self.MAIN,self.old_source())

    def test_missing_entire_map_and_unlisted_base_cannot_borrow_other_review(self):
        data=self.manifest();data.pop('additional_base_test_reviews')
        with self.assertRaisesRegex(ValueError,'Actual diff removes tests'):self.audit(data,self.MAIN,self.old_source())
        data=self.manifest()
        with self.assertRaisesRegex(ValueError,'Actual diff removes tests'):self.audit(data,'e'*40,self.old_source())
        self.assertEqual(self.audit(data,'e'*40,b'')['removed'],[])

    def test_original_comparison_base_review_remains_compatible_but_not_global(self):
        data=self.manifest();data.pop('additional_base_test_reviews');reason={'QuestifyCoreTests/OldTests/testOld0':'Existing explicit reason'};data['audit']['retirement_review']=reason
        self.assertEqual(self.review(data,self.DEV),reason)
        self.assertEqual(self.review(data,self.MAIN),{})

    def test_wrong_base_and_tree_and_shadow_are_rejected(self):
        import copy
        for kind in ('short','different','tree','tree_format','shadow'):
            data=copy.deepcopy(self.manifest());entries=data['additional_base_test_reviews']
            if kind=='short':entries['a'*39]=entries.pop(self.MAIN)
            if kind=='different':entries['e'*40]=entries.pop(self.MAIN)
            if kind=='tree':entries[self.MAIN]['base_tree']='e'*40
            if kind=='tree_format':entries[self.MAIN]['base_tree']=True
            if kind=='shadow':data['comparison_base']=self.MAIN
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.review(data)

    def test_blank_reason_missing_replacement_or_changed_hash_are_rejected(self):
        import copy
        for kind in ('reason','empty','unknown','path','hash','hash_format','duplicate','current_old'):
            data=copy.deepcopy(self.manifest());rows=data['additional_base_test_reviews'][self.MAIN]['retirements'];key=next(iter(rows));row=rows[key];replacement=row['replacements'][0]
            if kind=='reason':row['reason']=' \n'
            if kind=='empty':row['replacements']=[]
            if kind=='unknown':replacement['method']='QuestifyCoreTests/CurrentTests/testMissing'
            if kind=='path':replacement['path']='Tests/CoreTests/Another.swift'
            if kind=='hash':replacement['sha256']='e'*64
            if kind=='hash_format':replacement['sha256']=True
            if kind=='duplicate':row['replacements'].append(dict(replacement))
            if kind=='current_old':rows[self.METHOD]=rows.pop(key)
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.review(data)

    def test_unknown_fields_empty_record_and_wrong_shapes_are_rejected(self):
        import copy
        for kind in ('map','empty_row','base_extra','record_extra','replacement_extra','record_array'):
            data=copy.deepcopy(self.manifest());entry=data['additional_base_test_reviews'][self.MAIN];key=next(iter(entry['retirements']));row=entry['retirements'][key]
            if kind=='map':data['additional_base_test_reviews']=[]
            if kind=='empty_row':entry['retirements']={}
            if kind=='base_extra':entry['allow_any']=True
            if kind=='record_extra':row['allow_any']=True
            if kind=='replacement_extra':row['replacements'][0]['optional']=True
            if kind=='record_array':entry['retirements']=[row]
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.review(data)

    def test_replacement_source_changes_require_renewed_review(self):
        data=self.manifest();self.assertEqual(len(self.review(data)),27)
        data['snapshot']['sources'][0]['sha256']='f'*64
        with self.assertRaisesRegex(ValueError,'source changed'):self.review(data)

    def test_portable_replacement_uses_exact_current_identity_and_source(self):
        data=self.manifest();source='Tests/ContractChecks/test_current.py';method=source+'::Current.test_case'
        data['snapshot']['portable_methods'][method]=source;data['snapshot']['sources'].append({'path':source,'sha256':'e'*64})
        row=next(iter(data['additional_base_test_reviews'][self.MAIN]['retirements'].values()))
        row['replacements']=[{'method':method,'path':source,'sha256':'e'*64}]
        self.assertEqual(len(self.review(data)),27)
        del data['snapshot']['portable_methods'][method]
        with self.assertRaisesRegex(ValueError,'replacement identity'):self.review(data)

    def test_refresh_preserves_exact_review_and_refuses_stale_replacement_binding(self):
        import copy,tempfile,json
        from pathlib import Path
        from types import SimpleNamespace
        from unittest.mock import patch
        original=self.manifest();snapshot=copy.deepcopy(original['snapshot'])
        for method in ['QuestifyCoreTests/RegionalConfigurationTests/testFirstLaunchDefaultsAndExistingChoices',
                       'QuestifyAppUnitTests/NormalHomeRuntimeRecoveryTests/testUnconfiguredLaunchNeverReadsVaultOrDispatches',
                       'QuestifyUITests/EntryFlowTests/testSettingsReopensAfterRepeatedColdLaunch']:
            path='Tests/'+method.split('/')[0]+'/'+method.split('/')[1]+'.swift'
            snapshot['native_methods'][method]=path;snapshot['sources'].append({'path':path,'sha256':'f'*64})
        original['snapshot']=copy.deepcopy(snapshot)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'App/MerchantProjectsView.swift';source.parent.mkdir(parents=True);source.write_text('unchanged')
            path=root/ci.MANIFEST;path.parent.mkdir(parents=True);path.write_text(json.dumps(original))
            def read_git(where,*args):
                if args[0]=='diff':return b''
                if args[0]=='show':return b'unchanged'
                return self.git(where,*args)
            with patch.object(ci,'snapshot',return_value=snapshot),patch.object(ci,'source_dependencies',return_value={}),patch.object(ci,'current_ui_costs',return_value={}),patch.object(ci,'REVIEWED_DISPLAY_IMPACTS',{}),patch.object(ci,'git',side_effect=read_git),patch.object(ci.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=json.dumps(original).encode())):
                refreshed=ci.refresh(root,self.DEV,self.DEV)
                self.assertEqual(refreshed['additional_base_test_reviews'],original['additional_base_test_reviews'])
                saved=path.read_bytes()
                snapshot['sources'][0]['sha256']='e'*64
                with self.assertRaisesRegex(ValueError,'source changed'):ci.refresh(root,self.DEV,self.DEV)
                self.assertEqual(path.read_bytes(),saved)
