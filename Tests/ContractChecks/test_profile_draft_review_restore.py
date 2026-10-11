"""Focused source invariants only. Swift compilation/runtime remain separate acceptance."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
def section(path,start,end):return read(path).split(start,1)[1].split(end,1)[0]
class ProfileDraftReviewRestoreContracts(unittest.TestCase):
    def test_summary_uses_exact_bytes_and_actual_proposed_payload(self):
        s=read('Core/ProfileEditReviewSummary.swift')
        for token in ['before.utf8.elementsEqual(after.utf8)', 'a.utf8.elementsEqual(b.utf8)',
                      'text(.name, snapshot.nickname, payload.name)', 'text(.introduction, snapshot.introduction, payload.introduction)',
                      'if let after = payload.caseIntroduction, let before = snapshot.caseIntroduction']:
            self.assertIn(token,s)
        self.assertNotIn('trimmingCharacters',s)
    def test_every_supported_change_has_stable_single_field_identity(self):
        s=read('Core/ProfileEditReviewSummary.swift')
        for field in ['name','introduction','caseIntroduction','preferences','avatar','contactQR','casePictures']:
            self.assertIn('.'+field,s)
        self.assertIn('public var id: String { field.rawValue }',s)
        self.assertIn('changes = result',s)
        self.assertIn('public let changes:',s)
    def test_media_presentation_uses_presence_counts_not_raw_references(self):
        s=read('Core/ProfileEditReviewSummary.swift')
        for token in ['before: .present(!snapshot.avatar.isEmpty), after: .newAvatar',
                      'before: .present(!snapshot.wechat.isEmpty), after: .present(false)',
                      'before: .imageCount(ProfileCasePortfolio(casePics: snapshot.casePics).imageCount), after: .imageCount(0)']:
            self.assertIn(token,s)
        for token in ['.text(snapshot.avatar)', '.text(snapshot.wechat)', '.text(snapshot.casePics)', '.text(payload.avatar)']:
            self.assertNotIn(token,s)
    def test_summary_is_bound_to_immutable_prepared_confirmation(self):
        s=section('Core/ProfileEditCoordinator.swift','public struct ProfileEditConfirmation','/// Retain in AppSession')
        self.assertIn('public var reviewSummary: ProfileEditReviewSummary { .init(snapshot: snapshot, payload: payload) }',s)
        self.assertIn('fileprivate let snapshot:',s);self.assertIn('public let payload:',s)
    def test_coordinator_restore_consumes_only_live_unlocked_exact_session_review(self):
        s=section('Core/ProfileEditCoordinator.swift','public func discardReviewedDraft','public func save')
        for token in ['synchronizeSession()', '!Task.isCancelled, !isBusy, !isLocked, confirmation == value',
                      'session == value.session, currentSession() == value.session',
                      'confirmation = nil; snapshot = value.snapshot', 'return value.snapshot']:
            self.assertIn(token,s)
        self.assertLess(s.index('guard '),s.index('confirmation = nil'))
    def test_coordinator_restore_cannot_write_read_unlock_or_fake_save_success(self):
        s=section('Core/ProfileEditCoordinator.swift','public func discardReviewedDraft','public func save')
        self.assertIn('messageKey = "profile.reviewRestore.restored"; remoteMessage = nil',s)
        for token in ['await ', 'Task {', 'pending[', '.save(', '.read(', '.load(', 'onSaved(', 'profile.edit.saved', 'service.']:
            self.assertNotIn(token,s)
    def test_model_captures_draft_before_prepare_and_rejects_interleaved_changes(self):
        s=section('App/ProfileEditView.swift','    func prepare()','    func canRestoreReviewedDraft')
        self.assertIn('let captured = draft, capturedRevision = avatarDraftRevision',s)
        self.assertLess(s.index('let captured = draft'),s.index('await coordinator.prepare'))
        self.assertIn('reviewedDraft = nil',s)
        self.assertIn('if let value = confirmation, avatarDraftRevision == capturedRevision, Self.sameDraft(draft, captured)',s)
        self.assertIn('reviewID: value.id, generation: generation, modelRevision: revision',s)
    def test_model_restore_guard_binds_lifetime_version_draft_and_identity(self):
        s=section('App/ProfileEditView.swift','func canRestoreReviewedDraft','/// Restore every field')
        for token in ['!exitCommitted, !busy, !coordinator.isBusy, !coordinator.isLocked',
                      'textEdit == nil, !avatarPresentationActive, reloadConfirmation == nil, exitConfirmation == nil',
                      'confirmation == value, coordinator.confirmation == value', 'captured.reviewID == value.id',
                      'captured.generation == generation, captured.modelRevision == revision',
                      'captured.draftRevision == avatarDraftRevision, Self.sameDraft(draft, captured.draft)',
                      'captured.identity == coordinator.identity, captured.viewerRevision == coordinator.viewerRevision']:
            self.assertIn(token,s)
    def test_local_restore_is_atomic_and_stays_in_editor(self):
        s=section('App/ProfileEditView.swift','func restoreReviewedDraft','    func save(')
        for token in ['guard canRestoreReviewedDraft(value), let snapshot = coordinator.discardReviewedDraft(value)',
                      'reviewedDraft = nil; confirmation = nil', 'retireReload(); retireAvatar(); activateAvatar()',
                      'draft = snapshot.draft; revision += 1']:
            self.assertIn(token,s)
        for token in ['await ', 'Task {', 'commitExit()', 'dismiss()', '.load(', '.save(', 'pending[']:
            self.assertNotIn(token,s)
    def test_retirement_and_save_drop_restoration_capability(self):
        s=read('App/ProfileEditView.swift')
        self.assertIn('func retireAvatar() { cancelExit(); reviewedDraft = nil;',s)
        self.assertIn('let request = generation; reviewedDraft = nil; confirmation = nil; busy = true',s)
        self.assertIn('await coordinator.save(value)',s)
    def test_comparison_and_separate_discard_confirmation_are_native_and_local(self):
        s=read('App/ProfileDraftReviewSection.swift')
        for token in ['DisclosureGroup {','ForEach(summary.changes)', 'value(change.before)', 'value(change.after)',
                      '@State private var showsRestore = false', '.disabled(!canRestore)', '.confirmationDialog(',
                      'Button("profile.reviewRestore.confirm", role: .destructive, action: restore)',
                      'Button("action.cancel", role: .cancel)', 'text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty']:
            self.assertIn(token,s)
        for token in ['URLSession', 'URLRequest', 'AsyncImage', '.save(', '.load(', 'coordinator.']:
            self.assertNotIn(token,s)
    def test_existing_save_cancel_and_review_lifetime_wiring_remain(self):
        s=read('App/ProfileEditView.swift')
        self.assertIn('ProfileDraftReviewSection(summary: value.reviewSummary,',s)
        self.assertIn('canRestore: model.canRestoreReviewedDraft(value)',s)
        self.assertIn('restore: { _ = model.restoreReviewedDraft(value) })\n                        .id(value.id)',s)
        self.assertIn('Button { Task { await model.save(value) } }',s)
        self.assertIn('model.coordinator.cancel(value); model.confirmation = nil',s)
    def test_fragment_has_fifteen_bilingual_keys_and_no_central_changes(self):
        rows=json.loads(read('Resources/ProfileDraftReviewRestoreLocalizations.fragment.json'));self.assertEqual(len(rows),15)
        for key,row in rows.items():
            self.assertTrue(key.startswith('profile.reviewRestore.'))
            for lang in ['en','zh-Hans']:self.assertTrue(row['localizations'][lang]['stringUnit']['value'])
        f=json.loads(read('docs/profile-draft-review-restore-registration.fragment.json'))
        self.assertEqual(f['central_files_modified'],[]);self.assertEqual(f['apple'],'NOT_RUN')
    def test_authored_runtime_cases_and_limits_cover_complete_restore_chain(self):
        s=read('Tests/AppUnitTests/ProfileDraftReviewRestoreTests.swift')
        for name in ['testRestoreAtomicallyClearsEveryLocalProposalWithoutReadWriteOrSaveCallback',
                     'testDraftChangedWhilePrepareWasAwaitingDoesNotReceiveRestoreCapability',
                     'testUnknownWriteCannotBeUnlockedOrRepeatedByRestore', 'testRestoreThenEditAndSaveWorksWithoutCommittingExit',
                     'testRestoreRetiresStagedAvatarWithoutUploadingAgainOrDeletingAsset']:
            self.assertIn(name,s)
        docs=read('docs/profile-draft-review-restore.md')
        for token in ['Apple: NOT_RUN','PENDING_PARENT_INTEGRATION','does not claim Mini has this exact comparison screen',
                      'It is not server rollback','Website was considered and excluded']:
            self.assertIn(token,docs)
if __name__=='__main__':unittest.main()
