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
        s=self.read('App/OwnedOrderComposition.swift');self.assertIn('ProfileOrdersView(reader: session.ownedOrderReader)',s);self.assertIn('.id(session.ownedOrderReader.identity)',s)
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
if __name__=='__main__':unittest.main()
