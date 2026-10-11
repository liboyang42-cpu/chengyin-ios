"""Focused source contracts only; no native Swift, Apple, or backend execution."""
import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class D6RehearsalChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / 'Core/TemplateD6Rehearsal.swift').read_text()
        cls.app = (ROOT / 'App/TemplateD6RehearsalView.swift').read_text()
        cls.form = (ROOT / 'App/TemplateAdvancedGameConfigurationView.swift').read_text()
        cls.core_tests = (ROOT / 'Tests/CoreTests/TemplateD6RehearsalTests.swift').read_text()
        cls.app_tests = (ROOT / 'Tests/AppUnitTests/TemplateD6RehearsalControllerTests.swift').read_text()

    def test_new_d6_entry_keeps_existing_editor_and_other_previews(self):
        for token in ['TemplateD6RehearsalView(model: model)', 'TemplateD6Rehearsal(draft: model.draft.advanced)',
                      'field(game.section, "diceCount")', 'model.draft.advanced.setFace(index, $0)',
                      'TemplateD20ConfigurationView(model: model)', 'TemplateMiniGameConfigurationView(model: model, game: game)']:
            self.assertIn(token, self.form)

    def test_samples_use_current_valid_d6_section_and_existing_validation(self):
        for token in ['draft.enabled("diceRoll")', 'draft.diceMode == "d6"', 'fields["mode"]?.string == "d6"',
                      'isolated.value["diceRoll"] = .object(fields)', 'isolated.issues.isEmpty',
                      'fields["diceCount"]?.integer ?? 1', 'trimmingCharacters(in: .whitespacesAndNewlines)']:
            self.assertIn(token, self.core)

    def test_one_die_maps_action_and_two_dice_only_sum(self):
        for token in ['pips.count == diceCount', 'pips.allSatisfy({ (1...6).contains($0) })',
                      'total: pips.reduce(0, +)', 'action: diceCount == 1 ? faces[pips[0] - 1] : nil']:
            self.assertIn(token, self.core)
        self.assertNotIn('faces[pips.reduce', self.core)
        self.assertIn('templateD6.sumOnly', self.app)

    def test_choose_show_reset_reload_are_mounted(self):
        for token in ['controller.pip(index)', 'controller.sampleAction()', 'controller.resetAction()',
                      'controller.reload()', 'controller.visibleSample', 'templateD6.sampleOnly',
                      'self.lastSample = nil; self.pips[index] = value', 'self.pips == values']:
            self.assertIn(token, self.app)

    def test_all_captured_samples_and_controls_are_owner_lifecycle_fenced(self):
        for token in ['model.objectWillChange.sink', 'self?.retire()', 'model.canReadStoryDraft', 'model.canEdit',
                      'model.coordinator.session == session', 'model.coordinator.identity == identity',
                      'model.metadataGeneration == metadataGeneration', 'model.mediaReviewGeneration == mediaGeneration',
                      'self.generation == stamp', 'configuration = nil; pips = []; lastSample = nil',
                      '.onAppear { controller.reload() }', '.onDisappear { controller.retire() }']:
            self.assertIn(token, self.app)

    def test_read_only_and_no_player_roll_authority(self):
        for token in ['URLSession', 'HTTPTransport', 'ROLL_DICE', 'random(', 'RandomNumberGenerator', 'model.changed()',
                      'coordinator.change(', 'model.save(', 'model.draft =', 'model.draft.advanced =', 'PlayKitScreen(', 'capabilityGrant']:
            self.assertNotIn(token, self.core + self.app)
        self.assertNotIn('Codable', self.core)

    def test_localization_and_registration_fragments(self):
        fragment = json.loads((ROOT / 'docs/localization/template-d6-rehearsal.json').read_text())['strings']
        localized_source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', "", self.app + self.form)
        keys = set(re.findall(r'"(templateD6\.[^"\\]+)"', localized_source))
        self.assertTrue(keys <= set(fragment), keys - set(fragment))
        self.assertIn('templateD6.dieNumber %lld', fragment)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])
        registration = json.loads((ROOT / 'docs/registration/template-d6-rehearsal.json').read_text())
        for key in ['app_sources', 'app_unit_tests', 'package_tests']:
            for path in registration[key]: self.assertTrue((ROOT / path).is_file())

    def test_authored_native_tests_cover_complete_flow_and_local_persistence(self):
        for token in ['testEverySingleDieExampleUsesItsConfiguredFace', 'testAllTwoDiceCombinationsOnlyShowPipsAndTotal',
                      'testInvalidFacesAndUnknownDiceFieldsKeepExistingValidation', 'testSampleRejectsWrongCountOrOutOfRangeValues',
                      'testLocalDraftRoundTripRetainsConfigurationButNoSampleState']:
            self.assertIn(token, self.core_tests)
        for token in ['testChooseShowAndRepeatSingleDieSamplesWithoutAnyDraftWrite',
                      'testResetClearsResultAndRetiresRetainedPipAndShowControls',
                      'testDraftEditSynchronouslyRetiresSamplesBeforeParentOnChangeAndReloadsExplicitly',
                      'testLoadRestoreDiscardLeaveDismissAndOwnerChangeFenceEveryControl',
                      'testExistingLocalSaveFreshRestoreKeepsConfigWithoutSampleState',
                      'testPendingWriteLockDoesNotPermitRehearsalOrAnyDraftMutation']:
            self.assertIn(token, self.app_tests)

if __name__ == '__main__': unittest.main()
