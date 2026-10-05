"""Offline authoring-test input/wiring checks, not Apple compiler or runtime evidence."""
import json
from pathlib import Path
import re
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PreferenceEditorAcceptanceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ui = (ROOT / 'Tests/AppUITests/TemplatePreferenceDraftEditorFlowTests.swift').read_text()
        cls.editor = (ROOT / 'App/TemplatePreferenceDraftEditor.swift').read_text()
        cls.catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        source = re.search(r'private let original = " \\n" \+ #"""\n(.*?)\n    """# \+ "\\n "', cls.ui, re.S)
        if source is None:
            raise AssertionError('Could not read the exact authored UI input; refusing an empty check')
        cls.original = ' \n' + textwrap.dedent(source[1]) + '\n '

    def test_preservation_corpus_is_real_json_with_lexical_distinctions(self):
        data = json.loads(self.original)
        self.assertEqual(data['future']['integer'], 9007199254740993)
        self.assertIn('"decimal":1.2300', self.original)
        self.assertNotEqual(self.original, json.dumps(data))
        self.assertEqual(data['dimensions'], ['space'])
        self.assertEqual({option['key'] for option in data['steps'][0]['options']}, {'A', 'B'})
        self.assertEqual(set(data['results']), {'space'})
        self.assertIn('{{choices}}', data['results']['space']['body'])
        self.assertEqual(data['results']['space']['nextStepDays'], 7)

    def test_current_text_edit_is_invalid_at_every_possible_caret_position(self):
        # The UI inserts this via the real text view. No test fixture changes source after launch.
        insertion = '\nINVALID_CURRENT\n'
        self.assertIn('let insertion = "\\nINVALID_CURRENT\\n"', self.ui)
        for offset in range(len(self.original) + 1):
            with self.subTest(offset=offset), self.assertRaises(json.JSONDecodeError):
                json.loads(self.original[:offset] + insertion + self.original[offset:])
        self.assertIn('source.tap(); source.typeText(insertion)', self.ui)
        self.assertIn('current.replacingOccurrences(of: insertion, with: "")', self.ui)
        self.assertIn('Array($0.utf8)', self.ui)

    def test_status_expectations_match_real_english_catalog(self):
        valid = re.search(r'private let validMessage = "([^"]+)"', self.ui)[1]
        self.assertEqual(valid, self.catalog['templateAuthor.preference.valid']['localizations']['en']['stringUnit']['value'])
        invalid = self.catalog['templateAuthor.preference.error.json']['localizations']['en']['stringUnit']['value']
        self.assertIn('check("' + invalid + '", in: app)', self.ui)
        self.assertIn('"-AppleLanguages", "(en)"', self.ui)

    def test_preview_probes_follow_actual_current_report_and_field_values(self):
        self.assertIn('if let report = currentReport', self.editor)
        self.assertIn('if report.canPreview', self.editor)
        self.assertIn('Text(verbatim: field.value).accessibilityIdentifier("templateAuthor.preference.field." + field.path)', self.editor)
        for identifier in ['preview', 'unchecked']:
            self.assertIn('.accessibilityIdentifier("templateAuthor.preference.' + identifier + '")', self.editor)
        self.assertNotIn('ProcessInfo', self.editor)
        self.assertNotIn('sleep(', self.editor)
        self.assertIn('tap("templateAuthor.fixture.reopen", in: app)', self.ui)
        self.assertIn('tap("templateAuthor.restore", in: app)', self.ui)
        self.assertIn('chooseMethod("No validation", in: app, towardTop: true)', self.ui)


if __name__ == '__main__':
    unittest.main()
