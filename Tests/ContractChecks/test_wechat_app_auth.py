"""Source checks only, never substitutes for Swift or SDK/runtime execution."""
from pathlib import Path
import json, unittest
ROOT = Path(__file__).resolve().parents[2]
class WeChatAuthSourceChecks(unittest.TestCase):
    def test_source_contract_is_app_only(self):
        source = (ROOT/'Core/WeChatAppAuth.swift').read_text()
        self.assertIn('builder.make(.wechatApp, fields: ["code": code])', source)
        for forbidden in ['/login/code', 'getwxbindphone', 'UserDefaults', 'Keychain', 'print(', 'URLSession', 'UIApplication']:
            self.assertNotIn(forbidden, source)
    def test_all_grants_default_false_and_host_unconfigured(self):
        source = (ROOT/'Core/WeChatAppAuth.swift').read_text()
        for field in ['sdkVerified','providerVerified','legalVerified','appleAlternativeVerified','liveExchangeApproved']:
            self.assertIn(f'var {field} = false', source)
        host = (ROOT/'App/AppSession.swift').read_text()
        self.assertIn('lazy var weChatAuth = WeChatAppAuthCoordinator(adapter: weChatSDKAdapter, gate:', host)
        self.assertIn('private let weChatSDKConfiguration: WeChatSDKConfiguration? = nil', host)
        self.assertIn('private let weChatSDKGate = WeChatAppAuthGate()', host)
        self.assertIn('return try self.commitChannelLogin(result, expected: expected.session)', host)
    def test_callback_claim_precedes_exchange(self):
        source = (ROOT/'Core/WeChatAppAuth.swift').read_text()
        self.assertLess(source.index('phase = .exchanging;'), source.index('exchangeTask = Task'))
        self.assertIn('state == request?.state', source)
        self.assertIn('captured == context()', source)
        self.assertIn('guard request?.attemptID == attemptID else { return }', source)
    def test_localization_and_accessibility(self):
        catalog = json.loads((ROOT/'Resources/WeChatAppAuthLocalizations.fragment.json').read_text())
        self.assertEqual(len(catalog['strings']), 18)
        for entry in catalog['strings'].values():
            for language in ['en','zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'])
        view=(ROOT/'App/WeChatAppAuthSection.swift').read_text()
        self.assertIn('.disabled(!model.coordinator.canStart)', view)
        self.assertIn('.accessibilityIdentifier("auth.wechat.signIn")', view)
        self.assertIn('.onDisappear { model.coordinator.cancel() }', view)
    def test_existing_channels_preserved(self):
        login=(ROOT/'App/LoginView.swift').read_text()
        for key in ['auth.signIn','auth.otherChannels','AuthChannelView(coordinator:session.authChannels']:
            self.assertIn(key, login)
        self.assertIn('if session.operationalMarket == .china', login)
    def test_no_sdk_or_entitlement_activation(self):
        manifest=(ROOT/'Package.swift').read_text()
        self.assertNotIn('Wechat', manifest)
        self.assertNotIn('WeChatSDK', manifest)
if __name__ == '__main__': unittest.main()
