"""Source assertions only. These do not execute Swift or prove app behavior."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class RoamExperienceSourceTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_exact_read_routes_and_no_mutation_routes(self):
        text = self.read('Core/RoamExperienceService.swift')
        routes = set(re.findall(r'"(api/[^" ]+)"', text))
        self.assertEqual(routes, {'api/roam/session', 'api/roam/stamp/list', 'api/roam/tiles/page', 'api/roam/tiles', 'api/roam/badge/shop-streak'})
        for field in ['pageNum', 'pageSize', 'afterId', 'limit']:
            self.assertIn('"' + field + '"', text)

    def test_new_roam_surface_has_no_device_permission_or_share_calls(self):
        paths = list((ROOT/'App').glob('Roam*Views.swift')) + list((ROOT/'App').glob('RoamExperience*.swift'))
        text = '\n'.join(p.read_text() for p in paths)
        for forbidden in ['CLLocationManager(', 'requestWhenInUseAuthorization(', 'PhotosPicker(', 'UIImagePickerController(', 'UIActivityViewController(', 'ShareLink(']:
            self.assertNotIn(forbidden, text)
        self.assertNotIn('api/verify', text)

    def test_capabilities_stay_hard_off(self):
        text = self.read('Core/RoamExperienceContracts.swift')
        for key in ['location', 'presence', 'settlement', 'mediaUpload', 'stampExchange', 'voucherIssue', 'redemption', 'legacyHangout']:
            self.assertIn('static let ' + key + ' = false', text)

    def test_history_is_scope_bound_atomic_and_not_plaintext(self):
        store = self.read('Core/RoamHistoryStore.swift')
        for value in ['historyUnreadable', 'historyWriteFailed', 'hasCompleteSettlement', 'record.serverSessionID == sessionID', 'records.prefix(50)', 'currentScope() == scope', 'value.scope == scope']:
            self.assertIn(value, store)
        storage = self.read('App/RoamHistoryKeychainStorage.swift')
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', storage)
        self.assertIn('kSecAttrSynchronizable as String: false', storage)
        self.assertNotIn('UserDefaults', storage)

    def test_production_reader_uses_reviewed_regional_namespace_and_full_session(self):
        app = self.read('App/AppSession.swift')
        self.assertIn('namespace: storageScope.service', app)
        self.assertIn('self.currentRoamExperienceSession == captured', app)
        reader = self.read('Core/RoamExperienceReading.swift')
        self.assertIn('currentSession() == snapshot', reader)
        self.assertIn('store.scope == snapshot.identity.scope', reader)
        self.assertIn('snapshot.identity.scope.deployment == service.deployment.absoluteString', reader)

    def test_fixture_excludes_production_session_and_has_no_remote_assets(self):
        app = self.read('App/QuestifyApp.swift')
        self.assertEqual(app.count('RoamExperienceFixtureHostView.selected'), 2)
        fixtures = self.read('Core/RoamExperienceSyntheticFixtures.swift')
        self.assertNotIn('https://', fixtures)
        self.assertIn('isOfflineExample: Bool { true }', self.read('App/RoamExperienceFixtureSupport.swift'))

    def test_bilingual_catalog_covers_module(self):
        entries = json.loads(self.read('docs/roam-experience-localizations.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(entries), 80)
        for entry in entries:
            for language in ['en', 'zh-Hans']:
                self.assertEqual(entry[language], catalog[entry['key']]['localizations'][language]['stringUnit']['value'])

    def test_album_stale_and_moderation_boundaries(self):
        coordinator = self.read('Core/RoamExperienceCoordinators.swift')
        for value in ['generation == ticket', 'reader.identity == snapshot', 'result.pageNum == page', 'stamps.removeAll', 'stamp.isVisible']:
            self.assertIn(value, coordinator)
        contracts = self.read('Core/RoamExperienceContracts.swift')
        self.assertIn('checkState == 0 || checkState == 1', contracts)
        self.assertIn('state == .finished && resultComplete', contracts)

    def test_dormant_mutations_block_before_credential_or_transport(self):
        text = self.read('Core/RoamExperienceMutationContracts.swift')
        gate = text.index('guard mutation.productionEnabled')
        self.assertLess(gate, text.index('guard let snapshot = currentSession()'))
        self.assertLess(gate, text.index('transport.send(request)'))
        self.assertIn('public var isAvailable: Bool { false }', text)
        self.assertNotIn('api/verify/citynode/redeem', text)

    def test_stamp_workflow_uses_durable_same_key_and_same_created_id(self):
        text = self.read('Core/RoamStampExchangeCoordinator.swift')
        for value in ['entry.phase = .createPending; try journal.save(entry)', 'previous.draft == draft', 'entry.createdID = created.id', '.exchangeStamp(givenStampID: createdID)', 'currentIdentity() == identity', 'executor.isAvailable']:
            self.assertIn(value, text)
        self.assertNotIn('Task.sleep', text)

    def test_album_detail_navigation_preserves_source_rows(self):
        text = self.read('Core/RoamExperienceCoordinators.swift')
        self.assertIn('func cancelPending() { generation += 1; loading = false }', text)

if __name__ == '__main__':
    unittest.main()
