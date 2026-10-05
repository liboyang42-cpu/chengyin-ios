"""Host wiring assertions complement authored Swift tests; no runtime claims."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class CNSessionRestorationTests(unittest.TestCase):
    def test_bootstrap_uses_session_contract_and_same_vault_scope(self):
        source = (ROOT / 'App/AppSession.swift').read_text()
        bootstrap = source.split('func bootstrap() async {', 1)[1].split('func login(', 1)[0]
        self.assertIn('accountSessionService.storageScope == storageScope', bootstrap)
        self.assertIn('accountSessionService.currentAccount(token:saved)', bootstrap)
        self.assertNotIn('guard let service', bootstrap)
        self.assertNotIn('canUsePassword', bootstrap)
        self.assertNotIn('usernamePassword', bootstrap)
        self.assertLess(bootstrap.index('bool(forKey:restoreBlockedKey)'), bootstrap.index('vault.read()'))
        self.assertLess(bootstrap.index('guard !Task.isCancelled, gate.isCurrent(operation)'), bootstrap.index('commitAuthenticatedSession(token: saved, account: restored)'))
        self.assertIn('guard !Task.isCancelled, !(error is CancellationError), gate.isCurrent(operation)', bootstrap)

    def test_profile_save_refresh_is_phone_channel_independent_and_scoped(self):
        source = (ROOT / 'App/AppSession.swift').read_text()
        refresh = source.split('func refreshOwnAccount() async {', 1)[1].split('private var currentClubActionSession', 1)[0]
        self.assertIn('accountSessionService.storageScope == storageScope', refresh)
        self.assertIn('accountSessionService.currentAccount(token:credential)', refresh)
        self.assertNotIn('guard let service', refresh)
        self.assertIn('gate.currentStamp == stamp,token == credential,account?.id == accountID,fresh.id == accountID', refresh)
        self.assertIn('!Task.isCancelled', refresh)
        self.assertIn('expireIfMatching(error:error,stamp:stamp,credential:credential)', refresh)

    def test_logout_clears_locally_before_channel_independent_revocation(self):
        source = (ROOT / 'App/AppSession.swift').read_text()
        logout = source.split('func logout() async {', 1)[1].split('func activities(', 1)[0]
        self.assertIn('accountSessionService.storageScope == storageScope', logout)
        self.assertLess(logout.index('token=nil;account=nil'), logout.index('accountSessionService.logout(token:oldToken)'))
        self.assertLess(logout.index('vault.clear()'), logout.index('accountSessionService.logout(token:oldToken)'))
        self.assertNotIn('service.logout', logout)

    def test_cancellation_or_transient_error_does_not_erase_saved_token(self):
        source = (ROOT / 'App/AppSession.swift').read_text()
        failure = source.split('func bootstrap() async {', 1)[1].split('} catch {', 1)[1].split('func login(', 1)[0]
        unauthorized = failure.split('if error as? APIError == .unauthorized {', 1)[1].split('}', 1)[0]
        self.assertIn('set(true,forKey:restoreBlockedKey)', unauthorized)
        self.assertIn('vault.clear()', unauthorized)
        self.assertEqual(failure.count('vault.clear()'), 1)
        self.assertLess(failure.index('!(error is CancellationError)'), failure.index('vault.clear()'))

    def test_password_and_us_gates_remain_independent_and_closed(self):
        session = (ROOT / 'App/AppSession.swift').read_text()
        service = (ROOT / 'Core/CNAccountSessionService.swift').read_text()
        self.assertIn('service=regional.availability(of:.usernamePassword) == .available ? AuthService(', session)
        self.assertIn('guard configuration.market == .china', service)
        self.assertIn('storageScope.matches(configuration: configuration)', service)
        self.assertIn('configuration.availability(of: .domesticChinaPhone) == .available', service)
        self.assertNotIn('USAppleService(', session)
        self.assertNotIn('func login', service)


if __name__ == '__main__':
    unittest.main()
