"""Source gates for the dormant W04/W05/W06/W07/W17 client contracts. Not Swift execution."""
import json
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE = ['SceneAIScope', 'NPCNarrativePolicy', 'MerchantAIAuthoring', 'EnvironmentBranchSelection', 'CommerceOrderReadback',
        'MerchantStaffScope', 'RewardLedgerReadback', 'SponsoredRewardPool', 'MerchantAICommerceGates']
def core(name): return (ROOT / 'Core' / (name + '.swift')).read_text()

class MerchantAICommerceContractChecks(unittest.TestCase):
    def test_no_transport_route_or_credential_in_contracts(self):
        for name in CORE:
            source = core(name)
            for forbidden in ['URLSession', 'URLRequest', 'HTTPTransport', 'httpMethod', 'api/', 'http://', 'https://', 'token', 'Authorization', 'Keychain']:
                self.assertNotIn(forbidden, source, (name, forbidden))
        self.assertIn('public static let reviewedEndpoints: [String] = []', core('MerchantAICommerceGates'))

    def test_every_gate_defaults_off_and_payment_is_constant(self):
        gates = core('MerchantAICommerceGates')
        self.assertIn('public var paymentAndCashEnabled: Bool { false }', gates)
        for line in re.findall(r'public var \w+ = (\S+)', gates):
            self.assertIn(line, ['SceneAIAvailability.disabled', 'false', 'SponsoredRewardCapabilities.disabled'])
        self.assertEqual(re.findall(r'public var (\w+) = true', core('SponsoredRewardPool') + core('SceneAIScope')), [])
        self.assertIn('public var globalGenerationEnabled = false', core('SceneAIScope'))
        self.assertIn('public let allowsStreamingDisplay = false', core('SceneAIScope'))
        self.assertIn('public static let paymentEnabled = false', core('CommerceOrderReadback'))

    def test_scenario_biztypes_are_backend_registered_routes_only(self):
        # Captured from hengyin AiSceneRouter ROUTES (read-only). An unregistered bizType falls back to mock text.
        registered = {'merchant_plan', 'theme_draft', 'node_generate', 'chapter_overview', 'safety_precheck', 'merchant_task_suggest',
                      'merchant_insight', 'template_fill', 'club_design', 'npc_chat', 'merchant_npc_chat', 'npc_event'}
        used = set(re.findall(r'"([a-z_]+)"', core('SceneAIScope').split('registeredBizTypes')[1].split('availableInApp')[0]))
        self.assertTrue(used and used <= registered, used - registered)
        self.assertNotIn('npc_event', used)

    def test_reward_eligibility_has_no_ai_package_input(self):
        source = core('SponsoredRewardPool')
        signature = re.search(r'func merchantMayOffer\(([^)]*)\)', source).group(1)
        self.assertNotRegex(signature.lower(), r'ai|package|npc|subscription')
        self.assertIn("allocation == .guaranteed && guaranteeReserved ? .guaranteedReserved : .limitedWhileSuppliesLast", source)
        self.assertNotIn('case cash', core('RewardLedgerReadback'))

    def test_client_never_decides_payment_or_business_effects(self):
        orders = core('CommerceOrderReadback')
        self.assertIn('case queryOrder(orderID: String)', orders)
        self.assertNotIn('.paid', orders.split('enum CommerceClientPaymentRules')[1])
        npc = core('NPCNarrativePolicy')
        for effect in ['GRANT_REWARD', 'DEDUCT_STOCK', 'CHANGE_PRICE', 'CONFIRM_ARRIVAL', 'COMPLETE_TASK', 'PAYMENT', 'REFUND', 'ADJUST_POINTS']:
            self.assertIn('"' + effect + '"', npc)
        self.assertIn('if NPCForbiddenEffect(rawValue: rawAction) != nil { return .dropped(.forbiddenEffect) }', npc)

    def test_fixture_is_debug_only_and_catalog_is_complete(self):
        host = (ROOT / 'App/MerchantAICommerceFixtureHost.swift').read_text()
        self.assertTrue(host.startswith('#if DEBUG') and host.rstrip().endswith('#endif'))
        self.assertIn('MerchantAICommerceGates.disabled', host)
        app = (ROOT / 'App/QuestifyApp.swift').read_text()
        hook = app.index('"--merchant-ai-commerce-fixture"')
        self.assertLess(app.rfind('#if DEBUG', 0, hook), hook)
        self.assertGreater(app.find('#endif', hook), hook)
        catalog = json.loads((ROOT / 'Resources/MerchantAICommerce.xcstrings').read_text())
        used = set(re.findall(r'Text\("(merchantAICommerce\.[A-Za-z0-9.]+)", tableName: "MerchantAICommerce"\)', host))
        self.assertEqual(used, set(catalog['strings']))
        for entry in catalog['strings'].values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})

if __name__ == '__main__':
    unittest.main()
