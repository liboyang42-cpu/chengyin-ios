"""Static native contracts only, not Swift execution or provider acceptance."""
import json
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class OrderLifecycleProductionContracts(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()
    def test_factory_is_explicit_and_default_off(self):
        s = self.read('Core/OrderLifecycleProduction.swift')
        self.assertIn('enum OrderLifecycleProductionFactory', s)
        self.assertIn('configuration: OrderLifecycleProductionConfiguration? = nil', s)
        self.assertIn('externalCheckoutApproved: Bool = false, devicePaymentApproved: Bool = false', s)
        self.assertNotIn('#if DEBUG', s)
    def test_exact_context_order_action_and_source_revision(self):
        s = self.read('Core/OrderLifecycleProduction.swift')
        for fragment in ['context.market == market', 'context.baseURL == baseURL', 'context.role == role',
                         'context.session.namespace == namespace', 'context.session.accountID == accountID',
                         'current() == captured', 'review.scope == openedReviewScope', 'currentReviewScope() == openedReviewScope', 'orderID == review.detail.id', 'ownerType == review.detail.ownerType',
                         'ownerID == review.detail.ownerID', 'action == review.action', 'sourceRevision == OrderLifecycleSourceContract.revision']:
            self.assertIn(fragment, s)
    def test_awaited_reservation_has_immediate_fence(self):
        s = self.read('Core/OrderLifecycleProduction.swift')
        a = s.index('try await journal.reserve(record)')
        b = s.index('if review.action != .payment', a)
        after = s[a:b]
        self.assertIn('try check(review, visible: visible)', after)
        self.assertIn('try await fresh(review, visible: visible)', after)
        self.assertIn('try await checkLegal(review, visible: visible)', after)
        check = s[s.index('private func check('):s.index('private func fresh(')]
        self.assertIn('Task.checkCancellation()', check)
        self.assertIn('visible(), current() == captured', check)
        self.assertIn('currentReviewScope() == openedReviewScope', check)
    def test_fresh_snapshot_expiry_and_real_legal_read(self):
        s = self.read('Core/OrderLifecycleProduction.swift')
        for fragment in ['value == review.detail', 'OrderLifecycleCoordinator.isReviewable', 'now() < deadline',
                         'api/compliance/consents/latest', 'ComplianceSubject.signup.fields()',
                         'consent?.matches(.signup, event: .agree)', 'consent?.docVersion == expected.version', 'finalDocument == expected']:
            self.assertIn(fragment, s)
        self.assertNotIn('api/compliance/consents"', s)
    def test_source_builders_shared_provider_and_server_only_result(self):
        s = self.read('Core/OrderLifecycleProduction.swift')
        for fragment in ['OrderLifecycleRequestContract.cancellation', 'OrderLifecycleRequestContract.paymentParameters',
                         'provider.pay(registrationID: review.detail.id, parameters: parameters)',
                         'PaymentProviderReturnFlow(', 'OrderPaymentVerifier(', 'selfPlayJournal.pending']:
            self.assertIn(fragment, s)
        self.assertNotIn('PayReq(', s)
        self.assertNotIn('requestId"', s)
    def test_monotonic_lock_and_separate_refund_transition(self):
        s = self.read('Core/OrderLifecycleProduction.swift')
        for fragment in ['paymentObservedPaid', 'options: .atomic', 'record.action == OrderLifecycleAction.refund.rawValue',
                         'detail.paymentStatus == 2, detail.registrationStatus == 2']:
            self.assertIn(fragment, s)
        self.assertNotIn('func clear(', s)
        self.assertNotIn('removeObject', s)
    def test_ui_production_action_and_provider_result_are_mounted(self):
        app = self.read('App/AppSession.swift'); ui = self.read('App/OrderLifecycleView.swift')
        for value in ['OrderLifecycleProductionFactory.make', 'orderLifecycleConfiguration', 'selfPlayOperationGate', 'nativeWeChatPaymentAdapter']:
            self.assertIn(value, app)
        for value in ['orderLifecycle.review.confirmProduction', 'PaymentProviderReturnSheet', 'canDispatch']:
            self.assertIn(value, ui)
    def test_ordinary_fake_transport_test_coverage(self):
        s = self.read('Tests/CoreTests/OrderLifecycleProductionTests.swift')
        self.assertNotIn('#if DEBUG', s)
        self.assertIn('class HTTP: HTTPTransport', s)
        self.assertGreaterEqual(s.count('    func test'), 16)
        for name in ['testTaskCancellationAfterAwaitedReservation', 'testAccountChangeAfterAwaitedReservation',
                     'testDismissalAfterAwaitedReservation', 'testProviderReturnIsNotPayment', 'testFileJournalIsDurable']:
            self.assertIn(name, s)
    def test_new_bilingual_keys_are_keyed_additions(self):
        fragment = json.loads(self.read('docs/order-lifecycle-production-localizations.json'))
        self.assertEqual(len(fragment), 5)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key, value in fragment.items():
            self.assertEqual(catalog[key], value)
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
if __name__ == '__main__': unittest.main()
