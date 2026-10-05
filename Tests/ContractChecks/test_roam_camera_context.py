"""Roam camera lifetime source guards; not SwiftUI/MapKit runtime acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RoamCameraContextTests(unittest.TestCase):
    def setUp(self):
        self.host = (ROOT / 'App/RoamBrowserView.swift').read_text()
        self.map = (ROOT / 'App/QuestifyDensityMap.swift').read_text()
        self.core = (ROOT / 'Core/RoamReading.swift').read_text()
        self.results = self.host.split('private var results: some View {', 1)[1].split('// Both map members', 1)[0]

    def test_loading_error_and_empty_states_do_not_unmount_results(self):
        body = self.host.split('var body: some View {', 1)[1].split('private var controls:', 1)[0]
        for gate in ['if !reader.isConfigured', 'else if reader.identity == nil', 'else if reader.searchArea == nil']:
            self.assertIn(gate, body)
        for phase in ['else if loading', 'else if let issue', 'else if visibleItems.isEmpty']:
            self.assertNotIn(phase, body)
        self.assertIn('results', body)
        map_row = self.results.split('if showsMap, let scope = cameraScope {', 1)[1].split('if loading || loadedKey', 1)[0]
        self.assertIn('RoamMapView(area: scope.area, items: renderedItems', map_row)
        self.assertNotIn('contains(where:', map_row)
        self.assertIn('.id(scope)', map_row)

    def test_camera_scope_excludes_data_query_while_retaining_full_session_and_area(self):
        scope = self.core.split('public struct RoamMapCameraScope:', 1)[1].split('/// Construct from the live', 1)[0]
        for value in ['let readerID: ObjectIdentifier', 'let identity: RoamReadIdentity', 'let area: RoamSearchArea',
                      'guard isConfigured, let identity, identity.accountID > 0, let area else { return nil }']:
            self.assertIn(value, scope)
        for excluded in ['generation', 'query', 'placeFilter', 'eventFilter', 'radius', 'layer', 'pins', 'token']:
            self.assertNotIn(excluded, scope)
        self.assertIn('RoamMapCameraScope(readerID: ObjectIdentifier(reader)', self.host)
        self.assertNotIn('.id(renderedKey)', self.host)

    def test_stale_pins_are_removed_before_refresh_and_never_cached(self):
        self.assertIn('guard loadedKey == requestKey, !loading, issue == nil else { return [] }', self.host)
        for method in ['startLoad()', 'load() async']:
            body = self.host.split('private func ' + method + ' {', 1)[1].split('\n    }', 1)[0]
            self.assertLess(body.index('loadedKey = nil'), body.index('readOwner.'))
        self.assertIn('selected = nil; items = []; issue = nil; loadedKey = nil', self.host)
        self.assertIn('items = RoamMapItem.unique(result); loadedKey = key', self.host)
        for forbidden in ['cachedItems', 'previousItems', 'UserDefaults', 'AppStorage']:
            self.assertNotIn(forbidden, self.host)

    def test_query_snapshot_selection_fence_remains_stricter_than_camera_scope(self):
        for value in ['let request: RequestKey', 'let generation: Int', 'let query: String',
                      'let placeFilter: RoamPlaceFilter', 'let eventFilter: RoamEventFilter',
                      'key == presentationKey, loadedKey == key.request',
                      '!loading, issue == nil, snapshot == visibleItems', 'visibleItems.contains(item)']:
            self.assertIn(value, self.host)
        self.assertEqual(self.host.count('select(item, key: renderedKey, snapshot: renderedItems)'), 2)
        self.assertIn('RequestKey(readerID: ObjectIdentifier(reader)', self.host)
        self.assertIn('guard operation == generation, key == requestKey else { return }', self.host)

    def test_cluster_actions_from_replaced_pins_cannot_move_retained_camera(self):
        expand = self.map.split('private func expand(_ group: Group) {', 1)[1].split('private func applyCameraFit', 1)[0]
        self.assertIn('guard focusInput == currentFocusInput', expand)
        self.assertIn('group.members.allSatisfy({ currentPins.contains($0) }) else { return }', expand)
        self.assertLess(expand.index('guard focusInput'), expand.index('expansionID = UUID()'))
        self.assertIn('.onChange(of: snapshot) { _, _ in closeExpansion() }', self.map)
        self.assertIn('currentFocusInput = value', self.map)
        # Even an identical pin response must invalidate actions from the old read.
        self.assertIn('interactionID: AnyHashable(renderedKey)', self.host)
        self.assertIn('let interactionID: AnyHashable?', self.map)
        self.assertIn('.onChange(of: interactionID) { _, _ in closeExpansion() }', self.map)
        self.assertIn('interactionID: interactionID', (ROOT / 'App/RoamMapView.swift').read_text())

    def test_all_statuses_and_reload_routes_remain_accessible(self):
        for value in ['ProgressView("roam.loading")', 'RoamStatusView(issue: issue)',
                      '.accessibilityIdentifier("roam.empty")', 'Label("roam.noCoordinates"',
                      'ForEach(visibleItems)', '.refreshable { await load() }']:
            self.assertIn(value, self.results)
        self.assertIn('.disabled(loading || !reader.isConfigured', self.host)
        for forbidden in ['CLLocationManager', 'MapUserLocationButton', 'UserAnnotation', 'MKDirections', 'URLSession', 'onMapCameraChange']:
            self.assertNotIn(forbidden, self.host)
