"""Supplementary source guards; actual recorder assertions are Apple-hosted XCTest."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublicTemplateCompositionContracts(unittest.TestCase):
    def test_independent_typed_grant_and_exact_native_read_shapes(self):
        root = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        self.assertIn('case publicTopicTemplateCatalogAndDetail', root)
        self.assertIn('reads: Set<ReadGrant> = []', root)
        self.assertIn('deployment.reads.contains(.publicTopicTemplateCatalogAndDetail)', root)
        matcher = root.split('private enum PublicTopicTemplateReadRoute', 1)[1]
        for path in ['api/template/topic-template/list', 'api/template/topic-template/info']:
            self.assertEqual(matcher.count(path), 1)
        self.assertNotIn('hasPrefix("api/', matcher)
        for marker in ['url.absoluteString', 'request.httpMethod == "POST"', 'request.httpBodyStream == nil',
                       'body == Data("{}".utf8)', 'body.count <= 512', 'String(id) == value',
                       'canonical.httpBody == body']:
            self.assertIn(marker, matcher)
        self.assertIn('captured.isPublicTemplateViewer', root)
        self.assertIn('role == nil && token == nil', root)
        self.assertIn('request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) != captured.token.map({ Data($0.utf8) })', root)
        self.assertIn('current() == captured', root)
        self.assertIn('let viewerRevision: UInt64', root)
        self.assertIn('.init(deployment: .unconfigured)', (ROOT / 'App/RegionalLaunchConfiguration.swift').read_text())

    def test_session_services_and_viewer_projection_stay_on_existing_fenced_path(self):
        session = (ROOT / 'App/AppSession.swift').read_text()
        self.assertIn('discoveryService=DiscoveryService(configuration:configuration,transport:transport)', session)
        self.assertIn('let transport=compositionTransport', session)
        self.assertIn('return try await self.readPublicTopicTemplate(id: id, expiresSession: false)', session)
        self.assertIn('epoch == publicTemplateDetails.epoch', session)
        dto = (ROOT / 'Core/PublicTopicTemplateDetail.swift').read_text()
        self.assertIn('$0.withRecruitment(viewerIsMerchant || viewerIsPublisher)', dto)
        self.assertIn('guard generation == captured, !isInvalidated, !Task.isCancelled', dto)

    def test_catalog_unauthorized_side_effect_follows_viewer_and_loader_fences(self):
        session = (ROOT / 'App/AppSession.swift').read_text()
        self.assertIn('compositionViewerRevision &+= 1', session)
        self.assertIn('viewerRevision: self.compositionViewerRevision', session)
        read = session.split('private func readDiscovery<Value>', 1)[1].split('func discoveryBanners', 1)[0]
        failure = read.split('} catch {', 1)[1]
        self.assertLess(failure.index('viewerRevision == compositionViewerRevision'),
                        failure.index('if expiresSession { expireIfMatching'))
        self.assertIn('!Task.isCancelled', failure)
        request = session.split('func publicTopicTemplateCatalogRequest()', 1)[1].split('func discoveryPlayTemplate', 1)[0]
        self.assertIn('readDiscovery(expiresSession: false)', request)
        self.assertIn('onUnauthorized:', request)
        loader = (ROOT / 'App/DiscoveryComponents.swift').read_text().split('struct DiscoveryErrorView', 1)[0]
        failure = loader.split('catch {', 1)[1]
        self.assertLess(failure.index('current == generation, !Task.isCancelled'),
                        failure.index('onUnauthorized()'))
        browser = (ROOT / 'App/DiscoveryTemplateBrowserView.swift').read_text()
        self.assertIn('reader.publicTopicTemplateCatalogRequest()', browser)
        self.assertIn('topics.load(onUnauthorized: request.onUnauthorized, request.read)', browser)

    def test_apple_hosted_boundary_and_race_inventory_is_wired(self):
        tests = (ROOT / 'Tests/AppUnitTests/PublicTemplateCompositionTests.swift').read_text()
        for name in ['NormalGuestSessionReadsOnlyCatalogAndPublicDetailWithoutAuthenticationGrant',
                     'AuthenticatedContextUsesCurrentTokenAndServerViewerFlagsOnly',
                     'MissingPublicGrantAndHomeGrantCannotDispatchPublicReads',
                     'PublicGrantDoesNotImplyHomePrivateOrStandaloneGameReadsOrWrites',
                     'PrivateHomeReadStillRequiresItsIndependentOwnerGrant',
                     'WrongVerbPathQueryFragmentAndRealmMakeZeroDispatches',
                     'UnexpectedCatalogBodyAndDetailFieldsAreRejected',
                     'StaleCredentialsAndPartialGuestIdentityAreRejectedBeforeDispatch',
                     'GuestCompletionCannotPopulateAuthenticatedContextAndLogoutClearsProjection',
                     'AccountRoleAndTokenABARejectLate401AndSuccess',
                     'CatalogLateUnauthorizedCannotExpireChangedSession',
                     'RoleOnlyRefreshABAFencesCatalogSuccessAndUnauthorized',
                     'CurrentCatalogUnauthorizedStillExpiresNormalSession',
                     'SupersededCatalogLoaderUnauthorizedCannotExpireSessionOrEraseNewSuccess',
                     'CanceledCatalogLoaderCannotExpireSessionAndReentryFinishes',
                     'IndependentCatalogLoadersDoNotSupersedeEachOther',
                     'CatalogRequestCapturedBeforeRoleABARejectsDispatch',
                     'CurrentUnauthorizedExpiresNormalSessionAndSupersededDetailDoesNot',
                     'UnconfiguredNormalSessionMakesZeroPublicReadCalls',
                     'EveryViewerIdentityComponentFencesLateSuccessAndThrownFailure']:
            self.assertIn('func test' + name, tests)
        self.assertNotIn('URLSession', tests.replace('with no URLSession or vault', ''))
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        self.assertIn('Tests/AppUnitTests/PublicTemplateCompositionTests.swift', project)


if __name__ == '__main__':
    unittest.main()
