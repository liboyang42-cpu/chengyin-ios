"""Supplementary native source checks. These do not execute Swift or Apple UI."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class TemplateLegacyHintChecks(unittest.TestCase):
    def test_only_local_optional_intent_is_added_and_existing_wire_gate_is_used(self):
        domain = read('Core/TemplateAuthoringDomain.swift')
        self.assertIn('public var legacyHintsEnabled: Bool?', domain)
        self.assertIn('validationMethod != oldValue && !validationMethod.supportsLegacyHints', domain)
        contract = read('Core/TemplateAuthoringContract.swift')
        self.assertIn('d.validationMethod.supportsLegacyHints && d.legacyHintsAreEnabled', contract)
        for flag in ['hintEnabled', 'legacyHintsEnabled']:
            self.assertNotIn('"' + flag + '"', contract)
        self.assertIn('guard !d.validationMethod.isLocalConfigurationOnly', contract)
        self.assertIn('fields["id"] == nil', contract)

    def test_hydration_is_read_only_and_off_is_explicit(self):
        core = read('Core/TemplateLegacyHints.swift')
        self.assertIn('legacyHintsEnabled ?? [hint1, hint2, answerReveal].contains', core)
        self.assertIn('if !enabled { hint1 = ""; hint2 = ""; answerReveal = "" }', core)
        self.assertIn('guard legacyHintControlsVisible, legacyHintsAreEnabled', core)
        self.assertNotIn('trimmingCharacters', core)
        self.assertNotIn('maximum', core)

    def test_primary_predicate_is_read_only_and_does_not_conflate_modifiers(self):
        core = read('Core/TemplateLegacyHints.swift').split('var hasLegacyHintPrimaryGame: Bool')[1]
        for primary in ['album', 'profile', 'note', 'photoCheck', 'check', 'typeIn', 'qa', 'diceRoll']:
            self.assertIn('"' + primary + '"', core)
        for modifier in ['timer', 'leaderboard', 'multiplayer', 'compare', 'blindTaste']:
            self.assertNotIn('"' + modifier + '"', core)
        self.assertIn('["TYPE", "PICK", "SHOT"].contains(mode)', core)
        self.assertIn('["d6", "d20"].contains(text)', core)
        for mutation in ['set(', 'setGameEnabled', '.value =', 'URLSession', 'Task {']:
            self.assertNotIn(mutation, core)

    def test_editor_and_read_only_owner_inspection_keep_separate_hint_rendering(self):
        forms = read('App/TemplateAuthoringDetailForms.swift')
        self.assertIn('includesHints: false)', forms)
        self.assertIn('TemplateLegacyHintFields(model: model)', forms)
        self.assertIn('var includesHints = true', forms)
        self.assertIn('if includesHints && [.text, .choice, .gps].contains(method)', forms)
        owner = read('App/OwnedTemplateConfigurationView.swift')
        self.assertIn('TemplateAuthoringQAFields(method: method', owner)
        self.assertIn('readOnly: true', owner)
        self.assertNotIn('legacyHints', owner)

    def test_new_bindings_are_fenced_before_mutation_and_commit_immediately(self):
        app = read('App/TemplateLegacyHintFields.swift')
        self.assertIn('canReadLegacyHints && coordinator.session == session && coordinator.identity == identity && legacyHintGeneration == generation', app)
        for name in ['legacyHintMethodBinding', 'legacyHintToggle', 'legacyHint']:
            section = app.split('func ' + name + '(')[1].split('\n    }')[0]
            self.assertIn('legacyHintLeaseIsCurrent(session, identity, generation)', section)
            self.assertIn('guard self.canEdit, self.legacyHintLeaseIsCurrent', section)
            self.assertIn('self.changed()', section)
        model = read('App/TemplateAuthoringView.swift')
        self.assertIn('var canReadLegacyHints: Bool { coordinator.session != nil && epoch == coordinator.session && draftIdentity == coordinator.identity }', model)
        self.assertIn('self.legacyHintLeaseIsCurrent(session, identity, generation) ? self.draft.validationMethod : .manual', app)
        for method in ['func load()', 'func restore()', 'func discard()']:
            self.assertIn('legacyHintGeneration = UUID()', model.split(method)[1].split('\n    }')[0])
        self.assertIn('selection: model.legacyHintMethodBinding()', model)
        for network in ['.prepare(', '.confirm(', '.submit(', 'URLSession', 'Task {']:
            self.assertNotIn(network, app)

    def test_localization_is_complete_and_warning_explains_all_cleared_values(self):
        labels = json.loads(read('tools/template_legacy_hint_localizations.json'))
        catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(set(labels), {'templateLegacyHints.enabled', 'templateLegacyHints.clearNotice'})
        for key, translations in labels.items():
            self.assertEqual(set(translations), {'en', 'zh-Hans'})
            for language, text in translations.items():
                self.assertTrue(text)
                self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], text)
        self.assertIn('fallback answer', labels['templateLegacyHints.clearNotice']['en'])

    def test_authored_tests_cover_migration_suppression_and_lifecycle(self):
        core = read('Tests/CoreTests/TemplateLegacyHintTests.swift')
        for name in ['testMissingFlagInfersAnyNonemptyStringWithoutTrimmingOrMutating',
                     'testExplicitOffClearsExactlyThreeStringsAndDoesNotTouchAdvancedAnswers',
                     'testUnsupportedRoundTripDisablesWithoutClearingOrSilentlyReenabling',
                     'testPayloadSuppressesDisabledUnsupportedAndFinishOffWithoutMutating',
                     'testLocalOnlyMethodsStillCannotProduceRemoteRequestsOrPayloads',
                     'testModifiersAndUnknownSectionsDoNotHideLegacyHints',
                     'testExactHistoricalValuesAndUnknownOtherDataRoundTripUntilExplicitEdit']:
            self.assertIn(name, core)
        app = read('Tests/AppUnitTests/TemplateLegacyHintLifecycleTests.swift')
        for name in ['testChildNavigationRepeatedEditsSaveAndReopenPreserveIntentAndText',
                     'testRetainedBindingsCannotCrossAccountEpochOrRoleAfterReload',
                     'testDiscardAndSameOwnerReloadInvalidateRetainedCallbacks',
                     'testRestoreDoesNotNormalizeLegacyDraftAndFencesPreRestoreBindings',
                     'testLogoutHidesFreshAndRetainedBindingsBeforeReload',
                     'testLockedSubmissionRejectsHintAndMethodCallbacks']:
            self.assertIn(name, app)
        for check in ['XCTAssertTrue(model.canReadLegacyHints); XCTAssertFalse(model.canEdit)',
                      'XCTAssertEqual(model.legacyHint(.hint1).wrappedValue, "first")',
                      'XCTAssertEqual(model.legacyHint(.hint1).wrappedValue, "")']:
            self.assertIn(check, app)


if __name__ == '__main__': unittest.main()
