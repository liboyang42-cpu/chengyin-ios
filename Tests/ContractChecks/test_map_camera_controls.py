"""Presentation source guards only; Swift, MapKit and accessibility execution remain separate."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MapCameraControlsTests(unittest.TestCase):
    def setUp(self):
        self.ui = (ROOT / 'App/QuestifyDensityMap.swift').read_text()
        self.core = (ROOT / 'Core/MapMarkerDensity.swift').read_text()

    def test_explicit_controls_preserve_scale_and_do_not_add_location(self):
        self.assertIn('MapCompass().mapControlVisibility(.visible)', self.ui)
        self.assertIn('MapScaleView()', self.ui)
        for forbidden in ['MapUserLocationButton', 'UserAnnotation', 'CLLocationManager',
                          'requestWhenInUseAuthorization', 'MKDirections', 'URLSession']:
            self.assertNotIn(forbidden, self.ui + self.core)

    def test_focus_is_explicit_and_remains_outside_map_frame(self):
        self.assertLess(self.ui.index('}.frame(height: mapHeight)'), self.ui.index('if selectedID != nil { focusControl }'))
        control = self.ui.split('private var focusControl:', 1)[1].split('private func groups(', 1)[0]
        self.assertIn('Button {', control)
        self.assertIn('focusGate.consume(request)', control)
        self.assertIn('applyCameraFit(fit)', control)
        self.assertNotIn('onSelect', control)
        self.assertIn('.frame(minHeight: 44)', control)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', control)
        self.assertIn('.disabled(request == nil)', control)
        self.assertIn('Text("mapCamera.focusUnavailable")', control)

    def test_camera_movement_is_never_triggered_by_selection_refresh_or_drag(self):
        changes = self.ui.split('.onChange(of: focusInput)', 1)[1].split('private var focusControl:', 1)[0]
        self.assertIn('currentFocusInput = value', changes)
        self.assertIn('focusGate.invalidate()', changes)
        self.assertNotIn('position =', changes)
        self.assertNotIn('applyCameraFit', changes)
        self.assertIn('.onMapCameraChange(frequency: .continuous) { _ in cameraRevision &+= 1 }', self.ui)
        self.assertEqual(self.ui.count('position = .region'), 1)
        self.assertEqual(self.ui.count('applyCameraFit(fit)'), 2)  # Explicit focus or group expansion.
        self.assertNotIn('withAnimation', self.ui)

    def test_focus_snapshot_and_one_shot_revision_fence_stale_actions(self):
        for value in ['let area: RoamSearchArea', 'let pins: [SearchMapPin]', 'let selectedID: String?',
                      'let renderedInput = focusInput', 'renderedInput == currentFocusInput',
                      '.onDisappear { focusGate.invalidate() }']:
            self.assertIn(value, self.ui)
        for value in ['matches.count == 1', 'MapMarkerDensity.fit([target.coordinate])',
                      'guard request.revision == revision else { return nil }',
                      'invalidate()\n            return request.fit']:
            self.assertIn(value, self.core)

    def test_existing_search_and_roam_share_the_controlled_map(self):
        for path in ['App/SearchMapCanvas.swift', 'App/RoamMapView.swift']:
            self.assertIn('QuestifyDensityMap(area: area, pins: pins, selectedID: selectedID', (ROOT / path).read_text())
        self.assertIn('.id(MapPresentationIdentity(area: area, scope: reader.scope))',
                      (ROOT / 'App/SearchMapExplorerView.swift').read_text())
        self.assertIn('.id(renderedKey)', (ROOT / 'App/RoamBrowserView.swift').read_text())

    def test_camera_strings_cover_both_languages_without_claiming_user_location(self):
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['mapCamera.focusSelected', 'mapCamera.focusHint', 'mapCamera.focusUnavailable']:
            for language in ['en', 'zh-Hans']:
                self.assertTrue(strings[key]['localizations'][language]['stringUnit']['value'])
        label = strings['mapCamera.focusSelected']['localizations']['en']['stringUnit']['value']
        self.assertEqual(label, 'Show selected place')
