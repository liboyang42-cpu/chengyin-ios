"""Supplementary integrated-source gates. These do not execute Swift or XCTest."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class IntegratedReadCompositionContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_only_exact_validated_route_predicates_admit_queries(self):
        source = self.read('App/AppCompositionRoot.swift')
        self.assertIn('ManualMapReadRoute(request: request, baseURL: api.baseURL, area: $0.area)', source)
        self.assertIn('PlayReadRoute(request: request, baseURL: api.baseURL)', source)
        self.assertIn('guard url.query == nil || manualRead != nil || playRead != nil || cityRead != nil else', source)
        for marker in ['deployment.reads.contains(.manualMap)', 'deployment.reads.contains(.playNodesAndRouteState)',
                       'deployment.contentDetails == .activityAndTopic', 'captured.isSignedInContentViewer']:
            self.assertIn(marker, source)

    def test_central_clone_preserves_all_callbacks_and_current_mutable_selector(self):
        source = self.read('App/AppCompositionRoot.swift')
        copy = source.split('private func copy(', 1)[1].split('func send(', 1)[0]
        for marker in ['deployment: deployment', 'ownerDraftReadApproval: ownerDraftReadApproval',
                       'manualMapReadApproval: manualMapReadApproval', 'manualMapSelection: manualMapSelection',
                       'transport.current = { self.current() }',
                       'transport.playReadConfiguration = { self.playReadConfiguration($0) }']:
            self.assertIn(marker, copy)
        self.assertIn('return compositionTransport.replacingUnderlying(injected)', self.read('App/AppSession.swift'))
        self.assertNotIn('transport.playReadConfiguration = compositionTransport.playReadConfiguration', self.read('App/AppSession.swift'))

    def test_predispatch_success_and_error_have_identity_and_approval_fences(self):
        source = self.read('App/AppCompositionRoot.swift')
        self.assertEqual(source.count('guard current() == captured'), 3)
        self.assertIn('current.playReadApprovalID == issued.playReadApprovalID', source)
        self.assertIn('currentApproval.revision == approval.revision', source)
        self.assertIn('manualMapSelection?.snapshot == selectedArea', source)
        session = self.read('App/AppSession.swift')
        self.assertEqual(session.count('self.currentPlayReadApprovalKey == key.approval'), 3)
        self.assertIn('currentSession: { current() == captured ? captured : nil }', session)
        self.assertIn('guard let self, snapshot == captured, current() == captured else { return }', session)
        self.assertIn('manualMapApprovalRevision: currentManualMapApprovalRevision', session)
        self.assertIn('manualMapApprovalRevision:self.currentManualMapApprovalRevision', session)

    def test_defaults_remain_closed_and_public_home_approvals_remain_separate(self):
        source = self.read('App/AppCompositionRoot.swift')
        self.assertIn('reads: Set<ReadGrant> = []', source)
        self.assertIn('contentDetails: SignedInContentDetailReadApproval? = nil', source)
        self.assertIn('RuntimeDependencyConfiguration? = { _ in nil }', source)
        self.assertIn('ManualMapReadApproval? = { _ in nil }', source)
        self.assertIn('deployment.reads.contains(.publicTopicTemplateCatalogAndDetail)', source)
        self.assertIn('deployment.reads.contains(.homeAndSearch)', source)
        self.assertIn('let grant = deployment.privateHome', source)
        launch = self.read('App/RegionalLaunchConfiguration.swift')
        self.assertIn('.init(deployment: .unconfigured)', launch)
        for grant in ['manualMap', 'playNodesAndRouteState', 'contentDetails']:
            self.assertNotIn(grant, launch)

    def test_cross_family_regressions_are_authored_and_in_apple_target(self):
        source = self.read('Tests/AppUnitTests/IntegratedReadCompositionTests.swift')
        names = ['testBothCloneOrdersPreserveAllReadFamiliesAndExistingOwnerCallback',
                 'testEarlyClonesObserveMutablePlayInstallationRevocationAndReplacement',
                 'testThreeDeploymentGrantsAreIndependentAcrossBothCloneOrders',
                 'testRuntimeReadApprovalsDoNotAuthorizeSiblingFamilies',
                 'testQueryExceptionCannotLaunderCrossFamilyOrUnreviewedRoutes',
                 'testAllThreeReadGrantsStillLeavePublicHomePrivateHomeAndWritesClosed',
                 'testGuestAndPartialIdentityCannotBorrowAnySignedInReadGrant',
                 'testManualAreaReplacementDoesNotDisableSiblingDetailAndPlay',
                 'testSameViewerReissueCancelsCloneInflightSuccessHTTP401AndThrown401',
                 'testRootIdentityABAAndTaskCancellationFenceAllClonedFamilies']
        for name in names:
            self.assertIn('func ' + name, source)
        self.assertIn('Tests/AppUnitTests/IntegratedReadCompositionTests.swift', self.read('Questify.xcodeproj/project.pbxproj'))

if __name__ == '__main__':
    unittest.main()
