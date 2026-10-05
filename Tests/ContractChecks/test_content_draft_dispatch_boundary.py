"""Supplementary source checks only. Swift negative controls and runtime tests remain separate."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ContentDraftDispatchBoundarySourceTests(unittest.TestCase):
    def setUp(self):
        self.coordinator = (ROOT / 'Core/VersionedContentDraftCoordinator.swift').read_text()
        self.service = (ROOT / 'Core/VersionedContentDraftService.swift').read_text()
        self.storage = (ROOT / 'Core/ContentDraftSystemStorage.swift').read_text()
        self.journal = (ROOT / 'Core/ContentDraftDurableJournal.swift').read_text()
        self.permit = self.coordinator.split('@MainActor public final class ContentDraftPreparedDispatch:')[1].split('@available(macOS 14.0, *)')[0]

    def test_no_raw_service_entry_and_unforgeable_attempt(self):
        contracts = (ROOT / 'Core/VersionedContentDraftContracts.swift').read_text()
        for source in [self.service, contracts]:
            self.assertIn('func mutate(_ attempt: ContentDraftPreparedDispatch)', source)
            self.assertNotIn('func mutate(_ mutation: ContentDraftMutation)', source)
        self.assertIn('fileprivate init(snapshot:', self.permit)
        self.assertNotIn('public init(', self.permit)
        self.assertNotIn('Codable', self.permit)
        self.assertIn('private var started = false', self.permit)
        self.assertIn('private var retired = false', self.permit)
        self.assertEqual(self.permit.count('started = false'), 1)
        self.assertEqual(self.permit.count('retired = false'), 1)
        self.assertIn('fileprivate func retire() { retired = true }', self.permit)

    def test_attempt_bound_to_exact_request_and_snapshot(self):
        for token in ['request.httpBody == body', 'request.httpMethod == "POST"',
                      'request.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8)',
                      'self.lease === lease', 'try await journal.read() == snapshot',
                      'snapshot.value.dispatched', 'snapshot.generation.count == 32',
                      'encoder.encode(mutation.command)', 'ContentDraftJournalScope(context: lease.context, identity: mutation.identity)']:
            self.assertIn(token, self.permit)
        self.assertLess(self.permit.index('started = true\n'), self.permit.index('try await journal.read()'))
        self.assertGreaterEqual(self.permit.count('try lease.check()'), 3)
        self.assertIn('guard isCurrent(), !retired', self.permit)
        self.assertIn('guard started, !retired', self.permit)

    def test_only_coordinator_mints_and_retires_after_persistence(self):
        dispatch = self.coordinator.split('private func dispatchPending()')[1].split('public func fetchLatestForConflict()')[0]
        self.assertLess(dispatch.index('try await journal.replace(original'), dispatch.index('try ContentDraftPreparedDispatch('))
        self.assertLess(dispatch.index('guard try await journal.read() == dispatched'), dispatch.index('try ContentDraftPreparedDispatch('))
        self.assertIn('isCurrent: { [weak self] in self?.gate(ticket) == true }', dispatch)
        self.assertIn('defer { attempt.retire() }', dispatch)
        self.assertEqual(self.coordinator.count('try ContentDraftPreparedDispatch('), 1)
        for path in (ROOT / 'App').glob('*.swift'):
            self.assertNotIn('ContentDraftPreparedDispatch(', path.read_text())

    def test_service_consumes_before_transport_and_all_writes_require_attempt(self):
        self.assertIn('(route == .save || route == .delete) == (attempt != nil)', self.service)
        self.assertLess(self.service.index('try await attempt.consume('), self.service.index('try await transport.send(request)'))
        self.assertIn('transport: transport)', self.service)
        self.assertIn('try check(attempt.route, identity: mutation.identity)', self.service)

    def test_fixed_os_factory_is_only_source_of_sealed_storage(self):
        self.assertIn('fileprivate init(anchors: ContentDraftSystemAnchors, ciphertexts: ContentDraftSystemCiphertexts)', self.storage)
        self.assertEqual(self.storage.count('ContentDraftSystemStorage('), 1)
        self.assertIn('ContentDraftSystemAnchors(service: "questify.content-draft.pending.v1")', self.storage)
        self.assertIn('ContentDraftDurableJournal(scope: scope, system: storage)', self.storage)
        self.assertIn('private let systemStorage: ContentDraftSystemStorage?', self.journal)
        self.assertIn('var isSystemBacked: Bool { systemStorage != nil }', self.journal)
        injected = self.journal.split('public init(scope: ContentDraftJournalScope, anchors:')[1].split('public func read()')[0]
        self.assertIn('systemStorage = nil', injected)
        self.assertIn('(journal as? ContentDraftDurableJournal)?.isSystemBacked == true', self.permit)

    def test_fake_provenance_can_only_use_final_nonnetwork_recorder(self):
        self.assertIn('transport is ContentDraftRecordingTransport', self.permit)
        recorder = self.service.split('@MainActor final class ContentDraftRecordingTransport: HTTPTransport')[1]
        self.assertNotIn('public ', recorder)
        self.assertNotIn('URLSession', recorder)
        self.assertNotIn('HTTPTransport', recorder)
        self.assertNotIn('transport.send', recorder)
        self.assertNotIn('-> Void', recorder)
        self.assertNotIn('during', recorder)
        self.assertIn('requests.append(request)', recorder)
        self.assertIn('return response', recorder)
        for source in [self.service, self.permit, self.journal, self.storage]:
            self.assertNotIn('unsafeBypass', source)
            self.assertNotIn('#if DEBUG', source)

    def test_actual_coordinator_service_and_negative_api_controls_authored(self):
        tests = (ROOT / 'Tests/CoreTests/ContentDraftPreparedDispatchTests.swift').read_text()
        for term in ['RealServiceSeesExactDurableGeneration', 'MissingLockedCorruptAndInterrupted',
                     'RechecksGeneration', 'CrossOperationSnapshot', 'LostResponseRetry', 'UnconsumedAttemptRetires',
                     'ConsumedAttemptCannotAuthorizeNewReviewOrDelete', 'MismatchedBodyPathKeyOwnerAndVersion',
                     'DifferentLease', 'RevokedSession', 'ArbitraryTransportAndInjectedDurableStores', 'Late401',
                     'GenerationAdvanceInsideFinalBlobRead', 'RetirementDuringStartedFinalRead', 'FinalGrantClockCallback']:
            self.assertIn(term, tests)
        self.assertGreaterEqual(len(re.findall(r'func test\w+\(', tests)), 17)
        self.assertIn('ContentDraftCoordinator', tests)
        self.assertIn('ContentDraftService', tests)
        self.assertIn('ContentDraftDurableJournal', tests)
        for name in ['positive', 'raw_mutate', 'forge_attempt', 'forge_system_storage']:
            self.assertTrue((ROOT / 'Tests/CompileFailures/ContentDraftDispatch' / (name + '.swift.fixture')).is_file())

if __name__ == '__main__': unittest.main()
