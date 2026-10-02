"""Offline structure/source-boundary checks; not Swift execution or payment acceptance."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ClubOwnerRefundContractChecks(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_shipping_composition_has_read_only_fallback_and_independent_nil_approval(self):
        app = self.text('App/AppSession.swift')
        self.assertIn('fallback: ClubOwnerRefundReadOnlyAccess(governance: clubGovernanceAccess)', app)
        self.assertIn('approval: runtimeDependencies.ownerRefundApproval', app)
        self.assertIn('ownerRefundApproval: ClubOwnerRefundApproval? = nil', self.text('App/NativeRuntimeDependencies.swift'))
        self.assertNotIn('ClubOwnerRefundService(offlineConfiguration:', app)
        code = self.text('Core/ClubOwnerRefundService.swift').split('public final class ClubOwnerRefundReadOnlyAccess:')[1]
        self.assertIn('public let canDispatchOffline = false', code)
        self.assertIn('throw ClubOwnerRefundFailure.disabled', code)
        for forbidden in ['token:', 'transport.send', 'URLSession']: self.assertNotIn(forbidden, code)
    def test_production_gate_precedes_request_creation(self):
        code = self.text('Core/ClubOwnerRefundService.swift').split('public func cancel(')[1]
        self.assertLess(code.index('guard let offline'), code.index('let request ='))
        self.assertIn('private let offline: (any ClubOwnerRefundOfflineTransport)?', self.text('Core/ClubOwnerRefundService.swift'))
    def test_exact_bounded_form_contract(self):
        code = self.text('Core/ClubOwnerRefundService.swift')
        self.assertIn('appendingPathComponent("api/registration/cancel-by-owner")', code)
        self.assertIn('fields: ["id": String(registrationID)]', code)
        self.assertNotIn('Idempotency-Key', code)
        self.assertEqual(re.findall(r'"(api/[^"\n]+)"', code), ['api/registration/cancel-by-owner'])
    def test_fresh_owner_evidence_and_exact_review_preflight(self):
        contracts = self.text('Core/ClubOwnerRefundContracts.swift'); coordinator = self.text('Core/ClubOwnerRefundCoordinator.swift')
        for marker in ['snapshot.operation == .checkin', 'snapshot.scope == target.scope', 'value["canRefund"].bool', 'allows("OWNER", scope: target.scope)', '["PENDING", "CONTACTED"].contains(status)']:
            self.assertIn(marker, contracts)
        for marker in ['fresh == review.evidence', 'access.identity == identity', 'access.namespace == namespace', 'timeIntervalSince(review.createdAt) <= 120']:
            self.assertIn(marker, coordinator)
    def test_durable_exclusive_lock_precedes_dispatch(self):
        code = self.text('Core/ClubOwnerRefundCoordinator.swift')
        self.assertLess(code.index('try locks.acquire(candidate)'), code.index('try await access.send(review)'))
        after_acquire = code.split('for candidate in keys { try locks.acquire(candidate) }', 1)[1]
        self.assertLess(after_acquire.index('guard current(review.identity, review.namespace, key, generation), pending[key] == review'), after_acquire.index('try await access.send(review)'))
        store = self.text('Core/ClubOwnerRefundLocks.swift')
        self.assertIn('SHA256.hash', store); self.assertIn('.withoutOverwriting', store)
        self.assertIn('Data("pending".utf8)', store)
        self.assertNotIn('JSONEncoder().encode(review)', store)
    def test_no_dispatched_reply_or_readback_can_release_any_lock(self):
        code = self.text('Core/ClubOwnerRefundCoordinator.swift')
        for path in ['Core/ClubOwnerRefundCoordinator.swift', 'Core/ClubOwnerRefundLocks.swift', 'Core/ClubOwnerRefundSyntheticFixtures.swift']:
            self.assertNotIn('releaseRejected', self.text(path))
        self.assertNotIn('.rejected', code)
        reconciliation = code.split('public func reconcile(')[1]
        self.assertNotIn('access.send', reconciliation)
        self.assertIn('evidence.status == "REFUNDED"', reconciliation)
        self.assertIn('.refundRecorded', reconciliation)
    def test_parent_scope_is_exact_hashed_and_acquired_alongside_registration(self):
        code = self.text('Core/ClubOwnerRefundCoordinator.swift')
        for token in ['evidence.orderNo', '"parent-order", orderNo', 'SHA256.hash(data: tuple)', 'return [registration, parent]', 'for candidate in keys { try locks.acquire(candidate) }']:
            self.assertIn(token, code)
        self.assertIn('for candidate in keys { guard !(try locks.contains(candidate))', code)
        self.assertIn('return [registration]', code)
        self.assertIn('if let known = parentKeys[registration] { return [registration, known] }', code)
        self.assertNotIn('complete(', code)
        self.assertNotIn('removeItem', code)
    def test_http_and_business_non_success_always_stay_unconfirmed(self):
        code = self.text('Core/ClubOwnerRefundService.swift')
        self.assertNotIn('(400..<500)', code); self.assertNotIn('ClubOwnerRefundFailure.rejected', code)
        self.assertIn('guard (200..<300).contains(result.1), code == 200', code)
        self.assertIn('throw ClubOwnerRefundFailure.unconfirmed(message: message)', code)
        self.assertIn('fact("club.refund.serverMessage", message)', self.text('App/ClubOwnerRefundPanel.swift'))
    def test_cash_and_points_are_separate_from_record_status(self):
        code = self.text('Core/ClubOwnerRefundContracts.swift')
        for field in ['cancellationStatus', 'cashRefundStatus', 'pointsRefundStatus', 'MANUAL_REVIEW', 'MANUAL_HANDLED', 'MANUAL_VERIFIED', 'DISPATCH_PENDING', 'PARTIAL']:
            self.assertIn(field, code)
        self.assertIn('ClubOwnerRefundReceipt?', code)
        ui = self.text('App/ClubOwnerRefundPanel.swift')
        for label in ['club.refund.cancellation.', 'club.refund.cash.', 'club.refund.points.', 'club.refund.noReplay']:
            self.assertIn(label, ui)
    def test_confirmation_cancel_and_lifecycle_are_wired(self):
        code = self.text('App/ClubOwnerRefundPanel.swift')
        for marker in ['.sheet(item: $review, onDismiss: cancelPending)', 'coordinator?.cancel(pending)', '.interactiveDismissDisabled(status.inFlight)', '.onChange(of: identity)', '.onDisappear { coordinator?.leave(ownerID: ownerID) }', 'coordinator?.canDispatch != true || status.inFlight']:
            self.assertIn(marker, code)
        self.assertIn('ClubOwnerRefundPanel(target:', self.text('App/ClubGovernanceViews.swift'))
        self.assertIn('ownerRefund: governance.ownerRefund', self.text('App/ClubDetailView.swift'))
    def test_bilingual_fragment_covers_all_states_and_receipts(self):
        entries=json.loads(self.text('Resources/ClubOwnerRefundLocalizations.fragment.json'))['strings']
        for key,entry in entries.items():
            self.assertTrue(key.startswith('club.refund.'))
            for lang in ['en','zh-Hans']: self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        for state in ['idle','preparing','reviewing','preflighting','submitting','notSent','acknowledged','manualReview','outcomeUnknown','refundRecorded']:
            self.assertIn('club.refund.phase.'+state,entries)
        for prefix,values in [('cash',['NOT_NEEDED','DISPATCH_PENDING','DISPATCHING','PROCESSING','SUCCESS','PENDING_MANUAL','MANUAL_HANDLED','MANUAL_VERIFIED','MANUAL_REVIEW','UNCONFIRMED']),('points',['NOT_NEEDED','RETURNED','PARTIAL','UNCONFIRMED'])]:
            for value in values:self.assertIn('club.refund.'+prefix+'.'+value,entries)
    def test_synthetic_transport_cannot_reach_network(self):
        code=self.text('Core/ClubOwnerRefundSyntheticFixtures.swift')
        self.assertIn('(Data(body.utf8), status)',code)
        self.assertNotIn('URLSession(',code)
        self.assertNotIn('URLSession.shared',code)
        self.assertIn('ClubOwnerRefundOfflineTransport',code)
if __name__ == '__main__': unittest.main()
