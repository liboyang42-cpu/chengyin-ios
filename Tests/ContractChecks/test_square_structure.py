"""Cloud static checks only; these are not Swift compilation or simulator acceptance."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SquareStructureTests(unittest.TestCase):
    def test_localizations_cover_square_ui_literals(self):
        entries = json.loads((ROOT / 'docs/square-localizations.json').read_text())
        by_key = {item['key']: item for item in entries}
        self.assertEqual(len(by_key), len(entries))
        for item in entries:
            self.assertTrue(item['en'])
            self.assertTrue(item['zh-Hans'])
        # Integrated governance uses a separate namespaced fragment; validate it against the real catalog.
        fragment = json.loads((ROOT / 'docs/square-journey-chat/packets/native-square-governance-new/Resources/SquareGovernanceLocalizations.fragment.json').read_text())['strings']
        actual = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key, row in fragment.items():
            self.assertEqual(actual[key], row)
            by_key[key] = {lang: row['localizations'][lang]['stringUnit']['value'] for lang in ['en', 'zh-Hans']}
        # Only localized controls, labels and fixed string keys; IDs are excluded.
        for path in (ROOT / 'App').glob('Square*.swift'):
            source = path.read_text()
            literals = re.findall(r'(?:Text|ProgressView|Label|Button|Section|Picker|TextField)\("(square\.[^"\\]+)"', source)
            literals += re.findall(r'(?:return|prompt:|navigationTitle\()\s*"(square\.[^"\\]+)"', source)
            for key in literals:
                if key.endswith('.'):
                    self.assertTrue(any(k.startswith(key) for k in by_key), key)
                    continue
                self.assertIn(key, by_key, f'{path.name}: {key}')
    def test_only_three_audited_read_routes(self):
        source = (ROOT / 'Core/SquareService.swift').read_text()
        self.assertIn('api/v1/community/feeds/\\(query.mode.rawValue)', source)
        self.assertIn('api/creativesquare/info', source)
        self.assertIn('api/comment/list', source)
        for forbidden in ['api/creativesquare/list', 'api/comment/add', 'api/comment/like', 'api/v1/community/posts', 'api/creativesquare/action']:
            self.assertNotIn(forbidden, source)
        self.assertIn('request.httpMethod = "GET"', source)
        self.assertIn('"owner_type": "3"', source)
        self.assertIn('"pageNum": String(pageNumber)', source)
        self.assertIn('"pageSize": String(pageSize)', source)
    def test_fixtures_are_offline_and_debug_host_is_gated(self):
        source = (ROOT / 'App/SquareFixtureSupport.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertTrue(source.rstrip().endswith('#endif'))
        self.assertNotIn('URLSession', source)
        self.assertNotIn('SquareService(', source)
        fixtures = (ROOT / 'Core/SquareSyntheticFixtures.swift').read_text()
        literals = re.findall(r'public static let \w+ = #"(.*?)"#', fixtures)
        self.assertEqual(len(literals), 3)
        for literal in literals:
            json.loads(literal)
    def test_session_and_ui_stale_guards(self):
        reader = (ROOT / 'Core/SquareReading.swift').read_text()
        self.assertIn('currentSession() == session, scope == startedScope', reader)
        self.assertIn('!Task.isCancelled', reader)
        for name in ['SquareBrowserView.swift', 'SquareDetailView.swift']:
            source = (ROOT / 'App' / name).read_text()
            self.assertIn('operation == generation, captured == key', source)
            self.assertIn('.onDisappear', source)
    def test_no_interpolated_localization_or_plaintext_mutation_controls(self):
        for path in (ROOT / 'App').glob('Square*.swift'):
            source = path.read_text()
            self.assertNotRegex(source, r'LocalizedStringKey\("[^"\n]*\\\(')
            for forbidden in ['Button("Publish"', 'Button("Like"', 'Button("Send"']:
                self.assertNotIn(forbidden, source)

if __name__ == '__main__':
    unittest.main()
