from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
class PurchasedReadContracts(unittest.TestCase):
 def read(self,path):return (ROOT/path).read_text()
 def test_schema_and_duration_are_paid_exact_and_not_inferred(self):
  s=self.read('Core/WorkshopPurchasedContracts.swift')
  for marker in ['PAID_INDIVIDUAL_PURCHASED_VERSION_METADATA_ONLY','PERPETUAL_PURCHASED_VERSION','EXACT_PURCHASED_VERSION','CHANNEL_APPROVAL_REQUIRED','PAID_INSTALL_AUTHORITY_UNAVAILABLE','permitsContentUse: Bool { false }','permitsPurchase: Bool { false }']:
   self.assertIn(marker,s)
  self.assertNotIn('case expired',s)
 def test_normal_account_uses_independent_default_off_paid_factory(self):
  self.assertIn('WorkshopPurchasedAccountLink(browser: session.workshopPurchasedBrowser, makeInstall:',self.read('App/AccountView.swift'))
  s=self.read('App/AppCompositionRoot.swift');self.assertEqual(s.count('workshopPurchasedReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPurchasedReadApproval? = { _ in nil }'),2)
  self.assertEqual(s.count('workshopPurchasedReadApproval: workshopPurchasedReadApproval'),2)
  self.assertIn('WorkshopPurchasedComposition.makeBrowser',self.read('App/AppSession.swift'))
 def test_all_workshop_bindings_revoke_at_existing_identity_boundaries(self):
  s=self.read('App/AppSession.swift');self.assertIn('private func invalidateWorkshopReadBindings() { workshopCreatorPendingBinding.invalidate(); workshopCreatorConsentBinding.invalidate(); workshopPaidProfessionalBinding.invalidate(); workshopOwnedBinding.invalidate(); workshopPurchasedBinding.invalidate(); workshopPaidInstallBinding.invalidate(); workshopPaidInstalledTextBinding.invalidate() }',s)
  self.assertGreaterEqual(s.count('invalidateWorkshopReadBindings()'),10)
  self.assertIn('invalidateWorkshopReadBindings()\n        workshopReadConfigurationChanging = true',s)
 def test_permits_fence_queued_requests_and_unauthorized_side_effects(self):
  s=self.read('Core/WorkshopPurchasedService.swift');self.assertIn('try check(lifetime); onUnauthorized(lease.context)',s)
  n=self.read('App/WorkshopPurchasedNavigationState.swift');self.assertIn('before == nil || before == browser.nextCursor',n);self.assertIn('let action = permit.offer()',n)
  self.assertIn('action.isLive, !Task.isCancelled, current(), action.claim()',self.read('Core/WorkshopPurchasedBrowser.swift'))
 def test_read_routes_are_exact_and_no_purchase_ui_exists(self):
  s=self.read('App/WorkshopPurchasedReadRoute.swift')
  for marker in ['url.query == nil','request.httpBodyStream == nil','"Transfer-Encoding") == nil','String(body.count)','before_order_line_id=','WorkshopPurchasedWire.license']:
   self.assertIn(marker,s)
  view=self.read('App/WorkshopPurchasedLibraryView.swift');self.assertIn('purchaseUnavailable',view)
  for absent in ['StoreKit','requestPayment','purchase()', 'URLSession']:self.assertNotIn(absent,view)
 def test_honest_bilingual_lifetime_and_channel_copy(self):
  strings=json.loads(self.read('Resources/WorkshopPurchased.xcstrings'))['strings']
  for key in ['durationScope','purchaseUnavailable','applicationUnavailable','status.ACTIVE','status.SUSPENDED','status.REVOKED']:
   self.assertEqual(set(strings['workshopPurchased.'+key]['localizations']),{'en','zh-Hans'})
 def test_real_service_normal_navigation_and_transport_regressions_authored(self):
  s=self.read('Tests/AppUnitTests/WorkshopPurchasedNormalAccountTests.swift')
  for marker in ['testNormalHostedPurchasedEntry','testQueuedListAfterBackAndReopen','testCurrent401','testRoleABA','testConfigurationABA','testInvalidPaginationOffer','strictExpectedContext','UIHostingController']:
   self.assertIn(marker,s)
  self.assertIn('testFreeOwnedApprovalCannotReadPurchasedLibrary',self.read('Tests/AppUnitTests/WorkshopPurchasedTransportTests.swift'))
