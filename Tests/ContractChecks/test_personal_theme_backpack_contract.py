"""Source-contract checks, not Swift compilation or runtime/App verification."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
A = (ROOT / 'Core/PlayThemeBackpackActions.swift').read_text()
S = (ROOT / 'Core/PlayThemeBackpackRecovery.swift').read_text()
V = (ROOT / 'App/PlayThemeBackpackView.swift').read_text()
C = (ROOT / 'Core/PlayThemeBackpack.swift').read_text()
D = (ROOT / 'Core/PlayThemeBackpackDispatch.swift').read_text()

class PersonalThemeBackpackSourceTests(unittest.TestCase):
    def test_only_three_personal_operations(self):
        enum = A.split('public enum PlayThemeBackpackOperation', 1)[1].split('}', 1)[0]
        self.assertEqual(re.findall(r'"([A-Z_]+)"', enum), ['USE', 'DISCARD', 'RECEIVE'])
    def test_dedicated_acceptance_defaults_closed(self):
        self.assertIn('accepted: Bool = false', A)
        self.assertIn('completedReceiveAccepted: Bool = false', A)
        self.assertNotIn('capability: .reads', A)
    def test_exact_original_body_is_persisted_and_sent(self):
        self.assertIn('public let body: Data', A)
        self.assertIn('body == (try command.encodedBody())', A)
        self.assertIn('request.httpBody = intent.body', A)
        self.assertIn('encoder.outputFormatting = [.sortedKeys]', A)
    def test_utf8_identity_and_java_content_bound(self):
        self.assertIn('contentId.utf16.count <= 96', A)
        self.assertIn('utf8.elementsEqual(contentID.utf8)', A)
        self.assertIn('Data(owner.namespace.utf8).base64EncodedString()', A)
    def test_personal_scope_and_activity_are_verified(self):
        self.assertIn('raw["scope"] == .null || raw["scope"].text == "PERSONAL"', A)
        self.assertIn('guard id == activity', A)
        self.assertIn('guard id == topicID, activity == 0', A)
    def test_read_preserves_explicit_original_run(self):
        self.assertIn('fields["sessionId"] = String(sessionID)', A)
        self.assertIn('fields["activityId"] = "0"', A)
        self.assertIn('let originalID = stored?.value.intent.command.sessionId', A)
    def test_review_does_not_dispatch(self):
        begin = A.split('public func begin(', 1)[1].split('public func cancelReview', 1)[0]
        self.assertNotIn('service.write', begin)
        self.assertNotIn('recovery.prepare', begin)
    def test_prepare_precedes_dispatch(self):
        confirm = A.split('public func confirm()', 1)[1].split('public func recover()', 1)[0]
        self.assertLess(confirm.index('recovery.prepare(intent)'), confirm.index('dispatch(stored'))
    def test_exact_snapshot_rechecked_before_transport(self):
        writer = A.split('@MainActor func write(', 1)[1].split('private func request', 1)[0]
        self.assertIn('snapshot.value.state == .dispatching', writer)
        self.assertIn('snapshot.value.dispatchProcess == recovery.processID', writer)
        self.assertIn('try await recovery.read() == snapshot', writer)
        self.assertGreaterEqual(writer.count('try checkOwner()'), 2)
    def test_os_provenance_required_for_network(self):
        self.assertIn('transport is PlayRecoveryRecordingTransport || recovery.permitsSystemDispatch(to: configuration.baseURL)', A)
        self.assertIn('transport is PlayRecoveryRecordingTransport || lifetime != nil', A)
        self.assertIn('private struct SystemSeal', S)
        self.assertIn('systemSeal = nil', S)
    def test_get_cannot_acknowledge_original_write(self):
        refresh = A.split('public func refresh()', 1)[1].split('public func begin(', 1)[0]
        self.assertNotIn('to: .acknowledged', refresh)
        self.assertNotIn('service.write', refresh)
    def test_unknown_replay_never_remints_or_rebuilds(self):
        retry = A.split('public func recover()', 1)[1].split('private func dispatch', 1)[0]
        self.assertNotIn('UUID()', retry)
        self.assertNotIn('PlayThemeBackpackCommand(', retry)
        self.assertIn('dispatch(stored, stamp: stamp)', retry)
    def test_active_same_process_cannot_replay(self):
        self.assertIn('stored.value.dispatchProcess != recovery.processID', A)
        self.assertIn('value.dispatchProcess != processID', S)
    def test_only_original_post_receipt_acknowledges(self):
        dispatch = A.split('private func dispatch(', 1)[1].split('private func finishAcknowledged', 1)[0]
        self.assertLess(dispatch.index('service.write('), dispatch.index('to: .acknowledged'))
        self.assertIn('next.version == command.expectedVersion + 1', dispatch)
        self.assertIn('facts.version == intent.command.expectedVersion + 1', S)
    def test_errors_preserve_unknown_and_clear_only_ack(self):
        self.assertIn('to: .unknown', A)
        clear = S.split('public func clear(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('snapshot.value.state == .acknowledged', clear)
        self.assertNotIn('clear(', A.split('private func fail(', 1)[1].split('public func refresh', 1)[0])
    def test_storage_owner_and_scope_are_fixed(self):
        self.assertIn('intent.owner == owner, intent.scope == scope, intent.topicID == topicID', S)
        self.assertIn('intent.storageKey.utf8.elementsEqual(key.utf8)', S)
        self.assertIn('PlayThemeBackpackRecovery-v1', S)
        self.assertNotIn('PlayRecovery-v1"', S)
    def test_late_callbacks_and_suspension_are_fenced(self):
        self.assertIn('current() == captured', A)
        self.assertIn('generation == stamp', A)
        self.assertIn('visible = false; generation &+= 1; review = nil; facts = nil', A)
        self.assertIn('model.actions?.suspend()', V)
    def test_fresh_read_cannot_regress_successful_receipt(self):
        self.assertIn('old.version > value.version { throw PlayExperienceError.malformed }', A)
        self.assertIn('try acceptFresh', A)
    def test_reserved_items_and_capacity_are_gated(self):
        self.assertIn('guard !hasReservedSupplies else { return false }', A)
        self.assertIn('hasPending && hasRoomForPending(contentID)', A)
        self.assertIn('addingReportingOverflow', A)
        self.assertIn('multipliedReportingOverflow', A)
    def test_completed_receive_is_not_default_enabled(self):
        self.assertIn('completedReceiveAccepted && !hasReservedSupplies', A)
        self.assertIn('playx.backpack.action.completedUnavailable', V)
    def test_native_review_is_required_before_confirm(self):
        self.assertIn('.sheet(item: $selection', V)
        self.assertIn('Form {', V)
        self.assertIn('reviewIsCurrent(choice, actions: actions)', V)
        self.assertLess(V.index('try actions.begin('), V.index('await actions.confirm()'))
        self.assertNotIn('model.actions?.cancelReview()', V)  # Dismiss cannot race a confirmed dispatch.
    def test_ui_has_use_discard_receive_and_original_recovery(self):
        for name in ['use', 'discard', 'receive']:
            self.assertIn('playx.backpack.' + name + '.', V)
        for name in ['unknown', 'active', 'recover', 'storageUnavailable', 'reviewStale']:
            self.assertIn('playx.backpack.action.' + name, V)
    def test_old_readonly_fixture_path_remains_source_compatible(self):
        self.assertIn('actions: PlayThemeBackpackActions? = nil', C)
        self.assertIn('guard let reader, phase != .loading else { return }', C)
        self.assertIn('try PlayThemeBackpack(await reader.state())', C)
    def test_production_dispatch_uses_only_dedicated_transport(self):
        self.assertIn('transport as? any PlayThemeBackpackTransport', A)
        self.assertIn('sendThemeBackpackRead(request, session: session, scope: scope, topicID: topicID)', A)
        self.assertIn('sendThemeBackpackWrite(request, permit: permit)', A)
        self.assertEqual(A.count('try await transport.send(request)'), 2)
        self.assertEqual(A.count('if transport is PlayRecoveryRecordingTransport { reply = try await transport.send(request) }'), 2)
    def test_permit_cannot_be_publicly_constructed_or_consumed_twice(self):
        self.assertNotIn('public init(', D)
        self.assertIn('guard !consumed else', D)
        self.assertLess(D.index('consumed = true'), D.index('try await recovery.read()'))
        self.assertIn('try await recovery.read() == snapshot', D)
        self.assertIn('snapshot.value.dispatchProcess == recovery.processID', D)
    def test_permit_validates_exact_body_and_endpoint(self):
        self.assertIn('request.httpBody == intent.body', D)
        self.assertIn('request.httpBodyStream == nil', D)
        self.assertIn('parts.query == nil, parts.fragment == nil', D)
        self.assertIn('recovery.permitsSystemDispatch(to: baseURL)', D)
        self.assertIn('intent.owner.matches(session)', D)
    def test_read_route_is_canonical_and_scope_bound(self):
        self.assertIn('Set(items.map(\.name)).count == items.count', D)
        self.assertIn('fields["topicId"] == String(topicID)', D)
        self.assertIn('fields["activityId"] == String(activityID)', D)
        self.assertIn('expected.absoluteString.utf8.elementsEqual(url.absoluteString.utf8)', D)
    def test_completed_replay_keeps_its_independent_acceptance_requirement(self):
        self.assertIn('public let requiresCompletedReceive: Bool', A)
        self.assertIn('!intent.requiresCompletedReceive || completedReceiveAccepted', A)
        self.assertIn('requiresCompletedReceive: facts.status == "COMPLETED"', A)
        self.assertIn('requiresCompletedReceive = snapshot.value.intent.requiresCompletedReceive', D)
    def test_parent_result_callback_is_not_fired_by_an_unconfirmed_get(self):
        self.assertEqual(A.count('notificationPending = true'), 1)
        finish = A.split('private func finishAcknowledged', 1)[1]
        self.assertIn('notificationPending = true', finish)
        self.assertIn('await onConfirmed()', A)

if __name__ == '__main__':
    unittest.main(verbosity=2)
