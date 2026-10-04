"""Offline semantic/source guards. Swift algorithm tests are authored separately.
These assertions are not Swift execution, MapKit rendering or runtime acceptance.
"""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class MapMarkerDensityContracts(unittest.TestCase):
    def setUp(self):
        self.ui = (ROOT/'App/QuestifyDensityMap.swift').read_text()
        self.core = (ROOT/'Core/MapMarkerDensity.swift').read_text()
    def test_actual_screen_projection_and_dynamic_density(self):
        for value in ['proxy.convert(coordinate(pin.coordinate), to: .local)', '.onMapCameraChange(frequency: .continuous)', 'point.x >= 0', 'point.y >= 0', 'point.x <= size.width', 'point.y <= size.height', 'max(28, clusterExtra)']:
            self.assertIn(value, self.ui)
        self.assertIn('hypot($0.x - point.x, $0.y - point.y) < diameter', self.core)
    def test_fresh_inputs_and_scope_reset(self):
        for value in ['let supplied = currentPins', 'expandedSnapshot == snapshot', 'counts[$0.id]?.count == 1', '$0.x.isFinite && $0.y.isFinite']:
            self.assertIn(value, self.ui + self.core)
        host = (ROOT/'App/SearchMapExplorerView.swift').read_text()
        self.assertIn('.id(MapPresentationIdentity(area: area, scope: reader.scope))', host)
        self.assertIn('gate.accepts(', host)
    def test_cluster_never_selects_arbitrary_business_member(self):
        self.assertIn('if group.members.count == 1 { onSelect?(anchor.id) }', self.ui)
        self.assertIn('else { expand(group) }', self.ui)
        expand = self.ui.split('private func expand(',1)[1]
        self.assertNotIn('onSelect', expand)
        self.assertIn('guard expandedSnapshot == snapshot,', self.ui)
        self.assertIn('currentPins.contains(where: { $0 == pin })', self.ui)
        self.assertIn('onSelect?(pin.id); expanded = []', self.ui)
        self.assertIn('max(0.001, (north - south) * 1.5)', self.core)
        self.assertIn('east - west <= 180 else { return nil }', self.core)
        self.assertIn('2 * (85 - abs(latitude))', self.core)
        self.assertIn('min(360, max(0.001, (east - west) * 1.5))', self.core)
    def test_camera_and_business_boundaries(self):
        self.assertEqual(self.ui.count('position = .region'), 1)
        for value in ['URLSession', 'MKDirections', 'CLLocationManager', 'UserAnnotation', 'requestWhenInUseAuthorization', 'H3', 'http']:
            self.assertNotIn(value, self.ui + self.core)
        self.assertIn('members.first(where: { $0.id == selectedID })', self.ui)
        self.assertIn('var id: [String] { members.map(\\.id) }', self.ui)
