"""Bounded ordinary story-image consumer checks; Swift methods are authored, not executed here."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ProjectStoryImageContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_real_existing_upload_command_remains_separate_from_asset_and_release_proofs(self):
        source = self.read('Core/ProjectStoryImageUpload.swift')
        for token in ['api/common/uploadOSS', 'image_free', 'name=\\"file\\"', 'story.jpg', 'bytes.count <= 64 * 1024', 'try check(original)', 'reference: reference']:
            self.assertIn(token, source)
        self.assertNotIn('api/topic/cover', source)
        self.assertNotIn('sourceVersion', source)
        self.assertNotIn('URLSession.shared', source)
        self.assertLess(source.index('if status == 401'), source.index('let row = try ApprovedTopicReleaseWire'))

    def test_normal_factory_and_outer_clone_require_independent_current_approval(self):
        root = self.read('App/AppCompositionRoot.swift')
        session = self.read('App/AppSession.swift')
        self.assertIn('ProjectStoryImageUploadApproval? = { _ in nil }', root)
        self.assertIn('nativePicker: Bool = false', self.read('Core/ProjectStoryImageUpload.swift'))
        self.assertIn('transport.projectStoryImageUploadApproval = { self.projectStoryImageUploadApproval($0) }', root)
        self.assertIn('self.projectConfigurationRevision == revision', session)
        self.assertIn('projectEditConfigurationRevision() == revision', root)
        self.assertIn('makeProjectStoryImageUploadTransport()', session)
        route = self.read('App/ProjectStoryImageCompositionRoute.swift')
        for token in ['request.httpBodyStream == nil', 'request.url == baseURL', 'body.suffix(last.count)', 'RetainedSelectedImage.maximumBytes', 'image_free']:
            self.assertIn(token, route)

    def test_exact_draft_target_and_existing_length_limit_fence_apply(self):
        target = self.read('Core/ProjectStoryImageTarget.swift')
        for token in ['exactData(draft)', 'originalDraftHash', 'receipt.reference.utf16.count <= 500', 'blocks[bi].url = receipt.reference', 'block.url.utf8.elementsEqual', 'resultingBlockID']:
            self.assertIn(token, target)
        host = self.read('App/ProjectStoryImagePresentation.swift')
        for token in ['presentation?.id == original.id', 'editor.persistLocalChange(next, lease:', 'editor.editorIncarnation ==', 'ObjectIdentifier(source)', 'original.target.matches']:
            self.assertIn(token, host)

    def test_received_facts_are_independent_from_display_state_and_recover_locally(self):
        flow = self.read('Core/ProjectStoryImageFlow.swift')
        view = self.read('App/ProjectStoryImageAuthorView.swift')
        self.assertIn('journal.begin(target:', flow)
        self.assertIn('journal.remember(received', flow)
        self.assertIn('hasUnstoredReceipt:Bool{unstoredReceipt != nil}', flow)
        self.assertIn('if flow.hasUnstoredReceipt', view)
        self.assertIn('alreadyApplied', flow)
        self.assertNotIn('source.upload', flow.split('public func persistReceipt()', 1)[1])
        self.assertNotIn('source.status', flow)
        self.assertNotIn('Data(contentsOf:', view)
        self.assertNotIn('AsyncImage', view)

    def test_real_chapter_entry_uses_bounded_picker_and_source_aspect_crop(self):
        view = self.read('App/ProjectEditDetailForms.swift')
        self.assertIn('openImage(imageOpening)', view)
        self.assertIn('storyImages.open(opening)', view)
        self.assertIn('storyImages.presentation == nil, storyAudios.presentation == nil', view)
        self.assertNotIn('Button("projectEdit.addImage") { appendBlock(.image) }', view)
        panel = self.read('App/ProjectStoryImageAuthorView.swift')
        for token in ['TemplateImageCropSession', 'TemplateImageCropView', 'selectionApproval:', 'flow.claimUpload(review)', 'ProjectStoryImagePreparedReferences', 'payload["chapters"]']:
            self.assertIn(token, panel)
        for absent in ['requestAuthorization', 'PHPhotoLibrary', 'AVCapture', 'AVAudioRecorder']:
            self.assertNotIn(absent, panel)

    def test_bilingual_production_keys_and_test_only_generated_selection(self):
        fragment = json.loads(self.read('docs/project-story-image-localizations.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment), 20)
        for key, entry in fragment.items():
            self.assertEqual(set(entry), {'en', 'zh-Hans'})
            for language, value in entry.items():
                self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], value)
        synthetic = self.read('App/ProjectStoryImageSynthetic.swift')
        self.assertTrue(synthetic.startswith('#if DEBUG'))
        self.assertIn('UIGraphicsImageRenderer', synthetic)
        self.assertNotIn('ProjectStoryImageSynthetic', self.read('App/AppSession.swift'))

    def test_authored_regressions_keep_complete_journeys_and_recovery_assertions(self):
        core = self.read('Tests/CoreTests/ProjectStoryImageTests.swift')
        app = self.read('Tests/AppUnitTests/ProjectStoryImagePresentationTests.swift')
        composition = self.read('Tests/AppUnitTests/ProjectStoryImageCompositionTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 12)
        self.assertEqual(len(re.findall(r'func test\w+\(', app)), 13)
        self.assertEqual(len(re.findall(r'func test\w+\(', composition)), 5)
        for token in ['testPartialLocalEnvelopeSave', 'testReceiptPersistenceFailureReopens', 'testRetainedCropCallback', 'testActualApplySavesRestores']:
            self.assertIn(token, app)
        for token in ['testCapturedOpeningCannotReviveAfterStoryOrderABA', 'testReceivedReferenceCannotApplyAfterDeleteAndRestoreSameBlockIDs', 'testSuccessfulOwnAppendKeepsMarkerRetryButExternalOrderABARetiresIt']:
            self.assertIn(token, app)
        host = self.read('App/ProjectStoryImagePresentation.swift')
        self.assertIn('storyTopologyRevision: editor.storyTopologyRevision', host)
        self.assertIn('editor.storyTopologyRevision == (expected ?? original.storyTopologyRevision)', host)
        self.assertIn('ProjectEditPendingMaterials.exactData(editor.draft) == expected', host)
        for name, seconds in [('ProjectStoryImageFlowTests', 900), ('ProjectStoryImageCancellationFlowTests', 720)]:
            ui = self.read('Tests/AppUITests/' + name + '.swift')
            self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 1)
            self.assertIn(str(seconds) + ' seconds', ui)
            self.assertIn('assertFixtureEnvironment', ui)
            self.assertIn('storyImageUploadCount', ui)


if __name__ == '__main__':
    unittest.main()
