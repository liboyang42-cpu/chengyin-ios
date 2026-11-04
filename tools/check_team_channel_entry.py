#!/usr/bin/env python3
"""TEAM entry source/structure regression checks only. Does not execute Swift or iOS."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class TeamChannelEntrySourceChecks(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_both_normal_roots_inject_hooks(self):
        text = self.text('App/SessionTeamViews.swift')
        self.assertEqual(text.count('.environment(\\.teamChannelManagementHooks, session.normalTeamChannelManagementHooks)'), 2)
        self.assertIn('.id(session.teamViewIdentity)', text)
    def test_detail_has_real_source_consumer_and_rechecks_on_open(self):
        text = self.text('App/TeamHomeView.swift')
        self.assertIn('@Environment(\\.teamChannelManagementHooks)', text)
        self.assertIn('NativeTeamChannelManagementSource(coordinator: model.coordinator, lookup: lookup, readOnly: readOnly)', text)
        self.assertLess(text.index('guard source.isCurrent(for: selected)'), text.index('return channelManagementHooks.makeFlow(selected)'))
    def test_no_session_factory_rebinding_from_retained_old_closure(self):
        text = self.text('App/SessionTeamViews.swift')
        for phrase in ['capturedContext != nil', 'self.teamViewIdentity == capturedIdentity', 'self.currentRuntimeDependencyContext == capturedContext', 'guard current(), selected.guildKind == 3']:
            self.assertIn(phrase, text)
    def test_only_original_team_safe_destinations_are_injected(self):
        text = self.text('App/SessionTeamViews.swift').split('var normalTeamChannelManagementHooks:')[1]
        for phrase in ['friendInvites:', 'onboarding:', 'welcome:']: self.assertIn(phrase, text)
        for phrase in ['webhook:', 'progressPrivacy:', 'audit:', 'moderation:', 'friendMembers:', 'roles:']: self.assertNotIn(phrase, text)
        self.assertEqual(text.count('parentRouteIsActive: { current() && route.wrappedValue }'), 2)
    def test_source_cannot_mint_authority_or_network_operation(self):
        text = self.text('Core/NativeTeamChannelManagementSource.swift')
        for phrase in ['URLRequest', 'HTTPTransport', 'NativeChannelManagementApproval(', 'NativeChannelManagementIntent.', 'leader == true', 'team.ownerID', 'UserDefaults', 'try journal']:
            self.assertNotIn(phrase, text)
        self.assertIn('NativeChannelManagementScope(guildKind: 3, guildID: id)', text)
    def test_source_checks_current_membership_session_and_pending(self):
        text = self.text('Core/NativeTeamChannelManagementSource.swift')
        for phrase in ['coordinator.synchronizeSession()', 'coordinator.scope == sourceScope', 'coordinator.detail == detail', 'coordinator.detail?.joined == true', 'coordinator.pending == nil', 'coordinator.readFailure == nil', 'coordinator.retiredMembershipTeamID == nil', 'private weak var coordinator']:
            self.assertIn(phrase, text)
    def test_existing_channel_gate_and_recovery_remain_active(self):
        service = self.text('Core/NativeChannelManagementService.swift')
        self.assertIn('grant.matches(live, viewerRevision: capturedViewer, scope: scope)', service)
        self.assertIn('guard result.scope == scope', service)
        views = self.text('App/NativeChannelManagementViews.swift')
        self.assertIn('model.restoreOriginal()', views)
        self.assertIn('NativeChannelManagementRecoveryView(model: model)', views)
        launch = self.text('App/NativeChannelManagementEntry.swift')
        self.assertIn('model?.retire()', launch)
        self.assertIn('routeIsPresented.wrappedValue, scenePhase == .active', launch)
    def test_production_approval_remains_nil(self):
        self.assertIn('var nativeChannelManagementApproval: @MainActor (RuntimeDependencyContext, UInt64, NativeChannelManagementScope) -> NativeChannelManagementApproval? = { _, _, _ in nil }', self.text('App/AppCompositionRoot.swift'))
    def test_authored_runtime_cases_are_present_not_counted_as_execution(self):
        text = self.text('Tests/CoreTests/NativeTeamChannelManagementSourceTests.swift')
        for phrase in ['testAccountRoleRegionAndEpochReplacement', 'testSignOutAndApprovalWithdrawal', 'testMembershipRevocation', 'testLoadingAndFailedRefresh', 'testUnresolvedMembershipOperation', 'testChannelApprovalRevocation', 'testPendingChannelOriginalSurvivesBack', 'testJoinedTeamDoesNotReplaceMissingIndependentChannelApproval']:
            self.assertIn(phrase, text)
if __name__ == '__main__': unittest.main()
