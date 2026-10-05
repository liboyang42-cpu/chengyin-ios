"""Supplementary wiring checks; not Swift compilation or runtime evidence."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class SocialReaderProductionContracts(unittest.TestCase):
    def test_normal_factories_are_mounted_with_nil_default_approval(self):
        app = (ROOT / 'App/AppSession.swift').read_text()
        deps = (ROOT / 'App/NativeRuntimeDependencies.swift').read_text()
        self.assertIn('lazy var objectCardReader = makeObjectCardReader()', app)
        self.assertIn('lazy var socialMessageMediaReader = makeSocialMessageMediaReader()', app)
        self.assertNotIn('ObjectCardSessionReader(service: nil', app)
        self.assertNotIn('SocialMessageMediaReader(service: nil', app)
        self.assertIn('socialReaderApproval: SocialReaderProductionApproval? = nil', deps)
        self.assertEqual(app.count('approval: self.runtimeDependencies.socialReaderApproval'), 2)
        self.assertIn('serviceProvider:', app)

    def test_source_read_routes_and_separate_anonymous_media_transport(self):
        code = (ROOT / 'Core/SocialReaderProduction.swift').read_text()
        for text in ['api/object-card/list', 'api/im/messages', 'market == .china',
                     'endpoints.namespace == context.session.namespace', 'endpoints.accountID == context.session.accountID',
                     'configuration.baseURL == captured.baseURL', 'approval.objectCards', 'approval.messageImages',
                     'ObjectCardMediaPolicy.origin($0) == $0', 'ResponseLimitedHTTPTransport(enabled: true',
                     'maximumResponseBytes: SocialMessageMediaService.maximumBytes', 'current() == captured',
                     'request.value(forHTTPHeaderField: "Authorization") == nil', 'request.httpMethod == "GET"']:
            self.assertIn(text, code)
        for path in ['api/im/message-info', 'api/object-card/detail', 'api/im/send', 'api/object-card/rename']:
            self.assertNotIn(path, code)

    def test_readback_is_bounded_exact_and_runs_before_and_after_media(self):
        code = (ROOT / 'Core/SocialReaderProduction.swift').read_text()
        service = (ROOT / 'Core/SocialMessageMedia.swift').read_text()
        self.assertIn('static let maximumPages = 20', code)
        self.assertIn('seen.insert(next).inserted', code)
        self.assertIn('(try? SocialMessageMedia(message: row)) == media', code)
        self.assertEqual(service.count('try await authorize?(media)'), 2)
        first = service.index('try await authorize?(media)')
        send = service.index('try await transport.send(request)')
        last = service.rindex('try await authorize?(media)')
        self.assertLess(first, send)
        self.assertGreater(last, send)

    def test_final_reader_results_and_401s_recheck_full_context_on_main_actor(self):
        for path in ['Core/ObjectCardReading.swift', 'Core/SocialMessageMedia.swift']:
            code = (ROOT / path).read_text()
            reader = code.split('@MainActor public final class ', 1)[1]
            self.assertIn('currentContext: @escaping () -> RuntimeDependencyContext?', reader)
            self.assertIn('guard !requiresContext || context != nil', reader)
            self.assertIn('guard currentContext() == context,', reader)
            self.assertIn('guard !Task.isCancelled, currentContext() == context,', reader)
            self.assertLess(reader.rindex('currentContext() == context'), reader.rindex('onUnauthorized('))
        app = (ROOT / 'App/AppSession.swift').read_text()
        for method, following in [('func makeObjectCardReader()', 'private var currentCouponCodeSession'),
                                  ('func makeSocialMessageMediaReader()', '// Square workspace')]:
            body = app.split(method, 1)[1].split(following, 1)[0]
            self.assertIn('currentContext: { [weak self] in self?.currentRuntimeDependencyContext }', body)
        objects = (ROOT / 'Core/ObjectCardReading.swift').read_text()
        self.assertIn('context != contextSnapshot', objects)
        tests = (ROOT / 'Tests/CoreTests/SocialReaderFinalContextTests.swift').read_text()
        for name in ['testObjectSuccessAfterApprovedTransportAndNonisolatedDecodeCannotCrossFullContext',
                     'testObject401AfterApprovedTransportDoesNotExpireUnchangedAccountEpoch',
                     'testDecodedImageAfterFinalSuccessfulReadbackCannotCrossFullContext',
                     'testMedia401DecodedAfterApprovedReadbackTransportCannotExpireUnchangedIdentity',
                     'testDynamicReadersRequireContextAndRecoverWhenItAppears']:
            self.assertIn(name, tests)

    def test_factory_and_lifecycle_tests_are_authored(self):
        tests = (ROOT / 'Tests/CoreTests/SocialReaderProductionTests.swift').read_text()
        for name in ['testWrongMessageConversationTypeOrURLNeverFetchesMedia',
                     'testNoConversationAccessOrClosedHangoutNeverFetchesMedia',
                     'testCancelledReadbackNeverRequestsImage',
                     'testPermissionRevocationOrChangedMessageAfterFetchDiscardsBytes',
                     'testMediaSessionRoleAndTokenChangesDiscardBytesAndStaleFailure',
                     'testObjectReaderResolvesCurrentGrantAfterSignedOutConstruction',
                     'testWrongAccountMarketNamespaceAndAPIOriginHaveNoAccess']:
            self.assertIn(name, tests)
        self.assertTrue((ROOT / 'Tests/AppUnitTests/SocialReaderFactoryAppTests.swift').is_file())

if __name__ == '__main__':
    unittest.main()
