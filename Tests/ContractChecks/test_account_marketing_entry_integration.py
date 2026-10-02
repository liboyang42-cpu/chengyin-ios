"""Offline host contracts, not Swift execution or backend acceptance."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class AccountMarketingEntryIntegrationChecks(unittest.TestCase):
    def read(self, path): return (ROOT/path).read_text()
    def test_empty_policy_and_concrete_dormant_platform_hook(self):
        s=self.read('App/AppSession.swift'); root=self.read('App/QuestifyApp.swift')
        self.assertIn('NativeEntryLinkPolicy(verifiedHTTPSOrigins: [])',s)
        receiver=s[s.index('func receiveNativeURL('):s.index('func receiveWeChatUserActivity(')]
        self.assertIn('if weChatSDKDriver.handle(url, adapter: weChatSDKAdapter) { return }',receiver)
        self.assertIn('guard let intent = nativeEntryLinkPolicy.parse(url) else {\n            receiveNativeIntent(.routeError(.unsupported)); return\n        }',receiver)
        self.assertLess(receiver.index('weChatSDKDriver.handle'),receiver.index('nativeEntryLinkPolicy.parse'))
        self.assertIn('receiveNativeIntent(intent)',receiver)
        for forbidden in ['openURL(', 'transport.send', 'token']:
            self.assertNotIn(forbidden,receiver)
        self.assertIn('.onOpenURL { session.receiveNativeURL($0) }',root)
        for forbidden in ['CFBundleURLTypes','AssociatedDomains','applinks:']: self.assertNotIn(forbidden,root)
    def test_existing_session_and_explicit_disabled_gates(self):
        s=self.read('App/AppSession.swift')
        for text in ['readsEnabled: false, writesEnabled: false','legalApproved: { _, _ in false }','authoritativeMerchantID: { nil }','gates: .init(reads: false, insight: false, settlement: false), locks: nil','scanEnabled: false, bindingEnabled: false','retainedCompliance?.invalidate(); retainedMarketing?.sessionChanged()','didSet { synchronizeAccountMarketingEntry() }']:
            self.assertIn(text,s)
        self.assertIn('self.complianceSession == captured',s)
        self.assertIn('self.token == captured.token',s)
    def test_referral_storage_is_scoped_and_not_deleted(self):
        s=self.read('App/AppSession.swift')
        self.assertIn('safetyDirectory("DoorReferralSafety/" + namespace)',s)
        self.assertIn('try? retainedDoorQueue?.capture(inviter)',s)
        self.assertNotIn('retainedDoorQueue?.replay()',s)
        self.assertNotIn('removeItem',s[s.index('// Default-off source adapters'):s.index('private var token: String?')])
    def test_guest_invitation_retained_and_auth_not_duplicated(self):
        s=self.read('App/NativeEntryLandingView.swift')
        self.assertIn('MerchantOperatorInvitationLandingView',s)
        self.assertIn('LoginView(intent: .merchant)',s)
        self.assertIn('session.merchantBusinessJournal',s)
        self.assertIn('session.merchantExportRecovery',s)
        self.assertNotIn('AuthService(',s)
        self.assertIn('oldAccount != nil, oldAccount != account?.id',self.read('App/AppSession.swift'))
    def test_typed_suggestion_allowlist(self):
        s=self.read('App/NativeEntryLandingView.swift')
        for case in ['case .topicCooperation:', 'case .decoration:', 'case .content:']: self.assertIn(case,s)
        self.assertNotIn('openURL',s)
        self.assertIn('isSourceVisible: true',self.read('App/MerchantHomeView.swift'))
        self.assertIn('iOSCheckoutAvailable: Bool { false }',self.read('Core/MerchantMarketingModels.swift'))
    def test_compliance_legal_stays_missing_and_signup_does_not_grant_creation(self):
        s=self.read('App/AccountComplianceViews.swift')
        self.assertIn('subject: .signup, sourceText: nil',s)
        self.assertIn('onConfirmed: { _ in }',s)
        self.assertIn('creationPolicy: RegistrationUICreationPolicy = .disabled',self.read('App/RegistrationSheetView.swift'))
        self.assertIn('if let complianceCoordinator',self.read('App/SettingsSupportSections.swift'))
    def test_exact_fragment_values_preserved(self):
        catalog=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for name in ['AccountCompliance.xcstrings','MerchantMarketingLocalizations.fragment.json','DoorReferralLocalizations.fragment.json']:
            fragment=json.loads(self.read('Resources/'+name)); entries=fragment.get('strings',fragment)
            for key,value in entries.items(): self.assertEqual(catalog[key],value,key)
    def test_fixture_root_never_constructs_production_session(self):
        s=self.read('App/QuestifyApp.swift')
        for flag in ['--door-referral-fixture','--merchant-marketing-fixture']: self.assertGreaterEqual(s.count(flag),2)
        self.assertIn('session=nil',s)
