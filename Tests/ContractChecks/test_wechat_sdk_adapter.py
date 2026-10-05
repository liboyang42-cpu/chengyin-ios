"""Offline source/project contracts only; these do NOT compile or run the vendor SDK."""
from pathlib import Path
import json, re, unittest
ROOT = Path(__file__).resolve().parents[2]

class WeChatSDKSourceChecks(unittest.TestCase):
    def test_default_host_stays_unconfigured(self):
        host = (ROOT/'App/AppSession.swift').read_text()
        self.assertIn('private let weChatSDKConfiguration: WeChatSDKConfiguration? = nil', host)
        self.assertIn('private let weChatSDKGate = WeChatAppAuthGate()', host)
        line = next(x for x in host.splitlines() if 'lazy var weChatAuth =' in x)
        self.assertNotIn('service:', line)
        for path in [ROOT/'Config/Base.xcconfig', ROOT/'Config/Info.plist', ROOT/'Package.swift']:
            self.assertNotIn('QUESTIFY_WECHAT_SDK_APPROVED', path.read_text())
            self.assertNotIn('WechatOpenSDK', path.read_text())
        self.assertFalse(list(ROOT.rglob('*.xcframework')))
        self.assertFalse(list(ROOT.rglob('WXApi.h')))
    def test_verified_selectors_remain_inside_conditional_bridge(self):
        source = (ROOT/'App/QFWeChatSDKBridge.m').read_text()
        self.assertIn('#if defined(QUESTIFY_WECHAT_SDK_APPROVED) && QUESTIFY_WECHAT_SDK_APPROVED == 1 && __has_include(<WechatOpenSDK/WXApi.h>)', source)
        for selector in ['[WXApi registerApp:appID universalLink:universalLink]', '[WXApi isWXAppInstalled]', '[WXApi isWXAppSupportApi]', '[WXApi sendReq:request completion:', '[WXApi handleOpenURL:url delegate:self]', '[WXApi handleOpenUniversalLink:activity delegate:self]']:
            self.assertIn(selector, source)
        self.assertIn('[response isKindOfClass:[SendAuthResp class]]', source)
        self.assertIn('request.nonautomatic = YES', source)
        for banned in ['sendAuthReq:', 'PayReq', 'openWXApp]', 'startLog', 'NSLog', 'errStr', 'onReq:']:
            self.assertNotIn(banned, source)
        self.assertIn('strongSelf.generation isEqual:generation', source)
        self.assertIn('dispatch_get_main_queue()', source)
        self.assertIn('self.authResponse = nil', source)
    def test_clipboard_is_separate_and_refused_by_default(self):
        core=(ROOT/'Core/WeChatSDKAuthAdapter.swift').read_text()
        bridge=(ROOT/'App/QFWeChatSDKBridge.m').read_text()
        self.assertIn('pasteboardReadApproved: Bool = false', core)
        self.assertIn('onNeedGrantReadPasteBoardPermissionWithURL:', bridge)
        self.assertIn('![NSThread isMainThread] || !self.generation || !self.pasteboardReadApproved', bridge)
        self.assertIn('![self.routedURL isEqual:openURL]', bridge)
    def test_all_response_outcomes_require_actual_state_and_epoch(self):
        core=(ROOT/'Core/WeChatSDKAuthAdapter.swift').read_text()
        self.assertLess(core.index('response.state == expected'), core.index('switch response.errorCode'))
        self.assertIn('pending.context == context()', core)
        self.assertIn('gate().permitsAuthorization', core)
        for code in ['case 0:', 'case -2:', 'case -4:', 'case -5:']:
            self.assertIn(code, core)
        self.assertIn('pending = nil; driver?.detach()', core)
        self.assertNotIn('URLSession', core)
        self.assertNotIn('UIApplication', core)
    def test_url_and_universal_link_are_routed_through_exact_policy(self):
        driver=(ROOT/'App/WeChatNativeSDKDriver.swift').read_text()
        core=(ROOT/'Core/WeChatSDKAuthAdapter.swift').read_text()
        app=(ROOT/'App/QuestifyApp.swift').read_text()
        self.assertIn('guard adapter.acceptsURL(url) else { return false }', driver)
        self.assertIn('activity.activityType == NSUserActivityTypeBrowsingWeb', driver)
        self.assertIn('adapter.acceptsUniversalLink(url)', driver)
        self.assertIn('$0.host == host && $0.path == value.percentEncodedPath', core)
        self.assertIn('value.user == nil, value.password == nil, value.fragment == nil', core)
        self.assertIn('.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)', app)
    def test_generator_compiles_only_local_shim_with_arc(self):
        generator=(ROOT/'tools/generate_project.py').read_text()
        project=(ROOT/'Questify.xcodeproj/project.pbxproj').read_text()
        self.assertIn("*ROOT.glob('App/*.m')", generator)
        self.assertIn("if path in headers: continue", generator)
        self.assertIn("'COMPILER_FLAGS': '-fobjc-arc'", generator)
        self.assertIn('SWIFT_OBJC_BRIDGING_HEADER', generator)
        self.assertIn('App/QFWeChatSDKBridge.m', project)
        self.assertIn('App/Questify-Bridging-Header.h', project)
        self.assertIn('Tests/AppUnitTests/WeChatNativeSDKDriverTests.swift', project)
        self.assertNotIn('QUESTIFY_WECHAT_SDK_APPROVED', project)
    def test_vendor_evidence_records_exact_download_and_not_run_gates(self):
        evidence=json.loads((ROOT/'docs/wechat-sdk-adapter/source-evidence.json').read_text())
        self.assertEqual(evidence['sdk_version'], '2.0.5')
        self.assertEqual(evidence['archive_sha256'], '00e7c16d76de05cae3f96fd051b928147a17e2047169a5a6e10631a293f0dd14')
        self.assertEqual(evidence['archive_url'], 'https://dldir1.qq.com/WechatWebDev/opensdk/XCFramework/OpenSDK2.0.5.zip')
        self.assertEqual(evidence['sdk_installed'], False)
        self.assertEqual(evidence['sdk_linked_build'], 'NOT_RUN')
        self.assertEqual(evidence['live_login'], 'NOT_RUN')
        self.assertEqual(evidence['new_legal_terms_accepted'], False)
if __name__ == '__main__': unittest.main()
