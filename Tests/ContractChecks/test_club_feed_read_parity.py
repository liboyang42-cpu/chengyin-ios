"""Native-local structural guards. No Apple execution or external source acceptance."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def source(path):
    return (ROOT / path).read_text()

class ClubFeedReadParityContracts(unittest.TestCase):
    def test_feed_requests_limit_and_only_posts_keep_pagination(self):
        contract = source('Core/ClubGovernanceContracts.swift')
        self.assertIn('case .feed: allowed = ["limit"]; fields["limit"] = .integer(20)', contract)
        self.assertIn('if self == .feed { guard (1...50).contains(fields["limit"]?.int ?? 0)', contract)
        self.assertIn('case .posts: allowed = ["pageNum", "pageSize"]', contract)
        view = source('App/ClubGovernanceViews.swift')
        self.assertIn('if operation == .feed { options = ["limit": .integer(20)] }', view)
        self.assertIn('if operation == .posts, snapshot != nil {', view)
        self.assertNotIn('[.feed, .posts]', view)
        self.assertNotIn('[.feed, .posts]', contract)

    def test_typed_projection_reads_only_source_fields_and_bounds_media(self):
        core = source('Core/ClubFeedPresentation.swift')
        for field in ['id', 'clubId', 'nickname', 'avatar', 'content', 'images', 'createTime', 'clubName']:
            self.assertIn('record["' + field + '"]', core)
        self.assertIn('.prefix(3).compactMap', core)
        self.assertIn('parts.scheme == "https"', core)
        self.assertIn('parts.user == nil, parts.password == nil', core)
        self.assertNotIn('authorMemberId', core)
        self.assertNotIn('memberId', core)
        self.assertNotIn('Date()', core)
        self.assertNotIn('URLSession', core)
        self.assertNotIn('api/', core)

    def test_unknown_count_and_identity_are_not_coerced_to_empty(self):
        core = source('Core/ClubFeedPresentation.swift')
        self.assertIn('ClubGovernanceValidation.validate(snapshot.value, operation: .feed', core)
        self.assertIn('guard let count = value["clubCount"].int, count >= 0', core)
        self.assertIn('ClubCustomerHistoryTopicRoute.positiveID(record["clubId"])', core)
        view = source('App/ClubGovernanceViews.swift')
        self.assertIn('if feed.posts.isEmpty', view)
        self.assertIn('club.feed.emptyNoClubs', view)
        self.assertIn('club.feed.emptyPosts', view)

    def test_club_home_uses_existing_reader_without_inheriting_mutation_context(self):
        view = source('App/ClubHomeView.swift')
        binding = view.split('ClubGovernanceHomeEntries(feedContext:')[1].split('identity: reader.clubIdentity')[0]
        self.assertIn('readerIdentity: ObjectIdentifier(reader)', binding)
        self.assertIn('viewerRevision:', binding)
        self.assertIn('ClubDetailView(id: id, reader: reader, onSignIn: onSignIn)', binding)
        for token in ['actionCoordinator:', 'community:', 'management:']:
            self.assertNotIn(token, binding)

    def test_navigation_rechecks_exact_snapshot_row_reader_and_content(self):
        core = source('Core/ClubFeedPresentation.swift')
        for token in ['context.operation == .feed', 'context.scope == .init()', 'context.accepts(snapshot)',
                      'context.readerIdentity != nil', 'context.accessIdentity != nil', '(context.identity?.accountID ?? 0) > 0',
                      'self.snapshotGeneration == snapshotGeneration', '== [post.record]', '== [record]']:
            self.assertIn(token, core)
        view = source('App/ClubGovernanceViews.swift')
        for token in ['guard feedClub == nil, current(target)', 'if let destination = feedContext.destination, current(target)',
                      'destination(target.clubID).id(target.id)', 'accessIdentity: ObjectIdentifier(access)']:
            self.assertIn(token, view)

    def test_refresh_and_invalidation_remove_selection_and_media_scope(self):
        view = source('App/ClubGovernanceViews.swift')
        self.assertGreaterEqual(view.count('feedClub = nil; feedMediaScope = UUID()'), 2)
        self.assertIn('.task(id: readContext)', view)
        self.assertIn('.onChange(of: readContext)', view)
        self.assertIn('.onDisappear { generation &+= 1 }', view)
        self.assertIn('context.accepts(result)', view)
        self.assertIn('snapshotContext = context; snapshotGeneration = revision; snapshot = result', view)
        self.assertNotIn('.onDisappear { snapshot = nil', view)

    def test_media_reuses_bounded_existing_tile_and_disabled_default(self):
        card = source('App/ClubGovernanceFeedPostView.swift')
        for token in ['NativeMediaImage(raw: avatar', 'NativeMediaGalleryEntry(sources: post.images, scope: mediaScope',
                      '.id(mediaScope)', 'var imageReader: (any RetainedPublicImageReading)? = nil']:
            self.assertIn(token, card)
        self.assertIn('feedContext.imageReader ?? RetainedPublicImageReader()', source('App/ClubGovernanceViews.swift'))
        for token in ['AsyncImage', 'URLSession', 'origins:', 'enabled: true', 'SocialPublicProfileView', 'authorMemberId']:
            self.assertNotIn(token, card)
        service = source('Core/RetainedPublicImageReader.swift')
        self.assertIn('enabled: Bool = false, origins: Set<String> = []', service)

    def test_current_read_and_late_401_fences_are_preserved(self):
        service = source('Core/ClubGovernanceService.swift')
        read = service.split('public func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue], check readCheck:')[1].split('public func send(')[0]
        catch = read.split('} catch {')[1]
        self.assertLess(catch.index('try checkRead('), catch.index('onUnauthorized(session.identity)'))
        view = source('App/ClubGovernanceViews.swift')
        self.assertGreaterEqual(view.count('context == readContext'), 2)
        self.assertIn('access.identity == expected', view)

    def test_core_authored_coverage_and_synthetic_only_ui_fixture(self):
        tests = source('Tests/CoreTests/ClubFeedPresentationTests.swift')
        for name in ['testInvalidSourceClubPreservesPostButCannotNavigate', 'testSelectionExpiresForViewerReaderAccessAuthorityAndReadRevisions',
                     'testRemovedRetargetedOrChangedContentCannotRenderOldDestination', 'testLateSuccessAnd401AfterAccountEpochOrLogoutAreRejected',
                     'testLateSuccessAnd401AfterRevisionABAAndNewerReloadAreRejected', 'testCurrent401StillExpiresOnceForEnvelopeAndHTTP']:
            self.assertIn(name, tests)
        fixture = source('App/ClubFeedFixtureHost.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('let allowsOfflineWrites = false', fixture)
        self.assertNotIn('URLSession', fixture)
        self.assertIn('ClubDetailView(id: id, reader: reader)', fixture)
        ui = source('Tests/AppUITests/ClubFeedReadFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 6)
        self.assertIn('testAccountChangeClosesSelectedClubAndClearsPriorFeed', ui)
