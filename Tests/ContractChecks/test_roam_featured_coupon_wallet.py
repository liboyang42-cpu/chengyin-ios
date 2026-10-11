"""P127 coupon-feature navigation wiring only; not native runtime evidence."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RoamFeaturedCouponWalletSourceTests(unittest.TestCase):
    def setUp(self):
        self.detail = (ROOT / 'App/RoamItemDetailView.swift').read_text()
        self.target = (ROOT / 'Core/RoamFeaturedCouponWalletSelection.swift').read_text()
        self.session = (ROOT / 'App/SessionRoamCouponWalletView.swift').read_text()

    def test_coupon_type_opens_wallet_without_featured_id_invention(self):
        self.assertIn('detail.featured?.featuredType == 2', self.target)
        self.assertIn('merchantID == detail.merchant.id', self.target)
        self.assertNotIn('.featuredId', self.target)
        self.assertNotIn('couponID', self.target)
        self.assertIn('RoamFeaturedActivityTarget(node: renderedNode, detail: detail)', self.detail)
        self.assertIn('else if RoamFeaturedCouponWalletTarget(node: renderedNode, detail: detail)', self.detail)

    def test_ordinary_root_browser_and_detail_pass_the_same_factory(self):
        root = (ROOT / 'App/QuestifyApp.swift').read_text()
        browser = (ROOT / 'App/RoamBrowserView.swift').read_text()
        self.assertIn('couponWalletDestination: session.makeRoamCouponWalletDestination(reader: session.roamReader)', root)
        self.assertIn('couponWalletDestination: couponWalletDestination)', browser)
        self.assertIn('self.couponWalletDestination = couponWalletDestination', self.detail)

    def test_explicit_tap_requires_completed_current_read_and_no_other_navigation(self):
        button = self.detail.split('private func featuredCouponWalletButton(', 1)[1].split('private func featuredActivityButton(', 1)[0]
        for check in ['eventIsVisible', '!loading', 'issue == nil', '!merchantFailed',
                      'couponWalletDestination != nil', 'featuredCouponWalletNavigation == nil',
                      'node: node, currentNode: self.node', 'detail: detail, currentDetail: self.merchant',
                      'snapshotID: renderedSnapshot, currentSnapshotID: merchantReadSnapshot']:
            self.assertIn(check, button)
        self.assertIn('featuredCouponWalletNavigation = selection', button)
        self.assertNotIn('couponWalletDestination()', button)
        self.assertIn('.navigationDestination(item: $featuredCouponWalletNavigation)', self.detail)
        self.assertIn('selection.mayRemainOpen(in: eventScope, snapshotID: merchantReadSnapshot), let couponWalletDestination', self.detail)

    def test_scope_record_and_reread_changes_retire_navigation(self):
        for check in ['place == currentPlace', 'place.id == node.id', 'node == currentNode', 'detail == currentDetail',
                      'snapshotID == currentSnapshotID', 'rendered == current', 'origin.readerID == current.readerID',
                      'origin.identity == current.identity', 'origin.area == current.area']:
            self.assertIn(check, self.target)
        self.assertIn('merchantReadSnapshot = UUID(); featuredActivityNavigation = nil; featuredCouponWalletNavigation = nil', self.detail)
        self.assertGreaterEqual(self.detail.count('featuredCouponWalletNavigation = nil'), 5)

    def test_reuses_owned_wallet_with_session_scope_and_no_code_factory(self):
        for check in ['@ObservedObject var session: AppSession', 'self.sessionRevision == revision',
                      'self.contentDetailRevision == contentRevision', 'ObjectIdentifier(self.roamReader) == readerID',
                      'reader.identity == identity', 'reader.searchArea == area',
                      'self.accountCollectionReader.scope == walletScope',
                      'AccountCollectionCouponsView(reader: session.accountCollectionReader)',
                      '.environment(\\.couponCodeFactory, nil)', '.privacySensitive()']:
            self.assertIn(check, self.session)
        for forbidden in ['URLSession', 'couponTemplateId', 'featuredId', 'claim(', 'redeem(', 'CouponCodeView(']:
            self.assertNotIn(forbidden, self.session)

    def test_wallet_factory_creation_never_performs_a_read(self):
        for forbidden in ['ownedCoupons(', 'ownedCoupon(', 'Task {', '.task', 'service.', 'transport.']:
            self.assertNotIn(forbidden, self.session)
        self.assertIn('guard let self, isCurrent()', self.session)
        self.assertIn('if isCurrent()', self.session)

    def test_existing_translations_and_no_new_catalog_are_required(self):
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['merchant.publicHome.featured.openWallet', 'roamEvent.unavailable', 'roamEvent.changed']:
            self.assertTrue(catalog[key]['localizations']['en']['stringUnit']['value'])
            self.assertTrue(catalog[key]['localizations']['zh-Hans']['stringUnit']['value'])
        self.assertIn('"roamFeaturedCouponWallet.open"', self.detail)


if __name__ == '__main__':
    unittest.main()
