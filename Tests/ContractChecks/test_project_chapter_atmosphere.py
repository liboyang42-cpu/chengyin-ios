"""Focused source contracts. Does not compile or execute Swift / Apple UI tests."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ChapterAtmosphereContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_five_exact_wire_values_aliases_and_solid_colors(self):
        core = self.read('Core/ProjectChapterAtmosphere.swift')
        cases = re.search(r'case black = (.+)\n', core).group(1)
        self.assertEqual(re.findall(r'"([A-Z]+)"', cases), ['DEFAULT', 'BLUE', 'RED', 'YELLOW', 'WHITE'])
        aliases = dict(re.findall(r'case "([A-Z]+)": return \.(\w+)', core))
        self.assertEqual(aliases, {'NIGHT': 'blue', 'ARCHIVE': 'yellow', 'NEON': 'red', 'MOSS': 'black'})
        colors = dict(re.findall(r'case \.(\w+): return (0x[0-9A-F]+)', core))
        self.assertEqual(colors, {'black': '0x0A0A0A', 'blue': '0x14294F', 'red': '0x4E1C24',
                                  'yellow': '0x4E4114', 'white': '0xF5F6F8'})
        host = self.read('App/ProjectChapterAtmosphereFields.swift')
        self.assertIn('Color(.sRGB', host)
        self.assertNotIn('Gradient', host)

    def test_new_field_mount_keeps_actual_city_scope_and_node_narrative_host(self):
        forms = self.read('App/ProjectEditDetailForms.swift')
        self.assertIn('if model.draft.product == .city && chapterOverride == nil {\n                    ProjectChapterAtmosphereFields(model: model, chapterID: chapterID)', forms)
        self.assertIn('ProjectNodeNarrativeEntry(model: model, chapterID: chapterID, nodeID: nodeID)', forms)
        self.assertIn('private var storyImages: ProjectStoryImagePresentation', forms)
        self.assertIn('private var storyAudios: ProjectStoryAudioPresentation', forms)
        self.assertIn('private var storyTemplates: ProjectStoryTemplatePresentation', forms)

    def test_read_only_projection_and_explicit_single_field_mutation(self):
        core = self.read('Core/ProjectChapterAtmosphere.swift')
        projection, mutation = core.split('public func applying(to chapter:')
        self.assertNotRegex(projection, r'preserved\["atmospherePreset"\]\s*=')
        self.assertIn('default: return nil', projection)
        self.assertIn('return matching(value)', projection)
        self.assertEqual(re.findall(r'next\.preserved\["([^"]+)"\]\s*=', mutation), ['atmospherePreset'])
        self.assertNotIn('.onAppear', self.read('App/ProjectChapterAtmosphereFields.swift'))

    def test_real_model_lease_and_exact_snapshot_guards_precede_persistence(self):
        host = self.read('App/ProjectChapterAtmosphereFields.swift')
        for token in ['model.draft.product == .city', 'model.captureStarterLease()',
                      'value.host == hostIdentity', 'value.hostGeneration == hostGeneration',
                      'model.isCurrentStarterLease(value.lease)', 'model.draftMutationRevision == value.revision',
                      'ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes',
                      '.filter({ $0.id == hostIdentity.chapterID }).count == 1',
                      'firstIndex(where: { $0.id == hostIdentity.chapterID })']:
            self.assertIn(token, host)
        selection = host.split('func select(')[1].split('func retire()')[0]
        self.assertLess(selection.index('isCurrent(value)'), selection.index('preset.applying(to:'))
        self.assertLess(selection.index('preset.applying(to:'), selection.index('model.persistLocalChange(next, lease: value.lease)'))
        self.assertIn('saveUnconfirmed = true; return', selection)
        for forbidden in ['URLSession', 'coordinator.confirm(', 'OperationEndpointApproval', 'appSession', 'UserDefaults', 'chapters[0]']:
            self.assertNotIn(forbidden, host)

    def test_state_owner_and_host_retirement_match_real_route(self):
        host = self.read('App/ProjectChapterAtmosphereFields.swift')
        outer = host.split('struct ProjectChapterAtmosphereFields: View')[1].split('private struct ProjectChapterAtmosphereHost: View')[0]
        self.assertNotIn('@StateObject', outer)
        self.assertIn('.id(ProjectChapterAtmosphereHostIdentity(model: ObjectIdentifier(model), chapterID: chapterID))', outer)
        self.assertIn('self.model === model', host)
        self.assertIn('.onDisappear { controller.retire() }', host)
        self.assertIn('func retire() { hostGeneration += 1;', host)

    def test_existing_payload_and_endpoint_contract_is_reused(self):
        contract = self.read('Core/ProjectEditContract.swift')
        carried = re.search(r'chapterCarryOver = \[(.*?)\]', contract).group(1)
        self.assertIn('"atmospherePreset"', carried)
        self.assertIn('for key in chapterCarryOver { if let value = chapter.preserved[key] { p[key] = value } }', contract)
        for endpoint in ['/api/topic/create', '/api/topic/update', '/api/topic/edit-detail']:
            self.assertIn(endpoint, contract)
        new_code = self.read('Core/ProjectChapterAtmosphere.swift') + self.read('App/ProjectChapterAtmosphereFields.swift')
        self.assertNotIn('/api/', new_code)
        self.assertNotIn('URLRequest', new_code)
        self.assertIn('guard ProjectChapterAtmosphere.canSubmit(chapter) else { throw ProjectEditError.invalidDraft }', contract)
        self.assertIn('if ProjectChapterAtmosphere.canSubmit(c), let preset = ProjectChapterAtmosphere.selected(in: c)', contract)
        self.assertNotIn('aliases[rawPreset] ?? "DEFAULT"', contract)
        self.assertIn('first.value <= 0x20', new_code)
        self.assertIn('last.value <= 0x20', new_code)
        self.assertIn('ProjectChapterAtmosphere.canSubmit($0) ? ProjectChapterAtmosphere.selected(in: $0) : nil', new_code)

    def test_bilingual_fragment_covers_labels_and_selection_is_not_color_only(self):
        host = self.read('App/ProjectChapterAtmosphereFields.swift')
        visible = re.sub(r'\.accessibilityIdentifier\("[^"]*"(?:\s*\+\s*preset.rawValue)?\)', '', host)
        keys = set(re.findall(r'"(projectChapterAtmosphere\.[A-Za-z.]+)"', visible))
        keys.discard('projectChapterAtmosphere.color.')
        keys.discard('projectChapterAtmosphere.note.')
        for value in ['DEFAULT', 'BLUE', 'RED', 'YELLOW', 'WHITE']:
            keys.add('projectChapterAtmosphere.color.' + value)
            keys.add('projectChapterAtmosphere.note.' + value)
        fragment = json.loads(self.read('Resources/ProjectChapterAtmosphereLocalizations.fragment.json'))
        self.assertEqual(fragment['sourceLanguage'], 'en')
        self.assertEqual(set(fragment['strings']), keys)
        for entry in fragment['strings'].values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            for value in entry['localizations'].values():
                self.assertTrue(value['stringUnit']['value'].strip())
        for token in ['checkmark.circle.fill', '.isSelected', '.accessibilityValue(', '.fixedSize(horizontal: false, vertical: true)']:
            self.assertIn(token, host)

    def test_source_swatches_have_readable_foreground_contrast(self):
        def luminance(rgb):
            channels = [(rgb >> shift & 255) / 255 for shift in [16, 8, 0]]
            linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
            return sum(c * weight for c, weight in zip(linear, [0.2126, 0.7152, 0.0722]))
        for bg, fg in [(0x0A0A0A, 0xFFFFFF), (0x14294F, 0xFFFFFF), (0x4E1C24, 0xFFFFFF), (0x4E4114, 0xFFFFFF), (0xF5F6F8, 0x111318)]:
            low, high = sorted([luminance(bg), luminance(fg)])
            self.assertGreaterEqual((high + 0.05) / (low + 0.05), 4.5)

    def test_authored_lifecycle_coverage_does_not_expand_ui_ci(self):
        core = self.read('Tests/CoreTests/ProjectChapterAtmosphereTests.swift')
        lifecycle = self.read('Tests/AppUnitTests/ProjectChapterAtmosphereLifecycleTests.swift')
        self.assertEqual(core.count('func test'), 11)
        self.assertEqual(lifecycle.count('func test'), 10)
        for token in ['"deleteABA"', '"contentABA"', 'scope: .whitelist', 'product: .freeExplore',
                      'fresh.restore()', 'storage.failAt = storage.writes + offset',
                      'service.submissions.isEmpty', 'replacement.select(.red, captured: tap)']:
            self.assertIn(token, lifecycle)
        self.assertFalse((ROOT / 'Tests/AppUITests/ProjectChapterAtmosphereFlowTests.swift').exists())


if __name__ == '__main__':
    unittest.main()
