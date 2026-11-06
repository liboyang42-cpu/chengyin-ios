"""Package 03 contract check: Account Favorites Contract Closure (我的收藏契约收口)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class Pkg03FavoritesClosureTests(unittest.TestCase):
    def text(self, path: str) -> str:
        return (ROOT / path).read_text()

    def test_community_gate_property_and_state_on_favorites_view(self):
        view = self.text('App/AccountCollectionFavoritesView.swift')
        model = self.text('Core/AccountCollectionReading.swift')
        self.assertIn('var communityGate: (any SquareCommunityFeatureReading)? = nil', view)
        self.assertIn('@State private var gateModel = AccountCollectionCommunityGateModel()', view)
        for removed in ['@State private var gateFeatures', '@State private var gateScope', '@State private var gateFailed']:
            self.assertNotIn(removed, view)
        self.assertIn('private var postsAllowed: Bool { gateModel.postsAllowed(reader: reader, gate: communityGate) }', view)
        self.assertNotIn('guard let communityGate else { return true }', view)
        self.assertIn('guard hasGate, let currentScope, !isLoading, !failed else { return false }', model)
        self.assertIn('.task(id: gateKey) { await gateModel.load(reader: { reader }, gate: { communityGate }) }', view)
        self.assertIn('gateModel.invalidateIfIdentityChanged(reader: { reader }, gate: { communityGate })', view)

    def test_both_formal_hosts_inject_session_square_reader_gate(self):
        account = self.text('App/AccountView.swift')
        self.assertIn('communityGate: session.squareReader', account)
        links = self.text('App/AccountCollectionFavoritesView.swift').split(
            '@MainActor struct AccountCollectionAccountLinks: View {', 1
        )[1]
        self.assertIn('var communityGate: (any SquareCommunityFeatureReading)? = nil', links)
        self.assertIn('favoriteRemoval: favoriteRemoval, communityGate: communityGate', links)

        route = self.text('App/ProfileSettingsFavoritesRoute.swift')
        self.assertIn('let communityGate: (any SquareCommunityFeatureReading)?', route)
        self.assertIn('let gate: ObjectIdentifier?', route)
        self.assertIn('let gateScope: UUID?', route)
        self.assertIn('gate: communityGate.map { ObjectIdentifier($0) }, gateScope: communityGate?.scope', route)
        self.assertIn('communityGate: session.squareReader', route)
        self.assertIn('communityGate: route.access.communityGate', route)
        fixture = self.text('App/AccountCollectionFixtureSupport.swift')
        self.assertIn('AccountCollectionFixtureGate: SquareCommunityFeatureReading', fixture)
        self.assertIn('SquareCommunityFeatures(read: true, write: false)', fixture)
        self.assertIn('communityGate: communityGate', fixture)

    def test_posts_allowed_hides_posts_tab_when_community_gate_is_closed_pending_or_failed_and_supports_retry(self):
        view = self.text('App/AccountCollectionFavoritesView.swift')
        host = view.split('@MainActor struct AccountCollectionFavoritesView: View {', 1)[1].split(
            '@MainActor private struct AccountCollectionFavoriteTopicsView: View {', 1
        )[0]
        self.assertIn('if postsAllowed {\n                Picker("accountCollection.favorites.title", selection: $selectedTab)', host)
        self.assertIn('if postsAllowed && selectedTab == .posts {', host)
        model = self.text('Core/AccountCollectionReading.swift')
        gate = model.split('public final class AccountCollectionCommunityGateModel', 1)[1]
        self.assertIn('let value = try await gateNow.communityFeatures()', gate)
        self.assertIn('resolvedScope = nil', gate)
        self.assertIn('failed = true', gate)
        topics = view.split('@MainActor private struct AccountCollectionFavoriteTopicsView: View {', 1)[1].split(
            'private struct AccountCollectionFavoriteCard: View {', 1
        )[0]
        self.assertLess(topics.index('async let gateReload: Void = reloadGate()'), topics.index('await model.refresh(reader: reader, pageSize: pageSize)'))
        load_more = topics.split('private func loadMore() async {', 1)[1]
        self.assertNotIn('retryGate', load_more)
        self.assertIn('await gateModel.load(reader: { reader }, gate: { communityGate }, forceRetry: gateModel.failed)', host)
        self.assertEqual(
            view.count('AccountCollectionReadLifecycle(key: key, refresh: refresh, cancel: model.cancelPending)'),
            2,
        )
        self.assertIn('.modifier(TopicUnlikeFlow(controller: unlike) { unliked.insert($0) })', view)
        self.assertIn('ProfileFavoriteRecoverySection(scope: renderedScope, controller: favoriteRemoval,', view)
        self.assertIn('ProfileFavoriteRemovalEntry(post: post, scope: key.scope, controller: favoriteRemoval,', view)

        route = self.text('App/ProfileSettingsFavoritesRoute.swift')
        self.assertIn('favoriteRemoval: route.access.removal', route)
        self.assertIn('onOpenTopic: { owner.openTopic($0, from: route, current: current()) }', route)
        self.assertIn('onOpenPost: { owner.openPost($0, from: route, current: current()) }', route)
        self.assertIn('route?.id == offered.id', route)
        self.assertIn('foreground, route == nil', route)

        removal = self.text('Core/ProfileFavoriteRemoval.swift')
        self.assertIn('["api/creativesquare/info", "api/creativesquare/bookmark"]', removal)
        self.assertIn('let marked = try await bookmarked(value)', removal)
        self.assertIn('guard !stillMarked else', removal)

        tests = self.text('Tests/CoreTests/AccountCollectionTests.swift')
        self.assertIn('func testCommunityGateClosureKeepsFavoriteTopicsReadableWhilePostsRequireScopedReadFlag(', tests)
        self.assertIn('func testCommunityGateModelFailureRetryRecoveryAndScopeReset(', tests)
        self.assertIn('func testNilUnauthenticatedUnconfiguredAndPendingGateStayClosedWhileTopicsLoad(', tests)
        self.assertIn('func testGateFailureRetriesAndOutOfOrderResultsStayWithTheNewerAttempt(', tests)
        self.assertIn('func testReplacedReaderOrGateAndABACannotReviveACancelledGateAttempt(', tests)
        self.assertIn('CheckedContinuation', tests)

    def test_no_new_endpoints_or_write_gates_opened(self):
        service = self.text('Core/AccountCollectionService.swift')
        paths = set(re.findall(r'post\("(api/[^"]+)"', service))
        self.assertEqual(paths, {'api/topic/like_list', 'api/coupon/myrecvlist', 'api/creativesquare/list'})
        view = self.text('App/AccountCollectionFavoritesView.swift')
        for forbidden in ['URLSession', 'httpMethod', 'api/topic/like', 'api/creativesquare/bookmark', 'OperationEndpointApproval']:
            self.assertNotIn(forbidden, view)


if __name__ == '__main__':
    unittest.main()
