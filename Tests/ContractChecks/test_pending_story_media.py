"""Source-level integration fences; authored Swift tests still require Apple execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PendingStoryMediaContract(unittest.TestCase):
    def source(self, path):
        return (ROOT / path).read_text()

    def test_only_actual_pending_controller_mints_owned_destination_scope(self):
        source = self.source('App/ProjectStoryMediaChapterScope.swift')
        for token in ['fileprivate init(controller:', 'private let original: ProjectEditPendingController.Destination',
                      'extension ProjectEditPendingController', 'func captureStoryMediaScope(_ original: Destination)',
                      'guard isCurrent(original), case .story(let chapterID)', 'controller.model === editor',
                      'controller.isCurrent(original)', 'self.chapterID == chapterID']:
            self.assertIn(token, source)
        self.assertNotIn('current: () -> Bool', source)
        self.assertNotIn('templateID', source)

    def test_view_uses_controller_binding_and_arbitrary_override_remains_unavailable(self):
        view = self.source('App/ProjectEditDetailForms.swift')
        self.assertIn('mediaScope.map(ProjectStoryMediaChapterHost.pending) ?? (chapterOverride == nil ? .ordinary : .unavailable)', view)
        self.assertIn('if let actual = mediaScope?.chapter(editor: model, chapterID: chapterID) { return actual }', view)
        self.assertLess(view.index('if let actual = mediaScope?.chapter('), view.index('if let chapterOverride { return chapterOverride }'))
        self.assertIn('host: host', view)
        self.assertIn('usesRealMediaChapter ? storyImages.capture', view)
        self.assertIn('usesRealMediaChapter ? storyAudios.capture', view)
        self.assertIn('if !usesRealMediaChapter { appendBlock(.audio) }', view)
        self.assertIn('storyAudios.insertEmpty(', view)
        host = self.source('App/ProjectEditPendingPresentation.swift')
        self.assertIn('mediaScope: controller.captureStoryMediaScope(original)', host)
        self.assertIn('.id(original.id)', host)

    def test_media_actions_keep_original_targets_and_add_typed_host_currentness(self):
        for kind in ['Image', 'Audio']:
            controller = self.source('App/ProjectStory' + kind + 'Presentation.swift')
            self.assertIn('private let host: ProjectStoryMediaChapterHost', controller)
            self.assertIn('host.allows(editor: editor, chapterID: chapterID)', controller)
            self.assertIn('host.allows(editor: editor, chapterID: original.target.chapterID)', controller)
            self.assertIn('editor.persistLocalChange(', controller)
            self.assertIn('presentation?.id == original.id', controller)
            self.assertIn('editor.storyTopologyRevision', controller)
        self.assertIn('storyTopologyRevision == (expected ?? original.storyTopologyRevision)', self.source('App/ProjectStoryImagePresentation.swift'))
        self.assertIn('editor.storyTopologyRevision == original.topology', self.source('App/ProjectStoryAudioPresentation.swift'))

    def test_authored_real_controller_regressions_and_complete_button_journeys(self):
        source = self.source('Tests/AppUnitTests/ProjectPendingStoryMediaTests.swift')
        for token in ['testNewPendingChapterImageCancelApplyBackAndReopenKeepMaterialUnplaced',
                      'testExistingPendingStoryAudioApplyThenExplicitNodeInsertClosesOldMediaScope',
                      'testArbitraryOverrideWrongModelAndWrongChapterCannotBorrowOwnedScope',
                      'testOldParentCloseBeforeQueuedImageDispatchCannotUploadOrCloseNewDestination',
                      'testHeldAudioAfterParentCloseAndReopenCannotFillNewDestination',
                      'testActualReorderAndDeleteRestoreABARejectReceivedImageInPendingHost',
                      'testPendingImageLocalSaveFailureRetainsMaterialAndRetriesWithoutUpload',
                      'testExplicitRestoreAndAccountChangeRetireScopeWithoutChangingSavedMaterial']:
            self.assertIn(token, source)
        for kind in ['Image', 'Audio']:
            ui = self.source('Tests/AppUITests/ProjectPendingStory' + kind + 'FlowTests.swift')
            self.assertIn('assertFixtureEnvironment', ui)
            self.assertIn('900 seconds', ui)
            self.assertIn('projectEdit.fixture.reopen', ui)
            self.assertIn('projectPending.close', ui)
            self.assertIn('storyImageUploadCount', ui)
            self.assertIn('storyAudioUploadCount', ui)


if __name__ == '__main__':
    unittest.main()
