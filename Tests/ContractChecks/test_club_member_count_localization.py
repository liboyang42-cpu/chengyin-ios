"""Source/catalog contracts only; compiled Apple localization is covered by App XCTest."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ClubMemberCountLocalizationContractTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/ClubComponents.swift').read_text()
        self.catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']

    def test_bilingual_singular_and_plural_resources_preserve_integer_placeholder(self):
        expected = {'club.memberCount.singular %lld': ('%lld member', '%lld 名成员'),
                    'club.memberCount %lld': ('%lld members', '%lld 名成员')}
        for key, values in expected.items():
            for language, value in zip(('en', 'zh-Hans'), values):
                self.assertEqual(self.catalog[key]['localizations'][language]['stringUnit'],
                                 {'state': 'translated', 'value': value})
                self.assertEqual(re.findall(r'%[a-z]+', value), ['%lld'])

    def test_normal_card_uses_explicit_environment_locale_formatter(self):
        row = self.source.split('struct ClubRow: View {', 1)[1].split('struct ClubOptionalRow:', 1)[0]
        self.assertIn('@Environment(\\.locale) private var locale', row)
        self.assertIn('Text(verbatim: ClubMemberCountLocalization.text(club.memberCount, locale: locale))', row)
        self.assertIn('if club.isOwner { Text("club.role.creator") }', row)
        self.assertIn('else if club.isJoined { Text("club.membership.joined") }', row)
        self.assertNotIn('Text("club.memberCount \\(club.memberCount)")', row)

    def test_formatter_has_only_exact_one_branch_and_never_clamps_source(self):
        formatter = self.source.split('enum ClubMemberCountLocalization {', 1)[1].split('struct ClubRow:', 1)[0]
        self.assertIn('if count == 1 {', formatter)
        self.assertIn('LocalizedStringResource("club.memberCount.singular \\(count)", locale: locale)', formatter)
        self.assertIn('LocalizedStringResource("club.memberCount \\(count)", locale: locale)', formatter)
        self.assertIn('String(localized: resource(count, locale: locale))', formatter)
        for forbidden in ['Locale.current', 'UserDefaults', 'abs(', 'max(', 'Int32(', 'members"', '名成员']:
            self.assertNotIn(forbidden, formatter)

    def test_authored_app_cases_include_real_resource_resolution_and_normal_host(self):
        source = (ROOT / 'Tests/AppUnitTests/ClubMemberCountLocalizationTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test[A-Za-z0-9_]+\(', source)), 6)
        self.assertIn('Int.max', source)
        self.assertIn('ClubRow(club: club)', source)
        self.assertIn('.dynamicTypeSize(.accessibility5)', source)
        self.assertIn('resource.locale, locale', source)
        self.assertIn('"1 member"', source)
        self.assertIn('"1 名成员"', source)

if __name__ == '__main__':
    unittest.main()
