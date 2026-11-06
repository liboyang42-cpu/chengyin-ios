"""Offline source assertions only. Swift XCTest is NOT_RUN on Linux."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class MerchantNPCDraftCannotPriceContracts(unittest.TestCase):
    def setUp(self):
        self.draft = read('Core/MerchantNPCKnowledgeDraft.swift')
        self.validation = read('Core/MerchantNPCKnowledgeValidation.swift')
        self.coordinators = read('Core/MerchantNPCCoordinators.swift')
        self.http = read('Core/MerchantNPCHTTP.swift')
        self.gate = read('Core/MerchantNPCDraftApprovalGate.swift')
        self.isolation = read('Core/MerchantNPCPublicPrivateIsolation.swift')
        self.revoke = read('Core/MerchantNPCQualificationRevoke.swift')
        self.gate_tests = read('Tests/CoreTests/MerchantNPCDraftApprovalGateTests.swift')
        self.revoke_tests = read('Tests/CoreTests/MerchantNPCQualificationRevokeTests.swift')

    def test_ai_draft_cannot_price_deduct_stock_award_or_certify_presence(self):
        for token in ['encodesLiveCommerceMutation: Bool { false }', 'applyingAICommerce',
                      'livePrice, liveStock, liveAward, livePresence',
                      'case price, deductStock, award, certifyPresence']:
            self.assertIn(token, self.draft)
        for token in ['liveCommerceIssues', 'kind = .livePrice', 'kind = .liveStock',
                      'kind = .liveAward', 'kind = .livePresence']:
            self.assertIn(token, self.validation)
        for token in ['aiCannotPrice', 'aiCannotDeductStock', 'aiCannotAward',
                      'aiCannotCertifyPresence', 'static func commerce']:
            self.assertIn(token, self.gate)
        self.assertIn('refuseAICommerce', self.http)
        self.assertIn('testAICannotPriceDeductStockAwardOrCertifyPresence', self.gate_tests)
        self.assertNotIn('encodesLiveCommerceMutation: Bool { true}', self.draft)

    def test_ai_draft_cannot_publish_without_authorizer_then_player_consumes(self):
        for token in ['ingestAIDraft', 'verifyByAuthorizer', 'submitOriginalReview',
                      'publishApproved', 'playerConsume', 'authorizerRequired',
                      'originalReviewRequired', 'phase == .aiDraft']:
            self.assertIn(token, self.gate)
        self.assertLess(self.gate.index('ingestAIDraft'), self.gate.index('verifyByAuthorizer'))
        self.assertLess(self.gate.index('public func verifyByAuthorizer'), self.gate.index('public func submitOriginalReview(requestID'))
        self.assertLess(self.gate.index('public func submitOriginalReview(requestID'), self.gate.index('public func publishApproved() async'))
        self.assertLess(self.gate.index('public func publishApproved() async'), self.gate.index('public func playerConsume()'))
        self.assertIn('testAIDraftCannotPublishWithoutAuthorizer', self.gate_tests)
        self.assertIn('testAuthorizerThenOriginalReviewThenPlayerConsume', self.gate_tests)

    def test_missing_api_is_waiting_source_not_a_successful_stub(self):
        for token in ['waitingSource(capability:', 'MerchantNpcKnowledgeDraftService.http',
                      'MerchantNpcKnowledgeReviewAuthority.route', 'AiGateway.publicAuth']:
            self.assertIn(token, self.gate + self.http)
        self.assertIn('MerchantNPCWaitingSourcePublisher', self.gate)
        self.assertIn('throw MerchantNPCDraftGateFailure.waitingSource', self.gate)
        self.assertNotIn('return MerchantNPCPublishedRevision', self.gate.split('class MerchantNPCWaitingSourcePublisher')[1].split('enum MerchantNPCDraftDigest')[0])
        self.assertIn('refuseUnservedKnowledgePath', self.http)
        self.assertIn('try refuseUnservedKnowledgePath(path)', self.http)
        self.assertIn('refuseAiGatewayPublicAuth', self.http)
        served = self.http.split('servedPaths: Set<String> = [')[1].split(']')[0]
        self.assertIn('/api/ai/npc/merchant-chat', served)
        self.assertNotIn('knowledge/publish', served)
        self.assertNotIn('AiGateway', served)
        self.assertIn('testMissingReviewAndPublishAPIsAreWaitingSourceNotSuccessfulStubs', self.gate_tests)
        self.assertIn('AiThemeDraftRequestService.read', self.gate)
        self.assertIn('recoverFromDraftRead', self.gate)
        self.assertIn('c06-draft-missing', self.gate_tests)

    def test_reuses_existing_merchant_npc_stack_not_a_parallel_one(self):
        self.assertIn('MerchantNPCKnowledgeDraft', self.gate)
        self.assertIn('MerchantNPCScope', self.gate)
        self.assertIn('MerchantNPCHTTPClient', self.http)
        self.assertIn('applyQualificationRevoke(_ revoke: MerchantNPCQualificationRevoke)', self.coordinators)
        self.assertEqual(self.coordinators.count('applyQualificationRevoke(_ revoke: MerchantNPCQualificationRevoke)'), 2)
        combined = self.gate + self.isolation + self.revoke
        for token in ['class ShopNPC', 'NewNPCStack', 'AiGateway(', 'AppSession']:
            self.assertNotIn(token, combined)

    def test_public_private_isolation_and_theme_mainline_without_ai(self):
        for token in ['themeMainlineAvailableWhenAIUnavailable = true', 'playerPublicNPC',
                      'merchantPrivateAssistant', 'themeRunMayProceed', 'isolationViolation']:
            self.assertIn(token, self.isolation)
        self.assertIn('testThemeMainlineWorksWhenAIUnavailable', self.gate_tests)
        self.assertIn('audience(for: flow.phase), .merchantPrivateAssistant', self.gate_tests)
        self.assertIn('audience(for: flow.phase), .playerPublicNPC', self.gate_tests)

    def test_revoke_clears_cache_so_old_draft_cannot_serve(self):
        for token in ['publicCache[identity] = nil', 'privateDrafts[identity] = nil',
                      'rememberPublished', 'cachedPublic', 'allowsServing']:
            self.assertIn(token, self.revoke)
        self.assertIn('testRevokeClearsCacheSoOldDraftCannotServe', self.revoke_tests)
        self.assertIn('testChatCoordinatorDropsDisplayAfterQualificationRevoke', self.revoke_tests)
        self.assertIn('testOldDraftObjectCannotReenterPublicCacheAfterRevoke', self.revoke_tests)
        self.assertIn('testCachedPublicOfNeverSeenScopeDoesNotOccupyThenUniqueRememberPublishedApplies', self.revoke_tests)
        self.assertIn('applyQualificationRevoke(qualification)', self.revoke_tests)
        self.assertIn('.qualificationRevoked', self.revoke_tests)

    def test_forbidden_shared_files_are_untouched(self):
        self.assertNotIn('AppSession', self.gate + self.isolation + self.revoke + self.http)
        self.assertNotIn('Localizable.xcstrings', self.gate + self.isolation + self.revoke)
        self.assertNotIn('project.pbxproj', self.gate + self.isolation + self.revoke)
        self.assertNotIn('Authorization', self.http.split('refuseAiGatewayPublicAuth')[1].split('private struct Envelope')[0])

    def test_account_switch_isolation_markers_present(self):
        self.assertIn('testOtherAccountScopeCannotRewriteOriginalDraft', self.gate_tests)
        self.assertIn('testRestartedGateDoesNotInventPublishedRevision', self.gate_tests)
        self.assertIn('testUnpublishedCachedPublicDoesNotOccupyThenUniquePublishApplies', self.gate_tests)
        self.assertIn('testUnpublishedProjectionDoesNotOccupyPrivateScopesThenUniqueRetainPrivateApplies', self.gate_tests)
        self.assertIn('testUnusedVerifyBeforeIngestDoesNotOccupyThenUniqueIngestThenVerifyApplies', self.gate_tests)
        self.assertIn('testUnusedSubmitBeforeAuthorizerDoesNotOccupyThenUniqueSubmitApplies', self.gate_tests)
        self.assertIn('testUnusedInvalidIngestDoesNotOccupyThenUniqueValidIngestApplies', self.gate_tests)
        self.assertIn('staleScope', self.gate)
        self.assertIn('Stolen', self.gate_tests)
        self.assertIn('restarted.published', self.gate_tests)

    def test_authored_xctest_count_and_linux_not_run(self):
        self.assertEqual(self.gate_tests.count('func test'), 13)
        self.assertEqual(self.revoke_tests.count('func test'), 4)
        self.assertIn('Linux', Path(__file__).read_text())
        self.assertIn('NOT_RUN', Path(__file__).read_text())


if __name__ == '__main__':
    unittest.main()
