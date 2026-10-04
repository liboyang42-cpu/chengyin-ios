"""Supplementary source assertions; Swift/Apple execution remains separate."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ClubReviewRefreshChecks(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_snapshot_retention_is_narrow_and_read_only(self):
        s = self.read('App/ClubManagementView.swift')
        refresh = s.split('@MainActor private func refresh()')[1].split('@MainActor private func prepare(')[0]
        self.assertIn('error as? ClubManagementListConnectionFailure, failure.canRetain(snapshot)', refresh)
        self.assertIn('else { snapshot = nil; stale = false }', refresh)
        self.assertIn('stale = snapshot != nil', refresh)
        self.assertIn('snapshot = result; stale = false', refresh)
        self.assertNotIn('coordinator.confirm', refresh)
        self.assertNotIn('access.perform', refresh)
        self.assertNotIn('readbackUnavailable = false', refresh.split('do {')[0])
        self.assertIn('.disabled(loading || stale || !contextMatches || state.preventsNewAction)', s)
        self.assertIn('contextMatches, !stale, !state.preventsNewAction, !loading', s)
        self.assertIn('guard contextMatches, !stale, pending.identity == identity', s)
    def test_role_revision_is_threaded_from_session(self):
        self.assertIn('viewerRevision:compositionViewerRevision', self.read('App/AppSession.swift'))
        self.assertIn('viewerRevision:management.viewerRevision', self.read('App/ClubDetailView.swift'))
        self.assertIn('var viewerRevision: UInt64 = 0', self.read('App/ClubManagementContext.swift'))
        s = self.read('App/ClubManagementView.swift')
        self.assertIn('.task(id: readContext)', s)
        self.assertIn('if contextMatches, let snapshot', s)
        self.assertIn('if contextMatches, let pending = confirmation', s)
        self.assertGreaterEqual(s.count('viewerRevision == revision, screenRevision == revision'), 5)
        self.assertIn('leaveScreen()\n            generation', s)
    def test_only_connection_failures_after_permission_check_are_classified(self):
        s = self.read('Core/ClubManagementService.swift')
        part = s.split('func snapshot(')[1].split('func perform(')[0]
        self.assertLess(part.index('guard club.canGovern'), part.index('do {'))
        self.assertIn('try checkSession()\n            try Task.checkCancellation()', part)
        self.assertIn('ClubManagementListConnectionFailure(freshClub: club, error: error)', part)
        policy = self.read('Core/ClubManagementContracts.swift').split('public struct ClubManagementListConnectionFailure')[1]
        self.assertIn('let error = error as? URLError', policy)
        self.assertIn('default: return nil', policy)
        for gate in ['old.id == freshClub.id', 'old.isOwner == freshClub.isOwner', 'old.viewerIsAdmin == freshClub.viewerIsAdmin', 'old.isJoined == freshClub.isJoined']:
            self.assertIn(gate, policy)
    def test_unknown_write_and_confirmation_guards_are_retained(self):
        s = self.read('App/ClubManagementView.swift')
        self.assertIn('state = coordinator.state(clubID: clubID)', s)
        self.assertIn('coordinator.leaveScreen(clubID: clubID, expectedIdentity: screenIdentity, ownerID: ownerID)', s)
        self.assertIn('if case .acknowledged = state', s)
        self.assertIn('LabeledContent("club.management.target")', s)
        self.assertIn('case .outcomeUnknown:', s)
    def test_authored_runtime_cases_cover_recovery_privacy_and_unknown(self):
        s = self.read('Tests/AppUITests/ClubManagementFlowTests.swift')
        for name in ['testTransientRefreshRetainsReadOnlyContextAndRetryRestoresReview', 'testTransientListRefreshPreservesApplicantWithoutClaimingFreshness', 'testDeniedAndMalformedRefreshClearPrivateApplicantData', 'testRoleOnlyChangeClearsStaleApplicantWithoutAccountChange', 'testRoleOnlyChangeDoesNotClearUnknownWriteLock', 'testInterruptedRefreshClearsLoadingAndLateFailureCannotReplaceFreshList', 'testRoleABAWhileReadPendingCannotRestoreOldReview']:
            self.assertIn('func '+name, s)
        s = self.read('Tests/CoreTests/ClubManagementTests.swift')
        for name in ['testOnlyClassifiedConnectionFailuresCanRetainSamePermissionSnapshot', 'testServiceRequiresFreshPermissionBeforeClassifyingListFailure', 'testServerPermissionFailureAndChangedRoleCannotRetain']:
            self.assertIn('func '+name, s)
if __name__ == '__main__': unittest.main()
