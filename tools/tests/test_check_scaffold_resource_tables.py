"""Independent offline controls for locale-bound literal resource lookups.

These validate structural localization gates only, not Swift/Xcode or runtime behavior.
"""
import ast
import copy
import json
import pathlib
import re
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ast.parse((ROOT / 'tools/check_scaffold.py').read_text())
NAMES = {'parse_project', 'validate_bilingual_catalog', 'validate_literal_text_tables',
         'validate_literal_resource_tables'}
SCOPE = {'json': json, 'pathlib': pathlib, 're': re}
exec(compile(ast.Module(body=[node for node in MODULE.body
                             if isinstance(node, ast.FunctionDef) and node.name in NAMES],
                        type_ignores=[]), 'literal resource table helpers', 'exec'), SCOPE)


class LiteralResourceTableTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = pathlib.Path(self.scratch.name)
        (self.root / 'Resources').mkdir()
        self.objects = {
            'app': {'productType': 'com.apple.product-type.application', 'buildPhases': ['resources']},
            'resources': {'isa': 'PBXResourcesBuildPhase', 'files': ['build']},
            'build': {'fileRef': 'file'},
            'file': {'path': 'Resources/Other.xcstrings', 'sourceTree': '<group>'},
        }
        self.project = {'targets': ['app']}
        self.catalog = {'sourceLanguage': 'en', 'strings': {'message.custom.title': {'localizations': {
            'en': {'stringUnit': {'state': 'translated', 'value': 'Title'}},
            'zh-Hans': {'stringUnit': {'state': 'translated', 'value': '标题'}},
        }}}}
        self.write_catalog()
        self.call = 'String(localized: LocalizedStringResource("message.custom.title", table: "Other", locale: locale))'

    def write_catalog(self):
        (self.root / 'Resources/Other.xcstrings').write_text(json.dumps(self.catalog))

    def validate(self, source=None):
        return SCOPE['validate_literal_resource_tables'](
            self.call if source is None else source, self.root, self.objects, self.project)

    def default_gate(self, source, run_real_pipeline_call=False):
        # Execute the original default-key extraction/assertion, without copying
        # or replacing its key regex or broadening the default catalog contents.
        selected = []
        for node in MODULE.body:
            if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'keys'
                                                   for target in node.targets):
                selected.append(node)
            elif isinstance(node, ast.Assert) and ast.unparse(node.test).startswith('not keys - set(catalog'):
                selected.append(node)
        self.assertEqual(len(selected), 3)
        scope = dict(SCOPE, localizable_ui=source, catalog={'strings': {}},
                     ROOT=self.root, objects=self.objects, project_obj=self.project)
        if run_real_pipeline_call:
            calls = [node for node in MODULE.body if isinstance(node, ast.Assign)
                     and isinstance(node.value, ast.Call) and isinstance(node.value.func, ast.Name)
                     and node.value.func.id == 'validate_literal_resource_tables']
            self.assertEqual(len(calls), 1)
            self.assertLess(MODULE.body.index(calls[0]), MODULE.body.index(selected[0]))
            selected = calls + selected
        exec(compile(ast.Module(body=selected, type_ignores=[]), 'original default gate', 'exec'), scope)

    def assert_unproven(self, source):
        self.assertEqual(self.validate(source), source)
        with self.assertRaises(AssertionError): self.default_gate(self.validate(source))

    def testLiteralResourceMasksOnlyTheKeyAndPassesOriginalGate(self):
        result = self.validate()
        self.assertEqual(result, self.call.replace('message.custom.title', ''))
        self.default_gate(result)

    def testRealCheckerPipelineInvokesHelperBeforeUnchangedDefaultGate(self):
        self.default_gate(self.call, run_real_pipeline_call=True)
        with self.assertRaises(AssertionError):
            self.default_gate(self.call + '\nText("message.custom.title")', run_real_pipeline_call=True)

    def testWhitespaceAndSimpleLocaleVariablePass(self):
        source = 'String (\n localized : LocalizedStringResource (\n "message.custom.title",\n table : "Other",\n locale : selectedLocale_2\n )\n )'
        self.assertEqual(self.validate(source), source.replace('message.custom.title', ''))
        self.default_gate(self.validate(source))

    def testRepeatedProvenCallsEachMaskOnlyTheirKey(self):
        source = self.call + '\n' + self.call
        self.assertEqual(self.validate(source), source.replace('message.custom.title', ''))

    def testIdenticalKeyInDefaultTextStillFails(self):
        source = self.call + '\nText("message.custom.title")'
        result = self.validate(source)
        self.assertIn('Text("message.custom.title")', result)
        with self.assertRaises(AssertionError): self.default_gate(result)

    def testIdenticalKeyInUnprovenLookupStillFails(self):
        source = self.call + '\n' + self.call.replace('table: "Other"', 'table: selectedTable')
        result = self.validate(source)
        self.assertEqual(result.count('"message.custom.title"'), 1)
        with self.assertRaises(AssertionError): self.default_gate(result)

    def testNoTableDynamicTableAndInterpolatedTableRemainUnproven(self):
        for source in [self.call.replace(', table: "Other"', ''),
                       self.call.replace('table: "Other"', 'table: selectedTable'),
                       self.call.replace('table: "Other"', r'table: "Other\(suffix)"')]:
            with self.subTest(source=source): self.assert_unproven(source)

    def testInterpolatedAndDynamicKeysAreNotMasked(self):
        for key in [r'"message.custom.\(kind)"', 'selectedKey']:
            source = self.call.replace('"message.custom.title"', key)
            with self.subTest(source=source):
                self.assertEqual(self.validate(source), source)
                # Unsupported key syntax cannot grant a separate default lookup
                # an exemption, even though the old literal scan cannot parse it.
                with self.assertRaises(AssertionError):
                    self.default_gate(self.validate(source + '\nText("message.custom.title")'))

    def testExplicitBundleAndOtherExtraArgumentsRemainUnproven(self):
        for source in [self.call.replace('locale: locale)', 'locale: locale, bundle: .main)'),
                       self.call[:-1] + ', bundle: .main)',
                       self.call.replace('locale: locale)', 'locale: locale, comment: "Comment")'),
                       self.call.replace('table: "Other",', 'table: "Other", bundle: customBundle,')]:
            with self.subTest(source=source): self.assert_unproven(source)

    def testQualifiedAndCustomCallsRemainUnproven(self):
        for source in ['Foundation.' + self.call, 'Custom' + self.call,
                       self.call.replace('LocalizedStringResource(', 'Foundation.LocalizedStringResource('),
                       self.call.replace('LocalizedStringResource(', 'CustomLocalizedStringResource(')]:
            with self.subTest(source=source): self.assert_unproven(source)

    def testOnlyExactStringResourceWrapperIsProven(self):
        for source in [self.call[len('String(localized: '):-1],
                       self.call.replace('String(localized:', 'Text('),
                       self.call.replace('String(localized:', 'String(describing:')]:
            with self.subTest(source=source): self.assert_unproven(source)

    def testLocaleExpressionsAndMissingLocaleRemainUnproven(self):
        for locale in ['.current', 'self.locale', 'Locale(identifier: "en")', 'chooseLocale()',
                       'flag ? firstLocale : secondLocale']:
            with self.subTest(locale=locale):
                self.assert_unproven(self.call.replace('locale: locale', 'locale: ' + locale))
        self.assert_unproven(self.call.replace(', locale: locale', ''))

    def testAbsentTableCannotBorrowKeyFromExistingTable(self):
        with self.assertRaises(AssertionError): self.validate(self.call.replace('"Other"', '"Missing"'))

    def testExistingWrongTableCannotBorrowKeyFromOtherTable(self):
        self.objects['resources']['files'].append('wrongBuild')
        self.objects['wrongBuild'] = {'fileRef': 'wrongFile'}
        self.objects['wrongFile'] = {'path': 'Resources/Wrong.xcstrings', 'sourceTree': '<group>'}
        (self.root / 'Resources/Wrong.xcstrings').write_text(json.dumps({'sourceLanguage': 'en', 'strings': {}}))
        with self.assertRaises(AssertionError): self.validate(self.call.replace('"Other"', '"Wrong"'))

    def testMissingSelectedKeyFails(self):
        with self.assertRaises(AssertionError): self.validate(self.call.replace('message.custom.title', 'message.custom.absent'))

    def testFileReferenceWithoutAppResourceMembershipFails(self):
        self.objects['resources']['files'] = []
        with self.assertRaises(AssertionError): self.validate()

    def testWrongBuildPhaseFails(self):
        self.objects['resources']['isa'] = 'PBXSourcesBuildPhase'
        with self.assertRaises(AssertionError): self.validate()

    def testTestTargetResourceCannotAuthorizeAppLookup(self):
        self.objects['app']['productType'] = 'com.apple.product-type.bundle.unit-test'
        with self.assertRaises(AssertionError): self.validate()

    def testAmbiguousApplicationTargetFails(self):
        self.objects['secondApp'] = copy.deepcopy(self.objects['app'])
        self.project['targets'].append('secondApp')
        with self.assertRaises(AssertionError): self.validate()

    def testDuplicateTableRegistrationFails(self):
        self.objects['resources']['files'].append('build')
        with self.assertRaises(AssertionError): self.validate()

    def testMissingCatalogFileFails(self):
        (self.root / 'Resources/Other.xcstrings').unlink()
        with self.assertRaises(AssertionError): self.validate()

    def testUnsafeResourcePathsAndSourceTreesFail(self):
        for path, tree in [('../Other.xcstrings', '<group>'), ('/tmp/Other.xcstrings', '<group>'),
                           ('Resources/Other.xcstrings', 'SOURCE_ROOT')]:
            with self.subTest(path=path, tree=tree):
                self.objects['file'].update(path=path, sourceTree=tree)
                with self.assertRaises(AssertionError): self.validate()

    def testSymlinkOutsideRootFails(self):
        with tempfile.TemporaryDirectory() as directory:
            outside = pathlib.Path(directory) / 'Other.xcstrings'
            outside.write_text(json.dumps(self.catalog))
            path = self.root / 'Resources/Other.xcstrings'
            path.unlink(); path.symlink_to(outside)
            with self.assertRaises(AssertionError): self.validate()

    def testChineseSourcePassesOnlyWithBothCompleteLanguages(self):
        self.catalog['sourceLanguage'] = 'zh-Hans'; self.write_catalog()
        self.default_gate(self.validate())
        with self.assertRaises(AssertionError): SCOPE['validate_bilingual_catalog'](self.catalog, 'Localizable')
        del self.catalog['strings']['message.custom.title']['localizations']['en']; self.write_catalog()
        with self.assertRaises(AssertionError): self.validate()

    def testMissingUnexpectedOrUntranslatedLanguageFails(self):
        original = copy.deepcopy(self.catalog)
        for mutation in ['missing', 'extra', 'untranslated', 'blank', 'source']:
            with self.subTest(mutation=mutation):
                self.catalog = copy.deepcopy(original)
                entry = self.catalog['strings']['message.custom.title']['localizations']
                if mutation == 'missing': del entry['zh-Hans']
                elif mutation == 'extra': entry['fr'] = copy.deepcopy(entry['en'])
                elif mutation == 'untranslated': entry['zh-Hans']['stringUnit']['state'] = 'new'
                elif mutation == 'blank': entry['zh-Hans']['stringUnit']['value'] = '  '
                else: self.catalog['sourceLanguage'] = 'fr'
                self.write_catalog()
                with self.assertRaises(AssertionError): self.validate()

    def testUnreferencedBrokenEntryStillFailsFullCatalogValidation(self):
        self.catalog['strings']['unreferenced'] = {'localizations': {
            'en': {'stringUnit': {'state': 'translated', 'value': 'Value'}}}}
        self.write_catalog()
        with self.assertRaises(AssertionError): self.validate()

    def testActualNativeChannelLookupsUseRegisteredBilingualTable(self):
        project = SCOPE['parse_project']((ROOT / 'Questify.xcodeproj/project.pbxproj').read_text())
        objects = project['objects']
        source = (ROOT / 'App/NativeChannelMessageBubbleView.swift').read_text()
        result = SCOPE['validate_literal_resource_tables'](source, ROOT, objects, objects[project['rootObject']])
        default = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['message.system', 'message.recalled', 'message.unavailable']:
            with self.subTest(key=key):
                self.assertIn('LocalizedStringResource("' + key + '", table: "NativeChannelMessage", locale: locale)', source)
                self.assertNotIn('LocalizedStringResource("' + key + '"', result)
                self.assertEqual(source.count('Text("' + key + '"'), result.count('Text("' + key + '"'))
                self.assertNotIn(key, default)


if __name__ == '__main__':
    unittest.main()
