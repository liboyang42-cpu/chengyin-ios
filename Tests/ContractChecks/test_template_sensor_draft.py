"""Source-level guards only. Swift behavior and Keychain runtime are not executed."""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class TemplateSensorDraftSourceTests(unittest.TestCase):
    def test_optional_local_state_and_no_remote_field_mapping(self):
        domain = (ROOT / 'Core/TemplateAuthoringDomain.swift').read_text()
        self.assertIn('public var sensorDraft: TemplateSensorDraft?', domain)
        payload = (ROOT / 'Core/TemplateAuthoringContract.swift').read_text()
        self.assertNotIn('string("sensor', payload)

    def test_source_and_current_input_are_separate(self):
        core = (ROOT / 'Core/TemplateSensorDraft.swift').read_text()
        for text in ['public let originalType', 'public let originalConfig', 'public private(set) var working',
                     'guard isValid, let kind', 'if working == nil, let originalConfig', 'raw.utf16.count <= 2_000']:
            self.assertIn(text, core)
        self.assertIn('return working.inputs[parameter.rawValue] ?? ""', core)

    def test_ui_setters_guard_session_and_commit_before_navigation(self):
        ui = (ROOT / 'App/TemplateSensorDraftConfigurationView.swift').read_text()
        self.assertEqual(ui.count('guard canEdit, draft.id == nil, draft.validationMethod.rawValue == 7'), 2)
        self.assertEqual(ui.count('draft.sensorDraft = value; changed()'), 2)
        self.assertIn('if model.canEdit, model.draft.id == nil', ui)
        self.assertNotIn('publishIssues', ui)
        self.assertNotIn('@State', ui)

    def test_no_device_network_or_unprotected_storage(self):
        content = '\n'.join((ROOT / path).read_text() for path in [
            'Core/TemplateSensorDraft.swift', 'App/TemplateSensorDraftConfigurationView.swift'])
        for forbidden in ['CoreMotion', 'AVFoundation', 'CMPedometer', 'AVAudioRecorder', 'requestAuthorization',
                          'URLSession', 'UserDefaults', 'FileManager', 'sensor/submit']:
            self.assertNotIn(forbidden, content)

        # Static production wiring evidence only; no Keychain operation is executed.
        app = (ROOT / 'App/AppSession.swift').read_text()
        self.assertIn('TemplateAuthoringSecureStorage(scope: storageScope)', app)
        self.assertIn('TemplateAuthoringLocalStore(storage: templateAuthoringSecureStorage)', app)
        self.assertIn('store: templateAuthoringDraftStore', app)

    def test_localizations_and_test_scenarios_exist(self):
        fragment = json.loads((ROOT / 'Resources/TemplateSensorDraftLocalizations.fragment.json').read_text())
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key, translations in fragment.items():
            self.assertEqual(set(translations), {'en', 'zh-Hans'})
            for lang, value in translations.items():
                self.assertEqual(catalog[key]['localizations'][lang]['stringUnit']['value'], value)
        tests = (ROOT / 'Tests/CoreTests/TemplateSensorDraftTests.swift').read_text()
        self.assertIn('testLocalStorePipelineRoundTripAndOwnerSeparation', tests)
        self.assertIn('testOriginalIsExactButInvalidCurrentInputNeverFallsBack', tests)

if __name__ == '__main__':
    unittest.main()
