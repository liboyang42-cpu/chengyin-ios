"""Source-level checks only: not Swift compilation or Apple runtime evidence."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE = ROOT / "Core"
APP = ROOT / "App"

class GrowthSourceChecks(unittest.TestCase):
    def test_route_allowlist_matches_audited_flutter_reads(self):
        service = (CORE / "GrowthCenterService.swift").read_text()
        actual = set(re.findall(r'"(api/[^"\s]+)"', service))
        self.assertEqual(actual, {"api/growth/center", "api/growth/leaderboard", "api/play/growth", "api/play/my-completed"})
        self.assertIn('"application/json"', service)
        self.assertIn('limit: 1', service)
        self.assertIn('limit: Int = 50', service)
        self.assertIn('board.metric == query.metric, board.period == query.period', service)
        self.assertNotIn('URLSession.shared', service)
    def test_no_default_endpoint_or_embedded_credentials(self):
        for path in list(CORE.glob("Growth*.swift")) + list(APP.glob("Growth*.swift")):
            self.assertNotRegex(path.read_text(), r'https?://', str(path))
            self.assertNotIn('UserDefaults', path.read_text())
        self.assertNotIn('Bearer ', (CORE / "GrowthCenterService.swift").read_text())
    def test_all_four_sources_are_isolated_and_authentication_is_fatal(self):
        service = (CORE / "GrowthCenterService.swift").read_text()
        for index in range(4):
            self.assertIn(f'requireAuthorized(result.{index})', service)
            self.assertIn(f'section(result.{index})', service)
        self.assertIn('async let centerResult', service)
        self.assertIn('APIError.unauthorized', service)
    def test_reader_guards_success_and_failure_with_full_session_and_scope(self):
        reader = (CORE / "GrowthCenterReading.swift").read_text()
        self.assertGreaterEqual(reader.count('currentSession() == session, scope == captured'), 2)
        self.assertIn('fileprivate let token', reader)
        self.assertIn('let epoch: UInt64', reader)
        self.assertIn('let accountID: Int', reader)
        self.assertIn('loadedKey == key', reader)
        self.assertIn('captured == generation, currentKey() == key', reader)
    def test_native_ui_does_not_fetch_third_party_media_or_invent_actions(self):
        source = '\n'.join(p.read_text() for p in APP.glob("Growth*.swift"))
        for symbol in ['AsyncImage', 'URLSession', 'WKWebView', 'NavigationLink(destination: Text']:
            self.assertNotIn(symbol, source)
        self.assertIn('accessibilityReduceMotion', source)
        self.assertIn('.onDisappear', source)
        self.assertIn('.refreshable', source)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', source)
    def test_localization_covers_literal_and_computed_ui_keys(self):
        entries = json.loads((ROOT / "docs/growth-center-localizations.json").read_text())
        for key, values in entries.items():
            self.assertEqual(set(values), {"en", "zh-Hans"}, key)
            self.assertTrue(all(values.values()), key)
        source = '\n'.join(p.read_text() for p in list(CORE.glob("Growth*.swift")) + list(APP.glob("Growth*.swift")))
        dynamic = {'growth.metric.', 'growth.period.', 'growth.unit.'}
        identifiers = {'growth.issue', 'growth.points', 'growth.openLeaderboard', 'growth.badge.\\(index)', 'growth.board.me.\\(rank)', 'growth.board.row.\\(index)'}
        source = re.sub(r'\.accessibilityIdentifier\("[^"]*"\)', '', source)
        for key in set(re.findall(r'"(growth\.[A-Za-z.]+)"', source)):
            if key in dynamic or key in identifiers or key in {'growth.board.', 'growth.badge.'}:
                continue
            if key.startswith('growth.board.row.') or key.startswith('growth.board.me.'):
                continue
            self.assertIn(key, entries, key)
        for kind, values in {'metric': ['point', 'exp'], 'period': ['week', 'total'], 'unit': ['point', 'exp']}.items():
            for value in values: self.assertIn(f'growth.{kind}.{value}', entries)
    def test_fixtures_are_debug_only_and_valid_json(self):
        for path in [CORE / "GrowthCenterSyntheticFixtures.swift", APP / "GrowthCenterFixtureSupport.swift"]:
            self.assertTrue(path.read_text().startswith('#if DEBUG'))
        fixtures = (CORE / "GrowthCenterSyntheticFixtures.swift").read_text()
        for raw in re.findall(r'=#"(.*?)"#', fixtures): json.loads(raw)
        for raw in re.findall(r'= #"(.*?)"#', fixtures): json.loads(raw)
    def test_no_zero_defaults_or_claim_completion_logic(self):
        contracts = (CORE / "GrowthCenterContracts.swift").read_text()
        self.assertNotIn('?? 0', contracts)
        self.assertIn('let rank: Int?', contracts)
        self.assertIn('value.count == 19', contracts)
        self.assertIn('Set(rows.compactMap', contracts)
        self.assertIn('filter { $0 > 0 }', contracts)

    def test_integrated_session_uses_existing_region_and_storage_scope_gate(self):
        session = (ROOT / "App/AppSession.swift").read_text()
        start = session.index('if let scope, let regional, let configuration=regional.apiConfiguration')
        end = session.index('} else {', start)
        self.assertIn('growthCenterService=GrowthCenterService(configuration:configuration,transport:transport)', session[start:end])
        self.assertIn('growthCenterService=nil', session[end:])
        self.assertIn('self.currentGrowthCenterSession == captured', session)
        self.assertIn('private let accountSessionService: CNAccountSessionService?', session)
    def test_integrated_account_and_fixture_entries_preserve_scope(self):
        account = (ROOT / "App/AccountView.swift").read_text()
        self.assertIn('GrowthCenterView(reader:session.growthCenterReader).id(session.growthCenterReader.scope)', account)
        self.assertIn('CreatorContentProjectsView', account)
        self.assertIn('AccountCollectionAccountLinks', account)
        self.assertIn('case .growthCenter: GrowthCenterFixtureHostView()', (ROOT / "App/ModuleFixtureSupport.swift").read_text())
    def test_all_growth_strings_reach_shared_catalog(self):
        entries = json.loads((ROOT / "docs/growth-center-localizations.json").read_text())
        strings = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())["strings"]
        for key, languages in entries.items():
            for language, value in languages.items():
                self.assertEqual(strings[key]["localizations"][language]["stringUnit"]["value"], value)

if __name__ == '__main__': unittest.main()
