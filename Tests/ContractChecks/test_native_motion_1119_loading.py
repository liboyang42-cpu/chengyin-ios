"""motion-1119: shared loading container, remote image fade and numeric transitions. Offline source guard only."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / 'App'


def read(name):
    return (APP / name).read_text()


class SharedLoadingContainer(unittest.TestCase):
    def test_container_redacts_cross_fades_and_respects_reduce_motion(self):
        source = read('QuestifyMotionComponents.swift')
        for needle in ('struct QuestifyLoadingContainer', 'struct QuestifyRedactedPlaceholder',
                       '.redacted(reason: .placeholder)', '.allowsHitTesting(false)',
                       '.accessibilityLabel(Text(label))',
                       '.animation(reduceMotion || isLoading ? nil : QuestifyMotion.content, value: isLoading)',
                       'content.animation(reduceMotion || isLoading ? nil : QuestifyMotion.content, value: isLoading)'):
            self.assertIn(needle, source)
        # Placeholder → content swap reads the shared fadeSwap token, never a literal duration.
        block = source.split('// MARK: - motion-1119', 1)[1]
        self.assertIsNone(re.search(r'duration:\s*\d', block))
        self.assertIn('@QuestifyReduceMotion private var reduceMotion', block)

    def test_high_traffic_screens_use_placeholder_not_spinner_for_first_load(self):
        expected = {
            'HomeFeedView.swift': 'QuestifyRedactedPlaceholder(label: "homeFeed.loading"',
            'TopicDetailView.swift': 'QuestifyDetailListPlaceholder(label: "topic.loading"',
            'ActivityDetailView.swift': 'QuestifyDetailListPlaceholder(label: "activity.loading"',
            'TicketWalletView.swift': 'QuestifyPlaceholderRows(label: "ticketWallet.loading"',
            'TicketWalletDetailView.swift': 'QuestifyPlaceholderRows(label: "ticketWallet.loading"',
            'GrowthCenterView.swift': 'QuestifyPlaceholderRows(label: "growth.loading"',
            'SquareDetailView.swift': 'QuestifyPlaceholderRows(label: "square.loading"',
            'RoamItemDetailView.swift': 'QuestifyDetailListPlaceholder(label: "roam.loading"',
            'AccountCollectionCouponsView.swift': 'QuestifyPlaceholderRows(label: "accountCollection.loading"',
            'DiscoveryHomeView.swift': 'QuestifyRedactedPlaceholder(label: "discovery.loading"',
        }
        for name, needle in expected.items():
            source = read(name)
            self.assertIn(needle, source, name)
            self.assertTrue('questifyContentSwap(isLoading:' in source or 'transition(.opacity)' in source, name)
        self.assertNotIn('if model.loading { ProgressView("homeFeed.loading") }', read('HomeFeedView.swift'))
        self.assertNotIn('{ ProgressView("topic.loading") }', read('TopicDetailView.swift'))
        self.assertNotIn('{ ProgressView("growth.loading") }', read('GrowthCenterView.swift'))

    def test_profile_sections_stay_on_spinner(self):
        # Reverted in motion-1119: CI ProfileSelfOrdersFlowTests / ProfileSelfEditReturnFlowTests failed with the
        # placeholder + cross-fade on the profile List; kept as base until checked on a simulator.
        self.assertIn('{ ProgressView("profile.loading") }', read('ProfileSelfOrdersSection.swift'))
        self.assertIn('{ ProgressView("creatorContent.loading") }', read('ProfileSelfProjectsSection.swift'))

    def test_content_leaves_without_fade(self):
        # GrowthCenterFlowTests.testSessionChangeClearsPrivateBoardAndNavigation: after sign-out the private
        # board must be gone at once, so only placeholder → content animates.
        source = read('QuestifyMotionComponents.swift')
        self.assertNotIn('questifyContentSwap<V', source)
        for path in (APP).glob('*.swift'):
            self.assertNotIn('.questifyContentSwap(value:', path.read_text(), path.name)

    def test_error_and_empty_states_are_kept(self):
        self.assertIn('ContentUnavailableView("homeFeed.empty"', read('HomeFeedView.swift'))
        self.assertIn('TopicIssueView(issue: issue)', read('TopicDetailView.swift'))
        self.assertIn('activity.detail.retry', read('ActivityDetailView.swift'))
        self.assertIn('TicketWalletIssueView(issue: issue', read('TicketWalletView.swift'))
        self.assertIn('GrowthCenterIssueView(issue: issue', read('GrowthCenterView.swift'))
        self.assertIn('profile.selfOrders.empty', read('ProfileSelfOrdersSection.swift'))
        self.assertIn('profile.selfProjects.empty', read('ProfileSelfProjectsSection.swift'))

    def test_search_screens_stay_on_main(self):
        # Reverted in motion-1119: SearchMapFlowTests global-category cases failed in CI, and both files are
        # byte-pinned by test_global_search_category_recovery. Kept as main until checked on a simulator.
        self.assertIn('ProgressView("searchMap.loading").frame(maxWidth: .infinity).accessibilityIdentifier("searchMap.loading")', read('GlobalSearchView.swift'))
        self.assertNotIn('QuestifyRedactedPlaceholder', read('SearchMapExplorerView.swift'))


class RemoteImages(unittest.TestCase):
    def test_remote_image_reserves_size_fades_in_and_keeps_placeholder_on_failure(self):
        source = read('QuestifyMotionComponents.swift')
        self.assertIn('struct QuestifyRemoteImage', source)
        self.assertIn('static func questifyImageFade(reduceMotion: Bool) -> Transaction', source)
        self.assertIn('struct QuestifyImageLoadingTint', source)
        # ProfileBadgesView kept as base after ProfileSelfMedalsFlowTests failed in CI on the profile page.
        for name in ('DiscoveryComponents.swift', 'SquareComponents.swift',
                     'RoamStampViews.swift', 'ClubCommunityViews.swift', 'ClubPostImageGallery.swift'):
            body = read(name)
            self.assertIn('.questifyImageFade(reduceMotion: reduceMotion)', body, name)
            self.assertIn('.transition(.opacity)', body, name)
        for name in ('SquareComponents.swift', 'RoamStampViews.swift'):
            self.assertIn('QuestifyImageLoadingTint().overlay', read(name), name)
            self.assertNotIn('else { ProgressView(', read(name).split('AsyncImage(', 1)[1].split('}.frame', 1)[0], name)


class NumericTransitions(unittest.TestCase):
    def test_points_and_balances_roll(self):
        components = read('QuestifyMotionComponents.swift')
        self.assertIn(".contentTransition(reduceMotion ? .identity : .numericText(value: value))", components)
        # GrowthCenterInteger kept as base: ProfileSelfGrowthFlowTests (staticTexts["700"]) failed in CI with numericText.
        self.assertNotIn('questifyNumericTransition', read('GrowthCenterComponents.swift'))
        wallet = read('WalletCommerceViews.swift')
        self.assertEqual(wallet.count('LabeledContent("wallet.pointsBalance") { Text(verbatim: format.points('), 2)
        self.assertEqual(wallet.count('.questifyNumericTransition(value:'), 2)


if __name__ == '__main__':
    unittest.main()
