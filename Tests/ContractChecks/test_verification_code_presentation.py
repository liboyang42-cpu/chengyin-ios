"""Offline structural checks. Swift/Apple execution and live acceptance remain separate."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
class VerificationCodeContracts(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_each_normal_factory_has_an_independent_default_nil_grant(self):
        app=self.read('App/AppSession.swift'); deps=self.read('App/NativeRuntimeDependencies.swift')
        for key,kind in [('verificationCodeApproval','VerificationCodeApproval'),('couponCodeApproval','CouponCodeApproval'),('ownerRefundApproval','ClubOwnerRefundApproval')]:
            self.assertIn(f'{key}: {kind}? = nil',deps)
            self.assertIn('runtimeDependencies.'+key,app)
        for factory in ['VerificationCodeHTTPService','CouponCodeApprovedService','ClubOwnerRefundConfiguredAccess']:
            self.assertIn(factory,app)
        self.assertNotIn('ClubOwnerRefundService(offlineConfiguration:',app)
    def test_receipt_binds_server_payload_and_never_invents_a_code(self):
        code=self.read('Core/VerificationCodePresentation.swift')
        for marker in ['parts.count == 6','parts[0] == "v1"','Int(parts[1]) == target.id','Int64(parts[3]) == expiresAtMilliseconds','poiID == target.id','citynode_\\(accountID)','expiry > now','private let code: String']:
            self.assertIn(marker,code)
        for forbidden in ['UserDefaults','JSONEncoder','FileManager','print(', 'qrcodeUrl']:
            self.assertNotIn(forbidden,code)
        self.assertIn('filter.message = Data(code.utf8)',self.read('App/VerificationCodeView.swift'))
    def test_no_redemption_or_fabricated_status_endpoint(self):
        code=self.read('Core/VerificationCodePresentation.swift')
        paths=set(re.findall(r'"(api/[^" ]+)"',code))
        self.assertEqual(paths,{'api/verify/dyncode/issue','api/verify/citynode/issue','api/registration/info'})
        self.assertIn('OrderLifecycleService(configuration:',code)
        self.assertNotIn('verificationStatus == 1',code)
        self.assertIn('detail.registrationStatus == 2',code)
    def test_city_expiry_reissues_ticket_expiry_is_manual_and_failures_do_not_loop(self):
        code=self.read('Core/VerificationCodePresentation.swift')
        self.assertIn('if target.kind == .cityVoucher { await issue() }',code)
        self.assertIn('if now() >= expiry {\n            eraseCode(); phase = .expired',code)
        self.assertIn('guard let expiry else { return }',code)
        fail=code.split('private func fail(')[1]
        self.assertNotIn('await issue()',fail)
    def test_view_clears_on_inactive_disappearance_and_uses_cancellable_tick(self):
        ui=self.read('App/VerificationCodeView.swift')
        for marker in ['.task(id: scenePhase)','Task.sleep(for: .seconds(1))','operation?.cancel()','model.pause()','model.invalidate()','.privacySensitive()']:
            self.assertIn(marker,ui)
        for forbidden in ['AsyncImage','UIPasteboard','Photos','UserDefaults','UIScreen.main.brightness']:
            self.assertNotIn(forbidden,ui)
        self.assertIn('verificationCodeFactory',self.read('App/QuestifyApp.swift'))
        self.assertIn('VerificationCodeView',self.read('App/OrderPassPreviewView.swift'))
        self.assertIn('VerificationCodeView',self.read('App/RoamVoucherHangoutViews.swift'))
    def test_coupon_api_scope_and_media_origin_policies_are_separate(self):
        code=self.read('Core/CouponCodeApprovedFactory.swift')
        for marker in ['RuntimeDependencyTransport','session.role == captured.role','session.token == captured.session.token','ObjectCardMediaPolicy(approvedOrigins:','ObjectCardBoundedImageLoader','try check()']:
            self.assertIn(marker,code)
        self.assertNotIn('URLSession',code)
        media=self.read('Core/ObjectCardMedia.swift')
        for marker in ['configuration.ephemeral' if False else 'URLSessionConfiguration.ephemeral','completionHandler(nil)','response.url == url','httpCookieStorage = nil','urlCredentialStorage = nil']:
            self.assertIn(marker,media)
    def test_refund_configured_path_retains_owner_preflight_and_unknown_lock_guards(self):
        access=self.read('Core/ClubOwnerRefundApprovedAccess.swift'); model=self.read('Core/ClubOwnerRefundCoordinator.swift')
        for marker in ['required.isSubset(of: endpoints.paths)','approval.matches(context)','current() == captured','ClubGovernanceService','review.identity == identity','ClubOwnerRefundFailure.unknown','ClubOwnerRefundFailure.unconfirmed']:
            self.assertIn(marker,access)
        for marker in ['entries[key]?.authorization == access.authorizationGeneration','fresh == review.evidence','orderNo.utf16.contains(where: { $0 > 0x20 })','for candidate in keys { try locks.acquire(candidate) }']:
            self.assertIn(marker,model)
        self.assertNotIn('removeItem',model);self.assertNotIn('release(',model)
        self.assertIn('phase != .active',self.read('App/ClubOwnerRefundPanel.swift'))
    def test_fragment_has_bilingual_strings_and_matches_catalog(self):
        strings=json.loads(self.read('Resources/VerificationCodeLocalizations.fragment.json'))['strings']
        catalog=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertGreater(len(strings),20)
        for key,value in strings.items():
            self.assertEqual(value,catalog[key]);self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
        ui=self.read('App/VerificationCodeView.swift')
        for key in re.findall(r'"(verificationCode\.[^"\\]+)"',ui):
            if not key.endswith('.') and key not in ['verificationCode.view','verificationCode.phase','verificationCode.qr','verificationCode.orderState','verificationCode.refresh']:
                self.assertIn(key,strings)
if __name__=='__main__': unittest.main()
