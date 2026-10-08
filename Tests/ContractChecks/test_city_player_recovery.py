"""Supplementary static contracts only; Swift/SwiftUI execution remains Apple-toolchain UNRUN."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CityPlayerRecoveryContracts(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT / 'Core/CityPlayerReading.swift').read_text()
        self.view = (ROOT / 'App/CityPlayerView.swift').read_text()

    def test_exactly_one_recovery_reacquires_whole_snapshot(self):
        recovery = self.core.split('private func readRecoveringSnapshot(', 1)[1].split('private func readSnapshot(', 1)[0]
        self.assertEqual(recovery.count('try await readSnapshot(stamp: stamp)'), 2)
        self.assertEqual(recovery.count('catch CityReadError.snapshotChanged'), 1)
        self.assertIn('guard isConfigured, generation == stamp, !Task.isCancelled', recovery)
        self.assertNotRegex(recovery, r'\b(for|while)\b')
        snapshot = self.core.split('private func readSnapshot(', 1)[1].split('private static func', 1)[0]
        self.assertLess(snapshot.index('read(.current'), snapshot.index('read(.participation'))
        self.assertLess(snapshot.index('read(.participation'), snapshot.index('read(.points'))
        self.assertNotIn('stored =', snapshot)

    def test_owned_transport_task_cancels_on_replace_close_and_caller_cancellation(self):
        for marker in ['@ObservationIgnored private var pendingLoad: Task<Void, Never>?',
                       'guard !Task.isCancelled else { return }', 'pendingLoad?.cancel(); pendingLoad = nil',
                       'onCancel: { task.cancel() }', 'if generation == stamp { pendingLoad = nil }']:
            self.assertIn(marker, self.core)
        self.assertIn('if Self.isUnauthorized(error), isConfigured, !Task.isCancelled', self.core)

    def test_only_visible_active_view_owns_initial_retry_and_resume_tasks(self):
        for marker in ['@Environment(\\.scenePhase)', '.task(id: readRequest)',
                       'guard visible, scenePhase == .active, !Task.isCancelled',
                       '.onAppear { visible = true; readRequest = UUID() }',
                       '.onChange(of: scenePhase)', 'selection = nil; reader.cancel(); readRequest = UUID()',
                       '.onDisappear { visible = false; selection = nil; reader.cancel() }',
                       '.disabled(reader.state == .loading || !visible || scenePhase != .active)']:
            self.assertIn(marker, self.view)
        self.assertNotIn('Task { await reader.load() }', self.view)

    def test_no_new_route_authority_or_business_action(self):
        self.assertIn('case current, participation, points', self.core)
        for marker in ['POST', '"join"', '"capture"', '"wallet"', '"settlement"', '"event_id"', '"cursor"']:
            self.assertNotIn(marker, self.core)
        root = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        self.assertEqual(root.count('cityPlayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval? = { _ in nil }'), 2)

    def test_authored_regressions_cover_recovery_and_interruption_boundaries(self):
        source = (ROOT / 'Tests/CoreTests/CityPlayerReadRecoveryTests.swift').read_text()
        for marker in ['testSnapshotChangeRestartsCurrentAndNeverMixesMembershipOrSeason',
                       'testSecondSnapshotConflictStopsWithoutLoopOrPartialProjection',
                       'testRecoveryPreservesUnpublishedUnavailableAndVerifiedEmptyMeanings',
                       'testUnrelatedErrorsAreNeverAutomaticallyRetried',
                       'testSuspensionCancelsTransportAndForegroundReloadUsesNewSnapshot',
                       'testSupersedingLoadCancelsOldRequestWithoutClearingNewResult',
                       'testCallerCancellationReachesTransportAndDoesNotSignOut',
                       'testRevokedOrChangedOwnerCannotResumeOrRetryOldSnapshot',
                       'testLateUnauthorizedAfterReplacementCannotSignOutOrOverwriteNewRead',
                       'testDefaultOffAndAlreadyCancelledTasksNeverDispatch']:
            self.assertIn(marker, source)
        app = (ROOT / 'Tests/AppUnitTests/CityPlayerReadCompositionTests.swift').read_text()
        self.assertIn('testOneSnapshotRecoveryKeepsNormalRootScopeAndRereadsEveryProjection', app)
        self.assertIn('testRepeatedSnapshotChangeStopsAfterOneRecoveryThroughNormalRoot', app)
