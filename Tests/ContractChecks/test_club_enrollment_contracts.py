"""Native-local structural checks only; these do not execute Swift or its UI."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubEnrollmentContractChecks(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_scope_and_nested_projection_are_required(self):
        code = self.text('Core/ClubEnrollmentContracts.swift')
        for fragment in ['clubID == scope.clubID, topicID == scope.topicID', 'value["canRefund"].bool', 'ClubEnrollmentDecode.rows(value["omsTicketList"])', 'ClubEnrollmentDecode.rows(value["cmsRegistrationList"])', 'unique(tickets.flatMap(\\.registrants).map(\\.id))']:
            self.assertIn(fragment, code)
        self.assertIn('ClubEnrollmentRoster(value: value, scope: scope)', self.text('Core/ClubGovernanceValidation.swift'))
    def test_unknown_status_counts_and_capacity_are_preserved(self):
        code = self.text('Core/ClubEnrollmentContracts.swift')
        self.assertIn('case 0: return .pending; case 1: return .done; default: return .unknown', code)
        self.assertIn('public let signupCount: Int?', code)
        self.assertIn('public var refundableCount: Int?', code)
        self.assertIn('public let mode: Int?', code)
        self.assertIn('public let capacity: Int?', code)
    def test_roster_has_no_financial_dispatch(self):
        code = self.text('Core/ClubEnrollmentReader.swift') + self.text('App/ClubEnrollmentView.swift')
        for fragment in ['access.send(', 'cancel-by-owner', 'coordinator.confirm(', 'refund()']:
            self.assertNotIn(fragment, code)
        self.assertIn('ClubOwnerRefundPanel(', self.text('App/ClubGovernanceViews.swift'))
        self.assertIn('ClubOwnerRefundReadOnlyAccess(governance:', self.text('App/AppSession.swift'))
    def test_identity_and_generations_gate_all_receipts(self):
        code = self.text('Core/ClubEnrollmentReader.swift')
        for fragment in ['access.identity == expected', 'generation == revision', '!Task.isCancelled', 'detailGenerations[topicID] == detailRevision', 'if clearsSnapshot(issue) { clear()', '"club:member:list:read"']:
            self.assertIn(fragment, code)
    def test_refresh_does_not_leave_collapsed_detail_cache(self):
        code = self.text('Core/ClubEnrollmentReader.swift')
        self.assertIn('rosters = rosters.filter { expanded.contains($0.key) }', code)
        self.assertIn('await loadDetail(topicID: id)', code)
        self.assertIn('expanded.insert(focusTopicID)', code)
    def test_real_destinations_and_topic_focus_are_wired(self):
        ui = self.text('App/ClubEnrollmentView.swift')
        for fragment in ['SocialPublicProfileView(memberID: memberID', 'operation: .checkin', 'registrationID: item.source.registrant.id', 'if kind == .checkin { pendingReturn = UUID() }', 'await reader.refresh()', '.onDisappear { reader.suspend() }']:
            self.assertIn(fragment, ui)
        routes = self.text('App/ClubGovernanceViews.swift')
        self.assertIn('enrollmentLink(focusTopicID: scope.topicID)', routes)
        self.assertIn('enrollmentLink()', routes)
        self.assertNotIn('link(.registrations)', routes)
        self.assertIn('enrollmentProfile: .init(reader: socialAccountReader, squareReader: squareReader', self.text('App/AppSession.swift'))
    def test_additive_fragment_is_bilingual_and_covers_ui(self):
        fragment = json.loads(self.text('Resources/ClubEnrollmentLocalizations.fragment.json'))['strings']
        for key, entry in fragment.items():
            self.assertTrue(key.startswith('club.enroll.'))
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])
        ui = self.text('App/ClubEnrollmentView.swift')
        ui = re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', '', ui)
        keys = set(re.findall(r'"(club\.enroll\.[A-Za-z.]+)"', ui))
        for key in keys:
            if not key.endswith('.'): self.assertIn(key, fragment)
        for status in ['unknown', 'pending', 'done']: self.assertIn('club.enroll.checkin.' + status, fragment)
        for status in ['0', '1', '2']: self.assertIn('club.enroll.teamStatus.' + status, fragment)
    def test_existing_fixture_satisfies_new_root_identity_contract(self):
        code = self.text('Core/ClubGovernanceSyntheticFixtures.swift')
        line = next(line for line in code.splitlines() if 'case .registrations:' in line)
        fixture = json.loads(line.split('json(#"', 1)[1].split('"#)', 1)[0])
        self.assertEqual((fixture['clubId'], fixture['topicId']), (81, 91))
        self.assertIsInstance(fixture['canRefund'], bool)
        self.assertGreater(fixture['omsTicketList'][0]['id'], 0)

    def test_reader_captures_authorization_and_rechecks_each_read(self):
        code = self.text('Core/ClubEnrollmentReader.swift')
        for part in ['access.authorizationGeneration == authorization', 'access.storageNamespace == namespace', 'access.journalRealm == realm', 'ObjectIdentifier(access) == ObjectIdentifier(candidate)', 'guard isCurrentAccess else', 'isCurrentAccess && generation == revision']:
            self.assertIn(part, code)
        self.assertEqual(code.count('options: [:], check: {'), 2)
        self.assertIn('self.current(expected, revision)', code)
        self.assertIn('self.detailGenerations[topicID] == detailRevision', code)
    def test_page_identity_rebuilds_reader_for_changed_authority(self):
        ui = self.text('App/ClubEnrollmentView.swift')
        for part in ['.id(context)', 'accessID = ObjectIdentifier(access)', 'authorization = access.authorizationGeneration', 'namespace = access.storageNamespace', 'profileRevision = profile?.reader.presentationRevision', 'squareScope = profile?.squareReader.scope', 'host == liveHost', 'reader.isCurrentAccess']:
            self.assertIn(part, ui)
    def test_exact_row_mints_concrete_route_and_same_account_profile(self):
        ui = self.text('App/ClubEnrollmentView.swift')
        for part in ['reader.usesAccess(access)', 'roster.clubID == host.clubID, roster.topicID == topicID', 'reader.expanded.contains(topicID)', 'filter({ $0.id == registrant.id }).count == 1', 'contains(registrant)', 'profileIdentity?.accountID == identity?.accountID', 'profileIdentity?.epoch == identity?.epoch', 'if let item = navigation.item', '.id(item.id)', 'owner.binding(item, source: source)']:
            self.assertIn(part, ui)
    def test_whole_page_owner_and_visible_read_guards(self):
        ui = self.text('App/ClubEnrollmentView.swift')
        for part in ['@StateObject private var navigation', 'navigation.depart(attachment)', 'func hide() { visible = false }', 'guard attachment == expected', 'guard visible, active', 'host == liveHost && navigation.visible && scenePhase == .active', 'Task { if canRead { await reader.toggle', 'Task { if canRead { await reader.loadDetail', 'await refreshVisible()', 'controller.isBeingDismissed || controller.isMovingFromParent']:
            self.assertIn(part, ui)
        reader = self.text('Core/ClubEnrollmentReader.swift')
        suspension = reader.split('public func suspend()', 1)[1].split('private func clear()', 1)[0]
        self.assertNotIn('presentationRevision', suspension)
    def test_return_consumes_specific_checkin_once_and_supports_either_visibility_order(self):
        ui = self.text('App/ClubEnrollmentView.swift')
        for part in ['guard !isPresented, current(expected, source: source)', 'let kind = expected.kind; retire()', 'if kind == .checkin { pendingReturn = UUID() }', 'if completed { pendingReturn = nil }', '.onAppear { navigation.appear(); Task { await activateAndReturn() } }', '.onChange(of: owner.isPresented)', '.onDisappear { didClose() }']:
            self.assertIn(part, ui)
    def test_fixture_reuses_dynamic_parent_identity_without_relaxing_product_gate(self):
        ui = self.text('App/ClubGovernanceFixtureHost.swift')
        enrollment = ui.split('ClubEnrollmentView(clubID:', 1)[1].split('ClubGovernanceHomeEntries', 1)[0]
        self.assertNotIn('SocialAccountFixtureReader(.content)', enrollment)
        for part in ['.environment(\\.clubEnrollmentProfile, store.leaderboardProfile)', 'return .init(reader: profileReader, squareReader: squareReader)', 'profileReader.identity = .init(accountID: replacement.accountID, epoch: replacement.epoch)', 'access.identity = replacement']:
            self.assertIn(part, ui)

    def test_incomplete_background_return_retains_exact_pending_ticket(self):
        ui = self.text('App/ClubEnrollmentView.swift')
        core = self.text('Core/ClubEnrollmentReader.swift')
        for part in ['navigation.pauseReturnRead(); reader.suspend()', 'func pauseReturnRead() { returnRead = nil }', 'returnRead == ticket, attachment == ticket.attachment, pendingReturn == ticket.request', 'await navigation.refreshReturn(using: reader', 'reader.completedRefreshRevision > completed', 'if navigation.hasPendingReturn { await readReturnedRoster() }']:
            self.assertIn(part, ui)
        self.assertIn('guard current(expected, revision), detailFailures.isEmpty else { return }', core)
        self.assertIn('completedRefreshRevision &+= 1', core)
        self.assertLess(core.index('await loadDetail(topicID: id)'), core.index('completedRefreshRevision &+= 1'))

if __name__ == '__main__': unittest.main()
