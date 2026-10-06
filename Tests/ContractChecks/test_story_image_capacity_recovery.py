"""Capacity receipt-opening structure. Source assertions, not Swift runtime results."""
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class StoryImageCapacityRecoveryContracts(unittest.TestCase):
    def read(self, p): return (ROOT / p).read_text()
    def test_new_insert_limit_stays_strict_while_capture_has_exact_200_receipt_only_branch(self):
        gap = self.read('Core/ProjectStoryMediaGap.swift')
        target = self.read('Core/ProjectStoryImageTarget.swift')
        self.assertIn('blocks.count < 200',gap); self.assertIn('blocks.count < 200',target)
        host = self.read('App/ProjectStoryImagePresentation.swift')
        for token in ['if fresh == nil, blockID == nil, chapter.blocks?.count == 200', 'let saved = try? journal.read', 'if matches.count == 1 { recovery = matches[0] }', 'guard let target = fresh ?? recovery?.target']:
            self.assertIn(token,host)
        self.assertNotIn('chapter.blocks?.count >= 200',host)
    def test_recovery_requires_same_action_exact_postimage_and_durable_unapplied_receipt(self):
        s=self.read('App/ProjectStoryImagePresentation.swift')
        for token in ['!entry.applied', 'entry.target.chapterID == chapterID', 'entry.target.action == action', 'let receipt = entry.receipt', 'receipt.reference.utf16.count <= 500', 'source.permitsReference', 'entry.target.hasAppliedReference']:
            self.assertIn(token,s)
        branch=s.split('if fresh == nil',1)[1].split('guard let target',1)[0]
        self.assertNotIn('journal.unstored',branch)
    def test_open_rechecks_entry_and_retains_live_lease_revision_fences(self):
        s=self.read('App/ProjectStoryImagePresentation.swift')
        for token in ['saved.entries.contains(recovery)', 'recovery.target == original.target', '!recovery.applied', 'original.target.hasAppliedReference', 'editor.isCurrentStarterLease(original.lease)', 'isCurrent(original)', 'editor.storyGapRevision == (expectedGap ?? original.storyGapRevision)', 'recoveryOnly: original.recoveryOnly']:
            self.assertIn(token,s)
    def test_flow_locks_the_exact_entry_and_refuses_picker_upload_or_new_insert(self):
        s=self.read('Core/ProjectStoryImageFlow.swift')
        for token in ['recoveryOnly:ProjectStoryImageJournal.Entry? = nil', 'recoveryEntry=recoveryOnly', 'canPick:Bool{recoveryEntry == nil', 'canUpload(_ original:Review)->Bool{recoveryEntry == nil', 'entry==recoveryEntry', 'activeAttempt=nil', 'snapshot?.entries.contains(recoveryEntry)==true && alreadyApplied']:
            self.assertIn(token,s)
        branch=s.split('if let recoveryEntry {\n                activeAttempt=nil',1)[1].split('if let pending',1)[0]
        self.assertIn('target=entry.target;activeAttempt=entry.attemptID;state = .uploaded;return',branch)
        self.assertNotIn('sameField',branch)
    def test_end_recovery_is_not_disabled_by_a_parent_capacity_modifier(self):
        s=self.read('App/ProjectEditDetailForms.swift')
        footer=s.split('if let pendingGap { pendingGap(nil) }',1)[1].split('if imageOpening == nil',1)[0]
        self.assertIn('Button("projectEdit.addText") { appendBlock(.text) }.disabled(blocks.count >= 200)',footer)
        self.assertIn('}.disabled(blocks.count >= 200).accessibilityIdentifier("projectStoryAudio.add")',footer)
        self.assertIn('}.disabled(imageOpening == nil).accessibilityIdentifier("projectStoryImage.add")',footer)
        self.assertNotIn('}.buttonStyle(.bordered).disabled(blocks.count >= 200)',footer)
    def test_real_model_capacity_and_negative_controls_are_debug_only(self):
        s=self.read('Tests/AppUnitTests/ProjectStoryImageCapacityRecoveryTests.swift')
        self.assertIn('#if DEBUG\n@MainActor final class',s);self.assertTrue(s.rstrip().endswith('#endif'))
        self.assertEqual(len(re.findall(r'func test\w+\(',s)),7)
        for token in ['for position in [0, 99, 199]', 'for count in [200, 201]', 'cold.canRestore', 'failAppliedMarkerOnce = true', 'XCTAssertFalse(current.flow.canPick)', 'testCapacityReceiptDoesNotAuthorizeWrongAnchorMovedDuplicateOrReplacedPostimage', 'testCapturedRecoveryCannotReviveAfterLiveReplaceRevertOrDiscard', 'testRecoveryOpeningAndLoadRemainPinnedToExactUnappliedJournalEntry', 'testAmbiguousReceiptsForeignOwnerBucketAndUnavailableHostCannotRecover', 'testNormalReplacementAt200RemainsAvailableButNewInsertionStaysBlocked']:
            self.assertIn(token,s)
    def test_no_journal_format_grant_or_upload_transport_is_added(self):
        flow=self.read('Core/ProjectStoryImageFlow.swift')
        branch=flow.split('if let recoveryEntry {\n                activeAttempt=nil',1)[1].split('if let pending',1)[0]
        for token in ['source.upload','journal.begin','target.applying','URLSession']:self.assertNotIn(token,branch)
        self.assertIn('ProjectStoryImageUploadApproval? = { _ in nil }',self.read('App/AppCompositionRoot.swift'))
        self.assertIn('Envelope(version: 1',self.read('Core/ProjectStoryImageJournal.swift'))
if __name__=='__main__':unittest.main()
