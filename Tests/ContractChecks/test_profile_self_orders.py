"""Source wiring assertions only. Not Swift compilation or production approval."""
import json
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
def read(p):return (ROOT/p).read_text()
class ProfileSelfOrdersChecks(unittest.TestCase):
    def setUp(self):self.core=read('Core/ProfileSelfOrders.swift');self.app=read('App/ProfileSelfOrdersSection.swift')
    def test_both_owners_must_match(self):
        for t in ['owner.accountID == memberID','social.identity == owner','ordersOwner.accountID == memberID','orders.identity == ordersOwner']:self.assertIn(t,self.core)
    def test_config_and_parent_current_required(self):
        self.assertIn('guard isCurrent, memberID > 0',self.core);self.assertIn('social.isConfigured, orders.isConfigured',self.core)
    def test_reader_object_and_social_revision_fenced(self):
        for t in ['ObjectIdentifier(social)','ObjectIdentifier(orders)','social.presentationRevision','== expected']:self.assertIn(t,self.core)
    def test_scoped_identity_unavailable_after_retirement(self):self.assertIn('isCurrentContext ? expected.ordersOwner : nil',self.core)
    def test_list_pre_and_post_current_checks(self):
        b=self.core.split('public func profileOrders()')[1].split('public func profileOrder(id:')[0]
        self.assertGreaterEqual(b.count('guard isCurrentContext'),2);self.assertIn('guard !Task.isCancelled, isCurrentContext',b)
    def test_detail_pre_and_post_current_checks(self):
        b=self.core.split('public func profileOrder(id:')[1].split('public func profileParticipants')[0]
        self.assertGreaterEqual(b.count('guard isCurrentContext'),2);self.assertIn('guard !Task.isCancelled, isCurrentContext',b)
    def test_list_owner_and_unique_ids(self):
        self.assertIn('$0.id > 0 && $0.memberID == expected.memberID',self.core);self.assertIn('Set(rows.map(\\.id)).count == rows.count',self.core)
    def test_detail_exact_id_member(self):
        self.assertIn('guard id > 0 else { throw APIError.invalidRequest }',self.core);self.assertIn('guard row.id == id, row.memberID == expected.memberID',self.core)
    def test_narrow_reader_rejects_unrelated_methods(self):
        for t in ['public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.notConfigured }','public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }','public func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }']:self.assertIn(t,self.core)
    def test_preview_exactly_eight_original_order(self):
        self.assertIn('Array(rows.prefix(8))',self.core);self.assertNotIn('.sorted',self.core);self.assertNotIn('.shuffled',self.core)
    def test_no_image_or_financial_projection(self):
        for t in ['AsyncImage','SquareImage','ProfileOrderAmountLabel','URLSession','ProfileService(','OwnedOrderReadApproval(']:self.assertNotIn(t,self.app+self.core)
    def test_generation_scope_and_singleflight(self):
        for t in ['guard !isLoading else { return }','generation == stamp','loadedScope == reader.scope','!Task.isCancelled']:self.assertIn(t,self.core)
    def test_initial_unknown_empty_not_fabricated(self):self.assertIn('public private(set) var rows: [ProfileOrder]?',self.core);self.assertIn('rows = next',self.core)
    def test_authentication_and_config_failure_clear(self):self.assertIn('if failure == .signIn || failure == .unavailable { rows = nil }',self.core)
    def test_stale_cards_cannot_navigate(self):
        self.assertIn('!isLoading, issue == nil, let rows',self.core);self.assertIn('ProfileSelfOrdersPreview(rows: rows).rows.contains(row)',self.core)
        self.assertIn('guard selected == nil, model.canOpen(order, reader: reader)',self.app)
    def test_normal_helper_uses_only_owned_reader(self):
        self.assertIn('self.init(reader: session.ownedOrderReader',self.app);self.assertNotIn('session.profileReader',self.app)
    def test_unapproved_or_other_profile_has_no_entry(self):self.assertIn('if let context = access.context(memberID: memberID, social: social, isCurrent: isCurrent())',self.app)
    def test_exact_detail_and_existing_full_browser(self):
        self.assertIn('ProfileOrderDetailView(id: selection.orderID, reader: reader, ticketReader: ticketReader)',self.app)
        self.assertIn('ProfileOrdersView(reader: reader, ticketReader: ticketReader)',self.app)
    def test_retry_and_fresh_empty_are_distinct(self):
        for t in ['rows.isEmpty && model.issue == nil && !model.isLoading','if model.rows != nil { Text("profile.selfOrders.stale")','if issue == .readFailed']:self.assertIn(t,self.app)
    def test_push_suspends_not_retires_reader(self):self.assertIn('.onDisappear { model.suspend() }',self.app);self.assertNotIn('.onDisappear { model.retire()',self.app)
    def test_preview_privacy_and_no_writer(self):
        self.assertIn('.privacySensitive()',self.app)
        for t in ['coordinator.confirm','ParticipantWriting','OrderLifecycleCoordinator(','UserDefaults','print(']:self.assertNotIn(t,self.core+self.app)
    def test_fixture_has_no_production_dependencies(self):
        s=read('App/ProfileSelfOrdersFixture.swift');self.assertTrue(s.startswith('#if DEBUG'))
        for t in ['AppSession(','APIConfiguration','HTTPTransport','URLSession','OwnedOrderReadApproval(']:self.assertNotIn(t,s)
    def test_fragment_explicitly_pending_and_exact_dependency_chain(self):
        f=json.loads(read('docs/profile-self-orders-registration.fragment.json'));self.assertEqual(f['public_mount']['status'],'NOT_APPLIED');self.assertEqual(f['public_mount']['requires_prior_packages'],[8,10,11,12,13]);self.assertEqual(f['central_files_modified'],[])
        self.assertIn('selfOrdersAccess: .init(session: session)',f['public_mount']['unified_diff'])
    def test_mount_fragment_resets_retired_orders_tab(self):
        f=json.loads(read('docs/profile-self-orders-registration.fragment.json'))
        self.assertIn('if context == nil && tab == .orders { tab = .posts }',f['public_mount']['unified_diff'])
    def test_eight_bilingual_keys(self):
        f=json.loads(read('Resources/ProfileSelfOrdersLocalizations.fragment.json'))['strings'];self.assertEqual(len(f),8)
        for row in f.values():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
    def test_native_cases_cover_late_errors_and_stale_rows(self):
        s=read('Tests/CoreTests/ProfileSelfOrdersTests.swift')
        for t in ['testLateUnauthorizedCannotChangeNewPresentation','testFailedRefreshRetainsButDisablesStaleCard','testOrderApprovalRevisionRetiresContext','testMalformedOwnerAndDuplicateIDsDoNotPublish']:self.assertIn(t,s)
    def test_native_flow_covers_full_reader_and_retry(self):
        s=read('Tests/AppUITests/ProfileSelfOrdersFlowTests.swift');self.assertIn('testAllOrdersUsesExistingList',s);self.assertIn('testInitialFailureRetriesWithoutFalseEmpty',s)
if __name__=='__main__':unittest.main()
