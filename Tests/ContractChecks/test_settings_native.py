"""Offline source guardrails, not Swift or runtime evidence."""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SettingsNativeSourceChecks(unittest.TestCase):
    def test_attribution_copy_reuses_local_button_and_keeps_selectable_addresses(self):
        source = (ROOT/'App/SettingsSupportSections.swift').read_text()
        self.assertIn('SettingsAttributionsSection(copyText: copyText)', source)
        attribution = source.split('@MainActor struct SettingsAttributionsSection: View {', 1)[1]
        self.assertIn('let copyText: (String) throws -> Void', attribution)
        self.assertIn('NativeCopyTextButton(text: attribution.sourceURL,', attribution)
        self.assertIn('title: LocalizedStringKey(attribution.copyTitleKey)', attribution)
        self.assertIn('copyText: copyText)', attribution)
        self.assertIn('Text(verbatim: attribution.sourceURL)', attribution)
        self.assertIn('.textSelection(.enabled)', attribution)
        self.assertNotIn('onAppear', attribution)
        self.assertNotIn('UIPasteboard', attribution)
        self.assertNotIn('Link(', attribution)

    def test_attribution_row_identifier_is_on_title_leaf_not_copy_feedback_ancestor(self):
        source = (ROOT/'App/SettingsSupportSections.swift').read_text()
        attribution = source.split('@MainActor struct SettingsAttributionsSection: View {', 1)[1]
        title = 'Text(verbatim: attribution.title).font(.subheadline.weight(.semibold))'
        row_id = '.accessibilityIdentifier("settingsNative.attribution.\\(attribution.id)")'
        self.assertEqual(attribution.count(row_id), 1)
        self.assertIn(title + '\n                        ' + row_id, attribution)
        self.assertNotIn(row_id, attribution.split('NativeCopyTextButton(', 1)[1])
        self.assertIn('identifier: "settingsNative.attribution.copy.\\(attribution.id)"', attribution)
        copy = (ROOT/'App/NativeCopyTextButton.swift').read_text()
        self.assertIn('.accessibilityIdentifier(identifier)', copy)
        self.assertIn('.accessibilityIdentifier(identifier + (status == .copied ? ".copied" : ".failed"))', copy)
        self.assertIn('try copyText(text)', copy)
        self.assertIn('.onDisappear { status = nil }', copy)

    def test_attribution_copy_labels_identify_each_source_in_both_languages(self):
        contracts = (ROOT/'Core/SettingsAboutContracts.swift').read_text()
        self.assertIn('public var copyTitleKey: String { "settingsNative.attribution.copy.\\(id)" }', contracts)
        catalog = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        expected = {
            'game-icons': ('Copy game-icons.net source address', '复制 game-icons.net 来源地址'),
            'ansimuz': ('Copy ansimuz source address', '复制 ansimuz 来源地址'),
        }
        for identifier, values in expected.items():
            entry = catalog['settingsNative.attribution.copy.' + identifier]['localizations']
            for locale, value in zip(['en', 'zh-Hans'], values):
                self.assertEqual(entry[locale]['stringUnit']['value'], value)

    def test_attribution_copy_fixture_records_only_success_and_can_retry_failure(self):
        fixture = (ROOT/'App/SettingsFixtureSupport.swift').read_text()
        self.assertIn('if scenario == "attributionCopyFailure", !hasFailedCopy', fixture)
        self.assertIn('hasFailedCopy = true', fixture)
        self.assertIn('copiedText = text', fixture)
        self.assertIn('settingsNative.fixture.copiedText', fixture)
        self.assertLess(fixture.index('throw SettingsSoundStoreError.writeFailed', fixture.index('if scenario == "attributionCopyFailure"')), fixture.index('copiedText = text'))
        self.assertNotIn('UIPasteboard', fixture)

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
