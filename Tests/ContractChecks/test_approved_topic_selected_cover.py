"""Offline source checks; no Swift runtime, image provider or Apple acceptance claim."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
class SelectedCoverContracts(unittest.TestCase):
 def text(self,p):return (ROOT/p).read_text()
 def test_strict_author_only_reference_and_full_binding(self):
  s=self.text('Core/ApprovedTopicSelectedCover.swift')
  for value in ['OWNED_TOPIC_COVER_REVIEW_INPUT_V1','AUTHOR_PREVIEW_ONLY','AUTHOR_ONLY','row["publicPlayerReadable"] == .bool(false)','row["legacyImageBindingVerified"] == .bool(false)','asset["ownerMemberId"]?.integer == owner','Data($0.utf8)','selection > 0','slot > 0','sourceVersion=\\(version)&contentHash=\\(hash)']:
   self.assertIn(value,s)
  for absent in ['URLSession','UIImage','AsyncImage','httpBody']:self.assertNotIn(absent,s)
 def test_actual_client_flow_and_journal_reject_author_only_before_dispatch(self):
  self.assertIn('binding == .frozenReleaseReplacement',self.text('Core/ApprovedTopicSelectedCover.swift'))
  self.assertIn('selectedCover?.permitsReviewRequest ?? true',self.text('Core/ApprovedTopicReviewRequest.swift'))
  for p,token in [('Core/ApprovedTopicReviewClient.swift','record.capture.coverBindingAllowsReview'),('Core/ApprovedTopicReviewFlow.swift','capture.coverBindingAllowsReview'),('Core/ApprovedTopicReviewFlow.swift','original.capture.coverBindingAllowsReview'),('Core/ApprovedTopicReviewJournal.swift','capture.coverBindingAllowsReview && expected.ownerKey')]:self.assertIn(token,self.text(p))
  self.assertIn('capture.selectedCover?.ownerMemberID == session.accountID',self.text('Core/ApprovedTopicReviewClient.swift'))
 def test_ordinary_host_is_localized_without_fetching_arbitrary_references(self):
  s=self.text('App/ApprovedTopicReviewSummarySection.swift');self.assertIn('if let cover = capture.selectedCover',s)
  s=self.text('App/ApprovedTopicSelectedCoverSection.swift')
  self.assertIn('if !cover.permitsReviewRequest',s)
  for token in ['selectedCover.blocked','selectedCover.asset','selectedCover.hash','selectedCover.selection','selectedCover.slot','selectedCover.notLoaded']:self.assertIn(token,s)
  for absent in ['AsyncImage','URLSession','Link(']:self.assertNotIn(absent,s)
  fragment=json.loads(self.text('Resources/ApprovedTopicSelectedCoverLocalizations.fragment.json'));self.assertEqual(len(fragment['strings']),8)
  for entry in fragment['strings'].values():self.assertEqual(set(entry['localizations']),{'en','zh-Hans'})
 def test_only_explicit_debug_fixture_generates_synthetic_selected_cover(self):
  s=self.text('Core/ApprovedTopicReviewSynthetic.swift');self.assertTrue(s.startswith('#if DEBUG'));self.assertIn('selectedCoverEnabled: Bool = false',s)
  self.assertIn('--project-review-selected-cover',self.text('App/ProjectEditFixtureSupport.swift'))
  self.assertNotIn('selectedCoverEnabled',self.text('App/AppSession.swift'))
 def test_real_ui_taps_close_and_readback_keep_zero_review_writes(self):
  for path in ['Tests/AppUITests/ApprovedTopicSelectedCoverFlowTests.swift','Tests/AppUITests/ApprovedTopicSelectedCoverChineseFlowTests.swift']:
   s=self.text(path)
   for token in ['submitAndOpen','topicReview.selectedCover','XCTAssertFalse','reviewSubmitCount,0','reviewTaskCount,0','reviewRequestIDs.isEmpty','900 seconds','topicReview.close']:self.assertIn(token,s)
