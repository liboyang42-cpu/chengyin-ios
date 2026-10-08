"""Focused source contracts only; Swift/Apple/runtime acceptance is separate."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
def contracts(presentation, inspector, client, host, composition):
    for token in ["editor.topicMediaContext == original.context", "editor.isCurrentStarterLease(original.lease)",
                  "ObjectIdentifier(source) == ObjectIdentifier(original.source)", "source.policy(context: original.context, field: original.field) == original.policy",
                  "original.selection.begin(", "original.selection.prepareInspection(", "ProjectTopicMediaInspectionEvidence.inspect(",
                  "original.selection.finishInspection(", "original.selection.confirm(", "original.source.permittedURL(receipt",
                  "editor.persistLocalChange(next, lease: original.lease)", "original.selection.state == .picking(ticket)",
                  "receipt.attemptID == attemptID", "opening?.id == original.id", "original.selection.state != .closed", "original.selection.retire(); return false", "appended.utf16.count <= 2000"]:
        assert token in presentation, token
    for token in ["O_NOFOLLOW", "O_NONBLOCK", "fstat(descriptor, &before)", "mode_t(S_IFREG)",
                  "UInt64(chunk.count) <= ceiling - UInt64(bytes.count)", "try consume(chunk)", "bytes == image.jpeg",
                  "CGImageSourceCreateImageAtIndex", "CGImageSourceGetStatus(source) == .statusComplete",
                  "decodedContentSHA256: SHA256.hash(data: bytes)", "request.context == context", "request.reference == reference"]:
        assert token in inspector, token
    for token in ["approval: ProjectTopicImageUploadApproval? = nil", "currentApproval() == approval", "approval.fields.contains(field)",
                  "context.owner == .personal", "attempts.insert(attemptID).inserted", "try check(original, context: context, field: field)",
                  'case cover, gallery', '"image_3_4"', '"image_16_9"', '"api/common/uploadOSS"',
                  'receipt.context == context', 'reference.utf16.count <= (field == .cover ? 255 : 2000)']:
        assert token in client, token
    for token in ["RetainedImagePresenterHost", "projectTopicMedia.videoUnavailable", "projectTopicMedia.upload", "projectTopicMedia.apply",
                  "ProjectTopicImageCompositionRoute", "ProjectTopicImage-", "request.httpBodyStream == nil"]:
        assert token in host, token
    assert 'projectTopicImageUploadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProjectTopicImageUploadApproval? = { _ in nil }' in composition
    assert 'guard let issued = projectTopicImageUploadApproval(context)' in composition
    assert 'issued.fields.contains(field)' in composition
    return True

class ProjectTopicMediaAppContracts(unittest.TestCase):
    def sources(self):
        return tuple(read(x) for x in ['App/ProjectTopicMediaPresentation.swift', 'App/ProjectTopicMediaInspector.swift',
            'Core/ProjectTopicImageUpload.swift', 'App/ProjectTopicMediaHost.swift', 'App/AppCompositionRoot.swift'])
    def test_exact_evidence_upload_and_apply_chain(self): self.assertTrue(contracts(*self.sources()))
    def test_actual_host_mount_and_independent_composition(self):
        p, i, c, h, composition = self.sources()
        self.assertIn('ProjectTopicMediaHost(editor: model)', read('App/ProjectEditView.swift'))
        self.assertIn('topicImageSource: (any ProjectTopicImageUploading)? = nil', read('Core/ProjectEditCoordinator.swift'))
        session = read('App/AppSession.swift')
        self.assertIn('makeProjectTopicImageSource(owner: target.owner)', session)
        self.assertIn('self.composition.projectTopicImageUploadApproval(context)', session)
        self.assertIn('transport.projectTopicImageUploadApproval = { self.projectTopicImageUploadApproval($0) }', composition)
        for forbidden in ['storyImageSource', 'RetainedImageUploadReview', 'OwnedTopicCoverServing', 'ownedCoverSource']:
            self.assertNotIn(forbidden, p + c)
    def test_one_image_picker_no_video_or_network_preview(self):
        picker = read('App/ProjectTopicMediaPicker.swift')
        self.assertIn('RetainedNativeImagePicker', picker); self.assertIn('selectionApproval: permitted', picker)
        actual = read('App/RetainedNativeImagePicker.swift')
        self.assertIn('config.filter = .images', actual); self.assertIn('RetainedImageSanitizer.sanitize', actual)
        p, i, c, h, _ = self.sources()
        for forbidden in ['.videos', 'AVPlayer', 'AsyncImage', 'loadFileRepresentation', 'PhotosPicker']:
            self.assertNotIn(forbidden, p + i + h + picker)
        self.assertIn('CGImageSourceGetCount(source) == 1', i)
        self.assertNotIn('image_free', c)
    def test_editor_revision_account_and_scope_fences(self):
        p = self.sources()[0]
        for token in ['ownsVisit, fullEdit', 'coordinator.session', 'coordinator.identity', 'draftMutationRevision',
                      'draft.product, owner: draft.owner', 'publishMode: mode, editScope: snapshot.scope', 'visit: editorIncarnation']:
            self.assertIn(token, p)
        self.assertIn('state = .unknown', p)
        self.assertIn('state == .preview', p.split('func upload(', 1)[1])
        self.assertIn('state = .uploading', p)
        self.assertIn('original.selection.retire(); task?.cancel()', p)
    def test_local_policy_not_transmitted_or_used_as_credential(self):
        client = self.sources()[2]
        for forbidden in ['LocalSelectionIntent', 'contentSHA256', 'topicId', 'assetId', 'ownerId']:
            self.assertNotIn(forbidden, client)
        self.assertIn('currentApproval: @escaping () -> ProjectTopicImageUploadApproval?', client)
        self.assertIn('request.setValue(original.token, forHTTPHeaderField: "Authorization")', client)
        self.assertIn('body.append(image.jpeg)', client)
    def test_existing_gallery_order_not_normalized_or_silently_truncated(self):
        p = self.sources()[0]
        self.assertIn('next.imgArr + "," + permittedURL', p)
        self.assertIn('Self.galleryCount(next.imgArr) < 9', p)
        self.assertIn('$0 == "," || $0 == ";"', p)
        self.assertNotIn('.prefix(', p)
    def test_authored_apple_tests_are_not_claimed_as_run(self):
        app = read('Tests/AppUnitTests/ProjectTopicMediaPresentationTests.swift')
        core = read('Tests/CoreTests/ProjectTopicImageUploadTests.swift')
        for token in ['testSameByteDraftReplacementAndAccountChangeRejectOldApply', 'testLocalSaveRetryNeverRepeatsUpload',
                      'testUnknownHasNoAutomaticOrRepeatedUploadAndNoApply', 'testCancelledPickerLateCompletionCannotReplaceNewCrop',
                      'testNativeInspectionEvidenceAndCropRatiosAreActualPixels']:
            self.assertIn(token, app)
        self.assertGreaterEqual(len(re.findall(r'func test\w+', core)), 7)
        doc = read('docs/project-topic-media-app.md')
        for token in ['NOT_RUN', 'default nil', 'image_3_4', 'image_16_9', 'not end-to-end', '13 paths']:
            self.assertIn(token, doc)
    def test_negative_controls_detect_removed_boundaries(self):
        values = self.sources()
        mutations = [(0, 'editor.topicMediaContext == original.context'), (0, 'original.source.permittedURL(receipt'),
                     (0, 'original.selection.prepareInspection('), (0, 'appended.utf16.count <= 2000'),
                     (1, 'O_NOFOLLOW'), (1, 'try consume(chunk)'), (1, 'bytes == image.jpeg'),
                     (2, 'currentApproval() == approval'), (2, 'attempts.insert(attemptID).inserted'),
                     (4, 'issued.fields.contains(field)')]
        for index, token in mutations:
            changed = list(values); changed[index] = changed[index].replace(token, 'REMOVED')
            with self.subTest(token=token), self.assertRaises(AssertionError): contracts(*changed)

if __name__ == '__main__': unittest.main()
