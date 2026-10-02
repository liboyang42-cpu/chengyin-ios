"""Static source assertions; no Swift execution or live service acceptance."""
import json,pathlib,re,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class OrderLifecycleSourceTests(unittest.TestCase):
 def read(self,path):return (ROOT/path).read_text()
 def test_exact_read_only_routes(self):
  s=self.read('Core/OrderLifecycleService.swift')
  self.assertEqual(set(re.findall(r'"(api/[^" ]+)"',s)),{'api/registration/info','api/coupon/status'})
 def test_default_adapter_disabled_before_transport(self):
  s=self.read('Core/OrderLifecycleDormantAdapter.swift')
  self.assertIn('private var fixtureOnly = false',s)
  self.assertIn('isProductionDispatchEnabled: Bool { false }',s)
  self.assertIn('guard fixtureOnly else { throw OrderLifecycleFailure.notDispatched }',s)
  self.assertRegex(s,r'#if DEBUG\s+public init\(fixtureConfiguration:')
  self.assertNotIn('OrderLifecycleDormantAdapter(',self.read('App/AppSession.swift'))
 def test_cancel_refund_contracts_and_no_fabricated_idempotency_field(self):
  s=self.read('Core/OrderLifecycleCoordinator.swift')
  self.assertIn('case .cancel: return "api/registration/cancel"',s)
  self.assertIn('case .refund: return "api/registration/cancel-refund"',s)
  adapter=self.read('Core/OrderLifecycleDormantAdapter.swift')
  self.assertNotIn('"requestId":',adapter);self.assertNotIn('"quoteSign":',adapter)
 def test_immutable_review_session_and_target_guards(self):
  s=self.read('Core/OrderLifecycleCoordinator.swift')
  for guard in ['detail.id == orderID','review.scope == reader.scope','review.accountID == reader.accountID','review.detail == detail','now() < review.expiresAt','!isAttemptBlocking(review.action, orderID: review.detail.id)','outcomeUnknown']:
   self.assertIn(guard,s)
  self.assertIn('if try dispatcher.pending(orderID: review.detail.id) != nil',s)
  self.assertIn('catch { records[key] = .outcomeUnknown',s)
 def test_ui_has_no_credentials_provider_or_scanner_dispatch(self):
  s='\n'.join(self.read('App/'+file) for file in ['OrderLifecycleView.swift','OrderPassPreviewView.swift'])
  for value in ['AsyncImage','openURL','UIPasteboard','AVCaptureSession','qrcodeUrl','quoteSign','nonceStr']:
   self.assertNotIn(value,s)
 def test_refund_truth_and_team_source_identity(self):
  s=self.read('Core/OrderLifecycleContracts.swift')
  self.assertIn('case 1, 4: return result(.refunded',s)
  self.assertIn('guard paymentStatus == 2',s)
  team=self.read('Core/OrderLifecycleTeamContext.swift')
  for value in ['registrationID: id','ownerType == 2','registrationStatus == 2','teamMode == 2','teamMaxMembers']:
   self.assertIn(value,team)
 def test_session_owned_and_isolated_fixture_mounting(self):
  app=self.read('App/AppSession.swift');self.assertIn('self.currentOrderLifecycleSession == captured',app)
  self.assertIn('OrderLifecycleCoordinator(reader: orderLifecycleReader,',app)
  self.assertIn('production: { [weak self] in self?.makeOrderLifecycleDispatcher() }',app)
  self.assertEqual(self.read('App/QuestifyApp.swift').count('--uitesting-order-lifecycle-fixture'),2)
  self.assertIn('lifecycleCoordinator: orderLifecycleCoordinator',self.read('App/TicketWalletView.swift'))
 def test_payment_timeout_and_cancellation_cannot_become_paid(self):
  s=self.read('Core/OrderPaymentVerifier.swift')
  for value in ['currentScope()', 'systemUptime','case unknown','generation','OrderPaymentReadRace','guard !finished else { return }']:
   self.assertIn(value,s)
  self.assertNotIn('WechatPayOutcome',s)
 def test_bilingual_catalog_matches_owned_entries(self):
  entries=json.loads(self.read('docs/order-lifecycle-localizations.json'));self.assertEqual(len(entries),110)
  cat=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
  for entry in entries:
   for lang in ['en','zh-Hans']:self.assertEqual(entry[lang],cat[entry['key']]['localizations'][lang]['stringUnit']['value'])
 def test_station_choice_never_uses_unrelated_station_id(self):
  s=self.read('Core/OrderVerificationContracts.swift')
  self.assertIn('let id = value.registrationMerchantId, id > 0',s)
  self.assertIn('code == 401',s);self.assertIn('needChapterChoice == true',s)
if __name__=='__main__':unittest.main()
