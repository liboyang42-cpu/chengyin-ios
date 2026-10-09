"""Narrow source contracts only. This is not Swift typechecking or UI execution."""
import hashlib,json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class MerchantReviewPhotoGalleryContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gallery=read('App/MerchantReviewPhotoGallery.swift');cls.fields=read('App/MerchantBusinessRecordViews.swift');cls.host=read('App/MerchantBusinessViews.swift')
    def test_only_three_product_paths_mount_the_gallery(self):
        self.assertIn('MerchantReviewPhotoGalleryEntry(owner: reviewPhotoOwner, row: row)',self.fields)
        self.assertEqual(self.host.count('reviewPhotoOwner: model, settlementReader:'),1)
        self.assertNotIn('AsyncImage(',self.fields)
        self.assertIn('.id(ObjectIdentifier(reviewPhotoOwner))',self.fields)
    def test_gallery_reuses_existing_validation_and_renderer(self):
        self.assertIn('urls.allSatisfy(MerchantBusinessRecord.safeHTTPS)',self.gallery)
        self.assertIn('AsyncImage(url: url, transaction: Transaction(animation: nil))',self.gallery)
        for forbidden in ['URLSession','URLRequest','UIApplication.shared','UIPasteboard','ShareLink','PhotosPicker','FileManager','UserDefaults','@AppStorage','dataTask','downloadTask','openURL']:
            self.assertNotIn(forbidden,self.gallery)
    def test_source_nine_limit_preserves_ordinals_and_duplicate_urls(self):
        self.assertIn('(1...9).contains(values.count)',self.gallery)
        self.assertIn('images.count <= 9',read('Core/MerchantBusinessDocuments.swift'))
        self.assertIn('ForEach(photos.indices, id: \\.self)',self.gallery)
        self.assertIn('ForEach(0..<session.count, id: \\.self)',self.gallery)
        self.assertNotIn('Set(sources',self.gallery);self.assertNotIn('Set(urls',self.gallery)
        self.assertNotIn('prefix(',self.gallery)
    def test_no_preview_or_neighbor_image_prefetch(self):
        entry=self.gallery.split('@MainActor struct MerchantReviewPhotoGalleryEntry: View')[1].split('@MainActor private struct MerchantReviewPhotoGallery: View')[0]
        self.assertNotIn('AsyncImage',entry);self.assertNotIn('NativeMediaImage',entry)
        self.assertIn('if position == session.index, let url = session.currentURL',self.gallery)
        self.assertEqual(self.gallery.count('AsyncImage(url:'),1)
    def test_exact_review_access_and_scope_identity(self):
        for text in ['owner.revision == revision','scope.accountID == currentScope.accountID','scope.epoch == currentScope.epoch',
                     'scope.realm.utf8.elementsEqual(currentScope.realm.utf8)','authorizationGeneration == authorization',
                     'Self.sameAccess(access, snapshot.access)','Self.fingerprint($0) == rowFingerprint',
                     'Data(SHA256.hash(data: data))','encoder.outputFormatting = [.sortedKeys]','a.name.map { Data($0.utf8) }']:
            self.assertIn(text,self.gallery)
    def test_only_current_review_pages_and_filtered_rows_are_eligible(self):
        for text in ['c.reader.isConfigured, c.isCurrent, !c.isBusy, c.failureKey == nil','case .reviews = snapshot.document.query',
                     'pages.matches(scope: owner.coordinator.reader.scope','pages.rows.filter(owner.listFilters.review.matches)',
                     'snapshot.document.rows.filter(owner.listFilters.review.matches)']:
            self.assertIn(text,self.gallery)
    def test_rendered_context_and_lifetime_are_checked_at_explicit_open(self):
        self.assertIn('let context = MerchantReviewPhotoContext(owner: owner, row: row)',self.gallery)
        self.assertIn('model.open(permit: permit, context: context, row: row, index: position)',self.gallery)
        self.assertIn('active, permit == generation, session == nil, let context, context.matches(row)',self.gallery)
        self.assertIn('@Published private(set) var generation = UUID()',self.gallery)
        self.assertNotIn('Task {',self.gallery)
    def test_stale_binding_getter_and_dismissal_capture_presented_id(self):
        for text in ['let presentedID = session?.id','self.session?.id == presentedID','guard value == nil, let presentedID',
                     'self?.cancel(id: presentedID)','guard session?.id == id else { return }','generation = UUID(); session?.retire(); session = nil']:
            self.assertIn(text,self.gallery)
    def test_late_image_phase_and_retry_are_generation_fenced(self):
        self.assertGreaterEqual(self.gallery.count('session.isImageCurrent(generation, at: position)'),2)
        self.assertIn('isCurrent && imageGeneration == generation && index == position',self.gallery)
        self.assertIn('guard isImageCurrent(generation, at: position) else { return }',self.gallery)
        self.assertIn('.id(session.imageGeneration)',self.gallery)
        self.assertIn('session.setImageZoom(session.zoom * Double(value), generation: generation, at: position)',self.gallery)
        self.assertIn('guard isImageCurrent(generation, at: position) else { return false }',self.gallery)
    def test_close_background_and_owner_change_retire_sensitive_sources(self):
        for text in ['active = false; sources = []; context = nil','onDisappear { model.retire() }',
                     'onDisappear { session.retire() }','if value != .active { session.retire(); close() }',
                     'onChange(of: owner.revision)','onChange(of: owner.listFilters)',
                     'onChange(of: owner.coordinator.reader.scope)','onChange(of: owner.coordinator.reader.authorizationGeneration)',
                     'onChange(of: MerchantReviewPhotoContext.fingerprint(row))']:
            self.assertIn(text,self.gallery)
        self.assertIn('.privacySensitive()',self.gallery)
    def test_zoom_navigation_is_bounded_accessible_and_unanimated(self):
        for text in ['guard value.isFinite','zoom = min(5, max(1, value))','sources.indices.contains(position)',
                     'index = position; zoom = 1; imageGeneration = UUID()','dynamicTypeSize.isAccessibilitySize',
                     'MagnificationGesture()','ScrollView([.horizontal, .vertical])','.accessibilityValue(Text(verbatim:']:
            self.assertIn(text,self.gallery)
        for key in ['previous','next','zoomOut','zoomIn','resetZoom']:
            self.assertIn('accessibilityIdentifier("merchant.reviewPhotos.'+key+'")',self.gallery)
        self.assertNotIn('withAnimation',self.gallery);self.assertNotIn('UIAccessibility.post',self.gallery)
        self.assertNotIn('AccessibilityFocusState',self.gallery)
    def test_author_tests_exercise_actual_model_binding_and_late_callbacks(self):
        tests=read('Tests/AppUnitTests/MerchantReviewPhotoGalleryTests.swift')
        self.assertEqual(len(re.findall(r'func test',tests)),28)
        for name in ['testOldAndEmptyActualBindingsCannotDismissNewPresentation','testBackgroundAndReappearanceCannotReplayOldTapOrImageCallback',
                     'testExactUTF8ReviewFingerprintRejectsCanonicallyEquivalentReplacement','testLoadedEarlierPagePhotoRemainsEligibleInCurrentAccumulation',
                     'testLoadSameBytesInvalidatesRenderedContextAndOldPresentation','testExistingUnknownJournalReservationSurvivesGalleryLifetime',
                     'testOldImageCompletionAndRetryCannotAffectNewOrdinalOrReturnToSameURL']:
            self.assertIn(name,tests)
    def test_unique_bilingual_labels_cover_gallery_keys(self):
        values=json.loads(read('Resources/MerchantReviewPhotoGalleryLocalizations.fragment.json'))['strings']
        keys=set(re.findall(r'"(merchant\.reviewPhotos\.[A-Za-z]+)"',self.gallery))
        labels=keys-{'merchant.reviewPhotos.retry'}
        self.assertEqual(labels,set(values))
        for value in values.values():
            for locale in ['en','zh-Hans']:self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
    def test_accepted_invitation_mount_is_preserved(self):
        self.assertIn('MerchantOperatorInvitationReceiptView(owner: model, presentationID: invitation.id)',self.host)
        self.assertIn('.id(invitation.id)',self.host)
    def test_gallery_never_changes_service_authority_or_unknown_journal(self):
        for forbidden in ['.execute(','.prepare(','.confirm(','.reserve(','.complete(','.load(','.access()', 'coordinator.invalidate()']:
            self.assertNotIn(forbidden,self.gallery)
        self.assertIn('No image request occurs in the entry.',self.gallery)
if __name__=='__main__':unittest.main(verbosity=2)
