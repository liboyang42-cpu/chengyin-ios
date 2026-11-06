#!/usr/bin/env python3
"""Personal-share source/wire/parser checks; never a Swift typecheck or Apple runtime result."""
from pathlib import Path
import argparse, importlib.metadata, json, re, sys, unittest
from personal_location_share_source_contracts import shutdown_operations, rendered_catalog

ROOT = Path(__file__).resolve().parents[1]

class SourceChecks(unittest.TestCase):
    def read(self, relative): return (ROOT / relative).read_text()
    def test_default_capabilities_are_nil(self):
        host = self.read('App/PersonalLocationShareHost.swift')
        http = self.read('Core/PersonalLocationShareHTTPService.swift')
        app = self.read('App/AppSession.swift')
        for kind in ['Read', 'Write']:
            self.assertIn(f'personalLocationShare{kind}Approval: PersonalLocationShareEndpointApproval? = nil', app)
        self.assertIn('personalLocationShareCaptureApproval: PersonalLocationShareCaptureApproval? = nil', app)
        for source in [host, http]:
            self.assertIn('readApproval: @escaping () -> PersonalLocationShareEndpointApproval? = { nil }', source)
            self.assertIn('writeApproval: @escaping () -> PersonalLocationShareEndpointApproval? = { nil }', source)
        self.assertIn('captureApproval: @escaping () -> PersonalLocationShareCaptureApproval? = { nil }', host)
    def test_read_approval_precedes_transport_and_response_is_rechecked(self):
        s = self.read('Core/PersonalLocationShareHTTPService.swift')
        self.assertLess(s.index('let credential = try check(operation)'), s.index('transport.data(for: request)'))
        self.assertGreater(s.index('guard try check(operation) == credential'), s.index('transport.data(for: request)'))
        self.assertIn('guard !synthetic else', s)
        self.assertIn('completionHandler(nil)', s)
        self.assertIn('config.urlCache = nil', s)
        self.assertIn('request.setValue(credential, forHTTPHeaderField: "Authorization")', s)
    def test_journal_whitelist_and_original_key_order(self):
        journal = self.read('Core/PersonalLocationSharePendingJournal.swift')
        record = journal.split('public struct PersonalLocationSharePendingRecord')[1].split('public init')[0]
        fields = re.findall(r'public (?:let|var) (\w+):', record)
        self.assertEqual(set(fields), {'id','namespace','accountId','request','choicesDigest','serverRequestHash','stopRequested'})
        for term in ['latitude:', 'longitude:', 'token:', 'observation:']: self.assertNotIn(term, record)
        self.assertIn('.atomic', journal); self.assertIn('isExcludedFromBackup = true', journal)
        s = self.read('Core/PersonalLocationShareCoordinator.swift')
        start = s.split('public func confirmStart(')[1].split('public func restoreOriginalRequests()')[0]
        self.assertLess(start.index('try journal.put'), start.index('service.create'))
        stop = s.split('public func stop(requestKey:')[1].split('private func persistStop')[0]
        self.assertLess(stop.index('stopLocalPublisher()'), stop.index('persistStop('))
        self.assertLess(stop.index('persistStop('), stop.index('retryStop('))
        restore = s.split('public func restoreOriginalRequests()')[1].split('public func readback(')[0]
        self.assertNotIn('service.create', restore); self.assertNotIn('startPublisher', restore)
    def test_policy_has_no_seed_or_distance_fallback(self):
        s = self.read('Core/PersonalLocationSharePolicy.swift')
        self.assertIn('guard !requiresRecipientAcceptance', s)
        self.assertNotRegex(s, r'(?:refreshAfterMs|staleAfterMs|ownerLeaseMs|displayLeaseMs): Int64\s*=')
        mode = self.read('Core/PersonalLocationShareContracts.swift').split('public enum PersonalLocationShareMode')[1].split('public enum PersonalLocationShareStatus')[0]
        self.assertNotIn('DISTANCE_ONLY', mode)
    def test_receiver_and_lifecycle_are_fail_closed(self):
        receiver = self.read('Core/PersonalLocationShareReceiverProjection.swift')
        for marker in ['ticket.generation == generation', 'ticket.serial == serial', 'tombstones[grant.grantId] == nil', 'grant.recipientId == recipientId', 'visible = replacement', 'batch.resetRequired', 'observation.matches(grant', 'deadlineUptime']:
            self.assertIn(marker, receiver)
        c = self.read('Core/PersonalLocationShareCoordinator.swift')
        self.assertIn('let requestStarted = uptime()', c)
        self.assertIn('ticket: ticket, uptime: requestStarted', c)
        self.assertIn('receiver.expire(at: clockUptime)', c)
        self.assertIn('self.ownerDeadline = min(expiry, sendStarted', c)
        self.assertIn('stopLocalPublisher(); cancelReceiver(); receiver.clear()', c)
    def test_normal_entry_is_not_fixture_only(self):
        app = self.read('App/QuestifyApp.swift').split('struct SessionRootView')[1]
        self.assertIn('.environment(\\.personalLocationShareHost, session.personalLocationShareHost)', app)
        self.assertIn('session.personalLocationShareHost.sceneChanged(phase)', app)
        self.assertIn('PersonalLocationShareEntry(recipientId: nil)', self.read('App/AccountView.swift'))
        self.assertIn('PersonalLocationShareEntry(recipientId: Int64(memberID))', self.read('App/SocialPublicProfileView.swift'))
        session = self.read('App/AppSession.swift')
        self.assertGreaterEqual(session.count('invalidatePersonalLocationShare()'), 4)
        self.assertIn('retainedPersonalLocationShareHost?.prepareLogout()', session)
        self.assertNotIn('await retainedPersonalLocationShareHost?.prepareLogout()', session)
        host = self.read('App/PersonalLocationShareHost.swift')
        shutdown = host.split('func prepareLogout()')[1].split('func sceneChanged')[0]
        self.assertNotRegex(shutdown, r'(?m)^\s*(?:let \w+ = )?await ')
        self.assertIn('retained?.suspend(foreground: false', shutdown)
        view = self.read('App/PersonalLocationShareView.swift')
        self.assertNotRegex(view, r'Button[^\n]*\{\s*\}')
        for action in ['confirmStart(ticket:', 'readback(', 'stop(', 'retryStop(', 'refreshReceived()', 'openManagement()', 'restoreOriginalRequests()']:
            self.assertIn('coordinator.' + action, view)
    def test_core_location_is_isolated_and_never_expands_to_background(self):
        for f in [*ROOT.glob('Core/PersonalLocationShare*.swift'), *ROOT.glob('App/PersonalLocationShare*.swift')]:
            s = f.read_text()
            for forbidden in ['requestAlwaysAuthorization', 'requestTemporaryFullAccuracyAuthorization', 'allowsBackgroundLocationUpdates = true', 'nearby-runners', 'presence-visibility', 'fairness', 'Gemini']:
                self.assertNotIn(forbidden, s, str(f))
            if f.name != 'PersonalLocationShareHost.swift':
                self.assertNotIn('CLLocationManager()', s, str(f))
                self.assertNotIn('requestWhenInUseAuthorization()', s, str(f))
    def test_real_driver_is_grant_bound_and_first_prompt_is_explicit(self):
        host = self.read('App/PersonalLocationShareHost.swift')
        self.assertEqual(host.count('CLLocationManager()'), 1)
        self.assertEqual(host.count('requestWhenInUseAuthorization()'), 1)
        self.assertIn('manager.startUpdatingLocation()', host)
        self.assertIn('manager.stopUpdatingLocation(); manager.delegate = nil', shutdown_operations(host))
        self.assertNotRegex(host, r'manager\.location\b|(?:desiredAccuracy|distanceFilter)\s*=')
        self.assertIn('guard allowsFirstPermissionRequest', host)
        self.assertIn('allowsFirstPermissionRequest: binding.allowsFirstPermissionRequest', host)
        self.assertIn('requiresFullAccuracy: binding.grant.mode == .exact', host)
        self.assertIn('confirmationPurpose(scope: binding.scope) == binding.capturePurpose', host)
        self.assertIn('case .denied, .restricted:', host)
        self.assertIn('guard acquisitionId == id', host)
        self.assertIn('value.timestamp >= started', host)
        self.assertIn('value.sourceInformation?.isSimulatedBySoftware != true', host)
        self.assertIn('driver.accuracy == .fullAccuracy', host)
        self.assertIn('installedUsageDescription:', host)
        c = self.read('Core/PersonalLocationShareCoordinator.swift')
        self.assertIn('try providerFactory.make(binding: binding', c)
        self.assertIn('self.publishingGrantId == grant.grantId', c)
        self.assertIn('sample.systemAccuracy == .full', c)
        self.assertIn('provider?.stop(); provider = nil', c)
        view = self.read('App/PersonalLocationShareView.swift')
        self.assertIn('ticket.allowsFirstPermissionRequest', view)
        _, rendered_text = rendered_catalog(view, c, host, json.loads(self.read('Resources/PersonalLocationShare.xcstrings')))
        self.assertIn('设备最新位置会上传服务端', rendered_text)
        self.assertIn('服务端投影', rendered_text)
    def test_confirmation_ticket_is_frozen_bound_and_synchronously_consumed(self):
        c = self.read('Core/PersonalLocationShareCoordinator.swift'); v = self.read('App/PersonalLocationShareView.swift')
        ticket = c.split('public struct PersonalLocationShareConfirmationTicket')[1].split('@MainActor')[0]
        self.assertNotIn('public var ', ticket); self.assertIn('fileprivate init', ticket)
        for field in ['scope','presentationId','generation','contextRevision','choiceRevision','recipientId','policy','mode','duration','disclosures','capturePurpose','allowsFirstPermissionRequest','localDeadlineUptime']:
            self.assertIn('public let '+field+':', ticket)
        for guard in ['displayedRecipientId == recipientId', 'ticket.choiceRevision == confirmationRevision', 'context?.policy == ticket.policy', 'guard matchesConfirmation(ticket) else']:
            self.assertIn(guard, c)
        consume = c.split('public func confirmStart(ticket:')[1].split('private func startConfirmed')[0]
        self.assertNotIn(' async ', consume); self.assertIn('issuedConfirmation = nil;', consume)
        self.assertIn('displayedRecipientId: recipientId', v)
        self.assertIn('coordinator.recipientId != recipientId', v)
        self.assertIn('confirmationEntryDisappeared(presentationId:', v)
        self.assertNotIn('Task { await coordinator.confirmStart', v)
    def test_confirmed_seconds_and_server_span_bound_local_deadline(self):
        c = self.read('Core/PersonalLocationShareCoordinator.swift')
        for guard in ['grant.expiresAtMs - grant.createdAtMs <= seconds * 1000', 'ticket.policy.durationChoices.contains(ticket.duration)', 'min(ticket.localDeadlineUptime, serverDeadline, selectedDeadline)', 'Self.confirmedDeadline(grant:', 'grantExpiryUptime = expiry', 'if Int64(delta) > seconds']:
            self.assertIn(guard, c)
        start = c.split('private func startPublisher')[1].split('private func publishOne')[0]
        self.assertLess(start.index('Self.confirmedDeadline'), start.index('providerFactory.make'))
    def test_auth_status_is_terminal_only_for_its_identity_and_lease(self):
        h = self.read('Core/PersonalLocationShareHTTPService.swift'); host = self.read('App/PersonalLocationShareHost.swift')
        fence = h.split('private func validateResponseLease')[1].split('private static func machineError')[0]
        for guard in ['isCurrentService()', 'current() == scope', 'token() == credential', 'authorizationGeneration() == generation']:
            self.assertIn(guard, fence)
        result = h.split('let result: (Data, HTTPURLResponse)')[1].split('private func validateResponseLease')[0]
        self.assertEqual(result.count('try validateResponseLease(credential: credential, generation: requestGeneration)'), 2)
        self.assertLess(result.index('try validateResponseLease'), result.index('throw error'))
        self.assertLess(result.rindex('try validateResponseLease'), result.index('try Task.checkCancellation()'))
        self.assertIn('onAuthorizationFailure(failure)', result)
        self.assertIn('let envelope = try? JSONDecoder().decode(ErrorEnvelope.self', h)
        self.assertIn('retainedServiceLease == serviceLease', host)
        self.assertIn('retained = nil; retainedServiceLease = nil;', host)
        c = self.read('Core/PersonalLocationShareCoordinator.swift')
        self.assertGreaterEqual(c.count('handleAuthorizationFailure(error)'), 10)
        self.assertIn('authorizationGeneration &+= 1', c)
        self.assertIn('if failure == .retiredResponse { return true }', c)
        self.assertIn('suspend(foreground: false, connected: false); authorizationBlocked = true', c)
    def test_replaced_receiver_tasks_cannot_mutate_new_read_even_on_error(self):
        c = self.read('Core/PersonalLocationShareCoordinator.swift')
        refresh = c.split('public func refreshReceived()')[1].split('private func scheduleReceiver()')[0]
        poll = c.split('private func scheduleReceiver()')[1].split('private func scheduleLeaseExpiry()')[0]
        for section in [refresh, poll]:
            self.assertIn('receiverReadRevision &+= 1', section)
            self.assertGreaterEqual(section.count('receiverReadRevision == readRevision'), 2)
            self.assertIn('receiverReadRevision == readRevision', section.split('} catch {')[-1])
        self.assertIn('private func cancelReceiver() { receiverReadRevision &+= 1;', c)
    def test_purpose_strings_are_consistent_without_background_keys(self):
        strings = json.loads(self.read('Resources/InfoPlist.xcstrings'))['strings']
        en = strings['NSLocationWhenInUseUsageDescription']['localizations']['en']['stringUnit']['value']
        self.assertIn('personal location sharing', en)
        self.assertNotIn('not shared with other people', en)
        self.assertIn('INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = ' + en, self.read('Config/Base.xcconfig'))
        self.assertNotIn('NSLocationAlwaysUsageDescription', strings)
        self.assertNotIn('NSLocationAlwaysAndWhenInUseUsageDescription', strings)
    def test_localization_resource_is_valid_and_used(self):
        data = json.loads(self.read('Resources/PersonalLocationShare.xcstrings'))
        view = self.read('App/PersonalLocationShareView.swift')
        rendered_keys, _ = rendered_catalog(view, self.read('Core/PersonalLocationShareCoordinator.swift'),
            self.read('App/PersonalLocationShareHost.swift'), data)
        for key in data['strings']: self.assertIn(key, rendered_keys)

