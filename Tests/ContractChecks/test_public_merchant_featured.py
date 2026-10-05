"""Public merchant card source guards; not Swift compiler or Apple runtime evidence."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PublicMerchantFeaturedChecks(unittest.TestCase):
    def source(self, name):
        return (ROOT / name).read_text()

    def test_only_nested_whitelist_is_consumed(self):
        home = self.source('Core/PublicMerchantHome.swift')
        card = self.source('Core/PublicMerchantFeatured.swift')
        self.assertIn('public let featured: PublicMerchantFeatured?', home)
        self.assertIn('case featuredType, id, featuredId, name, description, imgUrl', card)
        self.assertIn('id > 0, id == featuredID', card)
        self.assertIn('kind == .activity ?', card)
        self.assertIn('case .coupon: return .couponWallet', card)
        for forbidden in ['coverImg', 'couponHistoryId', 'amount', 'URLRequest', '/api/', 'featuredType: Int']:
            self.assertNotIn(forbidden, card)

    def test_selection_fences_identity_scopes_and_snapshot(self):
        card = self.source('Core/PublicMerchantFeatured.swift')
        for text in ['let merchant = home.reviewTarget', 'merchant.ownerMemberID == id',
                     'merchant.merchantRowID == id', 'self.homeScope = homeScope',
                     'self.destinationScope = destinationScope', 'self.snapshotID = snapshotID', 'self == current']:
            self.assertIn(text, card)
        view = self.source('App/PublicMerchantHomeView.swift')
        for text in ['guard !loading, failure == nil, loadedKey == key, context.reader.isConfigured',
                     'destination.isCurrent()', 'value.publicFeatured(for: target)', 'snapshotID = UUID(); featuredSelection = nil',
                     '.onChange(of: key) { _, _ in featuredSelection = nil }',
                     '.onChange(of: context.featured?.scope)', 'guard canOpen(selection) else { return }']:
            self.assertIn(text, view)
        self.assertLess(view.index('.navigationTitle('), view.index('.navigationDestination(item: $featuredSelection)'))

    def test_existing_read_destinations_remain_gated(self):
        app = self.source('App/PublicMerchantFeaturedCard.swift')
        session = self.source('App/AppSession.swift')
        self.assertEqual(session.count('context.featured = makePublicMerchantFeaturedContext(homeReader: context.reader)'), 1)
        for text in ['homeReader.isConfigured', 'self.sessionRevision == revision',
                     'self.contentDetailRevision == contentRevision', 'self.accountCollectionReader.scope == scope',
                     '@ObservedObject var session: AppSession', 'if !isCurrent()',
                     'ActivityDetailView(id: id, reader: session)',
                     'AccountCollectionCouponsView(reader: session.accountCollectionReader)',
                     '.environment(\\.couponCodeFactory, nil)', '.privacySensitive()']:
            self.assertIn(text, app)
        for forbidden in ['registrationEnabled: true', 'playReaderForActivity:', 'AsyncImage(', 'URLSession',
                          'CouponCodeCoordinator(', 'AccountCollectionCouponDetailView(', 'ProductionApproval(']:
            self.assertNotIn(forbidden, app)

    def test_offline_fixture_and_authored_tests_cover_fail_closed_reentry(self):
        fixture = self.source('App/PublicMerchantHomeFixtureView.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        for text in ['featured-unknown', 'featured-malformed', 'featured-null', 'featured-static',
                     'featured-switch', 'featured-unavailable', 'captured == featuredScope']:
            self.assertIn(text, fixture)
        core = self.source('Tests/CoreTests/PublicMerchantFeaturedTests.swift')
        self.assertEqual(core.count('    func test'), 10)
        ui = self.source('Tests/AppUITests/PublicMerchantHomeFlowTests.swift')
        for text in ['testFeaturedActivityUsesExactIDAfterBackAndUnavailableDetail',
                     'testFeaturedCouponOpensWalletWithoutOwnedIDOrCodeInChineseLargeText',
                     'testMissingUnknownAndMalformedFeaturedCardsLeaveProfileUsable',
                     'testFeaturedSelectionClosesWhenReadScopeChangesThenUsesNewSnapshot']:
            self.assertIn(text, ui)

if __name__ == '__main__':
    unittest.main()
