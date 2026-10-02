"""Additive coupon integration evidence only; Apple compiler/runtime not exercised."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class CouponManagementIntegrationTests(unittest.TestCase):
 def read(self,p): return (ROOT/p).read_text()
 def test_source_marketing_host_is_mounted_after_fresh_snapshot(self):
  s=self.read('App/MerchantContentViews.swift')
  self.assertIn('case .recruiting:\n            // Source marketing-home',s)
  self.assertIn('merchantCouponManagementDestination',s)
  self.assertIn('if c.isCurrent, let snapshot = c.snapshot',s)
  self.assertIn('permissions.contains("merchant:marketing:read")',self.read('Core/MerchantContentService.swift'))
 def test_session_has_stable_identity_and_default_grants_absent(self):
  s=self.read('App/AppSession.swift')
  part=s[s.index('var couponManagementSession:'):s.index('private var walletEpochCache:')]
  self.assertIn('epoch: gate.currentStamp, authorizationRevision: account.effectiveRole',part)
  self.assertIn('readApproval: OperationEndpointApproval? = nil',part)
  self.assertIn('authorizer: publisher ?? CouponPublisherUnavailable()',part)
  self.assertNotIn('dormantWritesEnabled: true',part)
  self.assertNotIn('UUID()',part)
 def test_fixture_does_not_construct_real_session(self):
  self.assertEqual(self.read('App/QuestifyApp.swift').count('contains("--ui-coupon-management")'),2)
  self.assertIn('--ui-coupon-management',self.read('Tests/AppUITests/CouponManagementFlowTests.swift'))
 def test_http_read_approval_cannot_become_mutation_grant(self):
  s=self.read('Core/CouponManagementReadTransport.swift').split('public final class CouponManagementApprovedReadTransport')[1]
  self.assertIn('approval.allows(configuration: configuration',s)
  self.assertIn('await currentSession() == session',s)
  self.assertNotIn('/publish"',s);self.assertNotIn('/stop"',s)
 def test_dormant_http_is_concrete_and_default_off(self):
  s=self.read('Core/CouponManagementReadTransport.swift')
  self.assertIn('dormantWritesEnabled: Bool = false',s)
  self.assertIn('request.setValue(payload.contentType',s)
  self.assertIn('request.httpBody = payload.data',s)
  self.assertIn('http.send(request)',s)
  self.assertIn('testDormantHTTPBothGrantsOffAndExactPublicationAndStopSerialization',self.read('Tests/CoreTests/CouponManagementTests.swift'))
 def test_no_claim_or_pass_operation_is_invented(self):
  s=self.read('Core/CouponManagementContract.swift')
  paths=set(re.findall(r'"(/api/coupon/[^"\n]+)"',s))
  self.assertEqual(paths,{'/api/coupon/mypublishlist','/api/coupon/publish','/api/coupon/stop'})
  self.assertIn('public struct CouponDefinitionID',self.read('Core/CouponManagementDomain.swift'))
 def test_localization_and_durable_production_storage(self):
  s=self.read('App/CouponManagementView.swift');self.assertNotIn('String(localized:',s)
  self.assertIn('locale: locale',s)
  self.assertIn('CouponManagementFileLocks',self.read('App/SessionCouponManagementView.swift'))
  self.assertNotIn('MemoryLocks',self.read('App/SessionCouponManagementView.swift'))
  c=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
  self.assertEqual(len([k for k in c if k.startswith('couponManagement.')]),71)
