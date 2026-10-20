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
        self.assertIn('var communityGate: (any SquareCommunityFeatureReading)? = nil', view)
        self.assertIn('@State private var gateFeatures: SquareCommunityFeatures?', view)
        self.assertIn('@State private var gateScope: UUID?', view)
        self.assertIn(
            'private var postsAllowed: Bool { guard let communityGate else { return true }; '
            'return gateScope == communityGate.scope && gateFeatures?.read == true }',
            view,
        )
        self.assertIn('.task(id: communityGate?.scope) { await loadGate() }', view)

    def test_posts_allowed_hides_posts_tab_when_community_gate_is_closed_pending_or_failed(self):
        view = self.text('App/AccountCollectionFavoritesView.swift')
        host = view.split('@MainActor struct AccountCollectionFavoritesView: View {', 1)[1].split(
            '@MainActor private struct AccountCollectionFavoriteTopicsView: View {', 1
        )[0]
        self.assertIn('if postsAllowed {\n                Picker("accountCollection.favorites.title", selection: $selectedTab)', host)
        self.assertIn('if postsAllowed && selectedTab == .posts {', host)
        self.assertIn('guard let communityGate, reader.isAuthenticated, reader.isConfigured, gateScope != communityGate.scope else { return }', host)
        self.assertIn('let scope = communityGate.scope', host)
        self.assertIn('let value = try? await communityGate.communityFeatures()', host)
        self.assertIn('guard !Task.isCancelled, scope == communityGate.scope else { return }', host)
        self.assertIn('gateFeatures = value; gateScope = scope', host)

    def test_existing_lifecycle_and_removal_confirmation_readback_remain_intact(self):
        view = self.text('App/AccountCollectionFavoritesView.swift')
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

        removal = self.text('Core/ProfileFavoriteRemoval.swift')
        self.assertIn('["api/creativesquare/info", "api/creativesquare/bookmark"]', removal)
        self.assertIn('let marked = try await bookmarked(value)', removal)
        self.assertIn('guard !stillMarked else', removal)

        tests = self.text('Tests/CoreTests/AccountCollectionTests.swift')
        self.assertIn('func testCommunityGateClosureKeepsFavoriteTopicsReadableWhilePostsRequireScopedReadFlag(', tests)

    def test_no_new_endpoints_or_write_gates_opened(self):
        service = self.text('Core/AccountCollectionService.swift')
        paths = set(re.findall(r'post\("(api/[^"]+)"', service))
        self.assertEqual(paths, {'api/topic/like_list', 'api/coupon/myrecvlist', 'api/creativesquare/list'})
        view = self.text('App/AccountCollectionFavoritesView.swift')
        for forbidden in ['URLSession', 'httpMethod', 'api/topic/like', 'api/creativesquare/bookmark', 'OperationEndpointApproval']:
            self.assertNotIn(forbidden, view)


if __name__ == '__main__':
    unittest.main()
