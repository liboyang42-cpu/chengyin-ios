"""Offline structural safety checks; not Swift compilation or live navigation evidence."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class WalkingNavigationContracts(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_real_provider_is_walking_only_and_preserves_coordinates(self):
        value = self.read('App/MapKitWalkingRoutePlanner.swift')
        for marker in ['request.transportType = .walking', 'operation.calculate()', 'route.polyline.getCoordinates', 'route.distance', 'route.expectedTravelTime', 'route.steps', 'route.advisoryNotices']:
            self.assertIn(marker, value)
        self.assertNotIn('RuntimeLocationProjection', value)
        self.assertNotIn('.straightLine(', value)
        self.assertIn('verifiedRegions: Set<String> = []', value)
    def test_location_does_not_prompt_or_enable_background_or_share(self):
        value = self.read('App/WalkingForegroundLocationProvider.swift')
        for forbidden in ['requestWhenInUseAuthorization(', 'requestAlwaysAuthorization(', 'startUpdatingLocation(', 'allowsBackgroundLocationUpdates', 'presence(', 'URLSession']:
            self.assertNotIn(forbidden, value)
        self.assertIn('enabled: Bool = false', value)
        self.assertIn('UIApplication.shared.applicationState == .active', value)
    def test_normal_composition_is_dormant_and_session_scoped(self):
        deps = self.read('App/NativeRuntimeDependencies.swift')
        self.assertIn('walkingNavigation: NativeWalkingNavigationDependencies? = nil', deps)
        self.assertIn('walkingNavigationFactory = NativeWalkingNavigationFactory', self.read('App/AppSession.swift'))
        self.assertIn('.environment(\\.walkingNavigationFactory, session.walkingNavigationFactory)', self.read('App/SessionGlobalSearchView.swift'))
        factory = self.read('App/NativeWalkingNavigationFactory.swift')
        self.assertIn('context() == dependencies.owner', factory)
        self.assertIn('checkpoint.ownerNamespace == namespace(dependencies.owner)', factory)
    def test_navigation_has_no_gameplay_mutation_dependency(self):
        value = self.read('Core/WalkingNavigationCoordinator.swift')
        for forbidden in ['PlayExperienceService', 'api/play/arrive', 'completeNode(', '.complete(', '.reward(', 'sorted(']:
            self.assertNotIn(forbidden, value)
        self.assertIn('value.reference == reference', value)
        self.assertIn('value.coordinate.datum == .wgs84', value)
        self.assertIn('replanCount < 2', value)
        self.assertIn('now().timeIntervalSince(lastReplanAt) < 30', value)
    def test_no_legacy_straightline_used_in_navigable_preview(self):
        value = self.read('App/SearchRoutePreviewView.swift')
        self.assertNotIn('value = .straightLine', value)
        self.assertIn('guard !value.isStraightLine', value)
        self.assertIn('WalkingNavigationView(reference: navigationReference, factory: walkingFactory', value)
        self.assertNotIn('SearchRouteMode.allCases', value)
    def test_bilingual_keys_are_complete_and_match_catalog(self):
        fragment = json.loads(self.read('docs/walking-navigation-localizations.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key, languages in fragment.items():
            self.assertEqual(set(languages), {'en', 'zh-Hans'})
            for language, text in languages.items(): self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], text)
        app = self.read('App/WalkingNavigationView.swift') + self.read('App/SearchRoutePreviewView.swift')
        app = re.sub(r'\.accessibilityIdentifier\([^\n]+', '', app)
        keys = {k for k in re.findall(r'"(walking\.[A-Za-z0-9.]+)"', app) if not k.endswith('.')}
        self.assertTrue(keys <= set(fragment), keys - set(fragment))
    def test_offline_fixture_exercises_shipping_factory_and_adapter(self):
        value = self.read('App/WalkingNavigationFixtureSupport.swift')
        self.assertTrue(value.startswith('#if DEBUG'))
        for marker in ['NativeWalkingNavigationDependencies(', 'NativeWalkingNavigationFactory(dependencies:', 'MapKitWalkingRoutePlanner(verifiedRegions:', 'executor: directions']:
            self.assertIn(marker, value)
        self.assertIn('if offline {', self.read('App/WalkingNavigationView.swift'))
    def test_directions_response_rechecks_fix_before_publishing_route(self):
        value = self.read('Core/WalkingNavigationCoordinator.swift')
        accepted = value.split('let result = try await planner.preview', 1)[1].split('} catch', 1)[0]
        self.assertLess(accepted.index('guard accepts(ticket)'), accepted.index('try validateFix(fix)'))
        self.assertLess(accepted.index('try validateFix(fix)'), accepted.index('route = result'))
        self.assertLess(accepted.index('try validateFix(fix)'), accepted.index('apply(fix)'))
        validator = value.split('private func validateFix', 1)[1].split('private func request', 1)[0]
        self.assertIn('location.authorization == .authorized', validator)
        self.assertIn('age <= 15', validator)
    def test_future_region_and_resume_limits_are_documented(self):
        value = self.read('docs/walking-navigation.md')
        for marker in ['GCJ02', 'NOT_RUN', 'Tencent', 'No durable checkpoint storage', 'Mainland China']:
            self.assertIn(marker, value)

if __name__ == '__main__': unittest.main()
