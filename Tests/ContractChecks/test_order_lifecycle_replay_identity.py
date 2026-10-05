"""Static replay/privacy contracts; Apple execution is a separate required gate."""
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class OrderLifecycleReplayIdentityContracts(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()
    def test_replay_identity_excludes_session_scope_role_and_token(self):
        source = self.read('Core/OrderLifecycleCoordinator.swift')
        key = source.split('private struct AttemptKey:', 1)[1].split('private var recordScopes:', 1)[0]
        for field in ['accountID: Int', 'orderID: Int', 'replayContext: OrderLifecycleReplayContext?']:
            self.assertIn(field, key)
        for forbidden in ['scope: UUID', 'epoch:', 'token:', 'role:']:
            self.assertNotIn(forbidden, key)
        identity = self.read('Core/OrderLifecycleService.swift').split('public struct OrderLifecycleReplayContext:', 1)[1].split('/// Session token', 1)[0]
        for field in ['market: RegionalMarket', 'baseURL: URL', 'namespace: String']:
            self.assertIn(field, identity)
        self.assertNotIn('context.role', identity); self.assertNotIn('context.session.epoch', identity)
    def test_visible_receipts_redact_without_removing_stable_lock(self):
        source = self.read('Core/OrderLifecycleCoordinator.swift')
        attempt = source.split('public func attempt(orderID:', 1)[1].split('public func isAttemptBlocking', 1)[0]
        self.assertIn('recordScopes[key] == reader.scope', attempt)
        self.assertIn('return .outcomeUnknown(localAttemptID: id)', attempt)
        self.assertNotIn('removeValue', attempt)
    def test_stale_public_lookup_cannot_leak_captured_reservation(self):
        source = self.read('Core/OrderLifecycleProduction.swift')
        public = source.split('public func pending(orderID:', 1)[1].split('func capturedReservation', 1)[0]
        self.assertIn('guard isCurrent else { return nil }', public)
        self.assertLess(public.index('guard isCurrent'), public.index('journal.pending'))
        captured = source.split('func capturedReservation', 1)[1].split('public func observePaid', 1)[0]
        self.assertIn('review.accountID == captured.session.accountID', captured)
        self.assertIn('review.scope == openedReviewScope', captured)
        coordinator = self.read('Core/OrderLifecycleCoordinator.swift')
        self.assertIn('if let pending = try dispatcher.capturedReservation(for: review)', coordinator)
        self.assertIn('records[key] = .outcomeUnknown(localAttemptID: pending.attemptID)', coordinator)
    def test_production_composition_requires_matching_explicit_owner(self):
        source = self.read('Core/OrderLifecycleProduction.swift')
        matches = source.split('public func matchesReader', 1)[1].split('public func pending', 1)[0]
        for check in ['let replayContext = reader.replayContext', 'reader.accountID == captured.session.accountID',
                      'reader.scope == openedReviewScope', 'replayContext == OrderLifecycleReplayContext(context: captured)']:
            self.assertIn(check, matches)
        coordinator = self.read('Core/OrderLifecycleCoordinator.swift')
        self.assertIn('dispatcher.matchesReader(reader)', coordinator)
        self.assertIn('currentProduction()?.pending(orderID: orderID)', coordinator)
        app = self.read('App/AppSession.swift')
        self.assertIn('currentRuntimeDependencyContext.map { OrderLifecycleReplayContext(context: $0) }', app)
        self.assertIn('contextID: contextID, replayContext: replayContext', app)
    def test_real_journal_regression_cases_are_authored(self):
        source = self.read('Tests/CoreTests/OrderLifecycleProductionTests.swift')
        for name in ['testProductionUnknownLockSurvivesReloginAndUnavailableFactory',
                     'testProductionReplayOwnerSeparatesAccountMarketOriginAndNamespace',
                     'testSameOrderInDifferentDeploymentCanReserveWithoutConsumingOriginalLock',
                     'testRoleChangeCannotUnlockProductionUnknownAttempt',
                     'testProductionLateResponseKeepsCapturedOwnerLockWithoutExposingReceipt',
                     'testPaidHistoryAfterReloginPermitsOnlySeparatelyApprovedRefund',
                     'testRawPaidReadbackCannotUnlockUnknownPaymentAfterRelogin',
                     'testProductionFactoryRequiresExplicitMatchingReplayContextAndAccount']:
            self.assertIn(name, source)
        self.assertIn('let journal: OrderLifecycleFileJournal', source)
        self.assertIn('testPriorSessionReceiptIsRedactedWhileReplayLockSurvives', self.read('Tests/CoreTests/OrderLifecycleCoordinatorTests.swift'))
if __name__ == '__main__': unittest.main()
