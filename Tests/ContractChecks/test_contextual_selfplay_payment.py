"""Native source contracts only. No claim of Swift execution or real payment."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
class ContextSelfPlayTests(unittest.TestCase):
    def read(self,p):return (ROOT/p).read_text()
    def test_consent_and_lock_precede_create(self):
        s=self.read('Core/TopicSelfPlayFlow.swift').split('public func confirm(',1)[1].split('public func prepareExistingPayment',1)[0]
        self.assertLess(s.index('client.recordConsent'),s.index('journal.write(record)'))
        self.assertLess(s.index('journal.write(record)'),s.index('client.create'))
        self.assertIn('fresh.selfPlayPrice == value.price',s)
    def test_journal_callbacks_are_fenced_before_each_dispatch(self):
        s=self.read('Core/TopicSelfPlayFlow.swift')
        fence='guard stamp == generation, current, !Task.isCancelled else { return }'
        for write,dispatch in [
            ('try journal.write(record); pending = record', 'let created = try await client.create(value.intent)'),
            ('try markPaymentAttempted()', '_ = await provider.pay(registrationID: created.registrationID, parameters: params)'),
            ('try markPaymentAttempted()', '_ = await provider.pay(registrationID: value.registrationID, parameters: params)')]:
            prefix=s[:s.index(dispatch)]
            between=prefix[prefix.rindex(write)+len(write):]
            self.assertIn(fence,between)
            self.assertNotIn('pending = nil',between)
    def test_provider_outcome_is_never_payment_success(self):
        s=self.read('Core/TopicSelfPlayFlow.swift')
        self.assertIn('_ = await provider.pay(registrationID: created.registrationID, parameters: params)',s)
        self.assertIn('_ = await provider.pay(registrationID: value.registrationID, parameters: params)',s)
        self.assertNotIn('case .returned:',s)
        self.assertIn('try markPaymentAttempted()',s)
        self.assertIn('pending?.paymentAttempted != true',s)
        self.assertIn('value.ownerType == 1, value.ownerID == topic.id',s)
    def test_typed_topic_contract_has_no_activity_fields(self):
        s=self.read('Core/TopicSelfPlayContracts.swift').split('public struct TopicSelfPlayIntent',1)[1].split('public struct TopicSelfPlayDocument',1)[0]
        self.assertIn('try c.encode(1, forKey: .ownerType)',s)
        self.assertIn('try c.encode("APP", forKey: .payChannel)',s)
        self.assertNotIn('ticketId',s);self.assertNotIn('quoteSign',s)
    def test_runtime_factory_has_separate_checkout_and_provider_gates(self):
        s=self.read('App/AppSession.swift').split('func topicSelfPlayFlow(',1)[1].split('var couponManagementSession',1)[0]
        for marker in ['selfPlayExternalCheckoutApproved','runtimeDependencies.signupDocument','factory.permits(.topicSelfPlayConsentWrite)','factory.configuration.selfPlayPayment','runtimeDependencies.selfPlayPayment','currentRuntimeDependencyContext == captured']:
            self.assertIn(marker,s)
        d=self.read('Core/BusinessRuntimeConfiguration.swift')
        self.assertIn('selfPlayPayment: Bool = false',d);self.assertIn('selfPlayExternalCheckoutApproved: Bool = false',d)
    def test_review_dismissal_cannot_unlock_inflight_create(self):
        self.assertIn("pending == nil && phase == .reviewing",self.read("Core/TopicSelfPlayFlow.swift"))
    def test_normal_topic_browse_and_direct_routes_mount(self):
        self.assertIn('SessionTopicSelfPlayView',self.read('App/PlatformConsumerSessionOwner.swift'))
        self.assertIn('SessionTopicSelfPlayView',self.read('App/SessionTopicBrowserView.swift'))
        self.assertIn('contextSelfPlay.open',self.read('App/TopicDetailView.swift'))
        self.assertIn('PaymentProviderReturnSheet(flow: result)',self.read('App/TopicSelfPlaySheet.swift'))
    def test_new_order_requires_authoritative_terminal_proof(self):
        flow=self.read("Core/TopicSelfPlayFlow.swift")
        self.assertIn("[3, 4].contains(order.registrationStatus ?? 0)",flow)
        self.assertIn("try journal.resolve(pending, authoritativeOrder: order)",flow)
        self.assertIn("consented = false; document = nil",flow)
    def test_unresolved_journal_has_no_pii(self):
        s=self.read('Core/TopicSelfPlayContracts.swift').split('public struct TopicSelfPlayPending',1)[1].split('@MainActor public protocol TopicSelfPlayJournaling',1)[0]
        for secret in ['realName','phone','token','payParams']:self.assertNotIn(secret,s)
    def test_result_verifies_before_display_and_unknown_goes_back_to_host(self):
        self.assertIn('await verifier.verify(registrationID:',self.read('Core/PaymentProviderReturnFlow.swift'))
        view=self.read('App/PaymentProviderReturnSheet.swift')
        self.assertIn('.interactiveDismissDisabled()',view)
        self.assertIn('phase == .unknown || phase == .accessDenied { finish(phase) }',view)
        self.assertIn('2_000_000_000',view)
if __name__=='__main__':unittest.main()
