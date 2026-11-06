"""Offline source guardrails for pkg19 login/sign-out/account-deletion chain (not Swift/runtime evidence)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def src(path):
    return (ROOT / path).read_text()


def block(text, start, length=1400):
    index = text.index(start)
    return text[index:index + length]


class Pkg19LoginDeletionChain(unittest.TestCase):
    def test_settings_reaches_deletion_entry_without_debug_gate(self):
        for path in ['App/SettingsView.swift', 'App/SettingsSupportSections.swift',
                     'App/AccountComplianceViews.swift', 'App/SettingsAccountEntries.swift']:
            self.assertNotIn('#if DEBUG', src(path), path)
        self.assertIn('SettingsSupportSections(market: session.operationalMarket, complianceCoordinator: session.accountComplianceCoordinator)',
                      src('App/SettingsView.swift'))
        self.assertIn('case roam, marketing, cancellation', src('App/AccountComplianceViews.swift'))

    def test_non_cn_fallback_keeps_explicit_unavailable_deletion_row(self):
        sections = src('App/SettingsSupportSections.swift')
        self.assertIn('if let complianceCoordinator {', sections)
        self.assertIn('ForEach(SettingsUnavailableFeature.allCases)', sections)
        self.assertIn('case locationConsent, marketingConsent, accountDeletion', src('Core/SettingsAboutContracts.swift'))

    def test_deletion_service_stays_default_closed_in_session(self):
        session = src('App/AppSession.swift')
        body = block(session, 'var accountComplianceCoordinator: AccountComplianceCoordinator? {')
        self.assertIn('readsEnabled: false, writesEnabled: false, legalApproved: { _, _ in false }', body)
        self.assertIn('DormantComplianceRoamEffects()', body)
        self.assertIn('let authChannelService', body)
        service = src('Core/AccountComplianceService.swift')
        self.assertIn('readsEnabled: Bool = false, writesEnabled: Bool = false', service)

    def test_cn_only_auth_service_and_apple_hard_off(self):
        session = src('App/AppSession.swift')
        self.assertIn('authChannelService=regional.canUseDomesticChinaPhone ? AuthChannelService(', session)
        coordinator = block(session, 'lazy var authChannels=AuthChannelCoordinator(', 700)
        self.assertNotIn('appleConfigurationVerified', coordinator)
        core = src('Core/AuthChannelCoordinator.swift')
        self.assertIn('appleConfigurationVerified: Bool = false', core)
        self.assertIn('guard appleConfigurationVerified else { reject(.appleNotConfigured); return nil }', core)
        self.assertIn('domesticPhoneVisible:session.supportsDomesticPhoneInput', src('App/LoginView.swift'))
        self.assertIn('var supportsDomesticPhoneInput:Bool { operationalMarket == .china }', session)
        for path in ['App', 'Core']:
            for file in (ROOT / path).glob('*.swift'):
                self.assertNotRegex(file.read_text(), r'appleConfigurationVerified:\s*true', file.name)

    def test_auth_feature_flags_default_false(self):
        for path in ['App/AuthAndSessionAdmissionSectionView.swift']:
            text = src(path)
            for flag in ['smsSendEnabled', 'wechatSignInEnabled', 'appleSignInEnabled']:
                self.assertIn('%s: Bool = false,' % flag, text)
        audit = src('Core/AuthAndSessionAdmissionParityAudit.swift')
        for flag in ['smsSendEnabled', 'wechatSignInEnabled', 'appleSignInEnabled']:
            self.assertIn('%s: false,' % flag, audit)

    def test_legal_documents_never_release_approved(self):
        self.assertIn('public var isReleaseApproved: Bool { false }', src('Core/SettingsLegalContracts.swift'))

    def test_logout_and_expiry_clear_local_session_and_invalidate_compliance(self):
        session = src('App/AppSession.swift')
        logout = block(session, 'func logout() async {', 1800)
        for token in ['authChannels.cancel()', 'gate.invalidate()', 'restoreBlockedKey', 'token=nil;account=nil',
                      'try vault.clear()', 'accountSessionService.logout(token:oldToken)']:
            self.assertIn(token, logout)
        expire = block(session, 'private func expireIfMatching(', 1400)
        self.assertIn('try? vault.clear()', expire)
        self.assertIn('retainedCompliance?.invalidate()', session)
        self.assertIn('invalidateSession: { [weak self] captured in', session)
        self.assertIn('guard let self, self.complianceSession == captured else { return }', session)

    def test_apply_requires_confirmation_sms_and_invalidates_only_matching_session(self):
        coordinator = src('Core/AccountComplianceCoordinator.swift')
        self.assertIn('guard explicitlyConfirmed, noticeAccepted, state.smsSent, state.step == .review, let code = reviewCode else { return }',
                      coordinator)
        self.assertIn('await self.invalidateSession(session)', coordinator)
        views = src('App/AccountComplianceViews.swift')
        self.assertIn('explicitlyConfirmed: true', views)
        self.assertIn('.confirmationDialog("compliance.cancelReview"', views)

    def test_sign_out_entry_requires_confirmation(self):
        entry = src('App/SettingsAccountEntries.swift')
        self.assertIn('confirmationDialog("auth.signOutConfirm"', entry)
        self.assertIn('if session.account != nil {', entry)

    def test_no_new_endpoint_literals_in_auth_or_compliance_ui(self):
        for path in ['App/AccountComplianceViews.swift', 'App/AuthChannelView.swift', 'Core/AuthChannelCoordinator.swift',
                     'Core/AccountComplianceCoordinator.swift']:
            self.assertIsNone(re.search(r'https?://', src(path)), path)


if __name__ == '__main__':
    unittest.main()
