"""Read-only settlement journey source assertions; native tests run separately."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ClubSettlementReturnContracts(unittest.TestCase):
    def read(self,p):return (ROOT/p).read_text()
    def test_rows_only_emit_exact_target_to_stable_owner(self):
        s=self.read('App/ClubSettlementDetail.swift').split('struct ClubSettlementRows:',1)[1].split('struct ClubSettlementDetail:',1)[0]
        self.assertIn('@ObservedObject var owner:',s)
        self.assertIn('owner.open(target, source: source, current: currentSource(), active: active())',s)
        for x in ['@State', '.sheet(', '.onDisappear', '.task(']:self.assertNotIn(x,s)
    def test_parent_only_concrete_uuid_presenter(self):
        s=self.read('App/ClubGovernanceViews.swift')
        self.assertIn('@StateObject private var settlementReturn = ClubSettlementReturnOwner()',s)
        self.assertIn('if let item = settlementReturn.item {',s)
        self.assertIn('returned: { Task { await loadSettlementIfNeeded() } }).id(item.id)',s)
    def test_same_row_topic_context_remains_original_detail(self):
        s=self.read('App/ClubSettlementDetail.swift')
        for x in ['ClubSettlementDetail(target: item.target, identity: item.source.context.identity','target.isCurrent(presentation: source.presentation','source.generation, namespace: source.namespace','try projected.record(for: target)']: self.assertIn(x,s)
    def test_close_immediately_retires_read_admission(self):
        s=self.read('App/ClubSettlementDetail.swift')
        self.assertIn('isPresented && matches(expected, source: source, active: active)',s)
        self.assertIn('self.isPresented = false',s)
        self.assertIn('guard !isPresented, matches(expected, source: source, active: active)',s)
    def test_old_attachment_and_dismiss_do_not_change_new_owner(self):
        s=self.read('App/ClubSettlementDetail.swift')
        for x in ['guard attachment == expected else { return false }','item == expected && attachment == expected.attachment','self.current(expected, source: source(), active: active()) else { return }']:self.assertIn(x,s)
    def test_return_requires_visible_foreground_parent(self):
        s=self.read('App/ClubSettlementDetail.swift')
        self.assertIn('visible && active && item == nil',s)
        self.assertIn('needsRefresh = !succeeded',s)
        s=self.read('App/ClubGovernanceViews.swift')
        self.assertIn('settlementReadIsCurrent(attachment), !loading',s)
        self.assertIn('guard generation != before else { return }',s)
    def test_namespace_and_authorization_context_rotate_admission(self):
        s=self.read('App/ClubSettlementDetail.swift')
        self.assertIn('self.context != context || self.namespace != namespace',s)
        s=self.read('App/ClubGovernanceViews.swift')
        self.assertIn('SettlementReadKey: Hashable',s)
        self.assertIn('settlementReturn.namespace == access.storageNamespace',s)
        self.assertIn('.task(id: settlementReadKey)',s)
    def test_background_and_real_departure_fence_old_read(self):
        s=self.read('App/ClubGovernanceViews.swift')
        self.assertIn('settlementReturn.background(); generation &+= 1; loading = false',s)
        self.assertIn('if settlementReturn.depart(attachment) { generation &+= 1; loading = false }',s)
        self.assertEqual(s.count('topicSettingsReadIsCurrent(topicSettingsAttachment), banReadIsCurrent(banAttachment), settlementReadIsCurrent(settlementAttachment), access.identity == expected'),3)
    def test_dedicated_load_owner_does_not_get_generic_invalidation(self):
        s=self.read('App/ClubGovernanceViews.swift')
        self.assertIn('guard operation != .cases, operation != .settlement else { return }',s)
        self.assertIn('if !settlementReturn.retainsChild, let attachment = settlementReturn.attachment',s)
        self.assertIn('if settlementReturn.synchronize(readContext, namespace: access.storageNamespace) { invalidateRead(); loading = false }',s)
    def test_no_new_money_or_mutation_operations(self):
        s=self.read('App/ClubSettlementDetail.swift')
        for x in ['.send(', '.confirm(', '.perform(', 'URLSession','UserDefaults','withdraw(', 'refund(']:self.assertNotIn(x,s)
        self.assertIn('access.read(.settlement, scope: permit.context.read.scope, options: [:], check: check)',s)
    def test_original_core_finance_permission_remains(self):
        s=self.read('Core/ClubSettlementDetailPresentation.swift')
        self.assertIn('snapshot.permissions?.allows(ClubGovernanceRead.settlement.permission, scope: context.scope) == true',s)
        self.assertIn('guard record.topicID == target.topicID else',s)
    def test_authored_negative_cases_include_both_dismiss_orderings(self):
        s=self.read('Tests/AppUnitTests/ClubSettlementDetailTests.swift')
        for x in ['testCloseBeforeParentAppearsDefersFreshReadAdmission','testParentAppearsBeforeDismissDoesNotStartReadBehindDetail','testNamespaceAndAuthorizationChangesRetireOldChildBeforeNewRead','testBackgroundInterruptKeepsReadNeededUntilCurrentVisibleSuccess','testDetailFreshReadStillRequiresCurrentParentAndExactRow']:self.assertIn(x,s)
if __name__=='__main__':unittest.main()
