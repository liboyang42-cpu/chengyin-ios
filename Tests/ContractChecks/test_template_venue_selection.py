"""P036 source fences only; these do not execute Swift or establish Apple UI parity."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = ["景区", "公园绿地", "商圈街区", "古镇老街", "博物馆", "校园", "室内场馆"]
IDS = ['scenicArea', 'park', 'shoppingDistrict', 'historicTown', 'museum', 'campus', 'indoorVenue']


def read(path):
    return (ROOT / path).read_text()


def editor():
    return read('App/TemplateAuthoringMetadataSelectors.swift').split('@MainActor final class TemplateAuthoringVenueEditor: ObservableObject {')[1].split('@MainActor struct TemplateAuthoringVenueField: View')[0]


class TemplateVenueSelectionChecks(unittest.TestCase):
    def test_presets_match_seven_source_wire_values_in_order(self):
        core = read('Core/TemplateMetadata.swift').split('public enum TemplateVenuePreset:')[1].split('/// Only the two dictionaries')[0]
        pairs = re.findall(r'case \.(\w+): return "([^"]+)"', core)
        self.assertEqual(pairs, list(zip(IDS, EXPECTED)))
        self.assertIn('storedValue.utf8.elementsEqual(storedValue.utf8)', core)
        self.assertNotIn('trimmingCharacters', core)
        self.assertNotIn('localized:', core)

    def test_ordinary_editor_uses_selector_instead_of_unscoped_text_binding(self):
        view = read('App/TemplateAuthoringView.swift')
        self.assertEqual(view.count('TemplateAuthoringVenueField(model: model)'), 1)
        self.assertNotIn('TemplateAuthoringField("usageLocation"', view)
        host = read('App/TemplateAuthoringMetadataSelectors.swift').split('@MainActor struct TemplateAuthoringVenueField: View')[1].split('@MainActor private struct TemplateAuthoringVenueSelector: View')[0]
        self.assertIn('.sheet(item: $presented)', host)
        self.assertIn('VStack(alignment: .leading', host)
        self.assertIn('Presentation: Identifiable { let id = UUID() }', host)
        self.assertIn('.id(presentation.id)', host)
        self.assertIn('.buttonStyle(.borderless)', host)

    def test_lifetime_is_bound_to_owner_identity_generation_and_exact_venue_bytes(self):
        source = editor()
        for token in ['session == model.coordinator.session', 'identity == model.coordinator.identity',
                      'modelGeneration == model.metadataGeneration', 'originalDraft == model.draft',
                      'originalDraft.usageLocation.map({ Data($0.utf8) }) == model.draft.usageLocation.map({ Data($0.utf8) })',
                      'model.canReadMetadataDraft', 'model.canEdit', '!model.busy', 'model.coordinator.review == nil',
                      'model.draft.id == nil', 'guard canEdit else { return false }']:
            self.assertIn(token, source)

    def test_cancel_and_current_choice_do_not_write_or_dispatch(self):
        source = editor()
        self.assertIn('func close() { active = false }', source)
        self.assertIn('if selected != preset {\n            model.draft.usageLocation = preset.storedValue\n            model.changed()\n        }', source)
        self.assertEqual(source.count('model.changed()'), 1)
        self.assertEqual(re.findall(r'model\.draft\.(\w+) = ', source), ['usageLocation'])
        for token in ['URLRequest', 'HTTPTransport', 'reader', 'Task {', 'confirm(', 'saveLocal(', 'prepare(']:
            self.assertNotIn(token, source)

    def test_historical_values_are_visible_and_dismissal_retires_callbacks(self):
        source = read('App/TemplateAuthoringMetadataSelectors.swift').split('@MainActor private struct TemplateAuthoringVenueSelector: View')[1]
        for token in ['Text(verbatim: raw)', 'editor.hasHistoricalValue', 'Text("templateVenue.historical")',
                      'if editor.select(preset) { dismiss() }', '.onDisappear { editor.close() }',
                      'editor.close(); dismiss()', '.accessibilityAddTraits(editor.selected == preset ? .isSelected : [])',
                      '.frame(minHeight: 44)']:
            self.assertIn(token, source)

    def test_localized_labels_do_not_change_wire_values(self):
        rows = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        keys = {key for key in rows if key.startswith('templateVenue.')}
        self.assertEqual(keys, {'templateVenue.' + key for key in IDS + ['historical']})
        for key, stored in zip(IDS, EXPECTED):
            localizations = rows['templateVenue.' + key]['localizations']
            self.assertEqual(localizations['zh-Hans']['stringUnit']['value'], stored)
            self.assertTrue(localizations['en']['stringUnit']['value'])
            self.assertNotEqual(localizations['en']['stringUnit']['value'], stored)
        contract = read('Core/TemplateAuthoringContract.swift')
        self.assertIn('string("usageLocation", d.usageLocation)', contract)

    def test_authored_swift_tests_cover_noop_scope_stale_bytes_and_restoration(self):
        source = read('Tests/AppUnitTests/TemplateMetadataSelectorLifecycleTests.swift')
        for name in ['testVenueOpenCancel', 'testEveryVenueSelection', 'testCurrentVenueSelection',
                     'testVenueCallbacksRetire', 'testVenueStaleCanonicalEquivalentBytes',
                     'testVenueRestoreAndReview', 'testVenueBusyAndUnknownSubmission']:
            self.assertIn('func ' + name, source)
        self.assertIn('testVenuePresetsKeepSourceOrderAndExactChineseWireValues', read('Tests/CoreTests/TemplateMetadataTests.swift'))
        self.assertIn('testVenueMatchingNeverTrimsTranslatesOrReplacesUnknownHistoricalValues', read('Tests/CoreTests/TemplateMetadataTests.swift'))


if __name__ == '__main__':
    unittest.main()
