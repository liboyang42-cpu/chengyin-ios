"""Static contracts only; Swift/Apple test execution is a separate requirement."""
import json
import re
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PreferenceDraftContracts(unittest.TestCase):
    def source(self, path): return (ROOT / path).read_text()
    def test_source_json_is_only_persisted_truth(self):
        ui = self.source('App/TemplatePreferenceDraftEditor.swift')
        self.assertIn('model.draft.preferenceJson = value', ui)
        self.assertIn('model.changed()', ui)
        self.assertIn('.confirmationDialog(', ui)
        for forbidden in ['UserDefaults', 'URLSession', 'JSONEncoder', 'OwnedTemplateConfigurationSnapshot']:
            self.assertNotIn(forbidden, ui)
        domain = self.source('Core/TemplateAuthoringDomain.swift')
        self.assertIn('public var preferenceJson: String?', domain)
        storage = self.source('App/TemplateAuthoringSecureStorage.swift')
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', storage)
        self.assertIn('kSecAttrSynchronizable as String: false', storage)
    def test_validation_is_explicit_bounded_and_stale_result_fenced(self):
        ui = self.source('App/TemplatePreferenceDraftEditor.swift')
        self.assertIn('Task.detached', ui)
        self.assertIn('generation == stamp', ui)
        self.assertIn('raw.utf8.elementsEqual(source.utf8)', ui)
        self.assertIn('if editable {', ui)
        self.assertIn('model.draft.id == nil', ui)
        self.assertIn('checkedSource.map({ $0.utf8.elementsEqual(raw.utf8) }) == true', ui)
        self.assertIn('model.coordinator.session == session', ui)
        self.assertIn('model.coordinator.identity == identity', ui)
        self.assertIn('.onChange(of: raw) { _, _ in invalidate() }', ui)
        core = self.source('Core/TemplatePreferenceDraft.swift')
        for text in ['1_048_576', 'depth <= 64', 'next.count <= 4096', 'work >= count', 'fields.count <= 2_000', '.incomplete', '.unsupported']:
            self.assertIn(text, core)
        self.assertNotIn('TemplatePreferencePreview(', core)
    def test_backend_fields_and_rules_are_explicit(self):
        core = self.source('Core/TemplatePreferenceDraft.swift')
        for token in ['notApplicableResult', 'nextStepDays', '{{choices}}', 'tagConsumes', 'tagOutput', 'fromDimension', 'revocable', 'recipientLabel', 'purpose', '"single", "discard"', 'Int32.max', 'raw.contains(".")', 'resolved.count == 1', 'reachable == Set(dimensions)', 'coupons.allSatisfy']:
            self.assertIn(token, core)
    def test_remote_entries_all_fail_closed(self):
        contract = self.source('Core/TemplateAuthoringContract.swift')
        self.assertIn('!draft.validationMethod.isLocalConfigurationOnly', contract)
        self.assertIn('!d.validationMethod.isLocalConfigurationOnly', contract)
        self.assertIn('(0...5).contains(method)', contract)
        self.assertIn('privateConfiguration.isDisjoint(with: fields.keys)', contract)
        for path in ['Core/TemplateAuthoringService.swift', 'Core/TemplateAuthoringWireRequestBuilder.swift']:
            self.assertIn('TemplateAuthoringContract.permitsRemoteConfiguration(', self.source(path))
        owner = self.source('Core/OwnedTemplateConfiguration.swift')
        self.assertIn('[1, 3].contains(validationMethod)', owner)
    def test_remote_allowlist_matches_existing_serializer_fields(self):
        source = self.source('Core/TemplateAuthoringContract.swift')
        payload = source.split('public static func payload(')[1].split('public static func decodeList')[0]
        generated = set(re.findall(r'(?:string|number)\("([^"]+)"', payload)) | set(re.findall(r'p\["([^"]+)"', payload)) | {'title', 'description', 'isSync'}
        helper = source.split('public static func permitsRemoteConfiguration')[1].split('public static func request')[0]
        strings = helper.split('let stringFields: Set<String> = ')[1].split('let numberFields')[0]
        numbers = helper.split('let numberFields: Set<String> = ')[1].split('guard Set')[0]
        allowed = set(re.findall(r'"([^"]+)"', strings + numbers))
        self.assertEqual(generated - {'id'}, allowed)
        self.assertEqual(len(allowed), 40)
    def test_preference_ui_and_bilingual_scope(self):
        self.assertIn('TemplatePreferenceDraftEditor(model: model)', self.source('App/TemplateAuthoringDetailForms.swift'))
        view = self.source('App/TemplateAuthoringView.swift')
        self.assertIn('model.draft.validationMethod.isLocalConfigurationOnly', view)
        values = json.loads(self.source('tools/template_preference_draft_localizations.json'))
        catalog = json.loads(self.source('Resources/Localizable.xcstrings'))['strings']
        for key, translations in values.items():
            self.assertEqual(set(translations), {'en', 'zh-Hans'})
            for language, value in translations.items(): self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], value)
