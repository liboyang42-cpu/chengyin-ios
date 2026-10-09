"""Offline source assertions only; not Swift compilation or runtime evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SearchMapDatePresetContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / 'Core/SearchMapDatePresets.swift').read_text()
        cls.sheet = (ROOT / 'App/SearchMapFilterSheet.swift').read_text()

    def test_shipping_sheet_uses_draft_helper_and_shows_shortcuts_for_global_and_city(self):
        self.assertIn('@State private var dateDraft: SearchMapDateFilterDraft', self.sheet)
        dates = self.sheet.split('Section("searchMap.dates") {', 1)[1].split('TextField("searchMap.startDate"', 1)[0]
        self.assertLess(dates.index('Button("mapDatePreset.today")'), dates.index('if applyCityOptions != nil'))
        self.assertLess(dates.index('Button("mapDatePreset.tomorrow")'), dates.index('if applyCityOptions != nil'))
        self.assertEqual(dates.count('Button("mapDatePreset.today")'), 1)
        self.assertEqual(dates.count('Button("mapDatePreset.tomorrow")'), 1)
        self.assertIn('Text("globalDatePreset.disclosure")', dates)
        self.assertIn('selectDatePreset(.tomorrow)', self.sheet)
        self.assertIn('text: $dateDraft.startDate', self.sheet)
        self.assertIn('text: $dateDraft.endDate', self.sheet)

    def test_calendar_is_phone_zone_gregorian_with_calendar_day_addition(self):
        for text in ['Calendar(identifier: .gregorian)', 'timeZone: TimeZone = .current',
                     'calendar.timeZone = timeZone', 'date(byAdding: .day, value: preset.rawValue, to: now)',
                     'startDate = value', 'endDate = value']:
            self.assertIn(text, self.helper)
        for text in ['86400', 'Asia/Shanghai', 'Calendar.current', 'DateFormatter', 'Timer', 'Task {']:
            self.assertNotIn(text, self.helper)

    def test_apply_is_the_only_commit_and_cancel_remains_dismiss_only(self):
        select = self.sheet.split('private func selectDatePreset(', 1)[1].split('private func commit()', 1)[0]
        self.assertIn('dateDraft.select(preset)', select)
        self.assertNotIn('apply(', select)
        self.assertIn('Button("searchMap.cancel") { dismiss() }', self.sheet)
        self.assertLess(self.sheet.index('try dateDraft.applying(to: draft)'), self.sheet.index('apply(applied)'))
        self.assertIn('var result = filter', self.helper)
        self.assertIn('try result.validate()', self.helper)
        self.assertNotIn('Date()', self.helper.split('public func applying(', 1)[1])

    def test_reset_manual_entry_and_validation_are_preserved(self):
        self.assertIn('dateDraft = SearchMapDateFilterDraft(filter: draft)', self.sheet)
        for identifier in ['searchMap.filter.start', 'searchMap.filter.end', 'searchMap.filter.invalid',
                           'searchMap.filter.cancel', 'searchMap.filter.apply', 'searchMap.filter.reset']:
            self.assertIn(identifier, self.sheet)
        self.assertIn('trimmingCharacters(in: .whitespacesAndNewlines)', self.helper)

    def test_copy_is_bilingual_and_explains_fixed_source_day_filtering(self):
        fragment = json.loads((ROOT / 'Resources/SearchMapDatePresetLocalizations.fragment.json').read_text())
        self.assertEqual(set(fragment), set(re.findall(r'"(mapDatePreset\.[A-Za-z]+)"', self.sheet)))
        for value in fragment.values():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
            self.assertTrue(all(x['stringUnit']['value'] for x in value['localizations'].values()))
        self.assertIn('supplied start day', fragment['mapDatePreset.disclosure']['localizations']['en']['stringUnit']['value'])

    def test_native_and_source_semantics_remain_inclusive_start_day_prefix(self):
        contracts = (ROOT / 'Core/SearchMapContracts.swift').read_text()
        service = (ROOT / 'Core/SearchMapService.swift').read_text()
        for text in ['String(value.prefix(10))', 'day < start', 'day > end', 'if let day = Self.day(date)']:
            self.assertIn(text, contracts)
        self.assertIn('query.filter.matches(kind: .activity, date: $0.startDate', service)
        self.assertIn('Dates/prices are intentionally absent', service)

    def test_authored_core_and_hosted_tests_cover_boundaries_and_shipping_draft(self):
        core = (ROOT / 'Tests/CoreTests/SearchMapDatePresetsTests.swift').read_text()
        hosted = (ROOT / 'Tests/AppUnitTests/SearchMapDatePresetDraftTests.swift').read_text()
        for name in ['testTomorrowCrossesMonthYearAndLeapBoundaries', 'testTomorrowAcrossSpringDSTDoesNotSkipTheLocalDay',
                     'testTomorrowAcrossAutumnDSTDoesNotRepeatTheLocalDay', 'testSameInstantUsesEachPhoneZoneRatherThanADeadlineZone',
                     'testAppliedDateMatchesSourceStartDayPrefixWithoutInstantConversion']:
            self.assertIn(name, core)
        for name in ['testCancelDiscardsShippingDraftWithoutChangingAppliedQuery',
                     'testApplyReopenAndRepeatedReadsKeepConcreteDayUntilAnotherTap',
                     'testAppliedPresetParticipatesInExistingRefreshQueryScopeAndAreaFence']:
            self.assertIn(name, hosted)
        self.assertIn('@testable import Questify', hosted)

    def test_no_new_network_location_storage_or_clock_observer(self):
        for text in ['URLSession', 'CLLocationManager', 'MKDirections', 'UserDefaults', '.onReceive',
                     'NotificationCenter', 'start_date', 'date_type', 'api/', 'Timer']:
            self.assertNotIn(text, self.helper + self.sheet)

    def test_global_copy_names_all_filter_domains_without_claiming_server_or_deadline_behavior(self):
        fragment = json.loads((ROOT / 'Resources/GlobalSearchDatePresetLocalizations.fragment.json').read_text())
        self.assertEqual(set(fragment), {'globalDatePreset.disclosure'})
        self.assertEqual(set(fragment['globalDatePreset.disclosure']['localizations']), {'en', 'zh-Hans'})
        text = fragment['globalDatePreset.disclosure']['localizations']['en']['stringUnit']['value']
        for word in ['phone', 'fixed', 'topics and activities', 'Clubs and shops']:
            self.assertIn(word, text)
        self.assertNotIn('deadline', text)
        main = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        if 'globalDatePreset.disclosure' in main:
            self.assertEqual(fragment['globalDatePreset.disclosure'], main['globalDatePreset.disclosure'])

    def test_existing_global_host_only_searches_at_apply_and_has_no_city_options(self):
        view = (ROOT / 'App/GlobalSearchView.swift').read_text()
        sheet = view.split('.sheet(isPresented: $showsFilters)', 1)[1].split('.task(', 1)[0]
        self.assertIn('applyFilter(next)', sheet)
        self.assertNotIn('applyCityOptions:', sheet)
        select = self.sheet.split('private func selectDatePreset(', 1)[1].split('private func commit()', 1)[0]
        for forbidden in ['Task', 'reader', 'apply(', 'dismiss()', 'URL']:
            self.assertNotIn(forbidden, select)
        self.assertIn('Button("searchMap.cancel") { dismiss() }', self.sheet)

    def test_global_authored_cases_cover_cancel_timezone_rollover_reopen_and_domain_limits(self):
        tests = (ROOT / 'Tests/AppUnitTests/SearchMapDatePresetDraftTests.swift').read_text()
        for name in ['testGlobalPresetCancelKeepsQueryAndAllNonDateFilters',
                     'testGlobalPresetReopenDoesNotMoveAfterRolloverOrTimeZoneChange',
                     'testGlobalDatePresetFiltersOnlyKnownTopicAndActivityStartDays']:
            self.assertIn(name, tests)

if __name__ == '__main__':
    unittest.main()
