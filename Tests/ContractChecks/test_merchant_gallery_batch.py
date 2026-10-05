"""Supplementary source wiring checks; Apple execution remains a separate gate."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class GalleryBatchContractTests(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_ordered_bounded_serial_picker(self):
        s = self.read('App/RetainedNativeImagePicker.swift')
        for token in ['config.selectionLimit = limit', 'config.selection = .ordered', 'results.count <= selectionLimit',
                      'self.byteLimit - retained', 'self.load(results, index: index + 1', 'picker === activePicker',
                      'self.generation == stamp', 'activePicker = nil; dismiss()']:
            self.assertIn(token, s)
        self.assertIn('selectBatch(limit: 1, byteLimit: RetainedSelectedImage.maximumBytes)?.first', s)
    def test_only_durable_consumption_precedes_context_reacquisition(self):
        s = self.read('App/MerchantGalleryBatchModel.swift').split('func use(', 1)[1].split('private static func sameOwner', 1)[0]
        self.assertLess(s.index('oldContext.uploads.applyLocally'), s.index('guard applied, batchID == batch'))
        self.assertLess(s.index('guard applied, batchID == batch'), s.index('binding.context()'))
        for token in ['binding.draft() == after', 'binding.accessFence() == accessFence', 'image.id == reviewSelectionID',
                      'image.scope == oldContext.scope', 'candidate == image', 'next.scope.accessRevision != oldContext.scope.accessRevision']:
            self.assertIn(token, s)
    def test_document_owned_queue_and_nonappend_cancellation(self):
        s = self.read('App/MerchantOperationsViews.swift')
        self.assertIn('let galleryBatch = MerchantGalleryBatchModel()', s)
        for token in ['galleryBatch.cancel(); coordinator.edit(value)', 'galleryBatch.cancel(); coordinator.prepare()',
                      'galleryBatch.cancel(); coordinator.discardChanges()', 'galleryBatch.cancel(); imageOwner?.invalidate()',
                      'validatesGalleryBatchScope(scope, coordinator: self.coordinator) == true']:
            self.assertIn(token, s)
        self.assertIn('if field == .gallery {', self.read('App/MerchantOperationsEditor.swift'))
    def test_existing_upload_authority_and_journal_remain_single(self):
        s = self.read('App/MerchantGalleryBatchModel.swift')
        for token in ['await context.uploads.confirm(review)', 'context.uploads.prepare(image, scope: context.scope)',
                      'blocked = true; pending = []; cropDraft = nil', 'case .uploaded, .uploading, .unknown: blocked = true']:
            self.assertIn(token, s)
        for token in ['URLSession', 'journal.record', 'journal.begin', 'uploadOSS', 'UserDefaults', 'FileManager']:
            self.assertNotIn(token, s)
    def test_crop_never_automatically_transmits(self):
        s = self.read('App/MerchantGalleryBatchModel.swift').split('func confirmCrop', 1)[1].split('func confirmUpload', 1)[0]
        self.assertIn('rect.width * 9 == rect.height * 16', s)
        self.assertIn('MerchantGalleryBatchLimits.accepts([image] + pending', s)
        self.assertNotIn('uploads.confirm', s)
    def test_owner_scope_validation_keeps_security_fences(self):
        s = self.read('App/MerchantRetainedImageHost.swift').split('func validatesGalleryBatchScope', 1)[1].split('func draftChanged', 1)[0]
        for token in ['credentials == capturedCredentials', 'access.allows(.gallery)', 'draft == capturedDraft',
                      'scope.accessRevision == draftRevision', 'scope.accountID == credentials.accountID',
                      'scope.epoch == loadedScope', 'scope.namespace == credentials.namespace']:
            self.assertIn(token, s)
    def test_authored_adverse_lifecycle_coverage(self):
        s = self.read('Tests/AppUnitTests/MerchantGalleryBatchTests.swift')
        for name in ['testNinthImageBoundAndOverselection', 'testFailedDurableAppliedAfterAppendStopsWithoutReacquisition',
                     'testUnknownStopsWholeQueueAndSurvivesCancel', 'testJournalBeginFailureDoesNotTransmit',
                     'testPartialSuccessThenRejectionRequiresExplicitSkip', 'testCancelAcknowledgedNeverDeletesOrRetries',
                     'testReplacementPreservesPositionAndRejectsOldCropOrBatch', 'testPickerBoundAndOrderedConfigurationWithoutPresentation']:
            self.assertIn(name, s)
    def test_private_ui_is_immediately_scope_gated_and_localized(self):
        import json
        view = self.read('App/MerchantGalleryBatchView.swift')
        self.assertIn('if batch.active && batch.current {', view)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key in ['image.galleryBatch.remaining %lld', 'image.galleryBatch.applied %lld']:
            for language in ['en', 'zh-Hans']:
                self.assertIn('%lld', catalog[key]['localizations'][language]['stringUnit']['value'])
    def test_production_gates_unchanged(self):
        self.assertIn('var nativeSelectionEnabled = false', self.read('App/RetainedImagePresenterHost.swift'))
        self.assertIn('enabled: false, approvedOrigins: []', self.read('App/RetainedImageContextCache.swift'))
