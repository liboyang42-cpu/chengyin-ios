"""Offline source assertions only. Authored Swift tests are not executed by this checker."""
from pathlib import Path
import json,unittest
ROOT=Path(__file__).resolve().parents[2]
class ApprovedReleasePublicationContracts(unittest.TestCase):
    def read(self,path):return (ROOT/path).read_text()
    def test_explicit_command_and_receipt_bind_captured_manifest(self):
        s=self.read('Core/ApprovedTopicReleasePublication.swift')
        for token in ['expectedManifestHash = prepared.manifestHash','"expectedManifestHash": .string(expectedManifestHash)','row["manifestHash"]?.text == command.expectedManifestHash','fields == expected.fields','UUID = UUID()']:
            self.assertIn(token,s)
        self.assertNotIn('UserDefaults',s);self.assertNotIn('storage.remove',s)
    def test_journal_validates_before_write_and_requires_exact_readback(self):
        s=self.read('Core/ApprovedTopicReleasePublication.swift')
        for token in ['read(session: session, topicID: expected.topicID) == expected','decode(data, session: session, topicID: expected.topicID).records == records','observed.raw == data','ids.insert(command.requestID).inserted','prior.releaseID == receipt.releaseID','records: expected.records + [record]']:
            self.assertIn(token,s)
        self.assertLess(s.index('decode(data, session: session'),s.index('try storage.write'))
        self.assertEqual(self.read('Tests/CoreTests/ApprovedTopicReleasePublicationJournalTests.swift').count('func test'),11)
    def test_claim_and_tasks_are_original_identity_owned(self):
        s=self.read('Core/ApprovedTopicReleasePublicationClient.swift')
        for token in ['confirmation?.id == original.id','snapshot == original','claimID == original.id','journal.begin(original.prepared','ownedTask = task','ownedTask?.cancel()','withTaskCancellationHandler','requestID == request','currentCapability(path)']:
            self.assertIn(token,s)
        self.assertEqual(self.read('Tests/CoreTests/ApprovedTopicReleasePublicationFlowTests.swift').count('func test'),14)
        view=self.read('App/ApprovedReleasePreparationView.swift')
        self.assertIn('flow.state == .ready(original.prepared)',view);self.assertIn('let claim = publisher.claim(original)',view)
        self.assertIn('model.confirmationBinding(confirmation)',view)
        self.assertIn('original.publisher?.close(); original.flow.close()',view)
        confirm=self.read('App/ApprovedReleasePublicationConfirmationView.swift')
        self.assertIn('confirm(original)',confirm);self.assertIn('.onDisappear { cancel(original) }',confirm)
        self.assertNotIn('model.draft',confirm)
    def test_ordinary_factories_fence_viewer_revision_and_refresh_exact_capabilities(self):
        s=self.read('App/AppSession.swift')
        start=s.index('private var approvedReleaseRuntimeFactory:');end=s.index('private func projectEditorService',start);part=s[start:end]
        self.assertIn('composition.sessionDependencies(context)',part);self.assertGreaterEqual(part.count('compositionViewerRevision == viewerRevision'),3)
        self.assertIn('currentCapability:',part)
        self.assertIn('let current = self.approvedReleaseRuntimeFactory',part)
        self.assertEqual(self.read('Tests/AppUnitTests/ApprovedReleaseCompositionTests.swift').count('func test'),9)
    def test_outer_boundary_is_independent_default_off_and_clone_preserved(self):
        s=self.read('App/AppCompositionRoot.swift')
        self.assertIn('var approvedReleaseConfiguration: @MainActor (RuntimeDependencyContext) -> BusinessRuntimeConfiguration? = { _ in nil }',s)
        self.assertIn('transport.approvedReleaseConfiguration = { self.approvedReleaseConfiguration($0) }',s)
        self.assertIn('configuration.routes[route.feature]?.contains(exact) == true',s)
        route=self.read('App/ApprovedReleaseCompositionRoute.swift')
        for token in ['bytes.count <= 4096','request.httpBodyStream == nil','url.absoluteString == baseURL.appendingPathComponent','expectedManifestHash','UUID(uuidString: id)?.uuidString == id']:
            self.assertIn(token,route)
        for adjacent in ['api/topic/v2/create','api/approved-topic-release/v1/start','api/approved-topic-release/v1/resume']:
            self.assertNotIn(adjacent,route)
    def test_actual_shared_view_model_and_real_button_coverage_is_present(self):
        self.assertEqual(self.read('Tests/AppUnitTests/ApprovedReleasePublicationPresentationTests.swift').count('func test'),6)
        ui=self.read('Tests/AppUITests/ApprovedReleasePublicationFlowTests.swift')+self.read('Tests/AppUITests/ApprovedReleaseRecoveryFlowTests.swift')+self.read('Tests/AppUITests/ApprovedReleaseReceiptRecoveryFlowTests.swift')
        for token in ['tap("approvedRelease.confirm.create"','tap("approvedRelease.confirm.cancel"','tap("approvedRelease.publication.check"','releasePublishCount, 1','releaseAllocatedCount, 1','assertFixtureEnvironment','Array(target.label.utf8)','approvedRelease.fixture.restoreStorage']:
            self.assertIn(token,ui)
        self.assertEqual(ui.count('func test'),3);self.assertIn('estimate: 900 seconds.',ui);self.assertIn('estimate: 1200 seconds.',ui)
        synthetic=self.read('Core/ApprovedTopicReleasePublicationSynthetic.swift');self.assertTrue(synthetic.startswith('#if DEBUG'))
        self.assertIn('ApprovedTopicReleasePublicationClient',synthetic);self.assertNotIn('URLSession',synthetic)
    def test_added_copy_is_bilingual_and_does_not_claim_player_activation(self):
        fragment=json.loads(self.read('Resources/ApprovedReleasePublicationLocalizations.fragment.json'))
        self.assertEqual(len(fragment['strings']),15)
        for key,row in fragment['strings'].items():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
        english=fragment['strings']['approvedRelease.publishScope']['localizations']['en']['stringUnit']['value']
        self.assertIn('does not by itself prove public listing',english)
    def test_review_prepare_publish_status_factories_capture_configuration_generation(self):
        source=self.read('App/AppSession.swift')
        part=source.split('private var approvedReleaseRuntimeFactory:')[1].split('private var projectRuntimeFactory:')[0]
        self.assertEqual(part.count('configurationRevision = projectConfigurationRevision'),3)
        self.assertEqual(part.count('self.projectConfigurationRevision == configurationRevision'),5)
        self.assertIn('guard !projectConfigurationChanging',part)
        self.assertIn('approvedTopicReview*/approvedTopicRelease*',source)
        self.assertIn('compositionTransport.approvedReleaseConfigurationRevision =',source)
    def test_outer_generation_survives_clones_and_preserves_queued_journals(self):
        source=self.read('App/AppCompositionRoot.swift')
        self.assertIn('approvedReleaseConfigurationRevision: @MainActor () -> UInt64? = { nil }',source)
        self.assertIn('transport.approvedReleaseConfigurationRevision = { self.approvedReleaseConfigurationRevision() }',source)
        self.assertIn('approvedReleaseConfigurationRevision() == configurationRevision',source)
        tests=self.read('Tests/AppUnitTests/ApprovedReleaseCompositionTests.swift')+self.read('Tests/AppUnitTests/ApprovedTopicReviewCompositionTests.swift')
        for token in ['testOldPrepareAndPublicationFactoriesCannotBorrowNewGenerationSession','testRetiredReviewFactoryCannotBorrowNewSessionWhenSameCapabilitiesReturn','testOuterCloneRejectsBothReviewAndReleaseLateResponsesAcrossGenerationABA','XCTAssertEqual(storage.data,before)']:
            self.assertIn(token,tests)
if __name__=='__main__':unittest.main()
