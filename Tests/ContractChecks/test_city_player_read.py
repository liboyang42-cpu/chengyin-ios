"""Supplementary source contracts. Swift app-unit assertions remain Apple-toolchain UNRUN."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

class CityPlayerReadContracts(unittest.TestCase):
    def test_default_off_scoped_clone_preserved(self):
        root = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        self.assertEqual(root.count('cityPlayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval? = { _ in nil }'), 2)
        self.assertEqual(root.count('cityPlayerReadApproval: cityPlayerReadApproval,'), 2)
        self.assertIn('cityRead.regionID == approval.regionID', root)
        self.assertIn('currentApproval.revision == approval.revision && currentApproval.matches(context)', root)
        self.assertIn('guard current() == captured, readApprovalStillValid?() != false', root)
    def test_exact_routes_have_no_actor_override_or_write(self):
        source = (ROOT / 'Core/CityPlayerReading.swift').read_text()
        for marker in ['case current, participation, points', 'request.httpMethod == "GET"', 'request.httpBody == nil', 'request.httpBodyStream == nil', 'items.count == Set(items.map(\\.name)).count', 'Set(values.keys) == keys', 'absoluteString.utf8.elementsEqual', 'String(revision) == raw']:
            self.assertIn(marker, source)
        for key in ['"memberId"', '"sessionEpoch"', '"latitude":', '"longitude":', '"capture"', '"join"', '"reward"']:
            self.assertNotIn(key, source)
    def test_distinct_missing_provider_empty_and_unpublished(self):
        source = (ROOT / 'Core/CityPlayerReading.swift').read_text()
        for marker in ['case unavailable, loading, notPublished, available', 'NO_CURRENT_BOARD', 'CITY_PARTICIPATION_UNAVAILABLE', 'CITY_POINTS_UNAVAILABLE', 'CITY_SNAPSHOT_CHANGED', 'payload.complete == true', 'values.count <= 200', 'payload.board == board', '(!$0.mine || membership == .joined)', 'membership != .unavailable', 'points: [CityReadPoint]?']:
            self.assertIn(marker, source)
    def test_normal_map_entry_is_independent_of_poi_and_theme(self):
        app = (ROOT / 'App/QuestifyApp.swift').read_text()
        self.assertIn('cityDestination: { AnyView(SessionCityPlayerView()) }', app)
        session = (ROOT / 'App/AppSession.swift').read_text()
        self.assertIn('self.compositionViewerRevision == viewer', session)
        self.assertIn('self.composition.cityPlayerReadApproval(current)?.revision == approval.revision', session)
        view = (ROOT / 'App/CityPlayerView.swift').read_text()
        for marker in ['@EnvironmentObject private var session: AppSession', 'session.makeCityPlayerReader()', '.id(session.cityPlayerReadIdentity)', 'reader.cancel()', 'QuestifyMapAppearance.baseStyle']:
            self.assertIn(marker, view)
        for denied in ['CLLocationManager', 'UserAnnotation', 'requestWhenInUseAuthorization', 'Template', 'THEME', 'capture', 'toll', 'reward']:
            self.assertNotIn(denied, view)
    def test_all_city_strings_are_bilingual(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        keys = [key for key in catalog if key.startswith('city.read.')]
        self.assertEqual(len(keys), 20)
        for key in keys:
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][lang]['stringUnit']['value'])
    def test_normal_root_synthetic_tests_cover_rejection_and_late_results(self):
        tests = (ROOT / 'Tests/AppUnitTests/CityPlayerReadCompositionTests.swift').read_text()
        for marker in ['root(wire, Grants()).makeSession()', 'session.makeCityPlayerReader()', '"providerAbsent"', '"unpublished"', '"empty"', '"reissue"', '"expire"', '"roleABA"', '"sessionABA"', '"close"', 'for code in [200, 401, 402, 403, 404, 405, 406, -1]', 'testCurrent401ExpiresOnlyCurrentSession', 'testOuterTransportClonesRetainExactRegion']:
            self.assertIn(marker, tests)

    def test_review_url_whole_input_and_generic_auth_guards(self):
        source = (ROOT / 'Core/CityPlayerReading.swift').read_text()
        self.assertIn('try APIConfiguration(baseURL: context.baseURL)', source)
        self.assertIn('try APIConfiguration(baseURL: baseURL)', source)
        self.assertIn('guard var components = URLComponents', source)
        self.assertNotIn('resolvingAgainstBaseURL: false)!', source)
        self.assertIn(r'\\A[A-Za-z0-9][A-Za-z0-9_-]{0,95}\\z', source)
        self.assertIn(r'\\A[0-9a-f]{64}\\z', source)
        self.assertLess(source.index('if status == 401'), source.index('JSONDecoder().decode(CityEnvelope.self'))
        self.assertIn('error as? APIError == .unauthorized', source)
        self.assertIn('error as? APIError == .httpStatus(401)', source)
        tests = (ROOT / 'Tests/AppUnitTests/CityPlayerReadCompositionTests.swift').read_text()
        for marker in ['testInvalidBasesAndWholeInputIDsRejectWithoutTrapping', '"generic401"', '"empty401"', '"thrownUnauthorized"', '"hashNewline"', '"pointNewline"', '"participationNewline"']:
            self.assertIn(marker, tests)
