"""Source-only integration checks. Actual native execution still requires Apple CI."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class FrozenCoverContracts(unittest.TestCase):
    def text(self, path): return (ROOT / path).read_text()
    def test_new_profile_is_explicit_and_does_not_promote_author_locator(self):
        s = self.text('Core/ApprovedTopicSelectedCover.swift')
        for token in ['REPLACE_LEGACY_IMAGE_IN_W02_RELEASE', 'PLAYER_PINNED_RUN_ONLY', 'Set(row.keys) == expectedKeys', 'AUTHOR_ONLY', 'row["approvalProof"] == .bool(false)', 'identityBytes: Data']:
            self.assertIn(token, s)
        self.assertIn('binding == .frozenReleaseReplacement', s)
    def test_publication_journal_preserves_cover_and_checks_account(self):
        s = self.text('Core/ApprovedTopicReleasePublication.swift')
        self.assertIn('fields["selectedCover"] = selectedCover.persistedFields', s)
        self.assertIn('prepared.selectedCover?.ownerMemberID == session.accountID', s)
        self.assertIn('prepared.selectedCover?.ownerMemberID == session.accountID', self.text('Core/ApprovedTopicReleasePreparationClient.swift'))
        self.assertIn('image == nil || image == ""', self.text('Core/ApprovedTopicReleaseDomain.swift'))
    def test_both_real_summary_hosts_render_the_original_immutable_value(self):
        self.assertIn('cover: cover, prefix: prefix, approved: false', self.text('App/ApprovedTopicReviewSummarySection.swift'))
        self.assertIn('cover: cover, prefix: identifierPrefix, approved: true', self.text('App/ApprovedReleaseSummarySection.swift'))
        s = self.text('App/ApprovedTopicSelectedCoverSection.swift')
        for token in ['selectedCover.blocked', 'selectedCover.reviewBinding', 'selectedCover.approvedBinding', 'selectedCover.notLoaded']:
            self.assertIn(token, s)
        for token in ['URLSession', 'AsyncImage', 'Link(']:
            self.assertNotIn(token, s)
        self.assertIn('imageController.close(originalImage)', s)
        self.assertNotIn('imageController.retire()', s)
        self.assertIn('source.permits(.readAsset, session: session)', s)
    def test_synthetic_release_binding_is_explicit_default_off(self):
        s = self.text('Core/ApprovedTopicReviewSynthetic.swift')
        self.assertTrue(s.startswith('#if DEBUG')); self.assertIn('selectedCoverReleaseBound: Bool = false', s)
        self.assertIn('--project-frozen-cover-binding', self.text('App/ProjectEditFixtureSupport.swift'))
        self.assertNotIn('selectedCoverReleaseBound', self.text('App/AppSession.swift'))
        fragment = json.loads(self.text('Resources/ApprovedTopicFrozenCoverLocalizations.fragment.json'))
        self.assertEqual(len(fragment['strings']), 2)
        for value in fragment['strings'].values(): self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
    def test_independent_full_ui_journeys_keep_receipt_and_exact_field_assertions(self):
        for name in ['Review', 'Publication']:
            s = self.text(f'Tests/AppUITests/ApprovedTopicFrozenCover{name}FlowTests.swift')
            self.assertIn(': XCTestCase', s); self.assertEqual(s.count('    func test'), 1)
            for token in ['900 seconds', 'selectedCover.asset', 'selectedCover.selection', 'XCTAssertFalse', 'confirm.', 'close']:
                self.assertIn(token, s)
        self.assertIn('reviewSubmitCount, 1', self.text('Tests/AppUITests/ApprovedTopicFrozenCoverReviewFlowTests.swift'))
        self.assertIn('publication.releaseID', self.text('Tests/AppUITests/ApprovedTopicFrozenCoverPublicationFlowTests.swift'))
