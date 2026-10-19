"""Source checks for the store-day merchant page (mini-program pages/play/merchant). Not Swift execution."""
import json
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
PRESENTATION = 'Core/PlayStoreDayPresentation.swift'
SERVICE = 'Core/PlayStoreDayService.swift'
COORDINATOR = 'Core/PlayStoreDayCoordinator.swift'
VIEW = 'App/PlayStoreDayMerchantView.swift'
FIXTURE = 'App/PlayStoreDayMerchantFixtureHost.swift'

class PlayMerchantContractChecks(unittest.TestCase):
    def test_endpoints_are_exactly_the_mini_program_routes(self):
        source = read(SERVICE)
        paths = set(re.findall(r'Path = "([^"]+)"', source))
        self.assertEqual(paths, {'api/play/nodes', 'api/play/checkin', 'api/play/photo', 'api/play/answer',
                                 'api/compliance/consents/latest', 'api/compliance/consents'})
        self.assertNotIn('registrationId', source)  # source merchant page sends session + code only
        self.assertIn('fields.removeValue', read('Core/PlayExperienceService.swift'))
        self.assertIn('request.httpMethod = "GET"', source)
        self.assertIn('forHTTPHeaderField: "Content-Type"', source)
        self.assertIn('status >= 500 || status == 408 { return .unknown }', source)

    def test_projection_and_coordinator_have_no_transport(self):
        for path in [PRESENTATION, COORDINATOR]:
            source = read(path)
            for forbidden in ['URLSession', 'URLRequest', 'HTTPTransport', 'Authorization', 'http://', 'import SwiftUI', 'import UIKit']:
                self.assertNotIn(forbidden, source, (path, forbidden))
        self.assertNotIn('URLSession', read(SERVICE))

    def test_writes_default_off_and_need_reviewed_endpoint_or_offline_harness(self):
        gates = read('Core/MerchantCityNPCParityGates.swift')
        self.assertIn('public var storeDayProofWrites = false', gates)
        self.assertIn('public var storeDayConsentWrites = false', gates)
        self.assertIn('public static var reviewedEndpoints: [RegionalMarket: Set<String>] { [:] }', gates)
        service = read(SERVICE)
        self.assertIn('execution: Execution = .disabled', service)
        self.assertIn('readsEnabled: Bool = false', service)
        self.assertIn('transport is any PlayStoreDayOfflineTransport', service)
        self.assertIn('gates.storeDayProofWrites && [Self.checkinPath, Self.photoPath, Self.answerPath].allSatisfy { gates.allows($0, market: market) }', service)
        self.assertIn('gates.storeDayConsentWrites && gates.allows(Self.consentWritePath, market: market)', service)
        self.assertNotRegex(read(VIEW), r'PlayStoreDayService\(|injectedOfflineHarness')

    def test_unknown_writes_are_read_back_not_resent(self):
        source = read(COORDINATOR)
        self.assertIn('case .unknown: await resolveProofUnknown(autoPopup: autoPopup)', source)
        self.assertIn('case .unknown: await resolveGameUnknown()', source)
        retry = source.split('public func retryProofReadback()')[1].split('\n')[0]
        self.assertNotIn('checkin', retry); self.assertNotIn('photo(', retry)
        self.assertIn('if let prepared = preparedConsent, prepared.event == event { requestID = prepared.requestID }', source)

    def test_consent_contract_reuses_compliance_subject(self):
        self.assertIn('.merchantOnsite(authoritativeMerchantID: merchantID)', read(PRESENTATION))
        self.assertIn('"merchant-\\(event.rawValue.lowercased())-\\(merchantID)-\\(milliseconds)"', read(PRESENTATION))
        self.assertIn('return id.count <= 64 ? id : nil', read(PRESENTATION))

    def test_fixture_is_debug_only_and_synthetic(self):
        source = read(FIXTURE)
        self.assertTrue(source.startswith('#if DEBUG')); self.assertTrue(source.rstrip().endswith('#endif'))
        self.assertIn('init(scenario: String)', source)
        self.assertNotRegex(source, r'"latitude"|"longitude"|1[3-9]\d{9}')
        for scenario in ['empty', 'error', 'permission', 'uncertain', 'stillUnknown', 'consented', 'noTicket', 'disabled', 'noDevice']:
            self.assertIn('"%s"' % scenario, source)

    def test_catalog_matches_used_keys_and_source_copy(self):
        table = json.loads(read('Resources/PlayStoreDay.xcstrings'))['strings']
        used = set()
        for path in [VIEW, FIXTURE]:
            used |= set(re.findall(r'"(playStoreDay\.[A-Za-z0-9.]+)"', read(path)))
        self.assertEqual(used, set(table))
        zh = {k: v['localizations']['zh-Hans']['stringUnit']['value'] for k, v in table.items()}
        for key, text in {'playStoreDay.cta.verify': '出示核销码', 'playStoreDay.modal.title': '仅授权当前门店',
                          'playStoreDay.degraded.still': '还是没核对上，网络恢复后点这里再试 · 期间请勿重复核销',
                          'playStoreDay.crowd.queue': '排队中，建议先去别家', 'playStoreDay.notice.needTicket': '从票夹进入后才能出示核销码'}.items():
            self.assertEqual(zh[key], text)
        self.assertIn('Text(verbatim:', read(VIEW))

if __name__ == '__main__':
    unittest.main()
