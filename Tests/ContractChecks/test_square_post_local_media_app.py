"""App source contracts only: these do not compile Swift or execute Apple APIs."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SquarePostLocalMediaAppSourceTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()
    def model(self):
        return self.read('App/SquarePostLocalMediaPresentation.swift')
    def inspector(self):
        return self.read('App/SquarePostLocalMediaInspector.swift')
    def host(self):
        return self.read('App/SquareWorkspaceView.swift')
    def test_real_composer_mounts_picker_preview_and_existing_upload(self):
        s = self.host()
        for value in ['SquarePostLocalMediaPresentation()', 'SquarePostLocalMediaPreview(model: localMedia)',
                      'SquarePostLocalMediaPicker(request: request)', 'localMedia.accept(provider:',
                      'coordinator.upload(bytes: selected.bytes, mimeType: selected.mimeType',
                      'localMedia.applyUploadAcknowledgment(selected, apply: { draft.media.append(result) })', 'localMedia.remove()',
                      'draft.media.count >= 6', 'maximumImageBytes: SquareWorkspaceService.maximumUploadImageBytes']:
            self.assertIn(value, s)
        self.assertEqual(s.count('localMediaScopeIsCurrent(selected.scope)'), 2)
        self.assertNotIn('selectedBytes', s)
    def test_mini_order_is_preview_then_tools_then_uploaded_rows(self):
        s = self.host()
        self.assertLess(s.index('SquarePostLocalMediaPreview(model:'), s.index('localMedia.beginPicker'))
        self.assertLess(s.index('localMedia.beginPicker'), s.index('ForEach(draft.media)'))
        for identifier in ['squareWorkspace.selectPhoto', 'squareWorkspace.upload', 'squarePostLocalMedia.remove']:
            self.assertIn(identifier, s)
    def test_selected_item_picker_has_no_library_permission_or_other_host(self):
        s = self.read('App/SquarePostLocalMediaPicker.swift')
        for value in ['PHPickerConfiguration()', '.any(of: [.images, .videos])', 'configuration.selectionLimit = 1',
                      'guard !consumed else', 'if results.isEmpty { completed(nil, request) }',
                      'else if results.count == 1 { completed(results[0].itemProvider, request) }',
                      'completed(NSItemProvider(), request)']:
            self.assertIn(value, s)
        for forbidden in ['requestAuthorization', 'PHPhotoLibrary.shared', 'AVCaptureDevice', 'RetainedNativeImagePicker', 'ProjectTopicMedia']:
            self.assertNotIn(forbidden, s)
    def test_video_has_explicit_unavailable_row_without_read_upload_or_invented_limits(self):
        s = self.model()
        branch = 'if kind == .video { state = .videoUnavailable; return nil }'
        self.assertIn(branch, s)
        self.assertLess(s.index(branch), s.index('selection.beginInspection(id)'))
        for absent in ['AVPlayer', 'AVURLAsset', 'maximumVideoBytes:', 'maximumVideoDurationMilliseconds:', 'URLSession', 'uploadReceipt']:
            self.assertNotIn(absent, s + self.inspector())
        self.assertIn('No video file was read or uploaded', s)
        self.assertIn('case .bytesBoundMetadata(let evidence)', s)
        self.assertIn('guard state == .imagePreview', s)
    def test_provider_file_consumed_in_callback_with_actual_byte_bound(self):
        s = self.inspector()
        for value in ['loadFileRepresentation', 'url.isFileURL', 'FileHandle(forReadingFrom: url)',
                      'read(upToCount: 64 * 1024)', 'chunk.count <= maximumBytes - owned.count',
                      'owned.append(chunk)', 'operation.checkCancellation()', 'withTaskCancellationHandler',
                      'onCancel: { operation.cancel() }', 'guard terminal == nil', 'waiting?.resume(with: result)']:
            self.assertIn(value, s)
        for absent in ['Data(contentsOf:', 'UserDefaults', 'write(to:', 'copyItem', 'URLSession']:
            self.assertNotIn(absent, s)
    def test_real_pixels_and_actual_mime_precede_core_completion(self):
        s = self.inspector()
        for value in ['CGImageSourceCreateWithData', 'CGImageSourceGetType(source)', 'actualType == expectedType',
                      'CGImageSourceCreateThumbnailAtIndex', 'UIImage(cgImage: pixels)',
                      'try stream.append(bytes)', 'stream.finish(description)', 'Int64(bytes.count)']:
            self.assertIn(value, s)
        self.assertLess(s.index('CGImageSourceCreateThumbnailAtIndex'), s.index('stream.finish(description)'))
        self.assertNotIn('appDecodingPerformed: Bool { true }', s + self.model())
    def test_scope_and_attempt_guards_precede_late_callback_scope_failure(self):
        s = self.model()
        self.assertEqual(s.count('guard self.activeInspection == inspection.token else'), 2)
        self.assertEqual(s.count('guard scopeIsCurrent() else { self.invalidate(); return }'), 2)
        for branch in s.split('guard let self else { return }')[1:]:
            self.assertLess(branch.index('guard self.activeInspection'), branch.index('guard scopeIsCurrent()'))
        for value in ['pickerRequest == request', 'scope == request.scope', 'selection?.complete(result.evidence) == true',
                      'result.evidence.token == activeInspection', 'scope == result.evidence.token.scope']:
            self.assertIn(value, s)
    def test_interruption_clears_bytes_tokens_and_preview_without_remote_deletion_claim(self):
        s = self.model(); h = self.host()
        for value in ['loadTask?.cancel()', 'selection?.clear()', 'image = nil', 'previewRequest = nil',
                      'selection?.invalidate()', 'pickerRequest = nil', 'previewIsCurrent(request)']:
            self.assertIn(value, s)
        for value in ['.onDisappear { localMedia.invalidate() }', '.onChange(of: scenePhase)',
                      '.onChange(of: draft.workflowID)', '.onChange(of: coordinator.session)',
                      'if status == "squareWorkspace.sessionChanged"', 'scope.draftID == draft.workflowID',
                      'scope.lane == lane', 'try coordinator.refreshLocal(); return true']:
            self.assertIn(value, h)
        self.assertNotIn('deleteOwnedObject', s + h)
    def test_reuses_core_while_image_policy_and_existing_server_grants_stay_separate(self):
        s = self.model()
        self.assertIn('selection = SquarePostLocalMediaSelection(scope: scope)', s)
        self.assertIn('selection.beginInspection(id)', s)
        self.assertIn('selection?.cancelInspection', s)
        self.assertIn('selection?.fail(token)', s)
        self.assertIn('!coordinator.grants.live || !coordinator.grants.media', self.host())
        self.assertNotIn('SquareWorkspaceGrants(', s)
    def test_movie_representation_takes_priority_over_image_fallback_without_byte_read(self):
        s = self.model()
        movie = 'let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)'
        image = 'let imageType = isVideo ? nil : SquarePostLocalMediaInspector.imageType(in: provider)'
        self.assertIn(movie, s); self.assertIn(image, s)
        self.assertLess(s.index(movie), s.index(image))
        self.assertNotIn('imageType == nil && provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)', s)
        tests = self.read('Tests/AppUnitTests/SquarePostLocalMediaPresentationTests.swift')
        self.assertIn('testMixedMovieAndJPEGProviderNeverDowngradesToImageOrReadsRepresentations', tests)
        self.assertIn('[[UTType.jpeg, .movie], [UTType.movie, .jpeg]]', tests)
    def test_unsupported_selection_keeps_explicit_pending_media_fence(self):
        s = self.model()
        self.assertIn('var hasSelection: Bool { selectedKind != nil || unresolvedSelection }', s)
        self.assertIn('remove(); unresolvedSelection = true; state = .failed; return false', s)
        self.assertIn('selectedKind = nil; unresolvedSelection = false; state = .empty', s)
        tests = self.read('Tests/AppUnitTests/SquarePostLocalMediaPresentationTests.swift')
        for name in ['testUnsupportedHEICSelectionBlocksSaveUntilExplicitRemoval',
                     'testUnsupportedWebPSelectionNeverReadsAndBlocksSaveUntilExplicitRemoval',
                     'testWebPProviderWithJPEGRepresentationUsesOnlyDecodedJPEG',
                     'testUnknownVideoRepresentationBlocksSaveUntilExplicitRemoval',
                     'testProviderWithNoUsableRepresentationRemainsAnUnresolvedSelection',
                     'testUnsupportedReselectionCannotFallBackToPublishingWithoutTheFailedMedia']:
            self.assertIn(name, tests)
    def test_unknown_raw_fixture_is_distinct_from_known_video_policy_fixture(self):
        tests = self.read('Tests/AppUnitTests/SquarePostLocalMediaPresentationTests.swift')
        unknown = tests.split('func testUnknownVideoRepresentationBlocksSaveUntilExplicitRemoval()', 1)[1].split('\n    func ', 1)[0]
        for value in ['"com.questify.tests.unknown-video"', 'unsupportedProvider(typeIdentifier: typeIdentifier)',
                      'XCTAssertEqual(provider.registeredTypeIdentifiers, [typeIdentifier])',
                      'XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier))',
                      'XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.image.identifier))',
                      'XCTAssertNil(SquarePostLocalMediaInspector.imageType(in: provider))',
                      'XCTAssertFalse(model.accept(', 'XCTAssertEqual(model.state, .failed)',
                      'XCTAssertTrue(model.unresolvedSelection)', 'XCTAssertTrue(model.hasSelection)',
                      'XCTAssertNil(model.loadTask)', 'XCTAssertNil(model.imageUpload)', 'XCTAssertNil(model.thumbnail)',
                      'model.cancelPicker()', 'model.remove(); XCTAssertFalse(model.hasSelection); XCTAssertFalse(model.unresolvedSelection)']:
            self.assertIn(value, unknown)
        self.assertNotIn('unsupportedProvider(.video)', unknown)
        known = tests.split('func testMissingVideoPolicyNeverReadsProviderAndCannotMakeImageUpload()', 1)[1].split('\n    func ', 1)[0]
        for value in ['[UTType.movie, .video, .mpeg4Movie]',
                      'XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier))',
                      'unexpected.isInverted = true', 'unexpected.fulfill()',
                      'XCTAssertEqual(model.state, .videoUnavailable)', 'XCTAssertNil(model.loadTask)',
                      'XCTAssertNil(model.imageUpload)', 'XCTAssertTrue(model.hasSelection)']:
            self.assertIn(value, known)
    def test_actual_upload_callback_requires_current_selection_and_consumes_once(self):
        h = self.host(); s = self.model()
        self.assertIn('localMedia.isCurrentUpload(selected)', h)
        self.assertIn('guard localMedia.applyUploadAcknowledgment(selected, apply: { draft.media.append(result) }) else', h)
        self.assertEqual(h.count('draft.media.append(result)'), 1)
        self.assertIn('guard isCurrentUpload(upload) else { return false }', s)
        self.assertIn('apply(); clearUploaded(upload); return true', s)
        self.assertIn('imageUpload?.reference == upload.reference && scope == upload.scope', s)
        tests = self.read('Tests/AppUnitTests/SquarePostLocalMediaPresentationTests.swift')
        for name in ['testCurrentUploadAcknowledgmentAppendsExactlyOnceAndConsumesSelection',
                     'testBackgroundRetiredSelectionRejectsLateUploadAcknowledgment',
                     'testPageExitAndSameScopeReturnRejectLateUploadAcknowledgment',
                     'testRemovedSelectionRejectsLateUploadAcknowledgment',
                     'testReselectedImageRejectsOldUploadAcknowledgmentWithoutClearingNewImage']:
            self.assertIn(name, tests)
    def test_pending_selection_cannot_be_silently_omitted_by_server_save_or_publish(self):
        s = self.host()
        for identifier in ['saveServer', 'review']:
            self.assertRegex(s, r'\.disabled\(!coordinator\.grants\.live \|\| coordinator\.busy \|\| localMedia\.hasSelection\)\.accessibilityIdentifier\("squareWorkspace\.' + identifier + r'"\)')
        self.assertIn('Local media is not saved with drafts', self.model())
    def test_authored_app_tests_cover_real_decode_and_late_callback_boundaries(self):
        s = self.read('Tests/AppUnitTests/SquarePostLocalMediaPresentationTests.swift')
        for value in ['testImageDecodeOwnsBytesAndPreviewWithoutUpgradingCoreAuthority',
                      'testImageDecodeRejectsCorruptionAndProviderMIMEContradiction',
                      'testImageByteLimitAllowsExactBoundAndRejectsOneLess',
                      'testRemoveRetiresInflightAttemptAndDropsAllOwnedPixels',
                      'testCancelReadRejectsLateResultAndRetainsRemovableCancelledRow',
                      'testCancelReselectionPreservesPreviousReadyImage',
                      'testMissingVideoPolicyNeverReadsProviderAndCannotMakeImageUpload',
                      'testPageExitOrBackgroundInvalidatesPreviewAndSameScopeReopenCannotRestoreIt',
                      'testAsyncOldScopeCompletionDoesNotInvalidateNewAccountSelection',
                      'testAsyncCancelledReadFailureCannotOverwriteReselectedImage',
                      'testCoreCopiedStreamStillCannotRecoverAfterFailureThroughAppDecoder']:
            self.assertIn(value, s)
        self.assertEqual(len(re.findall(r'func test\w+\(', s)), 36)

if __name__ == '__main__':
    unittest.main()
