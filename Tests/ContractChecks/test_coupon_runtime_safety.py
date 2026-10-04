"""Offline source structure checks, not Swift compilation or behavioral evidence."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class CouponRuntimeSafetyTests(unittest.TestCase):
 def read(self,p): return (ROOT/p).read_text()
 def test_default_off_separate_capabilities_and_clone_forwarding(self):
  s=self.read('App/AppCompositionRoot.swift')
  for name,kind in [('couponReadApproval','CouponManagementReadApproval'),('couponWriteApproval','CouponManagementWriteApproval')]:
   self.assertEqual(s.count(f'{name}: @escaping @MainActor (RuntimeDependencyContext) -> {kind}? = {{ _ in nil }}'),2)
   self.assertIn(f'{name}: {name}',s)
  self.assertIn('func sendConfirmed(',s)
  self.assertIn('try authorization.consume(request',s)
  self.assertIn('couponBeforeForward',s)
 def test_private_ticket_and_persisted_frozen_payload_precede_dispatch(self):
  s=self.read('Core/CouponManagementCoordinator.swift')
  self.assertIn('fileprivate init(record:',s)
  self.assertLess(s.index('record.wire = try'),s.index('try locks.acquire(record)'))
  self.assertLess(s.index('try locks.acquire(record)'),s.index('CouponManagementDispatchAuthorization(record:'))
  self.assertIn('!consumed',s);self.assertIn('consumed = true',s)
  self.assertIn('locks.pending(ownerKey: record.ownerKey, resource: record.resource) == record',s)
  self.assertIn('request.allHTTPHeaderFields == expected.allHTTPHeaderFields',s)
 def test_fresh_merchant_scope_and_no_subscription(self):
  s=self.read('Core/CouponManagementRuntime.swift')
  self.assertIn('service.access(token:',s)
  self.assertIn('access.merchantID == merchantID',s)
  self.assertIn('access.permissions.contains("merchant:coupon:manage")',s)
  self.assertNotIn('/subscription',s)
  c=self.read('Core/CouponManagementCoordinator.swift')
  self.assertEqual(c.count('await authorizer.freshPermission'),3)
  self.assertIn('permission == accepted.permission',c)
 def test_explicit_merchant_scope_and_preserved_date_codec(self):
  s=self.read('Core/CouponManagementContract.swift')
  self.assertEqual(s.count('"scope": "MERCHANT"'),3)
  bridge=self.read('Core/CouponManagementReadTransport.swift')
  self.assertIn('CouponValidityTime.parse(start)',bridge)
  self.assertNotIn('ISO8601DateFormatter',bridge)
 def test_missing_id_unknown_readback_does_not_clear_unknown(self):
  s=self.read('Core/CouponManagementContract.swift')
  self.assertIn('let id: CouponDefinitionID',s)
  self.assertIn('else { return .unknown }',s)
  c=self.read('Core/CouponManagementCoordinator.swift')
  self.assertIn('case .unknown: issue = .locked',c)
  self.assertIn('JSONDecoder().decode(Envelope.self, from: data)',s)
  self.assertNotIn('object["code"] as? Int',s)
  self.assertIn('transport.isSynthetic ? .rejected(message) : .unknownWithMessage(message)',s)
  self.assertNotIn('locks.release',c[c.index('private func refreshAfterMutation'):])
  self.assertIn('acknowledgedDefinitionID',c);self.assertIn('verifiedRecord',c)
 def test_partial_write_capability_is_checked_before_journal(self):
  c=self.read('Core/CouponManagementCoordinator.swift')
  self.assertIn('guard canReviewPublish',c);self.assertIn('guard canReviewStop',c)
  self.assertLess(c.index('guard adapter.permits(accepted.action)'),c.index('try locks.acquire(record)'))
  s=self.read('App/AppSession.swift')
  self.assertIn('CouponManagementWriteApproval.Action.allCases.filter',s)
  self.assertIn('actions: actions',s)
 def test_normal_root_fixture_uses_composition_and_disk(self):
  s=self.read('App/QuestifyApp.swift')
  self.assertIn('coupon.composition().makeSession()',s)
  self.assertIn('SessionRootView(session:session)',s)
  f=self.read('App/CouponRuntimeFixture.swift')
  self.assertTrue(f.startswith('#if DEBUG'))
  self.assertIn('CouponManagementFileLocks',f);self.assertIn('makeTransport: { self }',f)
  self.assertNotIn('URLSession',f)
  t=self.read('Tests/AppUITests/CouponRuntimeFlowTests.swift')
  for route in ['account.merchant','merchant.content.open','merchant.content.entry.recruiting','couponManagement.marketing.entry']:
   self.assertIn(route,t)
 def test_ui_mount_replaces_coordinator_and_retains_time_rights(self):
  self.assertIn('.id(session.couponManagementSession)',self.read('App/SessionCouponManagementView.swift'))
  c=self.read('App/AppSession.swift')
  self.assertIn('self.currentRuntimeDependencyContext == captured',c)
  self.assertIn('self.couponManagementSession == capturedSession',c)
  self.assertIn('current coupon record verified',self.read('tools/build_coupon_management_localizations.py'))
if __name__ == '__main__': unittest.main()
