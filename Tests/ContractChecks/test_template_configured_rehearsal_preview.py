import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class TemplateConfiguredRehearsalPreviewContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = (ROOT/'App/TemplateConfiguredRehearsalPreview.swift').read_text()
        cls.host = (ROOT/'App/TemplateAuthoringView.swift').read_text()
    def test_normal_preview_preserves_summary_and_existing_routes(self):
        self.assertIn('TemplateConfiguredRehearsalPreview(model: model) { TemplateAuthoringPreviewView(draft: model.draft) }', self.host)
        for token in ['TemplateMiniGamePreviewView(draft: draft.advanced, game: game)', 'TemplateD20RehearsalView(draft: draft.advanced)', 'TemplateCreatorRehearsalView(draft: draft.advanced, family: family)', 'TemplateRootRehearsalView(draft: draft.advanced)', 'TemplatePreferencePreviewView(raw: raw)', 'templateAuthor.noGameplay']:
            self.assertIn(token, self.host)
        self.assertIn('TemplateConfiguredRehearsalPreviewButton(controller: configuredRehearsals, game: game)', self.host)
    def test_five_existing_current_configuration_destinations_only(self):
        for token in ['TemplateCoinFlipRehearsalView(model: model, mode: .currentConfiguration)', 'TemplateD6RehearsalView(model: model)', 'TemplateReactionRehearsalView(model: model, mode: .currentConfiguration)', 'TemplateTimerRehearsalView(model: model, kind: .countdown, mode: .currentConfiguration)', 'TemplateTimerRehearsalView(model: model, kind: .stopwatch, mode: .currentConfiguration)']:
            self.assertEqual(self.app.count(token), 1)
        self.assertNotIn('.sourceExample', self.app)
        self.assertIn('draft.advanced.diceMode == "d6"', self.app)
        self.assertIn('guard supported && draft.advanced.enabled(game.section)', self.app)
    def test_fixed_snapshot_owner_and_publication_fences(self):
        for token in ['let draft: TemplateAuthoringDraft', 'source = TemplateSamplePreview.snapshot(model.draft)', 'owner == model.coordinator.session', 'identity == model.coordinator.identity', 'metadata == model.metadataGeneration && media == model.mediaReviewGeneration', 'source == TemplateSamplePreview.snapshot(model.draft)', 'model.objectWillChange.sink', 'self?.retire()', '!model.busy && model.review == nil']:
            self.assertIn(token, self.app)
    def test_stable_sheet_owner_and_observed_lazy_buttons(self):
        self.assertEqual(self.app.count('@StateObject'), 1)
        shell = self.app.split('@MainActor struct TemplateConfiguredRehearsalPreview<Content: View>')[1].split('@MainActor private struct')[0]
        self.assertIn('NavigationStack(path: controller.navigationPath)', shell)
        self.assertIn('        }\n        .onAppear { controller.viewAppeared', shell)
        self.assertNotIn('.id(', shell)
        rows = self.app.split('/// Lazy summary rows')[1]
        self.assertEqual(rows.count('@ObservedObject'), 3)
        self.assertNotIn('@StateObject', rows); self.assertNotIn('.sheet(', rows)
    def test_hidden_background_and_repeated_appearance_boundaries(self):
        for token in ['active && !retired && !didClose && isVisible && sceneActive', 'guard !retired && !didClose && sceneActive', 'if !active { generation = UUID(); active = true }', 'func viewDisappeared() { isVisible = false; retire() }', 'if !isActive { retire() }', 'generation = UUID(); retired = true; active = false; path = []']:
            self.assertIn(token, self.app)
        phase = self.app.split('func sceneChanged')[1].split('private func retire')[0]
        self.assertNotIn('active = true', phase)
    def test_old_route_pop_and_dismiss_cannot_touch_new_identity(self):
        for token in ['struct Destination: Hashable { let id = UUID(); let route: Route }', 'guard path == [destination]', 'self.generation == stamp', 'self.path == expected', '!expected.isEmpty, value.isEmpty', 'self.path = [.init(route: route)]', 'self.didClose = true; self.retire(); dismiss()']:
            self.assertIn(token, self.app)
        self.assertIn('TemplateConfiguredRehearsalCloseButton(controller: configuredRehearsals)', self.host)
        getter = self.app.split('var navigationPath:')[1].split('}, set:')[0]
        self.assertIn('self.isCurrent, self.generation == stamp, self.path == expected', getter)
        self.assertIn('return expected', getter)
        self.assertNotIn('self?.path ?? []', getter)
    def test_no_new_capability_or_configuration_write(self):
        for token in ['URLSession', 'AVPlayer', 'PhotosPicker', 'CoreMotion', 'capabilityGrant', 'ProductionTransport', 'model.save(', 'model.prepare(', 'model.changed(', 'model.draft =', '.setGameEnabled(', '.setDiceMode(', 'Timer.publish', 'Task {', 'Double.random']:
            self.assertNotIn(token, self.app)
    def test_resources_registration_and_authored_negative_controls(self):
        strings = json.loads((ROOT/'Resources/TemplateConfiguredRehearsal.xcstrings').read_text())['strings']
        self.assertEqual(len(strings), 2)
        for value in strings.values():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
        reg = json.loads((ROOT/'docs/registration/template-configured-rehearsal-preview.json').read_text())
        for key in ['app_sources', 'app_unit_tests', 'resources']:
            for path in reg[key]: self.assertTrue((ROOT/path).is_file())
        tests = (ROOT/'Tests/AppUnitTests/TemplateConfiguredRehearsalPreviewTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test', tests)), 22)
        for name in ['testOldPopAndDestinationCannotAffectReopenedSameRoute', 'testHiddenForegroundAndOldCallbacksCannotReviveSnapshot', 'testDraftABAAndBusyABARequireANewSheetOwner', 'testHostedNormalSummaryPushBackKeepsOuterOwnerLive', 'testHostedDetachRetiresAndOldPopCannotCloseNewHostRoute']:
            self.assertIn(name, tests)
        self.assertIn('testOldPathGetterCannotObserveReopenedRouteOrFreshOwner', tests)
        self.assertIn('testEnteringAndActingInAllFiveRehearsalsDoesNotPublishParentModel', tests)
        self.assertIn('XCTAssertEqual(publications, 0)', tests)
        self.assertIn('NOT_RUN', (ROOT/'docs/template-configured-rehearsal-preview.md').read_text())

    def test_normal_legacy_question_route_reuses_complete_attempt_page(self):
        for token in ['TemplateLegacyQuestionRehearsal(draft)', 'return rehearsal.isAvailable && rehearsal.isConfigured ? model : nil', 'case .legacyQuestion: TemplateLegacyQuestionRehearsalView(model: model)', 'self.canOpenLegacyQuestion', 'self.path = [.init(route: .legacyQuestion)]']:
            self.assertIn(token, self.app)
        self.assertIn('TemplateConfiguredLegacyRehearsalPreviewButton(controller: configuredRehearsals)', self.host)
        self.assertIn('Button("templateLegacyQuiz.title", action: controller.openLegacyQuestionAction())', self.app)
        tests = (ROOT/'Tests/AppUnitTests/TemplateConfiguredRehearsalPreviewTests.swift').read_text()
        for name in ['testNormalLegacyTextAndChoiceUseActualAnswerHintAndSubmitWithoutParentWrite', 'testNormalLegacyRouteRejectsAdvancedPrimaryDisabledAndIncompleteQuestions', 'testNormalLegacyOldOpenReadPopAndDestinationCannotCrossReopenOrHide', 'testHostedNormalLegacyPreviewEntryKeepsOwnerAndAllowsBack']:
            self.assertIn(name, tests)
        reg = json.loads((ROOT/'docs/registration/template-normal-legacy-preview.json').read_text())
        self.assertEqual(reg['new_build_members'], [])
        for path in reg['reused_sources']: self.assertTrue((ROOT/path).is_file())
