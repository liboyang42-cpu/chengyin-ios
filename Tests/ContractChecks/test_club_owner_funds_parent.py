"""Source contracts for the owner-funds page and its existing contact route."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ClubOwnerFundsParentContracts(unittest.TestCase):
    def setUp(self):
        self.funds=(ROOT/'App/ClubOwnerFundsView.swift').read_text()
        self.host=(ROOT/'App/ClubGovernanceViews.swift').read_text()
        self.owner=self.funds.split('@MainActor final class ClubOwnerFundsParent:',1)[1].split('@MainActor struct ClubOwnerFundsContactOwner:',1)[0]
        self.row=self.funds.split('struct ClubOwnerFundsSection:',1)[1]
    def test_existing_finance_reads_still_surround_the_wallet_read(self):
        workflow=self.funds.split('@MainActor final class ClubOwnerFundsWorkflow:',1)[1].split('/// Stable owner',1)[0]
        self.assertLess(workflow.index('let before = try await access.read(.settlement'),workflow.index('let value = try await reader.readClubOwnerFunds()'))
        self.assertLess(workflow.index('let value = try await reader.readClubOwnerFunds()'),workflow.index('let after = try await access.read(.settlement'))
        self.assertEqual(workflow.count('guard target.accepts('),2)
        self.assertIn('availability == .positive',workflow)
    def test_lazy_row_only_observes_stable_parent(self):
        self.assertIn('@StateObject private var ownerFundsParent = ClubOwnerFundsParent()',self.host)
        for forbidden in ['@StateObject','.sheet(','.task(','.onDisappear','.onChange(']:self.assertNotIn(forbidden,self.row)
        self.assertIn('@ObservedObject var workflow: ClubOwnerFundsWorkflow',self.row)
        self.assertIn('@ObservedObject var parent: ClubOwnerFundsParent',self.row)
    def test_source_and_ticket_capture_exact_reader_scope_and_attachment(self):
        for token in ['let target: ClubOwnerFundsTarget','let readerID: ObjectIdentifier?','let walletScope: WalletCommerceScope?','let generation: UInt64','let namespace: String','let attachment: UUID','let revision: UUID']:
            self.assertIn(token,self.owner)
        self.assertIn('attachment == ticket.attachment && revision == ticket.revision && source == ticket.source && current == ticket.source',self.owner)
        self.assertIn('parent.source == currentSource()',self.row)
    def test_contact_uses_concrete_nonnil_stable_presenter(self):
        self.assertIn('if let item = ownerFundsParent.contact',self.host)
        self.assertIn('returned: { Task { await loadOwnerFundsIfNeeded() } }).id(item.id)',self.host)
        self.assertIn('.sheet(isPresented: owner.binding(item, current: current, active: active)',self.funds)
        self.assertIn('owner.current(item, source: current(), active: active()), let support = context.support',self.funds)
    def test_old_close_and_dismiss_cannot_touch_replacement(self):
        self.assertIn('guard contact == item else { return }; isPresented = false; workflow.closeContact()',self.owner)
        self.assertIn('guard contact == item, !isPresented, matches(item.ticket',self.owner)
        self.assertIn('contact = nil; revision = UUID(); needsRead = true; workflow.invalidate()',self.owner)
        self.assertIn('self.contact == item, self.matches(item.ticket',self.owner)
    def test_hidden_return_retains_need_without_reading(self):
        self.assertIn('guard visible, active, !otherPresented, contact == nil',self.owner)
        self.assertIn('visible && !otherPresented && contact == nil && matches',self.owner)
        self.assertIn('if contact == nil { invalidate() }',self.owner)
        self.assertIn('ownerFundsParent.appear(); Task { await loadOwnerFundsIfNeeded() }',self.host)
    def test_real_departure_is_bound_to_attachment(self):
        self.assertIn('guard attachment == expected else { return false }',self.owner)
        self.assertIn('ClubSettlementParentLifetime { ownerFundsParent.depart(attachment) }.id(attachment)',self.host)
        self.assertIn('attachment = nil; source = nil; visible = false',self.owner)
    def test_background_invalidates_and_foreground_only_uses_current_source(self):
        self.assertIn('if phase != .active { ownerFundsParent.background() }',self.host)
        self.assertIn('guard scenePhase == .active, settlementSource != nil',self.host)
        self.assertIn('ownerFundsParent.synchronize(ownerFundsSource)',self.host)
        self.assertIn('private func invalidate()',self.owner)
        self.assertIn('revision = UUID(); contact = nil; isPresented = false; needsRead = true',self.owner)
        self.assertIn('workflow.invalidate(); workflow = ClubOwnerFundsWorkflow()',self.owner)
    def test_ledger_and_contact_are_distinct_and_mutually_guarded(self):
        self.assertIn('if !settlementReturn.retainsChild, let attachment = settlementReturn.attachment',self.host)
        self.assertIn('if !ownerFundsParent.retainsContact {',self.host)
        self.assertIn('active: scenePhase == .active && !ownerFundsParent.retainsContact',self.host)
        self.assertIn('.disabled(ownerFundsParent.retainsContact || ownerFundsParent.workflow.loading)',self.host)
        self.assertIn('otherPresented: { settlementReturn.retainsChild }',self.host)
        self.assertIn('ClubSettlementPresentationOwner(item: item, owner: settlementReturn',self.host)
    def test_read_and_contact_await_existing_workflow_with_live_checks(self):
        self.assertIn('await workflow.load(target: offered.source.target',self.owner)
        self.assertIn('await workflow.openContact(target: offered.source.target',self.owner)
        self.assertIn('sourceIsCurrent: { self.accepts(offered',self.owner)
        self.assertIn('(self.visible || self.contact?.ticket == offered) && !otherPresented()',self.owner)
        self.assertIn('workflow.contactIsCurrent else { return }',self.owner)
    def test_no_financial_command_or_new_request_is_added(self):
        for value in ['.send(','.confirm(','.prepare(', 'URLSession','transport.send','grant(', 'refund(', 'withdraw(']: self.assertNotIn(value,self.owner)
        self.assertIn('if value.amountsKnown',self.row)
        self.assertIn('workflow.loadedScope == context.reader?.scope',self.row)
    def test_authored_cases_cover_normal_and_interrupted_return(self):
        tests=(ROOT/'Tests/AppUnitTests/ClubOwnerFundsFlowTests.swift').read_text()
        for name in ['testParentNormalFundsContactAndVisibleReturnRechecksBothFinanceReads','testParentSheetCoverageRetainsExactContactAndFreshReturnWaitsForAppearance','testParentAppearanceBeforeContactDismissDoesNotReadUntilExactDismissal','testOldContactBindingCloseAndDismissCannotTouchReopenedContact','testPendingFundsReadDepartAndLateResponseCannotRestoreSnapshot','testInterruptedReturnReadRestartsOnVisibleForegroundOnly']:
            self.assertIn('func '+name+'(',tests)
if __name__=='__main__':unittest.main()
