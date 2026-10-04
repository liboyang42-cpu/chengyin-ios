"""Presentation-only source evidence; not MapKit rendering/Apple runtime acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MapVisualFoundationTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_public_canvases_share_muted_style_without_blanket_poi_suppression(self):
        for path in ['App/QuestifyDensityMap.swift', 'App/RoamMapView.swift', 'App/WalkingNavigationView.swift']:
            source = self.read(path)
            self.assertIn('.mapStyle(QuestifyMapAppearance.baseStyle)', source)
            self.assertNotIn('.excludingAll', source)
            self.assertNotIn('.preferredColorScheme', source)
        source = self.read('App/SearchMapCanvas.swift')
        self.assertIn('static let version = 1', source)
        self.assertIn('emphasis: .muted', source)
        self.assertIn('pointsOfInterest: .excluding([.nightlife, .store, .bakery])', source)
        self.assertIn('showsTraffic: false', source)

    def test_selected_markers_preserve_identity_and_noncolor_cue(self):
        source = self.read('App/SearchMapCanvas.swift')
        self.assertIn('Image(systemName: symbol)', source)
        self.assertIn('Image(systemName: "checkmark.circle.fill")', source)
        self.assertIn('lineWidth: selected ? 3', source)
        self.assertIn('contrast == .increased', source)
        self.assertIn('@ScaledMetric(relativeTo: .body)', source)
        self.assertIn('max(44, diameter)', source)
        self.assertNotIn('selectedID ? "checkmark"', source)
        self.assertIn('QuestifyMapPinSymbol(symbol: pin.symbol, selected: pin.id == selectedID)', source)
        density = self.read('App/QuestifyDensityMap.swift')
        self.assertIn('QuestifyDensityMap(area: area, pins: pins, selectedID: selectedID', source)
        self.assertIn('QuestifyMapPinSymbol(symbol: anchor.symbol, selected: anchor.id == selectedID)', density)
        self.assertIn('.accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])', source)
        self.assertIn('.accessibilityAddTraits(group.members.contains(where: { $0.id == selectedID }) ? .isSelected : [])', density)
        self.assertIn('QuestifyMapPinSymbol(symbol: item.symbol)', self.read('App/RoamMapView.swift'))

    def test_route_casing_below_existing_route_and_target(self):
        for path in ['App/QuestifyDensityMap.swift', 'App/WalkingNavigationView.swift']:
            source = self.read(path)
            self.assertLess(source.index('.stroke(QuestifyMapAppearance.routeCasing'), source.index('.stroke(QuestifyMapAppearance.route,'))
        self.assertIn('dash: [7, 4]', self.read('App/QuestifyDensityMap.swift'))
        self.assertIn('Marker(target.title', self.read('App/WalkingNavigationView.swift'))

    def test_style_has_no_network_location_or_business_commands(self):
        style = self.read('App/SearchMapCanvas.swift').split('enum QuestifyMapAppearance', 1)[1]
        for forbidden in ['URLSession', 'MKDirections', 'CLLocationManager', 'Task {', '.onAppear', '.onChange', 'UserAnnotation', 'requestAuthorization', 'http']:
            self.assertNotIn(forbidden, style)
        self.assertIn('traits.userInterfaceStyle == .dark ? .black : .white', style)
        self.assertIn('Color(UIColor.systemBackground)', style)

    def test_authored_ui_fixture_is_offline_and_has_both_appearance_cases(self):
        source = self.read('App/ReferenceMapCardFixtureView.swift').split('struct MapMarkerStyleFixtureView', 1)[1]
        self.assertIn('offline: true', source)
        self.assertNotIn('Map {', source)
        tests = self.read('Tests/AppUITests/SearchMapFlowTests.swift')
        self.assertIn('testMapMarkerSelectionKeepsDistinctObjectsInLightAppearance', tests)
        self.assertIn('testMapMarkerSelectionKeepsDistinctObjectsInDarkLargeText', tests)
        self.assertIn('XCTAssertTrue(activity.isSelected); XCTAssertFalse(merchant.isSelected)', tests)

    def test_opaque_marker_and_route_token_contrast(self):
        # Numeric token check only, not basemap pixels or device appearance evidence.
        palette = self.read('App/QuestifyPalette.swift')
        self.assertIn('red:196.0/255,green:181.0/255,blue:253.0/255', palette)
        self.assertIn('red:109.0/255,green:40.0/255,blue:217.0/255', palette)
        source = self.read('App/SearchMapCanvas.swift')
        self.assertIn('red: 0.40, green: 0.72, blue: 1.0', source)
        self.assertIn('red: 0.0, green: 0.28, blue: 0.65', source)
        def luminance(rgb):
            linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
            return sum(a*b for a,b in zip(linear, [0.2126, 0.7152, 0.0722]))
        def ratio(a, b):
            light,dark = sorted([luminance(a), luminance(b)], reverse=True)
            return (light + 0.05) / (dark + 0.05)
        self.assertGreater(ratio([109/255,40/255,217/255], [1,1,1]), 4.5)
        self.assertGreater(ratio([196/255,181/255,253/255], [0,0,0]), 4.5)
        self.assertGreater(ratio([0,0.28,0.65], [1,1,1]), 4.5)
        self.assertGreater(ratio([0.40,0.72,1], [0,0,0]), 4.5)
