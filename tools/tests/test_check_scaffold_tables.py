"""Offline table-resolution controls; these do not invoke Xcode or CI."""
import ast
import json
import pathlib
import re
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ast.parse((ROOT / 'tools/check_scaffold.py').read_text())
# Import only pure validation helpers, avoiding unrelated full-repo checks.
FUNCTIONS = ast.Module(body=[node for node in MODULE.body if isinstance(node, ast.FunctionDef)
                            and node.name in {'validate_bilingual_catalog', 'validate_literal_text_tables'}],
                       type_ignores=[])
SCOPE = {'json': json, 'pathlib': pathlib, 're': re}
exec(compile(FUNCTIONS, 'check_scaffold table helpers', 'exec'), SCOPE)
validate = SCOPE['validate_literal_text_tables']


class ExplicitTextTableTests(unittest.TestCase):
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
        self.catalog = {'sourceLanguage': 'en', 'strings': {'club.custom.title': {'localizations': {
            'en': {'stringUnit': {'state': 'translated', 'value': 'Title'}},
            'zh-Hans': {'stringUnit': {'state': 'translated', 'value': '标题'}},
        }}}}
        self.write_catalog()
        self.call = 'Text("club.custom.title", tableName: "Other")'

    def write_catalog(self):
        (self.root / 'Resources/Other.xcstrings').write_text(json.dumps(self.catalog))

    def check(self, source=None):
        return validate(self.call if source is None else source, self.root, self.objects, self.project)

    def default_missing(self, source):
        # Use the exact existing default-key extraction/assertion from the real checker.
        selected = []
        for node in MODULE.body:
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'keys' for t in node.targets):
                selected.append(node)
            elif isinstance(node, ast.Assert) and isinstance(node.test, ast.UnaryOp) and isinstance(node.test.operand, ast.BinOp):
                if ast.unparse(node.test).startswith('not keys - set(catalog'):
                    selected.append(node)
        self.assertEqual(len(selected), 3)
        scope = {'re': re, 'localizable_ui': source, 'catalog': {'strings': {}}}
        exec(compile(ast.Module(body=selected, type_ignores=[]), 'original key gate', 'exec'), scope)

    def testCorrectTablePassesAndMasksOnlyTheMatchedKey(self):
        self.assertEqual(self.check(), 'Text("", tableName: "Other")')
        self.default_missing(self.check())

    def testWrongTableRejectsEvenIfAnotherTableHasTheKey(self):
        with self.assertRaises(AssertionError): self.check(self.call.replace('"Other"', '"Wrong"'))

    def testMissingKeyInSelectedTableRejects(self):
        with self.assertRaises(AssertionError): self.check(self.call.replace('club.custom.title', 'club.custom.absent'))

    def testNoTableNameKeepsOriginalDefaultRejection(self):
        with self.assertRaises(AssertionError): self.default_missing(self.check('Text("club.custom.title")'))

    def testSameKeyInDefaultTextIsNotExemptedByAnotherCall(self):
        with self.assertRaises(AssertionError): self.default_missing(self.check(self.call+'\nText("club.custom.title")'))

    def testFileReferenceWithoutAppResourceMembershipRejects(self):
        self.objects['resources']['files'] = []
        with self.assertRaises(AssertionError): self.check()

    def testTestTargetResourceDoesNotGrantAppMembership(self):
        self.objects['app']['productType'] = 'com.apple.product-type.bundle.unit-test'
        with self.assertRaises(AssertionError): self.check()

    def testWrongBuildPhaseRejects(self):
        self.objects['resources']['isa'] = 'PBXSourcesBuildPhase'
        with self.assertRaises(AssertionError): self.check()

    def testAmbiguousTableNameRejects(self):
        self.objects['resources']['files'].append('build')
        with self.assertRaises(AssertionError): self.check()

    def testMissingCatalogRejects(self):
        (self.root / 'Resources/Other.xcstrings').unlink()
        with self.assertRaises(AssertionError): self.check()

    def testTraversalPathRejects(self):
        self.objects['file']['path'] = '../Other.xcstrings'
        with self.assertRaises(AssertionError): self.check()

    def testMissingLanguageRejectsEvenOnAnUnreferencedCatalogEntry(self):
        self.catalog['strings']['unreferenced'] = {'localizations': {'en': {'stringUnit': {'state': 'translated', 'value': 'Value'}}}}
        self.write_catalog()
        with self.assertRaises(AssertionError): self.check()

    def testIncompleteTranslationAndBlankValueReject(self):
        for field,value in [('state', 'new'), ('value', '   ')]:
            with self.subTest(field=field):
                unit = self.catalog['strings']['club.custom.title']['localizations']['zh-Hans']['stringUnit']
                old = unit[field]; unit[field] = value; self.write_catalog()
                with self.assertRaises(AssertionError): self.check()
                unit[field] = old

    def testChineseSourceCatalogRequiresBothTranslatedLanguages(self):
        self.catalog['sourceLanguage'] = 'zh-Hans'; self.write_catalog()
        self.default_missing(self.check())
        with self.assertRaises(AssertionError): SCOPE['validate_bilingual_catalog'](self.catalog, 'Localizable')

    def testUnexpectedLanguageAndSourceLanguageReject(self):
        self.catalog['sourceLanguage'] = 'fr'; self.write_catalog()
        with self.assertRaises(AssertionError): self.check()
        self.catalog['sourceLanguage'] = 'en'
        self.catalog['strings']['club.custom.title']['localizations']['fr'] = {'stringUnit': {'state': 'translated', 'value': 'Titre'}}
        self.write_catalog()
        with self.assertRaises(AssertionError): self.check()

    def testDynamicTableAndExplicitBundleDoNotAcquireExemptions(self):
        for call in [self.call.replace('"Other"', 'selectedTable'), self.call[:-1]+', bundle: .main)', 'Custom'+self.call]:
            with self.subTest(call=call):
                self.assertEqual(self.check(call), call)
                with self.assertRaises(AssertionError): self.default_missing(self.check(call))

    def testWhitespaceIsAllowedWithoutBroadeningTheCallShape(self):
        self.assertEqual(self.check('Text(\n "club.custom.title",\n tableName: "Other"\n)'), 'Text(\n "",\n tableName: "Other"\n)')

    def testDefaultBilingualValidationStillRejectsMissingLanguage(self):
        del self.catalog['strings']['club.custom.title']['localizations']['zh-Hans']
        with self.assertRaises(AssertionError): SCOPE['validate_bilingual_catalog'](self.catalog, 'Localizable')


if __name__ == '__main__':
    unittest.main()