# A tiny, explicitly synthetic protocol model. It tests adversarial event order, not the Swift implementation.
class SyntheticProtocolChecks(unittest.TestCase):
    def test_stop_before_create_tombstone_is_terminal(self):
        server = {}; key = 'original-key'; server[key] = 'STOPPED'
        server.setdefault(key, 'ACTIVE')
        self.assertEqual(server[key], 'STOPPED')
    def test_unknown_does_not_authorize_new_key(self):
        journal = {'original-key': {'stop': False}}; outcome = None
        self.assertIsNone(outcome); self.assertEqual(list(journal), ['original-key'])
        journal['original-key']['stop'] = True
        self.assertEqual(list(journal), ['original-key'])
    def test_delayed_response_cannot_extend_monotonic_lease(self):
        request_start, response_arrival, server_remaining = 100, 150, 40
        deadline = request_start + server_remaining
        self.assertLessEqual(deadline, response_arrival)
    def test_invalidation_beats_late_snapshot(self):
        tombstones = {'grant': 8}; snapshot = {'grant': {'watermark': 7}}
        visible = {key: value for key, value in snapshot.items() if key not in tombstones}
        self.assertEqual(visible, {})

    def test_old_dialog_never_consumes_replacement_context(self):
        frozen = ('owner-A', 1, 'recipient-2', 'EXACT', 'duration-id', 120, 'policy-digest', 3, 7, 'purpose-A', False)
        def accepts(ticket, current, issued): return ticket == current and ticket == issued
        self.assertTrue(accepts(frozen, frozen, frozen))
        for index, replacement in enumerate(['owner-B', 2, 'recipient-3', 'COARSE', 'new-duration-id', 600, 'new-policy', 4, 8, 'purpose-B', True]):
            new = list(frozen); new[index] = replacement
            self.assertFalse(accepts(frozen, tuple(new), tuple(new)))
        self.assertFalse(accepts(frozen, frozen, None))  # Cancelled, disappeared, or already consumed.
    def test_context_changes_during_create_keep_original_key_but_never_start(self):
        journal = {'original': {'stop': False}}; ticket_revision, current_revision = 7, 8
        starts = 0
        if ticket_revision != current_revision: journal['original']['stop'] = True
        else: starts += 1
        self.assertEqual(starts, 0); self.assertEqual(journal, {'original': {'stop': True}})
    def test_duration_id_does_not_authorize_longer_numeric_span(self):
        selected_seconds, created = 120, 1000
        self.assertFalse((created + 3_600_000) - created <= selected_seconds * 1000)
        opened, request_start, arrival = 100, 110, 150
        deadline = min(opened + selected_seconds, request_start + selected_seconds, request_start + 30)
        self.assertEqual(deadline, 140); self.assertLess(deadline, arrival)
    def test_bad_json_auth_status_still_retires_only_current_identity(self):
        current = ('owner-B', 2, 'token-B', 'instance-B', 9)
        def should_retire(status, request_identity, current_identity):
            return status in (401, 403) and request_identity == current_identity
        for status in [401, 403]:
            for body in [b'bad json', b'{"code":401,"errorCode":"SESSION_INVALID"}']:
                self.assertTrue(should_retire(status, current, current))
                for index, old in enumerate(['owner-A', 1, 'token-A', 'instance-A', 8]):
                    request = list(current); request[index] = old
                    self.assertFalse(should_retire(status, tuple(request), current))
    def test_stop_a_start_b_retires_old_auth_without_touching_b(self):
        source = {'generation': 4, 'running': 'A', 'receiver': 'A'}
        request_generation = source['generation']
        source.update(generation=5, running=None, receiver=None)  # Synchronous stop A.
        source.update(generation=6, running='B', receiver='B')
        if request_generation == source['generation']: source.update(running=None, receiver=None)
        self.assertEqual(source['running'], 'B'); self.assertEqual(source['receiver'], 'B')
    def test_service_unavailable_or_bad_json_never_changes_unknown_create_key(self):
        for status, body in [(503, b'{"code":503,"errorCode":"POLICY_UNAVAILABLE"}'), (503, b'bad'), (200, b'bad')]:
            pending = {'original': 'unknown'}; posts = 1
            may_create = not pending
            if may_create: posts += 1
            self.assertEqual(posts, 1); self.assertEqual(list(pending), ['original'])

    def test_retired_success_and_503_are_identified_before_task_cancellation(self):
        def outcome(request_revision, current_revision, cancelled, status):
            if request_revision != current_revision: return 'retired'
            if status in (401, 403): return 'auth-terminal'
            if cancelled: return 'cancelled'
            return 'response'
        for status in [200, 401, 403, 503]:
            self.assertEqual(outcome(1, 3, True, status), 'retired')
        self.assertEqual(outcome(3, 3, True, 401), 'auth-terminal')
    def test_transport_throw_still_crosses_retired_request_fence(self):
        for error in ['cancellation', 'network-lost']:
            old_revision, new_revision = 1, 3
            forwarded = 'retired' if old_revision != new_revision else error
            self.assertEqual(forwarded, 'retired')
    def test_same_publication_lease_replacement_read_protects_receiver_from_old_error(self):
        publication_revision = 1; old_read, new_read = 4, 5
        for failure in ['cancelled', 'network-lost', 'policy-503']:
            receiver = {'visible': 'B', 'poll': 'B', 'publisher': 'same-lease'}
            if old_read == new_read:
                receiver.update(visible=None, poll=None)
                if failure == 'policy-503': receiver['publisher'] = None
            self.assertEqual(receiver, {'visible': 'B', 'poll': 'B', 'publisher': 'same-lease'})
            self.assertEqual(publication_revision, 1)

