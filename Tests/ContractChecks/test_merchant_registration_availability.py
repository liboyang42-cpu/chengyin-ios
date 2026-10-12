"""Source checks only. Native XCTest/UI/typechecking are separate, unexecuted stages."""
import json
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()

class MerchantRegistrationAvailabilityChecks(unittest.TestCase):
    def test_existing_update_only_gets_optional_group(self):
        commands = read('Core/MerchantContentCommands.swift')
        update = commands.split('case .updateRegistration(let id, let topic, let draft):')[1].split('case .cancelRegistration')[0]
        self.assertIn('draft.fieldsIncludingAvailability()', update)
        self.assertIn('"api/registration/merchant/update"', update)
        create = commands.split('case .register(let topic, let node, let draft, let time):')[1].split('case .updateRegistration')[0]
        self.assertIn('draft.fields()', create); self.assertNotIn('fieldsIncludingAvailability', create)
        self.assertIn('availabilityReplacement: MerchantRegistrationAvailability? = nil', read('Core/MerchantContentDomain.swift'))

    def test_wire_dates_and_hours_match_source_without_instant_conversion(self):
        core = read('Core/MerchantRegistrationAvailability.swift')
        for text in ['startDay + " 00:00:00"', 'endDay + " 23:59:59"', '"cooperateDate": .string(dailyTime)', 'startDay <= endDay', 'startMinutes < endMinutes']:
            self.assertIn(text, core)
        for text in ['ISO8601DateFormatter', 'timeIntervalSince1970', '.addingTimeInterval', 'DateFormatter']:
            self.assertNotIn(text, core)

    def test_untouched_source_is_not_serialized_and_group_is_atomic(self):
        source = read('Core/MerchantRegistrationAvailability.swift')
        self.assertIn('if let availabilityReplacement { result.merge(try availabilityReplacement.fields())', source)
        self.assertIn('guard isValid else { throw MerchantContentFailure.invalid }', source)
        self.assertIn('if raw.count == 10', source); self.assertIn('raw.count == 19, raw.hasSuffix(suffix)', source)
        self.assertNotIn('String(raw.prefix(10))', source.split('public struct MerchantRegistrationAvailabilitySource')[1])

    def test_editor_only_mounts_for_existing_registration_and_guards_apply(self):
        editor = read('App/MerchantContentEditor.swift')
        section = editor.split('if case .registrationEdit(let id) = kind {')[1].split('case .chapterNode:')[0]
        for text in ['MerchantRegistrationAvailabilityPicker', 'c.snapshot == s', 'c.snapshot?.observedAt == s.observedAt', 'c.receipt == nil', 'availabilityReplacement = replacement']:
            self.assertIn(text, section)
        self.assertIn('if case .registrationEdit = kind { draft.availabilityReplacement = availabilityReplacement }', editor)

    def test_calendar_buffer_cancel_restore_and_unknown_source_proposal(self):
        app = read('App/MerchantRegistrationAvailabilityPicker.swift')
        for text in ['@State private var draft:', 'cancel: { editor = nil }', 'merchant.registrationAvailability.restore', 'apply(nil)',
                     'MerchantRegistrationAvailability(source: captured.source) == nil', 'merchant.registrationAvailability.proposal',
                     'let next = value == MerchantRegistrationAvailability(source: source) ? nil : value']:
            self.assertIn(text, app)
        self.assertNotIn('service.perform', app)

    def test_stale_sheet_account_background_and_original_fields_are_fenced(self):
        app = read('App/MerchantRegistrationAvailabilityPicker.swift')
        for text in ['context == captured.context', 'source == captured.source', 'replacement == captured.replacement', 'scenePhase == .active',
                     '.onChange(of: context)', '.onChange(of: source)', '.onChange(of: replacement)', '.onChange(of: canEdit)',
                     '.onChange(of: scenePhase)']:
            self.assertIn(text, app)
        editor = read('App/MerchantContentEditor.swift')
        self.assertIn('@State private var availabilityEditor: MerchantRegistrationAvailabilityPicker.Session?', editor)
        self.assertIn('.modifier(MerchantRegistrationAvailabilityPresentation(editor: $availabilityEditor,', editor)
        picker = app.split('struct MerchantRegistrationAvailabilityPicker:')[1].split('struct MerchantRegistrationAvailabilityPresentation:')[0]
        self.assertNotIn('.sheet(', picker)
        self.assertNotIn('.onDisappear', picker)
        self.assertNotIn('@State private var editor', picker)
        presentation = app.split('struct MerchantRegistrationAvailabilityPresentation:')[1].split('private struct MerchantRegistrationAvailabilitySourceRows:')[0]
        self.assertIn('.sheet(item: $editor)', presentation)

    def test_calendar_carrier_and_off_step_minutes_are_preserved(self):
        app = read('App/MerchantRegistrationAvailabilityPicker.swift')
        for text in ['displayedComponents: .date', 'MerchantStationServiceWindow.pickerCalendar', 'MerchantStationServiceWindow.minuteChoices(preserving: total % 60)', 'draft.selectDay']:
            self.assertIn(text, app)
        self.assertNotIn('Calendar.current', read('Core/MerchantRegistrationAvailability.swift'))

    def test_frozen_human_review_shows_before_and_after(self):
        views = read('App/MerchantContentViews.swift')
        self.assertIn('MerchantRegistrationAvailabilityReview(source: .init(review.baseline.value), replacement: availability)', views)
        app = read('App/MerchantRegistrationAvailabilityPicker.swift').split('struct MerchantRegistrationAvailabilityReview:')[1].split('@MainActor private struct')[0]
        for text in ['MerchantRegistrationAvailabilitySourceRows(source: source)', 'MerchantRegistrationAvailabilityValues(value: replacement)', 'merchant.registrationAvailability.reviewHint']:
            self.assertIn(text, app)

    def test_only_acknowledged_new_update_gets_authoritative_readback(self):
        core = read('Core/MerchantContentCoordinator.swift')
        self.assertLess(core.index('receipt = value'), core.index('if frozen.command.registrationAvailability != nil'))
        section = core.split('if frozen.command.registrationAvailability != nil {')[1].split('\n        } catch {')[0]
        for text in ['snapshot = nil', 'service.load(query)', 'returned.query == query, returned.scope == frozen.scope',
                     'returned.access.merchantID == frozen.baseline.access.merchantID', 'snapshot = returned', 'readbackFailed']:
            self.assertIn(text, section)
        self.assertNotIn('perform(', section); self.assertNotIn('receipt = nil', section); self.assertNotIn('snapshot = frozen.baseline', section)

    def test_failed_readback_recovery_is_read_only_and_success_reseeds_draft(self):
        editor = read('App/MerchantContentEditor.swift')
        self.assertIn('availabilityReplacement != nil, c.receipt != nil, c.snapshot == nil, !c.busy', editor)
        section = editor.split('Button("merchant.registrationAvailability.retryReadback")')[1].split('.accessibilityIdentifier')[0]
        self.assertIn('await model.load()', section); self.assertNotIn('confirm', section); self.assertNotIn('perform', section)
        self.assertIn('text = [:]; availabilityReplacement = nil; seed(s)', editor)

    def test_fixture_stores_new_dates_locally_without_a_new_endpoint(self):
        fixture = read('Core/MerchantContentSyntheticFixtures.swift')
        for text in ['private var updatedRegistration:', 'path == "/api/registration/merchant/update"', '["startDate", "endDate", "cooperateDate"]', 'if let updatedRegistration']:
            self.assertIn(text, fixture)
        self.assertNotIn('URLSession', fixture.split('public final class MerchantContentFixtureTransport')[1])

    def test_new_localizations_are_complete_and_bilingual(self):
        src = read('App/MerchantRegistrationAvailabilityPicker.swift') + read('App/MerchantContentEditor.swift') + read('Core/MerchantContentCoordinator.swift')
        src = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', src)
        keys = set(re.findall(r'"(merchant\.registrationAvailability\.[A-Za-z]+)"', src))
        fragment = json.loads(read('Resources/MerchantRegistrationAvailabilityLocalizations.fragment.json'))
        self.assertEqual(keys, set(fragment)); self.assertEqual(len(fragment), 27)
        for value in fragment.values():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
            for unit in value['localizations'].values(): self.assertTrue(unit['stringUnit']['value'])

    def test_native_test_scope_and_source_boundary_are_recorded(self):
        core = read('Tests/CoreTests/MerchantRegistrationAvailabilityTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+', core)), 22)
        self.assertEqual(len(re.findall(r'func test\w+', read('Tests/AppUITests/MerchantRegistrationAvailabilityFlowTests.swift'))), 3)
        doc = read('docs/merchant-registration-availability.md')
        for text in ['NOT RUN', 'no `swift` or `xcodebuild`', 'status0/2', 'injectedOfflineHarness']:
            self.assertIn(text, doc)

if __name__ == '__main__': unittest.main()
