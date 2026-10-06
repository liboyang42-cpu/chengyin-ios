"""Structural contracts only: these checks do not compile or execute Swift/XCTest."""
import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class StoryMediaGapContracts(unittest.TestCase):
    def read(self, p): return (ROOT / p).read_text()
    def test_gap_is_owner_draft_chapter_anchor_bound_not_numeric_offset(self):
        s = self.read('Core/ProjectStoryMediaGap.swift')
        for token in ['beforeBlockID: String?', 'ownerKey', 'draftBucket', 'originalDraftHash', 'orderedBlockIDs', 'Set(blocks.map(\\.id)).count == blocks.count', 'blocks.count < 200', 'draft.chapters.filter({ $0.id == chapterID }).count == 1', 'blocks.insert(block, at: index)']:
            self.assertIn(token, s)
        self.assertIn('if let beforeBlockID', s)
        self.assertIn('else { throw ProjectStoryMediaGapFailure.changedContext }', s)
        self.assertNotIn('firstIndex(where: { $0.id == beforeBlockID }) ??', s)
    def test_legacy_image_actions_stay_distinct_and_insert_receipt_checks_exact_postimage(self):
        s = self.read('Core/ProjectStoryImageTarget.swift')
        for token in ['case append, replace(String), insertBefore(String)', 'case .insertBefore(let anchorID)', 'gap.inserting(image', 'inserted + 1 < blocks.count', 'blocks[inserted + 1].id == anchorID', 'original.chapters[ci].blocks?.remove(at: inserted)', 'matches(original, identity: identity, session: session)']:
            self.assertIn(token, s)
        self.assertIn('case .append:', s); self.assertIn('case .replace(let blockID):', s)
    def test_monotonic_exact_content_revision_covers_replace_revert_aba(self):
        s = self.read('App/ProjectEditView.swift')
        self.assertIn('exactData(oldValue.chapters)', s); self.assertIn('oldStory != newStory { storyGapRevision += 1 }', s)
        image = self.read('App/ProjectStoryImagePresentation.swift')
        self.assertIn('editor.storyGapRevision == (expectedGap ?? original.storyGapRevision)', image)
        self.assertIn('appliedTopology = (original.opening.target.id, editor.storyTopologyRevision, editor.storyGapRevision)', image)
        audio = self.read('App/ProjectStoryAudioPresentation.swift')
        self.assertIn('editor.storyGapRevision == original.gapRevision', audio)
        self.assertIn('appliedGapRevision = (original.opening.block.target.id, editor.storyGapRevision)', audio)
    def test_audio_blank_is_saved_before_any_picker_and_uses_existing_lease(self):
        s = self.read('App/ProjectStoryAudioPresentation.swift')
        body = s.split('@discardableResult func insertEmpty(chapterID: String, captured original: Insertion)',1)[1].split('func captureBlock',1)[0]
        for token in ['host.allows', 'editor.isCurrentStarterLease', 'editor.storyTopologyRevision == original.topology', 'original.gap.inserting(block', 'editor.persistLocalChange(next, lease: original.lease)']:
            self.assertIn(token, body)
        for forbidden in ['upload(', 'picker', 'append(']: self.assertNotIn(forbidden, body)
    def test_per_block_ui_passes_exact_ids_and_end_remains_explicit(self):
        s = self.read('App/ProjectEditDetailForms.swift')
        for token in ['if usesRealMediaChapter { mediaGap(before: block.id) }', 'insertingBefore: blockID', 'captureInsertion(chapterID: chapterID, before: blockID)', 'captureInsertion(chapterID: chapterID, before: nil)', 'projectStoryMedia.gap.', 'projectStoryImage.insertBefore.', 'projectStoryAudio.insertBefore.']:
            self.assertIn(token, s)
        self.assertIn('storyImages.presentation == nil, storyAudios.presentation == nil', s)
    def test_host_capability_is_unchanged_and_approvals_are_still_off(self):
        s = self.read('App/ProjectStoryMediaChapterScope.swift')
        self.assertIn('case .unavailable: return false', s); self.assertIn('controller.model === editor', s)
        root = self.read('App/AppCompositionRoot.swift')
        self.assertIn('ProjectStoryImageUploadApproval? = { _ in nil }', root)
        self.assertIn('ProjectStoryAudioUploadApproval? = { _ in nil }', root)
    def test_new_model_tests_guard_synthetic_only_and_cover_recovery_plus_live_aba(self):
        s = self.read('Tests/AppUnitTests/ProjectStoryMediaGapPresentationTests.swift')
        self.assertIn('#if DEBUG\n@MainActor final class', s); self.assertTrue(s.rstrip().endswith('#endif'))
        self.assertEqual(len(re.findall(r'func test\w+\(',s)), 14)
        for token in ['testActualImageFirstMiddleEnd', 'testActualAudioFirstMiddleEnd', 'testDurableImageReceiptColdRecovery', 'testLiveImageReceiptCannotApplyAfterAnchorReplaceRevertButFreshExactRecoveryCan', 'testHeldAudioCallback', 'testTypedPendingHost', 'testOwnerAndEditorIncarnation']:
            self.assertIn(token, s)
    def test_core_legacy_journal_and_exact_gap_tests_are_release_independent(self):
        s = self.read('Tests/CoreTests/ProjectStoryMediaGapTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(',s)), 7)
        self.assertIn('testLegacyVersionOneAppendAndReplaceJournalsDecodeUnchanged', s)
        self.assertIn('testNewInsertJournalRoundTripKeepsExactAnchorAndReceipt', s)
        self.assertNotIn('#if DEBUG', s)
    def test_six_complete_ui_methods_have_full_budgets_and_real_save_restore_probes(self):
        for media in ['Image', 'Audio']:
            for gap in ['First', 'Middle', 'End']:
                s = self.read('Tests/AppUITests/ProjectStory'+media+gap+'GapFlowTests.swift')
                self.assertEqual(len(re.findall(r'func test\w+\(',s)), 1)
                self.assertIn('UNMEASURED complete-method estimate: 900 seconds',s)
                self.assertIn(media.lower()+'Journey(.'+gap.lower()+')',s)
        helper = self.read('Tests/AppUITests/ProjectStoryMediaGapFlowSupport.swift')
        for token in ['projectEdit.fixture.reopen','projectEdit.restore','submissionCount, 0','projectStoryImage.prepared.0.','projectStoryAudio.prepared.0.','projectStoryMedia.gap.']:
            self.assertIn(token,helper)
    def test_bilingual_gap_control_and_no_new_transport_or_permission(self):
        key = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']['projectStoryMedia.insertBefore']['localizations']
        self.assertEqual(key['en']['stringUnit']['value'], 'Insert before this block')
        self.assertEqual(key['zh-Hans']['stringUnit']['value'], '在此内容前插入')
        for path in ['Core/ProjectStoryMediaGap.swift','App/ProjectStoryAudioPresentation.swift','App/ProjectStoryImagePresentation.swift']:
            for forbidden in ['URLSession', 'requestAuthorization', 'AVCapture', 'AVAudioRecorder']:
                self.assertNotIn(forbidden,self.read(path))
if __name__ == '__main__': unittest.main()
