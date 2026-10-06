"""Source wiring checks, not Apple execution or server authorization tests."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class IMHistoryBridgeContracts(unittest.TestCase):
    def read(self, name): return (ROOT/name).read_text()
    def test_only_canonical_history_forms_and_bounded_sizes(self):
        source = self.read('Core/MessagingHistoryReadApproval.swift')
        for item in ['api/im/conversations', 'api/im/messages', 'conversation_id', 'cursor_id', 'size',
                     '(1...50).contains(count)', 'canonical.httpBody == body', 'httpBodyStream == nil',
                     'url.query == nil', 'url.fragment == nil', 'APIConfiguration(baseURL: context.baseURL)']:
            self.assertIn(item, source)
        for path in ['api/im/read', 'api/im/start', 'api/im/send', 'api/im/mute', 'api/im/block', 'api/im/unblock']:
            self.assertNotIn(path, source)
    def test_default_nil_outer_clone_and_completion_fences(self):
        source = self.read('App/AppCompositionRoot.swift')
        self.assertEqual(source.count('messagingHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval? = { _ in nil }'), 2)
        self.assertEqual(source.count('messagingHistoryReadApproval: messagingHistoryReadApproval'), 2)
        self.assertIn('currentApproval.revision == approval.revision && currentApproval.matches(context)', source)
        self.assertIn('current() == captured, readApprovalStillValid?() != false', source)
        self.assertIn('current() == captured, !Task.isCancelled, readApprovalStillValid?() != false', source)
    def test_retained_reader_cannot_adopt_new_lease_or_role_aba(self):
        source = self.read('App/AppSession.swift')
        self.assertNotIn('lazy var messagingReader=', source)
        for text in ['self.compositionViewerRevision == viewerRevision', 'self.currentMessagingHistoryReadApproval?.revision == approval.revision',
                     'ContentDraftContextFence.matches(self.currentRuntimeDependencyContext, context)', 'isAvailable: available',
                     '!factory.routes([.imSend]).isEmpty', 'currentMessageMediaIdentity']:
            self.assertIn(text, source)
        for path in ['App/AccountView.swift', 'App/ClubChatEntryView.swift']:
            self.assertIn('.id(session.messagingViewIdentity)', self.read(path))
        for path in ['App/MessagingComponents.swift', 'App/MessagingHistoryView.swift', 'App/MessagingMessageDetailView.swift']:
            self.assertIn('reader.identity', self.read(path))
        self.assertIn('failure?.isForbidden == true', self.read('App/MessagingComponents.swift'))
    def test_normal_root_and_adversarial_tests_are_authored(self):
        app = self.read('Tests/AppUnitTests/MessagingHistoryCompositionTests.swift')
        for test in ['testNormalFactoryHistoryKeepsSenderPrivacyAndBlockedHistoryWithoutWrites',
                     'testLoadedReaderInvalidatesOnRevocationExpiryRoleABAAndReissue',
                     'testPendingSuccess401AndTransportErrorCannotOutliveExactIssuance',
                     'testCanonicalClonesAllAdjacentMutationsAndCrossScopeStayClosed',
                     'testClonedPendingReadRejectsLeaseAndTokenRotation']:
            self.assertIn(test, app)
        ui = (self.read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift') + '\n' +
              self.read('Tests/AppUITests/IntegratedDeniedAcceptanceFlowTests.swift'))
        self.assertIn('testNormalRootIMHistoryNeverMarksReadOrSends', ui)
        self.assertIn('testNormalRootIMHistoryDefaultNilNeverDispatches', ui)
