"""Native bank integration structure only; no Swift compiler, bank or server calls."""
from pathlib import Path
import json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
class BankWithdrawalContractTests(unittest.TestCase):
 def test_no_live_factory_or_implicit_financial_grant(self):
  app=read('App/AppSession.swift');view=read('App/BankWithdrawalView.swift');adapter=read('Core/BankWithdrawalAdapter.swift')
  self.assertIn('factory.permits(.bankPrepare)',app);self.assertIn('factory.permits(.bankConsentRead)',app);self.assertIn('let provider = runtimeDependencies.bankDocument',app);self.assertIn('businessConfiguration: BusinessRuntimeConfiguration? = nil',read('App/NativeRuntimeDependencies.swift'))
  self.assertIn('var adapter: BankWithdrawalAdapter? = nil',view)
  self.assertIn('enableReviewedWrites: Bool = false',adapter)
  self.assertIn('approval: OperationEndpointApproval? = nil',adapter)
  self.assertIn('consentEvidence: @escaping () -> BankWithdrawalConsentEvidence? = { nil }',adapter)
  self.assertNotIn('URLSession',adapter)
 def test_entry_and_native_state_surfaces(self):
  self.assertIn('BankWithdrawalView(reader: reader)',read('App/WithdrawalSupportLandingView.swift'))
  view=read('App/BankWithdrawalView.swift')
  for key in ['SecureField','keyboardDone','reviewSheet','confirmSubmit','applicationID','unresolved','interactiveDismissDisabled(true)','WalletWithdrawalsView(reader: reader)']:self.assertIn(key,view)
 def test_input_is_memory_only_and_journal_has_no_body(self):
  contracts=read('Core/BankWithdrawalContracts.swift');adapter=read('Core/BankWithdrawalAdapter.swift')
  self.assertIn('public struct BankWithdrawalDraft: Equatable, CustomStringConvertible',contracts)
  self.assertNotIn('BankWithdrawalDraft: Codable',contracts)
  self.assertIn('OperationPendingRecord(operationID: review.id, ownerKey: owner(review.scope), targetKey: target)',adapter)
  self.assertNotRegex(adapter+contracts,r'print\(|NSLog\(|logger\.')
  prepare=adapter.split('public func prepare(')[1].split('private func requireProof')[0]
  self.assertLess(prepare.index('try journal.write(pending)'),prepare.index('await send(request'))
 def test_exact_wire_and_server_states(self):
  contracts=read('Core/BankWithdrawalContracts.swift');adapter=read('Core/BankWithdrawalAdapter.swift')
  for key in ['requestId','realname','bankName','bankAccount','mobilephone','withdrawalAmount','challengeId']:self.assertIn('"'+key+'"',contracts)
  self.assertIn('"STATIC", "WARNING", "BLOCKED"',contracts)
  self.assertIn('response.state == "PENDING"',contracts)
  self.assertIn('confirmed.state == "CONFIRMED"',adapter)
  self.assertIn('response.state == "REJECTED"',adapter)
  self.assertIn('api/fund/preflight/bank-withdrawal',adapter);self.assertIn('api/withdrawal/create',adapter)
 def test_consent_is_current_and_server_sourced(self):
  s=read('Core/BankWithdrawalContracts.swift')
  for text in ['bank_account_collection','withdrawal','currentDocumentVersion == consentDocumentVersion','consent: ComplianceConsent','eventType == "AGREE"']:self.assertIn(text,s)
 def test_no_automatic_replay_and_confirm_cannot_spend_without_create_grant(self):
  s=read('Core/BankWithdrawalAdapter.swift');submit=s.split('public func submit(')[1].split('public func reject(')[0]
  self.assertLess(submit.index('let create = try authorizedRequest'),submit.index('await send(confirm'))
  self.assertLess(submit.index('proof = nil'),submit.index('await send(confirm'))
  self.assertIn('session == capturedSession',s)
  self.assertIn('now() < value.expiresAt',s)
  self.assertNotRegex(s,r'func (reset|retry|force)')
 def test_background_and_account_loss_clear_sensitive_form(self):
  s=read('App/BankWithdrawalView.swift')
  for text in ['.onChange(of: reader.scope)', 'phase == .background { clear() }','.onDisappear { clear() }','draft = .init(); snapshot = nil; review = nil; proof = nil','adapter?.discardLocalInput()']:self.assertIn(text,s)
 def test_status_mapping_matches_current_backend(self):
  s=read('Core/WalletCommerceContracts.swift')
  self.assertIn('["wallet.pendingReview", "wallet.approved", "wallet.rejected", "wallet.paid"][status]',s)
 def test_catalog_covers_bank_text_in_both_languages(self):
  catalog=json.loads(read('Resources/Localizable.xcstrings'))['strings'];view=read('App/BankWithdrawalView.swift')+read('App/WithdrawalSupportLandingView.swift')
  keys=set(re.findall(r'"(bank\.withdrawal\.[A-Za-z.]+)"',view))
  identifiers={'bank.withdrawal.entry','bank.withdrawal.receipt','bank.withdrawal.issue','bank.withdrawal.form','bank.withdrawal.reviewSheet'}
  for key in keys-identifiers:
   self.assertIn(key,catalog);self.assertEqual(set(catalog[key]['localizations']),{'en','zh-Hans'})
 def test_authored_swift_proof_and_ui_tests_remain_offline(self):
  s=read('Tests/CoreTests/BankWithdrawalTests.swift')
  self.assertIn('https://example.com',s)
  self.assertIn('UnknownConfirmationPersistsAcrossRestart',s);self.assertIn('MissingCreateGrantDoesNotEvenConfirm',s)
  self.assertIn('Bank withdrawal',read('App/WalletCommerceFixtureHost.swift'))
  self.assertIn('testBankFormIsReachableAndClearlyDormant',read('Tests/AppUITests/WalletCommerceFlowTests.swift'))
if __name__=='__main__':unittest.main(verbosity=2)
