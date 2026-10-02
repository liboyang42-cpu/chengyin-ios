"""Offline source guardrails, not Swift or runtime evidence."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SettingsNativeSourceChecks(unittest.TestCase):
    def test_legal_market_never_follows_language(self):
        source = (ROOT/'Core/SettingsSourceLegalCatalog.swift').read_text()
        self.assertIn('guard let market else { return .missing(.missingMarket) }', source)
        self.assertIn('guard market == .china else { return .missing(.regionalTextNotProvided) }', source)
        self.assertIn('case .privacyPolicy: return .missing(.pendingSourceText)', source)
        self.assertNotIn('AppLanguage', source)
        self.assertNotIn('Locale', source)

    def test_settings_module_has_no_live_or_device_side_effect_adapters(self):
        files = list((ROOT/'Core').glob('Settings*.swift')) + [ROOT/'App'/name for name in ['SettingsAboutView.swift','SettingsSupportSections.swift','SettingsLegalDocumentView.swift','SettingsFixtureSupport.swift']]
        source = '\n'.join(path.read_text() for path in files)
        for forbidden in ['URLSession','URLRequest','openURL','UIApplication.shared','CLLocationManager','AVAudioSession','UIImpactFeedbackGenerator','AuthRequestBuilder','setMarketingConsent','revokeRoamLocationConsent']:
            self.assertNotIn(forbidden, source)

    def test_existing_settings_remains_only_owner_of_language(self):
        source = (ROOT/'App/SettingsView.swift').read_text()
        self.assertIn('@AppStorage("preferences.language")', source)
        self.assertIn('RegionalLaunchConfiguration.language(storedLanguage)', source)
        self.assertIn('SettingsSupportSections(market: session.operationalMarket, complianceCoordinator: session.accountComplianceCoordinator)', source)
        self.assertNotIn('market: language', source)
        self.assertEqual(source.count('NavigationStack'), 1)
        self.assertNotIn('@AppStorage', (ROOT/'App/SettingsSupportSections.swift').read_text())

    def test_app_metadata_is_bundle_derived_not_flutter_version(self):
        source = (ROOT/'Core/SettingsAboutContracts.swift').read_text()
        for field in ['CFBundleDisplayName','CFBundleShortVersionString','CFBundleVersion','bundle.infoDictionary']:
            self.assertIn(field, source)
        self.assertNotIn('1.0.0', (ROOT/'App/SettingsAboutView.swift').read_text())

    def test_every_localization_fragment_value_is_installed(self):
        entries = json.loads((ROOT/'docs/settings-native-localizations.json').read_text())
        catalog = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        self.assertEqual(len(entries), len({entry['key'] for entry in entries}))
        for entry in entries:
            for locale in ['en','zh-Hans']:
                self.assertEqual(catalog[entry['key']]['localizations'][locale]['stringUnit']['value'], entry[locale])

    def test_debug_fixture_is_memory_backed_and_root_reuses_module_router(self):
        source = (ROOT/'App/ModuleFixtureSupport.swift').read_text()
        self.assertIn('case settingsNative', source)
        self.assertIn('case .settingsNative: SettingsFixtureHostView()', source)
        fixture = (ROOT/'App/SettingsFixtureSupport.swift').read_text()
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertNotIn('UserDefaults', fixture)
        self.assertNotIn('SettingsLocalSoundStore', fixture)

    def test_legal_view_cannot_record_acceptance(self):
        source = (ROOT/'App/SettingsLegalDocumentView.swift').read_text()
        self.assertIn('.onDisappear { model.invalidate() }', source)
        self.assertIn('settingsNative.legal.sourceNotice', source)
        self.assertIn('settingsNative.legal.noAcceptance', source)
        self.assertNotIn('func accept', source)
        self.assertNotIn('consentStore', source)
        contracts = (ROOT/'Core/SettingsLegalContracts.swift').read_text()
        self.assertIn('public var isReleaseApproved: Bool { false }', contracts)

    def test_local_flags_do_not_claim_playback_or_modify_system_state(self):
        source = (ROOT/'Core/SettingsSoundPreferences.swift').read_text()
        self.assertIn('case sound, haptics, airplane, ocean, raindrop, forest', source)
        self.assertIn('guard !state.isBusy, var next = state.preferences', source)
        self.assertIn('try await store.write(next)', source)
        self.assertIn('state.preferences = next', source)
        self.assertIn('scene_sound_haptics', source)
        self.assertNotIn('preferences.language', source)
