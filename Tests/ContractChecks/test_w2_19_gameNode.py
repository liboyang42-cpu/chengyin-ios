"""Source checks for the pages/merchant/game-node parity slice (w2-19, page key gameNode)."""
from pathlib import Path
import json, re, unittest
ROOT = Path(__file__).resolve().parents[2]
CORE = sorted((ROOT / 'Core').glob('MerchantGameNode*.swift'))
APP = sorted((ROOT / 'App').glob('MerchantGameNode*.swift'))
SERVICE = ROOT / 'Core/MerchantGameNodeService.swift'
PROJECTION = ROOT / 'Core/MerchantGameNodeProjection.swift'
COMMANDS = ROOT / 'Core/MerchantGameNodeCommands.swift'
COORDINATOR = ROOT / 'Core/MerchantGameNodeCoordinator.swift'
FIXTURE = ROOT / 'App/MerchantGameNodeFixtureHost.swift'
GATES = ROOT / 'Core/MerchantCityNPCParityGates.swift'
CATALOG = ROOT / 'Resources/MerchantGameNode.xcstrings'


class GameNodeContract(unittest.TestCase):
    def test_exact_endpoints_and_methods(self):
        s = SERVICE.read_text()
        for path in ('"api/game/session/view"', '"api/game/session/merchant/entries"', '"api/game/session/command"',
                     '"api/game/session/receipt"', '"api/merchant/chapter-node/live-checkin-code"'):
            self.assertIn(path, s)
        self.assertIn('"perspective": "MERCHANT"', s)
        self.assertIn('application/x-www-form-urlencoded', s)  # live-checkin-code binds a plain Long nodeId
        self.assertIn('"requestId": requestID', s)
        self.assertNotIn('URLSession', s)

    def test_core_is_foundation_only(self):
        self.assertEqual(len(CORE), 4)
        for path in CORE:
            text = path.read_text()
            self.assertNotRegex(text, r'import (SwiftUI|UIKit|AVFoundation|CoreLocation)', path.name)
            self.assertNotIn('try!', text, path.name)
            self.assertNotRegex(text, r'\.url!|\]!|\)!\s', path.name)

    def test_rejection_codes_and_source_rules(self):
        p = PROJECTION.read_text()
        for code in ('EMPTY', 'FORBIDDEN_PROJECTION', 'INVALID_MERCHANT_VIEW', 'INVALID_SESSION', 'INVALID_FALLBACK_OPTIONS', 'INVALID_STATION'):
            self.assertIn('"%s"' % code, p)
        self.assertIn('playMode == .route || !checklist.isEmpty', p)
        self.assertIn('"NO_PUBLIC_CONTENT"', p)
        self.assertIn('session != "FINISHED" && session != "CANCELLED"', p)
        c = COMMANDS.read_text()
        self.assertIn('["game", shortName(action)', c)
        self.assertIn('.prefix(64)', c)
        self.assertIn('^[A-Za-z0-9_-]{8,64}$', c)
        self.assertIn('^[1-9][0-9]{0,18}$', c)
        self.assertIn('fields["authorityEpoch"]', c)
        self.assertNotIn('"fallbackNodeId"', c)

    def test_writes_gated_and_pending_receipt_not_required_to_carry_action(self):
        g = GATES.read_text()
        self.assertIn('public var stationCommands = false', g)
        self.assertRegex(g, r'reviewedEndpoints: \[RegionalMarket: Set<String>\] \{ \[:\] \}')
        s = SERVICE.read_text()
        self.assertIn('gates.stationCommands', s)
        self.assertIn('execution == .injectedOfflineHarness && transport is any MerchantContentOfflineTransport', s)
        reader = s[s.index('class MerchantGameNodeContentReader'):]
        self.assertIn('public var permitsWrites: Bool { false }', reader)
        self.assertIn('if receipt.outcome == "PENDING" { return .pending }', s)
        coord = COORDINATOR.read_text()
        self.assertIn('guard service.permitsWrites', coord)
        self.assertIn('service.persistPending(entry.index)', coord)
        self.assertIn('await service.submit(command)', coord)
        self.assertIn('guard command == frozen', coord)

    def test_fixture_is_debug_only_and_offline(self):
        text = FIXTURE.read_text()
        self.assertTrue(text.startswith('#if DEBUG'))
        self.assertTrue(text.rstrip().endswith('#endif'))
        self.assertIn('struct MerchantGameNodeFixtureHost: View', text)
        self.assertIn('init(scenario: String)', text)
        self.assertIn('MerchantContentOfflineTransport', text)
        self.assertIn('.injectedOfflineHarness', text)
        self.assertNotIn('URLSession', text)
        for scenario in ('"invited"', '"uncertain"', '"restored"', '"empty"', '"error"', '"denied"', '"readOnly"', '"entries"'):
            self.assertIn(scenario, text)

    def test_catalog_matches_used_keys_and_is_bilingual(self):
        catalog = json.loads(CATALOG.read_text())['strings']
        used = set()
        for path in CORE + APP:
            used |= set(re.findall(r'"(merchantGameNode\.[A-Za-z0-9_.]+)"', path.read_text()))
        self.assertEqual(used, set(catalog))
        for key, row in catalog.items():
            self.assertEqual(set(row['localizations']), {'en', 'zh-Hans'}, key)
        zh = lambda k: catalog[k]['localizations']['zh-Hans']['stringUnit']['value']
        self.assertEqual(zh('merchantGameNode.title'), '本站准备与运行')
        self.assertEqual(zh('merchantGameNode.pause.noFallbackTitle'), '不设备用方案，直接暂停？')
        self.assertEqual(zh('merchantGameNode.unknown.confirm'), '确认操作结果')
        for path in APP:
            self.assertNotIn('tableName: "Localizable"', path.read_text())


if __name__ == '__main__':
    unittest.main()
