"""Static contracts only; not Swift or OS execution evidence."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def core(name): return (ROOT / 'Core' / name).read_text()
class PlayDurableRecoveryContracts(unittest.TestCase):
    def test_async_generation_contract_replaces_blind_writes(self):
        text=core('PlayRecoveryStorage.swift')
        for term in ['async throws', 'replacing snapshot: PlayPausedStorageSnapshot', 'transition(_ snapshot: PlayCompletionRecoverySnapshot']:
            self.assertIn(term,text)
        self.assertNotIn('func write(_ pending:',text)
    def test_no_credentials_in_persisted_owner_and_intent(self):
        text=core('PlayRecoveryStorage.swift').split('public struct PlayPendingCompletion')[0]
        self.assertNotIn('let token',text); self.assertNotIn('session.token',text); self.assertIn('originEpoch',text)
    def test_encrypted_generation_and_presence_fail_closed(self):
        text=core('PlayDurableRecovery.swift')
        for term in ['AES.GCM.seal','AES.GCM.open','matchingTag:','createPresence','hasPresence','case reserved, ready, clearing, empty','observed == expected','let ready = try item(value)']:
            self.assertIn(term,text)
        self.assertNotIn('try?',text)
    def test_final_dispatch_requires_endpoint_provenance_and_snapshot(self):
        text=core('PlayExperienceCoordinator.swift')
        for term in ['fileprivate init(service:','try await store.read(key) == expected','try await store.read(key: key) == expected','permitsSystemDispatch(to:','completionTask?.cancel()','runTask?.cancel()','attempt.retire()']:
            self.assertIn(term,text)
    def test_raw_helper_and_aliases_are_guarded(self):
        text=core('PlayExperienceService.swift')
        for term in ['omittingEmptySubsequences: false','if protected','guard transport is PlayRecoveryRecordingTransport','try attempt?.checkLifetime()']:
            self.assertIn(term,text)
    def test_system_seal_validates_regional_namespace(self):
        text=core('PlayRecoverySystemStorage.swift')
        for term in ['fileprivate init(','PlayRecovery-v1','storageScope.matches(configuration: regionalConfiguration)','session.namespace.utf8.elementsEqual(storageScope.service.utf8)']:
            self.assertIn(term,text)
        text=core('PlayRecoveryRecordingTransport.swift')
        self.assertIn('final class PlayRecoveryRecordingTransport',text)
        for forbidden in ['any HTTPTransport','URLSession(','@escaping']: self.assertNotIn(forbidden,text)
    def test_unknown_and_paused_writes_keep_locks(self):
        text=core('PlayExperienceCoordinator.swift')
        for term in ['retryReadbackVerified','old.value?.pendingRemote != true','pendingRemote: true']: self.assertIn(term,text)
        self.assertNotIn('try? await service.readPaused',text)
    def test_factory_does_not_enable_network(self):
        text=(ROOT/'App/PlayRecoveryComposition.swift').read_text()
        self.assertIn('PlayRecoverySystemFactory.make',text)
        self.assertNotIn('enabled:',text); self.assertNotIn('PlayMemory',text)

    def test_sealed_fixture_preserves_leader_and_preference_readback(self):
        text=(ROOT/'App/PlayExperienceFixtureSupport.swift').read_text()
        self.assertIn('for action in PlayLeadAction.allCases',text)
        self.assertIn('recorder.responses.merge(recorder.afterCompletion)',text)
    def test_late_unauthorized_probe_has_a_real_callback_and_positive_control(self):
        text=(ROOT/'Tests/CoreTests/PlayRecoveryDispatchTests.swift').read_text()
        self.assertIn('XCTAssertEqual(revoked, 2)',text)
        self.assertIn('testFinalReadReplacementRejectsDispatchEvenWithAnUnchangedSession',text)
        self.assertIn('testFinalReadRechecksLiveSelectorWithoutAnExplicitHostInvalidation',text)
