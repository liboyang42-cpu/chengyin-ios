"""Offline source evidence; this is not execution of authored Swift or UI tests."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ProjectSubmissionAcknowledgmentContract(unittest.TestCase):
    def read(self,path):return (ROOT/path).read_text()
    def test_real_v2_transport_retains_whole_acknowledgment(self):
        s=self.read('Core/ProjectEditHTTPService.swift')
        branch=s.split('if path == ProjectEditStoryContract.createPath',1)[1].split('let topicID: Int',1)[0]
        self.assertIn('ProjectEditBundleAcknowledgment.decode',branch)
        self.assertIn('return .bundleAcknowledged(operationID: operation.operationID, acknowledgment: acknowledgment)',branch)
        self.assertIn('return .acknowledged(operationID: operation.operationID, topicID: topicID)',s)
    def test_durable_metadata_is_optional_and_cross_checked(self):
        s=self.read('Core/ProjectEditLocalStore.swift')
        for token in ['bundleAcknowledgment: ProjectEditBundleAcknowledgment? = nil','value.hasConsistentAcknowledgment','completedTopicID == bundleAcknowledgment.topicID','ProjectEditStoryContract.createPath','storedPendingMatches(expected']:
            self.assertIn(token,s)
        c=self.read('Core/ProjectEditCoordinator.swift');self.assertIn('completed.bundleAcknowledgment = bundle',c)
        self.assertIn('try store.savePending(completed',c);self.assertIn('case .unknown: state = .unknown',c)
    def test_submission_evidence_cannot_decode_approval(self):
        s=self.read('Core/ProjectEditStoryContract.swift').split('public struct ProjectEditBundleAcknowledgment',1)[1]
        self.assertIn('self = try Self.decode',s);self.assertIn('["PENDING", "ESCALATED", "DRAFT", "NOT_REQUIRED"]',s)
        self.assertNotIn('"APPROVED"',s)
    def test_normal_editor_and_original_receipt_mount_readonly_facts(self):
        s=self.read('App/ProjectEditView.swift');self.assertIn('ProjectSubmissionEvidenceSection(model: model)',s)
        self.assertIn('guard model.editorIncarnation == submissionIncarnation, next == nil',s)
        self.assertIn('loadedSession == coordinator.session',s);self.assertIn('coordinator.pending?.ownerKey == session.ownerKey',s)
        self.assertIn('guard model.submissionIsCurrent(receipt, incarnation: submissionIncarnation), submission?.id == receipt.id',s)
        h=self.read('App/PublishingContextHandoffViews.swift');self.assertIn('if let acknowledgment = receipt.bundleAcknowledgment',h)
        self.assertIn('ProjectSubmissionEvidenceView(acknowledgment: acknowledgment, currentVerificationConfigured: canVerifyRelease)',h); self.assertIn('var canVerifyRelease = false',h)
        v=self.read('App/ProjectSubmissionEvidenceViews.swift');self.assertIn('projectSubmission.releaseUnavailable',v)
        for forbidden in ['URLSession','AsyncImage','Task {','releaseId =','OperationEndpointApproval(']:self.assertNotIn(forbidden,v)
    def test_fixture_branch_is_debug_only_and_authored_coverage_kept(self):
        s=self.read('Core/ProjectEditSyntheticFixtures.swift');self.assertTrue(s.startswith('#if DEBUG'))
        for path,count in [('Tests/CoreTests/ProjectSubmissionAcknowledgmentTests.swift',12),('Tests/AppUnitTests/ProjectSubmissionEvidenceTests.swift',4),('Tests/AppUITests/ProjectSubmissionAcknowledgmentFlowTests.swift',2)]:
            self.assertEqual(self.read(path).count('func test'),count)
        ui=self.read('Tests/AppUITests/ProjectSubmissionAcknowledgmentFlowTests.swift')
        self.assertEqual(ui.count('UNMEASURED complete method estimate: 720 seconds.'),2)
        self.assertIn('UICTContentSizeCategoryAccessibilityXXXL',ui)
        self.assertIn('Array(target.label.utf8)',ui)
if __name__=='__main__':unittest.main()
