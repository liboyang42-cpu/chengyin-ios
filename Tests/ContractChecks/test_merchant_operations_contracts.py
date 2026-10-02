"""Supplementary source/structure checks. No Swift execution or live acceptance."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / 'app-audit' / 'lib'

class MerchantOperationsSourceTests(unittest.TestCase):
    def text(self, file):
        return (ROOT / file).read_text()

    def test_all_read_routes_exist_in_exact_flutter_sources(self):
        service = self.text('Core/MerchantOperationsService.swift')
        routes = set(re.findall(r'"(api/[a-zA-Z0-9/-]+)"', service))
        self.assertEqual(routes, {
            'api/merchant/access/me', 'api/merchant/info', 'api/merchant/coop-profile',
            'api/merchant/npc/profile', 'api/merchant/npc/voice/status', 'api/merchant/npc/avatar/status',
            'api/merchant/city-node/list', 'api/template/my-list', 'api/template/myinfo', 'api/merchant/city-node/template/submit'})
        if SOURCE.exists():
            source = '\n'.join((SOURCE/'data/api'/f).read_text() for f in ['merchant_api.dart','merchant_npc_api.dart','template_api.dart'])
            for route in routes:
                self.assertIn('/' + route, source)

    def test_mutation_routes_are_exact_and_scoped_before_transport(self):
        draft = self.text('Core/MerchantOperationsDraft.swift')
        routes = set(re.findall(r'path: "(api/[a-zA-Z0-9/-]+)"', draft))
        self.assertEqual(routes, {'api/merchant/update','api/merchant/decor/save','api/merchant/coop-profile/save','api/merchant/npc/save','api/merchant/city-node/template/submit'})
        self.assertNotIn('URLRequest', draft)
        service = self.text('Core/MerchantOperationsService.swift')
        save = service.split('public func save(', 1)[1]
        self.assertIn('throw MerchantOperationsFailure.liveWritesDisabled', save)
        self.assertIn('transport.send', save)
        for guard in ['approval.allows', 'previews.allSatisfy', 'fresh == .draft(baseline)', 'access.allows', 'journal.write(record)', 'partial(acknowledgedSteps:']: self.assertIn(guard,save)
        self.assertLess(save.index('try journal.write(record)'),save.index('transport.send'))

    def test_explicit_permission_keys_are_source_backed(self):
        contract = self.text('Core/MerchantOperationsContracts.swift')
        for key in ['merchant:profile:write','merchant:coop:manage']:
            self.assertIn(key, contract)
            if SOURCE.exists(): self.assertIn(key, (SOURCE/'data/api/merchant_api.dart').read_text())
        self.assertIn('identity = try MerchantAccess(from: decoder)', contract)
        self.assertNotIn('Account.role', contract)

    def test_no_production_upload_provider_payment_or_deletion(self):
        files = [p for folder in ['Core','App'] for p in (ROOT/folder).glob('MerchantOperations*.swift')]
        implementation = '\n'.join(p.read_text() for p in files)
        for forbidden in ['AVAudioRecorder','PHPhotoLibrary','PhotosPicker','URLSession.shared','UserDefaults','/withdraw','/payment','/voice/enroll','/voice/revoke','/avatar/generate','/city-node/offline','/template/delete','/common/uploadOSS']:
            self.assertNotIn(forbidden, implementation)
        self.assertIn('reader.isOfflineExample', implementation)

    def test_fixture_reader_is_debug_only_and_never_creates_network(self):
        fixture = self.text('Core/MerchantOperationsSyntheticFixtures.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertTrue(fixture.strip().endswith('#endif'))
        self.assertNotIn('URLSession(', fixture)
        self.assertNotIn('HTTPTransport', fixture)
        self.assertNotIn('https://', fixture)

    def test_session_checks_include_epoch_and_prevent_post_access_stale_read(self):
        reader = self.text('Core/MerchantOperationsReading.swift')
        self.assertIn('public let epoch: UInt64', reader)
        self.assertIn('expected == currentSession()', reader)
        self.assertIn('currentSession() == session, captured == scope', reader)
        self.assertIn('scope: UUID', reader)

    def test_unknown_is_not_success_and_no_automatic_retry(self):
        coordinator = self.text('Core/MerchantOperationsReading.swift')
        self.assertIn('isLocked = true', coordinator)
        self.assertIn('isLocked ? .key("merchant.operations.unknownOutcome")', coordinator)
        self.assertNotIn('Timer', coordinator)
        self.assertNotIn('Task.sleep', coordinator)
        self.assertIn('latest == .draft(value.baseline)', coordinator)
        self.assertIn('confirmation == value', coordinator)

    def test_bilingual_localizations_cover_ui_and_domain_messages(self):
        catalog = json.loads(self.text('docs/merchant-operations-localizations.json'))
        base_file = ROOT.parent/'chengyin-ios/Resources/Localizable.xcstrings'
        base = set(json.loads(base_file.read_text())['strings']) if base_file.exists() else set()
        content = '\n'.join(p.read_text() for folder in ['Core','App'] for p in (ROOT/folder).glob('MerchantOperations*.swift'))
        # Remove explicit accessibility identifiers and purely generated prefixes.
        content = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', content)
        keys = set(re.findall(r'"(merchant\.operations\.[A-Za-z0-9.]+)"', content))
        keys = {key for key in keys if not key.endswith('.')}
        self.assertFalse(keys - set(catalog) - base, keys - set(catalog) - base)
        for key, value in catalog.items():
            self.assertEqual(set(value), {'en','zh-Hans'})
            self.assertTrue(value['en'].strip() and value['zh-Hans'].strip())
        for i in range(1,6): self.assertIn(f'merchant.operations.method.{i}', catalog)

    def test_native_card_and_accessible_form_structure(self):
        views = self.text('App/MerchantOperationsViews.swift')
        editor = self.text('App/MerchantOperationsEditor.swift')
        self.assertIn('QuestifyImageEntityCard(', views)
        self.assertIn('Form {', editor)
        self.assertNotIn('.stroke(', views + editor)
        self.assertIn('interactiveDismissDisabled', views)
        self.assertIn('confirmationDialog', views)
        self.assertIn('confirmation.draft.reviewLines', editor)
        self.assertIn('frame(minWidth: 44, minHeight: 44)', editor)

    def test_private_template_detail_and_first_page_stay_explicit(self):
        service = self.text('Core/MerchantOperationsService.swift')
        self.assertIn('"api/template/myinfo"', service)
        self.assertNotIn('"api/template/info"', service)
        self.assertIn('"pageSize": "100"', service)
        self.assertIn('"category_id": ""', service)
        self.assertIn('"is_quote": ""', service)
        self.assertIn('templatePageLimit', self.text('App/MerchantOperationsViews.swift'))

if __name__ == '__main__': unittest.main()
