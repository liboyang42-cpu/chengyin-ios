"""Offline source contracts only; never execute Apple, provider, location, or HTTP code."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PrivateHomeMapPickerContracts(unittest.TestCase):
    def read(self, name):
        return (ROOT / name).read_text()

    def test_real_owner_entry_hosts_picker_and_existing_confirmation(self):
        view = self.read('App/PrivateHomeView.swift')
        for marker in ['PrivateHomeView(model: coordinator, mapAdapter: mapAdapter)', 'PrivateHomeInactiveMapKitAdapter()', 'picker.open()', '.sheet(isPresented:', 'PrivateHomeMapPickerView(picker: picker, initialLabel: label)', 'await model.confirm()', 'PrivateHomeCoordinateReview(point: point)']:
            self.assertIn(marker, view)
        picker = self.read('App/PrivateHomeMapPicker.swift')
        self.assertIn('owner.prepareSet(label: label, point: point)', picker)
        for forbidden in ['service.mutate', 'journal.save', 'PrivateHomeMutation(', 'requestId:', 'expectedVersion:']:
            self.assertNotIn(forbidden, picker)

    def test_production_adapter_is_inactive_and_cannot_mount_provider(self):
        picker = self.read('App/PrivateHomeMapPicker.swift')
        adapter = picker.split('final class PrivateHomeInactiveMapKitAdapter:', 1)[1].split('@MainActor @Observable', 1)[0]
        self.assertIn('let approvedSource: PrivateHomeMapSource? = nil', adapter)
        self.assertIn('func start(receive: @escaping (PrivateHomeMapCandidate) -> Void) {}', adapter)
        self.assertNotIn('import MapKit', picker)
        self.assertLess(picker.index('guard adapter.approvedSource?.isReviewedWGS84 == true'), picker.index('adapter.start'))
        for path in [*ROOT.glob('App/PrivateHome*.swift'), ROOT / 'Core/PrivateHomeMapSelection.swift']:
            code = '\n'.join(line for line in path.read_text().splitlines() if not line.lstrip().startswith('///'))
            for forbidden in ['CLLocationManager(', 'requestWhenInUseAuthorization', 'MapReader', 'MKLocalSearch(', 'Map(', 'URLSession(', 'UserAnnotation(', 'RuntimeLocationProjection', 'SearchMapCanvas(']:
                self.assertNotIn(forbidden, code, path.name)

    def test_candidate_requires_explicit_matching_provenance_and_reuses_point_validation(self):
        core = self.read('Core/PrivateHomeMapSelection.swift')
        for marker in ['WalkingCoordinateDatum?', 'source.datum == .wgs84', 'source == approvedSource', 'PrivateHomePoint.parse', 'precisionUnsupported', 'case providerUnverified']:
            self.assertIn(marker, core)
        for forbidden in ['Double(', 'NSDecimalRound', 'UserDefaults', 'JSONEncoder', 'Codable']:
            self.assertNotIn(forbidden, core)
        self.assertEqual(core.count('"PrivateHome[redacted]"'), 2)

    def test_cancel_reopen_background_and_owner_version_fences(self):
        core = self.read('Core/PrivateHomeMapSelection.swift')
        picker = self.read('App/PrivateHomeMapPicker.swift')
        host = self.read('App/PrivateHomeView.swift')
        for marker in ['guard generation == ticket', 'point = nil; issue = nil', 'generation = nil; point = nil; issue = nil; approvedSource = nil']:
            self.assertIn(marker, core)
        for marker in ['owner.canEdit && owner.home?.version == ownerVersion', 'self.selection.generation == ticket', 'guard self.currentOwner', 'adapter.cancel()', 'if phase != .active { picker.close() }']:
            self.assertIn(marker, picker)
        for marker in ['if phase != .ready { picker.close() }', 'if phase == .invalidated { clearInput() }', '.onDisappear { picker.close(); clearInput(); model.cancelReview() }']:
            self.assertIn(marker, host)

    def test_debug_only_synthetic_adapter_and_payload_free_recorder(self):
        self.assertTrue(self.read('App/PrivateHomeFixtureMapAdapter.swift').startswith('#if DEBUG'))
        self.assertTrue(self.read('App/PrivateHomeFixtureHost.swift').startswith('#if DEBUG'))
        fixture = self.read('App/PrivateHomeFixtureHost.swift')
        for marker in ['--private-home-map-fixture', '--private-home-map-recorder', 'privateHome.recorder.requests', 'privateHome.recorder.exactPoint', 'mutations.append(mutation)']:
            self.assertIn(marker, fixture)
        self.assertIn('#if DEBUG\n                if let fixture', self.read('App/PrivateHomeMapPicker.swift'))

    def test_all_picker_keys_have_both_languages(self):
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        expected = json.loads(self.read('docs/private-home-localizations.json'))
        keys = {k for k in expected if k.startswith('privateHome.map.') or k == 'privateHome.gamePoint'}
        self.assertGreaterEqual(len(keys), 21)
        for key in keys:
            for lang in ['en', 'zh-Hans']:
                self.assertEqual(catalog[key]['localizations'][lang]['stringUnit']['value'], expected[key][lang])
        for required in ['need not be your real residence', 'does not verify safety', 'at most six decimal places']:
            self.assertIn(required, ' '.join(expected[key]['en'] for key in keys))

    def test_apple_tests_are_in_project_and_not_claimed_executed(self):
        project = self.read('Questify.xcodeproj/project.pbxproj')
        for name in ['App/PrivateHomeMapPicker.swift', 'App/PrivateHomeFixtureMapAdapter.swift', 'Core/PrivateHomeMapSelection.swift', 'Tests/AppUnitTests/PrivateHomeMapPickerTests.swift', 'Tests/AppUITests/PrivateHomeMapPickerFlowTests.swift']:
            self.assertIn(name, project)
        ui = self.read('Tests/AppUITests/PrivateHomeMapPickerFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 10)
        self.assertIn('accessibility5', ui); self.assertIn('"en", "zh-Hans"', ui)
        self.assertIn('record("requests", "0", app)', ui)
        self.assertIn('XCTAssertEqual(app.maps.count, 0)', ui)

if __name__ == '__main__':
    unittest.main()
