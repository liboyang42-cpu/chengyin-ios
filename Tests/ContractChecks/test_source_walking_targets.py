"""Offline source-contract regressions only; not Swift or backend execution."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class SourceWalkingTargetContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_city_visibility_proof_is_separate_from_provenance(self):
        source = self.read('Core/SourceWalkingTargetAuthorizer.swift')
        city = source.split('case .cityNode:', 1)[1].split('case .nearbyNode:', 1)[0]
        self.assertIn('node.status == 1', city)
        self.assertIn('node.poiID == reference.id', city)
        self.assertIn('node.coordinate != nil', city)
        evidence = city.split('throw WalkingTargetReadFailure.missingEvidence([', 1)[1].split('])', 1)[0]
        self.assertEqual(re.findall(r'"([A-Za-z]+)"', evidence), ['publicVisibility', 'coordinateDatum', 'countryRegion', 'authorityRevision', 'navigationIssuedAt', 'navigationExpiresAt'])
        self.assertIn('.businessCode(410)', city)
        self.assertIn('.httpStatus(410)', city)
        self.assertNotIn('return ', city)
    def test_nearby_keeps_registration_namespace_and_visibility_deficits(self):
        nearby = self.read('Core/SourceWalkingTargetAuthorizer.swift').split('case .nearbyNode:', 1)[1].split('case .merchant, .storyNode:', 1)[0]
        self.assertIn('reader.nearby(area: nearbyArea)', nearby)
        self.assertIn('$0.id == reference.id', nearby)
        self.assertNotIn('reader.cityNode(', nearby)
        self.assertNotIn('$0.nodeID', nearby)
        for field in ['playerNavigationVisibility', 'locked', 'coordinateDatum', 'countryRegion', 'authorityRevision', 'navigationExpiresAt']:
            self.assertIn('"' + field + '"', nearby)
    def test_candidate_wire_contract_is_documented_without_a_live_decoder(self):
        doc = self.read('docs/walking-navigation/source-target-contract.md')
        for marker in ['namespace: "roam_poi"', 'targetId: poiId', '"WGS84" | "GCJ02"', 'publicVisibility: "CURRENT_PUBLIC"', 'epoch-millisecond', 'navigationIssuedAt', 'navigationExpiresAt', 'not wired to the endpoint or decoded here']:
            self.assertIn(marker, doc)
        self.assertIn('no current-public-visibility predicates', doc)
        self.assertNotIn('mapper separately checks approved content and merchant visibility', doc)
        self.assertIn('unreviewed response supplies these keys', doc)
        self.assertNotIn('navigationEvidence', self.read('Core/SearchMapContracts.swift'))
    def test_cancel_reopen_and_delayed_boundary_tests_are_authored(self):
        tests = self.read('Tests/CoreTests/SourceWalkingTargetTests.swift')
        for name in ['testUnreviewedEvidenceKeysCannotConvertSuccessfulDetailIntoAuthority', 'testRemovedCityAndMissingGeometryRemainUnavailable', 'testPreviewCancelledDuringAuthorizationRejectsLateTargetBeforeProvider', 'testPreviewDropsSuspendedRouteAfterCancellationOrContextChange', 'testPreviewRechecksExpiryAfterSuspendedProviderReturns']:
            self.assertIn(name, tests)
        self.assertIn('CheckedContinuation<AuthorizedWalkingTarget, Error>', tests)
        self.assertIn('CheckedContinuation<SearchRoutePreview, Error>', tests)
    def test_preview_identity_fences_same_coordinate_target_changes(self):
        view = self.read('App/SearchRoutePreviewView.swift')
        self.assertIn('let reference: WalkingTargetReference?', view)
        self.assertIn('LoadIdentity(request: request, scope: scope, reference: navigationReference)', view)
        self.assertIn('reference = navigationReference, ticket = gate.begin(scope: scope)', view)
        self.assertEqual(view.count('navigationReference == reference else { return }'), 2)
    def test_preview_factory_never_constructs_location_provider(self):
        factory = self.read('App/NativeWalkingNavigationFactory.swift')
        preview = factory.split('func makePreviewPlanner(', 1)[1].split('func restore(', 1)[0]
        self.assertIn('reference.isValid, available', preview)
        self.assertIn('RegionBoundWalkingTargets', preview)
        self.assertIn('self?.context() == owner', preview)
        self.assertNotIn('makeLocation()', preview)

if __name__ == '__main__': unittest.main()
