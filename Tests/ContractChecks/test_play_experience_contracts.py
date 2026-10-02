"""Source/schema checks only. These do not execute or typecheck Swift."""
import json
import pathlib
import re
import unittest
from flutter_source import read_flutter_source

ROOT = pathlib.Path(__file__).resolve().parents[2]

class PlayExperienceSourceChecks(unittest.TestCase):
    def core(self, name): return (ROOT / 'Core' / name).read_text()
    def test_contract_files_exist(self):
        for file in ['PlayExperienceContracts.swift','PlayExperienceService.swift','PlayExperienceCoordinator.swift','PlayRunLifecycle.swift','PlayAdvancedRuntime.swift','PlayGameSessionRuntime.swift','PlayCircleRuntime.swift','PlayDeviceTasks.swift','PlayDirectorRuntime.swift']:
            self.assertTrue((ROOT/'Core'/file).is_file(), file)
    def test_source_classic_paths_and_distinct_encodings(self):
        service=self.core('PlayExperienceService.swift')
        for path in ['api/play/nodes','api/play/route-state','api/play/sensor-result','api/play/ending','api/play/hint/unlock','api/play/puzzle/hint','api/play/puzzle/reveal']:
            self.assertIn(path, service)
        self.assertIn('AuthRequestBuilder.makeFormRequest', service)
        self.assertIn('JSONEncoder().encode(json)', service)
    def test_classic_paths_external_flutter_parity(self):
        source=read_flutter_source(self, 'data/api/play_api.dart')
        for path in ['api/play/nodes','api/play/route-state','api/play/sensor-result','api/play/ending','api/play/hint/unlock','api/play/puzzle/hint','api/play/puzzle/reveal']:
            self.assertIn(path, source)
    def test_dormant_default_no_live_transport_fallback(self):
        service=self.core('PlayExperienceService.swift')
        self.assertIn('enabled: Set<PlayExperienceCapability> = []', service)
        self.assertIn('guard enabled.contains(capability)', service)
        for p in (ROOT/'Core').glob('Play*.swift'):
            self.assertNotIn('URLSession.shared', p.read_text())
    def test_exact_route_id_and_version_without_client_outcome(self):
        text=self.core('PlayExperienceService.swift')+self.core('PlayExperienceContracts.swift')
        self.assertIn('"routeActionId"', text); self.assertIn('"expectedRouteVersion"', text)
        self.assertNotIn('"outcomeCode":', text); self.assertNotIn('"targetNodeId":', text)
        self.assertIn('coordinateSystem == "GCJ02"', text)
    def test_qr_server_resolves_node(self):
        self.assertIn('fields.removeValue(forKey: "nodeId")', self.core('PlayExperienceService.swift'))
    def test_route_conflict_uses_structured_code(self):
        text=self.core('PlayExperienceCoordinator.swift')
        self.assertIn('if code == 409', text); self.assertNotIn('message.contains', text)
    def test_different_session_namespaces(self):
        self.assertIn('session.namespace, String(session.accountID)', self.core('PlayRunLifecycle.swift'))
        self.assertIn('currentSession() == session', self.core('PlayExperienceCoordinator.swift'))
    def test_tombstone_and_duration_guards(self):
        text=self.core('PlayRunLifecycle.swift')
        self.assertIn('7 * 24 * 3600', text); self.assertIn('remote.endedAt >=', text)
        self.assertIn('writeTombstone', text); self.assertIn('monotonicNow', text)
    def test_advanced_action_catalog_matches_source(self):
        source=read_flutter_source(self, 'feature/play/advanced/playkit_host.dart')
        block=source.split('kPlayKitServerActionsOf =',1)[1].split('/// 在册动作名的并集',1)[0]
        source_actions=set(re.findall(r"'([A-Z][A-Z0-9_]+)'",block))
        target=self.core('PlayAdvancedRuntime.swift').split('public static let actions:',1)[1].split('public static func payload',1)[0]
        target_actions=set(re.findall(r'"([A-Z][A-Z0-9_]+)"',target))
        self.assertEqual(source_actions,target_actions)
    def test_advanced_unit_and_units_match_source(self):
        text=self.core('PlayAdvancedRuntime.swift')
        self.assertIn('unit-\\(state.sessionID)-v\\(state.version)', text)
        self.assertIn('"roundsMs"', text); self.assertIn('"heldMs"', text)
        self.assertIn('result.version >= pending.version', text)
    def test_player_command_identity_and_receipt_paths(self):
        text=self.core('PlayGameSessionRuntime.swift')
        for path in ['api/game/session/view','api/game/session/command','api/game/session/receipt']:
            self.assertIn(path,text)
        for identity in ['"activityId"','"requestId"','"action"','"revision"','"receiptId"']:
            self.assertIn(identity,text)
        self.assertIn('value.revision >= receipt.revision',text)
    def test_player_paths_external_flutter_parity(self):
        source=read_flutter_source(self, 'data/api/game_session_api.dart')
        for path in ['api/game/session/view','api/game/session/command','api/game/session/receipt']:
            self.assertIn(path, source)
    def test_circle_uses_presence_readback_without_retry_endpoint(self):
        text=self.core('PlayCircleRuntime.swift')
        for path in ['api/circle-theme/session/join','api/circle-theme/session']:
            self.assertIn(path, text)
        self.assertIn('value.confirms(pending)',text); self.assertNotIn('func retry',text)
        self.assertIn('card.raw["completed"].bool != true',text)
    def test_circle_paths_external_flutter_parity(self):
        source=read_flutter_source(self, 'data/api/page_parity_api.dart')
        for path in ['api/circle-theme/session/join','api/circle-theme/session']:
            self.assertIn(path, source)
    def test_hardware_is_injected_and_never_opened_implicitly(self):
        text=self.core('PlayDeviceTasks.swift')
        for bad in ['import CoreLocation','import AVFoundation','import Photos','import CoreMotion','requestWhenInUseAuthorization','requestAccess']:
            self.assertNotIn(bad,text)
        self.assertIn('PlayDeviceProviding',text); self.assertIn('supported: Set<PlayDeviceKind> = []',text)
    def test_stillness_and_stopwatch_source_mechanics(self):
        text=self.core('PlayDeviceTasks.swift')
        for token in ['window.count == 5','delta <= 0.250','completionCount = 1','elapsed < 1','0.05 * scale','0.20 * scale','0.50 * scale']:
            self.assertIn(token,text)
    def test_director_actions_match_source(self):
        source=read_flutter_source(self, 'data/models/game_session.dart').split('const Set<String> clubDirectorActions =',1)[1].split('};',1)[0]
        target=self.core('PlayDirectorRuntime.swift').split('public enum PlayDirectorAction:',1)[1].split('public struct PlayDirectorCommand',1)[0]
        self.assertEqual(set(re.findall(r"'([A-Z_]+)'",source)),set(re.findall(r'"([A-Z_]+)"',target)))
    def test_bilingual_localizations_for_text_literals(self):
        strings=json.loads((ROOT/'docs/play-experience-localizations.json').read_text())
        for file in (ROOT/'App').glob('Play*.swift'):
            text=file.read_text()
            keys=re.findall(r'(?:Text|Button|Label|Section|LabeledContent|TextField|ProgressView|navigationTitle)\("(playx\.[A-Za-z0-9_.-]+)"',text)
            for key in keys:
                self.assertIn(key,strings,(file.name,key))
                self.assertTrue(strings[key]['en']); self.assertTrue(strings[key]['zh-Hans'])
    def test_runtime_verification_is_explicitly_not_run(self):
        verification=json.loads((ROOT/'docs/play-experience-verification.json').read_text())
        for key in ['swift_tests','ios_build','ui_tests','device_acceptance','backend_acceptance']:
            self.assertEqual(verification[key],'NOT_RUN')

if __name__ == '__main__': unittest.main()
