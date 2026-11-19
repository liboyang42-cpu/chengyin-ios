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
                       '.animation(reduceMotion ? nil : QuestifyMotion.content, value: isLoading)',
                       'content.animation(reduceMotion ? nil : QuestifyMotion.content, value: value)'):
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
            'GlobalSearchView.swift': 'QuestifyRedactedPlaceholder(label: "searchMap.loading", identifier: "searchMap.loading")',
            'SearchMapExplorerView.swift': 'QuestifyRedactedPlaceholder(label: "searchMap.loading", identifier: "searchMap.loading")',
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
            self.assertTrue('questifyContentSwap(value:' in source or 'transition(.opacity)' in source, name)
        self.assertNotIn('if model.loading { ProgressView("homeFeed.loading") }', read('HomeFeedView.swift'))
        self.assertNotIn('{ ProgressView("topic.loading") }', read('TopicDetailView.swift'))
        self.assertNotIn('{ ProgressView("growth.loading") }', read('GrowthCenterView.swift'))

    def test_profile_sections_stay_on_spinner(self):
        # Reverted in motion-1119: CI ProfileSelfOrdersFlowTests / ProfileSelfEditReturnFlowTests failed with the
        # placeholder + cross-fade on the profile List; kept as base until checked on a simulator.
        self.assertIn('{ ProgressView("profile.loading") }', read('ProfileSelfOrdersSection.swift'))
        self.assertIn('{ ProgressView("creatorContent.loading") }', read('ProfileSelfProjectsSection.swift'))

    def test_error_and_empty_states_are_kept(self):
        self.assertIn('ContentUnavailableView("homeFeed.empty"', read('HomeFeedView.swift'))
        self.assertIn('TopicIssueView(issue: issue)', read('TopicDetailView.swift'))
        self.assertIn('activity.detail.retry', read('ActivityDetailView.swift'))
        self.assertIn('TicketWalletIssueView(issue: issue', read('TicketWalletView.swift'))
        self.assertIn('GrowthCenterIssueView(issue: issue', read('GrowthCenterView.swift'))
        self.assertIn('profile.selfOrders.empty', read('ProfileSelfOrdersSection.swift'))
        self.assertIn('profile.selfProjects.empty', read('ProfileSelfProjectsSection.swift'))

    def test_search_ui_identifier_survives_on_placeholder(self):
        # SearchMapFlowTests wait on descendants(matching: .any)["searchMap.loading"].
        self.assertIn('identifier: "searchMap.loading"', read('GlobalSearchView.swift'))
        self.assertIn('identifier: "searchMap.loading"', read('SearchMapExplorerView.swift'))


class RemoteImages(unittest.TestCase):
    def test_remote_image_reserves_size_fades_in_and_keeps_placeholder_on_failure(self):
        source = read('QuestifyMotionComponents.swift')
        self.assertIn('struct QuestifyRemoteImage', source)
        self.assertIn('static func questifyImageFade(reduceMotion: Bool) -> Transaction', source)
        self.assertIn('struct QuestifyImageLoadingTint', source)
        for name in ('ProfileBadgesView.swift', 'DiscoveryComponents.swift', 'SquareComponents.swift',
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
