"""Static integration checks only. Swift/SwiftUI execution requires Apple CI."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path):
    return (ROOT / path).read_text()
def function(source, name):
    start = source.index('func ' + name)
    opening = source.index('{', start)
    depth = 1
    for end in range(opening + 1, len(source)):
        depth += (source[end] == '{') - (source[end] == '}')
        if depth == 0:
            return source[start:end + 1]
    raise AssertionError(name)

class ShopNPCInterruptionContracts(unittest.TestCase):
    def test_normal_authoritative_node_entry_uses_the_changed_shipping_view(self):
        play = read('App/PlayExperienceView.swift')
        host = read('App/ShopNPCSessionHost.swift')
        session = read('App/AppSession.swift')
        self.assertIn('ShopNPCNodeEntrance(name: shopNPC.name', play)
        self.assertIn('ShopNPCView(coordinator: coordinator, name: name, greeting: greeting, scriptedGuide: scriptedGuide)', host)
        self.assertIn('ShopNPCAuthenticatedHTTPTransport(configuration: configuration', session)
        for token in ['snapshot.availability == .active', '!snapshot.isLocked(node)', 'node.npc == npc', 'shopNPCSessionOwner.register(coordinator)']:
            self.assertIn(token, session)
        self.assertIn('NavigationLink("shopNPC.open") { ShopNPCOwnedDestination', read('App/ShopNPCView.swift'))

    def test_resume_transport_defaults_to_denial_without_authority(self):
        source = read('Core/ShopNPCHTTP.swift')
        fallback = source.split('public extension ShopNPCHTTPTransport {', 1)[1].split('@MainActor public struct', 1)[0]
        self.assertIn('throws { throw ShopNPCFailure.disabled }', fallback)
        self.assertIn('try transport.validateResume(scope: scope, grants: grants)', source)

    def test_shipping_resume_validation_is_synchronous_local_and_double_checks_identity(self):
        body = function(read('Core/ShopNPCAuthenticatedTransport.swift'), 'validateResume')
        for token in ['productionWritesEnabled', 'grants.textAllowed', 'captured.scope == scope', 'scope.valid', 'currentGrants() == grants', 'currentSession() == captured']:
            self.assertIn(token, body)
        for token in ['await ', 'transport.send', 'URLRequest', 'perform(', 'Task {']:
            self.assertNotIn(token, body)
        self.assertEqual(body.count('currentSession()'), 2)

    def test_foreground_revalidates_but_requires_explicit_restore_without_send(self):
        source = read('Core/ShopNPCCoordinator.swift')
        for name in ['suspend', 'revalidateSuspension', 'resumeAfterInterruption']:
            body = function(source, name)
            for forbidden in ['transmit(', 'client.text(', 'client.voice(', 'UUID()', 'active = true']:
                self.assertNotIn(forbidden, body)
        self.assertIn('guard active, isSuspended', function(source, 'revalidateSuspension'))
        self.assertIn('invalidate(); failure = reason', function(source, 'revalidateSuspension'))
        self.assertIn('guard revalidateSuspension() else { return }', function(source, 'resumeAfterInterruption'))
        view = read('App/ShopNPCView.swift')
        self.assertIn('if phase != .active { suspend() }', view)
        self.assertIn('else { coordinator.revalidateSuspension() }', view)
        self.assertIn('Button("shopNPC.resume") { coordinator.resumeAfterInterruption()', view)

    def test_stop_waiting_owns_cancellation_and_does_not_replace_original_review(self):
        source = read('Core/ShopNPCCoordinator.swift')
        body = function(source, 'stopWaiting')
        self.assertIn('guard active, busy', body)
        self.assertLess(body.index('epoch &+= 1'), body.index('transmission?.cancel()'))
        self.assertIn('failure = .unknownOutcome', body)
        for forbidden in ['pending =', 'UUID()', 'messages =']:
            self.assertNotIn(forbidden, body)
        self.assertIn('private var transmission: Task<ShopNPCReply, Error>?', source)
        self.assertIn('onCancel: { task.cancel() }', source)

    def test_late_completion_cannot_clear_or_publish_over_a_new_request(self):
        body = function(read('Core/ShopNPCCoordinator.swift'), 'transmit(reviewID: UUID, intent:')
        guard = 'guard active, !isSuspended, epoch == stamp, scope == review.scope else { return }'
        self.assertEqual(body.count(guard), 2)
        self.assertLess(body.index(guard), body.index('transmission = nil; busy = false; pending = nil'))
        self.assertIn('guard !task.isCancelled else { throw CancellationError() }', body)
        self.assertIn('requestID: review.id, scope: review.scope', body)
        self.assertIn('now().timeIntervalSince(lastSend) < 1', body)

    def test_scope_revocation_and_destination_exit_remain_terminal(self):
        source = read('Core/ShopNPCCoordinator.swift')
        body = function(source, 'invalidate')
        for token in ['transmission?.cancel()', 'active = false', 'isSuspended = false', 'pending = nil', 'messages = []']:
            self.assertIn(token, body)
        self.assertIn('.onDisappear { invalidate() }', read('App/ShopNPCView.swift'))
        host = read('App/ShopNPCSessionHost.swift')
        self.assertIn('.onDisappear { scriptedGuide?.retire(); scriptedGuide = nil; coordinator?.invalidate() }', host)
        self.assertIn('coordinator?.invalidate()', host)
        self.assertIn('scriptedGuide?.retire(); scriptedGuide = nil', host)
        self.assertIn('conversations.forEach { $0.value?.invalidate() }', read('App/ShopNPCSessionHost.swift'))

    def test_suspension_hides_transcript_review_and_draft_and_cancels_recording(self):
        view = read('App/ShopNPCView.swift')
        self.assertIn('showsConversation: Bool { coordinator.active && !coordinator.isSuspended }', view)
        self.assertIn('if showsConversation {\n', view)
        self.assertIn('Binding(get: { showsConversation ? draft : "" }', view)
        self.assertIn('if !coordinator.isSuspended, let error', view)
        self.assertIn('capture?.cancel()', function(view, 'suspend'))
        self.assertIn('.disabled(scenePhase != .active)', view)
        self.assertIn('private var sending: Bool { coordinator.busy }', view)
        self.assertNotIn('@State private var sending', view)

    def test_pending_request_cannot_be_overwritten_or_discarded_while_sending(self):
        source = read('Core/ShopNPCCoordinator.swift')
        for name in ['reviewText', 'reviewVoice', 'reviewRegeneration']:
            self.assertIn('guard pending == nil else { throw ShopNPCFailure.busy }', function(source, name))
        self.assertIn('guard active, !isSuspended, !busy', function(source, 'cancelReview'))
        self.assertIn('guard active, !isSuspended, scope.valid', function(source, 'check'))

    def test_no_new_provider_permission_persistence_or_merchant_identity_path(self):
        paths = ['Core/ShopNPCCoordinator.swift', 'Core/ShopNPCHTTP.swift', 'Core/ShopNPCAuthenticatedTransport.swift', 'App/ShopNPCView.swift']
        source = '\n'.join(read(path) for path in paths)
        for forbidden in ['UserDefaults', 'FileManager', 'requestRecordPermission', 'requestAuthorization', 'MerchantNPC', 'bizId', 'merchantId', 'URLSession.shared']:
            self.assertNotIn(forbidden, source)
        contracts = read('Core/ShopNPCContracts.swift')
        for grant in ['server', 'provider', 'legal', 'access', 'voiceTransmission', 'voiceFormatVerified', 'microphone', 'playback']:
            self.assertIn('var ' + grant + ' = false', contracts)
        for token in ['grants.voiceAllowed', 'grants.microphone', 'startAfterExplicitMicrophoneIntent']:
            self.assertIn(token, read('App/ShopNPCView.swift'))

    def test_queued_send_intent_is_captured_before_task_and_consumed_after_epoch_check(self):
        view = read('App/ShopNPCView.swift')
        capture = view.index('let intent = try coordinator.prepareTransmission(reviewID: review.id)')
        queued = view.index('Task {', capture)
        self.assertLess(capture, queued)
        self.assertIn('guard scenePhase == .active, showsConversation, coordinator.scope == review.scope', view[queued:])
        self.assertIn('await coordinator.transmit(reviewID: review.id, intent: intent)', view[queued:])
        source = read('Core/ShopNPCCoordinator.swift')
        body = function(source, 'transmit(reviewID: UUID, intent:')
        self.assertIn('transmissionIntent == intent, intent.generation == epoch, intent.reviewID == reviewID', body)
        self.assertLess(body.index('transmissionIntent = nil'), body.index('Task<ShopNPCReply, Error>'))
        for name in ['suspend', 'invalidate', 'cancelReview']:
            self.assertIn('transmissionIntent = nil', function(source, name))
        self.assertIn('epoch &+= 1', function(source, 'suspend'))

    def test_six_additive_bilingual_keys_are_complete_before_parent_catalog_merge(self):
        fragment = json.loads(read('Resources/ShopNPCInterruptionLocalizations.fragment.json'))['strings']
        self.assertEqual(set(fragment), {'shopNPC.paused', 'shopNPC.pauseNotice', 'shopNPC.resume', 'shopNPC.stopWaiting', 'shopNPC.retry', 'shopNPC.retryNotice'})
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        for key, entry in fragment.items():
            if key in catalog:
                self.assertEqual(catalog[key], entry)
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])
            self.assertIn('"' + key + '"', read('App/ShopNPCView.swift'))
        self.assertIn('may have received', fragment['shopNPC.retryNotice']['localizations']['en']['stringUnit']['value'])

    def test_http_wait_helper_fails_within_a_bounded_deadline(self):
        source = read('Tests/CoreTests/ShopNPCInterruptionTests.swift')
        helper = function(source, 'waitFor')
        for token in ['async throws', 'ContinuousClock()', '.seconds(2)', 'clock.now < deadline', 'throw WaitFailure.requestNotDispatched(index)', 'try await Task.sleep']:
            self.assertIn(token, helper)
        self.assertNotIn('Task.yield()', helper)
        self.assertNotRegex(source, r'(?<!try )await h\.http\.waitFor')

    def test_behavior_regressions_use_shipping_adapter_without_real_network(self):
        tests = read('Tests/CoreTests/ShopNPCInterruptionTests.swift')
        self.assertEqual(tests.count('func test'), 21)
        self.assertIn('ShopNPCAuthenticatedHTTPTransport(', tests)
        self.assertIn('CheckedContinuation<(Data, Int), Never>', tests)
        for name in ['testStopWaitingPreservesOriginalIDAndLateReplyCannotReplaceRetry', 'testAccountRoleNodeRunAndRevisionChangesPermanentlyInvalidate', 'testVoiceGrantRevocationWhileSuspendedPreventsResumeAndUpload', 'testInterruptedRegenerationPreservesOriginalAnswerAndReplacesItOnlyOnce']:
            self.assertIn(name, tests)
        self.assertNotIn('URLSession', tests)

if __name__ == '__main__':
    unittest.main()
