"""Offline closeout composition contracts; not Swift or Apple runtime acceptance."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
class NativeCloseoutTests(unittest.TestCase):
    def test_voice_configuration_gate_is_mounted_before_disabled_resource_reads(self):
        text=(ROOT/'App/MerchantNPCViews.swift').read_text()
        self.assertLess(text.index('Section("merchantVoice.title")'),text.index('if model.coordinator.isCurrent, let resources'))
        self.assertIn('MerchantNPCResourceEditor(coordinator: coordinator', (ROOT/'App/AppSession.swift').read_text())
        self.assertIn('accessibilityIdentifier("merchantVoice.configurationRequired")',text)
    def test_voice_default_transport_is_bounded_and_independently_disabled(self):
        text=(ROOT/'Core/MerchantNPCVoiceUpload.swift').read_text()
        self.assertIn('transport: any HTTPTransport = ResponseLimitedHTTPTransport()',text)
        self.assertIn('enabled: Bool = false',text)
        self.assertIn('policy.resourceAllowed, policy.voiceCloning',text)
        self.assertIn('approval?.allows(configuration:',text)
        self.assertNotIn('URLSessionTransport()',text)
    def test_voice_catalog_fragment_is_merged_exactly(self):
        fragment=json.loads((ROOT/'Resources/MerchantNPCVoiceSamples.fragment.json').read_text())['strings']
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        for key,value in fragment.items():self.assertEqual(catalog[key],value)
    def test_shared_image_and_voice_editor_scopes_survive_reconciliation(self):
        text=(ROOT/'App/MerchantNPCViews.swift').read_text()
        for marker in ['voiceSamples?.invalidate()', 'proof.npcAvatar(scope:', 'return selectedImage != nil', 'imageContext.currentScope() == proof.scope', 'imageContext?.picker.cancel()']:
            self.assertIn(marker,text)
    def test_app_unit_target_includes_voice_and_both_image_test_sources(self):
        text=(ROOT/'Questify.xcodeproj/project.pbxproj').read_text()
        for name in ['MerchantNPCVoiceDeviceTests','RetainedImageNormalHostTests','RetainedImageSanitizerTests']:
            self.assertIn('Tests/AppUnitTests/'+name+'.swift',text)
        source=(ROOT/'Tests/AppUnitTests/RetainedImageNormalHostTests.swift').read_text()
        self.assertIn('var value: RetainedImageHostCredentials?',source)
        self.assertIn('journal:',source)
