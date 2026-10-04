from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class JoinedInvitationDetailNavigationTests(unittest.TestCase):
    def test_current_members_only_enter_fresh_exact_id_route(self):
        text = (ROOT / 'App/TeamHomeView.swift').read_text()
        joined = text.split('if detail.joined == true {', 1)[1].split('else { actionButton', 1)[0]
        self.assertIn('TeamDetailView(lookup: .id(detail.team.id), coordinator: makeCoordinator(), makeCoordinator: makeCoordinator, requiresMembership: true)', joined)
        self.assertIn('team.invitation.openDetail', joined)
        self.assertIn('.disabled(model.actionLocked)', joined)
        self.assertIn('loadDetail(lookup, requireMembership: requiresMembership)', text)

    def test_membership_refresh_fails_closed_and_keeps_existing_identity_checks(self):
        text = (ROOT / 'Core/TeamCoordinator.swift').read_text()
        body = text.split('public func loadDetail(', 1)[1].split('public func loadCreation(', 1)[0]
        self.assertIn('if requireMembership {\n            detail = nil\n            guard case .id = lookup', body)
        self.assertIn('guard active(session, stamp)', body)
        self.assertIn('result.team.id != id', body)
        self.assertIn('if requireMembership, result.joined != true { detail = nil; throw TeamFailure.invalidContract }', body)
        self.assertIn('try restorePending(targetKey: "team-\\(result.team.id)", session: session)', body)
        self.assertNotIn('submit(', body)

    def test_normal_and_fixture_factories_are_wired(self):
        for file in ['SessionTeamViews.swift', 'NativeNavigationCompletionViews.swift', 'TeamFixtureSupport.swift']:
            lines = (ROOT / 'App' / file).read_text().splitlines()
            calls = [line for line in lines if 'TeamDetailView(lookup:' in line]
            self.assertTrue(calls)
            for line in calls:
                self.assertIn('makeCoordinator:', line)

    def test_authored_behavior_tests_cover_back_revocation_and_locks(self):
        core = (ROOT / 'Tests/CoreTests/TeamCoordinatorTests.swift').read_text()
        ui = (ROOT / 'Tests/AppUITests/TeamFlowTests.swift').read_text()
        for name in ['testJoinedInvitationContinuationRequiresFreshMembership', 'testJoinedContinuationRejectsInvitationLookupAndUnknownMembership', 'testJoinedContinuationClearsRosterWhenRefreshFails', 'testJoinedContinuationDiscardsReadAfterSessionChanges', 'testJoinedContinuationPreservesUnknownJournalLock']:
            self.assertIn(name, core)
        self.assertIn('testAlreadyJoinedInvitationOpensDetailBackAndReopens', ui)
        self.assertIn('testNonmemberInvitationHasNoOwnedDetailShortcut', ui)
