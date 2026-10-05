"""Supplementary native wire/composition guard. This is not Swift or provider runtime proof."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class CNNativeLoginContracts(unittest.TestCase):
    def text(self, name): return (ROOT/name).read_text()
    def test_password_flag_cannot_enable_legacy_bootstrap(self):
        config = self.text('Core/RegionalConfiguration.swift')
        self.assertIn('market == .china ? [.domesticChinaPhone] : []', config)
        root = self.text('App/AppCompositionRoot.swift')
        self.assertIn('[AuthEndpoint.smsSend, .phone, .userInfo, .logout]', root)
        self.assertNotIn('[AuthEndpoint.password,', root)
        self.assertIn('CNAccountSessionService.accepts(request, configuration: api)', root)
        self.assertIn('deployment.regional.canUseDomesticChinaPhone', root)
    def test_byte_boundaries_and_role_readback_are_explicit(self):
        route = self.text('Core/CNAccountSessionService.swift')
        for marker in ['body.count <= 1024', 'canonical.httpBody == body', 'url.query == nil', 'url.fragment == nil', 'request.httpBodyStream == nil', 'keys = ["phone", "code"]']:
            self.assertIn(marker, route)
        for path in ['Core/CNAccountSessionService.swift','Core/AuthChannelService.swift']:
            self.assertIn('["player", "club", "merchant"].contains(', self.text(path))
        self.assertNotIn('configuration.availability(of: .usernamePassword)', route)
    def test_shipping_config_stays_closed_and_recorders_use_two_step_phone(self):
        self.assertIn('.init(deployment: .unconfigured,', self.text('App/RegionalLaunchConfiguration.swift'))
        tests = self.text('Tests/AppUnitTests/AppCompositionRootTests.swift')
        for marker in ['testPasswordVerificationFlagCannotMountLegacyWeChatCodeRoute', 'testProviderUnavailableWrongOTPAndRateLimitNeverCommitOrRetry', 'testMerchantEntryIntentDoesNotGrantMerchantRoleOrWriteAccess', 'testColdRestoreRejectsLegacyRolelessProjectionWithoutDestroyingCredential', 'authChannels.loginWithPhone']:
            self.assertIn(marker, tests)
        self.assertNotIn('if path == "login"', tests)

    def test_parent_close_invalidates_phone_before_ui_dismissal(self):
        session = self.text('App/AppSession.swift')
        cancel = session.split('    func cancelPendingLogin() {', 1)[1].split('    func logout()', 1)[0]
        self.assertIn('authChannels.cancel()', cancel)
        self.assertLess(cancel.index('authChannels.cancel()'), cancel.index('gate.cancelLogin()'))

    def test_dormant_ui_checks_do_not_require_removed_password_fields(self):
        for path in ['Tests/AppUITests/EntryFlowTests.swift', 'Tests/AppUITests/WeChatAppAuthFlowTests.swift']:
            source = self.text(path)
            self.assertNotIn('XCTAssertTrue(app.buttons["auth.signIn"].exists)', source)
            self.assertIn('XCTAssertFalse(app.secureTextFields.firstMatch.exists)', source)
        entry = self.text('Tests/AppUITests/EntryFlowTests.swift')
        self.assertIn('phone.typeText("10000000000")', entry)
        self.assertIn('code.typeText("123456")', entry)
        self.assertIn('XCTAssertFalse(app.buttons["auth.channels.phoneSignIn"].isEnabled)', entry)

    def test_login_copy_matches_exact_otp_and_account_creation_contract(self):
        catalog = json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
        english = lambda key: catalog[key]['localizations']['en']['stringUnit']['value']
        self.assertEqual(english('auth.channels.invalidCode'), 'Enter the six-digit verification code.')
        self.assertIn('may create a player account', english('auth.registrationPending'))
        self.assertIn('auth.channels.phoneTitle', self.text('App/LoginView.swift'))

    def test_normal_root_has_interrupt_restore_and_storage_recorder_cases(self):
        source = self.text('Tests/AppUnitTests/AppCompositionRootTests.swift')
        for name in ['testCancelPendingPhoneExchangeCannotStartReadbackAndReentryWorks',
                     'testCloseDuringReadbackFencesLateSuccessAndUnauthorized',
                     'testMismatchedRolelessOrUnknownCurrentAccountNeverPersists',
                     'testColdRestoreUnauthorizedTombstonesWhileTransientFailuresPreserveCredential',
                     'testVaultWriteFailureDoesNotPublishLoginOrClearRestoreTombstone',
                     'testLogoutClearFailureCannotRestoreTheOldCredential',
                     'testLateLogoutFailureCannotClearNewAuthenticatedSession']:
            self.assertIn('func ' + name + '(', source)
        self.assertIn('XCTAssertEqual(vault.writeAttempts, 0)', source)
        self.assertIn('recorder.finishPausedAuth()', source)
