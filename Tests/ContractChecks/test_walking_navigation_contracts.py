"""Offline structural safety checks; not Swift compilation or live navigation evidence."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

# Exact approved checkpoint/power additions; unrelated keys still require the original fragment.
CHECKPOINT_POWER_LOCALIZATIONS = {'walking.saved.open': {'en': 'Saved walking destination', 'zh-Hans': '已保存的步行目的地'}, 'walking.saved.retryRead': {'en': 'Retry local read', 'zh-Hans': '重试本机读取'}, 'walking.saved.restoreUnavailable': {'en': 'This saved reference could not be reopened. Retry the local read, or go back to refresh the saved destination. Navigation has not started.', 'zh-Hans': '暂时无法重新打开此保存记录。可重试本机读取，或返回刷新已保存目的地。导航尚未开始。'}, 'walking.power.notice': {'en': 'Low Power Mode is on. Foreground navigation keeps its normal updates; inactive checks are less frequent. You can pause at any time.', 'zh-Hans': '低电量模式已开启。前台导航保持正常更新，非活跃时减少检查频率。你可随时主动暂停。'}, 'walking.saved.notice': {'en': 'Only this destination is saved on this device. Starting again checks current access and location. No route or travel history is saved.', 'zh-Hans': '仅在本机保存此目的地。再次开始时会重新检查当前访问资格和定位；不会保存路线或行走轨迹。'}, 'walking.saved.remove': {'en': 'Remove saved destination', 'zh-Hans': '移除已保存目的地'}, 'walking.saved.failed': {'en': 'The saved destination could not be updated. Navigation has not been saved or restored by this message.', 'zh-Hans': '未能更新已保存目的地。此提示不表示导航已保存或恢复。'}}

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
        self.assertIn('var walkingNavigationFactory: NativeWalkingNavigationFactory { NativeWalkingNavigationFactory', self.read('App/AppSession.swift'))
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
        loader = self.read('Core/SearchRoutePreview.swift')
        self.assertIn('guard !value.isStraightLine else { throw WalkingNavigationFailure.noRoute }', loader)
        self.assertIn('await loader.load(owner)', value)
        self.assertIn('testShippingPreviewLoaderRejectsStraightLineResult', self.read('Tests/AppUnitTests/WalkingNavigationAppTests.swift'))
        self.assertIn('WalkingNavigationView(reference: navigationReference, factory: walkingFactory', value)
        self.assertNotIn('SearchRouteMode.allCases', value)
    def test_bilingual_keys_are_complete_and_match_catalog(self):
        fragment = json.loads(self.read('docs/walking-navigation-localizations.json'))
        self.assertTrue(set(fragment).isdisjoint(CHECKPOINT_POWER_LOCALIZATIONS))
        fragment.update(CHECKPOINT_POWER_LOCALIZATIONS)
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

    def test_checkpoint_keys_cannot_hide_missing_or_changed_translation(self):
        original_read = self.read
        original_catalog = json.loads(original_read('Resources/Localizable.xcstrings'))
        try:
            for key in CHECKPOINT_POWER_LOCALIZATIONS:
                for language in ['en', 'zh-Hans']:
                    catalog = json.loads(json.dumps(original_catalog))
                    catalog['strings'][key]['localizations'][language]['stringUnit']['value'] = ''
                    self.read = lambda path, catalog=catalog: json.dumps(catalog) if path == 'Resources/Localizable.xcstrings' else original_read(path)
                    with self.assertRaises(AssertionError):
                        self.test_bilingual_keys_are_complete_and_match_catalog()
        finally:
            self.read = original_read

if __name__ == '__main__': unittest.main()
