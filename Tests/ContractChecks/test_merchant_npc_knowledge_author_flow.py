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
                      'await readHeldThemeDraft(flow)',
                      'holdThemeDraftRequest(memberID: memberID, requestID: requestID)',
                      'reader.readAndRecover(flow)',
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
        self.assertLess(fn.index('submitForOriginalReview('), fn.index('readHeldThemeDraft('))
        self.assertLess(fn.index('readHeldThemeDraft('), fn.index('flow.gate.phase == phase'))
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

    def test_theme_draft_request_read_calls_held_get_and_does_not_publish(self):
        caller = read('Core/MerchantNPCThemeDraftRequestRead.swift')
        tests = read('Tests/CoreTests/MerchantNPCThemeDraftRequestReadTests.swift')
        hunk = read('docs/issue5-hunks/C06-theme-draft-request-read.hunk')
        page = read('App/MerchantOperationsEditor.swift')
        session = read('App/AppSession.swift')
        root = read('App/AppCompositionRoot.swift')
        project = read('Questify.xcodeproj/project.pbxproj')
        self.assertIn('api/ai/theme/draft/request', caller)
        self.assertIn('URLQueryItem(name: "requestId"', caller)
        self.assertIn('httpMethod = "GET"', caller)
        self.assertIn('forHTTPHeaderField: "Authorization"', caller)
        self.assertIn('heldThemeDraftRequestID', caller)
        self.assertIn('memberId', caller)
        self.assertIn('recoverFromDraftRead', caller)
        self.assertIn('NOT_FOUND', caller)
        self.assertIn('isThemeDraftRequestID', caller)
        self.assertLess(caller.index('isThemeDraftRequestID'), caller.index('transport.send'))
        self.assertNotIn('publishApproved', caller)
        self.assertNotIn('httpMethod = "POST"', caller)
        self.assertNotIn('UUID()', caller)
        self.assertNotIn('URLSession(', caller)
        self.assertNotIn('Bearer ', caller)
        self.assertNotIn('api/ai/theme/draft/quota', caller)
        self.assertNotIn('api/ai/theme/draft"', caller)
        self.assertNotIn("api/ai/theme/draft'", caller)
        self.assertIn('holdThemeDraftRequest', self.flow)
        self.assertIn('heldThemeDraftRequestID', self.flow)
        self.assertIn('isThemeDraftRequestID', self.flow)
        self.assertNotIn('theme/draft', self.flow)
        self.assertNotIn('publishApproved', self.flow)
        self.assertNotIn('UUID()', self.flow)
        for name in ['testMatchingRequestAndMemberPassesHitAndDoesNotPublish',
                     'testNotFoundLeavesPhaseUnchanged',
                     'testMismatchedRequestIdDoesNotPassHit',
                     'testReturnedMemberIdMismatchDoesNotPassHit',
                     'testMismatchedMemberDoesNotSendOrPublish',
                     'testInvalidRequestIdIsRejectedBeforeRead',
                     'testMissingHeldRequestDoesNotInventOne',
                     'testReadFailureLeavesPhaseUnchanged']:
            self.assertIn(name, tests)
        self.assertEqual(tests.count('func test'), 8)
        self.assertIn('httpMethod, "GET"', tests)
        self.assertIn('"/api/ai/theme/draft/request"', tests)
        self.assertIn('NOT_FOUND', tests)
        self.assertIn('publisher.published, 0', tests)
        self.assertNotIn('func submitAuthoredFields()', page.replace('func submitAuthoredFields()', '', 1))
        for source in (session, root, project):
            self.assertNotIn('MerchantNPCThemeDraftRequestRead', source)
            self.assertNotIn('holdThemeDraftRequest', source)
        for token in ['Do not apply', 'App/AppSession.swift', 'App/AppCompositionRoot.swift',
                      'Questify.xcodeproj/project.pbxproj', 'merchantOperationsDestination',
                      'publisher: nil', 'let caller = MerchantNPCThemeDraftRequestRead',
                      'Not inserted', 'submitAuthoredFields', 'api/ai/theme/draft/request',
                      'NOT_FOUND', 'does not invent']:
            self.assertIn(token, hunk)
        self.assertNotIn('readAndRecover(flow)', hunk)
        self.assertIn('NOT_RUN', Path(__file__).read_text())
        self.assertIn('NOT_RUN', hunk)

    def test_manage_editor_reads_held_request_and_does_not_publish(self):
        page = read('App/MerchantOperationsEditor.swift')
        host = read('App/MerchantOperationsViews.swift')
        session = read('App/AppSession.swift')
        root = read('App/AppCompositionRoot.swift')
        project = read('Questify.xcodeproj/project.pbxproj')
        hunk = read('docs/issue5-hunks/C06-manage-draft-read.hunk')
        submit = page[page.index('func submitAuthoredFields()'):page.index('func readHeldThemeDraft')]
        read_fn = page[page.index('func readHeldThemeDraft'):page.index('struct MerchantOperationsConfirmationView')]
        self.assertIn('await readHeldThemeDraft(flow)', submit)
        self.assertLess(submit.index('submitForOriginalReview('), submit.index('readHeldThemeDraft('))
        self.assertLess(submit.index('readHeldThemeDraft('), submit.index('flow.gate.phase == phase'))
        self.assertIn('guard let memberID = draftReadMemberID, let requestID = draftReadRequestID', read_fn)
        self.assertIn('flow.holdThemeDraftRequest(memberID: memberID, requestID: requestID)', read_fn)
        self.assertIn('let reader = themeDraftRequestRead else { return }', read_fn)
        self.assertIn('reader.readAndRecover(flow)', read_fn)
        self.assertLess(read_fn.index('draftReadMemberID'), read_fn.index('holdThemeDraftRequest'))
        self.assertLess(read_fn.index('holdThemeDraftRequest'), read_fn.index('readAndRecover(flow)'))
        self.assertLess(read_fn.index('else { return }'), read_fn.index('readAndRecover(flow)'))
        self.assertNotIn('UUID()', read_fn)
        self.assertNotIn('_ = caller', page)
        self.assertNotIn('publishApproved', page)
        self.assertNotIn('httpMethod = "POST"', page)
        self.assertNotIn('api/ai/theme/draft"', page)
        self.assertNotIn("api/ai/theme/draft'", page)
        self.assertNotIn('recoverFromDraftRead(memberID: draftReadMemberID, requestID: draftReadRequestID, read: draftRead)', page)
        self.assertIn('case .character(let value):', page)
        self.assertIn('case .template(let value):', page)
        self.assertIn('Button("merchantNPC.author.submit")', page)
        self.assertIn('themeDraftRequestRead: themeDraftRequestRead', host)
        self.assertIn('var themeDraftRequestRead: MerchantNPCThemeDraftRequestRead? = nil', host)
        self.assertNotIn('MerchantNPCThemeDraftRequestRead(', host)
        self.assertNotIn('holdThemeDraftRequest', host)
        self.assertNotIn('readAndRecover', host)
        self.assertNotIn('_ = caller', host)
        for source in (session, root, project):
            self.assertNotIn('MerchantNPCThemeDraftRequestRead', source)
            self.assertNotIn('readHeldThemeDraft', source)
            self.assertNotIn('holdThemeDraftRequest', source)
            self.assertNotIn('themeDraftRequestRead', source)
        for token in ['Do not apply', 'App/AppSession.swift', 'App/AppCompositionRoot.swift',
                      'Questify.xcodeproj/project.pbxproj', 'merchantOperationsDestination',
                      'merchantStoreCharacterDestination', 'publisher: nil',
                      'let caller = MerchantNPCThemeDraftRequestRead',
                      'themeDraftRequestRead: caller', 'heldThemeDraftMemberID',
                      'heldThemeDraftRequestID', 'draftReadMemberID: heldMember',
                      'draftReadRequestID: heldRequest', 'Text("manage"',
                      'MerchantStoreCharacterView', 'MerchantOperationsDocumentView',
                      'Not inserted', 'does not mint', 'readHeldThemeDraft']:
            self.assertIn(token, hunk)
        self.assertNotIn('_ = caller', hunk)
        self.assertNotIn('UUID()', hunk)
        self.assertNotIn('publishApproved', hunk)
        self.assertNotIn('readAndRecover(flow)', hunk)
        self.assertNotIn('httpMethod = "POST"', hunk)
        self.assertIn('NOT_RUN', hunk)
        self.assertIn('NOT_RUN', Path(__file__).read_text())


if __name__ == '__main__':
    unittest.main()
