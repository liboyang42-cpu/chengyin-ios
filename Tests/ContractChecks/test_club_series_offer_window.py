"""Local source contracts for waitlist input. No Swift formatter/runtime execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


def require_projection(source):
    for token in ['let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)',
                  'if let value = Int(text), (5...1440).contains(value)',
                  'else { minutes = nil }', 'guard let minutes else { return nil }',
                  'formatter.string(from: TimeInterval(minutes * 60))']:
        if token not in source:
            raise AssertionError('Missing exact-minute projection: ' + token)


class ClubSeriesOfferWindowContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'App/ClubSeriesScheduleEditor.swift').read_text().split(
            'struct ClubSeriesOfferWindowPresentation', 1)[1]
        cls.form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        cls.draft = (ROOT / 'Core/ClubGovernanceFormDraft.swift').read_text()
        cls.command = (ROOT / 'Core/ClubGovernanceCommands.swift').read_text()
        cls.tests = (ROOT / 'Tests/AppUnitTests/ClubSeriesScheduleEditorTests.swift').read_text()

    def test_both_normal_series_forms_share_only_the_original_offer_binding(self):
        self.assertIn('if isSeries {\n                    ClubSeriesOfferWindowField(minutes: textBinding("offerMinutes"))', self.form)
        self.assertIn('[.createSeries, .updateSeries].contains(route.operation)', self.form)
        self.assertIn('!ClubSeriesScheduleDraft.fieldKeys.contains(key) && key != "offerMinutes"', self.form)
        self.assertIn('draft.text[key] = $0; dirty = true; review = nil; coordinator.cancelReview()', self.form)
        self.assertIn('}.disabled(busy || locked || review != nil)', self.form)

    def test_same_integer_minute_validation_as_original_command(self):
        require_projection(self.source)
        self.assertIn('"offerMinutes"', self.draft)
        self.assertIn('guard let number = Int(value)', self.draft)
        self.assertIn('(5...1440).contains(result["offerMinutes"]?.int ?? 0)', self.command)
        for token in ['Double(', '.rounded(', '?? 1440', '?? 0']:
            self.assertNotIn(token, self.source)

    def test_mutating_range_parse_or_unknown_guard_is_detected(self):
        for token in ['(5...1440).contains(value)', 'Int(text)', 'guard let minutes else { return nil }']:
            with self.subTest(token=token), self.assertRaises(AssertionError):
                require_projection(self.source.replace(token, '', 1))

    def test_duration_uses_current_locale_and_fixed_day_without_rounding(self):
        for token in ['Calendar(identifier: .gregorian)', 'calendar.locale = locale',
                      'calendar.timeZone = TimeZone(secondsFromGMT: 0)!',
                      'formatter.calendar = calendar', 'formatter.allowedUnits = [.day, .hour, .minute]',
                      'formatter.unitsStyle = .full', 'formatter.maximumUnitCount = 2',
                      'formatter.collapsesLargestUnit = false', 'formatter.allowsFractionalUnits = false',
                      'formatter.zeroFormattingBehavior = .dropAll']:
            self.assertIn(token, self.source)
        self.assertNotIn('Date()', self.source)

    def test_partial_text_stays_original_and_feedback_is_visible(self):
        for token in ['@Binding var minutes: String', 'text: $minutes',
                      '.accessibilityIdentifier("club.gov.input.offerMinutes")',
                      'Text(verbatim: "5–1440")', 'if let duration = presentation.duration(locale: locale)',
                      'Text(verbatim: duration)', 'Text("club.gov.invalid")']:
            self.assertIn(token, self.source)
        self.assertNotIn('minutes =', self.source.split('struct ClubSeriesOfferWindowField', 1)[1])

    def test_existing_catalog_resolves_input_and_feedback_in_both_languages(self):
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in ['club.gov.field.offerMinutes', 'club.gov.invalid']:
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(strings[key]['localizations'][locale]['stringUnit']['value'])

    def test_no_new_service_or_submit_path_in_local_field(self):
        for token in ['Task', 'await', '.send(', '.read(', 'coordinator', 'grant', 'Button(', '.sheet(', '@State']:
            self.assertNotIn(token, self.source)
        self.assertIn('try await coordinator.prepare(draft.command())', self.form)
        self.assertIn('try await coordinator.confirm(review)', self.form)

    def test_authored_native_cases_cover_invalid_input_binding_wire_and_languages(self):
        for name in ['testMinuteBoundsAndHourRemaindersPreserveExactValue',
                     'testEmptyPartialFractionalOverflowAndOutOfRangeHaveNoDuration',
                     'testEnglishDurationUsesDayHoursAndMinutesWithoutRounding',
                     'testChineseDurationUsesDayHoursAndMinutesWithoutRounding',
                     'testFieldBindingRetainsPartialTextAndChangesOnlyOfferDraftIdentity',
                     'testFixingRawInputKeepsWireMinutesAndNeverWritesBackFormatting',
                     'testCreateAndUpdateSubmissionKeepTheAuthoritativeRangeValidation',
                     'testWaitlistOffDoesNotBypassMinuteValidationAndOtherFieldsStayExact']:
            self.assertIn('func ' + name + '(', self.tests)
        self.assertIn('XCTAssertThrowsError(try value.command())', self.tests)
        self.assertIn('XCTAssertEqual(value.anchors, original.anchors)', self.tests)
        self.assertIn('XCTAssertNotEqual(value.requestID, id)', self.tests)


if __name__ == '__main__':
    unittest.main()
