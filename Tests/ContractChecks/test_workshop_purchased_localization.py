"""Source/catalog checks only; no Foundation localization or Apple execution claim."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def resource_first_arguments(source):
    """Read complete first expressions, including nested calls and quoted commas."""
    for match in re.finditer(r'\bLocalizedStringResource\s*\(', source):
        start = match.end()
        depth = 0
        quoted = False
        escaped = False
        for index in range(start, len(source)):
            character = source[index]
            if quoted:
                if escaped:
                    escaped = False
                elif character == '\\':
                    escaped = True
                elif character == '"':
                    quoted = False
                continue
            if character == '"':
                quoted = True
            elif character == '(':
                depth += 1
            elif character == ')':
                if depth == 0:
                    yield source[start:index].strip()
                    break
                depth -= 1
            elif character == ',' and depth == 0:
                yield source[start:index].strip()
                break
        else:
            raise AssertionError('Unterminated LocalizedStringResource call')


class PurchasedLocalizationChecks(unittest.TestCase):
    def test_purchased_title_explicitly_converts_dynamic_key_and_keeps_table_and_environment_locale(self):
        source = (ROOT / 'App/WorkshopPurchasedLibraryView.swift').read_text()
        title = source.split('private struct PurchasedTitle: ViewModifier {', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('let key: String', title)
        self.assertIn('@Environment(\\.locale) private var locale', title)
        self.assertIn('LocalizedStringResource(String.LocalizationValue(stringLiteral: "workshopPurchased." + key), table: "WorkshopPurchased", locale: locale)', title)
        self.assertNotIn('LocalizedStringResource("workshopPurchased." + key,', title)
        self.assertNotIn('Locale.current', title)
        self.assertNotIn('Text(verbatim:', title)
        self.assertIn('String(localized:', title)

    def test_both_dynamic_navigation_suffixes_resolve_to_the_existing_english_and_chinese_catalog_entries(self):
        source = (ROOT / 'App/WorkshopPurchasedLibraryView.swift').read_text()
        suffixes = re.findall(r'\.modifier\(PurchasedTitle\("([^"]+)"\)\)', source)
        self.assertEqual(set(suffixes), {'title', 'detail'})
        catalog = json.loads((ROOT / 'Resources/WorkshopPurchased.xcstrings').read_text())
        expected = {
            'title': {'en': 'Purchased packages', 'zh-Hans': '已购玩法包'},
            'detail': {'en': 'Purchased license details', 'zh-Hans': '已购许可详情'},
        }
        for suffix in suffixes:
            dynamic_key = 'workshopPurchased.' + suffix
            localizations = catalog['strings'][dynamic_key]['localizations']
            self.assertEqual(set(localizations), {'en', 'zh-Hans'})
            for locale, value in expected[suffix].items():
                self.assertEqual(localizations[locale]['stringUnit']['state'], 'translated')
                self.assertEqual(localizations[locale]['stringUnit']['value'], value)
        self.assertEqual(catalog['sourceLanguage'], 'en')

    def test_all_nonliteral_resource_arguments_use_explicit_localization_values_or_the_typed_shared_helper(self):
        nonliteral = []
        for directory in ('App', 'Core'):
            for path in sorted((ROOT / directory).rglob('*.swift')):
                for first in resource_first_arguments(path.read_text()):
                    if re.fullmatch(r'"(?:\\.|[^"\\])*"', first):
                        continue
                    nonliteral.append((path.relative_to(ROOT).as_posix(), re.sub(r'\s+', '', first)))
        self.assertEqual(sorted(nonliteral), sorted([
            ('App/AppLocalizedString.swift', 'key'),
            ('App/OwnedTopicCoverAuthorView.swift', 'key'),
            ('App/ProjectEditDetailForms.swift', 'key'),
            ('App/ProjectStoryAudioAuthorView.swift', 'key'),
            ('App/ProjectStoryImageAuthorView.swift', 'key'),
            ('App/WorkshopOwnedLibraryView.swift', 'String.LocalizationValue(stringLiteral:"workshopOwned."+key)'),
            ('App/WorkshopPurchasedLibraryView.swift', 'String.LocalizationValue(stringLiteral:"workshopPurchased."+key)'),
        ]))
        shared = (ROOT / 'App/AppLocalizedString.swift').read_text()
        self.assertIn('func appLocalized(_ key:String.LocalizationValue,locale:Locale)->String', shared)
        self.assertIn('LocalizedStringResource(key,locale:locale)', shared)
        # The reviewed media branch uses the StaticString/defaultValue overload.
        # Prove the parameter and fallback types; an arbitrary String key is not allowed.
        helpers = [
            ('OwnedTopicCoverAuthorView.swift', 'text', 'english', 'locale'),
            ('ProjectEditDetailForms.swift', 'imageText', 'fallback', 'storyImageLocale'),
            ('ProjectStoryAudioAuthorView.swift', 'text', 'fallback', 'locale'),
            ('ProjectStoryImageAuthorView.swift', 'text', 'fallback', 'locale'),
        ]
        for filename, function, fallback, locale in helpers:
            source = re.sub(r'\s+', '', (ROOT/'App'/filename).read_text())
            self.assertIn('privatefunc'+function+'(_key:StaticString,_'+fallback+':String.LocalizationValue)->String', source)
            self.assertIn('LocalizedStringResource(key,defaultValue:'+fallback+',locale:'+locale+')', source)
            self.assertNotIn('privatefunc'+function+'(_key:String,', source)


    def test_expression_scan_rejects_unwrapped_dynamic_string_and_keeps_nested_wrapper_intact(self):
        bad = list(resource_first_arguments('LocalizedStringResource("workshopPurchased." + key, table: "WorkshopPurchased", locale: locale)'))
        good = list(resource_first_arguments('LocalizedStringResource(String.LocalizationValue(stringLiteral: "workshopPurchased." + key), table: "WorkshopPurchased", locale: locale)'))
        self.assertEqual(bad, ['"workshopPurchased." + key'])
        self.assertIsNone(re.fullmatch(r'"(?:\\.|[^"\\])*"', bad[0]))
        self.assertEqual(good, ['String.LocalizationValue(stringLiteral: "workshopPurchased." + key)'])


if __name__ == '__main__':
    unittest.main()
