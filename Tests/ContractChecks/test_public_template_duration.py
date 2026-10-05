"""Public topic-template duration is seconds, independent of legacy minute display helpers."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublicTemplateDurationContracts(unittest.TestCase):
    def test_catalog_seconds_are_typed_and_not_relabelled_as_minutes(self):
        dto = (ROOT / 'Core/DiscoveryContracts.swift').read_text().split('public struct DiscoveryTopicTemplate:', 1)[1].split('public struct DiscoveryTemplateHome:', 1)[0]
        self.assertIn('public let totalTime: Int?', dto)
        self.assertIn('decodeIfPresent(Int.self, forKey: .totalTime)', dto)
        self.assertIn('totalTime.map({ $0 >= 0 })', dto)
        self.assertNotIn('durationValue', dto)
        metadata = (ROOT / 'App/DiscoveryComponents.swift').read_text().split('struct DiscoveryTopicMetadata:', 1)[1].split('extension DiscoveryPackType', 1)[0]
        self.assertIn('if let seconds = item.totalTime', metadata)
        self.assertIn('LabeledContent("discovery.publicSeconds", value: String(seconds))', metadata)
        self.assertNotIn('discovery.durationValue', metadata)
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())
        units = catalog['strings']['discovery.publicSeconds']['localizations']
        self.assertEqual(units['en']['stringUnit']['value'], 'Duration (seconds)')
        self.assertEqual(units['zh-Hans']['stringUnit']['value'], '时长（秒）')

    def test_duration_fixture_and_regressions_use_source_contract(self):
        fixture = (ROOT / 'App/DiscoveryFixtureReader.swift').read_text()
        self.assertIn('"totalTime":5400', fixture)
        self.assertNotIn('"totalTime":"90 minutes"', fixture)
        tests = (ROOT / 'Tests/CoreTests/DiscoveryContractTests.swift').read_text()
        for name in ['PublicTopicDurationPreservesIntegralSecondsAndExplicitZero',
                     'PublicTopicMissingDurationRemainsUnknown',
                     'PublicTopicMalformedDurationNeverBecomesMinutesOrUnknown']:
            self.assertIn('func test' + name, tests)


if __name__ == '__main__':
    unittest.main()
