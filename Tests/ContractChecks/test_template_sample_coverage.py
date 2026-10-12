import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TemplateSampleCoverageContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateAdditionalSamplePreview.swift').read_text()
        cls.app = (ROOT / 'App/TemplateAdditionalSampleBrowserView.swift').read_text()
        cls.host = (ROOT / 'App/TemplateSampleBrowserView.swift').read_text()

    def test_four_choices_and_original_seven_remain_separate(self):
        self.assertIn('case predict, pricePair, dice, d20', self.core)
        old = (ROOT / 'Core/TemplateSamplePreview.swift').read_text()
        self.assertIn('case qaText, qaPick, estimate, random, profile, note, typeIn', old)
        self.assertEqual(self.host.count('TemplateAdditionalSampleBrowserView(model: model)'), 1)

    def test_existing_rehearsals_reused_without_new_game_algorithm(self):
        for token in ['TemplateCreatorRehearsalView(draft:', 'TemplateD20RehearsalView(draft:', 'TemplateD6Rehearsal(draft:']:
            self.assertIn(token, self.app)
        for token in ['rehearsal.evaluate(', 'Int.random', 'Double.random', 'total =', 'PlayKitReasoningForm(', 'PlayKitSensorChallengeView(']:
            self.assertNotIn(token, self.app)
        self.assertIn('TemplateCreatorConfigurationView(model: model, family: family)', self.app)
        self.assertIn('TemplateAdvancedGameConfigurationView(model: model, game: .dice)', self.app)

    def test_only_current_pristine_fields_seed_in_value_copy(self):
        for token in ['var copy = original', 'let current = fields[key]', 'let expected = defaults[key]', 'bytes == Self.bytes(expected)', 'copy.value[choice.section] = .object(fields)']:
            self.assertIn(token, self.core)
        self.assertNotIn('model.draft =', self.app)
        self.assertNotIn('model.draft.advanced.set', self.app)

    def test_d20_mode_initialization_is_existing_copy_only_operation(self):
        self.assertIn('if copy.diceMode != "d20" { copy.setDiceMode("d20") }', self.core)
        self.assertIn('pristine.setDiceMode("d20")', self.core)
        self.assertIn('(try? TemplateD20Rehearsal(draft: copy)) == nil', self.core)
        self.assertIn('(try? TemplateD6Rehearsal(draft: copy)) == nil', self.core)
        self.assertNotIn('setDiceMode(', self.app)

    def test_fixed_d6_adapter_and_reset(self):
        self.assertIn('configuration.sample(pips: configuration.diceCount == 2 ? [5, 4] : [5])', self.app)
        self.assertIn('Button("creator.reset") { sample = nil }', self.app)
        self.assertIn('if let action = sample.action', self.app)
        self.assertIn('Text("templateD6.sumOnly")', self.app)

    def test_model_staleness_and_identity_fences(self):
        for token in ['model.objectWillChange.sink', 'self?.close()', 'owner == model.coordinator.session', 'identity == model.coordinator.identity', 'current.metadata == model.metadataGeneration', 'current.media == model.mediaReviewGeneration', 'self.generation == token', 'source == TemplateSamplePreview.snapshot(self.model.draft)', 'Publishers.CombineLatest(model.$busy, model.$review)', '.onDisappear { controller.viewDisappeared() }', 'controller.close(expected: presentationID)']:
            self.assertIn(token, self.app)

    def test_no_permission_media_transport_or_durable_side_effect(self):
        for token in ['AsyncImage', 'URLSession', 'FileManager', 'UserDefaults', 'model.changed(', 'model.prepare(', 'model.confirm(', 'requestAuthorization', 'capabilityGrant', 'AVFoundation', 'PhotosUI', 'startUpdating', 'PlayKitNativeSensorProvider']:
            self.assertNotIn(token, self.app + self.core)
        self.assertEqual(self.app.count('Text("templateSampleCoverage.nameOnly")'), 2)

    def test_four_source_demo_objects_are_bounded(self):
        data = json.loads(self.core.split('private static let demoJSON = #"""\n', 1)[1].split('\n"""#', 1)[0])
        self.assertEqual(set(data), {'predict', 'pricePair', 'dice', 'd20'})
        self.assertEqual(len(data['dice']['faces']), 6)
        self.assertEqual(data['dice']['faces'][4], '把杯子摆正')
        self.assertEqual(len(data['pricePair']['items']), 3)
        self.assertNotIn('module.exports', self.core)

    def test_registration_and_nine_bilingual_keys(self):
        strings = json.loads((ROOT / 'docs/localization/template-sample-coverage.json').read_text())['strings']
        self.assertEqual(len(strings), 9)
        for item in strings.values():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(item['localizations'][locale]['stringUnit']['value'])
        used = set(re.findall(r'(?:Text|Button|NavigationLink)\("(templateSampleCoverage\.[a-zA-Z]+)"', self.app + self.host))
        self.assertTrue(used.issubset(strings))
        registration = json.loads((ROOT / 'docs/registration/template-sample-coverage.json').read_text())
        self.assertEqual(registration['dependencies'], ['creator-sample-browser-0772737'])
        for name in registration['app_sources'] + registration['package_tests'] + registration['app_unit_tests']:
            self.assertTrue((ROOT / name).is_file())

    def test_native_tests_authored_and_audit_limits_disclosed(self):
        for name, count in [('Tests/CoreTests/TemplateAdditionalSamplePreviewTests.swift', 12), ('Tests/AppUnitTests/TemplateAdditionalSampleBrowserTests.swift', 15)]:
            self.assertEqual(len(re.findall(r'func test', (ROOT / name).read_text())), count)
        doc = (ROOT / 'docs/template-sample-coverage.md').read_text()
        for token in ['32 primary entries', '10 modifiers', 'all42', 'key/next', 'id/nextStepId', 'NOT_RUN', 'name-only', 'Encounter-only', 'not repaired here']:
            self.assertIn(token, doc)

    def test_hidden_parent_cannot_reload_and_owned_sheet_lifetime_stays_stable(self):
        for token in ['private(set) var isVisible = false', 'private var sceneActive = false',
                      'isVisible && sceneActive && active && model.canEdit',
                      'func viewDisappeared() { isVisible = false; retire() }',
                      'guard isVisible && sceneActive else { retire(); return }',
                      'if !active { reload() }', 'if becameActive || !active { reload() }',
                      'controller.viewAppeared(sceneIsActive: scenePhase == .active)',
                      'controller.mediaChanged(sceneIsActive: scenePhase == .active)',
                      'controller.sceneChanged(isActive: phase == .active)']:
            self.assertIn(token, self.app)
        self.assertNotIn('self.model = model; reload()', self.app)
        self.assertEqual(self.app.count('.sheet(item: controller.presentationBinding)'), 1)
        self.assertIn('controller.close(expected: presentationID)', self.app)
        self.assertLess(self.app.index('}.navigationTitle('), self.app.index('.sheet(item: controller.presentationBinding)'))

    def test_presentation_binding_getter_is_same_captured_visible_identity(self):
        binding = self.app.split('var presentationBinding:')[1].split('\n}')[0]
        getter = binding.split('}, set:')[0]
        self.assertIn('let expected = presentation?.id', binding)
        self.assertIn('let expected, let current = self.visiblePresentation', getter)
        self.assertIn('current.id == expected else { return nil }', getter)
        self.assertIn('return current', getter)
        self.assertNotIn('self?.presentation', getter)
        self.assertIn('if value == nil, let expected { self?.close(expected: expected) }', binding)
        tests = (ROOT / 'Tests/AppUnitTests/TemplateAdditionalSampleBrowserTests.swift').read_text()
        self.assertIn('testPresentationBindingReadsOnlyCapturedIdentityIncludingInitialNilAndSameChoiceReopen', tests)
        self.assertIn('testPresentationBindingUsesVisibleLeaseAndCannotReadHiddenOwnerReentry', tests)
