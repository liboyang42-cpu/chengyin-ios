"""Wallet native integration contracts; source-only, not runtime verification."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class WalletIntegrationTests(unittest.TestCase):
 def read(self,p): return (ROOT/p).read_text()
 def test_session_and_host_are_wired_without_default_grant(self):
  s=self.read('App/AppSession.swift')
  self.assertIn('lazy var walletCommerceReader = makeWalletCommerceReader()',s)
  self.assertIn('func makeWalletCommerceReader(readApproval: OperationEndpointApproval? = nil',s)
  self.assertIn('SessionWalletCommerceView()',self.read('App/AccountView.swift'))
 def test_epoch_and_expiration_are_current_account_scoped(self):
  s=self.read('App/AppSession.swift')
  self.assertIn('walletEpochCache?.stamp != gate.currentStamp',s)
  self.assertIn('walletEpochCache?.accountID != account.id',s)
  self.assertIn('self.walletCommerceScope == captured',s)
  self.assertIn('session()?.scope == captured.scope',self.read('Core/WalletCommerceSafety.swift'))
 def test_read_grant_does_not_authorize_writes(self):
  s=self.read('Core/WalletCommerceSafety.swift').split('public final class WalletCommerceApprovedReadTransport')[1]
  self.assertNotIn('api/cart/order/settlement',s)
  self.assertNotIn('api/cart/cart/add',s)
  self.assertIn('approval.allows(configuration: configuration',s)
  self.assertIn('current.scope == scope, current.token == token',s)
  self.assertIn('request.value(forHTTPHeaderField: "Authorization") == token',s)
  self.assertIn('@MainActor public func send',s)
  self.assertIn('throw APIError.notConfigured // Unbound requests',s)
 def test_hidden_commerce_is_not_promoted_or_executed(self):
  s=self.read('App/SessionWalletCommerceView.swift')
  self.assertNotIn('value.mall = true',s);self.assertNotIn('value.points = true',s)
  s=self.read('App/WalletCommerceViews.swift');self.assertNotIn('execute(',s)
  self.assertNotIn('WalletCommerceDormantAdapter(',self.read('App/AppSession.swift'))
 def test_club_finance_routes_to_existing_reader(self):
  s=self.read('App/SessionWalletCommerceView.swift')
  self.assertIn('CoopFlowReadView(reader: session.cooperationFlowReader, resource: .finance',s)
 def test_fixture_skips_real_session(self):
  s=self.read('App/QuestifyApp.swift');self.assertGreaterEqual(s.count('WalletCommerceFixtureHost.selected'),2)
  self.assertIn('--wallet-commerce-fixture',self.read('Tests/AppUITests/WalletCommerceFlowTests.swift'))
 def test_localization_and_accessibility_boundaries(self):
  s=self.read('App/WalletCommerceViews.swift')
  self.assertNotIn('String(localized:',s)
  self.assertNotIn('}.accessibilityIdentifier("wallet.issue")',s)
  self.assertIn('appLocalized("wallet.unknown", locale: locale)',s)
  catalog=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
  self.assertEqual(set(catalog['wallet.previewOnly']['localizations']),{'en','zh-Hans'})
