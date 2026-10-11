"""Static source seams only; not native compilation or runtime acceptance."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
def section(path,start,end):return read(path).split(start,1)[1].split(end,1)[0]
class ProfileCasePictureRemovalContracts(unittest.TestCase):
    def test_count_covers_omitted_images_and_keeps_duplicate_positions(self):
        s=read('Core/ProfileCasePortfolio.swift')
        self.assertIn('public var imageCount: Int { images.count + omittedImageCount }',s)
        self.assertIn('images = Array(values.prefix(100))',s)
        self.assertNotIn('Set(',s);self.assertNotIn('.sorted(',s)
    def test_clear_only_flag_and_effective_payload_preserve_original_bytes(self):
        s=read('Core/ProfileEditContracts.swift')
        self.assertIn('public var removesCasePictures: Bool',s)
        self.assertIn('removesCasePictures: Bool = false',s)
        self.assertIn('removesCasePictures = draft.removesCasePictures && ProfileCasePortfolio(casePics: snapshot.casePics).imageCount > 0',s)
        self.assertIn('casePics = removesCasePictures ? "" : snapshot.casePics',s)
        keys=section('Core/ProfileEditContracts.swift','public struct ProfileEditPayload','public struct ProfileEditSession').split('enum CodingKeys:',1)[1].split('public init',1)[0]
        self.assertNotIn('removesCasePictures',keys)
        self.assertIn('case name, introduction, avatar, wechat, casePics, tagIds',keys)
    def test_noop_and_dirty_state_use_the_effective_all_image_proposal(self):
        s=section('Core/ProfileEditContracts.swift','public func hasChanges','public var isValid')
        self.assertIn('ordinary.removesCasePictures = false',s)
        self.assertIn('let picturesChanged = removesCasePictures && ProfileCasePortfolio(casePics: snapshot.casePics).imageCount > 0',s)
        self.assertIn('|| contactQRChanged || picturesChanged',s)
        view=read('App/ProfileEditView.swift')
        self.assertIn('|| (draft.removesCasePictures && ProfileCasePortfolio(casePics: snapshot.casePics).imageCount > 0)',view)
        self.assertIn('&& lhs.removesCasePictures == rhs.removesCasePictures',view)
    def test_intent_survives_normalization_avatar_staging_discard_and_fingerprint(self):
        s=read('Core/ProfileEditContracts.swift')
        self.assertEqual(s.count('removesContactQR: removesContactQR, removesCasePictures: removesCasePictures)'),2)
        self.assertIn('removesContactQR: draft.removesContactQR, removesCasePictures: draft.removesCasePictures)',read('App/ProfileEditView.swift'))
        self.assertIn('if value.removesCasePictures { parts.append("remove-case-pictures") }',read('Core/ProfileAvatarUpload.swift'))
    def test_confirmation_requires_correct_field_and_original_bytes_or_empty(self):
        s=section('App/ProfileEditView.swift','func confirmTextEdit','func ownsAvatarScope')
        for token in ['case .casePictures:', 'guard text.isEmpty || text.utf8.elementsEqual(snapshot.casePics.utf8) else { return false }',
                      'next.removesCasePictures = text.isEmpty && ProfileCasePortfolio(casePics: snapshot.casePics).imageCount > 0',
                      'guard value.field == .casePictures else { return false }',
                      'return confirmTextEdit(value, text: remove ? "" : value.snapshot.casePics)']:
            self.assertIn(token,s)
    def test_existing_scope_aba_and_one_use_fences_are_retained(self):
        s=section('App/ProfileEditView.swift','func confirmTextEdit','func ownsAvatarScope')
        for token in ['guard textEdit?.id == value.id else { return false }','!exitCommitted','!coordinator.isLocked',
                      'coordinator.identity == value.identity','coordinator.viewerRevision == value.viewerRevision',
                      'generation == value.generation','revision == value.modelRevision','avatarDraftRevision == value.draftRevision',
                      'Self.sameDraft(draft, value.draft)','Self.sameSnapshot(snapshot, value.snapshot)']:
            self.assertIn(token,s)
        self.assertLess(s.index('retireTextEdit()'),s.index('var next = draft'));self.assertNotIn('await ',s)
    def test_review_and_final_prewrite_reject_byte_exact_image_drift(self):
        s=read('Core/ProfileEditCoordinator.swift')
        self.assertIn('!draft.removesCasePictures || latest.casePics.utf8.elementsEqual(original.casePics.utf8)',s)
        self.assertIn('!value.payload.removesCasePictures || latest.casePics.utf8.elementsEqual(value.snapshot.casePics.utf8)',s)
        self.assertIn('if unresolved.acknowledged && matches',s)
        self.assertIn('messageKey = "profile.edit.readbackUnconfirmed"',s)
        self.assertIn('&& casePics == snapshot.casePics',read('Core/ProfileEditContracts.swift'))
    def test_sheet_clear_keep_cancel_are_local_and_need_no_reader_or_upload(self):
        s=read('App/ProfileCasePictureRemovalEditor.swift')
        for token in ['@State private var removes: Bool','_removes = State(initialValue: edit.draft.removesCasePictures)',
                      'Button("profile.caseRemoval.restore") { removes = false }',
                      'Button("profile.caseRemoval.remove", role: .destructive) { removes = true }',
                      'Button("action.cancel", role: .cancel, action: cancel)','Button("profile.fieldEdit.apply") { confirm(removes) }']:
            self.assertIn(token,s)
        for token in ['model.draft','NativeMediaGallery','RetainedPublicImage','URLSession','AsyncImage','PhotosPicker','TextField(','.upload(','.save(']:self.assertNotIn(token,s)
    def test_empty_state_has_no_destructive_action_and_total_count_is_visible(self):
        s=read('App/ProfileCasePictureRemovalEditor.swift')
        self.assertIn('LabeledContent("profile.caseRemoval.count", value: String(imageCount))',s)
        empty=s.split('if imageCount == 0 {',1)[1].split('} else if removes',1)[0]
        self.assertIn('Text("profile.caseRemoval.empty")',empty);self.assertNotIn('Button(',empty)
    def test_main_entry_and_review_are_connected_without_arbitrary_text_editor(self):
        s=read('App/ProfileEditView.swift')
        for token in ['Button("profile.caseRemoval.open") { model.beginTextEdit(.casePictures) }',
                      'ProfileCasePictureRemovalEditor(edit: value,','model.confirmCasePictureRemoval(value, remove: $0)',
                      'if value.payload.removesCasePictures { Text("profile.caseRemoval.review") }']:
            self.assertIn(token,s)
        editor=read('App/ProfileTextFieldEditor.swift')
        self.assertIn('case .casePictures: return ""',editor);self.assertIn('.disabled(edit.field == .casePictures)',editor)
    def test_description_editor_reflects_pending_removal_not_original_gallery(self):
        s=read('App/ProfileTextFieldEditor.swift')
        self.assertIn('if edit.draft.removesCasePictures {',s)
        self.assertIn('Text("profile.caseRemoval.staged").accessibilityIdentifier("profile.caseRemoval.stagedInDescription")',s)
        self.assertIn('} else {\n                    ProfileCasePortfolioSection(casePics: edit.snapshot.casePics, scope: edit.id, reader: caseImageReader)',s)
    def test_synthetic_fixture_persists_casePics_and_keeps_invalid_image_origins(self):
        s=read('Core/ProfileEditSyntheticFixtures.swift')
        for token in ['if scenario == .portfolioImages || scenario == .caseRemoval', 'https://profile-fixture.invalid/one.jpg;https://profile-fixture.invalid/two.jpg',
                      '"casePics": casePics','casePics = payload.casePics']:
            self.assertIn(token,s)
        self.assertIn('case "caseRemoval": mode = .caseRemoval',read('App/ProfileEditFixtureSupport.swift'))
    def test_fragments_have_ten_bilingual_keys_and_no_central_registration_changes(self):
        f=json.loads(read('Resources/ProfileCasePictureRemovalLocalizations.fragment.json'));self.assertEqual(len(f),10)
        for key,row in f.items():
            self.assertTrue(key.startswith('profile.caseRemoval.'))
            for lang in ['en','zh-Hans']:self.assertTrue(row['localizations'][lang]['stringUnit']['value'])
        f=json.loads(read('docs/profile-case-picture-removal-registration.fragment.json'))
        self.assertEqual(f['central_files_modified'],[]);self.assertEqual(f['apple'],'NOT_RUN')
    def test_runtime_tests_and_source_parity_limits_are_explicit(self):
        s=read('Tests/AppUnitTests/ProfileCasePictureRemovalTests.swift')
        for name in ['testArbitraryReplacementAndPartialImageStringCannotBeStaged','testUnicodeOnlyPrewriteImageDriftPreventsDeletion',
                     'testUnknownClearRemainsLockedEvenWithEmptyReadbackAndNeverRepeatsPost','testSavedImagesCannotBeRestoredThroughStaleEditorAction']:
            self.assertIn(name,s)
        docs=read('docs/profile-case-picture-removal.md')
        for token in ['Apple: NOT_RUN','PENDING_PARENT_INTEGRATION','does not claim that Mini has a dedicated clear-all button','not acceptance evidence']:
            self.assertIn(token,docs)
if __name__=='__main__':unittest.main()
