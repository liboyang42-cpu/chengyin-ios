"""Source gates for w2-19 cityNode / cityNodeCreate (mini pages/merchant/citynode + create). Not Swift execution."""
import json
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
APP = ['App/MerchantCityNodeHubView.swift', 'App/MerchantCityNodeCreateView.swift', 'App/MerchantCityNodeFixtureHost.swift', 'App/MerchantCityNodeSessionBinding.swift']

class CityNodeContractChecks(unittest.TestCase):
    def test_core_projection_has_no_transport_or_credentials(self):
        source = read('Core/MerchantCityNodeHub.swift')
        for forbidden in ['URLSession', 'URLRequest', 'HTTPTransport', 'httpMethod', 'http://', 'Authorization', 'token', 'import SwiftUI']:
            self.assertNotIn(forbidden, source, forbidden)
        self.assertNotRegex(source, r'\w!\s*[.)\]]')

    def test_endpoints_match_the_mini_program_exactly(self):
        commands = read('Core/MerchantContentCommands.swift')
        for path, fields in [('api/merchant/city-node/claim', '"poiId"'), ('api/merchant/city-node/claim/cancel', '"poiId"'),
                             ('api/merchant/city-node/offline', '"status"'), ('api/merchant/city-node/save', None)]:
            self.assertIn('"%s"' % path, commands)
        service = read('Core/MerchantContentService.swift')
        self.assertIn('read("api/merchant/city-node/poster-code", .form(["poiId": String(poiID)]), session: session)', service)
        self.assertIn('case .city: value = try await read("api/merchant/city-node/list", session: s)', service)
        self.assertIn('"api/merchant/city-node/claimable", .form(["keyword": keyword])', service)
        hub = read('App/MerchantCityNodeHubView.swift')
        self.assertIn('query: .claimable(keyword: "")', hub)
        self.assertNotIn('TextField', hub)
        gate = read('Core/MerchantCityNodeHub.swift')
        self.assertEqual(set(re.findall(r'"(api/merchant/city-node/[a-z/-]+)"', gate)),
                         {'api/merchant/city-node/claim', 'api/merchant/city-node/claim/cancel', 'api/merchant/city-node/offline', 'api/merchant/city-node/save'})

    def test_save_receipt_accepts_bare_integer(self):
        service = read('Core/MerchantContentService.swift')
        self.assertIn('guard MerchantCityPlacementReceipt.applicationID(receipt.data) != nil else { throw MerchantContentFailure.unknown }', service)
        self.assertIn('let id = data["id"].integer ?? data.integer', read('Core/MerchantCityNodeHub.swift'))

    def test_gates_default_off_and_production_binding_is_dormant(self):
        gates = read('Core/MerchantCityNPCParityGates.swift')
        self.assertIn('public var cityNodeWrites = false', gates)
        self.assertIn('public static var reviewedEndpoints: [RegionalMarket: Set<String>] { [:] }', gates)
        binding = read('App/MerchantCityNodeSessionBinding.swift')
        for forbidden in ['injectedOfflineHarness', 'isOfflineFixture: true', 'MerchantContentService(', 'cityNodeWrites = true', 'enabled: true']:
            self.assertNotIn(forbidden, binding)
        for view in APP[:2]:
            source = read(view)
            self.assertIn('MerchantCityNodeWriteGate.enabled(permitsWrites: service.permitsWrites, isOfflineExample: isOfflineFixture', source)
            self.assertNotIn('CLLocationManager', source)
        self.assertIn('if isOfflineExample { return true }', read('Core/MerchantCityNodeHub.swift'))

    def test_fixture_is_debug_only_synthetic_and_offline(self):
        fixture = read('App/MerchantCityNodeFixtureHost.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertTrue(fixture.rstrip().endswith('#endif'))
        self.assertIn('struct MerchantCityNodeHubFixtureHost: View', fixture)
        self.assertIn('struct MerchantCityNodeCreateFixtureHost: View', fixture)
        self.assertEqual(len(re.findall(r'init\(scenario: String\)', fixture)), 4)
        self.assertIn('MerchantContentOfflineTransport', fixture)
        for forbidden in ['URLSession', 'PublishingMapKitAdapter', 'CLLocation', 'AVCapture']:
            self.assertNotIn(forbidden, fixture)
        self.assertNotRegex(fixture, r'1[3-9]\d{9}')

    def test_catalog_keys_match_sources_and_have_both_languages(self):
        table = json.loads(read('Resources/MerchantCityNode.xcstrings'))['strings']
        used = set()
        for source in APP:
            used |= set(re.findall(r'"(merchantCityNode\.[A-Za-z0-9_.]+)"', read(source)))
        self.assertEqual(used, set(table))
        for key, entry in table.items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'}, key)
        zh = {k: v['localizations']['zh-Hans']['stringUnit']['value'] for k, v in table.items()}
        for key, text in {'merchantCityNode.title': '成为节点', 'merchantCityNode.create.title': '报名成为节点', 'merchantCityNode.place.action': '投放据点',
                          'merchantCityNode.audit.reviewing': '审核中', 'merchantCityNode.audit.rejected': '已驳回', 'merchantCityNode.poster.title': '到店打卡码',
                          'merchantCityNode.create.readbackTitle': '申请状态暂未同步', 'merchantCityNode.create.leaveTitle': '放弃未提交草稿吗'}.items():
            self.assertEqual(zh[key], text)
        for source in APP[:3]:
            self.assertNotRegex(read(source), r'Text\("[一-鿿]')

if __name__ == '__main__':
    unittest.main()
