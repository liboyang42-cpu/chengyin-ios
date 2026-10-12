import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TemplateSampleBrowserSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateSamplePreview.swift').read_text()
        cls.app = (ROOT / 'App/TemplateSampleBrowserView.swift').read_text()
        cls.host = (ROOT / 'App/TemplateAuthoringDetailForms.swift').read_text()

    def test_single_catalogue_entry_and_existing_renderer_reuse(self):
        self.assertEqual(self.host.count('TemplateSampleBrowserView(model: model)'), 1)
        self.assertIn('TemplateSampleBrowserView(model: model)', self.host.split('struct TemplateAuthoringAdvancedView', 1)[1])
        self.assertEqual(self.app.count('TemplateCreatorRehearsalView('), 1)
        self.assertIn('TemplateCreatorConfigurationView(model: model, family: choice.family)', self.app)
        for token in ['rehearsal.evaluate(', 'startBranch(', 'tapHiddenObject(', 'AVPlayer', 'AsyncImage']:
            self.assertNotIn(token, self.app)

    def test_catalogue_is_explicitly_bounded_to_non_media_families(self):
        self.assertIn('case qaText, qaPick, estimate, random, profile, note, typeIn', self.core)
        family = self.core.split('public var family:', 1)[1].split('public var group:', 1)[0]
        for forbidden in ['.hiddenObject', '.photoCheck', '.album', '.scan', '.compass', '.shout']:
            self.assertNotIn(forbidden, family)

    def test_examples_only_replace_exact_pristine_fields_in_copy(self):
        for token in ['let current = fields[key]', 'let expected = pristine[key]', 'bytes == Self.bytes(expected)', 'var copy = original', 'copy.value[choice.family.rawValue] = .object(fields)', 'fields["mode"] = .string("PICK")']:
            self.assertIn(token, self.core)
        self.assertNotIn('setCreatorEnabled(', self.app)
        self.assertNotIn('model.draft =', self.app)
        self.assertNotIn('model.draft.advanced.set', self.app)

    def test_demo_data_is_bounded_well_formed_and_source_identifiable(self):
        raw = self.core.split('private static let demoJSON = #"""\n', 1)[1].split('\n"""#', 1)[0]
        data = json.loads(raw)
        self.assertEqual(set(data), {'qaText', 'qaPick', 'estimate', 'random', 'profile', 'note', 'typeIn'})
        self.assertEqual(data['qaText']['answerText'], '1937')
        self.assertEqual(data['typeIn']['seconds'], 20)
        self.assertEqual(len(data['random']['items']), 3)
        self.assertNotIn('module.exports', self.core)
        self.assertNotIn('require(', self.core)

    def test_stale_snapshot_session_lock_and_lifecycle_guards(self):
        for token in ['owner == model.coordinator.session', 'identity == model.coordinator.identity', 'current.metadata == model.metadataGeneration', 'current.media == model.mediaReviewGeneration', 'model.$draft.dropFirst()', 'self.generation == token', 'metadata == self.model.metadataGeneration', 'source == TemplateSamplePreview.snapshot(self.model.draft)', 'Publishers.CombineLatest(model.$busy, model.$review)', '.onDisappear { controller.viewDisappeared() }']:
            self.assertIn(token, self.app)
        self.assertIn('presentation?.id != expected', self.app)
        self.assertIn('controller.close(expected: presentationID)', self.app)

    def test_no_persistence_permissions_or_transport_added(self):
        for token in ['model.save(', 'model.changed(', 'model.prepare(', 'model.confirm(', 'URLSession', 'ProductionTransport', 'capabilityGrant', 'requestAuthorization', 'PlayKitNativeSensorProvider', 'FileManager', 'UserDefaults']:
            self.assertNotIn(token, self.core + self.app)
        self.assertNotIn('publishIssues', self.app)

    def test_registration_and_bilingual_ui_fragments(self):
        strings = json.loads((ROOT / 'docs/localization/template-sample-browser.json').read_text())['strings']
        self.assertEqual(len(strings), 18)
        used = set(re.findall(r'(?:Text|Button|NavigationLink)\("(templateSamples\.[a-zA-Z]+)"', self.app + self.host))
        self.assertTrue(used.issubset(strings), used - set(strings))
        for value in strings.values():
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][lang]['stringUnit']['value'])
        registration = json.loads((ROOT / 'docs/registration/template-sample-browser.json').read_text())
        self.assertEqual(registration['dependencies'], [])
        for path in registration['app_sources'] + registration['package_tests'] + registration['app_unit_tests']:
            self.assertTrue((ROOT / path).is_file())

    def test_native_cases_authored_and_limits_explicit(self):
        for name, count in [('Tests/CoreTests/TemplateSamplePreviewTests.swift', 10), ('Tests/AppUnitTests/TemplateSampleBrowserViewTests.swift', 15)]:
            self.assertEqual(len(re.findall(r'func test', (ROOT / name).read_text())), count)
        doc = (ROOT / 'docs/template-sample-browser.md').read_text()
        for token in ['NOT_RUN', 'not the entire Mini catalogue', 'original family editor', 'Private original Mini source']:
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
        tests = (ROOT / 'Tests/AppUnitTests/TemplateSampleBrowserViewTests.swift').read_text()
        self.assertIn('testPresentationBindingReadsOnlyCapturedIdentityIncludingInitialNilAndSameChoiceReopen', tests)
        self.assertIn('testPresentationBindingUsesVisibleLeaseAndCannotReadHiddenOwnerReentry', tests)
