"""Supplementary source contracts only; not Swift compilation or UI execution."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()


class MerchantTemplateParticipationPlanChecks(unittest.TestCase):
    def test_group_is_explicit_local_opt_in_without_server_decode(self):
        source = read('Core/MerchantOperationsContracts.swift')
        model = source.split('public struct MerchantNodeTemplate:')[1].split('public struct MerchantCityNodeRecord:')[0]
        self.assertIn('public var participationPlan: MerchantTemplateParticipationPlan?', model)
        decoder = model.split('public init(from decoder:')[1].split('public var blocker:')[0]
        self.assertNotIn('participationPlan', decoder)
        self.assertIn('return participationPlan?.blocker', model)
        self.assertIn('case unspecified, selfGuided, staffRequired', source)
        self.assertIn('public var staffing: Staffing = .unspecified', source)

    def test_numbers_have_exact_positive_integer_validation(self):
        source = read('Core/MerchantOperationsContracts.swift')
        group = source.split('public struct MerchantTemplateParticipationPlan:')[1].split('public struct MerchantNodeTemplate:')[0]
        for token in ['value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })', 'let number = Int(value), number > 0',
                      'Self.positiveInteger(durationMinutes)', 'Self.positiveInteger(maximumParticipants)', 'staffing == .unspecified']:
            self.assertIn(token, group)
        self.assertNotIn('Double(', group)

    def test_wire_payload_keeps_local_plan_out_and_preview_rejects_it(self):
        source = read('Core/MerchantOperationsContracts.swift')
        wire = source.split('public struct MerchantNodeTemplate:')[1].split('public var fields:')[1].split('public struct MerchantCityNodeRecord:')[0]
        for token in ['participationPlan', 'durationMinutes', 'maximumParticipants', 'staffing']:
            self.assertNotIn(token, wire)
        draft = read('Core/MerchantOperationsDraft.swift')
        preview = draft.split('public func previews()')[1].split('public struct MerchantOperationsRequestPreview')[0]
        self.assertIn('guard !localOnlyReview else { throw MerchantOperationsFailure.liveWritesDisabled }', preview)
        self.assertLess(preview.index('guard !localOnlyReview'), preview.index('switch self'))
        self.assertEqual(preview.count('api/merchant/city-node/template/submit'), 1)

    def test_review_can_freeze_but_confirm_stops_before_any_read_or_write(self):
        source = read('Core/MerchantOperationsReading.swift')
        prepare = source.split('public func prepare()')[1].split('public func confirm(')[0]
        self.assertIn('if !draft.localOnlyReview { _ = try draft.previews() }', prepare)
        self.assertIn('draft: draft, baseline: baseline, scope: loadedScope', prepare)
        confirm = source.split('public func confirm(')[1].split('public extension MerchantOperationsReading')[0]
        self.assertIn('guard !value.draft.localOnlyReview else', confirm)
        self.assertLess(confirm.index('guard !value.draft.localOnlyReview'), confirm.index('try await reader.document'))
        self.assertLess(confirm.index('guard !value.draft.localOnlyReview'), confirm.index('try await reader.saveReviewed'))
        service = read('Core/MerchantOperationsService.swift').split('let previews = try draft.previews()', 1)[1]
        self.assertIn('let access = try await access(token: token)', service)

    def test_existing_merchant_editor_and_frozen_review_mount_the_group(self):
        app = read('App/MerchantOperationsEditor.swift')
        self.assertIn('MerchantTemplateParticipationPlanFields(model: model)', app)
        self.assertIn('confirmation.draft.localOnlyReview || !model.coordinator.reader.canSave', app)
        self.assertIn('let plan = template.participationPlan', app)
        self.assertIn('MerchantTemplateParticipationPlanReview(plan: plan)', app)
        self.assertIn('value.participationPlan = .init(); model.edit(.template(value))', app)
        self.assertIn('value.participationPlan = nil; model.edit(.template(value))', app)
        self.assertIn('edit(&plan); value.participationPlan = plan; model.edit(.template(value))', app)

    def test_ai_field_allowlist_never_accepts_participation_facts(self):
        source = read('Core/MerchantTemplateAssistContracts.swift')
        fields = source.split('public enum MerchantTemplateAssistField:')[1].split('public struct MerchantTemplateAssistEdits:')[0]
        for token in ['participationPlan', 'durationMinutes', 'maximumParticipants', 'staffing']:
            self.assertNotIn(token, fields)

    def test_fragment_covers_all_static_and_dynamic_bilingual_keys(self):
        fragment = json.loads(read('Resources/MerchantTemplateParticipationPlanLocalizations.fragment.json'))
        referenced = set()
        for path in ['App/MerchantOperationsEditor.swift', 'Core/MerchantOperationsContracts.swift', 'Core/MerchantOperationsReading.swift']:
            source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', read(path))
            referenced.update(re.findall(r'"(merchant\.participation\.[A-Za-z]+)"', source))
        referenced.update('merchant.participation.staffing.' + suffix for suffix in ['unspecified', 'selfGuided', 'staffRequired'])
        self.assertEqual(set(fragment), referenced)
        for key, value in fragment.items():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][locale]['stringUnit']['value'], (key, locale))
        self.assertIn('editing session only', fragment['merchant.participation.localOnly']['localizations']['en']['stringUnit']['value'])
        self.assertIn('不能提交', fragment['merchant.participation.localOnly']['localizations']['zh-Hans']['stringUnit']['value'])

    def test_authored_swift_and_ui_regressions_cover_lifecycle_and_no_sends(self):
        core = read('Tests/CoreTests/MerchantTemplateParticipationPlanTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 8)
        for token in ['reader.saveCount, 0', 'reader.accessCount, accessReads', 'coordinator.discardChanges()',
                      'reader.switchAccount()', 'coordinator.leaveScreen()', 'coordinator.cancelConfirmation()',
                      'snapshot.participationPlan?.durationMinutes, "15"', 'XCTAssertThrowsError']:
            self.assertIn(token, core)
        ui = read('Tests/AppUITests/MerchantTemplateParticipationPlanFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 2)
        self.assertIn('XCTAssertFalse(confirm.isEnabled)', ui)
        self.assertIn('XCTAssertEqual(field.value as? String, "15")', ui)


if __name__ == '__main__':
    unittest.main()
