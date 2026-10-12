"""Source contracts only: not compiled Swift, real read permission, or UI execution."""
import json
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
class ProfileOrderFilterChecks(unittest.TestCase):
    def setUp(self):
        self.core=read('Core/ProfileOrderHistoryFilter.swift');self.app=read('App/ProfileOrdersView.swift');self.ui=read('App/ProfileOrderFilterSection.swift')
    def test_exact_nine_options(self):self.assertIn('case all, pendingPayment, notStarted, inProgress, completed, refunding, refunded, nonRefundable, manualRefund',self.core)
    def test_all_preserves_every_row(self):self.assertIn('self == .all ? rows : rows.filter',self.core)
    def test_source_order_no_sort_or_drop(self):
        self.assertNotIn('.sorted',self.core);self.assertNotIn('.prefix(',self.core);self.assertNotIn('.compactMap',self.core)
    def test_manual_refund_first(self):self.assertLess(self.core.index('if manualRefundCaseStatus'),self.core.index('if historyFacts.hasRefundApplication'))
    def test_only_payout_one_four_refunded(self):self.assertIn('if refundPayoutStatus == 1 || refundPayoutStatus == 4 { return .refunded }',self.core)
    def test_manual_payout_stays_processing(self):self.assertIn('if refundPayoutStatus == 2 || refundPayoutStatus == 3 { return .refunding }',self.core)
    def test_zero_and_rejected_refund_fall_back(self):self.assertIn('(refundAmount.map { $0 > .zero } ?? true), refundApplicationStatus != 2',self.core)
    def test_absent_refund_not_empty_object(self):self.assertIn('c.contains(.refundApplication) && (try? c.decodeNil(forKey: .refundApplication)) == false',self.core)
    def test_cancellation_has_no_payout_inference(self):self.assertIn('case 3: return .cancelled',self.core);self.assertIn('case 4: return .expired',self.core)
    def test_paid_scan_required(self):self.assertIn('if paymentStatus == 2, OrderLifecycleTime.date(historyFacts.firstSuccessfulScanAt) != nil { return .completed }',self.core)
    def test_free_requires_all_source_facts(self):
        for t in ['historyFacts.totalAmountIsZero && payableAmount == .zero','pointPaymentAmount == nil || pointPaymentAmount == .zero','wechatPaymentAmount == nil || wechatPaymentAmount == .zero','if !free && refundable == false']:self.assertIn(t,self.core)
    def test_total_literal_not_numeric_prefix(self):
        self.assertIn('options: .regularExpression',self.core);self.assertIn('^',self.core);self.assertIn('$',self.core);self.assertNotIn('Decimal(string:',self.core.split('let trimmed')[1].split('hasRefundApplication')[0])
    def test_source_date_fallbacks(self):
        self.assertIn('start = present(owner?.startDate) ?? present(owner?.startTime)',self.core)
        self.assertIn('end = present(owner?.endDate) ?? present(owner?.endTime) ?? start',self.core)
    def test_exact_start_end_boundaries(self):
        self.assertIn('now > end { return .completed }',self.core);self.assertIn('now < start { return .notStarted }',self.core)
    def test_core_is_read_only(self):
        for t in ['URLSession','transport.send','Task {','UserDefaults','func confirm','func refund','func pay']:self.assertNotIn(t,self.core)
    def test_current_owner_gates_selection(self):
        for t in ['guard rendered == current, current.isCurrent else { return }','owner == current && current.isCurrent ? filter : .all','(identity?.accountID ?? 0) > 0']:self.assertIn(t,self.core)
    def test_retirement_is_local(self):self.assertIn('owner = nil; filter = .all',self.core);self.assertIn('.onChange(of: filterOwner) { _, _ in filterSelection.retire() }',self.app)
    def test_filter_cannot_make_requests(self):
        for t in ['Task {','.profileOrders(','.profileOrder(','.refreshable']:self.assertNotIn(t,self.ui)
        self.assertEqual(self.app.count('try await reader.profileOrders()'),1)
    def test_timer_only_recomputes_display(self):
        self.assertIn('TimelineView(.periodic(from: .now, by: 60))',self.app)
        block=self.app.split('TimelineView(')[1].split('.appNavigationTitle("profile.orders.title")')[0]
        self.assertNotIn('await ',block);self.assertNotIn('Task {',block)
    def test_visible_links_keep_original_ids(self):
        self.assertIn('ForEach(visible) { order in',self.app)
        self.assertIn('ProfileOrderDetailView(id: order.id, reader: reader,',self.app)
        self.assertIn('historyState: order.historyState(now: clock.date)',self.app)
    def test_true_empty_and_filter_empty_distinct(self):
        self.assertIn('if orders.isEmpty',self.app);self.assertIn('isEmpty: visible.isEmpty',self.app)
        self.assertIn('Text("profile.orderFilter.empty")',self.ui);self.assertIn('{ selection = .all }',self.ui)
    def test_detail_push_does_not_retire_filter(self):
        list_view=self.app.split('private struct ProfileOrderRow')[0];self.assertNotIn('.onDisappear',list_view)
    def test_supplemental_projection_mounted_only_once(self):
        s=read('Core/ProfileContracts.swift');self.assertEqual(s.count('public let historyFacts: ProfileOrderHistoryFacts'),1);self.assertEqual(s.count('historyFacts = try ProfileOrderHistoryFacts(from: decoder)'),1)
    def test_fixture_is_memory_only_and_account_filtered(self):
        s=read('App/ProfileOrderFilterFixture.swift');self.assertTrue(s.startswith('#if DEBUG'))
        self.assertIn('rows.filter { $0.memberID == identity?.accountID }',s)
        for t in ['APIConfiguration','URLSession','HTTPTransport','OwnedOrderReadApproval(','AppSession(']:self.assertNotIn(t,s)
    def test_fragment_keys_and_no_permission_registration(self):
        f=json.loads(read('Resources/ProfileOrderFilterLocalizations.fragment.json'))['strings'];self.assertEqual(len(f),5)
        for row in f.values():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
        d=json.loads(read('docs/profile-order-filters-registration.fragment.json'));self.assertEqual(d['new_approvals'],[]);self.assertEqual(d['central_files_modified'],[])
    def test_native_tests_cover_no_read_and_unknown(self):
        s=read('Tests/CoreTests/ProfileOrderHistoryFilterTests.swift');self.assertIn('testEmptyRefundObjectIsDistinctFromAbsentAndNull',s);self.assertIn('testSelectionRejectsStaleRenderedOwner',s)
        a=read('Tests/AppUnitTests/ProfileOrderFilterAppTests.swift');self.assertIn('testSelectingAllFiltersDoesNotReadAgain',a);self.assertIn('testSelectedOrderUsesOriginalDetailID',a)
if __name__=='__main__':unittest.main()
