"""Offline source checks for the shipping preview loader; not Swift execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WalkingPreviewRequestContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_origin_context_is_exact_explicit_and_never_relabelled(self):
        source = self.read('Core/SearchRoutePreview.swift')
        builder = source.split('public static func walkingPreview(', 1)[1].split('\n    }', 1)[0]
        self.assertIn('originContext: WalkingCoordinate?', builder)
        self.assertIn('guard let originContext, originContext.point == origin else { return nil }', builder)
        self.assertIn('datum: originContext.datum, region: originContext.region', builder)
        self.assertIn('mode: .walking', builder)
        for forbidden in ['.wgs84', '.gcj02', 'RuntimeLocationProjection', 'Locale', 'market', 'target.coordinate']:
            self.assertNotIn(forbidden, builder)

    def test_view_and_tests_use_the_same_shipping_loader(self):
        view = self.read('App/SearchRoutePreviewView.swift')
        self.assertIn('@State private var loader = SearchRoutePreviewLoader()', view)
        self.assertIn('await loader.load(owner)', view)
        self.assertIn('var previewOriginContext: WalkingCoordinate? = nil', view)
        self.assertIn('SearchRouteRequest.walkingPreview(origin: origin, originContext: previewOriginContext', view)
        self.assertIn('if owner != nil, let route = loader.route', view)
        self.assertIn('else if owner != nil, loader.failed', view)
        self.assertNotIn('gate.begin(', view)
        self.assertNotIn('activePlanner?.cancel()', view)
        self.assertNotIn('private func accepts(', view)

    def test_async_work_can_only_consume_shared_current_owner_before_any_mutation(self):
        source = self.read('Core/SearchRoutePreview.swift')
        load = source.split('public func load(_ captured: Owner,', 1)[1].split('public struct SearchRouteStep', 1)[0]
        guard = load.index('guard accepts(captured) else { return }')
        for mutation in ['attempt = ticket', 'previous?.cancel()', 'route = nil', 'makePlanner()']:
            self.assertLess(guard, load.index(mutation))
        self.assertLess(load.index('guard let requested = captured.input.request'), load.index('makePlanner()'))
        for forbidden in ['replaceOwner(', 'appear(', 'update(', 'owner =']:
            self.assertNotIn(forbidden, load.replace('owner ==', 'owner_equals'))
        self.assertIn('owner == captured && (candidate == nil || candidate == attempt) && !Task.isCancelled', source)
        self.assertEqual(load.count('guard accepts(captured, attempt: ticket) else { return }'), 2)
        self.assertIn('defer { if owner == captured, attempt == ticket { activePlanner = nil } }', load)

    def test_synchronous_input_binding_drives_task_key_and_retry_captures_owner(self):
        view = self.read('App/SearchRoutePreviewView.swift')
        for marker in ['let input = self.input', 'let owner = loader.capture(for: input)',
                       '.onAppear { loader.appear(input) }',
                       '.onChange(of: input) { _, current in loader.update(current) }',
                       '.task(id: owner)', '.onDisappear { loader.disappear() }',
                       'guard let retryOwner = loader.capture(for: input) else { return }',
                       'Task { await load(retryOwner) }']:
            self.assertIn(marker, view)
        task = view.split('.task(id: owner)', 1)[1].split('.onDisappear', 1)[0]
        self.assertNotIn('.appear(', task)
        self.assertNotIn('.update(', task)
        self.assertIn('guard let owner else { return }', task)

    def test_shared_owner_changes_for_input_and_appearance_without_reactivating_disappeared_view(self):
        source = self.read('Core/SearchRoutePreview.swift')
        self.assertIn('@MainActor @Observable public final class SearchRoutePreviewLoader', source)
        self.assertIn('public private(set) var owner: Owner?', source)
        self.assertIn('public func appear(_ input: Input) { replaceOwner(.init(input: input, generation: UUID())) }', source)
        self.assertIn('guard let owner, owner.input != input else { return }', source)
        self.assertIn('public func disappear() { replaceOwner(nil) }', source)
        self.assertIn('guard let owner, owner.input == input else { return nil }', source)
        reset = source.split('private func replaceOwner(', 1)[1].split('private func accepts', 1)[0]
        self.assertLess(reset.index('owner = next; attempt = UUID()'), reset.index('previous?.cancel()'))

    def test_actual_loader_negative_controls_include_same_appearance_changes_and_late_results(self):
        tests = self.read('Tests/AppUnitTests/WalkingNavigationAppTests.swift')
        for name in ['testShippingLoaderQueuedRetryAfterDisappearCannotStartProviderWithoutTaskCancellation',
                     'testShippingLoaderSameAppearanceInputChangeRejectsQueuedOldRetryBeforeCancellingNewRoute',
                     'testShippingLoaderLateOldSuccessOrFailureCannotReplaceNewInputRoute',
                     'testShippingLoaderAppearanceAndInputBindingSupplyLoadKeyInEitherCallbackOrder',
                     'testShippingPreviewLoaderRejectsStraightLineResult',
                     'testShippingLoaderCancelledTaskCannotPublishSuccessOrFailureForSameOwner']:
            self.assertIn(name, tests)
        for marker in ['await loader.load(oldOwner)', 'loader.update(second)', 'XCTAssertFalse(Task.isCancelled)',
                       'XCTAssertEqual(oldPlannerCreations, 0)', 'XCTAssertEqual(loader.route, accepted)',
                       'XCTAssertEqual(harness.directions.cancels, 0)', 'XCTAssertFalse(loader.failed)',
                       'for variant in 0..<3', 'for oldFails in [false, true]']:
            self.assertIn(marker, tests)
        queued = tests.split('func testShippingLoaderSameAppearanceInputChangeRejectsQueuedOldRetryBeforeCancellingNewRoute', 1)[1].split('func testShippingLoaderLateOldSuccess', 1)[0]
        self.assertNotRegex(queued, r'(?m)^\s*guard ')
        self.assertNotIn('lifetime.accepts', tests)

    def test_typed_fixture_is_separate_from_navigation_suspension_scenario(self):
        fixture = self.read('App/SearchMapFixtureSupport.swift')
        self.assertIn('entry == "walking" || entry == "walkingPreview"', fixture)
        self.assertIn('previewOriginContext: previewOriginContext', fixture)
        context = fixture.split('private var previewOriginContext: WalkingCoordinate?', 1)[1].split('private var syntheticArea', 1)[0]
        self.assertIn('guard entry == "walkingPreview" else { return nil }', context)
        self.assertIn('WalkingCoordinate(point: syntheticArea.coordinate, datum: .wgs84, region: "US")', context)
        for path in ['App/SearchMapDetailViews.swift', 'App/SearchMapExplorerView.swift']:
            self.assertNotIn('previewOriginContext:', self.read(path))

    def test_factory_adapter_tests_still_cover_authority_coordinates_failure_and_location(self):
        tests = self.read('Tests/AppUnitTests/WalkingNavigationAppTests.swift')
        for name in ['testPreviewViewWithoutOriginContextOrWithMismatchedOriginIsUnavailable',
                     'testPreviewViewRequestReachesAuthorizedFactoryAndMapKitAdapterWithoutLocation',
                     'testPreviewOriginDatumAndRegionMismatchNeverReachDirections',
                     'testPreviewReauthorizesTargetAndRejectsDestinationMismatchBeforeDirections',
                     'testPreviewProviderErrorsRemainUnavailableWithoutStraightLineFallback',
                     'testPreviewCancellationRejectsLateDirectionsAndReopenUsesFreshPlanner',
                     'testPreviewContextChangeRejectsLateDirectionsAndNewFactoryWork']:
            self.assertIn(name, tests)
        self.assertIn('return try XCTUnwrap(view.request)', tests)
        self.assertIn('MapKitWalkingRoutePlanner(verifiedRegions: regions, executor: directions)', tests)
        self.assertIn('XCTAssertEqual(harness.locationCreations, 0)', tests)

    def test_no_permissions_live_requests_gameplay_mutation_or_coordinate_conversion_added(self):
        source = self.read('App/SearchRoutePreviewView.swift') + self.read('Core/SearchRoutePreview.swift')
        for forbidden in ['CLLocationManager', 'requestWhenInUseAuthorization', 'requestAlwaysAuthorization',
                          'startUpdatingLocation', 'MKDirections(', 'URLSession', 'api/play/arrive',
                          'completeNode(', 'RuntimeLocationProjection']:
            self.assertNotIn(forbidden, source)

    def test_delivery_corrects_historical_audit_and_retains_acceptance_limits(self):
        doc = self.read('docs/walking-navigation/preview-request.md')
        for marker in ['c95737b4c54881a7492ca72bd31f68749304d1d1', 'straightLine', 'MKDirections',
                       'gcj02', 'region=nil', 'NOT_RUN', 'walkingPreview', 'source-target-contract.md', 'R2']:
            self.assertIn(marker, doc)


if __name__ == '__main__':
    unittest.main()
