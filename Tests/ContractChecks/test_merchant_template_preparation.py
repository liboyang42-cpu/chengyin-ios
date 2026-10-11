"""Supplementary source checks for existing venue/material fields, not Apple acceptance."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplatePreparationChecks(unittest.TestCase):
    def test_venue_choices_are_exact_mini_values_without_new_backend_enums(self):
        source = read('Core/MerchantOperationsContracts.swift')
        choices = source.split('public enum MerchantTemplateVenueChoice:')[1].split('public enum MerchantTemplateMethod:')[0]
        self.assertEqual(re.findall(r'= "([\u4e00-\u9fff]+)"', choices), ['景区', '公园绿地', '商圈街区', '古镇老街', '博物馆', '校园', '室内场馆'])
        self.assertNotIn('default:', choices)

    def test_exact_existing_optional_strings_decode_and_serialize(self):
        model = read('Core/MerchantOperationsContracts.swift').split('public struct MerchantNodeTemplate:')[1].split('public struct MerchantCityNodeRecord:')[0]
        for key in ['usageLocation', 'requiredMaterials']:
            self.assertIn('public var ' + key + ' = ""', model)
            self.assertIn('try c.decodeIfPresent(String.self, forKey: .' + key + ') ?? ""', model)
        self.assertIn('fields["usageLocation"] = usageLocation', model)
        self.assertIn('"requiredMaterials": requiredMaterials', model)
        self.assertNotIn('clearUsageLocation', model)

    def test_unknown_source_venue_is_preserved_and_no_choice_is_assumed(self):
        app = read('App/MerchantOperationsEditor.swift')
        for token in ['MerchantTemplateVenueChoice(rawValue: value.usageLocation) == nil',
                      'Text(verbatim: value.usageLocation).tag(value.usageLocation)',
                      'Text("merchant.preparation.unspecified").tag("").disabled(true)',
                      'value.usageLocation = text; model.edit(.template(value))']:
            self.assertIn(token, app)
        self.assertNotIn('usageLocation = MerchantTemplateVenueChoice', app)
        fixture = read('Core/MerchantOperationsSyntheticFixtures.swift')
        self.assertIn('? baseline.usageLocation : draft.usageLocation', fixture)

    def test_existing_editor_and_frozen_review_show_both_preparation_fields(self):
        app = read('App/MerchantOperationsEditor.swift')
        for token in ['ForEach(MerchantTemplateVenueChoice.allCases', 'templateField("merchant.preparation.materials", \\.requiredMaterials',
                      'MerchantTemplateVenueChoice(rawValue: template.usageLocation)',
                      'Text(verbatim: template.usageLocation)', 'template.requiredMaterials.trimmingCharacters']:
            self.assertIn(token, app)
        self.assertIn('confirmation.draft', app)
        self.assertIn('merchant.preparation.omissionHint', app)

    def test_ai_and_local_planning_guards_remain_separate_from_persisted_fields(self):
        ai = read('Core/MerchantTemplateAssistContracts.swift')
        self.assertNotIn('usageLocation', ai); self.assertNotIn('requiredMaterials', ai)
        draft = read('Core/MerchantOperationsDraft.swift')
        self.assertIn('guard !localOnlyReview else { throw MerchantOperationsFailure.liveWritesDisabled }', draft)
        reader = read('Core/MerchantOperationsReading.swift')
        self.assertIn('guard reader.canSave', reader)
        self.assertIn('reader.saveTemplateReviewed(template, baseline: baseline)', reader)
        self.assertIn('baseline = .template(returned); draft = .template(returned)', reader)

    def test_fragment_covers_all_labels_and_semantic_wire_values_stay_untranslated(self):
        fragment = json.loads(read('Resources/MerchantTemplatePreparationLocalizations.fragment.json'))
        keys = set()
        for path in ['Core/MerchantOperationsContracts.swift', 'App/MerchantOperationsEditor.swift']:
            source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', read(path))
            keys.update(re.findall(r'"(merchant\.preparation\.[A-Za-z.]+)"', source))
        self.assertEqual(set(fragment), keys)
        self.assertEqual(len(fragment), 14)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        self.assertIn('.tag(choice.rawValue)', read('App/MerchantOperationsEditor.swift'))

    def test_authored_tests_cover_write_readback_preservation_cancel_and_no_replay(self):
        core = read('Tests/CoreTests/MerchantTemplatePreparationTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 10)
        for token in ['" Legacy venue "', 'PreparationTransport: HTTPTransport', 'XCTAssertEqual(saves.count, 1)',
                      'payload["usageLocation"]', 'payload["requiredMaterials"]',
                      '"/prod-api/api/template/myinfo"', 'source.requiredMaterials, "Canonical materials"',
                      'coordinator.cancelConfirmation()', 'coordinator.discardChanges()', 'reader.saveCount, 0']:
            self.assertIn(token, core)
        ui = read('Tests/AppUITests/MerchantTemplatePreparationFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 2)
        self.assertIn('app.buttons["Museum"].tap()', ui)
        self.assertIn('app.alerts.buttons["merchant.operations.discardReload"].tap()', ui)
        self.assertIn('XCTAssertEqual(field.value as? String, "Map and pen")', ui)
        self.assertIn('app.alerts.buttons["merchant.operations.keepEditing"].waitForExistence(timeout: 5)', ui)
        self.assertIn('app.alerts.buttons["merchant.operations.discardReload"].waitForExistence(timeout: 5)', ui)


if __name__ == '__main__': unittest.main()
