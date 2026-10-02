"""Source-shape guards only; no Swift compilation or runtime evidence."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class RegistrationWaitlistCompositionTests(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_shipped_host_is_scoped_and_default_off(self):
        source = self.read('App/AppSession.swift')
        for guard in ('registrationApproval: RegistrationProductionApproval? = nil', 'registrationStorefront: @escaping () -> String? = { nil }', 'RegistrationProductionFactory.make', 'activityID == service.approval.activityID', 'Date() < service.approval.expiresAt'):
            self.assertIn(guard, source)
    def test_factory_uses_real_transport_and_exact_grants(self):
        source = self.read('Core/RegistrationProduction.swift')
        for guard in ('transport: URLSessionTransport()', 'session.identity == approval.identity', 'session.storefront == approval.storefront', 'session.market == approval.market', 'session.namespace == approval.endpoint.namespace', 'approval.endpoint.allows', 'market == .china', 'storefront == "CHN"'):
            self.assertIn(guard, source)
        for forbidden in ('#if DEBUG', 'writesEnabled', 'WXApi', 'StoreKit', 'payment/retry', 'waitlist/claim', 'waitlist/renew'): self.assertNotIn(forbidden, source)
    def test_waitlist_scope_and_backend_timezone(self):
        source = self.read('Core/RegistrationWaitlist.swift')
        scope = source.split('public struct RegistrationWaitlistScope:')[1].split('public enum RegistrationWaitlistState')[0]
        self.assertIn('activityID = "activityId", ticketID = "ticketId"', scope)
        for field in ('memberID', 'quantity', 'participants', 'realName', 'phone'): self.assertNotIn(field, scope)
        self.assertIn('TimeZone(identifier: "Asia/Shanghai")', source)
        self.assertNotIn('121', source)
    def test_same_offer_pair_reaches_quote_and_create(self):
        source = self.read('Core/RegistrationContracts.swift')
        self.assertEqual(source.count('try c.encode(waitlistOffer.id, forKey: .waitlistOfferId)'), 2)
        self.assertEqual(source.count('try c.encode(waitlistOffer.token, forKey: .waitlistOfferToken)'), 2)
        flow = self.read('Core/RegistrationUIFlow.swift')
        self.assertIn('review.draft.details(waitlistOffer: review.selection.waitlistOffer)', flow)
        self.assertIn('result.offer(at: now()) != activeWaitlistOffer', flow)
    def test_durable_lock_before_create_and_no_unverified_clear(self):
        source = self.read('Core/RegistrationProduction.swift')
        create = source.split('public func create(')[1].split('public func creationLock')[0]
        self.assertLess(create.index('try journal.write(pending)'), create.index('registration.create(intent'))
        self.assertNotIn('journal.clear', create)
        for guard in ('hasFreshQuote(intent)', 'public func readRetainedStatus', 'RegistrationPendingFailure.waitlistUnknown'): self.assertIn(guard, source)
    def test_explicit_legal_notice_version_and_replay_guard(self):
        source = self.read('Core/RegistrationProduction.swift')
        for guard in ('func agreeToSignupNotice', 'consent?.docVersion == approval.consentVersion', 'fields["eventType"] = "AGREE"', 'fields["requestId"] = pending.operationID.uuidString', 'targetKey: key) == nil'): self.assertIn(guard, source)
        self.assertIn('Link("registration.waitlist.legalNotice", destination: grant.noticeURL)', self.read('App/RegistrationSheetView.swift'))
    def test_inline_native_waitlist_and_relaunch_readback(self):
        source = self.read('App/RegistrationSheetView.swift')
        for marker in ('waitlistSection', 'TimelineView', 'await flow.reviewWaitlistOffer()', 'await flow.cancelWaitlist()', 'await flow.readDurableStatus()', 'await flow.recordSignupConsent()'): self.assertIn(marker, source)
    def test_state_catalog_is_bilingual(self):
        entries = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for suffix in ('NONE', 'WAITING', 'OFFERED', 'CLAIMED', 'CONVERTED', 'CANCELLED', 'EXPIRED'):
            entry = entries['registration.waitlist.state.' + suffix]
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for value in entry['localizations'].values(): self.assertTrue(value['stringUnit']['value'])
if __name__ == '__main__': unittest.main()
