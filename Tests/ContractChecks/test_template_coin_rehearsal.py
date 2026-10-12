import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TemplateCoinRehearsalContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateCoinFlipRehearsal.swift').read_text()
        cls.app = (ROOT / 'App/TemplateCoinFlipRehearsalView.swift').read_text()
        cls.config = (ROOT / 'App/TemplateAdvancedGameConfigurationView.swift').read_text()
        cls.browser = (ROOT / 'App/TemplateAdditionalSampleBrowserView.swift').read_text()

    def test_two_exact_entry_modes_and_prior_choices_retained(self):
        self.assertEqual(self.config.count('TemplateCoinFlipRehearsalView(model: model, mode: .currentConfiguration)'), 1)
        self.assertEqual(self.browser.count('TemplateCoinFlipRehearsalView(model: model, mode: .sourceExample)'), 1)
        self.assertIn('TemplateD6RehearsalView(model: model)', self.config)
        self.assertIn('TemplateAdditionalSamplePreview.Choice.allCases', self.browser)
        old = (ROOT / 'Core/TemplateSamplePreview.swift').read_text()
        self.assertIn('case qaText, qaPick, estimate, random, profile, note, typeIn', old)

    def test_source_projection_and_exact_pristine_demo_boundary(self):
        for token in ['if mode == .sourceExample', 'let current = fields[key]', 'let expected = defaults[key]', 'bytes == Self.bytes(expected)', 'var copy = original', 'TemplateAuthoringStory.sourceTrim(text)', 'fallback: "抛一次,认结果"', 'fallback: "正面"', 'fallback: "反面"']:
            self.assertIn(token, self.core)
        demo = json.loads(self.core.split('private static let demoJSON = #"""\n', 1)[1].split('\n"""#', 1)[0])
        self.assertEqual(set(demo), {'kicker', 'heads', 'tails'})
        self.assertEqual(demo['heads']['action'], '这杯店家请')
        self.assertEqual(demo['tails']['action'], '你请下一杯')

    def test_deterministic_face_result_selection_and_reset(self):
        for token in ['case heads = "HEADS", tails = "TAILS"', 'selection: Face = .heads', 'face == .heads ? heads : tails', 'selection = face; result = nil', 'result = .init(face: selection, side: side(selection))', 'selection = .heads; result = nil']:
            self.assertIn(token, self.core)
        for token in ['random(', 'SystemRandom', 'Timer', 'Task.sleep', 'DispatchQueue']:
            self.assertNotIn(token, self.core + self.app)

    def test_both_sides_show_again_reset_close_and_reentry_exist(self):
        for token in ['side(state.heads, key:', 'side(state.tails, key:', 'Button("templateCoin.show"', 'Button("templateCoin.again"', 'Button("creator.reset"', 'controller.closeAction { dismiss() }', '.onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }', '.onDisappear { controller.viewDisappeared() }']:
            self.assertIn(token, self.app)
        self.assertIn('Text(verbatim: result.side.label)', self.app)
        self.assertIn('Text(verbatim: result.side.action)', self.app)

    def test_snapshot_owner_exact_draft_and_lock_fences(self):
        for token in ['model.objectWillChange.sink', 'self?.retire()', 'owner == model.coordinator.session', 'identity == model.coordinator.identity', 'metadata == model.metadataGeneration', 'media == model.mediaReviewGeneration', 'source == TemplateSamplePreview.snapshot(model.draft)', '!model.busy && model.review == nil']:
            self.assertIn(token, self.app)

    def test_old_bindings_show_reset_and_close_are_generation_scoped(self):
        self.assertGreaterEqual(self.app.count('let stamp = generation'), 4)
        self.assertGreaterEqual(self.app.count('self.generation == stamp'), 5)
        self.assertIn('self.retire(); dismiss()', self.app)
        self.assertIn('controller.sceneChanged(isActive: phase == .active)', self.app)

    def test_no_hardware_finance_player_or_durable_effect_path(self):
        for token in ['URLSession', 'AsyncImage', 'FileManager', 'UserDefaults', 'AVFoundation', 'CoreMotion', 'startAccelerometer', 'haptic(', 'FLIP_COIN', 'triggerEvent', 'model.changed(', 'model.prepare(', 'model.confirm(', 'model.draft =', 'requestAuthorization', 'capabilityGrant']:
            self.assertNotIn(token, self.core + self.app)
        self.assertIn('.privacySensitive()', self.app)

    def test_type_damage_and_missing_nested_data_are_not_rebuilt(self):
        self.assertIn('guard var fields = original.value["coinFlip"]?.object else { return nil }', self.core)
        self.assertIn('guard fields[key] == nil || fields[key]?.object != nil else { return nil }', self.core)
        self.assertIn('guard let text = raw.string else { return nil }', self.core)
        self.assertNotIn('setNested(', self.core)

    def test_registration_and_fourteen_bilingual_keys(self):
        strings = json.loads((ROOT / 'docs/localization/template-coin-rehearsal.json').read_text())['strings']
        self.assertEqual(len(strings), 14)
        for item in strings.values():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(item['localizations'][locale]['stringUnit']['value'])
        used = set(re.findall(r'(?:Text|Button|Section|Picker|NavigationLink)\("(templateCoin\.[a-zA-Z]+)"', self.app + self.config + self.browser))
        self.assertTrue(used.issubset(strings), used - set(strings))
        registration = json.loads((ROOT / 'docs/registration/template-coin-rehearsal.json').read_text())
        self.assertEqual(len(registration['dependencies']), 2)
        for name in registration['app_sources'] + registration['package_tests'] + registration['app_unit_tests']:
            self.assertTrue((ROOT / name).is_file())

    def test_native_inventory_and_scope_disclosures(self):
        for path, count in [('Tests/CoreTests/TemplateCoinFlipRehearsalTests.swift', 12), ('Tests/AppUnitTests/TemplateCoinFlipRehearsalViewTests.swift', 15)]:
            self.assertEqual(len(re.findall(r'func test', (ROOT / path).read_text())), count)
        doc = (ROOT / 'docs/template-coin-rehearsal.md').read_text()
        for token in ['NOT_RUN', 'server-selected face', 'author-only inspection', 'Only coin is added', 'remain incomplete', 'fail closed', 'original', 'No animation timer']:
            self.assertIn(token, doc)

    def test_retained_hidden_destination_cannot_reactivate_on_foreground(self):
        for token in ['private(set) var isVisible = false', 'private var sceneActive = false',
                      'var canReload: Bool { isVisible && sceneActive && model.canReadStoryDraft',
                      'func viewDisappeared() { isVisible = false; retire() }',
                      'guard isVisible && sceneActive else { retire(); return }',
                      'if !active { reload() }', 'if becameActive || !active { reload() }',
                      'controller.viewAppeared(sceneIsActive: scenePhase == .active)',
                      'controller.sceneChanged(isActive: phase == .active)']:
            self.assertIn(token, self.app)
        self.assertNotIn('.onAppear { controller.reload() }', self.app)
        self.assertNotIn('if phase == .active { controller.reload() }', self.app)
