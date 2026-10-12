import pathlib,unittest
R=pathlib.Path(__file__).resolve().parents[2];C=(R/'Core/MerchantPersonalIncomeEligibility.swift').read_text();V=(R/'App/MerchantPersonalIncomeHandoff.swift').read_text();H=(R/'App/MerchantBusinessRecordViews.swift').read_text();A=(R/'App/QuestifyApp.swift').read_text()
class Contracts(unittest.TestCase):
 def test_source_gate(self):self.assertIn('"COOP_ORDER"',C);self.assertIn('"merchant:finance:read"',C);self.assertIn('case .redemption(let id)',C)
 def test_current_detail_recheck(self):self.assertIn('reader.snapshot(baseline.document.query)',V);self.assertIn('reader.authorizationGeneration == authorization',V);self.assertIn('latest.access == baseline.access',V)
 def test_wallet_identity(self):self.assertIn('scope.accountID == source.scope.accountID',V);self.assertIn('currentWallet() === wallet',V);self.assertIn('wallet.scope == scope',V)
 def test_existing_approval_only(self):self.assertIn('session.walletHistoryReader',V);self.assertNotIn('WalletHistoryReadApproval(',V);self.assertNotIn('makeWalletHistoryReader',V);self.assertNotIn('OperationEndpointApproval(',V)
 def test_existing_screen(self):self.assertIn('WalletIncomeView(reader: wallet',V);self.assertIn('Text("wallet.unavailable")',V)
 def test_cancel_and_late_callback(self):self.assertIn('generation == ticket',V);self.assertIn('source.wrappedValue?.id == captured',V);self.assertIn('if captured == nil { captured = current.id }',V);self.assertIn('return current.id == captured ? current : nil',V);self.assertIn('phase != .active { source = nil }',V)
 def test_hosts(self):self.assertIn('row.kind == .redemption, !compact',H);self.assertIn('MerchantPersonalIncomeEntry(row: row',H);self.assertIn('SessionMerchantPersonalIncomeView(session: session, source: $0)',A)
 def test_no_writers(self):
  for text in ['transfer(', 'withdraw(', 'checkout(', 'requestPermission(', 'URLRequest']:self.assertNotIn(text,V)
if __name__=='__main__':unittest.main()
