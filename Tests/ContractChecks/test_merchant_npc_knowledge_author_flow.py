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

    def test_character_page_submits_four_fields_and_stays_unpublished(self):
        page = read('App/MerchantOperationsEditor.swift')
        host = read('App/MerchantOperationsViews.swift')
        session = read('App/AppSession.swift')
        root = read('App/AppCompositionRoot.swift')
        project = read('Questify.xcodeproj/project.pbxproj')
        hunk = read('docs/issue5-hunks/C06-author-page-read.hunk')
        call = page.index('await submitAuthoredFields()')
        character = page.index('case .character(let value):')
        template = page.index('case .template(let value):')
        self.assertLess(character, call)
        self.assertLess(call, template)
        fn = page[page.index('func submitAuthoredFields()'):]
        for token in ['guard let flow = authorFlow else { return }',
                      'MerchantNPCFieldDraft(field: .name, source: source)',
                      'MerchantNPCFieldDraft(field: .greeting, source: source)',
                      'MerchantNPCFieldDraft(field: .persona, source: source)',
                      'MerchantNPCFieldDraft(field: .knowledge, source: source)',
                      'flow.supply(name: name, greeting: greeting, persona: persona, knowledge: knowledge, source: source)',
                      'flow.ingestAsAIDraft()',
                      'MerchantNPCAuthorizer(accountID: flow.gate.scope.accountID, merchantRowID: flow.gate.scope.merchantRowID)',
                      'flow.verify(authorizer)',
                      'flow.submitForOriginalReview(requestID: UUID())',
                      'flow.recoverFromDraftRead(memberID: draftReadMemberID, requestID: draftReadRequestID, read: draftRead)',
                      'guard flow.gate.phase == phase else { return }',
                      'flow.stayedOnMissingPublisher',
                      'flow.gate.published == nil',
                      'flow.gate.phase != .published',
                      'Text("merchantNPC.draft.unpublished").font(.footnote)',
                      '.font(.body)']:
            self.assertIn(token, page)
        self.assertLess(fn.index('flow.supply('), fn.index('ingestAsAIDraft()'))
        self.assertLess(fn.index('ingestAsAIDraft()'), fn.index('flow.verify('))
        self.assertLess(fn.index('flow.verify('), fn.index('submitForOriginalReview('))
        self.assertLess(fn.index('submitForOriginalReview('), fn.index('recoverFromDraftRead('))
        self.assertLess(fn.index('recoverFromDraftRead('), fn.index('flow.gate.phase == phase'))
        for token in ['publishApproved', 'theme/draft', 'MerchantNPCGrants', 'MerchantNPCKnowledgeAuthorFlow(',
                      'MerchantNPCWaitingSourcePublisher(', 'LinearGradient', '.shadow', '.font(.custom',
                      'playerConsume', '🔥', '✨']:
            self.assertNotIn(token, page)
        self.assertIn('var authorFlow: MerchantNPCKnowledgeAuthorFlow? = nil', page)
        self.assertIn('authorFlow: authorFlow', host)
        self.assertIn('var authorFlow: MerchantNPCKnowledgeAuthorFlow? = nil', host)
        self.assertNotIn('MerchantNPCKnowledgeAuthorFlow(', host)
        self.assertNotIn('publishApproved', host)
        self.assertNotIn('theme/draft', host)
        for source in (session, root, project):
            self.assertNotIn('MerchantNPCKnowledgeAuthorFlow', source)
            self.assertNotIn('submitAuthoredFields', source)
        for token in ['Do not apply', 'App/AppSession.swift', 'App/AppCompositionRoot.swift',
                      'Questify.xcodeproj/project.pbxproj', 'MerchantNPCKnowledgeAuthorFlow(',
                      'publisher: nil', 'authorFlow: flow', 'Not inserted']:
            self.assertIn(token, hunk)
        self.assertNotIn('publishApproved', hunk)
        self.assertNotIn('theme/draft', hunk)
        self.assertEqual(self.tests.count('func test'), 4)
        self.assertIn('NOT_RUN', Path(__file__).read_text())


if __name__ == '__main__':
    unittest.main()
