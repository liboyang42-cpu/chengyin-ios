"""Source assertions only. These do not compile or execute Swift and make no network calls."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class MerchantEngagementProductionContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_normal_host_injects_typed_default_off_factory(self):
        host = self.read('App/AppSession.swift'); dependencies = self.read('App/NativeRuntimeDependencies.swift')
        self.assertIn('merchantEngagementFactory?.service(for: command, merchantID: merchantID)', host)
        self.assertIn('runtimeDependencies.merchantEngagementApproval', host)
        self.assertIn('merchantEngagementApproval: MerchantEngagementProductionApproval? = nil', dependencies)
        self.assertIn('MerchantEngagementService(configuration:configuration,readTransport:transport)', host)
    def test_production_gate_is_exact_and_never_role_alone(self):
        source = self.read('Core/MerchantEngagementProduction.swift')
        for text in ['market == .china', 'context.market == market', 'endpoints.baseURL == context.baseURL',
                     'endpoints.accountID == context.session.accountID', 'endpoints.namespace == context.session.namespace',
                     '$0.merchantID == merchantID && $0.command == command', 'endpoints.paths.contains(request.path)', 'current() == captured']:
            self.assertIn(text, source)
        self.assertNotIn('role ==', source)
    def test_exact_request_and_one_shot_authority(self):
        source = self.read('Core/MerchantEngagementProduction.swift')
        for text in ['request.url == expected.url', 'request.httpMethod == expected.httpMethod', 'request.httpBody == expected.httpBody',
                     'request.allHTTPHeaderFields == expected.allHTTPHeaderFields', 'request.httpBodyStream == nil', 'forwarded = true', 'try authorization.validate(review)']:
            self.assertIn(text, source)
        coordinator = self.read('Core/MerchantEngagementCoordinator.swift')
        self.assertIn('fileprivate init(_ review:', coordinator)
        self.assertIn('guard !consumed, self.review == review', coordinator)
    def test_fresh_reads_after_journal_and_final_http_barrier(self):
        coordinator = self.read('Core/MerchantEngagementCoordinator.swift').split('public func confirm')[1]
        self.assertLess(coordinator.index('reader.proof'), coordinator.index('journal.reserve'))
        self.assertLess(coordinator.index('journal.reserve'), coordinator.index('MerchantEngagementDispatchAuthorization(frozen'))
        reader = self.read('Core/MerchantEngagementReading.swift').split('try authorization.consume(review); try check()')[-1]
        self.assertLess(reader.index('let fresh = try await proof'), reader.index('selected.executeReviewed'))
        transport = self.read('Core/MerchantEngagementProduction.swift')
        barrier = transport[transport.index('if let beforeForward { await beforeForward() }'):]
        self.assertLess(barrier.index('try authorization.validate(review)'), barrier.index('transport.send(request)'))
    def test_nonfinancial_unknown_retains_durable_namespaced_lock(self):
        s = self.read('Core/MerchantEngagementCoordinator.swift')
        self.assertIn('reader.isSyntheticEnabled || journal.isDurable', s)
        self.assertIn('reader.journalRealm == frozen.journalRealm', s)
        self.assertIn('MerchantMutationFailureDisposition.provesNoDispatch(error)', s)
        production = self.read('Core/MerchantEngagementProduction.swift')
        self.assertIn('if error as? MerchantBusinessFailure == .disabled { throw MerchantBusinessFailure.unknown }', production)
        self.assertNotIn('payment', production.lower())
        self.assertNotIn('refund/execute', production)
    def test_missing_source_invitation_and_campaign_fields_fail_closed(self):
        production = self.read('Core/MerchantEngagementProduction.swift')
        self.assertIn('if case .acceptInvitation = command { throw MerchantBusinessFailure.disabled }', production)
        self.assertIn('task.hasReviewableMessage', production)
        model = self.read('Core/MerchantEngagementModels.swift')
        self.assertIn('count == recipients.count', model)
        self.assertIn('source.mbText("content")', model)
        self.assertNotIn('invite/preview', production)
    def test_download_bounded_ephemeral_no_redirect_and_credentials_only_header(self):
        production = self.read('Core/MerchantEngagementProduction.swift')
        self.assertIn('ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: Self.maximumDownloadBytes)', production)
        service = self.read('Core/MerchantEngagementService.swift')
        self.assertIn('bytes.count <= MerchantEngagementProductionFactory.maximumDownloadBytes', service)
        self.assertIn('forHTTPHeaderField: "X-CRM-Export-Token"', service)
        self.assertNotIn('queryItems', service)
        self.assertIn('refund.rawValue', service)
        self.assertIn('name=\\"refundId\\"', service)
        bounded = self.read('Core/ResponseLimitedHTTPTransport.swift')
        self.assertIn('URLSessionConfiguration.ephemeral', bounded)
        self.assertIn('redirectDenied', bounded)
        self.assertIn('chunk.count > maximumResponseBytes - bytes.count', bounded)
    def test_device_effects_independent_and_fresh_permission(self):
        production = self.read('Core/MerchantEngagementProduction.swift')
        self.assertIn('deviceGrants: [MerchantEngagementDeviceGrant] = []', production)
        for flag in ['customerContactPrivacy', 'customerExportPrivacy', 'aftercareEvidencePrivacy', 'marketingConsent']:
            self.assertIn(flag, production)
        coordinator = self.read('Core/MerchantEngagementCoordinator.swift')
        self.assertIn('public func authorizeExportSave', coordinator)
        self.assertIn('reader.permitsDevice(.contact(contact.customerID, contact.purpose)', coordinator)
        self.assertIn('clearSensitiveReceipt()\n        try await delivery', coordinator)
        self.assertIn('reader.permitsDevice(.selectEvidence(id), merchantID: merchantID)', self.read('App/MerchantEngagementViews.swift'))
    def test_ordinary_http_core_and_ui_tests_are_authored(self):
        source = self.read('Tests/CoreTests/MerchantEngagementProductionTests.swift')
        self.assertIn('class Wire: HTTPTransport', source)
        self.assertGreaterEqual(source.count('    func test'), 20)
        self.assertIn('testFinalHTTPBarrierCancellationPreventsDispatch', source)
        self.assertIn('testAfterReservationPermissionRevocationRetainsUncertainLock', source)
        self.assertIn('testOrdinaryHTTPProductionFactoryReviewUsesExplicitConfirmation', self.read('Tests/AppUITests/MerchantEngagementFlowTests.swift'))
        fixture = self.read('App/MerchantEngagementFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('struct MerchantEngagementOrdinaryFixtureTransport: HTTPTransport', fixture)
    def test_production_review_bilingual_and_not_hardcoded_synthetic(self):
        app = self.read('App/MerchantEngagementComposer.swift')
        self.assertIn('synthetic ? "merchant.engagement.confirmSynthetic" : "merchant.engagement.confirmProduction"', app)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for key in ['merchant.engagement.confirmProduction', 'merchant.engagement.productionReview']:
            self.assertEqual(set(catalog[key]['localizations']), {'en', 'zh-Hans'})
if __name__ == '__main__': unittest.main()
