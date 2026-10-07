"""Offline source contracts for a review request; not Swift, approval, or release evidence."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ApprovedTopicReviewRequestContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_separate_default_off_routes_and_real_normal_host(self):
        config = self.read('Core/BusinessRuntimeConfiguration.swift')
        for suffix in ['Prepare', 'Submit', 'Status']:
            self.assertIn('case .approvedTopicReview' + suffix + ':', config)
        session = self.read('App/AppSession.swift')
        for item in ['makeApprovedTopicReviewSource(owner:', 'self.compositionViewerRevision == viewerRevision', 'current.permits($0)', 'current.permits(.approvedTopicReviewSubmit)']:
            self.assertIn(item, session)
        core = self.read('Core/ProjectEditCoordinator.swift')
        self.assertIn('releaseReviewSource: (any ApprovedTopicReviewServing)? = nil', core)
        host = self.read('App/ProjectEditView.swift')
        self.assertIn('ApprovedTopicReviewEntrySection(model: model, controller: reviewRequest)', host)
        self.assertIn('reviewRequest.binding(reviewRequestPresentation)', host)
    def test_original_presentation_and_queued_confirmation_are_fenced(self):
        source = self.read('App/ApprovedTopicReviewPresentation.swift')
        for item in ['model.editorIncarnation == original.incarnation', 'model.ownsVisit', 'ProjectEditLocalStore.exactPending(pending, original.pending)', 'presentation?.id == original.id', 'self.close(original)']:
            self.assertIn(item, source)
        model = self.read('App/ApprovedTopicReviewRequestView.swift')
        for item in ['confirmation == nil, !isWorking', 'confirmation?.id == original.id', 'flow.claim(original)', 'flow.submit(claim)', 'model.cancel(captured)', '.onDisappear { original.flow.close() }']:
            self.assertIn(item, model)
        # A separate source-read capture task now precedes confirmation in the type.
        # Keep the original ordering assertion on the exact confirmation method.
        model = model.split('    func confirm(_ original:', 1)[1].split('    func check(_ original:', 1)[0]
        self.assertLess(model.index('flow.claim(original)'), model.index('Task { [weak self, flow]'))
    def test_actual_tasks_owned_and_canceled_before_late_result(self):
        source = self.read('Core/ApprovedTopicReviewFlow.swift')
        for item in ['readTask = task', 'writeTask = task', 'readTask?.cancel(); writeTask?.cancel()', 'requestID == request', 'withTaskCancellationHandler', 'snapshot == original', 'try journal.read(session: session, topicID: origin.topicID) == original']:
            self.assertIn(item, source)
        client = self.read('Core/ApprovedTopicReviewClient.swift')
        self.assertNotIn('onUnauthorized', client)
        self.assertIn('Task.checkCancellation()', client)
    def test_journal_keeps_unknown_and_original_origin_and_exact_bytes(self):
        source = self.read('Core/ApprovedTopicReviewJournal.swift')
        for item in ['expected.current?.receipt != nil', 'expected.records.count < 32', 'originOperationID == origin.operationID', 'observed.raw == data', 'observed.records == records', 'origins.insert(operation).inserted', 'requestIDs.insert(command.requestID).inserted']:
            self.assertIn(item, source)
        self.assertNotIn('clearPending', source); self.assertNotIn('storage.remove', source)
        capture = self.read('Core/ApprovedTopicReviewRequest.swift')
        self.assertIn('identityBytes', capture)
        self.assertIn('approvalProof', capture); self.assertIn('releaseAllocated', capture)
        previous = self.read('App/ApprovedReleaseAuthorPresentation.swift')
        self.assertIn('readScope.reviewSnapshot == opening.reviewSnapshot', previous)
    def test_projection_is_reference_only_and_confirmation_uses_capture(self):
        source = self.read('App/ApprovedTopicReviewSummarySection.swift') + self.read('App/ApprovedTopicReviewRequestView.swift')
        for forbidden in ['AsyncImage', 'URLSession', 'coordinator.draft', 'model.draft', 'questionAnswer', 'merchantGuide']:
            self.assertNotIn(forbidden, source)
        self.assertIn('capture: original.capture', source)
        self.assertIn('Text(verbatim:', source)
        self.assertIn('templateCategoryID', source)
        self.assertIn('templateCategoryIDs', source)
    def test_synthetic_wire_only_and_complete_real_control_journeys(self):
        source = self.read('Core/ApprovedTopicReviewSynthetic.swift')
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertIn('ApprovedTopicReviewClient', source)
        self.assertIn('func send(_ request: URLRequest)', source)
        for name, seconds in [('Request',720),('Unknown',900),('Persistence',720)]:
            ui = self.read('Tests/AppUITests/ApprovedTopicReview'+name+'FlowTests.swift')
            self.assertEqual(ui.count('func test'),1)
            self.assertIn('UNMEASURED complete method estimate: '+str(seconds)+' seconds.',ui)
            self.assertIn('tap("topicReview.confirm.submit"',ui)
            self.assertIn('projectSubmission.auditTaskID',ui)
            self.assertIn('Array(target.label.utf8)',ui)
        for path, count in [('Tests/CoreTests/ApprovedTopicReviewRequestTests.swift',12),('Tests/CoreTests/ApprovedTopicReviewClientTests.swift',7),('Tests/AppUnitTests/ApprovedTopicReviewPresentationTests.swift',7),('Tests/AppUnitTests/ApprovedTopicReviewCompositionTests.swift',16)]:
            self.assertEqual(self.read(path).count('func test'),count,path)
    def test_catalog_additive_bilingual_and_source_keys_registered(self):
        fragment=json.loads(self.read('Resources/ApprovedTopicReviewLocalizations.fragment.json'))
        self.assertEqual(len(fragment['strings']),50)
        for key, value in fragment['strings'].items():
            self.assertTrue(key.startswith('topicReview.'))
            self.assertEqual(set(value['localizations']), {'en','zh-Hans'})
            self.assertTrue(value['localizations']['zh-Hans']['stringUnit']['value'])
if __name__ == '__main__': unittest.main()
