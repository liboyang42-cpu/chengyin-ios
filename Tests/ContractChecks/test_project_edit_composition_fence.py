"""Source-level only: does not execute Swift, grant routes, or publish content."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ProjectEditCompositionFenceContracts(unittest.TestCase):
    def read(self,path):return (ROOT/path).read_text()
    def test_exact_routes_use_only_independent_project_features(self):
        route=self.read('App/ProjectEditCompositionRoute.swift')
        for token in ['return .projectRead','return .projectWrite','request.httpBodyStream == nil','url.query == nil','url.fragment == nil','bytes == Data("{}".utf8)','canonical.httpBody == body','Set(fields.keys).isSubset(of: allowed)','ProjectEditStoryContract.validatePayload(fields)']:
            self.assertIn(token,route)
        for forbidden in ['.publishingRead','.publishingWrite','.approvedTopicReleasePublish','api/topic/delete','api/template/my-list']:
            self.assertNotIn(forbidden,route)
    def test_normal_composition_and_clone_read_current_configuration(self):
        source=self.read('App/AppCompositionRoot.swift')
        for token in ['var projectEditConfiguration:', 'transport.projectEditConfiguration = { self.projectEditConfiguration($0) }','ProjectEditCompositionRoute(request: request, baseURL: api.baseURL)','configuration.routes[route.feature]?.contains(exact) == true']:
            self.assertIn(token,source)
        self.assertIn('projectEditConfiguration: @MainActor (RuntimeDependencyContext) -> BusinessRuntimeConfiguration? = { _ in nil }',source)
        session=self.read('App/AppSession.swift')
        self.assertIn('compositionTransport.projectEditConfiguration = { [weak self] context in',session)
        factory=session.split('private func projectEditorService(owner:')[1].split('private var publishingEpochCache:')[0]
        self.assertIn('let factory = projectRuntimeFactory',factory)
        self.assertIn('self.compositionViewerRevision == viewerRevision',factory)
        self.assertIn('self.projectRuntimeFactory?.permits(.projectRead) == true',factory)
    def test_viewer_revision_is_runtime_only_and_existing_locks_are_untouched(self):
        source=self.read('Core/ProjectEditLocalStore.swift')
        session=source.split('public struct ProjectEditDraftIdentity:')[0]
        self.assertIn('viewerRevision: UInt64 = 0',session)
        self.assertIn('public var ownerKey: String { "\\(storageNamespace.utf8.count):\\(storageNamespace):\\(accountID)" }',session)
        envelope=source.split('public struct ProjectEditEnvelope:')[1].split('public enum ProjectEditRestore')[0]
        self.assertNotIn('viewerRevision',envelope)
        self.assertIn('viewerRevision: compositionViewerRevision',self.read('App/AppSession.swift'))
        service=self.read('Core/ProjectEditHTTPService.swift')
        self.assertIn('persisted.dispatchStarted == true { return .unknown }',service)
        self.assertIn('try store.savePending(dispatched, session: session)',service)
    def test_real_normal_factory_tests_cover_both_modes_and_unknown(self):
        source=self.read('Tests/AppUnitTests/ProjectEditCompositionTests.swift')
        self.assertEqual(source.count('func test'),14)
        for token in ['session.projectEditor(product:', 'await editor.confirm(original)', 'ProjectEditOwner.personal,.merchant','ProjectEditProduct.allCases','wire.finish401()', 'current.ownerKey,owner.ownerKey', 'flow.submit(claim)','expected.dispatchStarted = true']:
            self.assertIn(token,source)
        self.assertEqual(self.read('Tests/CoreTests/ProjectEditViewerRevisionTests.swift').count('func test'),3)
    def test_grant_generation_fences_write_only_aba_before_dispatch_marker(self):
        session=self.read('App/AppSession.swift')
        for token in ['func withProjectEditConfigurationChange', 'let alreadyChanging = projectConfigurationChanging', 'projectConfigurationRevision &+= 1', 'projectConfigurationChanging = alreadyChanging', 'self.projectConfigurationRevision == configurationRevision', 'configurationRevision: projectConfigurationRevision']:
            self.assertIn(token,session)
        outer=self.read('App/AppCompositionRoot.swift')
        self.assertIn('projectEditConfigurationRevision() == configurationRevision',outer)
        self.assertIn('transport.projectEditConfigurationRevision = { self.projectEditConfigurationRevision() }',outer)
        for path in ['App/ProjectEditLaunchView.swift','App/SessionPublishingModesView.swift','App/ClubAIDesignView.swift','App/NativeEntryLandingView.swift','App/ProjectOwnedContentViews.swift']:
            self.assertIn('session.projectEditorContextID',self.read(path))
        tests=self.read('Tests/AppUnitTests/ProjectEditCompositionTests.swift')
        for token in ['testHeldNormalPreflightCannotContinueAfterWriteOnlyGrantABA','testQueuedNormalConfirmationCannotCrossGrantABAWithIdenticalRoutes','testCloneRejectsSuccessfulOldResponseAfterGrantGenerationABA','testActualServiceFinalPreflightRejectsWriteOnlyABA_BEFORE_DurableDispatchMarker','XCTAssertEqual(result,.notSent)','XCTAssertNotEqual(durable.dispatchStarted,true)']:
            self.assertIn(token,tests)
if __name__=='__main__':unittest.main()
