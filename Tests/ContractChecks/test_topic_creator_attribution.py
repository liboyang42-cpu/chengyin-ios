"""Native-only source checks; these do not execute Swift or SwiftUI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TopicCreatorAttributionChecks(unittest.TestCase):
    def test_public_display_has_no_collaborator_as_creator_projection(self):
        contract = (ROOT / 'Core/TopicContracts.swift').read_text()
        detail = contract.split('public struct TopicDetail:', 1)[1].split('public enum TopicAvailability:', 1)[0]
        for unsupported in ['initiatorName', 'initiatorAvatar', 'TopicCollaboratorRecord', 'collaborators.first']:
            self.assertNotIn(unsupported, contract)
        for unsupported in ['collaboratorsList', 'umsMember', 'contentPublisherName']:
            self.assertNotIn(unsupported, detail)
        self.assertIn('publisherAuthoritySource = try? PublisherTopicAuthoritySource(from: decoder)', detail)
        self.assertIn('isOwner = c.flag("isOwner")', detail)

    def test_person_label_is_omitted_while_club_and_existing_routes_remain(self):
        view = (ROOT / 'App/TopicDetailView.swift').read_text()
        self.assertNotIn('topic.initiator', view)
        self.assertNotIn('initiatorName', view)
        self.assertIn('if let club = value.clubName { Text(verbatim: club) }', view)
        self.assertIn('if let publisherDestination { publisherDestination(value) }', view)
        self.assertIn('if let activities = value.activities', view)

    def test_separate_collaborator_review_projection_and_owner_gate_remain(self):
        evidence = (ROOT / 'Core/PublisherAuthoritySource.swift').read_text()
        self.assertIn('static let collaborator: Self = fields(["memberId", "memberRealName", "memberAvatar", "nickname", "avatar"])', evidence)
        self.assertIn('"collaboratorsList": .array(collaborator)', evidence)
        self.assertIn('let owner = PublisherSourceProjection.flag(body["isOwner"])', evidence)
        self.assertIn('viewerIsOwner = owner', evidence)

    def test_authored_regressions_cover_distinct_person_and_authority_data(self):
        tests = (ROOT / 'Tests/CoreTests/TopicTests.swift').read_text()
        for token in ['testTopicDisplayDoesNotPromoteCollaboratorsOrPublisherToInitiator',
                      'testOmittingInitiatorPreservesSeparateCollaboratorReviewEvidenceAndOwnerProof',
                      '"Public publisher"', '"Content entity"', '"First collaborator"',
                      'XCTAssertEqual(actual, expected', 'XCTAssertFalse(evidence.viewerIsOwner',
                      'XCTAssertNil(try decode(TopicDetail.self, missingOwner).publisherAuthoritySource)']:
            self.assertIn(token, tests)


if __name__ == '__main__':
    unittest.main()