def check_wire(backend: Path):
    java = (backend / 'chengyinhub-system/src/main/java/com/chengyinhub/business/locationshare/PersonalLocationShareContracts.java').read_text()
    swift = (ROOT / 'Core/PersonalLocationShareContracts.swift').read_text()
    names = {'Context':'PersonalLocationShareContext','Create':'PersonalLocationShareCreate','Grant':'PersonalLocationShareGrant',
             'Receipt':'PersonalLocationShareReceipt','Owned':'PersonalLocationShareOwned','Sample':'PersonalLocationSharePublish',
             'Published':'PersonalLocationSharePublished','Observation':'PersonalLocationShareObservation',
             'Snapshot':'PersonalLocationShareSnapshot','EventBatch':'PersonalLocationShareEventBatch'}
    for j, sw in names.items():
        match = re.search(r'public record '+j+r'\((.*?)\) \{', java, re.S)
        if not match: raise AssertionError(f'Java record missing: {j}')
        jf = set(re.findall(r'\b(\w+)\s*(?:,|$)', match.group(1)))
        start = swift.index('public struct '+sw+':')
        end = swift.find('\npublic ', start+1); section = swift[start:end if end >= 0 else None]
        # Nested snapshot Entry and event fields are separately matched below.
        if j == 'Snapshot': section = section[section.index('    public let recipientId:'):]
        if j == 'EventBatch': section = section[section.index('    public let recipientId:'):]
        sf = set(re.findall(r'^    public let (\w+):', section, re.M))
        if jf != sf: raise AssertionError(f'{j} fields differ: Java={sorted(jf)}, Swift={sorted(sf)}')
    print('PASS exact Java/Swift field sets for 10 wire DTOs (not serialization runtime).')

