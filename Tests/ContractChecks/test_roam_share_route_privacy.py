"""Focused source wiring checks; these do not execute Swift or an iOS application."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class RoamShareRoutePrivacySourceTests(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/RoamHistoryShareView.swift').read_text()
        self.math = (ROOT / 'Core/RoamExperienceMath.swift').read_text().split('public enum RoamShareRoutePrivacy {', 1)[1]

    def test_preview_and_export_use_same_card(self):
        self.assertIn('                card\n', self.view)
        self.assertIn('ImageRenderer(content: card.frame', self.view)
        self.assertIn('if includeRoute { privateRoute }', self.view)
        self.assertIn('RoamShareRoutePrivacy.sketch(for: record)', self.view)
        self.assertNotIn('RoamRouteSketchView(record:', self.view)

    def test_no_poi_or_raw_route_rendering(self):
        self.assertIn('RoamRouteSketch(track: clippedTrack(record.track), places: [])', self.math)
        self.assertNotIn('record.pois', self.view)
        self.assertNotIn('record.track.enumerated()', self.view)
        self.assertIn('sketch.track.enumerated()', self.view)

    def test_export_binds_full_record_and_current_choice(self):
        self.assertIn('if let image, renderedRecord == record, renderedIncludeRoute == includeRoute {', self.view)
        self.assertIn('renderedRecord = image == nil ? nil : record', self.view)
        self.assertIn('renderedIncludeRoute = includeRoute', self.view)

    def test_owner_record_change_and_dismissal_invalidate_export(self):
        self.assertIn('.onChange(of: record) { _, _ in includeRoute = false; invalidateImage() }', self.view)
        self.assertIn('.onDisappear { invalidateImage() }', self.view)
        self.assertIn('image = nil; renderedRecord = nil; renderingFailed = false', self.view)

    def test_route_opt_in_remains_default_off(self):
        self.assertIn('@State private var includeRoute = false', self.view)
        self.assertIn('onChange(of: includeRoute) { _, _ in invalidateImage() }', self.view)

    def test_length_based_clip_and_degenerate_fail_closed(self):
        self.assertIn('public static let endpointFraction = 0.1', self.math)
        self.assertIn('RoamExperienceMath.distanceMeters(a.coordinate, b.coordinate)', self.math)
        self.assertIn('let start = total * endpointFraction, end = total - start', self.math)
        self.assertIn('guard total.isFinite, total > 0 else { return [] }', self.math)
        self.assertNotRegex(self.math, r'return\s+track\b')

    def test_actual_insets_and_retained_length_fail_closed(self):
        self.assertIn('let startInset = RoamExperienceMath.distanceMeters(track[0].coordinate, result[0].coordinate)', self.math)
        self.assertIn('let endInset = RoamExperienceMath.distanceMeters(track[track.count - 1].coordinate, result[result.count - 1].coordinate)', self.math)
        self.assertIn('guard startInset.isFinite, startInset > 0, endInset.isFinite, endInset > 0 else { return [] }', self.math)
        self.assertIn('guard retainedLength.isFinite, retainedLength > 0 else { return [] }', self.math)
        self.assertLess(self.math.index('guard retainedLength.isFinite'), self.math.index('return result'))

    def test_no_external_or_history_write_capability(self):
        for forbidden in ['URLSession', 'CLLocationManager', 'UserDefaults', 'prependSettled', 'publishShareSnapshot', 'saveImageToPhotosAlbum']:
            self.assertNotIn(forbidden, self.math + self.view)

    def test_native_tests_cover_edges(self):
        tests = (ROOT / 'Tests/CoreTests/RoamShareRoutePrivacyTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test\w+\(', tests)), 17)
        self.assertIn('testVeryShortTrackDoesNotFallBackToOriginal', tests)
        self.assertIn('testSketchNeverIncludesOriginalPOIsAndRecordIsUnchanged', tests)

if __name__ == '__main__':
    unittest.main()
