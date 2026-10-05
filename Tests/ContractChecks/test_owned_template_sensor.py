"""Read-only sensor source contracts, not Swift execution evidence."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class OwnedSensorContracts(unittest.TestCase):
    def test_source_ranges_and_no_defaults_or_device_actions(self):
        source = (ROOT / 'Core/OwnedTemplateSensorConfiguration.swift').read_text()
        for token in ['return 600', 'return 100_000', 'return 86_400', 'return 60', 'raw.utf16.count <= 2_000', 'topLevelLiterals(raw)', 'unsupported-duplicate', r'\A[0-9]+\z', 'Self.hasBoundedJSONDepth(raw)', 'if depth > 16' , 'case missing, null, invalid, unsupportedType, ready, partial']:
            self.assertIn(token, source)
        for token in ['Codable', 'PlayStillnessConfiguration(', 'Provider', 'submit(', 'save(', '?? 30', 'filter_shot']:
            self.assertNotIn(token, source)
    def test_initializer_unknown_fields_closure_captures_local_not_partial_self(self):
        source = (ROOT / 'Core/OwnedTemplateSensorConfiguration.swift').read_text()
        self.assertIn('let configuredParameters = parameters', source)
        self.assertIn('let unknown = fields.keys.contains { key in !configuredParameters.contains { $0.rawValue == key } }', source)
        self.assertNotIn('fields.keys.contains { key in !parameters.contains', source)
        self.assertLess(source.index('let configuredParameters = parameters'), source.index('let unknown = fields.keys.contains'))
        self.assertLess(source.index('let unknown = fields.keys.contains'), source.index('status = !allValid ? .invalid : (unknown ? .partial : .ready)'))
    def test_identity_precedes_sensor_and_shared_lifetime_retains_nothing_in_view(self):
        source = (ROOT / 'Core/OwnedTemplateConfiguration.swift').read_text()
        self.assertLess(source.index('fields["memberId"]?.integer == accountID'), source.index('sensor = validationMethod == 7'))
        view = (ROOT / 'App/OwnedTemplateSensorConfigurationView.swift').read_text()
        for token in ['@State', 'Button(', 'Link(', 'TextField(', 'AVFoundation', 'CoreMotion', 'sensorConfig', 'originalResponse']:
            self.assertNotIn(token, view)
        parent = (ROOT / 'App/OwnedTemplateConfigurationView.swift').read_text()
        self.assertIn('snapshot.id == id', parent)
        self.assertIn('OwnedTemplateSensorConfigurationFields(configuration: sensor)', parent)
        self.assertIn('host.clear()', parent)
    def test_names_and_bounds_do_not_expand_write_enum(self):
        source = (ROOT / 'Core/TemplateAuthoringDomain.swift').read_text()
        method = source.split('enum TemplateAuthoringMethod')[1].split('public enum')[0]
        self.assertIn('preference = 6', method); self.assertIn('sensor = 7', method)
        self.assertIn('self == .preference || self == .sensor', method)
        contract = (ROOT/'Core/TemplateAuthoringContract.swift').read_text()
        self.assertIn('!draft.validationMethod.isLocalConfigurationOnly', contract)
        self.assertIn('!d.validationMethod.isLocalConfigurationOnly', contract)
        self.assertIn('(0...5).contains(method)', contract)
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        self.assertEqual(strings['templateOwnerSensor.preference']['localizations']['zh-Hans']['stringUnit']['value'], '偏好题组')
        self.assertEqual(strings['templateOwnerSensor.challenge']['localizations']['zh-Hans']['stringUnit']['value'], '传感器挑战')
        for key in ['durationSec', 'targetSteps', 'windowSec', 'minDurationSec']:
            self.assertIn('templateOwnerSensor.parameter.' + key, strings)
if __name__ == '__main__': unittest.main()
