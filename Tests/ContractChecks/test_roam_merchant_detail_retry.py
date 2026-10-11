"""Focused P127 supplementary-read action checks; no native runtime claim."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RoamMerchantDetailRetrySourceTests(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/RoamItemDetailView.swift').read_text()
        self.model = (ROOT / 'App/RoamMerchantDetailRetryModel.swift').read_text()

    def test_failed_merchant_section_offers_explicit_local_loading_and_retry(self):
        self.assertIn('else if merchantFailed {\n                merchantRetrySection(node: node)', self.view)
        self.assertIn('Button("action.retry", systemImage: "arrow.clockwise")', self.view)
        self.assertIn('if merchantRetry.isLoading', self.view)
        self.assertIn('"roam.merchant.retry.loading"', self.view)
        self.assertIn('"roam.merchant.retry"', self.view)

    def test_only_the_existing_merchant_read_is_used(self):
        self.assertIn('try await reader.roamMerchantDetail(id: merchantID)', self.model)
        self.assertIn('guard detail.merchant.id == merchantID', self.model)
        for forbidden in ['roamNodeDetail(', 'URLSession', 'sendRequest(', 'toggleFavorite', 'redeem', 'claim(']:
            self.assertNotIn(forbidden, self.model)
        self.assertIn('private let owner = ManualMapReadTaskOwner()', self.model)

    def test_current_node_scope_and_snapshot_are_required_at_tap_and_completion(self):
        action = self.view.split('private func retryMerchant(', 1)[1].split('@ViewBuilder private func merchantContent(', 1)[0]
        for guard in ['merchantFailed, merchant == nil, !merchantRetry.isLoading', 'rendered == eventScope',
                      'snapshot == merchantReadSnapshot', 'self.node == capturedNode',
                      'currentPlace?.id == capturedNode.id', 'merchantID > 0',
                      'merchantReadSnapshot == attemptSnapshot']:
            self.assertIn(guard, action)
        self.assertIn('merchant = value; merchantFailed = false', action)
        self.assertIn('if error as? APIError == .unauthorized', action)
        self.assertNotIn('startLoad()', action)
        self.assertNotIn('roamNodeDetail(', action)

    def test_repeat_taps_and_superseded_callbacks_are_fenced(self):
        self.assertIn('!isLoading, !Task.isCancelled, isCurrent()', self.model)
        self.assertIn('isLoading = true', self.model)
        self.assertIn('defer { if self.generation == captured { self.isLoading = false } }', self.model)
        self.assertIn('guard self.generation == captured, isCurrent()', self.model)
        self.assertIn('generation = UUID(); owner.cancel(); isLoading = false', self.model)

    def test_close_context_replacement_and_full_reload_cancel_retry(self):
        self.assertIn('Button("roam.close") { merchantRetry.cancel(); dismiss() }', self.view)
        self.assertIn('.onDisappear { merchantRetry.cancel();', self.view)
        self.assertIn('.onChange(of: reader.identity) { _, _ in merchantRetry.cancel();', self.view)
        self.assertIn('.onChange(of: reader.searchArea) { _, _ in merchantRetry.cancel();', self.view)
        self.assertIn('latestReaderID = value; eventPresentationID = UUID(); merchantRetry.cancel()', self.view)
        self.assertIn('latestItem = value; eventPresentationID = UUID(); merchantRetry.cancel()', self.view)
        self.assertIn('private func performLoad() async {\n        merchantRetry.cancel()', self.view)

    def test_prior_wallet_navigation_and_translated_labels_are_retained(self):
        self.assertIn('featuredCouponWalletButton(place: renderedPlace, node: renderedNode, detail: detail)', self.view)
        self.assertIn('RoamFeaturedActivityTarget(node: renderedNode, detail: detail)', self.view)
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['action.retry', 'roam.merchantFailed', 'roam.loading']:
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][locale]['stringUnit']['value'])


if __name__ == '__main__':
    unittest.main()