def syntax():
    try:
        from tree_sitter import Language, Parser
        import tree_sitter_swift
    except ImportError as e: raise RuntimeError('Tree-sitter unavailable. Set PYTHONPATH to an installed parser; do not claim Swift compilation.') from e
    parser = Parser(Language(tree_sitter_swift.language()))
    # Scope to this group in both sparse delivery trees and the full integration tree.
    files = sorted(ROOT.glob('Core/PersonalLocationShare*.swift')) + sorted(ROOT.glob('App/PersonalLocationShare*.swift'))
    files += [ROOT / path for path in (
        'App/AccountView.swift', 'App/AppSession.swift', 'App/QuestifyApp.swift',
        'App/SocialPublicProfileView.swift', 'Tests/CoreTests/PersonalLocationShareTests.swift',
        'Tests/AppUnitTests/PersonalLocationShareNormalEntryTests.swift')]
    assert all(path.is_file() for path in files), 'A required personal-sharing source file is missing'
    count = 0
    for path in files:
        tree = parser.parse(path.read_bytes())
        root = tree.root_node
        stack = [root]
        while stack:
            node = stack.pop()
            if node.is_error or node.is_missing:
                print(f'{path.relative_to(ROOT)}:{node.start_point.row+1}: {node.type}'); count += 1
            if node.has_error: stack.extend(node.children)
    if count: raise AssertionError(f'{count} parser recovery nodes')
    print('Parser versions:', importlib.metadata.version('tree-sitter'), importlib.metadata.version('tree-sitter-swift'))
    print(f'PASS supplementary Tree-sitter parse: {len(files)} Swift files. NOT typechecking, Apple SDK or runtime evidence.')

if __name__ == '__main__':
    args = argparse.ArgumentParser(); args.add_argument('--backend-root', type=Path); opts = args.parse_args()
    suite = unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(SourceChecks), unittest.defaultTestLoader.loadTestsFromTestCase(SyntheticProtocolChecks)])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful(): sys.exit(1)
    if opts.backend_root: check_wire(opts.backend_root)
    syntax()
    print('UNEXECUTED: Swift compiler, XCTest, Xcode build, simulator, device, production network/coordinates.')
