"""Source-only integration guards; Swift/Keychain execution remains an Apple CI gate."""
import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class RegionalStorageBoundaryTests(unittest.TestCase):
    def test_scope_uses_explicit_deployment_components_and_no_account_or_locale(self):
        source = (ROOT / 'Core/RegionalSessionStorageScope.swift').read_text()
        self.assertIn('[bundleIdentifier, market.rawValue, endpoint, realm]', source)
        self.assertIn('configuration.apiConfiguration?.baseURL.absoluteString', source)
        self.assertIn('"questify.session.v2."', source)
        self.assertIn('scope', (ROOT / 'App/KeychainTokenStore.swift').read_text())
        self.assertIn('!value.contains("$(")', source)
        self.assertNotRegex(source, r'\b(?:accountID|Locale|UserDefaults)\b')

    def test_every_live_service_is_inside_the_storage_scope_gate(self):
        source = (ROOT / 'App/AppSession.swift').read_text()
        gated = source.split('if let scope, let regional, let configuration=regional.apiConfiguration {', 1)[1].split('} else {', 1)[0]
        live_constructors = re.findall(r'\b\w*Service\(configuration:configuration,transport:transport\)', source)
        self.assertGreater(len(live_constructors), 20)
        self.assertEqual(live_constructors, re.findall(r'\b\w*Service\(configuration:configuration,transport:transport\)', gated))
        for service in ['creatorContentService', 'accountCollectionService', 'cooperationService']:
            self.assertRegex(gated, service + r'=\w+Service\(configuration:configuration,transport:transport\)')
            self.assertIn(service + '=nil', source)
        self.assertIn('var isConfigured: Bool { storageScope != nil }', source)
        self.assertIn('vault=KeychainTokenStore(scope:scope)', source)
        self.assertIn('restoreBlockedKey=scope?.restoreBlockedKey', source)
        self.assertNotIn('KeychainTokenStore(market:', source)
        self.assertNotIn('"session.preventRestore."', source)

    def test_nil_scope_never_queries_or_deletes_legacy_keychain_items(self):
        source = (ROOT / 'App/KeychainTokenStore.swift').read_text()
        self.assertIn('guard let scope else { throw StoreError.unconfigured }', source)
        self.assertIn('kSecAttrService as String:scope.service', source)
        self.assertIn('kSecAttrSynchronizable as String:false', source)
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', source)
        read = source.split('func read()', 1)[1].split('func write(', 1)[0]
        clear = source.split('func clear()', 1)[1]
        self.assertLess(read.index('guard scope != nil else { return nil }'), read.index('SecItemCopyMatching'))
        self.assertLess(clear.index('guard scope != nil else { return }'), clear.index('SecItemDelete'))
        self.assertNotIn('Bundle.main', source)
        self.assertNotIn('"Questify"', source)

    def test_realm_metadata_is_explicit_and_local_override_is_not_erased(self):
        with (ROOT / 'Config/Info.plist').open('rb') as handle:
            metadata = plistlib.load(handle)
        self.assertEqual(metadata['QuestifySessionRealm'], '$(QUESTIFY_SESSION_REALM)')
        config = (ROOT / 'Config/Base.xcconfig').read_text()
        assignments = re.findall(r'^QUESTIFY_SESSION_REALM\s*=([^\n]*)$', config, re.MULTILINE)
        self.assertEqual(assignments, [''])
        self.assertLess(config.index('QUESTIFY_SESSION_REALM ='), config.index('#include? "Local.xcconfig"'))
        self.assertIn('INFOPLIST_KEY_QuestifySessionRealm = $(QUESTIFY_SESSION_REALM)', config)

    def test_region_hardening_does_not_enable_provider_or_write_capabilities(self):
        launch = (ROOT / 'App/RegionalLaunchConfiguration.swift').read_text()
        session = (ROOT / 'App/AppSession.swift').read_text()
        apple = (ROOT / 'Core/USAppleContracts.swift').read_text()
        self.assertIn('let approved:[RegionalMarket:Set<String>]=[:]', launch)
        self.assertIn('verifiedCapabilities:[]', launch)
        self.assertIn('storageScope != nil && regionalConfiguration?.availability(of:.usernamePassword) == .available', session)
        self.assertIn('regional.canUseDomesticChinaPhone ?', session)
        self.assertIn('answersEnabled:false', session)
        self.assertRegex(apple, r'static let enabled\s*=\s*false')


if __name__ == '__main__':
    unittest.main()
