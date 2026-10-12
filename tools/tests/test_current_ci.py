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
            self.assertIn('max-parallel: 3',section);self.assertIn('timeout-minutes: 45',section)

    def test_missing_ui_execution_or_failed_units_still_fail_current_aggregate(self):
        from tools import current_native as native
        good={key:{'result':'success'} for key in ['controls','secrets','native','ui']}
        good['platforms']={'result':'skipped'}
        for part,result in [('ui','skipped'),('ui','failure'),('ui','cancelled'),('native','failure')]:
            needs={key:dict(value) for key,value in good.items()};needs[part]['result']=result
            with self.subTest(part=part,result=result),self.assertRaisesRegex(ValueError,'required current worker'):
                native.aggregate_current({}, {}, needs)
