"""Focused source/registration checks only; not Swift typecheck or runtime tests."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()

class MerchantBrandImagesChecks(unittest.TestCase):
    def test_existing_owned_read_route_is_used_with_both_existing_grants(self):
        source = read('Core/MerchantOperationsService.swift').split('public func brandImages(')[1].split('public func storeIndustries')[0]
        for text in ['access.allows(.profile), access.cooperationManage', '"api/merchant/coop-profile", body: .json', 'value.merchantID == access.identity.merchantID']:
            self.assertIn(text, source)
        self.assertNotIn('save(', source); self.assertNotIn('businessLicense', source)

    def test_reader_refreshes_access_and_uses_existing_session_fence(self):
        source = read('Core/MerchantOperationsReading.swift').split('public func brandImages()')[1].split('public func storeIndustries')[0]
        for text in ['let expected = currentSession()', 'return try await read', 'service.access(token: token)', 'expected == currentSession()', 'service.brandImages(access: access, token: token)']:
            self.assertIn(text, source)
        self.assertIn('func brandImages() async throws -> MerchantBrandImages { throw APIError.notConfigured }', read('Core/MerchantOperationsReading.swift'))

    def test_projection_uses_only_persisted_brand_csv_and_preserves_order(self):
        core = read('Core/MerchantBrandImages.swift')
        for text in ['case id, derivatives', 'decodeIfPresent(String.self, forKey: .derivatives)', 'components(separatedBy: ",")', '.enumerated().map', 'source: $0.element']:
            self.assertIn(text, core)
        for text in ['businessLicense', 'Set(items)', 'sorted()', 'prefix(9)']:
            self.assertNotIn(text, core)

    def test_https_policy_rejects_credentials_controls_and_relative_requests(self):
        core = read('Core/MerchantBrandImages.swift')
        for text in ['CharacterSet.controlCharacters', 'components.scheme == "https"', 'components.user == nil', 'components.password == nil', '!(components.host ?? "").isEmpty']:
            self.assertIn(text, core)
        self.assertIn('merchant.brandImages.unsupported', read('App/MerchantBrandImagesView.swift'))

    def test_viewer_is_not_an_editor_and_never_adds_a_write_contract(self):
        core = read('Core/MerchantBrandImages.swift'); app = read('App/MerchantBrandImagesView.swift')
        for text in ['owner.edit(', 'saveReviewed(', 'saveExample(', 'URLSession', 'UserDefaults', 'UIPasteboard', 'ShareLink', 'PhotosPicker']:
            self.assertNotIn(text, core + app)
        self.assertIn('MerchantBrandImagesEntry(document: model)', read('App/MerchantOperationsEditor.swift'))
        self.assertIn('Core/MerchantBrandImages.swift', read('docs/merchant-brand-images.md'))

    def test_document_and_async_read_fences_cover_stale_source(self):
        core = read('Core/MerchantBrandImages.swift')
        for text in ['owner.draftIdentity == identity', 'owner.draft == original', 'owner.reader.scope == scope', 'owner.confirmation == nil',
                     'ticket == generation, isCurrent', 'request?.cancel()', 'value.merchantID == merchantID', 'active = false; generation += 1']:
            self.assertIn(text, core)

    def test_selected_image_only_and_synthetic_branch_precedes_network_renderer(self):
        app = read('App/MerchantBrandImagesView.swift')
        self.assertEqual(app.count('AsyncImage('), 1)
        self.assertIn('if let url = session.currentURL', app)
        self.assertLess(app.index('if model.isExample'), app.index('AsyncImage('))
        self.assertIn('model.session.imageIsCurrent(ticket, index: index)', app)
        self.assertIn('.privacySensitive()', app)
        self.assertNotIn('Text(url', app); self.assertNotIn('Text(item.source', app)

    def test_full_image_interaction_and_retirement_are_wired(self):
        app = read('App/MerchantBrandImagesView.swift')
        for text in ['MagnificationGesture()', 'merchant.brandImages.next', 'merchant.brandImages.previous', 'merchant.brandImages.resetZoom',
                     'merchant.brandImages.retryImage', 'merchant.brandImages.retrySource', 'merchant.brandImages.reload',
                     '.onChange(of: scenePhase)', '.onChange(of: document.coordinator.reader.scope)', '.onChange(of: document.coordinator.draft)',
                     '.onDisappear { model.retire() }', 'ViewThatFits(in: .horizontal)']:
            self.assertIn(text, app)
        self.assertIn('min(5, max(1, value))', read('Core/MerchantBrandImages.swift'))

    def test_empty_error_and_unsupported_are_not_conflated(self):
        app = read('App/MerchantBrandImagesView.swift')
        for text in ['if session.isLoading', 'else if let issue = session.issue', 'else if session.document != nil', 'session.items.isEmpty', 'item.url == nil']:
            self.assertIn(text, app)
        core = read('Core/MerchantBrandImages.swift')
        self.assertIn('document = nil; issue = nil; closeImage(); isLoading = true', core)

    def test_localizations_cover_all_new_user_visible_keys(self):
        source = read('App/MerchantBrandImagesView.swift')
        source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', source)
        keys = set(re.findall(r'"(merchant\.brandImages\.[A-Za-z]+)"', source)); keys.add('merchant.brandImages.image %lld')
        fragment = json.loads(read('Resources/MerchantBrandImagesLocalizations.fragment.json'))
        self.assertEqual(keys, set(fragment)); self.assertEqual(len(fragment), 17)
        for value in fragment.values():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
            for unit in value['localizations'].values(): self.assertTrue(unit['stringUnit']['value'])

    def test_native_authored_coverage_is_explicitly_unexecuted(self):
        doc = read('docs/merchant-brand-images.md')
        self.assertIn('NOT RUN', doc); self.assertIn('no `swift` or `xcodebuild`', doc)
        core = read('Tests/CoreTests/MerchantBrandImagesTests.swift')
        for name in ['testRetirementRejectsLateSuccessfulRead', 'testNewReloadSupersedesOldReadWithoutClearingItsBusyState',
                     'testViewingReadsSavedSourceWithoutChangingDirtyProfile', 'testEitherMissingExistingGrantStopsBeforePrivateRead']:
            self.assertIn(name, core)
        self.assertEqual(len(re.findall(r'func test\w+', core)), 18)
        self.assertEqual(len(re.findall(r'func test\w+', read('Tests/AppUITests/MerchantBrandImagesFlowTests.swift'))), 3)

if __name__ == '__main__': unittest.main()
