"""P107 local field-edit wiring checks. These do not compile or execute Swift."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()

def section(start, end):
    return read('App/ProfileEditView.swift').split(start, 1)[1].split(end, 1)[0]

class ProfileTextFieldEditContracts(unittest.TestCase):
    def test_main_form_opens_local_editors_instead_of_direct_draft_bindings(self):
        view = read('App/ProfileEditView.swift')
        self.assertIn('textFieldRow(.name, value: model.draft.name)', view)
        self.assertIn('textFieldRow(.introduction, value: model.draft.introduction)', view)
        self.assertNotIn('text: $model.draft.name', view)
        self.assertNotIn('text: $model.draft.introduction', view)
        self.assertIn('Button { model.beginTextEdit(field) }', view)
        self.assertIn('.disabled(!model.canBeginTextEdit)', view)

    def test_scratch_is_view_owned_exact_original_and_not_normalized(self):
        editor = read('App/ProfileTextFieldEditor.swift')
        for token in ['@State private var text: String', '_text = State(initialValue: edit.originalText)',
                      'text: $text', 'field.value(in: draft)',
                      'case .name: return draft.name', 'case .introduction: return draft.introduction']:
            self.assertIn(token, editor)
        for forbidden in ['normalized', 'trimmingCharacters', '$model.draft', '.onDisappear', '.onChange']:
            self.assertNotIn(forbidden, editor)

    def test_open_is_context_bound_and_repeated_open_is_blocked(self):
        guard = section('var canBeginTextEdit:', 'func beginTextEdit')
        for token in ['!exitCommitted', '!busy', '!coordinator.isBusy', '!coordinator.isLocked',
                      'coordinator.isConfigured', 'coordinator.snapshot != nil', 'textEdit == nil',
                      'confirmation == nil', 'coordinator.confirmation == nil', 'reloadConfirmation == nil',
                      'exitConfirmation == nil', '!avatarPresentationActive']:
            self.assertIn(token, guard)
        begin = section('func beginTextEdit', 'func cancelTextEdit')
        self.assertLess(begin.index('guard !exitCommitted'), begin.index('synchronizeContext()'))
        self.assertLess(begin.index('synchronizeContext()'), begin.index('guard canBeginTextEdit'))
        for token in ['identity: identity', 'viewerRevision: coordinator.viewerRevision',
                      'generation: generation', 'modelRevision: revision', 'draftRevision: avatarDraftRevision',
                      'snapshot: snapshot', 'draft: draft']:
            self.assertIn(token, begin)

    def test_cancel_and_interactive_dismissal_are_scoped_to_presented_id(self):
        cancel = section('func cancelTextEdit', 'private func retireTextEdit')
        self.assertIn('guard textEdit?.id == value.id else { return }', cancel)
        self.assertIn('retireTextEdit()', cancel)
        self.assertNotIn('draft =', cancel)
        binding = section('private var textEditPresentation:', 'private func textFieldRow')
        self.assertIn('let presented = model.textEdit', binding)
        self.assertIn('model.cancelTextEdit(presented)', binding)
        self.assertIn('.id(value.id)', read('App/ProfileEditView.swift'))
        self.assertIn('}.interactiveDismissDisabled(false)', read('App/ProfileEditView.swift'))
        editor = read('App/ProfileTextFieldEditor.swift')
        self.assertIn('Button("action.cancel", role: .cancel) { focused = false; cancel() }', editor)
        self.assertNotIn('interactiveDismissDisabled', editor)

    def test_confirm_has_identity_generation_snapshot_and_byte_guards(self):
        confirm = section('func confirmTextEdit', 'func ownsAvatarScope')
        for token in ['guard textEdit?.id == value.id else { return false }', '!exitCommitted', '!busy',
                      '!coordinator.isBusy', '!coordinator.isLocked', 'confirmation == nil',
                      'coordinator.confirmation == nil', 'reloadConfirmation == nil', 'exitConfirmation == nil',
                      '!avatarPresentationActive', 'coordinator.identity == value.identity',
                      'coordinator.viewerRevision == value.viewerRevision', 'generation == value.generation',
                      'revision == value.modelRevision', 'avatarDraftRevision == value.draftRevision',
                      'Self.sameDraft(draft, value.draft)', 'Self.sameSnapshot(snapshot, value.snapshot)',
                      'cancelTextEdit(value); return false']:
            self.assertIn(token, confirm)
        exact = section('private static func sameDraft', 'private var hasUnsavedDraft')
        self.assertIn('lhs.name.utf8.elementsEqual(rhs.name.utf8)', exact)
        self.assertIn('lhs.introduction.utf8.elementsEqual(rhs.introduction.utf8)', exact)
        self.assertIn('$0.0.utf8.elementsEqual($0.1.utf8)', exact)

    def test_confirmation_consumes_once_and_stages_only_chosen_field(self):
        confirm = section('func confirmTextEdit', 'func ownsAvatarScope')
        self.assertLess(confirm.index('retireTextEdit()'), confirm.index('var next = draft'))
        for token in ['case .name: next.name = text', 'case .introduction: next.introduction = text', 'draft = next']:
            self.assertIn(token, confirm)
        self.assertNotIn("routePreferenceIDs =", confirm.split("case .preferences:", 1)[0])
        self.assertIn("if selected != original { next.routePreferenceIDs = selected }", confirm.split("case .preferences:", 1)[1])
        for forbidden in ['normalized', 'trimmingCharacters', 'avatarReplacement =', 'draft = .init']:
            self.assertNotIn(forbidden, confirm)

    def test_local_path_cannot_dispatch_transport_or_release_locks(self):
        local = section('var canBeginTextEdit:', 'func ownsAvatarScope')
        for forbidden in ['await ', 'Task {', '.load(', '.prepare(', '.save(', 'URLRequest', 'URLSession',
                          'pending[', '.reconcile(', 'isLocked =', '.leaveScreen(']:
            self.assertNotIn(forbidden, local)

    def test_draft_aba_and_context_reset_retire_old_edit(self):
        view = read('App/ProfileEditView.swift')
        self.assertIn('didSet { retireTextEdit(); avatarDraftRevision &+= 1', view)
        sync = section('private func synchronizeContext()', 'func resetAndLoad()')
        self.assertIn('retireTextEdit()', sync)
        self.assertIn('if let value = model.textEdit { model.cancelTextEdit(value) }', view)
        reset = section('func resetAndLoad()', 'func load()')
        self.assertLess(reset.index('guard !exitCommitted, !Task.isCancelled'), reset.index('retireTextEdit()'))

    def test_background_keeps_text_scratch_and_presentation_avoids_avatar_retirement(self):
        view = read('App/ProfileEditView.swift')
        self.assertIn('if phase != .active { model.retireReload(); model.retireAvatar() }', view)
        self.assertIn('func retireReload() { reloadContextRevision &+= 1; cancelReload(); cancelExit() }', view)
        self.assertIn('func retireAvatar() { cancelExit();', view)
        self.assertIn('if !showPreferences, model.textEdit == nil, model.confirmation == nil, !model.avatarPresentationActive', view)

    def test_pending_text_edit_blocks_competing_operations(self):
        view = read('App/ProfileEditView.swift')
        for method in ['load()', 'requestReload()', 'prepare()', 'save(_ value: ProfileEditConfirmation)']:
            self.assertIn(f'func {method} async {{\n        guard !exitCommitted else {{ return }}\n        guard textEdit == nil else {{ return }}', view)
        self.assertIn('textEdit == nil', section('var canRequestExit:', 'func cancelExit()'))
        self.assertIn('textEdit == nil', section('func avatarTarget', 'func stageAvatar'))
        self.assertIn('hasUnsavedDraft || textEdit != nil || busy || coordinator.isBusy', view)

    def test_existing_exit_terminal_and_full_page_save_paths_remain(self):
        view = read('App/ProfileEditView.swift')
        self.assertEqual(view.count('exitCommitted = false'), 1)
        for token in ['exitCommitted = true', 'coordinator.leaveScreen()',
                      'if model.confirmExit(value) { dismiss() }', 'await coordinator.prepare(draft,',
                      'await coordinator.save(value)', 'model.draft.isValid']:
            self.assertIn(token, view)

    def test_localization_is_bilingual_fragment_and_dynamic_title_uses_supported_api(self):
        fragment = json.loads(read('Resources/ProfileTextFieldEditLocalizations.fragment.json'))
        self.assertEqual(set(fragment), {'profile.fieldEdit.empty', 'profile.fieldEdit.hint', 'profile.fieldEdit.apply'})
        for row in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(row['localizations'][language]['stringUnit']['value'])
        self.assertIn('.appNavigationTitle(key: edit.field.titleKey)', read('App/ProfileTextFieldEditor.swift'))

    def test_app_and_ui_tests_cover_cancel_confirm_stale_scope_and_interruptions(self):
        tests = read('Tests/AppUnitTests/ProfileTextFieldEditTests.swift')
        for token in ['testCancelRetainsWholeDraftAndReopenStartsFresh', 'testRepeatedConfirmationAndLateCancelCannotChangeSuccessor',
                      'testDraftABAAndUnrelatedFieldChangeRetireOldScratch', 'testAccountEpochAndViewerChangesRejectOldScratch',
                      'testSnapshotDriftIncludingCanonicalUnicodeDifferenceRejectsScratch',
                      'testStagedAvatarAndPreferencesSurviveFieldCancelAndApply', 'testConfirmedFieldStillRequiresWholePageReviewAndSave']:
            self.assertIn(token, tests)
        ui = read('Tests/AppUITests/ProfileEditFlowTests.swift')
        for token in ['testNicknameCancelReopenAndApply', 'testIntroductionCancelDoesNotRevertPreviouslyStagedNickname',
                      'testSwipeDismissDiscardsOnlyLocalFieldScratch', 'testBackgroundKeepsFieldScratchUntilExplicitCancel']:
            self.assertIn(token, ui)

    def test_registration_is_fragment_only_and_limits_are_explicit(self):
        fragment = json.loads(read('docs/profile-text-field-edit-registration.fragment.json'))
        self.assertEqual(fragment['status'], 'PENDING_PARENT_INTEGRATION')
        self.assertEqual(fragment['app_sources'], ['App/ProfileTextFieldEditor.swift'])
        self.assertEqual(fragment['app_unit_test_sources'], ['Tests/AppUnitTests/ProfileTextFieldEditTests.swift'])
        docs = read('docs/profile-text-field-edit.md')
        for token in ['Apple: NOT_RUN', 'openPop4/cancel4/confirm4', 'openPop/cancel/confirm', 'openPop2',
                      'PENDING_PARENT_INTEGRATION', 'No per-field network save']:
            self.assertIn(token, docs)

if __name__ == '__main__':
    unittest.main()
