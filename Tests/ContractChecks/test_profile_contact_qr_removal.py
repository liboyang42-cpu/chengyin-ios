"""Focused source checks, not Swift compilation or native runtime acceptance."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
def section(path, start, end): return read(path).split(start, 1)[1].split(end, 1)[0]

class ProfileContactQRRemovalContracts(unittest.TestCase):
    def test_proposal_is_clear_only_not_an_arbitrary_reference(self):
        s = section('Core/ProfileEditContracts.swift', 'public struct ProfileEditDraft', 'public struct ProfileEditPayload')
        self.assertIn('public var removesContactQR: Bool', s)
        self.assertIn('removesContactQR: Bool = false', s)
        for token in ['wechat: String', 'contactQR: String', 'qrURL', 'URLSession', 'URLRequest']:
            self.assertNotIn(token, s)

    def test_payload_preserves_exact_original_or_clears_existing_wire_key(self):
        s = section('Core/ProfileEditContracts.swift', 'public struct ProfileEditPayload', 'public struct ProfileEditSession')
        self.assertIn('removesContactQR = draft.removesContactQR && !snapshot.wechat.isEmpty', s)
        self.assertIn('wechat = removesContactQR ? "" : snapshot.wechat\n        casePics = removesCasePictures ? "" : snapshot.casePics', s)
        keys = s.split('enum CodingKeys:', 1)[1].split('public init', 1)[0]
        self.assertIn('case name, introduction, avatar, wechat, casePics, tagIds', keys)
        self.assertNotIn('removesContactQR', keys)
        self.assertNotIn('member_id', keys)
        self.assertIn('&& wechat == snapshot.wechat', s)

    def test_effective_dirty_state_accounts_for_empty_qr_and_restoration(self):
        s = section('Core/ProfileEditContracts.swift', 'public func hasChanges', 'public var isValid')
        for token in ['ordinary.removesContactQR = false', 'let contactQRChanged = removesContactQR && !snapshot.wechat.isEmpty',
                      'return ordinary != snapshot.draft.normalized || caseChanged || contactQRChanged']:
            self.assertIn(token, s)
        model = read('App/ProfileEditView.swift')
        self.assertIn('|| (draft.removesContactQR && !snapshot.wechat.isEmpty)', model)
        self.assertIn('&& lhs.removesContactQR == rhs.removesContactQR', model)

    def test_avatar_and_normalization_preserve_intent_and_fingerprint(self):
        contracts = read('Core/ProfileEditContracts.swift')
        self.assertEqual(contracts.count('caseIntroduction: caseIntroduction, removesContactQR: removesContactQR, removesCasePictures: removesCasePictures)'), 2)
        self.assertIn('caseIntroduction: draft.caseIntroduction, removesContactQR: draft.removesContactQR, removesCasePictures: draft.removesCasePictures)', read('App/ProfileEditView.swift'))
        fingerprint = section('Core/ProfileAvatarUpload.swift', 'public static func draft', 'public struct ProfileAvatarTarget')
        self.assertIn('if value.removesContactQR { parts.append("remove-contact-qr") }', fingerprint)

    def test_confirmation_uses_existing_full_scope_and_aba_fences(self):
        s = section('App/ProfileEditView.swift', 'func confirmTextEdit', 'func ownsAvatarScope')
        for token in ['guard textEdit?.id == value.id else { return false }', '!exitCommitted, !busy, !coordinator.isBusy, !coordinator.isLocked',
                      'coordinator.identity == value.identity', 'coordinator.viewerRevision == value.viewerRevision',
                      'generation == value.generation', 'revision == value.modelRevision', 'avatarDraftRevision == value.draftRevision',
                      'Self.sameDraft(draft, value.draft)', 'Self.sameSnapshot(snapshot, value.snapshot)']:
            self.assertIn(token, s)
        self.assertLess(s.index('retireTextEdit()'), s.index('var next = draft'))
        self.assertNotIn('await ', s)

    def test_model_accepts_only_original_bytes_or_empty_and_correct_field(self):
        s = section('App/ProfileEditView.swift', 'func confirmTextEdit', 'func ownsAvatarScope')
        self.assertIn('guard text.isEmpty || text.utf8.elementsEqual(snapshot.wechat.utf8) else { return false }', s)
        self.assertIn('next.removesContactQR = text.isEmpty && !snapshot.wechat.isEmpty', s)
        self.assertIn('guard value.field == .contactQR else { return false }', s)
        self.assertIn('return confirmTextEdit(value, text: remove ? "" : value.snapshot.wechat)', s)

    def test_before_review_and_before_write_qr_drift_are_byte_exact(self):
        s = read('Core/ProfileEditCoordinator.swift')
        self.assertIn('!draft.removesContactQR || latest.wechat.utf8.elementsEqual(original.wechat.utf8)', s)
        self.assertIn('!value.payload.removesContactQR || latest.wechat.utf8.elementsEqual(value.snapshot.wechat.utf8)', s)
        self.assertIn('if unresolved.acknowledged && matches', s)
        self.assertIn('messageKey = "profile.edit.readbackUnconfirmed"', s)
        self.assertIn('try await service.save(value.payload, token: expected.token)', s)

    def test_scratch_remove_restore_and_cancel_do_not_write_page_or_network(self):
        s = read('App/ProfileContactQREditor.swift')
        for token in ['@State private var removes: Bool', '_removes = State(initialValue: edit.draft.removesContactQR)',
                      'Button("profile.contactQR.restore") { removes = false }',
                      'Button("profile.contactQR.remove", role: .destructive) { removes = true }',
                      'Button("action.cancel", role: .cancel, action: cancel)',
                      'Button("profile.fieldEdit.apply") { confirm(removes) }']:
            self.assertIn(token, s)
        for token in ['model.draft', 'edit.draft.removesContactQR =', 'TextField(', 'PhotosPicker', 'fileImporter', '.save(', '.upload(', 'URLSession', 'AsyncImage', 'enabled: true']:
            self.assertNotIn(token, s)

    def test_existing_empty_qr_has_no_remove_or_restore_action(self):
        s = section('App/ProfileContactQREditor.swift', 'if edit.snapshot.wechat.isEmpty', '} else if removes')
        self.assertIn('ContentUnavailableView("profile.contactQR.empty"', s)
        self.assertNotIn('Button(', s)

    def test_viewer_is_only_an_entry_until_authorized_reader_is_injected(self):
        s = read('App/ProfileContactQREditor.swift')
        self.assertIn('reader: (any RetainedPublicImageReading)? = nil', s)
        self.assertIn('NativeMediaGalleryEntry(sources: [edit.snapshot.wechat], scope: edit.id,', s)
        self.assertIn('titleKey: "profile.contactQR.title", reader: reader)', s)
        self.assertNotIn('enabled: true', s)
        account = read('App/AccountView.swift')
        self.assertNotIn('caseImageReader:', account)
        self.assertNotIn('caseImageReader:', read('App/ProfileEditFixtureSupport.swift'))

    def test_editor_routes_actions_with_unique_scope_and_no_raw_input(self):
        s = read('App/ProfileEditView.swift')
        self.assertIn('ProfileContactQRSection(wechat:', s)
        self.assertIn('if value.field == .contactQR', s)
        self.assertIn('ProfileContactQREditor(edit: value, reader: caseImageReader,', s)
        self.assertIn('model.confirmContactQR(value, remove: $0)', s)
        self.assertIn('.id(value.id)', s)
        self.assertIn('if value.payload.removesContactQR', s)
        self.assertIn('Text("profile.contactQR.reviewRemoval")', s)
        fallback = read('App/ProfileTextFieldEditor.swift')
        self.assertIn('case .contactQR: return ""', fallback)
        self.assertIn('if edit.field == .contactQR {\n                    Text("profile.contactQR.noUpload")', fallback)
        self.assertIn('.disabled(edit.field == .contactQR ||', fallback)

    def test_synthetic_fixture_clears_qr_without_enabling_image_fetch(self):
        s = read('Core/ProfileEditSyntheticFixtures.swift')
        self.assertIn('https://profile-fixture.invalid/contact.png', s)
        self.assertIn('wechat = payload.wechat', s)
        self.assertIn('"wechat": wechat', s)
        self.assertIn('case "contactQR": mode = .contactQR', read('App/ProfileEditFixtureSupport.swift'))

    def test_fragments_declare_only_new_sources_and_ten_bilingual_keys(self):
        rows = json.loads(read('Resources/ProfileContactQRRemovalLocalizations.fragment.json'))
        self.assertEqual(len(rows), 10)
        for key, row in rows.items():
            self.assertTrue(key.startswith('profile.contactQR.'))
            for language in ['en', 'zh-Hans']: self.assertTrue(row['localizations'][language]['stringUnit']['value'])
        f = json.loads(read('docs/profile-contact-qr-removal-registration.fragment.json'))
        self.assertEqual(f['central_files_modified'], [])
        self.assertEqual(f['image_loading'], 'PENDING_AUTHORIZED_PERSONAL_READER_INJECTION')
        self.assertEqual(f['apple'], 'NOT_RUN')

    def test_authored_runtime_cases_and_documentation_limitations_are_explicit(self):
        app = read('Tests/AppUnitTests/ProfileContactQRRemovalTests.swift')
        for name in ['testArbitraryQRCodeReplacementIsRejectedAndOriginalNeverShownAsInput',
                     'testNewQRCodeBeforeReviewOrBeforeSavePreventsDeletion',
                     'testUnknownRemovalNeverUnlocksOrRepeatsPostOnEmptyReadback',
                     'testSuccessfulRemovalCannotRestoreOldQRWithAStaleAction']:
            self.assertIn(name, app)
        docs = read('docs/profile-contact-qr-removal.md')
        for word in ['NOT_RUN', '51d3e24de92427a777f8690f847cec39971b041a', 'reader', 'getAppUserId']:
            self.assertIn(word, docs)

if __name__ == '__main__': unittest.main()
