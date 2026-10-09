"""Focused picker wiring/civil-time checks, not Swift or UI runtime evidence."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantStationServiceTimeContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_existing_ready_fields_and_final_contract_are_reused(self):
        source = self.read('App/MerchantContentEditor.swift')
        self.assertIn('field("capacity"); field("serviceStartAt"); field("serviceEndAt"); field("note")', source)
        self.assertIn('MerchantStationServiceTimeFields(context:', source)
        self.assertIn('"serviceStartAt": .string(value("serviceStartAt")), "serviceEndAt": .string(value("serviceEndAt"))', source)
        self.assertIn('try result.validate(against: s)', source)
        core = self.read('Core/MerchantStationServiceWindow.swift')
        self.assertIn('MerchantStationCommand.validTime(start)', core)
        self.assertIn('MerchantStationCommand.validTime(day + " 00:00")', core)
        self.assertIn('startMinutes < endMinutes', core)
        self.assertIn('MerchantStoreHours.clock(startMinutes)', core)

    def test_apply_is_atomic_and_bound_to_current_snapshot_and_original_pair(self):
        source = self.read('App/MerchantContentEditor.swift')
        block = source.split('MerchantStationServiceTimeFields(context:', 1)[1].split('}.id(snapshot.observedAt)', 1)[0]
        write = block.index('text["serviceStartAt"] = pair.start')
        for token in ['c.isCurrent', '!c.busy', '!c.locked', 'c.review == nil', 'c.snapshot == snapshot',
                      'c.snapshot?.observedAt == snapshot.observedAt',
                      '(text["serviceStartAt"] ?? "") == originalStart', '(text["serviceEndAt"] ?? "") == originalEnd',
                      'let pair = try? window.wireValues()']:
            self.assertLess(block.index(token), write)
        self.assertIn('if pair.start == originalStart && pair.end == originalEnd { return true }', block)
        self.assertIn('text["serviceStartAt"] = pair.start; text["serviceEndAt"] = pair.end', block)
        self.assertIn('dirty = true; model.cancel(); return true', block)
        self.assertNotIn('await', block)

    def test_cancel_open_and_picker_edits_do_not_write_parent_values(self):
        source = self.read('App/MerchantStationServiceTimeFields.swift')
        opening = source.split('Button("merchant.stationTime.choose"', 1)[1].split('.disabled(!canEdit)', 1)[0]
        self.assertNotIn('apply(', opening)
        self.assertIn('cancel: { editor = nil }', source)
        self.assertIn('Button("action.cancel", action: cancel)', source)
        self.assertIn('stale = !apply(draft)', source)
        self.assertIn('guard canEdit, context == captured.context, start == captured.start, end == captured.end', source)
        self.assertIn('.onChange(of: context) { _, _ in editor = nil }', source)
        self.assertIn('.onDisappear { editor = nil }', source)

    def test_explicit_calendar_carrier_prevents_default_timezone_date_shift(self):
        source = self.read('App/MerchantStationServiceTimeFields.swift')
        self.assertIn('.environment(\\.calendar, MerchantStationServiceWindow.pickerCalendar)', source)
        self.assertIn('.environment(\\.timeZone, MerchantStationServiceWindow.pickerCalendar.timeZone)', source)
        core = self.read('Core/MerchantStationServiceWindow.swift')
        self.assertIn('calendar.timeZone = TimeZone(secondsFromGMT: 0)!', core)
        self.assertIn('Self.pickerCalendar.dateComponents([.year, .month, .day], from: value)', core)
        self.assertNotIn('DateFormatter', core)
        self.assertNotIn('addingTimeInterval', core)

    def test_five_minute_choices_never_round_existing_minutes_on_open(self):
        core = self.read('Core/MerchantStationServiceWindow.swift')
        self.assertIn('startMinutes: Int = 0, endMinutes: Int = 0', core)
        self.assertIn('Array(stride(from: 0, to: 60, by: 5))', core)
        self.assertIn('choices.append(minute); choices.sort()', core)
        self.assertNotIn('round(', core)
        self.assertNotIn('rounded(', core)
        self.assertIn('startMinutes: minutes(start), endMinutes: minutes(end)', core)

    def test_only_local_ui_no_new_io_or_submission(self):
        source = self.read('App/MerchantStationServiceTimeFields.swift')
        for forbidden in ['URLSession', 'UserDefaults', 'FileManager', 'model.confirm', 'perform(', 'request(', 'Task {', 'calendarRequest']:
            self.assertNotIn(forbidden, source)
        self.assertIn('.disabled(!draft.isValid)', source)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', source)

    def test_unique_bilingual_keys_and_authored_legacy_cases(self):
        fragment = json.loads(self.read('Resources/MerchantStationServiceTimeLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 10)
        for value in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][language]['stringUnit']['value'].strip())
        tests = self.read('Tests/CoreTests/MerchantStationServiceWindowTests.swift')
        for name in ['testExistingNonFiveMinuteValuesArePreservedUntilExplicitEdit',
                     'testOpeningOrCancellingAnIndependentDraftCannotChangeOriginalStrings',
                     'testCalendarCarrierNeverShiftsExistingCivilDateOrTimes',
                     'testSameOrEarlierEndCannotBeApplied',
                     'testExistingReadyWireContractStillAcceptsLegacyCrossDayValues',
                     'testMissingTimesBeginAtSourceZeroPairAndRequireAnExplicitEdit']:
            self.assertIn('func ' + name, tests)

if __name__ == '__main__': unittest.main()
