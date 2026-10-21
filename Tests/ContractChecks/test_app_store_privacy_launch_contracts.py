import json
import pathlib
import plistlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def xcconfig_keys(text):
    return dict(re.findall(r'^(INFOPLIST_KEY_\w+)\s*=\s*(.+)$', text, re.M))


class AppStorePrivacyLaunchContracts(unittest.TestCase):
    def test_usage_strings_in_xcconfig_and_bilingual_catalog(self):
        keys = xcconfig_keys((ROOT / 'Config/Base.xcconfig').read_text())
        catalog = json.loads((ROOT / 'Resources/InfoPlist.xcstrings').read_text())['strings']
        for name in ('NSLocationWhenInUseUsageDescription', 'NSMicrophoneUsageDescription'):
            self.assertTrue(keys.get('INFOPLIST_KEY_' + name, '').strip(), name)
            localizations = catalog[name]['localizations']
            self.assertEqual(localizations['en']['stringUnit']['value'], keys['INFOPLIST_KEY_' + name])
            self.assertRegex(localizations['zh-Hans']['stringUnit']['value'], r'[\u4e00-\u9fff]')
        self.assertIn('background', keys['INFOPLIST_KEY_NSLocationWhenInUseUsageDescription'])
        mic_en = catalog['NSMicrophoneUsageDescription']['localizations']['en']['stringUnit']['value']
        mic_zh = catalog['NSMicrophoneUsageDescription']['localizations']['zh-Hans']['stringUnit']['value']
        for snippet in ('NPC voice', 'sound peak', 'amplitude is measured on device without uploading audio'):
            self.assertIn(snippet, mic_en)
        for snippet in ('NPC', '声音互动玩法', '本地测量振幅', '不上传录音'):
            self.assertIn(snippet, mic_zh)

    def test_no_background_or_always_location_declarations(self):
        blob = '\n'.join((ROOT / p).read_text() for p in (
            'Config/Base.xcconfig', 'Config/Info.plist', 'Resources/InfoPlist.xcstrings', 'Resources/PrivacyInfo.xcprivacy'))
        for forbidden in ('NSLocationAlwaysUsageDescription', 'NSLocationAlwaysAndWhenInUseUsageDescription',
                          'UIBackgroundModes', 'INFOPLIST_KEY_UIBackgroundModes'):
            self.assertNotIn(forbidden, blob)
        self.assertEqual(list(ROOT.glob('*.entitlements')) + list(ROOT.glob('App/*.entitlements')), [])

    def test_privacy_manifest(self):
        manifest = plistlib.loads((ROOT / 'Resources/PrivacyInfo.xcprivacy').read_bytes())
        self.assertIs(manifest['NSPrivacyTracking'], False)
        self.assertEqual(manifest['NSPrivacyTrackingDomains'], [])
        apis = {item['NSPrivacyAccessedAPIType']: item['NSPrivacyAccessedAPITypeReasons']
                for item in manifest['NSPrivacyAccessedAPITypes']}
        self.assertEqual(apis, {
            'NSPrivacyAccessedAPICategoryUserDefaults': ['CA92.1'],
            'NSPrivacyAccessedAPICategoryFileTimestamp': ['C617.1'],
            'NSPrivacyAccessedAPICategorySystemBootTime': ['35F9.1'],
        })
        for item in manifest['NSPrivacyCollectedDataTypes']:
            self.assertIs(item['NSPrivacyCollectedDataTypeTracking'], False)
            self.assertTrue(item['NSPrivacyCollectedDataTypePurposes'])

    def test_privacy_manifest_registered_as_app_resource(self):
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        self.assertIn('Resources/PrivacyInfo.xcprivacy', project)
        self.assertIn('PrivacyInfo.xcprivacy', (ROOT / 'tools/generate_project.py').read_text())

    def test_local_xcconfig_example_is_placeholder_only_and_ignored(self):
        lines = (ROOT / 'Config/Local.xcconfig.example').read_text().splitlines()
        active = [line for line in lines if line.strip() and not line.lstrip().startswith('//')]
        self.assertEqual(active, [])
        text = '\n'.join(lines)
        for key in ('DEVELOPMENT_TEAM', 'PRODUCT_BUNDLE_IDENTIFIER', 'QUESTIFY_API_BASE_URL', 'QUESTIFY_SESSION_REALM'):
            self.assertRegex(text, r'(?m)^// ' + key + r' = .*<[A-Z_]+')
        self.assertNotIn('47.103.124.64', text)
        ignored = subprocess.run(['git', 'check-ignore', '-q', 'Config/Local.xcconfig'], cwd=ROOT)
        self.assertEqual(ignored.returncode, 0)

    def test_release_docs_match_repository_reality(self):
        checklist = (ROOT / 'docs/release-readiness-checklist.md').read_text()
        self.assertNotIn('com.example.questify', checklist)
        self.assertNotIn('CODE_SIGNING_ALLOWED = NO`, `PRODUCT', checklist)
        handoff = (ROOT / 'docs/handoff/issue-61-response-20261020.md').read_text()
        self.assertNotIn('仍为空 `[]`', handoff)
        self.assertNotIn('仍为空数组', handoff)
        self.assertNotIn('CODE_SIGNING_ALLOWED', (ROOT / 'Config/Base.xcconfig').read_text())


if __name__ == '__main__':
    unittest.main()
