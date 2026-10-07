"""Source integration evidence only; no compiler, MapKit or UI execution claim."""
import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class PlayRouteMapCameraContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/PlayRouteMapCamera.swift').read_text()
        cls.host = (ROOT / 'App/PlayRouteMapView.swift').read_text()
        cls.controls = (ROOT / 'App/PlayRouteMapCameraControls.swift').read_text()
        cls.tests = '\n'.join((ROOT / ('Tests/AppUITests/' + name + '.swift')).read_text() for name in ['PlayRouteMapCameraFlowTests', 'PlayRouteMapCameraFallbackFlowTests'])

    def test_bound_camera_uses_existing_safe_projection_and_fit(self):
        for text in ['PlayRouteMapPresentation(snapshot: snapshot)', 'presentation.mappedStops', 'presentation.currentNodeID', 'MapMarkerDensity.fit(', 'stop.coordinate.map { [$0] } ?? []', '.missingCoordinates : .unsupportedExtent']:
            self.assertIn(text, self.core)
        self.assertNotIn('snapshot.result.nodes', self.core)
        self.assertIn('Map(position: $cameraPosition', self.host)
        self.assertIn('if let fit = decision.fit', self.host)
        self.assertIn('cameraPosition = .region', self.host)

    def test_current_and_preview_are_distinct_and_existing_task_buttons_stay_exact(self):
        self.assertIn('public enum Action: Equatable { case overview, current, preview(Int) }', self.core)
        self.assertIn('presentation.stops.first(where: { $0.id == id && $0.state == .current })', self.core)
        self.assertIn('Button { choose(stop.id, snapshot: snapshot, context: context) } label: { stopLabel(stop) }', self.host)
        self.assertIn('Button("playRoute.openCurrent") { choose(id, snapshot: snapshot, context: context) }', self.host)
        self.assertIn('if preview.canOpen', self.controls)
        self.assertIn('onOpen: { choose($0, snapshot: snapshot, context: context) }', self.host)
        self.assertIn('.accessibilityAddTraits(inspecting ? .isSelected : [])', self.host)

    def test_requests_and_previews_require_exact_read_and_visible_lifetime(self):
        for text in ['private let context: PlayInteractionContext', 'guard read == current else { return nil }', 'guard visible, request.revision == revision else { return nil }', 'guard request.read == current else { return nil }']:
            self.assertIn(text, self.core)
        for text in ['let renderedGate = cameraGate', 'cameraGate.consume(request, current: cameraRead)', '.onChange(of: cameraRead)', 'cameraGate.disappear()', 'cameraPreview?.resolve(current: cameraRead)']:
            self.assertIn(text, self.host)

    def test_inspection_does_not_add_providers_writes_or_authority(self):
        for text in ['URLSession', 'CLLocationManager', 'MKDirections', 'CLGeocoder', 'NetworkGrant', 'WalkingNavigationCoordinator', 'model.submit(', 'model.review(', 'model.startRun(']:
            self.assertNotIn(text, self.core + self.controls)
        self.assertNotIn('model.load(', self.core + self.controls)
        self.assertIn('presentation.stops.filter { $0.state != .locked }', self.controls)
        self.assertNotIn('.lineLimit(', self.controls)
        self.assertIn('.frame(minHeight: 44', self.controls)

    def test_all_added_labels_are_bilingual_with_explicit_no_camera_fallback(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        keys = ['showControls', 'hideControls', 'title', 'notice', 'overview', 'current', 'choose', 'preview', 'openTask', 'issue.missingCoordinates', 'issue.unsupportedExtent']
        for suffix in keys:
            entry = catalog['playRouteCamera.' + suffix]['localizations']
            self.assertEqual(set(entry), {'en', 'zh-Hans'})
            self.assertTrue(all(v['stringUnit']['value'] for v in entry.values()))
        self.assertIn('current task stays the same', catalog['playRouteCamera.notice']['localizations']['en']['stringUnit']['value'])
        self.assertIn('相机保持不变', catalog['playRouteCamera.issue.missingCoordinates']['localizations']['zh-Hans']['stringUnit']['value'])

    def test_only_new_camera_journeys_are_in_new_suite(self):
        self.assertEqual(len(re.findall(r'    func test\w+\(', self.tests)), 5)
        for text in ['playRouteCamera.current', 'playRouteCamera.overview', 'playRouteCamera.choose', 'playRouteCamera.openTask', 'routeMapFocusMissingCurrent', 'routeMapFocusPolar', 'playRoute.fixture.read', 'assertFixtureEnvironment']:
            self.assertIn(text, self.tests)
        self.assertNotIn('func testCurrentCompletedAndOldTaskEntrancesRemainReachable', self.tests)

if __name__ == '__main__': unittest.main()
