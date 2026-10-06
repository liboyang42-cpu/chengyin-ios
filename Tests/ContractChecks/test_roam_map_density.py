"""Source regression guards only; no claim of MapKit/Swift/VoiceOver execution."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class RoamMapDensityContracts(unittest.TestCase):
    def setUp(self):
        self.adapter = (ROOT/'App/RoamMapView.swift').read_text()
        self.host = (ROOT/'App/RoamBrowserView.swift').read_text()
        self.density = (ROOT/'App/QuestifyDensityMap.swift').read_text()

    def test_roam_reuses_actual_projection_and_safe_membership(self):
        self.assertIn('QuestifyDensityMap(area: area, pins: pins, selectedID: selectedID', self.adapter)
        self.assertIn('proxy.convert(coordinate(pin.coordinate), to: .local)', self.density)
        self.assertIn('MapMarkerDensity.groups(projected', self.density)
        self.assertIn('MapMarkerDensity.fit(group.members.map', self.density)
        self.assertIn('else { expand(group) }', self.density)
        self.assertNotIn('onSelect', self.density.split('private func expand(', 1)[1].split('\n    }', 1)[0])
        self.assertIn('guard matches.count == 1, let item = matches.first', self.adapter)

    def test_only_map_is_fixed_height_member_choices_remain_in_outer_list(self):
        self.assertIn('mapHeight: 270, initialSpan: 0.045', self.adapter)
        self.assertNotIn('.frame(height: 270)', self.host)
        self.assertIn('}.frame(height: mapHeight)', self.density)
        self.assertLess(self.density.index('}.frame(height: mapHeight)'), self.density.index('if !expanded.isEmpty'))
        self.assertIn('return List {', self.host)
        self.assertIn('ForEach(visibleItems)', self.host)
        self.assertIn('fixedSize(horizontal: false, vertical: true)', self.density)
        self.assertIn('}.buttonStyle(.plain).frame(minHeight: 44)', self.density)
        self.assertIn('Button("mapDensity.close") { closeExpansion() }.buttonStyle(.plain)', self.density)

    def test_selection_context_includes_filter_session_read_and_snapshot(self):
        for value in ['let request: RequestKey', 'let generation: Int', 'let query: String',
                      'let placeFilter: RoamPlaceFilter', 'let eventFilter: RoamEventFilter',
                      '.id(scope)', 'key == presentationKey, loadedKey == key.request',
                      '!loading, issue == nil, snapshot == visibleItems', 'visibleItems.contains(item)',
                      '.onChange(of: requestKey) { _, _ in selected = nil }']:
            self.assertIn(value, self.host)
        self.assertEqual(self.host.count('select(item, key: renderedKey, snapshot: renderedItems)'), 2)
        for entry in ['startLoad()', 'load() async']:
            body = self.host.split('private func '+entry+' {',1)[1].split('\n    }',1)[0]
            self.assertLess(body.index('loadedKey = nil'), body.index('readOwner.'))
        self.assertIn('expandedSnapshot == snapshot', self.density)
        self.assertIn('currentPins.contains(where: { $0 == pin })', self.density)

    def test_identity_localization_privacy_and_search_defaults_are_preserved(self):
        for value in ['pinIdentifierPrefix: "roam.pin."', 'appLocalized("roam.unnamed", locale: locale)',
                      'Text(item.kindLabel)', 'coordinate: coordinate, symbol: item.symbol']:
            self.assertIn(value, self.adapter)
        self.assertIn('selectedID: selected?.id', self.host)
        for value in ['mapHeight: CGFloat = 300', 'initialSpan: Double = 0.04',
                      'pinIdentifierPrefix: String = "searchMap.pin."',
                      '.accessibilityHint(pinHint(pin.id))']:
            self.assertIn(value, self.density)
        reading = (ROOT/'Core/RoamReading.swift').read_text()
        self.assertIn('case .player(let value): return value.approximateCoordinate', reading)
        for forbidden in ['URLSession', 'CLLocationManager', 'MKDirections', 'UserAnnotation', 'requestWhenInUseAuthorization']:
            self.assertNotIn(forbidden, self.adapter + self.density)

    def test_expansion_issuance_fences_old_group_close_reopen_and_duplicate_taps(self):
        # Supplement to the private event-trace review; no runtime claim.
        self.assertIn('let renderedExpansionID = expansionID', self.density)
        self.assertIn('renderedExpansionID == expansionID, expanded.contains(pin.id)', self.density)
        close = self.density.split('private func closeExpansion() {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('expansionID = UUID()', close)
        self.assertIn('expanded = []', close)
        self.assertIn('expandedSnapshot = []', close)
        expand = self.density.split('private func expand(_ group: Group) {', 1)[1]
        self.assertLess(expand.index('expansionID = UUID()'), expand.index('expanded = group.id'))
        self.assertIn('closeExpansion()\n                            onSelect?(pin.id)', self.density)
        self.assertIn('currentPins.contains(where: { $0 == pin }) else { return }', self.density)
