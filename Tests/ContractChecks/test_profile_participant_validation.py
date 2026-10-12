"""Focused source contracts only. These do not execute Swift or the iOS interface."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

def read(path): return (ROOT / path).read_text()

class ProfileParticipantValidationTests(unittest.TestCase):
    def setUp(self):
        self.core = read('Core/ProfileParticipantValidationReview.swift')
        self.app = read('App/ParticipantFormView.swift')
    def test_single_validation_authority(self):
        self.assertIn('draft.validation.map', self.core)
        self.assertIn('guard let validation = draft.validation', self.core)
        self.assertNotIn('regularExpression', self.core)
        self.assertNotIn('utf8', self.core)
    def test_review_stores_only_boolean(self):
        self.assertIn('public private(set) var hasRequestedReview = false', self.core)
        self.assertEqual(self.core.count('var '), 2)  # Boolean + computed messageKey
        for token in ['UserDefaults', 'FileManager', 'URLSession', 'sendRequest', 'print(']: self.assertNotIn(token, self.core)
    def test_request_reveals_first_issue(self):
        self.assertIn('hasRequestedReview = true', self.core)
        self.assertIn('return draft.validation.map { ProfileParticipantValidationField($0) }', self.core)
    def test_empty_form_is_quiet_until_check(self):
        self.assertIn('guard hasRequestedReview ||', self.core)
    def test_legacy_live_phone_hint(self):
        self.assertIn('validation == .invalidPhone && !draft.mobilePhone.isEmpty', self.core)
    def test_valid_changes_clear_feedback(self):
        self.assertIn('guard let validation = draft.validation else { return nil }', self.core)
    def test_error_to_field_is_explicit(self):
        self.assertIn('case .nameRequired: self = .name', self.core)
        self.assertIn('case .invalidPhone: self = .phone', self.core)
    def test_review_has_current_reader_and_mutation_guards(self):
        self.assertIn('canMutate && !busy && reader.isConfigured && coordinator.isConfigured', self.app)
        self.assertIn('loadedIdentity != nil && reader.identity == loadedIdentity', self.app)
        self.assertIn('guard canReviewForSave else { return nil }', self.app)
    def test_feedback_hidden_outside_editable_state(self):
        block = self.app.split('var validationIssue:')[1].split('/// Invalid')[0]
        self.assertIn('guard canReviewForSave else { return nil }', block)
    def test_valid_review_prepares_existing_confirmation_only(self):
        block = self.app.split('func reviewForSave()')[1].split('func sync()')[0]
        self.assertIn('let field = validationReview.request(in: draft)', block)
        self.assertIn('if field == nil { prepareSave() }', block)
        for forbidden in ['confirmMutation', 'coordinator.confirm', 'perform(', 'Task {']: self.assertNotIn(forbidden, block)
    def test_local_review_resets_on_load_and_disappear(self):
        self.assertEqual(self.app.count('validationReview = ProfileParticipantValidationReview()'), 3)
    def test_same_button_labels_check_and_save(self):
        self.assertIn('model.draft.validation == nil ? "participant.form.save" : "profile.participantValidation.check"', self.app)
        self.assertIn('.disabled(!model.canReviewForSave)', self.app)
        self.assertIn('.accessibilityIdentifier("participant.form.save")', self.app)
    def test_keyboard_and_button_focus_first_error(self):
        self.assertIn('@FocusState private var focusedField: ProfileParticipantValidationField?', self.app)
        self.assertEqual(self.app.count('focusedField = model.reviewForSave()'), 2)
    def test_feedback_accessible_and_localized(self):
        self.assertIn('Text(LocalizedStringKey(field.messageKey))', self.app)
        self.assertIn('"profile.participantValidation.issue." + field.rawValue', self.app)
    def test_existing_save_guard_is_retained(self):
        self.assertIn('canMutate && draft.validation == nil', self.app)
        self.assertIn('guard canSave, let identity = loadedIdentity else { return }', self.app)
        self.assertIn('confirmation = try coordinator.prepare(.save(draft), expectedIdentity: identity)', self.app)
    def test_does_not_add_visible_data_fields(self):
        self.assertEqual(self.app.count('TextField('), 2)
        self.assertNotIn('text: $model.draft.province', self.app)
        self.assertNotIn('UIPasteboard', self.app)
    def test_fragment_three_bilingual_keys(self):
        strings = json.loads(read('Resources/ProfileParticipantValidationLocalizations.fragment.json'))['strings']
        self.assertEqual(set(strings), {'profile.participantValidation.check', 'profile.participantValidation.name', 'profile.participantValidation.phone'})
        for row in strings.values():
            self.assertEqual(set(row['localizations']), {'en', 'zh-Hans'})
            for loc in row['localizations'].values(): self.assertTrue(loc['stringUnit']['value'])
    def test_fixture_reuses_existing_offline_module(self):
        doc = json.loads(read('docs/profile-participant-validation-registration.fragment.json'))
        self.assertEqual(doc['fixture_launch']['existing_module'], 'participants')
        self.assertEqual(doc['new_endpoints'], [])
        self.assertEqual(doc['central_files_modified'], [])
    def test_native_cases_cover_transition_and_no_write(self):
        core = read('Tests/CoreTests/ProfileParticipantValidationReviewTests.swift')
        app = read('Tests/AppUnitTests/ProfileParticipantValidationAppTests.swift')
        self.assertIn('testPhoneIsNextAfterFixingName', core)
        self.assertIn('testValidCorrectionClearsIssueWithoutAnotherAction', core)
        for name in ['testInvalidReviewHasNoConfirmationOrDispatch', 'testReadIdentityChangeBlocksLocalAction', 'testUnknownWriteKeepsExistingLock', 'testRepeatedValidTapCannotReplacePendingConfirmation']: self.assertIn(name, app)
    def test_native_ui_cases_cover_cancel_reenter(self):
        s = read('Tests/AppUITests/ProfileParticipantValidationFlowTests.swift')
        self.assertIn('testReenterStartsWithoutOldFeedbackOrDraft', s)
        self.assertIn('testNameCorrectionThenPhoneCorrectionReachesExistingConfirmation', s)

if __name__ == '__main__': unittest.main()
