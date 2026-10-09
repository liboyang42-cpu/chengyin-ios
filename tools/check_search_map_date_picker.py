#!/usr/bin/env python3
"""Offline structure/localization and calendar-oracle checks; never Swift execution."""
import argparse
import calendar
import datetime
import hashlib
import json
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--baseline', type=Path, help='Optional unchanged integration snapshot')
    parser.add_argument('--mini-program', type=Path, help='Optional retained searchmap JavaScript evidence')
    args = parser.parse_args()
    root = args.root.resolve()
    checks = []

    def check(name, condition):
        if not condition:
            raise AssertionError(name)
        checks.append(name)

    core = (root / 'Core/SearchMapDatePicker.swift').read_text()
    app = (root / 'App/SearchMapFilterSheet.swift').read_text()
    core_tests = (root / 'Tests/CoreTests/SearchMapDatePickerTests.swift').read_text()
    app_tests = (root / 'Tests/AppUnitTests/SearchMapDatePickerDraftTests.swift').read_text()
    fragment = json.loads((root / 'Resources/SearchMapDatePickerLocalizations.fragment.json').read_text())
    doc = (root / 'docs/search-map-date-picker.md').read_text()
    check('wheel-only year bounds are exactly 1970–2050', 'public static let years = 1970...2050' in core)
    check('selection components cannot be mutated outside clamped setters', all(f'public private(set) var {key}: Int' in core for key in ['year', 'month', 'day']))
    check('phone day uses explicit Gregorian calendar and supplied phone zone',
          'Calendar(identifier: .gregorian)' in core and 'calendar.timeZone = timeZone' in core and 'timeZone: TimeZone = .current' in core)
    check('current then valid start then phone-day fallback',
          'let fallback = field == .end ? Self.components(draft.startDate) : nil' in core and 'let source = current ?? fallback ?? (' in core)
    check('strict ASCII date parsing and Gregorian real-day validation',
          'bytes.count == 10' in core and '(48...57).contains($0.element)' in core and '(1...dayCount(year: parts[0], month: parts[1])).contains(parts[2])' in core)
    check('locale-independent ASCII formatting', 'String(value)' in core and 'String(repeating: "0"' in core and 'DateFormatter' not in core)
    check('year and month changes clamp the retained day', core.count('day = min(day, days.upperBound)') == 2)
    check('full Gregorian leap-year formula', all(value in core for value in ['year.isMultiple(of: 400)', 'year.isMultiple(of: 4)', '!year.isMultiple(of: 100)']))
    check('civil selections never convert through a timestamp', all(value not in core for value in ['calendar.date(from:', 'addingTimeInterval', 'secondsFromGMT', 'ISO8601DateFormatter']))
    check('Confirm compares both directions before assigning a copied draft',
          '(field == .start && value > otherValue) || (field == .end && value < otherValue)' in core and
          core.index('throw APIError.invalidRequest') < core.index('var result = draft'))
    check('nested presentation has a separate local picker draft',
          '@State private var datePicker: SearchMapDatePickerDraft?' in app and '@State private var picker: SearchMapDatePickerDraft' in app and '.sheet(item: $datePicker)' in app)
    check('successful Confirm updates only outer draft',
          'dateDraft = try selection.confirming(in: dateDraft)' in app and 'invalid = false; datePicker = nil' in app)
    nested = app.split('@MainActor private struct SearchMapDatePickerSheet: View {', 1)[1]
    check('picker cancellation dismisses without calling Confirm or Apply',
          'Button("searchMap.cancel") { dismiss() }.accessibilityIdentifier("mapDatePicker.cancel")' in nested and 'apply(' not in nested)
    check('invalid Confirm stays in the picker for correction', 'Button("mapDatePicker.confirm") { invalid = !confirm(picker) }' in nested)
    check('three native wheels have independent stable identifiers', all(f'identifier: "mapDatePicker.{key}"' in nested for key in ['year', 'month', 'day']) and '.pickerStyle(.wheel)' in nested)
    check('accessibility text sizes stack wheels in a scrollable sheet',
          'dynamicTypeSize.isAccessibilitySize' in nested and 'AnyLayout(VStackLayout' in nested and 'ScrollView {' in nested)
    for key in ['start', 'end']:
        check(f'existing {key} manual field retained', f'TextField("searchMap.{key}Date", text: $dateDraft.{key}Date).accessibilityIdentifier("searchMap.filter.{key}")' in app)
        check(f'{key} optional picker button has a minimum target', f'.frame(minHeight: 44).accessibilityIdentifier("mapDatePicker.open.{key}")' in app)
    check('existing today and tomorrow remain available', all(f'selectDatePreset(.{key})' in app for key in ['today', 'tomorrow']))
    check('Apply is still the only applied-query callback', app.count('apply(applied)') == 1 and 'let applied = try dateDraft.applying(to: draft)' in app)
    check('Reset clears only the filter draft and retains keyword',
          'draft = GlobalSearchQuery(keyword: draft.keyword); minimum = ""; maximum = ""; dateDraft = SearchMapDateFilterDraft(filter: draft); invalid = false' in app)
    literal_keys = set(re.findall(r'"(mapDatePicker\.[A-Za-z.]+)"', re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', app)))
    literal_keys -= {'mapDatePicker.year', 'mapDatePicker.month', 'mapDatePicker.day'}
    check('all visible picker keys have fragment entries', literal_keys <= set(fragment))
    check('eight nonempty English and Simplified Chinese entries', len(fragment) == 8 and all(
        set(entry['localizations']) == {'en', 'zh-Hans'} and all(
            entry['localizations'][lang]['stringUnit']['state'] == 'translated' and entry['localizations'][lang]['stringUnit']['value']
            for lang in ['en', 'zh-Hans']) for entry in fragment.values()))
    check('authored domain tests cover boundaries, DST, locale, and ordering', all(key in core_tests for key in [
        'testCurrentFieldWinsAndEndFallsBackToValidStart', 'testYearMonthAndDayChangesClampAtMonthEndAndLeapDay',
        'testPickerYearBoundsClampValidValuesButDoNotRestrictManualApply', 'testDSTFallbackUsesCivilDayWithoutAddingSeconds',
        'testGregorianYearAndASCIIFormattingAreIndependentOfCalendarLocale', 'testConfirmRejectsInversionInEitherDirectionWithoutMutatingDraft',
        'testConcreteDateNeverMovesAcrossPhoneZonesOrSkippedCivilDay']))
    check('authored app-unit tests cover picker and filter lifecycle', all(key in app_tests for key in [
        'testWheelChangesCancelAndReopenLeaveOuterDraftAndAppliedQueryUnchanged',
        'testConfirmChangesOnlyOuterDraftAndFilterCancelDiscardsIt',
        'testApplyCommitsConcreteDateAndPreservesOtherFiltersOnReopen',
        'testResetIsDraftLocalAndReopeningEndPickerUsesStartOrPhoneDay',
        'testPresetsManualFieldsAndRepeatedPickerOpenRemainInteroperable',
        'testFailedConfirmKeepsDraftAndAllowsCorrectionBeforeApply']))
    check('no live provider, location, network, or persistence API added', all(value not in core + nested for value in [
        'CLLocationManager', 'MKDirections', 'URLSession', 'UserDefaults', 'Keychain', 'requestWhenInUseAuthorization']))
    check('manual Apple acceptance and integration instructions are explicit', all(value in doc for value in [
        'NOT_RUN', 'Localizable.xcstrings', 'generate_project.py', 'VoiceOver', 'interactive dismissal', '1970', '2050']))

    # Independent standard-library oracle, NOT execution of the Swift implementation.
    # This checks the Gregorian month-length rule encoded above over its full range.
    for year in range(1970, 2051):
        for month in range(1, 13):
            formula_days = (29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28) if month == 2 else (30 if month in [4, 6, 9, 11] else 31)
            assert formula_days == calendar.monthrange(year, month)[1]
            for day in [1, formula_days]:
                assert datetime.date(year, month, day).isoformat() == f'{year:04d}-{month:02d}-{day:02d}'
    check('independent Gregorian oracle covers 972 months and 1944 boundary dates', True)

    if args.baseline:
        baseline = args.baseline.resolve()
        before = (baseline / 'App/SearchMapFilterSheet.swift').read_text()
        # A precise unchanged suffix covers presets, manual parsing, Apply and Reset's callbacks.
        original_methods = before[before.index('    private func selectDatePreset('):]
        check('preset and commit implementations remain byte-identical', original_methods in app)
        for directory in ['Tests/AppUITests']:
            original = {p.relative_to(baseline): hashlib.sha256(p.read_bytes()).hexdigest() for p in (baseline / directory).rglob('*') if p.is_file()}
            actual = {p.relative_to(root): hashlib.sha256(p.read_bytes()).hexdigest() for p in (root / directory).rglob('*') if p.is_file()}
            check(f'all {directory} files and bytes are unchanged', original == actual)

    if args.mini_program:
        source = args.mini_program.read_text()
        check('retained mini-program has 81 years from 1970', 'Array.from({ length: 81 }, (_, index) => 1970 + index)' in source)
        check('retained mini-program initializes end from valid start', "field === 'enddate' && isDateValue(this.data.startdate)" in source)
        check('retained mini-program clamps day when wheel month/year changes', 'Math.min(value[2], days.length - 1)' in source)
        check('retained mini-program Cancel and Confirm are separate', 'cancelDatePicker()' in source and 'confirmDatePicker()' in source)
        check('retained mini-program rejects inverted start and end', 'selected > this.data.enddate' in source and 'selected < this.data.startdate' in source)
    print(f'PASS {len(checks)} offline structure/localization/calendar-oracle checks')
    for name in checks:
        print(' - ' + name)
    print('Swift Core tests, app-unit execution, Apple compilation, XCUITest, VoiceOver, visual/device acceptance: NOT_RUN')
    print('Calendar oracle checks the specification only; it is not Swift runtime evidence.')


if __name__ == '__main__':
    main()
