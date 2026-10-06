"""Offline source checks; no Swift, Apple, approval or release execution proof."""
from pathlib import Path
import json,unittest
ROOT=Path(__file__).resolve().parents[2]
class ReviewObservationContracts(unittest.TestCase):
 def read(self,p):return (ROOT/p).read_text()
 def test_observation_contract_is_exact_and_never_approval_proof(self):
  s=self.read('Core/ApprovedTopicReviewObservation.swift')
  for token in ['record.receipt','questify.topic-release.review-observation.v1','root["approvalProof"] == .bool(false)','root["releaseAllocated"] == .bool(false)','receipt.auditTaskID','version >= receipt.submittedTaskVersion','matches == (hash == receipt.snapshotHash)','case pending = 0, approved = 1, rejected = 2, escalated = 3, cancelled = 4']:
   self.assertIn(token,s)
  self.assertNotIn('URLSession',s)
 def test_actual_client_sends_exact_original_command_under_separate_capability(self):
  s=self.read('Core/ApprovedTopicReviewClient.swift').split('public func observe(')[1].split('public func prepare(')[0]
  for token in ['record.ownerKey == session.ownerKey','record.receipt != nil','record.command.fields','path: ApprovedTopicReviewPath.current']:
   self.assertIn(token,s)
  self.assertIn('case .approvedTopicReviewCurrent: paths = [ApprovedTopicReviewPath.current]',self.read('Core/BusinessRuntimeConfiguration.swift'))
  self.assertIn('current.permits(.approvedTopicReviewCurrent)',self.read('App/AppSession.swift'))
  self.assertIn('case .reviewCurrent: return .approvedTopicReviewCurrent',self.read('App/ApprovedReleaseCompositionRoute.swift'))
 def test_owned_read_checks_original_journal_before_and_after_response(self):
  s=self.read('Core/ApprovedTopicReviewFlow.swift');part=s.split('public func observeCurrent(')[1].split('private func send(')[0]
  self.assertEqual(part.count('try journal.read(session: session, topicID: origin.topicID) == original'),2)
  for token in ['snapshot == original','observationTask = task','withTaskCancellationHandler','requestID == request','isCurrent','observation = .ready(value)']:
   self.assertIn(token,part)
  self.assertIn('observationTask?.cancel()',s)
  self.assertNotIn('journal.record',part);self.assertNotIn('journal.begin',part)
 def test_real_view_method_and_renderer_use_captured_snapshot(self):
  model=self.read('App/ApprovedTopicReviewRequestView.swift')
  self.assertIn('flow.canObserve, flow.snapshot == original',model)
  self.assertIn('flow.observeCurrent(original)',model)
  ui=self.read('App/ApprovedTopicReviewObservationSection.swift')
  self.assertIn('model.observe(original)',ui);self.assertIn('.disabled(!model.flow.canObserve)',ui)
  for forbidden in ['AsyncImage','URLSession','model.draft','coordinator.pending']:
   self.assertNotIn(forbidden,ui)
 def test_debug_transport_and_ordinary_factory_coverage_stay_distinct(self):
  source=self.read('Core/ApprovedTopicReviewSynthetic.swift');self.assertTrue(source.startswith('#if DEBUG'))
  self.assertIn('observationEnabled: Bool = false',source)
  self.assertIn('if observationEnabled { paths.insert(ApprovedTopicReviewPath.current) }',source)
  tests=self.read('Tests/AppUnitTests/ApprovedTopicReviewCompositionTests.swift')
  self.assertIn('testNormalObservationFactoryUsesOnlyOriginalSixFieldsAndIndependentCurrentGrant',tests)
  self.assertIn('testNormalCurrentObservationLate401AfterGrantABACannotExpireSession',tests)
  self.assertEqual(self.read('Tests/CoreTests/ApprovedTopicReviewObservationTests.swift').count('func test'),8)
  self.assertEqual(self.read('Tests/AppUnitTests/ApprovedTopicReviewObservationPresentationTests.swift').count('func test'),3)
 def test_two_complete_real_button_journeys_have_separate_bounded_estimates(self):
  for name in ['ApprovedTopicReviewCurrentFlowTests','ApprovedTopicReviewCurrentChineseFlowTests']:
   ui=self.read('Tests/AppUITests/'+name+'.swift');self.assertEqual(ui.count('func test'),1)
   for token in ['UNMEASURED complete method estimate: 900 seconds.','tap("topicReview.current.read"','projectSubmission.submittedState','reviewObservationCount','Array(target.label.utf8)']:
    self.assertIn(token,ui)
  self.assertIn('dynamicTypeSize:"accessibility5"',self.read('Tests/AppUITests/ApprovedTopicReviewCurrentChineseFlowTests.swift'))
 def test_additive_localization_is_bilingual(self):
  v=json.loads(self.read('Resources/ApprovedTopicReviewObservationLocalizations.fragment.json'))
  self.assertEqual(len(v['strings']),14)
  for key,value in v['strings'].items():self.assertTrue(key.startswith('topicReview.current'));self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
