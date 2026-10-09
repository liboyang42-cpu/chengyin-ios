"""Source contracts only; passing these is not Swift compilation or UI execution."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SearchMapActivityCardContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = (ROOT / 'Core/ActivitySummary.swift').read_text()
        cls.presentation = (ROOT / 'Core/SearchMapActivityPresentation.swift').read_text()
        cls.card = (ROOT / 'App/SearchMapActivityCard.swift').read_text()
        cls.explorer = (ROOT / 'App/SearchMapExplorerView.swift').read_text()
        cls.core_tests = (ROOT / 'Tests/CoreTests/SearchMapActivityPresentationTests.swift').read_text()
        cls.app_tests = (ROOT / 'Tests/AppUnitTests/SearchMapActivityCardTests.swift').read_text()

    def test_decodes_only_real_source_category_names_and_keeps_business_text(self):
        self.assertIn('case categoryName', self.model)
        self.assertIn('forKey: .sysCategoryList', self.model)
        self.assertIn('.compactMap(\\.name)', self.model)
        category = self.model.split('private struct ActivitySummaryCategory:', 1)[1].split('/// Decode supported', 1)[0]
        self.assertIn('name = raw', category)
        for invented in ['categoryIds', 'case name', 'lowercased()', 'capitalized']:
            self.assertNotIn(invented, category)

    def test_result_list_and_selected_object_use_the_identical_card(self):
        self.assertEqual(self.explorer.count('SearchMapActivityCard(item: row, offline: reader.isOfflineExample)'), 2)
        selected = self.explorer.split('private func pinDetail(', 1)[1].split('else if let node', 1)[0]
        result_list = self.explorer.split('ForEach(pagination.rows)', 1)[1].split('activityPaginationControls', 1)[0]
        for surface in [selected, result_list]:
            self.assertIn('destination(.activity(row.id))', surface)
        self.assertIn('if let topic = row.linkedTopicID', selected)
        self.assertIn('destination(.topic(topic))', selected)
        self.assertNotIn('row.topicID', selected)

    def test_topic_label_cannot_rewrite_activity_identity(self):
        self.assertIn('linkedTopicID = activity.linkedTopicID', self.presentation)
        self.assertIn('linkedTopicID == nil ? .activity : .topic', self.presentation)
        self.assertIn('primaryDestination: SearchMapDestination { .activity(activityID) }', self.presentation)
        self.assertNotIn('productType', self.presentation)
        self.assertIn('id: "activity-\\(activity.id)"', self.explorer)

    def test_source_fields_and_missing_states_are_visible_without_extra_metrics(self):
        for fragment in ['value.categoryNames', 'value.linkedTopicID != nil', 'value.address', 'timestamp(value.starts', 'timestamp(value.ends', 'mapActivity.addressUnknown', 'mapActivity.timeUnknown']:
            self.assertIn(fragment, self.card)
        self.assertIn('address = Self.nonblank(activity.address)', self.presentation)
        for field in ['minimumAmount', 'distance', 'rating', 'viewCount', 'favorited']:
            self.assertNotIn(field, self.card)

    def test_dates_are_strict_and_phone_zone_changes_rerender_same_instant(self):
        self.assertIn('TimeZone(identifier: "Asia/Shanghai")', self.presentation)
        self.assertIn('case calendarDay(String)', self.presentation)
        self.assertIn('case instant(Date)', self.presentation)
        self.assertEqual(self.presentation.count('formatter.string(from: date) == value'), 2)
        self.assertIn('case .calendarDay(let value): return value', self.presentation)
        self.assertIn('timeZone: phoneTimeZone', self.presentation)
        self.assertIn('yyyy-MM-dd HH:mm:ss XXX', self.presentation)
        self.assertIn('NSSystemTimeZoneDidChange', self.card)
        self.assertIn('phoneTimeZone = .current', self.card)
        self.assertNotIn('Text(verbatim: item.startDate', self.card)

    def test_offline_artwork_and_accessibility_use_existing_native_primitive(self):
        self.assertIn('QuestifyImageEntityCard(imageSource: offline ? nil : item.imageURL', self.card)
        self.assertIn('QuestifyImageEntityMetadata', self.card)
        self.assertIn('.accessibilityElement(children: .combine)', self.card)
        self.assertNotIn('.lineLimit(1)', self.card)
        self.assertNotIn('.frame(height:', self.card)

    def test_new_copy_is_complete_bilingual_fragment(self):
        fragment = json.loads((ROOT / 'Resources/SearchMapActivityCardLocalizations.fragment.json').read_text())
        used = set(re.findall(r'"(mapActivity\.[A-Za-z.]+)"', self.card))
        used |= {'mapActivity.point.activity', 'mapActivity.point.topic'}
        self.assertEqual(used, set(fragment))
        for entry in fragment.values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            self.assertTrue(all(value['stringUnit']['value'] for value in entry['localizations'].values()))

    def test_authored_tests_cover_invalid_links_missing_values_calendar_days_and_dst(self):
        for case in ['testActualCategoryListNamesStayVerbatimAndInSourceOrder',
                     'testInvalidLinkAndProductTypeCannotCreateThemePoint',
                     'testSameNumberAcrossDomainsKeepsIndependentRoutes',
                     'testDateOnlyRetainsCalendarDayAcrossPhoneZones',
                     'testShanghaiDTOInstantDisplaysAcrossMidnightInPhoneZone',
                     'testPhoneDaylightSavingTransitionUsesOffsetAtEachInstant',
                     'testMissingMalformedAndUnverifiedFormatsAreUnknown']:
            self.assertIn(case, self.core_tests)
        for case in ['testListAndSelectedCardReceiveIdenticalPresentation',
                     'testCardGrowsForAccessibilityTextWithoutHorizontalOverflow',
                     'testMissingAddressAndTimeStatesConstructInBothLanguages']:
            self.assertIn(case, self.app_tests)

    def test_presentation_has_no_network_location_or_business_mutation(self):
        for source in [self.presentation, self.card]:
            for forbidden in ['URLSession', 'CLLocationManager', 'MKDirections', 'requestWhenInUseAuthorization',
                              'startUpdatingLocation', '/reveal', '/arrive', '/favorite', 'grant =', 'Task {']:
                self.assertNotIn(forbidden, source)

    def test_hosted_measurements_keep_strict_growth_and_content_bounds(self):
        self.assertIn('ScrollView {', self.explorer)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', self.app_tests)
        self.assertIn('CGSize(width: 300, height: proposedHeight)', self.app_tests)
        self.assertIn('XCTAssertGreaterThan(largest.height, normal.height', self.app_tests)
        self.assertNotIn('XCTAssertGreaterThanOrEqual(largest.height, normal.height', self.app_tests)
        for assertion in ['size.width.isFinite && size.height.isFinite',
                          'XCTAssertLessThanOrEqual(size.width, 301',
                          'XCTAssertLessThan(size.height, 10_000',
                          'testIntrinsicCardHeightDoesNotFollowHostingProposal',
                          'proposedHeight: 10_000', 'proposedHeight: 20_000',
                          'XCTAssertEqual(first.height, second.height, accuracy: 0.5']:
            self.assertIn(assertion, self.app_tests)


if __name__ == '__main__':
    unittest.main()
