"""Focused source contracts, not Swift compilation or runtime acceptance."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class PlayRouteMapContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/PlayRouteMapPresentation.swift').read_text()
        cls.app = (ROOT / 'App/PlayRouteMapView.swift').read_text()
        cls.host = (ROOT / 'App/PlayExperienceView.swift').read_text()
        cls.fixture = (ROOT / 'App/PlayRouteMapFixture.swift').read_text()
        cls.ui = '\n'.join((ROOT / ('Tests/AppUITests/' + name + '.swift')).read_text() for name in ['PlayRouteMapFlowTests', 'PlayRouteMapContinuationFlowTests'])
        cls.strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']

    def test_projection_has_only_safe_visible_rows(self):
        self.assertIn('let nodes = snapshot.visibleNodes', self.core)
        self.assertNotIn('snapshot.result.nodes', self.core)
        for value in ['name: locked ? nil', 'address: locked ? nil', 'coordinate: locked ? nil']:
            self.assertIn(value, self.core)
        projection = self.core.split('public struct PlayRouteMapSelection:', 1)[0]
        for value in ['storyText', 'questionImage', 'questionAudio', 'options:', 'lockReason', '.npc']:
            self.assertNotIn(value, projection)
        self.assertIn('state == .current || state == .completed', self.core)

    def test_only_orientation_and_authoritative_current(self):
        self.assertIn('== .cityOrientation', self.core)
        self.assertIn('snapshot.route?.currentNodeID, snapshot.route?.recommendedNodeID', self.core)
        self.assertIn('first(where: eligibleIDs.contains)', self.core)
        self.assertIn('snapshot.availability == .active || snapshot.availability == .completed', self.core)

    def test_coordinates_are_checked_and_gaps_not_joined(self):
        for value in ['latitude.isFinite', 'longitude.isFinite', '(-90...90).contains(latitude)', '(-180...180).contains(longitude)', 'zip(stops, stops.dropFirst())', 'guard let a = start.coordinate, let b = end.coordinate else { return nil }']:
            self.assertIn(value, self.core)

    def test_snapshot_and_lifetime_selection_check_at_tap_and_destination(self):
        for value in ['context == self.context', 'snapshot == self.snapshot', 'private let context: PlayInteractionContext']:
            self.assertIn(value, self.core)
        for value in ['model.interactionContext == context', 'model.snapshot == snapshot', 'choice.nodeID(in: model)', '.onChange(of: context)', '.onChange(of: model.snapshot)', 'owner == PlayExperiencePresentationKey(model: model)', 'model.phase == .reviewing || model.phase == .submitting']:
            self.assertIn(value, self.app)
        self.assertIn('showRouteMap = false', self.host)

    def test_map_and_equivalent_list_share_projection_without_location_or_routing(self):
        self.assertIn('ForEach(presentation.stops)', self.app)
        self.assertIn('ForEach(presentation.mappedStops)', self.app)
        self.assertIn('MapPolyline(', self.app)
        self.assertIn('dash: [6, 5]', self.app)
        for value in ['CLLocationManager', 'MKDirections', 'CLGeocoder', 'UserAnnotation', 'MapUserLocationButton', 'URLSession', 'PlatformExternalMaps', 'requestWhenInUseAuthorization', 'NetworkGrant']:
            self.assertNotIn(value, self.app + self.core)
        self.assertNotIn('model.submit(', self.app)
        self.assertNotIn('model.review(', self.app)

    def test_accessibility_and_bilingual_disclaimer(self):
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', self.app)
        self.assertIn('minHeight: 44', self.app)
        self.assertNotIn('.lineLimit(', self.app)
        self.assertNotIn('.animation(', self.app)
        keys = set(re.findall(r'"(playRoute\.[A-Za-z]+)"', self.app + self.host))
        keys -= {'playRoute.screen', 'playRoute.selectionUnavailable', 'playRoute.refresh', 'playRoute.toggleMap'}
        keys |= {'playRoute.state.' + state for state in ['current', 'completed', 'available', 'locked', 'unknown']}
        for key in keys:
            with self.subTest(key=key):
                entry = self.strings[key]['localizations']
                self.assertEqual(set(entry), {'en', 'zh-Hans'})
                self.assertTrue(all(value['stringUnit']['value'] for value in entry.values()))
        self.assertIn('not walking directions', self.strings['playRoute.explanation']['localizations']['en']['stringUnit']['value'])
        self.assertIn('不采集你的位置', self.strings['playRoute.explanation']['localizations']['zh-Hans']['stringUnit']['value'])

    def test_fixture_is_additive_debug_read_only_and_ui_journeys_authored(self):
        self.assertTrue(self.fixture.startswith('#if DEBUG'))
        self.assertIn('scenario == "routeMapReview" ? [.reads, .classicCompletion] : [.reads]', self.fixture)
        self.assertIn('PlayExperienceView(model: model)', self.fixture)
        self.assertIn('PlayRecoveryRecordingTransport()', self.fixture)
        self.assertEqual(len(re.findall(r'    func test\w+\(', self.ui)), 8)
        for value in ['routeMapMissing', 'playRoute.fixture.read', 'playRoute.fixture.account', '--uitesting-max-text', 'assertFixtureEnvironment', 'playx.node.701', 'playRoute.back', 'mode2']:
            self.assertIn(value, self.ui)

if __name__ == '__main__':
    unittest.main()
