"""Offline source assertions for the NPC knowledge author flow. Swift XCTest is NOT_RUN on Linux."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class MerchantNPCKnowledgeAuthorFlowContracts(unittest.TestCase):
    def setUp(self):
        self.flow = read('Core/MerchantNPCKnowledgeAuthorFlow.swift')
        self.tests = read('Tests/CoreTests/MerchantNPCKnowledgeAuthorFlowTests.swift')
        self.gate = read('Core/MerchantNPCDraftApprovalGate.swift')

    def test_author_flow_wraps_gate_without_rewriting_publish(self):
        for token in ['MerchantNPCFieldDraft', 'MerchantNPCTextField.allCases',
                      'ingestAIDraft', 'verifyByAuthorizer', 'submitOriginalReview',
                      'recoverFromDraftRead', 'playerConsume',
                      'knowledgeReviewAuthority', 'knowledgeDraftHTTP',
                      'name.field == .name', 'greeting.field == .greeting',
                      'persona.field == .persona', 'knowledge.field == .knowledge']:
            self.assertIn(token, self.flow)
        self.assertLess(self.flow.index('func supply'), self.flow.index('func ingestAsAIDraft'))
        self.assertLess(self.flow.index('func ingestAsAIDraft'), self.flow.index('func verify'))
        self.assertLess(self.flow.index('func verify'), self.flow.index('func submitForOriginalReview'))
        self.assertLess(self.flow.index('func submitForOriginalReview'), self.flow.index('func recoverFromDraftRead'))
        self.assertLess(self.flow.index('func recoverFromDraftRead'), self.flow.index('func playerConsume'))
        self.assertNotIn('publishApproved', self.flow)
        self.assertNotIn('theme/draft', self.flow)
        self.assertNotIn('reviewedPolicyVersion', self.flow)
        self.assertNotIn('encodesLiveCommerceMutation: Bool { true }', self.flow)
        self.assertIn('class MerchantNPCDraftApprovalGate', self.gate)
        self.assertNotIn('MerchantNPCKnowledgeAuthorFlow', self.gate)

    def test_missing_publisher_stays_unpublished_and_consume_stays_closed(self):
        for token in ['testAuthorSuppliesFieldsThenIngestsVerifiesAndStaysUnpublished',
                      'testSubmittedReviewDoesNotPublishAndPlayerConsumeStaysClosed',
                      'testCatalogKeepsWholeFieldTextAndDoesNotTruncate',
                      'testInvalidSupplyAndIngestBeforeAuthorDoNotOccupy',
                      'missingReviewCapability', 'missingPublishCapability',
                      'stayedOnMissingPublisher', '.waitingSource', '.unpublished',
                      'c06-author-1', 'publisher.published, 0']:
            self.assertIn(token, self.tests)
        self.assertNotIn('theme/draft', self.tests)
        self.assertNotIn('reviewedPolicyVersion', self.tests)
        self.assertEqual(self.tests.count('func test'), 4)
        self.assertIn('NOT_RUN', Path(__file__).read_text())


if __name__ == '__main__':
    unittest.main()
