"""Official-selector source checks. These do not execute/link the Tencent SDK."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
class WeChatPaymentChecks(unittest.TestCase):
    def read(self,p):return (ROOT/p).read_text()
    def test_official_payment_fields_and_separate_build_gate(self):
        s=self.read('App/QFWeChatPaymentBridge.m')
        for token in ['QUESTIFY_WECHAT_PAYMENT_SDK_APPROVED','!defined(BUILD_WITHOUT_PAY)','PayReq *request','request.partnerId = partnerID','request.prepayId = prepayID','request.nonceStr = nonce','request.timeStamp = timestamp','request.package = package','request.sign = signature','[WXApi sendReq:request completion:','[PayResp class]']:
            self.assertIn(token,s)
        self.assertNotIn('request.state',s);self.assertNotIn('response.state',s);self.assertNotIn('returnKey',s)
    def test_payment_flags_not_enabled_in_configuration(self):
        for p in (ROOT/'Config').glob('*'):
            if p.is_file():self.assertNotIn('QUESTIFY_WECHAT_PAYMENT_SDK_APPROVED=1',p.read_text())
        self.assertIn('weChatPaymentConfiguration: WeChatSDKPaymentConfiguration? = nil',self.read('App/NativeRuntimeDependencies.swift'))
        self.assertIn('selfPlayExternalCheckoutApproved: Bool = false',self.read('Core/BusinessRuntimeConfiguration.swift'))
    def test_context_order_and_callback_safety(self):
        s=self.read('Core/WeChatSDKPaymentAdapter.swift')
        for token in ['pending == nil, registrationID > 0','pending.id == id','context() == pending.context','pendingRegistrationID','configuration?.sdk.acceptsURL(url)','configuration?.sdk.acceptsUniversalLink(url)','finish(.unknown, id: attempt)','code == 0 ? .returned']:
            self.assertIn(token,s)
        self.assertNotIn('case paid',s);self.assertNotIn('UserDefaults',s)
    def test_normal_factory_and_callback_paths_are_wired(self):
        s=self.read('App/AppSession.swift')
        self.assertIn('runtimeDependencies.selfPlayPayment ?? nativeWeChatPaymentAdapter',s)
        self.assertIn('nativeWeChatPaymentDriver.handle(url, adapter: nativeWeChatPaymentAdapter)',s)
        self.assertIn('nativeWeChatPaymentDriver.handle(activity, adapter: nativeWeChatPaymentAdapter)',s)
        self.assertIn('nativeWeChatPaymentAdapter.cancelPending()',s)
        self.assertIn('"QFWeChatPaymentBridge.h"',self.read('App/Questify-Bridging-Header.h'))
    def test_header_evidence_is_pinned_and_not_vendored(self):
        evidence=json.loads(self.read('docs/wechat-payment-adapter/source-evidence.json'))
        self.assertEqual(evidence['sdk_version'],'2.0.5')
        self.assertEqual(evidence['pay_response_has_state'],False)
        self.assertEqual(evidence['vendor_code_copied'],False)
        self.assertEqual(evidence['device_payment'],'NOT_RUN')
if __name__=='__main__':unittest.main()
