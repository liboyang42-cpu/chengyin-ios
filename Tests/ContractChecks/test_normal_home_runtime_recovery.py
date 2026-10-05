"""Recovered normal Home wiring, not Apple execution or real-backend approval."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class NormalHomeRuntimeRecoveryContracts(unittest.TestCase):
    def read(self, p): return (ROOT/p).read_text()
    def test_launch_binds_reviewed_deployment_to_exact_build_and_keeps_default_nil(self):
        source = self.read('App/RegionalLaunchConfiguration.swift')
        for marker in ['makeComposition(reviewed: nil, build: .current)', 'market == deployment.regional.market',
                       'build.baseURL == endpoint', 'bundleIdentifier: build.bundleIdentifier, realm: build.realm',
                       'scope == deployment.storageScope', 'try validate(reviewed, build: build)']:
            self.assertIn(marker, source)
        self.assertNotIn('OperationEndpointApproval(', source)
        self.assertIn('let approved:[RegionalMarket:Set<String>]=[:]', source)
    def test_readiness_checks_actual_services_and_independent_grants(self):
        root = self.read('App/AppCompositionRoot.swift')
        for marker in ['reviewed.storageScope.matches(configuration: reviewed.regional)', 'reviewed.reads.contains(.homeAndSearch)',
                       'reviewed.contentDetails == .activityAndTopic', 'identity.isPublicTemplateViewer', 'identity.isSignedInContentViewer']:
            self.assertIn(marker, root)
        session = self.read('App/AppSession.swift')
        self.assertIn('homeFeedService != nil', session)
        self.assertIn('activityService != nil && topicService != nil && currentTopicSession != nil', session)
    def test_guest_public_reads_remain_allowed_and_partial_identity_is_not_guest(self):
        root = self.read('App/AppCompositionRoot.swift')
        self.assertIn('if accountID == nil { return role == nil && token == nil }', root)
        branch = root.split('guard request.httpMethod == "POST", deployment.reads.contains(.homeAndSearch)',1)[1].split('\n        }',1)[0]
        self.assertIn('captured.isPublicTemplateViewer', branch)
        self.assertNotIn('isSignedInContentViewer', branch)
        self.assertIn('operation(service, session?.token)', self.read('Core/HomeFeedReading.swift'))
    def test_role_revision_invalidates_normal_home_cache_and_route_without_changing_detail_route(self):
        reading = self.read('Core/HomeFeedReading.swift')
        self.assertIn('role: String? = nil, viewerRevision: UInt64 = 0', reading)
        self.assertIn('lhs.viewerRevision == rhs.viewerRevision', reading)
        session = self.read('App/AppSession.swift').split('private var currentHomeFeedSession:',1)[1].split('lazy var homeFeedReader',1)[0]
        self.assertIn('role:account.effectiveRole,viewerRevision:compositionViewerRevision', session)
        view = self.read('App/SessionHomeFeedView.swift')
        self.assertIn('.id(session.homeFeedReader.scope)', view)
        self.assertIn('SessionTopicDetailView(id: id, session: session)', view)
        self.assertIn('.onChange(of:session.homeFeedReader.scope)', view)
    def test_normal_blocked_views_prevent_loading_and_have_bilingual_reasons(self):
        self.assertIn('if reader.isConfigured && unavailableMessageKey == nil { await model.reload', self.read('App/HomeFeedView.swift'))
        self.assertIn('session.contentDetailReadAvailability.messageKey', self.read('App/PlatformConsumerSessionOwner.swift'))
        entries = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key in ['deploymentMissing','buildMismatch','homeReadNotApproved','detailReadNotApproved','signInRequired','sessionUnavailable','serviceUnavailable']:
            self.assertEqual(set(entries['readConfiguration.'+key]['localizations']), {'en','zh-Hans'})
    def test_authored_normal_root_tests_cover_identity_lifecycle_and_honest_empty_failure(self):
        tests = self.read('Tests/AppUnitTests/NormalHomeRuntimeRecoveryTests.swift')
        for marker in ['AppSessionContainer(composition:', 'SessionRootView(session: session)', 'HomeFeedModel()',
                       'testReviewedBuildRejectsWrongMarketEndpointBundleAndRealmBeforeVaultUse',
                       'testHomeAndDetailReadGrantsStayIndependentOfLoginAndMountedService',
                       'testOfflineAndValidEmptyHomeRemainDifferentStates',
                       'testRetiredDetailSuccessAnd401CannotCrossLogoutAndNextOwner',
                       'testCompleteGuestAndSignedInAllowedButPartialHomeViewerNeverDispatches',
                       'testRoleABACancelsLateHomeSuccessAnd401WithoutExpiringOwner',
                       'testNewViewerReloadClearsLoadedRowsBeforeNewResponse']:
            self.assertIn(marker, tests)
        self.assertNotIn('URLSession', tests)
