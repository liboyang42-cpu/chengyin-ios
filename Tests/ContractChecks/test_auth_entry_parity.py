"""Offline source guardrails for w2-01 entry/auth parity, not Swift or runtime evidence."""
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FILES = ['UsageConsentGateView', 'PrivacyProtectionView', 'SessionExpiryNoticeModifier', 'DeregistrationParityViews', 'LoginView']


class AuthEntryParitySourceChecks(unittest.TestCase):
    def test_every_auth_entry_key_is_bilingual_in_its_own_table(self):
        catalog = json.loads((ROOT/'Resources/AuthEntry.xcstrings').read_text())['strings']
        for name in FILES:
            source = re.sub(r'\.accessibilityIdentifier\("[^"]*"\)', '', (ROOT/'App'/(name + '.swift')).read_text())
            keys = re.findall(r'"(authEntry\.[A-Za-z0-9.]+)"', source)
            for key in keys:
                self.assertIn(key, catalog, (name, key))
            for match in re.finditer(r'Text\("(authEntry\.[^"]+)"(.{0,30})', source):
                self.assertTrue(match.group(2).startswith(', tableName: "AuthEntry")'), (name, match.group(0)))
        for key, entry in catalog.items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'}, key)

    def test_catalog_matches_its_generator(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)/'AuthEntry.xcstrings'
            subprocess.run([sys.executable, '-B', str(ROOT/'tools/build_auth_entry_catalog.py'), str(target)], check=True)
            self.assertEqual(target.read_text(), (ROOT/'Resources/AuthEntry.xcstrings').read_text())

    def test_root_mounts_gate_and_expiry_notice_without_new_dispatch(self):
        root = (ROOT/'App/QuestifyApp.swift').read_text()
        self.assertIn('.usageConsentLaunchGate(signedIn: session.account != nil', root)
        self.assertIn('.sessionExpiryNotice(session: session, onContinueAsGuest: { browsingAsGuest = true })', root)
        for name in FILES:
            source = (ROOT/'App'/(name + '.swift')).read_text()
            self.assertNotIn('URLRequest', source, name)
            self.assertNotIn('/api/', source, name)

    def test_consent_recording_and_feature_flags_stay_unapproved(self):
        policy = (ROOT/'Core/UsageConsentPolicy.swift').read_text()
        self.assertIn('public static let liveRecordingApproved = false', policy)
        self.assertNotIn('HTTPTransport', policy)
        composition = (ROOT/'App/AppCompositionRoot.swift').read_text()
        self.assertNotIn('LaunchFeatureFlagsReader', composition)

    def test_deregister_never_sends_wechat_code_and_checks_method_before_consent(self):
        coordinator = (ROOT/'Core/AccountComplianceCoordinator.swift').read_text()
        service = (ROOT/'Core/AccountComplianceService.swift').read_text()
        self.assertNotIn('wxcode', coordinator + service)
        precheck = coordinator.split('public func precheckAndAgree', 1)[1].split('public func sendSMS', 1)[0]
        self.assertLess(precheck.index('verificationAvailableOnThisDevice'), precheck.index('self.service.consent('))

    def test_sign_in_channels_require_current_agreement(self):
        login = (ROOT/'App/LoginView.swift').read_text()
        self.assertIn('.disabled(session.isWorking || !consentGranted)', login)
        self.assertIn('session.operationalMarket == .china && consentGranted', login)
        self.assertIn('onOpenPrivacy: { legalDocument = AuthEntryLegalSheet(type: .privacyPolicy) }', login)


if __name__ == '__main__':
    unittest.main()
