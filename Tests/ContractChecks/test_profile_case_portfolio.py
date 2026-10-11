"""Source-only P107 portfolio checks; not Swift compilation or native execution."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

def read(path): return (ROOT / path).read_text()
def section(path, start, end): return read(path).split(start, 1)[1].split(end, 1)[0]

class ProfileCasePortfolioContracts(unittest.TestCase):
    def test_decode_distinguishes_missing_null_and_exact_backend_key(self):
        s = section('Core/ProfileEditContracts.swift', 'public struct ProfileEditSnapshot', 'public struct ProfileEditDraft')
        self.assertIn('case caseIntroduction = "caseIntroducton"', s)
        self.assertIn('if c.contains(.caseIntroduction) { caseIntroduction = try preserved(.caseIntroduction) }', s)
        self.assertIn('else { caseIntroduction = nil }', s)
        self.assertIn('try c.decodeIfPresent(String.self, forKey: key) ?? ""', s)

    def test_payload_only_adds_explicit_optional_edit_and_preserves_media(self):
        s = section('Core/ProfileEditContracts.swift', 'public struct ProfileEditPayload', 'public struct ProfileEditSession')
        for token in ['public let caseIntroduction: String?', 'case caseIntroduction = "caseIntroducton"',
                      'draft.caseIntroduction == nil || snapshot.caseIntroduction != nil', 'caseIntroduction = draft.caseIntroduction',
                      'wechat = removesContactQR ? "" : snapshot.wechat; casePics = snapshot.casePics']:
            self.assertIn(token, s)
        self.assertNotIn('caseIntroduction = draft.normalized', s)
        self.assertNotIn('casePics.split', s)
        self.assertNotIn('func encode(', s)  # Synthesized optional encoding omits nil.

    def test_exact_readback_checks_explicit_case_before_other_fields(self):
        s = section('Core/ProfileEditContracts.swift', 'public func matches', 'public struct ProfileEditSession')
        exact = 'if let caseIntroduction, !ProfileCasePortfolio.sameText(caseIntroduction, snapshot.caseIntroduction) { return false }'
        self.assertIn(exact, s); self.assertLess(s.index(exact), s.index('if avatarReplacement != nil'))

    def test_optional_comparison_distinguishes_nil_and_unicode_bytes(self):
        s = read('Core/ProfileCasePortfolio.swift')
        for token in ['case (nil, nil): return true', 'lhs.utf8.elementsEqual(rhs.utf8)', 'default: return false']:
            self.assertIn(token, s)
        self.assertNotIn('lhs == rhs', s)

    def test_case_text_survives_normalization_and_avatar_operations(self):
        s = read('Core/ProfileEditContracts.swift')
        self.assertIn('avatarReplacement: value, caseIntroduction: caseIntroduction, removesContactQR: removesContactQR)', s)
        self.assertIn('avatarReplacement: avatarReplacement, caseIntroduction: caseIntroduction, removesContactQR: removesContactQR) }', s)
        self.assertIn('caseIntroduction: draft.caseIntroduction, removesContactQR: draft.removesContactQR)', read('App/ProfileEditView.swift'))
        s = section('Core/ProfileEditContracts.swift', 'public func hasChanges', 'public var isValid')
        self.assertIn('ordinary.caseIntroduction = nil', s)
        self.assertIn('!ProfileCasePortfolio.sameText($0, snapshot.caseIntroduction)', s)
        self.assertIn('return ordinary != snapshot.draft.normalized || caseChanged', s)

    def test_case_changes_participate_in_model_draft_snapshot_and_exit_fences(self):
        s = read('App/ProfileEditView.swift')
        self.assertEqual(s.count('ProfileCasePortfolio.sameText(lhs.caseIntroduction, rhs.caseIntroduction)'), 2)
        self.assertIn('draft.caseIntroduction.map { !ProfileCasePortfolio.sameText($0, snapshot.caseIntroduction) }', s)
        self.assertIn('model.draft.hasChanges(comparedTo: $0)', s)
        self.assertIn('guard !exitCommitted, !Task.isCancelled else { return }', s)

    def test_field_confirm_preserves_exact_text_or_restores_nil_noop(self):
        s = section('App/ProfileEditView.swift', 'func confirmTextEdit', 'func ownsAvatarScope')
        self.assertIn('case .caseIntroduction:', s)
        self.assertIn('guard snapshot.caseIntroduction != nil else { return false }', s)
        self.assertIn('next.caseIntroduction = ProfileCasePortfolio.sameText(text, snapshot.caseIntroduction) ? nil : text', s)
        self.assertIn('Self.sameDraft(draft, value.draft)', s)
        self.assertIn('Self.sameSnapshot(snapshot, value.snapshot)', s)
        self.assertNotIn('trimmingCharacters', s)
        self.assertNotIn('await ', s)

    def test_review_and_prewrite_detect_description_drift(self):
        s = read('Core/ProfileEditCoordinator.swift')
        self.assertIn('guard draft.hasChanges(comparedTo: original) else', s)
        self.assertIn('draft.caseIntroduction == nil || ProfileCasePortfolio.sameText(latest.caseIntroduction, original.caseIntroduction)', s)
        self.assertIn('ProfileCasePortfolio.sameText(latest.caseIntroduction, value.snapshot.caseIntroduction)', s)
        self.assertIn('if unresolved.acknowledged && matches', s)
        self.assertIn('messageKey = "profile.edit.readbackUnconfirmed"', s)

    def test_avatar_fingerprints_bind_case_description_but_keep_omission_compatible(self):
        s = section('Core/ProfileAvatarUpload.swift', 'public enum ProfileAvatarExact', 'public struct ProfileAvatarTarget')
        self.assertEqual(s.count('if let text = value.caseIntroduction { parts += ["caseIntroducton", text] }'), 2)
        self.assertEqual(s.count('return hash(strings(parts))'), 2)

    def test_image_projection_keeps_raw_order_and_duplicates_and_bounded_count(self):
        s = read('Core/ProfileCasePortfolio.swift')
        for token in ['casePics.split(separator: ";", omittingEmptySubsequences: false)',
                      '.map(String.init).filter', 'images = Array(values.prefix(100))',
                      'omittedImageCount = max(0, values.count - images.count)']:
            self.assertIn(token, s)
        for forbidden in ['Set(', '.sorted(', 'URLSession', 'casePics =', '.joined(']: self.assertNotIn(forbidden, s)

    def test_ui_uses_unique_editor_scope_and_existing_disabled_default_reader(self):
        editor = read('App/ProfileTextFieldEditor.swift')
        self.assertIn('(draft.caseIntroduction ?? snapshot.caseIntroduction ?? "")', editor)
        self.assertIn('edit.field == .caseIntroduction, edit.snapshot.caseIntroduction == nil', editor)
        self.assertIn('.disabled(edit.field == .contactQR || (edit.field == .caseIntroduction && edit.snapshot.caseIntroduction == nil))', editor)
        self.assertIn('ProfileCasePortfolioSection(casePics: edit.snapshot.casePics, scope: edit.id, reader: caseImageReader)', editor)
        view = read('App/ProfileEditView.swift')
        self.assertIn('caseImageReader: (any RetainedPublicImageReading)? = nil', view)
        self.assertIn('ProfileTextFieldEditor(edit: value, caseImageReader: caseImageReader,', view)
        self.assertIn('.id(value.id)', view)
        self.assertIn('if let text = value.payload.caseIntroduction', view)
        self.assertIn('if field == .caseIntroduction, model.coordinator.snapshot?.caseIntroduction == nil', view)
        gallery = read('App/ProfileCasePortfolioSection.swift')
        self.assertIn('NativeMediaGalleryEntry(sources: portfolio.images, scope: scope,', gallery)
        for forbidden in ['URLSession', 'AsyncImage', 'PhotosPicker', 'fileImporter', '.save(', 'enabled: true', '.remove(', '.upload(']:
            self.assertNotIn(forbidden, gallery)

    def test_fixture_uses_reserved_urls_with_no_production_reader(self):
        source = read('Core/ProfileEditSyntheticFixtures.swift')
        self.assertIn('caseIntroducton', source)
        self.assertIn('if let text = payload.caseIntroduction { caseIntroduction = text }', source)
        self.assertIn('https://profile-fixture.invalid/one.jpg;https://profile-fixture.invalid/two.jpg', source)
        fixture = read('App/ProfileEditFixtureSupport.swift')
        self.assertIn('case "portfolioImages": mode = .portfolioImages', fixture)
        self.assertNotIn('caseImageReader:', fixture)

    def test_fragments_declare_two_intentional_overrides_and_no_grants(self):
        f = json.loads(read('Resources/ProfileCasePortfolioLocalizations.fragment.json'))
        self.assertEqual(len(f), 9)
        for row in f.values():
            for lang in ['en', 'zh-Hans']: self.assertTrue(row['localizations'][lang]['stringUnit']['value'])
        registry = json.loads(read('docs/profile-case-portfolio-registration.fragment.json'))
        self.assertEqual(registry['status'], 'PENDING_PARENT_INTEGRATION')
        self.assertEqual(registry['intentional_localization_overrides'], ['profile.exitDiscard.message', 'profile.reloadDiscard.message'])
        self.assertEqual(registry['central_files_modified'], [])

    def test_tests_cover_end_to_end_new_field_and_limits_are_honest(self):
        core = read('Tests/CoreTests/ProfileCasePortfolioTests.swift')
        app = read('Tests/AppUnitTests/ProfileCasePortfolioTests.swift')
        for token in ['testExplicitEmptyClearsAndMissingSnapshotCannotBeOverwritten', 'testReadbackMustContainExactChangedCaseText',
                      'testImageProjectionPreservesOrderDuplicatesAndNonblankBytes', 'testAvatarFingerprintsCoverCaseTextPresenceAndExactBytes']:
            self.assertIn(token, core)
        for token in ['testCaseOnlySaveIsReadBackAndReopensSavedDescription', 'testUnknownWriteNeverUnlocksEvenWhenCaseReadbackMatches',
                      'testMismatchedReadbackKeepsLockUntilAcknowledgedExactReadback', 'testRejectedSaveAndFailedRefreshKeepCaseDraft']:
            self.assertIn(token, app)
        docs = read('docs/profile-case-portfolio.md')
        for token in ['Apple: NOT_RUN', 'PENDING_PARENT_INTEGRATION', 'not claimed current Mini visual parity', 'No new origin']:
            self.assertIn(token, docs)

if __name__ == '__main__': unittest.main()
