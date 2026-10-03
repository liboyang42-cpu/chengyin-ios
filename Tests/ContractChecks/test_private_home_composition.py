"""Supplementary wiring/source guards. AppSession XCTest requires Apple execution."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class PrivateHomeCompositionContracts(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_shipping_remains_unconfigured_and_all_inputs_default_off(self):
        root = self.text('App/AppCompositionRoot.swift')
        self.assertIn('.init(deployment: .unconfigured)', self.text('App/RegionalLaunchConfiguration.swift'))
        self.assertIn('privateHome: PrivateHomeTransportGrant? = nil', root)
        self.assertIn('privateHomeKeychain: (any PrivateHomeKeychainPrimitive)? = nil', root)
        self.assertIn('privateHome?.storageScope == storageScope', root)
        self.assertNotIn('PrivateHomeSystemKeychain()', root)
    def test_private_home_has_exact_method_path_and_owner_grant(self):
        root = self.text('App/AppCompositionRoot.swift')
        for text in ['api.baseURL.appendingPathComponent(PrivateHomeService.path)',
                     '["GET", "PUT", "DELETE"].contains(request.httpMethod ?? "")',
                     'grant.matches(storageScope: deployment.storageScope, accountID: captured.accountID, role: captured.role)',
                     'let token = captured.token, AuthRequestBuilder.isValidToken(token)',
                     'url.query == nil', 'url.fragment == nil', 'current() == captured']:
            self.assertIn(text, root)
        factory = self.text('App/PrivateHomeComposition.swift')
        self.assertNotIn('OperationEndpointApproval(', factory)
        self.assertNotIn('URLSessionTransport', factory)
    def test_factory_always_requires_secure_adapter_and_full_context(self):
        source = self.text('App/PrivateHomeComposition.swift')
        for text in ['context.session.namespace == reviewed.storageScope.service',
                     'context.market == reviewed.regional.market, context.baseURL == api.baseURL',
                     'let primitive = storage.privateHomeKeychain', 'PrivateHomeKeychainJournal(storageScope:',
                     'current() == context ? context.session : nil', 'journal: journal']:
            self.assertIn(text, source)
    def test_session_hooks_revoke_without_deleting_unknown_and_wire_normal_root(self):
        source = self.text('App/AppSession.swift')
        gate = next(line for line in source.splitlines() if 'private var gate = SessionOperationGate()' in line)
        self.assertIn('didSet', gate); self.assertIn('synchronizePrivateHome()', gate)
        self.assertIn('private func synchronizeAccountMarketingEntry() {\n        synchronizePrivateHome()', source)
        block = source.split('func invalidatePrivateHome() {', 1)[1].split('private var committingAuthenticatedSession', 1)[0]
        self.assertIn('retainedPrivateHome?.coordinator.invalidate(); retainedPrivateHome = nil', block)
        self.assertNotIn('clear(', block)
        self.assertIn('guard !committingAuthenticatedSession, privateHomePresentationActive else { return nil }', source)
        self.assertIn('guard let self, !self.committingAuthenticatedSession else { return nil }', source)
        app = self.text('App/QuestifyApp.swift')
        self.assertIn('privateHomeCoordinator:session.privateHomeCoordinator', app)
        self.assertIn('.onDisappear { session.setPrivateHomePresentationActive(false) }', app)
        self.assertIn('.onAppear { session.setPrivateHomePresentationActive(true) }', app)
    def test_authored_app_tests_cover_normal_owner_recovery_and_revocation(self):
        source = self.text('Tests/AppUnitTests/PrivateHomeCompositionTests.swift')
        for name in ['testNormalRootInjectsStableSessionCoordinatorAndDurableJournal',
                     'testDeleteUsesExactDurableContractAndCancelDoesNotSend',
                     'testAuthenticatedNoGrantAndMissingDurableStorageMakeZeroHomeHTTP',
                     'testLockedStorageBlocksLoadBeforeHTTPAndSaveBeforeMutation',
                     'testLogoutAndSameOwnerReentryReloadExactUnknownDurableRequest',
                     'testColdRecreationRecoversSameOwnerButDifferentAccountAndRealmDoNot',
                     'testRoleTokenAndRootChangesSynchronouslyClearRetainedDisplay',
                     'testLate401AndMutationSuccessCannotExpireOrPopulateReplacement',
                     'testSameEpochRoleAndRootABACannotApplyLateMutationOrClearPendingEvidence',
                     'testSameEpochRoleAndRootABACannotApplyLatePrivateHomeRead',
                     'testExactFeatureTransportGrantCannotAuthorizeUnrelatedMethodsRoutesOrOwners']:
            self.assertIn('func ' + name, source)
