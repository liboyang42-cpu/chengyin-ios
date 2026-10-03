"""Normal merchant public/NPC factory wiring and CURRENT backend source comparison."""
import os
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class MerchantPublicFactoryContractTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_normal_host_consumes_factory_and_resets_retained_context(self):
        session = self.read('App/AppSession.swift')
        self.assertIn('runtimeDependencies.makeMerchantPublicFactory(api: api, journal: merchantNPCJournal', session)
        self.assertIn('merchantPublicFactory?.homeReader ?? disabledPublicMerchantHomeReader', session)
        self.assertIn('retainedMerchantPublicFactory = nil', session)
        self.assertIn('return factory.chatClient(currentScope:', session)
        self.assertNotIn('MerchantNPCAuthenticatedTransport(configuration:', session)
        self.assertNotIn('publicMerchantHomeReader = DisabledPublicMerchantHomeReader()', session)
        self.assertIn('guard MerchantPublicProductionFactory.supportsLegacyResources else', session)
        self.assertIn('role: account?.effectiveRole, token: token', session)

    def test_normal_dependencies_default_off_and_only_exact_factory_injection(self):
        deps = self.read('App/NativeRuntimeDependencies.swift')
        self.assertIn('merchantPublicApproval: MerchantPublicProductionApproval? = nil', deps)
        self.assertIn('merchantNPCGrants: MerchantNPCGrants = .init()', deps)
        self.assertIn('merchantPublicApproval?.matches(context) == true', deps)
        self.assertIn('transport: transportOverride ?? transport ?? ResponseLimitedHTTPTransport(enabled: true)', deps)
        production = self.read('Core/MerchantPublicProduction.swift')
        self.assertIn('publicHomeRead: Bool = false, chatMerchantRows: Set<PublicMerchantRowID> = []', production)
        self.assertIn('market == .china && context.market == market', production)
        self.assertIn('namespace == context.namespace && accountID == context.accountID', production)
        self.assertIn('public static let supportsLegacyResources = false', production)
        self.assertNotIn('URLSessionTransport()', production)
        self.assertNotIn('UserDefaults', production)

    def test_chat_has_readback_request_identity_and_durable_unknown_lock(self):
        production = self.read('Core/MerchantPublicProduction.swift')
        for text in ['homeReader.home(.legacyMerchantRowID(input.scope.merchantRowID))',
                     'input.path == "/api/ai/npc/merchant-chat"',
                     'Set(fields.keys) == ["requestId", "bizId", "message"]',
                     'message.unicodeScalars.count <= 300',
                     'OperationPendingRecord(operationID: id', 'pending != record',
                     'try journal.write(record)', 'data["requestId"] as? String == requestID',
                     'status != "PROCESSING" && !retryable', 'try journal.clear(record)',
                     'guard valid(input.scope), !Task.isCancelled']:
            self.assertIn(text, production)
        self.assertLess(production.index('try journal.write(record)'), production.index('transport.send(request)'))
        for unsupported in ['/api/merchant/npc/voice/script', '/api/merchant/npc/voice/revoke', '/api/merchant/npc/avatar/generate']:
            self.assertNotIn(unsupported, production)

    def test_unit_and_normal_app_factory_tests_are_authored(self):
        tests = self.read('Tests/CoreTests/MerchantPublicProductionTests.swift')
        self.assertGreaterEqual(tests.count('    func test'), 17)
        for name in ['testExactChatFactoryReadsFreshPublicRowThenUsesRawToken',
                     'testUnknownOutcomeRetriesExactIdentityAndBlocksNewIdentityAcrossRecreation',
                     'testProcessingMismatchedReceiptAndLateAccountChangeKeepLock',
                     'testUnsupportedResourceClientAndUnapprovedRowNeverSend']:
            self.assertIn(name, tests)
        app = self.read('Tests/AppUnitTests/MerchantPublicFactoryAppTests.swift')
        self.assertIn('AppSession(runtimeDependencies:', app)
        self.assertIn('d.makeMerchantPublicFactory(', app)
        self.assertGreaterEqual(app.count('    func test'), 3)

class CurrentBackendMerchantSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = os.environ.get('CHENGYIN_BACKEND_SOURCE_ROOT')
        if not path:
            raise unittest.SkipTest('NOT_RUN: explicit CURRENT backend source root not supplied')
        cls.root = pathlib.Path(path)
        if not cls.root.is_dir():
            raise AssertionError('Explicit backend source root does not exist')
        cls.controller = (cls.root / 'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java').read_text()
        cls.ai = (cls.root / 'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiAiNpcController.java').read_text()
        cls.service = (cls.root / 'chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/NpcChatService.java').read_text()

    def test_public_home_is_anonymous_discriminated_identity_and_visibility_checked(self):
        body = self.controller.split('@PostMapping("/public-home")', 1)[1].split('private boolean isPubliclyVisible', 1)[0]
        for text in ['body.get("id")', 'body.get("memberId")', '(id == null) == (memberId == null)',
                     'selectMmsMerchantById(id)', 'selectMmsMerchantByMemberId(memberId)', 'if (!isPubliclyVisible(m))', 'resolveForMerchant(m.getId())']:
            self.assertIn(text, body)
        self.assertNotIn('getAppUserId()', body)

    def test_current_chat_request_and_server_idempotency_match(self):
        body = self.ai.split('@PostMapping("/merchant-chat")', 1)[1].split('@Operation', 1)[0]
        for text in ['npcFeatureFlags.merchantChatOn()', 'getAppUserId()', 'req.getBizId()', 'npcChatService.chatWithMerchant(req, userId, merchantId)']:
            self.assertIn(text, body)
        for text in ['MESSAGE_MAX_CODE_POINTS = 300', 'selectByUserAndRequestId(userId, rid)', 'return fromStored(existing)',
                     'profile -> merchantFactsBuilder.build(profile, merchantId)', '"merchant_npc_chat"']:
            self.assertIn(text, self.service)

    def test_current_voice_is_single_sample_and_reset_not_legacy_five_sample_contract(self):
        enroll = self.controller.split('@PostMapping("/npc/voice/enroll")', 1)[1].split('@PostMapping("/npc/voice/status")', 1)[0]
        for text in ['body.getVoiceConsent()', 'body.getVoiceSample()', 'MerchantPermission.PROFILE_WRITE',
                     'ownNpcOrNull(access.getMerchantId())', 'voiceCloneClient.enroll(sample)', 'r.put("voiceStatus"']:
            self.assertIn(text, enroll)
        self.assertIn('@PostMapping("/npc/voice/reset")', self.controller)
        self.assertNotIn('sampleUrls', enroll)
        api_files = list((self.root / 'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api').glob('*.java'))
        combined = '\n'.join(p.read_text() for p in api_files)
        for unsupported in ['@PostMapping("/npc/voice/script")', '@PostMapping("/npc/voice/revoke")',
                            '@PostMapping("/npc/avatar/generate")', '@PostMapping("/npc/avatar/status")']:
            self.assertNotIn(unsupported, combined)

if __name__ == '__main__':
    unittest.main()
