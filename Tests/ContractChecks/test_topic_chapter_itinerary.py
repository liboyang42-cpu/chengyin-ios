"""Offline source assertions, not Swift execution or Apple UI evidence."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TopicChapterItineraryChecks(unittest.TestCase):
    def test_projection_uses_only_adjacent_visible_stops(self):
        source = (ROOT / 'Core/TopicChapterItinerary.swift').read_text()
        for value in ['chapter.nodes.enumerated()', 'chapter.nodes[index - 1]', 'index > 0',
                      'latitude != 0, longitude != 0', 'RoamCoordinate(latitude: latitude, longitude: longitude)',
                      'meters.isFinite, meters > 0', 'RoamExperienceMath.distanceMeters',
                      'max(1, Int((meters / 80).rounded()))']:
            self.assertIn(value, source)
        for forbidden in ['nodeTime', '.sorted(', '.filter(', 'totalChapterCount', 'URLSession',
                          'SearchRoutePreview(', 'requestLocation', 'isSignUp', 'APIConfiguration']:
            self.assertNotIn(forbidden, source)

    def test_coordinate_string_support_is_scoped_to_topic_nodes(self):
        source = (ROOT / 'Core/TopicContracts.swift').read_text()
        self.assertIn('Double($0.trimmingCharacters(in: .whitespacesAndNewlines))', source)
        self.assertIn('return value.flatMap { $0.isFinite ? $0 : nil }', source)
        self.assertEqual(source.count('= c.coordinate('), 2)
        self.assertIn('latitude = c.coordinate("latitude")', source)
        self.assertIn('longitude = c.coordinate("longitude")', source)
        self.assertIn('averageRating = c.number("averageRating")', source)

    def test_reader_scope_and_estimate_disclosure_remain_visible(self):
        source = (ROOT / 'App/TopicDetailView.swift').read_text().split('struct TopicChapterView', 1)[1]
        self.assertIn('if scope != reader.scope { TopicIssueView(issue: .unavailable) }', source)
        self.assertIn('ForEach(itinerary.stops)', source)
        self.assertIn('if itinerary.hasWalkingEstimates', source)
        self.assertLess(source.index('TopicWalkingEstimate(minutes:'), source.index('Text(verbatim: node.name)'))
        self.assertIn('PlatformExternalMapHost(destination:', source)
        self.assertIn('if let owner = PublicMerchantOwnerID(merchant.memberID)', source)
        component = (ROOT / 'App/TopicComponents.swift').read_text()
        self.assertIn('.accessibilityValue(String(minutes))', component)
        self.assertIn('.accessibilityElement(children: .combine)', component)

    def test_all_new_localization_keys_are_bilingual_and_estimate_is_honest(self):
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        keys = {key for key in strings if key.startswith('topic.itinerary.')}
        self.assertEqual(keys, {'topic.itinerary.estimatedWalkMinutes', 'topic.itinerary.estimateNotice',
                                'topic.itinerary.stopNumber'})
        for key in keys:
            self.assertEqual(set(strings[key]['localizations']), {'en', 'zh-Hans'})
        notice = strings['topic.itinerary.estimateNotice']['localizations']
        self.assertIn('straight-line', notice['en']['stringUnit']['value'])
        self.assertIn('80 m/min', notice['en']['stringUnit']['value'])
        self.assertIn('直线距离', notice['zh-Hans']['stringUnit']['value'])

    def test_authored_tests_include_rounding_unknown_geometry_and_navigation(self):
        unit = (ROOT / 'Tests/CoreTests/TopicChapterItineraryTests.swift').read_text()
        for name in ['testNumericAndStringCoordinatesUseSameEstimateAndKeepSourceOrder',
                     'testOnlyImmediatePredecessorCanSupplyAnEstimate',
                     'testFirstStopEmptyChapterAndSeparateChaptersHaveNoInventedLeg',
                     'testMissingMalformedZeroAndOutOfRangeCoordinatesOmitBothAdjacentLegs',
                     'testIdenticalLocationsHaveNoArtificialOneMinuteWalk',
                     'testNearestMinuteRoundingAndMinimumOneMinute',
                     'testDwellChapterAndChallengeDurationsDoNotBecomeWalkingTime',
                     'testAntimeridianUsesShortDistanceAndAntipodesRemainFinite']:
            self.assertIn(name, unit)
        ui = (ROOT / 'Tests/AppUITests/TopicFlowTests.swift').read_text()
        self.assertIn('testChapterItineraryEstimatesUnknownLegsAndBackReopen', ui)
        self.assertIn('testChapterItineraryEstimateUsesChineseLabels', ui)
        self.assertIn('"1", file: file, line: line', ui)


if __name__ == '__main__':
    unittest.main()
