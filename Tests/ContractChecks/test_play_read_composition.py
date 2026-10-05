"""Supplementary source contracts; app/Core XCTest and Apple runtime remain separate."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PlayReadCompositionContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_query_exception_is_a_closed_typed_request_matcher(self):
        matcher = self.read('Core/PlayReadRoute.swift')
        for text in ['case nodes = "api/play/nodes"', 'case routeState = "api/play/route-state"',
                     'request.httpMethod == "GET"', 'request.httpBody == nil', 'request.httpBodyStream == nil',
                     'items.count == 1', 'id > 0, String(id) == value', 'case "activityId"', 'case "topicId"',
                     'canonical?.url?.absoluteString == url.absoluteString']:
            self.assertIn(text, matcher)
        self.assertNotIn('hasPrefix(', matcher)
        root = self.read('App/AppCompositionRoot.swift')
        self.assertIn('guard url.query == nil || manualRead != nil || playRead != nil', root)
        self.assertIn('PlayReadRoute(request: request, baseURL: api.baseURL)', root)

    def test_root_and_current_runtime_are_independent_and_fail_closed(self):
        root = self.read('App/AppCompositionRoot.swift')
        matcher = self.read('Core/PlayReadRoute.swift')
        self.assertIn('deployment.reads.contains(.playNodesAndRouteState)', root)
        self.assertIn('RuntimeDependencyConfiguration? = { _ in nil }', root)
        for text in ['configuration.matches(context)', 'configuration.play.contains(.reads)',
                     'configuration.endpoints.paths.contains(endpoint.rawValue)']:
            self.assertIn(text, matcher)
        self.assertIn('readApprovalStillValid?() != false', root)
        self.assertIn('current() == captured', root)
        session = self.read('App/AppSession.swift')
        self.assertIn('compositionTransport.playReadConfiguration = { [weak self] context in', session)
        self.assertIn('self.currentRuntimeDependencyContext == context', session)
        self.assertIn('return (self.injectedRuntimeDependencies ?? self.composition.sessionDependencies(context)).configuration', session)
        self.assertIn('return compositionTransport.replacingUnderlying(injected)', session)
        self.assertIn('transport.playReadConfiguration = { self.playReadConfiguration($0) }', root)
        self.assertIn('current.playReadApprovalID == issued.playReadApprovalID', root)
        self.assertEqual(session.count('self.currentPlayReadApprovalKey == key.approval'), 3)
        self.assertIn('currentSession: { current() == captured ? captured : nil }', session)
        self.assertIn('guard let self, snapshot == captured, current() == captured else { return }', session)
        self.assertIn('private var playReadDependencyFactory: RuntimeDependencyFactory?', session)
        config = self.read('Core/RuntimeDependencyConfiguration.swift')
        self.assertIn('playReadApprovalID: UUID? = nil', config)
        self.assertIn('configuration.playReadApprovalID != nil', matcher)

    def test_escaped_legacy_and_rich_readers_have_role_aba_fences(self):
        session = self.read('App/AppSession.swift')
        play = session.split('private var playService:', 1)[1].split('// Journey extras', 1)[0]
        self.assertEqual(play.count('self.compositionViewerRevision == key.viewerRevision'), 3)
        self.assertIn('let current: () -> PlayExperienceSession?', play)
        self.assertIn('currentSession: { current() == captured ? captured : nil }', play)
        self.assertIn('let viewerRevision:UInt64', play)
        self.assertIn('playReaders.removeAll()', session)
        self.assertIn('playExperienceCoordinators.values.forEach { $0.invalidate() }', session)

    def test_read_only_progress_does_not_enable_controls_or_durable_writes(self):
        coordinator = self.read('Core/PlayExperienceCoordinator.swift')
        self.assertIn('!service.enabled.isDisjoint(with: [.classicCompletion, .hints, .leader, .thoughtClaims])', coordinator)
        session = self.read('App/AppSession.swift')
        self.assertNotIn('PlayMemoryCompletionRecovery()', session)
        self.assertNotIn('PlayMemoryPausedStorage()', session)
        self.assertIn('composition.storage.playRecovery.make(session: captured, scope: scope,', session)
        self.assertIn('regionalConfiguration: regional, storageScope: storageScope)', session)
        self.assertIn('recovery: recovery, pausedStorage: recovery', session)
        self.assertIn('PlayRecoveryAccountRole(rawValue: account.effectiveRole)', session)
        self.assertIn('token: token, role: role.rawValue)', session)
        self.assertIn('answersEnabled:false', session)
        self.assertIn('loadedSession == currentSession() ? storedSnapshot : nil', coordinator)
        launch = self.read('App/RegionalLaunchConfiguration.swift')
        self.assertNotIn('playNodesAndRouteState', launch)

    def test_synthetic_recovery_is_explicit_and_cannot_forge_system_provenance(self):
        root = self.read('App/AppCompositionRoot.swift')
        self.assertIn('playRecovery: PlayRecoveryConstruction = .system', root)
        seam = self.read('App/PlayRecoveryComposition.swift')
        self.assertIn('enum PlayRecoveryAccountRole: String { case player, club, merchant }', seam)
        self.assertIn('storageScope.matches(configuration: regionalConfiguration)', seam)
        self.assertIn('session.namespace.utf8.elementsEqual(storageScope.service.utf8)', seam)
        self.assertIn('#if DEBUG\n    case synthetic', seam)
        self.assertIn('case .unavailable:\n            throw PlayExperienceError.persistenceUnavailable', seam)
        synthetic = seam.split('case .synthetic(let anchors, let ciphertexts):', 1)[1].split('case .unavailable:', 1)[0]
        self.assertIn('anchors: anchors, ciphertexts: ciphertexts', synthetic)
        self.assertNotIn('SystemFactory', synthetic)
        self.assertNotIn('system:', synthetic)
        tests = self.read('Tests/AppUnitTests/PlayReadCompositionTests.swift')
        self.assertIn('recovery ?? .synthetic(anchors: PlayReadAnchors(), ciphertexts: PlayReadCiphertexts())', tests)
        self.assertIn('tokenStore: { _ in vault }, playRecovery: recovery)', tests)
        for name in ['testRootReopenKeepsUnknownCompletionAndNeverSendsDuplicate',
                     'testRootUnavailableLockedAndCorruptRecoveryNeverBecomesEmptyOrDispatches',
                     'testRootRoleBindingRejectsArbitraryRolesAndCannotReadAnotherRolePending',
                     'testSyntheticConstructionChecksRegionalNamespaceAndRoleWithoutProductionStorage']:
            self.assertIn(name, tests)
        for forbidden in ['SecItem', 'NSHomeDirectory', 'ContentDraftSystemAnchors(', 'ContentDraftSystemCiphertexts(']:
            self.assertNotIn(forbidden, tests)

    def test_read_only_run_and_each_mutation_capability_remain_independent(self):
        coordinator = self.read('Core/PlayExperienceCoordinator.swift')
        for text in ['public var canManageRun: Bool { service.enabled.contains(.runPersistence) && hasCurrentMediaSnapshot && !localRecoveryFailed && pausedLease?.value?.pendingRemote != true }',
                     'guard service.enabled.contains(.classicCompletion), canWrite',
                     'guard service.enabled.contains(.classicCompletion), phase == .unknown',
                     'guard service.enabled.contains(.hints), canWrite',
                     'guard service.enabled.contains(.leader), canWrite',
                     'guard service.enabled.contains(.runPersistence), let session',
                     'guard canManageRun, let session']:
            self.assertIn(text, coordinator)
        self.assertIn('disabled(!model.canManageRun)', self.read('App/PlayExperienceView.swift'))
        self.assertIn('enabled: factory.accepted?.play.intersection([.reads]) ?? []', self.read('App/AppSession.swift'))
        self.assertIn('XCTAssertFalse(model.canWrite)', self.read('Tests/CoreTests/ChapterThoughtSyncTests.swift'))

    def test_ending_protocol_fix_does_not_expand_root_routes(self):
        service = self.read('Core/PlayExperienceService.swift')
        self.assertIn('request("api/play/ending", query: scopeFields(scope), capability: .reads', service)
        self.assertNotIn('api/play/ending', self.read('Core/PlayReadRoute.swift'))
        self.assertIn('testEndingMatchesExistingGETControllerWithOneCanonicalScope', self.read('Tests/CoreTests/PlayEndingReadProtocolTests.swift'))

    def test_normal_session_recorder_and_apple_target_are_wired(self):
        tests = self.read('Tests/AppUnitTests/PlayReadCompositionTests.swift')
        for text in ['sessionDependencies:', 'testNormalAppSessionBothReadersDispatchExactAuthenticatedBranchReads',
                     'testGuestUnconfiguredMissingRootMissingRuntimeAndWrongAccountNeverDispatch',
                     'testCurrentHTTPAndBusiness401ExpireMatchingSessionForBothReaders',
                     'testLateRoleABASuccessAnd401CannotPopulateOrExpireSameEpochSession',
                     'testLate401AfterLogoutReloginAndCancellationNeverExpiresReplacement',
                     'testRevokedRuntimeApprovalDropsLate401AtCompositionBoundary']:
            self.assertIn(text, tests)
        project = self.read('Questify.xcodeproj/project.pbxproj')
        self.assertIn('Tests/AppUnitTests/PlayReadCompositionTests.swift', project)
        self.assertIn('Core/PlayReadRoute.swift', project)

if __name__ == '__main__':
    unittest.main()
