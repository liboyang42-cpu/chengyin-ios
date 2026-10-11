"""Focused source checks for P107 exit safety; not Swift compilation or device proof."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def view():
    return (ROOT / 'App/ProfileEditView.swift').read_text()


def section(start, end):
    return view().split(start, 1)[1].split(end, 1)[0]


class ProfileExitDiscardContracts(unittest.TestCase):
    def test_exit_request_uses_exact_existing_dirty_comparison(self):
        dirty = section('private var hasUnsavedDraft: Bool', 'func ownsAvatarScope')
        for token in ['draft.name.utf8.elementsEqual(snapshot.nickname.utf8)',
                      'draft.introduction.utf8.elementsEqual(snapshot.introduction.utf8)',
                      'draft.routePreferenceIDs.map', 'snapshot.tagIds.utf8',
                      '?? true', 'draft.avatarReplacement != nil']:
            self.assertIn(token, dirty)
        self.assertNotIn('normalized', dirty)
        request = section('func requestExit() -> Bool', 'private func canExit')
        self.assertLess(request.index('synchronizeContext()'), request.index('guard canRequestExit'))
        self.assertIn('guard hasUnsavedDraft else { return commitExit() }', request)

    def test_review_is_bound_to_owner_draft_snapshot_and_pending_write_state(self):
        guard = section('private func canExit', '/// Validate and consume synchronously')
        for token in ['canRequestExit', 'coordinator.identity == value.identity',
                      'coordinator.viewerRevision == value.viewerRevision',
                      'generation == value.generation', 'revision == value.modelRevision',
                      'reloadContextRevision == value.contextRevision',
                      'coordinator.isLocked == value.writeWasLocked',
                      'Self.sameDraft(draft, value.draft)', 'Self.sameSnapshot(snapshot, value.snapshot)']:
            self.assertIn(token, guard)

    def test_cancel_only_retires_review_and_confirmation_is_consumed_once(self):
        self.assertIn('func cancelExit() { exitConfirmation = nil }', view())
        confirm = section('func confirmExit', 'private func commitExit')
        self.assertIn('guard exitConfirmation?.id == value.id else { return false }', confirm)
        self.assertIn('guard canExit(value) else { cancelExit(); return false }', confirm)
        self.assertNotIn('Task', confirm)
        commit = section('private func commitExit', 'func cancelReload()')
        self.assertLess(commit.index('guard !exitCommitted'), commit.index('exitCommitted = true'))
        self.assertLess(commit.index('exitCommitted = true'), commit.index('draft = .init()'))
        self.assertIn('retireReload(); retireAvatar()', commit)
        self.assertIn('coordinator.leaveScreen()', commit)

    def test_exit_paths_cannot_send_reads_writes_or_release_pending_lock(self):
        scope = section('func cancelExit()', 'func cancelReload()')
        for forbidden in ['await ', '.load(', '.prepare(', '.save(', 'pending[',
                          'URLRequest', 'URLSession', 'transport.', '.reconcile(']:
            self.assertNotIn(forbidden, scope)
        self.assertNotRegex(scope, r'isLocked\s*=(?!=)')

    def test_busy_reviews_and_avatar_presentation_prevent_competing_exit(self):
        guard = section('var canRequestExit:', 'func cancelExit()')
        for token in ['!exitCommitted', '!busy', '!coordinator.isBusy', 'confirmation == nil',
                      'coordinator.confirmation == nil', 'reloadConfirmation == nil', '!avatarPresentationActive']:
            self.assertIn(token, guard)
        # Unknown save is intentionally allowed to leave once its dispatch has settled.
        self.assertNotIn('!coordinator.isLocked', guard)

    def test_draft_aba_and_existing_lifecycle_retirement_invalidate_exit(self):
        self.assertIn('func retireReload() { reloadContextRevision &+= 1; cancelReload(); cancelExit() }', view())
        self.assertIn('@Published var draft = ProfileEditDraft() { didSet {', view())
        self.assertIn('avatarPreview = nil }; retireReload() } }', view())
        self.assertIn('func retireAvatar() { cancelExit();', view())
        for token in ['.onChange(of: sessionRevision) { _, _ in model.retireReload() }',
                      'if phase != .active { model.retireReload(); model.retireAvatar() }',
                      '.onChange(of: showPreferences) { _, _ in model.cancelExit() }']:
            self.assertIn(token, view())

    def test_committed_exit_blocks_queued_operations_and_reset_is_terminal(self):
        for signature in ['func load() async {', 'func requestReload() async {',
                          'func prepare() async {', 'func save(_ value: ProfileEditConfirmation) async {']:
            self.assertIn(signature + '\n        guard !exitCommitted else { return }', view())
        reset = section('func resetAndLoad() async {', 'func load() async {')
        guard = 'guard !exitCommitted, !Task.isCancelled else { return }'
        self.assertIn(guard, reset)
        self.assertLess(reset.index(guard), reset.index('retireReload()'))
        self.assertNotIn('exitCommitted = false', reset)
        self.assertEqual(view().count('exitCommitted = false'), 1)

    def test_custom_back_and_modal_fence_require_validated_dismissal(self):
        for token in ['@Environment(\\.dismiss) private var dismiss',
                      '.navigationBarBackButtonHidden(true)',
                      '.interactiveDismissDisabled(model.blocksInteractiveExit)',
                      'if model.requestExit() { dismiss() }',
                      'if model.confirmExit(value) { dismiss() }',
                      '.disabled(!model.canRequestExit)',
                      '.accessibilityIdentifier("profile.exitDiscard.back")',
                      '.accessibilityIdentifier("profile.exitDiscard.confirm")']:
            self.assertIn(token, view())
        self.assertEqual(view().count('dismiss()'), 2)

    def test_dialog_cancel_and_system_dismissal_retain_draft(self):
        self.assertIn('Button("action.cancel", role: .cancel) { model.cancelExit() }', view())
        self.assertIn('.onChange(of: showExitConfirmation) { _, showing in if !showing { model.cancelExit() } }', view())
        self.assertIn('.onChange(of: model.exitConfirmation?.id) { _, id in showExitConfirmation = id != nil }', view())

    def test_avatar_upload_cannot_start_under_exit_review(self):
        target = section('func avatarTarget', 'func stageAvatar')
        self.assertIn('exitConfirmation == nil', target)

    def test_three_new_strings_are_bilingual_unmerged_fragments(self):
        fragment = json.loads((ROOT / 'Resources/ProfileExitDiscardLocalizations.fragment.json').read_text())
        self.assertEqual(set(fragment), {'profile.exitDiscard.title', 'profile.exitDiscard.confirm', 'profile.exitDiscard.message'})
        for key, row in fragment.items():
            self.assertIn('"' + key + '"', view())
            for language in ['en', 'zh-Hans']:
                self.assertTrue(row['localizations'][language]['stringUnit']['value'])
        # Integration ownership is documented; absence from the catalog is not a runtime pass.
        documentation = (ROOT / 'docs/profile-exit-discard.md').read_text()
        self.assertIn('PENDING_PARENT_INTEGRATION', documentation)
        self.assertIn('Apple: NOT_RUN', documentation)

    def test_authored_runtime_cases_cover_actual_model_and_transport_counts(self):
        text = (ROOT / 'Tests/AppUnitTests/ProfileExitDiscardTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test\w+\(', text)), 27)
        for name in ['CleanExitAllowsDismissalOnce', 'CancelPreservesAllDraftBytes',
                     'CanonicalUnicodeByteDifferences', 'DraftABA', 'AnotherEditor',
                     'AccountEpochAndViewerChanges', 'UnknownSaveCanLeaveWithoutReleasingLock',
                     'CommittedExitRejectsQueued', 'QueuedResetAfterCommittedExit',
                     'CancelledResetPreservesActiveDraftAndExitReview',
                     'ReopenedEditorUsesANewModelAndKeepsUnknownWriteLock',
                     'OldResetCannotClearReopenedEditorsSaveReview', 'StagedAvatarOnlyNeedsReview']:
            self.assertIn(name, text)
        self.assertIn('XCTAssertTrue(model.coordinator.isLocked)', text)
        self.assertIn('XCTAssertEqual(service.saveCount, 0)', text)


if __name__ == '__main__':
    unittest.main()
