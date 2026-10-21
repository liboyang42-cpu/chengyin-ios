"""Source contracts for the native pages/merchant/decor/ai-npc parity. Does not compile Swift."""
from pathlib import Path
import json
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = (ROOT / 'Core/StoreCharacterContracts.swift').read_text()
SERVICE = (ROOT / 'Core/StoreCharacterService.swift').read_text()
COORDINATOR = (ROOT / 'Core/StoreCharacterCoordinator.swift').read_text()
ISOLATION = (ROOT / 'Core/StoreCharacterSceneIsolation.swift').read_text()
GATES = (ROOT / 'Core/MerchantCityNPCParityGates.swift').read_text()
VIEW = (ROOT / 'App/MerchantStoreCharacterView.swift').read_text()
FIXTURE = (ROOT / 'App/MerchantStoreCharacterFixtureHost.swift').read_text()
BINDING = (ROOT / 'App/MerchantStoreCharacterSessionBinding.swift').read_text()
CATALOG = json.loads((ROOT / 'Resources/StoreCharacter.xcstrings').read_text())['strings']
CORE = [CONTRACTS, SERVICE, COORDINATOR, ISOLATION]


class AINPCContracts(unittest.TestCase):
    def test_endpoints_are_exact_source_routes(self):
        expected = {
            'access': 'api/merchant/access/me', 'profile': 'api/merchant/npc/profile', 'save': 'api/merchant/npc/save',
            'voiceStatus': 'api/merchant/npc/voice/status', 'voiceEnroll': 'api/merchant/npc/voice/enroll',
            'consent': 'api/compliance/consents', 'mapPointRead': 'api/merchant/coop-profile', 'mapPointSave': 'api/merchant/decor/save',
        }
        for name, path in expected.items():
            self.assertIn(f'public static let {name} = "{path}"', CONTRACTS)
        for invented in ['voice/script', 'voice/revoke', 'avatar/generate', 'avatar/status', 'sampleUrls']:
            self.assertNotIn(invented, CONTRACTS + SERVICE)

    def test_bodies_match_backend_contracts(self):
        self.assertIn('["name": name, "greeting": greeting, "persona": persona, "knowledge": knowledge, "avatar": avatar]', CONTRACTS)
        self.assertIn('["voiceSample": voiceSample, "voiceConsent": true]', CONTRACTS)
        self.assertIn('docType = "voice_clone_processing"', CONTRACTS)
        self.assertIn('scene = "merchant_voice"', CONTRACTS)
        self.assertIn('eventType = "AGREE"', CONTRACTS)
        self.assertIn('["locationLat": latitude, "locationLng": longitude, "address": address]', CONTRACTS)
        self.assertIn('requiredPermission = "merchant:profile:write"', CONTRACTS)

    def test_voice_status_is_top_level(self):
        block = SERVICE.split('private struct TopLevelVoice')[1].split('}')[0]
        self.assertIn('voiceStatus', block)
        self.assertNotIn('data', block)

    def test_consent_precedes_enrollment(self):
        body = COORDINATOR.split('public func agreeAndEnroll')[1]
        self.assertLess(body.index('recordVoiceConsent'), body.index('writer.enroll'))

    def test_core_is_foundation_only(self):
        for source in CORE:
            self.assertNotIn('import SwiftUI', source)
            self.assertNotIn('URLSession', source)
            self.assertNotIn('AVAudio', source)
            self.assertNotIn('CLLocation', source)

    def test_gates_default_off_and_allowlist_empty(self):
        for flag in ['storeCharacterSaves', 'storeVoiceEnrollment', 'themeNPCBinding', 'merchantAIDrafts']:
            self.assertIn(f'public var {flag} = false', GATES)
        self.assertIn('reviewedEndpoints: [RegionalMarket: Set<String>] { [:] }', GATES)
        self.assertIn('execution == .injectedOfflineHarness || gates.allows(path, market: market)', SERVICE)
        self.assertIn('publishRouteRegistered = false', ISOLATION)

    def test_production_binding_is_read_only(self):
        self.assertIn('StoreCharacterOperationsReader(reader: reader)', BINDING)
        self.assertNotIn('writer:', BINDING)
        self.assertNotIn('injectedOfflineHarness', BINDING)

    def test_no_capture_or_picker_execution(self):
        for source in [VIEW, FIXTURE]:
            for forbidden in ['AVAudioRecorder', 'AVCaptureDevice', 'PhotosPicker', 'CLLocationManager', 'MKLocalSearch', 'UIImagePickerController']:
                self.assertNotIn(forbidden, source)

    def test_fixture_is_debug_only(self):
        self.assertTrue(FIXTURE.startswith('#if DEBUG'))
        self.assertTrue(FIXTURE.rstrip().endswith('#endif'))
        self.assertIn('struct MerchantStoreCharacterFixtureHost: View', FIXTURE)
        self.assertIn('init(scenario: String)', FIXTURE)

    def test_catalog_matches_used_keys_and_source_copy(self):
        used = set()
        for source in [VIEW, FIXTURE, BINDING]:
            used |= set(re.findall(r'"(storeCharacter\.[A-Za-z0-9.]+)"', source))
        self.assertEqual(used, set(CATALOG))
        zh = {k: v['localizations']['zh-Hans']['stringUnit']['value'] for k, v in CATALOG.items()}
        for key, value in {
            'storeCharacter.title.home': 'AI 店铺角色', 'storeCharacter.title.avatar': '上传角色形象',
            'storeCharacter.hero.namePlaceholder': '给角色起个名字', 'storeCharacter.badge.online': '已上线',
            'storeCharacter.badge.rejected': '已驳回', 'storeCharacter.badge.reviewing': '审核中',
            'storeCharacter.row.avatarValue': '上传 / 更换', 'storeCharacter.voiceValue.failed': '生成失败 · 重试',
            'storeCharacter.mapPoint.unset': '尚未选择地图位置', 'storeCharacter.discard.title': '还没有保存',
            'storeCharacter.notice.saveProfileFirst': '请先保存角色形象', 'storeCharacter.preset.use': '使用这个形象',
            'storeCharacter.voice.queryStatus': '查询生成状态', 'storeCharacter.consent.agree': '单独同意',
        }.items():
            self.assertEqual(zh[key], value)
        for key, entry in CATALOG.items():
            self.assertTrue(entry['localizations']['en']['stringUnit']['value'].strip(), key)

    def test_catalog_builder_is_reproducible(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools/build_store_character_catalog.py')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
