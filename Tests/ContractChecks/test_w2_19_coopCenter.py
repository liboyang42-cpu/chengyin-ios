"""Source checks for the native pages/merchant/coop-center parity (w2-19 page coopCenter)."""
import json, pathlib, re, subprocess, sys, unittest

R = pathlib.Path(__file__).resolve().parents[2]
CORE = (R / 'Core/MerchantCoopCenterPlaza.swift').read_text()
SERVICE = (R / 'Core/MerchantContentService.swift').read_text()
VIEW = (R / 'App/MerchantCoopCenterView.swift').read_text()
BINDING = (R / 'App/MerchantCoopCenterSessionBinding.swift').read_text()
FIXTURE = (R / 'App/MerchantCoopCenterFixtureHost.swift').read_text()
GATES = (R / 'Core/MerchantCityNPCParityGates.swift').read_text()
TABLE = json.loads((R / 'Resources/MerchantCoopCenter.xcstrings').read_text())['strings']


def zh(key):
    return TABLE['merchantCoopCenter.' + key]['localizations']['zh-Hans']['stringUnit']['value']


class CoopCenterContract(unittest.TestCase):
    def test_exact_endpoints(self):
        method = SERVICE[SERVICE.index('public func loadRecruitingHome()'):SERVICE.index('private func document(')]
        self.assertIn('access(session, query: .recruiting)', method)
        self.assertIn('read("api/merchant/marketing-home", session: session)', method)
        self.assertIn('read("api/merchant/access/me", session: session)', SERVICE)
        self.assertIn('guard permissions.contains("merchant:marketing:read")', SERVICE)
        self.assertIn('reader.events(city: nil)', VIEW)
        self.assertIn('MerchantOfficialRecruitment.visible(', VIEW)

    def test_core_is_pure_projection(self):
        self.assertTrue(CORE.startswith('import Foundation\n'))
        for forbidden in ['SwiftUI', 'URLRequest', 'URLSession', 'HTTPTransport', 'api/']:
            self.assertNotIn(forbidden, CORE)
        self.assertIsNone(re.search(r'[\w)\]]!(?!=)', CORE), 'no force unwraps on server data')

    def test_normalize_matches_source_contract(self):
        for key in ['"count"', '"couponCount"', '"received"', '"verified"', '"topicCount"', '"freeExploreCount"', '"activityCount"']:
            self.assertIn(key, CORE)
        self.assertIn('recruiting["hasMoreOpen"] == .bool(true)', CORE)
        self.assertIn('static let chinaOffset: Int64 = 8 * 3600', CORE)
        self.assertIn('Self.falsy(primary) ? item["merchantSignUpEndDate"] : primary', CORE)
        self.assertIn('instant > now ? .open', CORE)
        self.assertIn('tight: remaining == 1', CORE)

    def test_read_only_page(self):
        for text in (VIEW, BINDING):
            for forbidden in ['perform(', 'prepare(', 'POST', 'api/coop/handle', 'MerchantContentCommand']:
                self.assertNotIn(forbidden, text)
        self.assertNotIn('cooperationCenter', GATES)  # no write switch is needed or added
        self.assertIn('public static var reviewedEndpoints: [RegionalMarket: Set<String>] { [:] }', GATES)

    def test_loads_parallel_guarded_no_refetch_on_tab(self):
        self.assertIn('func loadAll() { loadRoutes(); loadEvents() }', VIEW)
        self.assertIn('guard !routesInFlight else { return }', VIEW)
        self.assertIn('guard !eventsInFlight else { return }', VIEW)
        self.assertIn('func start() { guard !started else { return }; started = true; loadAll() }', VIEW)
        self.assertNotIn('onChange(of: tab)', VIEW)
        self.assertIn('guard service.scope == scope else', VIEW)
        self.assertIn('guard reader.scope == scope else', VIEW)

    def test_navigation_targets(self):
        self.assertIn('MerchantContentDocumentView(service: content, query: .chapters(topicID: topicID))', VIEW)
        self.assertIn('OfficialEventDetailView(id: event.id, reader: model.official, actions: officialActions)', VIEW)
        self.assertIn('CooperationBrowserView(reader: session.cooperationReader, onClose: close, peerReader: session.cooperationFlowReader)', BINDING)
        self.assertIn('MerchantOfficialRecruitmentReader<AppSession>', BINDING)
        self.assertIn('official.setActive(phase == .active)', BINDING)

    def test_source_copy(self):
        expected = {
            'title': '合作中心', 'tab.official': '官方活动', 'tab.plaza': '广场', 'inbox': '协作邀请：收到的与我发出的',
            'mode.city': '城市定向', 'mode.free': '自由探索', 'seat.full': '已满', 'seat.remaining': '余 %@ 席',
            'terms.perkAmount': '权益核销 · 权益不低于 ¥%@', 'terms.revshareAmount': '分润计酬 · 人头费上限 ¥%@/人次',
            'terms.traffic': '引流合作 · 无结算', 'terms.trafficShort': '引流合作', 'deadline.open': '招商截止 %@',
            'deadline.closed': '已截止', 'detail': '看详情', 'plaza.scope': '共 %1$lld 个开放商机 · 当前列出前 %2$lld 个',
            'plaza.refreshing': '正在刷新开放承接路线…', 'plaza.empty': '还没有开放的路线', 'plaza.error.title': '路线没有加载出来',
            'official.refreshing': '正在刷新官方活动…', 'official.empty': '还没有官方活动', 'official.error.title': '官方活动没有加载出来',
            'official.cityAll': '全城', 'official.gap': '信息不全', 'official.gapFallback': '关键承接方缺失，待补位',
            'official.open': '查看活动', 'refresh': '刷新合作机会', 'retry': '重新加载', 'meta.stations': '%@ 站',
        }
        for key, value in expected.items():
            self.assertEqual(zh(key), value, key)

    def test_catalog_builder_keys_match(self):
        out = subprocess.run([sys.executable, str(R / 'tools/build_merchant_coop_center_catalog.py')], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertNotIn('Text("merchantCoopCenter.', VIEW)

    def test_fixture_debug_only_and_synthetic(self):
        self.assertTrue(FIXTURE.startswith('#if DEBUG\n'))
        self.assertTrue(FIXTURE.rstrip().endswith('#endif'))
        self.assertIn('struct MerchantCoopCenterFixtureHost: View', FIXTURE)
        self.assertIn('init(scenario: String)', FIXTURE)
        self.assertIn('MerchantContentOfflineTransport', FIXTURE)
        self.assertNotIn('ProcessInfo', FIXTURE)
        for scenario in ['normal', 'official', 'focus', 'empty', 'error', 'denied', 'signedOut']:
            self.assertIn(scenario, FIXTURE)
        self.assertNotRegex(FIXTURE, r'\b1[3-9]\d{9}\b')
        self.assertNotIn('Fixture', VIEW)


if __name__ == '__main__':
    unittest.main()
