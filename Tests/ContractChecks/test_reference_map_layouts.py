"""Finite W1/W2/C1 source contracts, never Apple rendering or runtime acceptance."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ReferenceMapLayoutContracts(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_walking_reuses_native_map_and_inset_and_one_sheet(self):
        value = self.read('App/WalkingNavigationView.swift')
        for token in ['.safeAreaInset(edge: .bottom', '.sheet(isPresented: $showsSteps', 'NavigationStack', '.presentationDetents(typeSize.isAccessibilitySize ? [.large]', 'if model?.route == nil { showsSteps = false }', 'model?.synchronize()', 'model?.setForeground(value == .active)', 'model?.pause()']:
            self.assertIn(token, value)
        self.assertEqual(value.count('.sheet('), 1)
        for forbidden in ['DragGesture', 'UserAnnotation', 'requestWhenInUseAuthorization', 'startUpdatingLocation', 'ActivityKit', 'URLSession']:
            self.assertNotIn(forbidden, value)
    def test_summary_only_projects_existing_authorized_data(self):
        source = self.read('App/ActiveDestinationSummary.swift')
        for token in ['let target: AuthorizedWalkingTarget?', 'let route: SearchRoutePreview?', 'let progress: WalkingNavigationProgress?', 'route.steps.indices.contains(stepIndex)', 'walking.arrivalBoundary', '.units(allowed: [.minutes]']:
            self.assertIn(token, source)
        for forbidden in ['@State', 'CLLocation', 'Task {', 'URLSession', '.start()', 'api/', 'MKDirections']:
            self.assertNotIn(forbidden, source)
    def test_steps_keep_provider_notices_and_read_live_route(self):
        source = self.read('App/WalkingNavigationView.swift').split('private struct WalkingStepsDetail:', 1)[1]
        for token in ['let model: WalkingNavigationCoordinator', 'if let route = model.route', 'provider.attribution', 'provider.advisoryNotices', 'walking.safety', 'walking.arrivalBoundary']:
            self.assertIn(token, source)
    def test_map_selection_and_query_gates_do_not_enable_location(self):
        source = self.read('App/SearchMapExplorerView.swift')
        self.assertIn('if mapEnabled {', source)
        self.assertNotIn('mapEnabled || reader.isOfflineExample', source)
        self.assertEqual(source.count('mapEnabled = true'), 1)
        self.assertIn('Button("searchMap.showMap") { mapEnabled = true }', source)
        for token in ['selectedID: selectedPin', 'mapEnabled = false; invalidate()', 'selectedPin = nil', 'gate.accepts(ticket, scope: reader.scope)', 'filter == query.filter', '.onChange(of: sortType)', 'mapEnabled = false; showsArea = false; showsFilters = false']:
            self.assertIn(token, source)
        self.assertIn('selectPlace("city-\\(row.id)", title: row.name)', source)
        self.assertIn('.accessibilityAddTraits', self.read('App/SearchMapCanvas.swift'))
    def test_card_retains_full_bleed_tokens_and_complete_text(self):
        source = self.read('App/QuestifyImageEntityCard.swift')
        for token in ['.padding(20)', 'cornerRadius:24', 'scrimOpacity', '0.94 : 0.86', 'scaledToFill()', '.lineLimit(nil)', '.fixedSize(horizontal:false,vertical:true)', '} else { placeholder }']:
            self.assertIn(token, source)
        for forbidden in ['questifyCardSurface', '.stroke(', '.strokeBorder(', '.border(', 'lineLimit(3)', 'minimumScaleFactor']:
            self.assertNotIn(forbidden, source)
        self.assertNotIn('questifyCardSurface', self.read('App/SearchMapComponents.swift'))
    def test_reference_keys_are_bilingual_and_catalog_matches(self):
        entries = json.loads(self.read('Resources/ReferenceMapLocalizations.fragment.json'))['strings']
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key, value in entries.items():
            self.assertEqual(catalog[key], value)
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
        source = self.read('App/ActiveDestinationSummary.swift') + self.read('App/WalkingNavigationView.swift')
        source = re.sub(r'\.accessibilityIdentifier\("[^"]*"\)', '', source)
        keys = set(re.findall(r'"(walking\.[A-Za-z.]+)"', source))
        self.assertFalse(keys - set(catalog))
    def test_no_added_dependency_and_authored_regressions_exist(self):
        package = self.read('Package.swift')
        for forbidden in ['Shimmer', 'exyte', 'Giphy', 'Kingfisher']:
            self.assertNotIn(forbidden, package)
        ui = self.read('Tests/AppUITests/WalkingNavigationFlowTests.swift')
        for test in ['testRoutingCanBeCancelledWithoutLateRouteAndReopened', 'testExpiredScopeDismissesStepsAndClearsDestination', 'testMaximumBilingualSummaryAndNativeStepsCanCloseAndReopen']:
            self.assertIn(test, ui)
        options = self.read('App/AccessibilityFixtureOptions.swift')
        self.assertIn('.accessibility5', options)
        self.assertIn('traitOverrides.accessibilityContrast = .high', self.read('Tests/AppUnitTests/ReferenceMapCardAppTests.swift'))


    def test_new_layout_identifiers_do_not_shadow_action_identifiers(self):
        view = self.read('App/SearchMapExplorerView.swift')
        self.assertNotIn('.accessibilityIdentifier("searchMap.filterRow")', view)
        self.assertIn('Text("searchMap.selectedPlace").accessibilityIdentifier("searchMap.selectedSummary")', view)
        self.assertNotIn('.id("selected-place-summary").accessibilityIdentifier', view)
        canvas = self.read('App/SearchMapCanvas.swift')
        self.assertIn('Text("searchMap.offlineMap").accessibilityIdentifier("searchMap.map")', canvas)
    def test_synthetic_routing_and_scope_changes_have_explicit_barriers(self):
        fixture = self.read('App/WalkingNavigationFixtureSupport.swift')
        self.assertIn('suspendNextCalculation = true', fixture)
        self.assertIn('withCheckedThrowingContinuation', fixture)
        self.assertIn('pending?.resume(throwing: CancellationError())', fixture)
        self.assertNotIn('delayNanoseconds', fixture)
        self.assertNotIn('didCalculate', fixture)
        self.assertNotIn('Task.sleep', fixture)
        self.assertTrue(fixture.startswith('#if DEBUG'))
        view = self.read('App/WalkingNavigationView.swift')
        self.assertIn('walking.fixture.expireScope', view)
        tests = self.read('Tests/AppUITests/WalkingNavigationFlowTests.swift')
        case = tests.split('func testExpiredScopeDismissesStepsAndClearsDestination()')[1].split('func testNearDestination')[0]
        self.assertLess(case.index('walking.steps.close'), case.index('tap("walking.fixture.expireScope")'))
        self.assertIn('timeout: 12', case)

if __name__ == '__main__': unittest.main()
