"""Bounded local media review host; source checks are not Apple UI acceptance."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class TemplateMediaReviewUIContracts(unittest.TestCase):
    def test_controller_uses_captured_targets_and_never_writes_references(self):
        source = read('App/TemplateMediaReviewController.swift')
        for token in ['TemplateAuthoringMediaReferenceSnapshot', 'beginSelection(target: row.target)',
                      'scope?.isCurrent(value.selection)', 'generation == model.mediaReviewGeneration',
                      'inventoryIsCurrent', 'Data($0.utf8)', 'finishSelection(value.selection)',
                      'scope?.cancelSelection(value.selection)', 'scope?.topologyDidChange()']:
            self.assertIn(token, source)
        for token in ['URLSession', 'HTTPTransport', 'uploadOSS', 'RetainedUploadedImage', 'ImageUploadJournal',
                      '.questionImg =', '.questionAudio =', '.audioUrl =', 'setStory(', 'setChoiceOptionMedia(']:
            self.assertNotIn(token, source)

    def test_panel_cannot_reacquire_new_review_or_dismiss_it_with_old_id(self):
        panel = read('App/TemplateMediaReviewPanel.swift')
        self.assertIn('controller.presentation(for: original.id)', panel)
        self.assertIn('let originalID = controller.review?.id', panel)
        self.assertIn('controller.cancel(originalID: originalID)', panel)
        self.assertIn('controller.cancel(originalID: original.id)', panel)
        self.assertNotIn('onDismiss:', panel)
        self.assertIn('controller.confirmCrop(value.review, id: id, rect: rect)', panel)
        controller = read('App/TemplateMediaReviewController.swift')
        self.assertIn('value.id == originalID, isCurrent(value)', controller)
        self.assertIn('let next = Review(id: value.id, selection: selection', controller)

    def test_default_gates_and_metadata_only_audio_remain_truthful(self):
        controller = read('App/TemplateMediaReviewController.swift')
        self.assertIn('imageSelectionApproved: @escaping () -> Bool = { false }', controller)
        self.assertIn('imageSelectionApproved(),', controller)
        self.assertNotIn('TemplateAudioDocumentPickerAdapter', controller)
        panel = read('App/TemplateMediaReviewPanel.swift')
        self.assertIn('.disabled(true).accessibilityIdentifier("templateMedia.apply")', panel)
        self.assertIn('TemplateImageCropRenderer.validatedImage(selected)', panel)
        for forbidden in ['AsyncImage', 'AVPlayer', 'AVAudioPlayer', 'URL(string:', 'Data(contentsOf:']:
            self.assertNotIn(forbidden, panel)
        launch = read('App/TemplateAuthoringLaunchView.swift')
        self.assertIn('session.retainedImagePickerHost.nativeSelectionEnabled', launch)
        self.assertNotIn('nativeSelectionEnabled = true', launch)

    def test_lifecycle_and_story_slot_changes_invalidate_before_callbacks(self):
        model = read('App/TemplateAuthoringView.swift')
        for method in ['func load()', 'func restore()', 'func discard()']:
            self.assertIn(method + ' {\n        retireMediaReviews()', model)
        self.assertIn('.onDisappear { media.retire(); model.leave() }', model)
        story = read('App/TemplateStoryEditor.swift')
        self.assertIn('self.model.mediaReferencesWillChange()', story)
        self.assertLess(story.index('beats = next; originalJSON = draft.storyJson'), story.index('model.changed()', story.index('private func apply')))
        self.assertIn('.onDisappear { media.retire() }', read('App/TemplateAuthoringDetailForms.swift'))
        source = read('App/TemplateMediaReviewController.swift')
        self.assertIn('beat.imgs.count < TemplateAuthoringStory.maximumImagesPerBeat', source)
        self.assertIn('$0.slot.field == row.0 && $0.ordinal == row.1', source)

    def test_generated_selection_is_debug_only_and_no_user_document_is_read(self):
        source = read('App/TemplateMediaReviewController.swift')
        generated = source.split('#if DEBUG')[1]
        self.assertIn('RetainedImageSanitizer.sanitize(data)', generated)
        self.assertIn('Data(repeating: 0, count: 128)', generated)
        self.assertIn('reportedByteCount: 128', generated)
        fixture = read('App/TemplateAuthoringFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('--template-author-media-fixture', fixture)

    def test_all_localized_labels_are_bilingual_and_reuse_exact_crop_fragment(self):
        fragment = json.loads(read('Resources/TemplateMediaReviewLocalizations.fragment.json'))['strings']
        crop = json.loads(read('Resources/TemplateImageCropLocalizations.fragment.json'))['strings']
        for key, value in crop.items(): self.assertEqual(fragment[key], value)
        for key, value in fragment.items():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'}, key)
            self.assertTrue(all(v['stringUnit']['value'] for v in value['localizations'].values()))

    def test_real_authored_regressions_cover_retained_panel_and_raw_reference_safety(self):
        tests = read('Tests/AppUnitTests/TemplateMediaReviewControllerTests.swift')
        self.assertEqual(tests.count('func test'), 13)
        for token in ['testRetainedOldPanelAndDismissalCannotReacquireOrCancelNewField',
                      'testSamePanelReselectRotatesSelectionAndRejectsRetainedCallbacks',
                      'testExplicitClearAndABAReferenceEditInvalidateBeforeOnChange',
                      'testStoryDuplicatesStayDistinctMoveKeepsSlotsAndInvalidatesPending']:
            self.assertIn(token, tests)
        ui = read('Tests/AppUITests/TemplateMediaReviewFlowTests.swift')
        self.assertEqual(ui.count('func test'), 3)
        for token in ['240/420/660', 'adjust(toNormalizedSliderPosition: 0.4)',
                      'XCTAssertEqual(value.requestCount, 0)', 'Array($0.utf8)',
                      'XCTAssertFalse(select.isEnabled)', 'XCTAssertFalse(apply.isEnabled)',
                      'tap("templateMedia.open.optionImage.A", in: app)',
                      'tap("templateMedia.open.optionAudio.B", in: app)',
                      'tap("templateMedia.open.narration", in: app)',
                      'app.navigationBars[title].waitForExistence', 'Array(raw.label.utf8), Array(reference.utf8)',
                      'app.buttons["Multiple choice"]']:
            self.assertIn(token, ui)


if __name__ == '__main__': unittest.main()
