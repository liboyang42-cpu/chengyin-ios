"""Supplementary source checks only. Recorder XCTest needs the Apple toolchain."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ManualMapCompositionContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_root_and_runtime_approval_default_off(self):
        root = self.read('App/AppCompositionRoot.swift')
        self.assertIn('manualMapReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval? = { _ in nil }', root)
        self.assertIn('deployment.reads.contains(.manualMap)', root)
        self.assertIn('approval.matches(context)', root)
        self.assertIn('currentApproval.revision == approval.revision', root)
        self.assertIn('manualMapSelection?.snapshot == selectedArea', root)
        self.assertIn('.init(deployment: .unconfigured,', self.read('App/RegionalLaunchConfiguration.swift'))
    def test_only_route_specific_query_exception(self):
        source = self.read('Core/ManualMapReadApproval.swift')
        for path in ['api/roam/pois', 'api/map/nearby', 'api/city/nodes']:
            self.assertIn('"' + path + '"', source)
        for denied in ['api/roam/reveal', 'api/roam/finish', 'api/roam/presence', 'api/merchant/public-detail', 'api/map/reverse-geocode']:
            self.assertNotIn('"' + denied + '"', source)
        for marker in ['request.httpBodyStream == nil', 'request.httpBody == nil', 'canonical.httpBody == body', 'fields[item.name] == nil', 'parts.fragment == nil', 'fields["latitude"] == String(area.coordinate.latitude)', 'fields["lng"] == String(area.coordinate.longitude)']:
            self.assertIn(marker, source)
    def test_both_real_readers_use_distinct_bound_transports(self):
        app = self.read('App/AppSession.swift')
        self.assertIn('transport.scopedForManualMap(searchMapSelection)', app)
        self.assertIn('transport.scopedForManualMap(roamMapSelection)', app)
        self.assertIn('didSet { roamMapSelection.select(roamArea) }', app)
        self.assertIn('manualAreaSelection: searchMapSelection', app)
        self.assertIn('viewerRevision: compositionViewerRevision', app)
        self.assertIn('areaRevision:self.roamMapSelection.revision', app)
    def test_current_manual_area_fences_ui_and_late_unauthorized(self):
        reading = self.read('Core/SearchMapReading.swift')
        self.assertEqual(reading.count('manualAreaRevision == areaRevision else'), 2)
        self.assertIn('reader.selectManualArea(selected)', self.read('App/SearchMapExplorerView.swift'))
        self.assertIn('originatingReadKey == readKey', self.read('App/SearchMapDetailViews.swift'))
        area = self.read('Core/ManualMapReadApproval.swift')
        self.assertIn('revision &+= 1', area)
    def test_no_device_permission_provider_or_production_expansion(self):
        new = self.read('Core/ManualMapReadApproval.swift')
        for forbidden in ['CLLocationManager(', 'requestWhenInUseAuthorization(', 'currentFix(', 'MKDirections(', 'URLSession', 'UserDefaults', 'Info.plist']:
            self.assertNotIn(forbidden, new)
        app_tests = self.read('Tests/AppUnitTests/ManualMapCompositionTests.swift')
        self.assertIn('final class DeviceSpy: RoamDeviceLocationProviding', app_tests)
        self.assertIn('XCTAssertEqual(wire.deviceOrProviderCalls, 0)', app_tests)
    def test_actual_composition_recorder_coverage_authored(self):
        source = self.read('Tests/AppUnitTests/ManualMapCompositionTests.swift')
        for name in ['testActualCompositionBothReadersManualAreaListToCorrelatedDetailAndFallback', 'testMissingGrantMissingApprovalGuestAndNoAreaMakeZeroMapDispatches', 'testUnsupportedLayersAndAllWritesRemainClosed', 'testExactQueryAndMultipartRejectDuplicatesExtraScopeWrongMethodAndMalformedValues', 'testAreaABAAndApprovalRevocationRejectLateSuccessAnd401WithoutExpiringSession', 'testAccountAndRoleRefreshABAFenceBothReaders', 'testAccountTokenABACancelsRetainedSearchAndRoamDetails', 'testWrongResponseNodeIDAndCurrentUnauthorizedAreNotAccepted']:
            self.assertIn(name, source)
        self.assertIn('AppSession(composition: root', source)

    def test_final_reader_authority_contains_current_approval_issuance(self):
        app = self.read('App/AppSession.swift')
        self.assertIn('private var currentManualMapApprovalRevision: UUID?', app)
        self.assertIn('composition.manualMapReadApproval(context), approval.matches(context)', app)
        self.assertIn('manualMapApprovalRevision: currentManualMapApprovalRevision', app)
        self.assertIn('manualMapApprovalRevision:self.currentManualMapApprovalRevision', app)
        for file in ['Core/RoamReading.swift', 'Core/SearchMapReading.swift']:
            self.assertIn('public let manualMapApprovalRevision: UUID?', self.read(file))
    def test_manual_read_owner_cancels_real_reader_work(self):
        owner = self.read('Core/ManualMapReadApproval.swift')
        for marker in ['final class ManualMapReadTaskOwner', 'await withTaskCancellationHandler', 'currentTask.cancel()', 'generation == capturedGeneration']:
            self.assertIn(marker, owner)
        for file in ['App/RoamBrowserView.swift', 'App/RoamItemDetailView.swift', 'App/SearchMapExplorerView.swift', 'App/SearchMapDetailViews.swift']:
            source = self.read(file)
            self.assertIn('await readOwner.run { await performLoad() }', source)
            self.assertIn('.onDisappear { readOwner.deactivate();', source)
            self.assertIn('readOwner.start { await performLoad() }', source)
        self.assertIn('@State private var originatingIdentity: RoamReadIdentity?', self.read('App/RoamItemDetailView.swift'))
        self.assertIn('_originatingReadKey = State(initialValue:', self.read('App/SearchMapDetailViews.swift'))
    def test_transport_replacement_preserves_approval_callbacks_and_area(self):
        root = self.read('App/AppCompositionRoot.swift')
        self.assertIn('func replacingUnderlying(_ underlying: any HTTPTransport)', root)
        self.assertIn('copy(underlying: underlying, manualMapSelection: manualMapSelection)', root)
        self.assertIn('transport.current = { self.current() }', root)
        self.assertIn('ownerDraftReadApproval: ownerDraftReadApproval, manualMapReadApproval: manualMapReadApproval', root)
        self.assertIn('return compositionTransport.replacingUnderlying(injected)', self.read('App/AppSession.swift'))
        self.assertIn('testReplacingTransportPreservesManualAreaApprovalAndCurrentIdentityCallbacks', self.read('Tests/AppUnitTests/ManualMapCompositionTests.swift'))
    def test_literal_plus_query_encoding_matches_servlet_interpretation(self):
        for file in ['Core/ManualMapReadApproval.swift', 'Core/SearchMapService.swift']:
            self.assertIn('replacingOccurrences(of: "+", with: "%2B")', self.read(file))
    def test_adversarial_review_coverage_is_authored_not_runtime_evidence(self):
        source = self.read('Tests/AppUnitTests/ManualMapCompositionTests.swift')
        for name in ['testEncodedTraversalAmbiguousQueriesAndNumericBoundsDoNotDispatch',
                     'testBothReaderFinalBoundariesRejectApprovalRevocationAndReissueBeforeDecodeReturns',
                     'testNormalCompositionApprovalReissueChangesRetainedReaderLifetimes',
                     'testOwnedCancellationDropsLate401WithoutExpiringCurrentSession',
                     'testRetiredOwnerCompletionCannotClearReplacementTask',
                     'testOwnedReadPropagatesParentCancellation',
                     'testManualApprovalExactAuthorityExpiryAndMissingIssuanceFailClosed',
                     'testGuestPublicCityLayerAndLiteralPlusFilterPreserveFallbackAndExactWire']:
            self.assertIn(name, source)

if __name__ == '__main__': unittest.main()
