"""Fresh structural checks only; no Swift execution or API acceptance."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[2]
class OwnedOrderContracts(unittest.TestCase):
    def read(self,p):return (R/p).read_text()
    def test_separate_nil_grant_and_every_clone_callback(self):
        s=self.read('App/AppCompositionRoot.swift')
        self.assertIn('ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }',s)
        c=s.split('private func copy(',1)[1].split('func send(',1)[0]
        for v in ['ownedOrderReadApproval: ownedOrderReadApproval','ownerDraftReadApproval: ownerDraftReadApproval','manualMapReadApproval: manualMapReadApproval','transport.current = { self.current() }','transport.playReadConfiguration = { self.playReadConfiguration($0) }']:self.assertIn(v,c)
        self.assertNotIn('ownedOrder',self.read('App/RegionalLaunchConfiguration.swift'))
    def test_normal_account_orders_and_actual_task_cancellation(self):
        self.assertIn('SessionOwnedOrdersView(session: session)',self.read('App/AccountView.swift'))
        s=self.read('App/OwnedOrderComposition.swift');self.assertIn('ProfileOrdersView(reader: session.ownedOrderReader, ticketReader: session.ticketWalletReader)',s);self.assertIn('.id(session.ownedOrderReader.identity)',s)
        self.assertNotIn('lifecycleCoordinator:',s);self.assertNotIn('makeExternalMaps:',s)
        s=self.read('App/ProfileReadScreen.swift')
        for v in ['loadOwner.start { await reload() }','loadOwner.run { await reload() }','loadOwner.deactivate()']:self.assertIn(v,s)
        self.assertNotIn('Task { await reload() }',s)
    def test_observable_irreversible_expiry_and_exact_money(self):
        s=self.read('Core/OwnedOrderRead.swift')
        for v in ['@MainActor @Observable public final class OwnedOrderReadApproval','isRevoked = true','self?.revoke()','Task.sleep','!isRevoked && now < expiresAt','current() == captured']:self.assertIn(v,s)
        money=s.split('public enum OwnedOrderMoneyText',1)[1]
        self.assertIn('NSDecimalNumber(decimal: amount).stringValue',money);self.assertNotIn('Double',money);self.assertNotIn('NumberFormatter',money)
        self.assertIn('OwnedOrderMoneyText.string(amount)',self.read('App/ProfileOrdersView.swift'))
        task=s.split('expiryTask = Task',1)[1].split('deinit',1)[0]
        self.assertIn('Self.expiryDelay(until: expiresAt, now: Date())',task)
        self.assertNotIn('UInt64(duration *',task)
    def test_strict_owned_table_and_detail_checks(self):
        s=self.read('Core/ProfileService.swift')
        for v in ['result.total == result.rows.count','$0.memberID == expectedAccountID','Set(result.rows.map(\\.id)).count == result.rows.count','result.memberID != expectedAccountID','result.id == id']:self.assertIn(v,s)
        self.assertIn('canonical.httpBody == body',self.read('Core/OwnedOrderRead.swift'))
    def test_authored_apple_tests_and_backend_activation_blocker(self):
        project=self.read('Questify.xcodeproj/project.pbxproj')
        for f in ['Tests/AppUnitTests/OwnedOrderCompositionTests.swift','Tests/AppUITests/OwnedOrderFlowTests.swift']:self.assertIn(f,project)
        self.assertIn('testIdleLoadedScreenClearsImmediatelyOnExplicitRevocationAndExpiry',self.read('Tests/AppUITests/OwnedOrderFlowTests.swift'))
        self.assertIn('Production issuance remains blocked',self.read('docs/owned-orders/read-flow.md'))
    def test_ticket_navigation_is_opt_in_and_requires_exact_fresh_order_member(self):
        view=self.read('App/ProfileOrdersView.swift');host=self.read('App/OwnedOrderComposition.swift')
        self.assertEqual(view.count('var ticketReader: (any TicketWalletReading)? = nil'),2)
        self.assertIn('requestedID > 0, order.id == requestedID, origin.isConfigured',host)
        self.assertIn('order.memberID == identity.accountID',host)
        for requirement in ['originReaderID = ObjectIdentifier(origin)','originIdentity = identity','ticketReaderID = ObjectIdentifier(tickets)','ticketScope = tickets.scope']:
            self.assertIn(requirement,host)
    def test_ticket_activation_and_destination_are_both_current_and_retire_on_owner_changes(self):
        view=self.read('App/ProfileOrdersView.swift')
        for requirement in ['ticketEntryVisible, ticketTarget == nil, renderedPresentation == ticketPresentationID',
                            'target.registrationID == id, target.matches(origin: reader, tickets: ticketReader)',
                            '.navigationDestination(item: $ticketTarget)',
                            '.onChange(of: reader.identity)', '.onChange(of: reader.isConfigured)',
                            '.onChange(of: ObjectIdentifier(reader))', '.onChange(of: ticketReader?.scope)',
                            '.onChange(of: ticketReader?.isAuthenticated)', '.onChange(of: ticketReader?.isConfigured)',
                            '.onChange(of: id)', 'ticketTarget = nil; ticketPresentationID = UUID()']:
            self.assertIn(requirement,view)
        # Pushing must not immediately remove its own destination; Back is owned by native binding.
        self.assertIn('.onDisappear { ticketEntryVisible = false; ticketPresentationID = UUID() }',view)
    def test_ticket_read_proxy_fences_both_dispatch_and_success_error_receipts(self):
        host=self.read('App/OwnedOrderComposition.swift')
        proxy=host.split('final class ProfileOrderTicketReader:',1)[1].split('@MainActor struct ProfileOrderTicketDestination',1)[0]
        self.assertIn('guard current, id == target.registrationID else',proxy)
        self.assertLess(proxy.index('guard current, id == target.registrationID'),proxy.index('tickets.ticketDetail(id: id)'))
        after=proxy.split('tickets.ticketDetail(id: id)',1)[1]
        self.assertIn('guard current else { throw CancellationError() }',after)
        self.assertIn('guard value.id == target.registrationID else { throw APIError.malformedResponse }',after)
        self.assertIn('guard !Task.isCancelled, current else { throw CancellationError() }',after)
        self.assertIn('func ticketWallet() async throws -> TicketWalletSnapshot { throw APIError.notConfigured }',proxy)
        self.assertIn('func retire() { retired = true }',proxy)
        self.assertIn('.onDisappear { reader.retire() }',host)
    def test_ticket_destination_reuses_fresh_read_without_writer_or_code(self):
        host=self.read('App/OwnedOrderComposition.swift')
        self.assertIn('TicketWalletDetailView(id: target.registrationID, reader: reader)',host)
        for forbidden in ['VerificationCode', 'makeVerification', 'URLSession', 'transport.send', 'orderLifecycleCoordinator', 'onAppear { reader.ticket']:
            self.assertNotIn(forbidden,host)
        target=host.split('struct ProfileOrderTicketTarget:',1)[1].split('final class ProfileOrderTicketReader:',1)[0]
        for forbidden in ['await ', 'Task {', '.ticketDetail(', '.ticketWallet(']:self.assertNotIn(forbidden,target)
    def test_authored_navigation_cases_and_unique_bilingual_copy(self):
        import json
        tests=self.read('Tests/AppUnitTests/ProfileOrderTicketNavigationTests.swift')
        self.assertEqual(tests.count('func test'),12)
        for method in ['CreatingNavigationMakesNoRead','ExactAccountEpochViewerAndApproval','OriginRevocationAtReceipt','TicketAccountScopeChange','RetirementRejectsLateSuccess','WrongIDAndListCannotDispatch','StaleErrorIsCancelled']:
            self.assertIn(method,tests)
        fragment=json.loads(self.read('Resources/ProfileOrderTicketEntryLocalizations.fragment.json'))
        self.assertEqual(set(fragment),{'orderTicketEntry.'+part for part in ['open','freshRead','unavailable','changed']})
        for item in fragment.values():self.assertEqual(set(item['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
