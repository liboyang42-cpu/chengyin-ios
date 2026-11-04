"""Executable offline positive/negative controls; no Swift, CI, or live API use."""
import ast
import copy
import json
import pathlib
import re
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ast.parse((ROOT / 'tools/check_scaffold.py').read_text())
NAMES = {'validate_bilingual_catalog', 'validate_literal_text_tables', 'validate_bound_participant_issue_tables'}
SCOPE = {'json': json, 'pathlib': pathlib, 're': re}
exec(compile(ast.Module(body=[n for n in MODULE.body if isinstance(n, ast.FunctionDef) and n.name in NAMES], type_ignores=[]), 'unchanged gates and bound helper', 'exec'), SCOPE)

SOURCE = '''struct ParticipantScreenIssue {
    let key: String
    private(set) var tableName: String? = nil
    init(_ block: ParticipantCoordinatorBlock) {
        switch block {
        case .unavailable: key = "participant.recovery.custom"; tableName = "Recovery"
        }
    }
}
struct ParticipantIssueText: View {
    let issue: ParticipantScreenIssue
    var body: some View {
        Text(LocalizedStringKey(issue.key), tableName: issue.tableName)
    }
}
'''

class BoundIssueTableTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        (self.root / 'Resources').mkdir()
        self.objects = {
            'app': {'productType': 'com.apple.product-type.application', 'buildPhases': ['resources']},
            'resources': {'isa': 'PBXResourcesBuildPhase', 'files': ['build']},
            'build': {'fileRef': 'file'},
            'file': {'path': 'Resources/Recovery.xcstrings', 'sourceTree': '<group>'},
        }
        self.project = {'targets': ['app']}
        self.catalog = {'sourceLanguage': 'en', 'strings': {'participant.recovery.custom': {'localizations': {
            'en': {'stringUnit': {'state': 'translated', 'value': 'Check unavailable'}},
            'zh-Hans': {'stringUnit': {'state': 'translated', 'value': '暂时无法检查'}},
        }}}}
        self.write_catalog()

    def write_catalog(self):
        (self.root / 'Resources/Recovery.xcstrings').write_text(json.dumps(self.catalog))

    def validate(self, source=SOURCE):
        return SCOPE['validate_bound_participant_issue_tables'](source, self.root, self.objects, self.project)

    def original_default_gate(self, source):
        selected = []
        for node in MODULE.body:
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'keys' for t in node.targets):
                selected.append(node)
            elif isinstance(node, ast.Assert) and ast.unparse(node.test).startswith('not keys - set(catalog'):
                selected.append(node)
        self.assertEqual(len(selected), 3)
        scope = {'re': re, 'localizable_ui': source, 'catalog': {'strings': {}}}
        exec(compile(ast.Module(body=selected, type_ignores=[]), 'original default key assertion', 'exec'), scope)

    def testProvenBindingMasksOnlyItsAssignmentAndPassesOriginalGate(self):
        result = self.validate()
        self.assertIn('case .unavailable: key = ""; tableName = "Recovery"', result)
        self.assertIn('Text(LocalizedStringKey(issue.key), tableName: issue.tableName)', result)
        self.original_default_gate(result)

    def testMissingSelectedKeyFails(self):
        self.catalog['strings'] = {}; self.write_catalog()
        with self.assertRaises(AssertionError): self.validate()

    def testMissingChineseAndBlankTranslationFail(self):
        for mutation in ['missing', 'blank', 'untranslated']:
            with self.subTest(mutation=mutation):
                saved = copy.deepcopy(self.catalog)
                entry = self.catalog['strings']['participant.recovery.custom']['localizations']
                if mutation == 'missing': del entry['zh-Hans']
                elif mutation == 'blank': entry['zh-Hans']['stringUnit']['value'] = ' '
                else: entry['zh-Hans']['stringUnit']['state'] = 'new'
                self.write_catalog()
                with self.assertRaises(AssertionError): self.validate()
                self.catalog = saved
        self.write_catalog()

    def testMissingAppResourceMembershipFails(self):
        self.objects['resources']['files'] = []
        with self.assertRaises(AssertionError): self.validate()

    def testUnitTestTargetCannotSupplyAppResourceAuthority(self):
        self.objects['app']['productType'] = 'com.apple.product-type.bundle.unit-test'
        with self.assertRaises(AssertionError): self.validate()

    def testDuplicateTableRegistrationFails(self):
        self.objects['resources']['files'].append('build')
        with self.assertRaises(AssertionError): self.validate()

    def testWrongTableCannotBorrowKeyFromOtherCatalog(self):
        with self.assertRaises(AssertionError): self.validate(SOURCE.replace('tableName = "Recovery"', 'tableName = "Wrong"'))

    def testMissingFileFails(self):
        (self.root / 'Resources/Recovery.xcstrings').unlink()
        with self.assertRaises(AssertionError): self.validate()

    def testSameKeyInDefaultTextStillFailsOriginalGate(self):
        result = self.validate(SOURCE + '\nText("participant.recovery.custom")')
        with self.assertRaises(AssertionError): self.original_default_gate(result)

    def testDefaultCaseInBoundStructStillRequiresDefaultCatalog(self):
        source = SOURCE.replace('        case .unavailable:', '        case .accountChanged: key = "participant.untranslated.default"\n        case .unavailable:')
        with self.assertRaises(AssertionError): self.original_default_gate(self.validate(source))

    def testRendererWithoutForwardedTableFails(self):
        with self.assertRaises(AssertionError): self.validate(SOURCE.replace(', tableName: issue.tableName', ''))

    def testRendererWithWrongFieldOrBundleFails(self):
        for source in [SOURCE.replace('issue.tableName)', 'selectedTable)'), SOURCE.replace('issue.tableName)', 'issue.tableName, bundle: .main)'), SOURCE.replace('issue.key)', 'other.key)')]:
            with self.subTest(source=source):
                with self.assertRaises(AssertionError): self.validate(source)

    def testMutableKeyAndPublicTableSetterFail(self):
        for source in [SOURCE.replace('let key:', 'var key:'), SOURCE.replace('private(set) var tableName:', 'var tableName:')]:
            with self.subTest(source=source):
                with self.assertRaises(AssertionError): self.validate(source)

    def testLaterTableOverrideFails(self):
        with self.assertRaises(AssertionError): self.validate(SOURCE.replace('    init(', '    func change() { tableName = "Wrong" }\n    init('))

    def testExtraCaseStatementFails(self):
        with self.assertRaises(AssertionError): self.validate(SOURCE.replace('        }', '            mutateSomething()\n        }', 1))

    def testDuplicateBindingOrRendererFails(self):
        for source in [SOURCE + SOURCE.split('struct ParticipantIssueText')[0], SOURCE + 'struct ParticipantIssueText: View {\n}\n']:
            with self.subTest(source=source):
                with self.assertRaises(AssertionError): self.validate(source)

    def testOtherDynamicLookupsDoNotReceiveExemptions(self):
        for source in ['Text("participant.recovery.custom", tableName: selectedTable)', SOURCE.replace('ParticipantScreenIssue', 'AnotherIssue')]:
            with self.subTest(source=source):
                with self.assertRaises(AssertionError): self.original_default_gate(self.validate(source))

    def testSplitUnprovenBindingStillFailsDefaultGate(self):
        source = SOURCE.replace('; tableName =', '\n            tableName =')
        with self.assertRaises(AssertionError): self.original_default_gate(self.validate(source))

    def testUnsupportedCommentBasedBindingFailsClosed(self):
        with self.assertRaises(AssertionError): self.validate(SOURCE.replace('    init(', '    // Unsupported extra binding syntax\n    init('))

if __name__ == '__main__':
    unittest.main()
