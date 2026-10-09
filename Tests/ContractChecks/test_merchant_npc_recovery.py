"""Bounded source contracts; these do not execute Swift or Apple UI."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class MerchantNPCRecoveryContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/MerchantNPCCoordinators.swift').read_text()
        cls.app = (ROOT / 'App/MerchantNPCRecoveryPresentation.swift').read_text()
        cls.host = (ROOT / 'App/MerchantNPCViews.swift').read_text()
        cls.projection = cls.core.split('public func retryRecovery(', 1)[1].split('@discardableResult public func retry()', 1)[0]
        cls.policy = cls.app.split('@MainActor struct MerchantNPCRecoveryView:', 1)[0]

    def test_projection_is_read_only_and_does_not_replace_retry_authority(self):
        self.assertIn('guard isCurrent, grants().chatAllowed, let requestID else', self.projection)
        for token in ['attempts >= 3', 'reply?.canRetry == true || failure == .unknownOutcome', 'retryAt > now', 'ceil(seconds)']:
            self.assertIn(token, self.projection)
        for forbidden in ['requestID =', 'retryAt =', 'attempts +=', 'await ', 'run()', 'send(', 'Task']:
            self.assertNotIn(forbidden, self.projection)
        self.assertIn('attempts < 3 && (retryAt ?? .distantPast) <= Date()', self.core)

    def test_current_owner_and_authority_are_checked_at_confirmation(self):
        for token in ['expected.owner == ObjectIdentifier(coordinator)', 'expected.scope == coordinator.scope',
                      'expected.namespaceBytes.elementsEqual(coordinator.scope.namespace.utf8)', 'expected.revision == revision',
                      'let value = coordinator.retryRecovery(), value.canAbandon']:
            self.assertIn(token, self.policy)

    def test_confirmation_binds_exact_request_attempt_deadline_and_outcome(self):
        for token in ['confirmation?.id == expected.id', 'value.requestID == expected.requestID',
                      'value.attemptCount == expected.attemptCount', 'value.retryAt == expected.retryAt',
                      'value.outcomeUnknown == expected.outcomeUnknown']:
            self.assertIn(token, self.policy)
        self.assertIn('confirmation = nil\n        coordinator.abandon()', self.policy)

    def test_confirmation_is_synchronous_and_cannot_edit_or_send_draft(self):
        for forbidden in ['Task {', 'async ', 'await ', '@Binding', 'coordinator.send(', 'coordinator.retry(', 'message:', 'safeText']:
            self.assertNotIn(forbidden, self.policy)
        self.assertIn('mutating func cancel() { confirmation = nil }', self.policy)
        self.assertEqual(self.policy.count('coordinator.abandon()'), 1)

    def test_scene_and_departure_retire_confirmation_without_queued_action(self):
        for token in ['visible, active, sceneActive', 'mutating func sceneChanged(active: Bool)',
                      'mutating func disappear()', '.onDisappear', '.onChange(of: scenePhase)', '.onChange(of: revision)']:
            self.assertIn(token, self.app)
        self.assertNotIn('Task.sleep', self.app)

    def test_live_revision_is_read_in_action_not_old_view_snapshot(self):
        self.assertIn('currentRevision: { model.revision }', self.host)
        self.assertIn('revision: currentRevision(), sceneActive: scenePhase == .active', self.app)
        self.assertIn('presentation.confirm(confirmation, coordinator: coordinator, revision: currentRevision()', self.app)

    def test_countdown_uses_existing_absolute_deadline_and_stable_voiceover_value(self):
        self.assertIn('retryRecovery(at: timeline.date)', self.app)
        self.assertIn('.accessibilityElement(children: .ignore)', self.app)
        self.assertIn('.accessibilityValue(Text(deadline, format: .dateTime.hour().minute().second()))', self.app)
        self.assertNotIn('UIAccessibility.post', self.app)
        self.assertNotIn('AccessibilityFocusState', self.app)
        self.assertNotIn('withAnimation', self.app)

    def test_retry_is_explicit_and_preserves_original_composer_receipt_gate(self):
        self.assertEqual(self.app.count('retry(value.requestID)'), 1)
        self.assertIn('coordinator.requestID == value.requestID, coordinator.canRetry', self.app)
        self.assertIn('let completion = await model.coordinator.retry(requestID: capturedRequestID)', self.host)
        self.assertIn('MerchantNPCComposerRetention.shouldClear(submitted: submitted, currentDraft: text,', self.host)
        self.assertNotIn('Button("merchantNPC.abandon") { model.coordinator.abandon()', self.host)

    def test_unknown_outcome_limits_and_cancel_have_honest_local_wording(self):
        strings = json.loads((ROOT / 'Resources/MerchantNPCRecoveryLocalizations.fragment.json').read_text())
        self.assertEqual(len(strings), 8)
        for value in strings.values():
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][lang]['stringUnit']['value'])
        warning = strings['merchantNPCRecovery.abandonConsequences']['localizations']['en']['stringUnit']['value']
        for token in ['does not cancel server processing', 'delete chat records', 'typed draft stays', 'new request', 'another charge']:
            self.assertIn(token, warning)
        self.assertIn('Button("action.cancel", role: .cancel) { presentation.cancel() }', self.app)

    def test_no_new_network_media_grants_or_publication(self):
        for forbidden in ['URLSession', 'api/', 'microphone', 'pasteboard', 'audioUrl', 'publish(', 'save(', 'grants =']:
            self.assertNotIn(forbidden, self.app)

    def test_read_only_projection_distinguishes_cap_from_wait_and_unknown(self):
        for token in ['.waitingForReply', '.stoppingLocalWait', '.attemptLimitReached', '.cooldown(seconds:',
                      '.retryAvailable', 'outcomeUnknown: failure == .unknownOutcome']:
            self.assertIn(token, self.projection)

    def test_authored_regressions_cover_same_id_attempts_and_lifecycle(self):
        tests = (ROOT / 'Tests/AppUnitTests/MerchantNPCRecoveryPresentationTests.swift').read_text()
        for name in ['testExistingThreeAttemptCapAndOriginalBytesArePreserved',
                     'testSameRequestNewAttemptInvalidatesConfirmationEvenWithOldViewRevision',
                     'testInactiveSceneBlocksConfirmationBeforeLifecycleCallback',
                     'testAbandonPreservesEarlierVerifiedTranscript']:
            self.assertIn(name, tests)


if __name__ == '__main__':
    unittest.main()
