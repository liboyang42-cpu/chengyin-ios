"""Supplementary wiring checks; Apple execution is required for navigation evidence."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubManagementReturnStateChecks(unittest.TestCase):
    def test_navigation_is_independent_of_mutating_source_rows(self):
        source = (ROOT / 'App/ClubManagementView.swift').read_text()
        self.assertIn('.navigationDestination(item: $selection)', source)
        self.assertIn('Button { selection = .request(request.id) }', source)
        self.assertIn('Button { selection = .member(member.id) }', source)
        self.assertNotIn('NavigationLink {', source)
        self.assertIn('snapshot.requests.first(where:', source)
        self.assertIn('snapshot.members.first(where:', source)

    def test_return_and_notification_require_acknowledgement(self):
        source = (ROOT / 'App/ClubManagementView.swift').read_text()
        confirm = source.split('@MainActor private func confirm(')[1]
        self.assertIn('guard run == generation, access.identity == pending.identity, !Task.isCancelled', confirm)
        self.assertIn('if case .acknowledged = state {', confirm)
        self.assertLess(confirm.index('if case .acknowledged = state {'), confirm.index('selection = nil'))
        self.assertLess(confirm.index('selection = nil'), confirm.index('onMembershipChanged?()'))
        self.assertIn('case .unavailable: readbackUnavailable = true', confirm)

    def test_detail_shows_outcome_and_read_only_refresh(self):
        source = (ROOT / 'App/ClubManagementView.swift').read_text()
        detail = source.split('@ViewBuilder private func detail(')[1].split('@ViewBuilder private var status')[0]
        self.assertIn('status', detail)
        self.assertIn('access.identity == identity', detail)
        self.assertIn('await refresh()', detail)
        self.assertIn('.onDisappear { leaveScreen() }', detail)
        refresh = source.split('@MainActor private func refresh()')[1].split('@MainActor private func prepare(')[0]
        self.assertIn('access.snapshot(clubID: clubID)', refresh)
        self.assertNotIn('.perform(', refresh)
        self.assertNotIn('.confirm(', refresh)

    def test_parent_refresh_uses_generation_and_identity_gated_loader(self):
        detail = (ROOT / 'App/ClubDetailView.swift').read_text()
        self.assertIn('refreshRevision: managementRevision', detail)
        self.assertIn('onMembershipChanged: {', detail)
        self.assertIn('managementRevision &+= 1', detail)
        screen = (ROOT / 'App/ClubReadScreen.swift').read_text()
        self.assertIn('LoadIdentity(identity: reader.clubIdentity, revision: refreshRevision)', screen)
        self.assertIn('request == generation, reader.clubIdentity == identity', screen)

    def test_parent_reload_is_deferred_until_return(self):
        source = (ROOT / 'App/ClubDetailView.swift').read_text()
        callback = source.split('onMembershipChanged: {')[1].split('})')[0]
        self.assertIn('managementNeedsRefresh = true', callback)
        self.assertNotIn('managementRevision &+= 1', callback)
        appeared = source.split('.onAppear {')[1].split('.onChange')[0]
        self.assertIn('guard managementNeedsRefresh', appeared)
        self.assertIn('managementRevision &+= 1', appeared)

    def test_interrupted_detail_refresh_releases_loading(self):
        source = (ROOT / 'App/ClubManagementView.swift').read_text()
        leave = source.split('private func leaveScreen()')[1].split('@ViewBuilder')[0]
        self.assertIn('generation &+= 1', leave)
        self.assertIn('loading = false', leave)

    def test_reentry_does_not_erase_acknowledged_readback_failure(self):
        source = (ROOT / 'App/ClubManagementView.swift').read_text()
        self.assertIn('screenIdentity != identity || screenRevision != viewerRevision || snapshot == nil && state == .idle', source)
        self.assertIn('club.management.readbackUnavailable', source)

    def test_authored_runtime_cases_cover_server_outcomes(self):
        source = (ROOT / 'Tests/AppUITests/ClubManagementFlowTests.swift').read_text()
        for name in ['testAcknowledgedApplicationReturnsToFreshList', 'testAcknowledgedRemovalReturnsToFreshList',
                     'testUnknownOutcomeStaysVisibleAndRefreshNeverReplays', 'testAcknowledgementWithUnavailableReadbackIsExplicit']:
            self.assertIn('func ' + name, source)

if __name__ == '__main__':
    unittest.main()
