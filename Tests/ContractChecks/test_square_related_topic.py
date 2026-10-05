"""Related-topic read wiring checks only; Swift and Apple UI remain separate gates."""
import pathlib
import json
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SquareRelatedTopicChecks(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_route_is_namespace_bound_and_never_guesses_a_topic(self):
        source = self.text('Core/SquareRelatedTopic.swift')
        for item in ['source.valid, source.id == post.id, source.generation == post.generation',
                     'case .legacySquare: topicID = post.relatedTopicIDs.legacy',
                     'case .communityV1: topicID = post.relatedTopicIDs.community',
                     'case .unknown: return nil', 'root["sportTopicId"]',
                     'reference.first("reference_type", "referenceType").string == "TOPIC"',
                     'self.squareScope == squareScope && self.topicScope == topicScope',
                     'guard let id, id > 0 else { return nil }']:
            self.assertIn(item, source)
        for item in ['post.dataID', 'post.id == topicID', 'URLRequest', 'URLSession', 'token', '/api/']:
            self.assertNotIn(item, source)

    def test_normal_root_supplies_only_existing_reader(self):
        source = self.text('App/QuestifyApp.swift')
        self.assertEqual(source.count('.environment(\\.squareRelatedTopic, .init(squareScope: session.squareReader.scope, reader: session.topicReader))'), 1)
        source = self.text('App/SquareRelatedTopicView.swift')
        self.assertIn('static let defaultValue: SquareRelatedTopicContext? = nil', source)
        self.assertIn('context.squareScope == squareReader.scope', source)
        self.assertIn('guard selected.isCurrent(squareScope: squareReader.scope, topicScope: context.reader.scope)', source)
        self.assertIn('TopicDetailView(id: selection.route.topicID, reader: topicReader)', source)
        self.assertIn('.privacySensitive()', source)
        for item in ['URLSession', 'AppSession(', 'topicService', 'selfPlayDestination:', 'reviewOwner:', 'publisherDestination:', 'SocialActionCoordinator(']:
            self.assertNotIn(item, source)

    def test_detail_mounts_route_outside_lazy_rows_and_invalidates_scope(self):
        source = self.text('App/SquareDetailView.swift')
        self.assertIn('SquareRelatedTopicLink(post: post, source: .init(id: id, generation: contentGeneration), squareReader: reader)', source)
        self.assertLess(source.index('.appNavigationTitle("square.detail")'), source.index('.navigationDestination(item: $relatedTopic)'))
        self.assertIn('.onChange(of: key) { _, _ in relatedTopic = nil }', source)
        self.assertIn('.onChange(of: relatedTopicContext?.reader.scope) { _, _ in relatedTopic = nil }', source)
        self.assertIn('operation == generation, captured == key', source)

    def test_authored_coverage_includes_invalid_ids_reentry_and_failure(self):
        core = self.text('Tests/CoreTests/SquareRelatedTopicTests.swift')
        self.assertEqual(core.count('    func test'), 9)
        for item in ['testEqualNumericPostIDsNeverCrossGenerations', 'testInvalidAssociationIDsStayAbsentInsteadOfBeingTruncated',
                     'testBothReadScopesFenceASelectedAssociation', 'testOnlyTheDisplayedFirstReferenceIsNavigable']:
            self.assertIn(item, core)
        ui = self.text('Tests/AppUITests/SquareFlowTests.swift')
        for item in ['testRelatedTopicOpensExactLegacyReadAndReopensAfterBack',
                     'testCommunityTopicReferenceAndMissingLegacyAssociationRemainSeparate',
                     'testUnavailableRelatedTopicKeepsPostAccessibleAfterBack', 'Synthetic linked topic 31', 'Synthetic linked topic 32']:
            self.assertIn(item, ui)
        fixture = self.text('App/SquareFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertNotIn('https://', fixture)

    def test_community_ui_fixture_uses_wrapped_topic_in_feed_and_detail(self):
        fixture = self.text('App/SquareFixtureSupport.swift')
        feed = fixture.split('func squareFeed(', 1)[1].split('func squareDetail(', 1)[0]
        detail = fixture.split('func squareDetail(id:', 1)[1].split('private func relatedCommunityPost()', 1)[0]
        self.assertIn('if scenario == .relatedCommunity {\n            return .init(items: cursor == nil ? [try relatedCommunityPost()] : [], hasMore: false)', feed)
        self.assertIn('if scenario == .relatedCommunity {\n            let post = try relatedCommunityPost()\n            guard post.id == id else { throw SquareReadFailure.unavailable }\n            return post', detail)
        helper = fixture.split('private func relatedCommunityPost()', 1)[1].split('func squareComments(', 1)[0]
        self.assertIn('JSONDecoder().decode(SquarePost.self, from: Data(SquareSyntheticFixtures.wrappedPostJSON.utf8)).qualified(as: .communityV1)', helper)
        source = self.text('Core/SquareSyntheticFixtures.swift')
        match = re.search(r'public static let wrappedPostJSON = #"(.*?)"#', source)
        self.assertIsNotNone(match)
        payload = json.loads(match.group(1))
        self.assertEqual(payload['post']['id'], 702)
        reference = payload['references'][0]
        self.assertEqual(reference['reference_type'], 'TOPIC')
        self.assertEqual(int(reference['reference_id']), 32)
        self.assertNotIn('sportTopicId', payload)

if __name__ == '__main__':
    unittest.main()
