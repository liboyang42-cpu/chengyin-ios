"""Supplementary W05.2 exit-plan source checks; no Swift/runtime acceptance claim."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path):
    return (ROOT / path).read_text()


class MerchantTemplateExitPlanChecks(unittest.TestCase):
    def test_explicit_bounded_local_model_requires_both_instructions(self):
        source = read('Core/MerchantOperationsContracts.swift')
        plan = source.split('public struct MerchantTemplateExitPlan:')[1].split('public struct MerchantNodeTemplate:')[0]
        for token in ['public static let maximumTextLength = 600', 'public var offlineAlternative = ""',
                      'public var failureExit = ""', 'offlineAlternative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty',
                      'failureExit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty',
                      'offlineAlternative.utf16.count > Self.maximumTextLength', 'failureExit.utf16.count > Self.maximumTextLength']:
            self.assertIn(token, plan)
        self.assertNotIn('prefix(', plan)
        self.assertIn('return participationPlan?.blocker ?? exitPlan?.blocker', source)

    def test_server_decoder_and_wire_fields_cannot_import_or_export_local_plan(self):
        model = read('Core/MerchantOperationsContracts.swift').split('public struct MerchantNodeTemplate:')[1].split('public struct MerchantCityNodeRecord:')[0]
        decoder = model.split('private enum CodingKeys:')[1].split('public var blocker:')[0]
        wire = model.split('public var fields:')[1]
        for token in ['exitPlan', 'offlineAlternative', 'failureExit']:
            self.assertNotIn(token, decoder)
            self.assertNotIn(token, wire)
        self.assertIn('public var exitPlan: MerchantTemplateExitPlan?', model)

    def test_each_group_independently_blocks_request_construction(self):
        draft = read('Core/MerchantOperationsDraft.swift')
        self.assertIn('return value.participationPlan != nil || value.exitPlan != nil', draft)
        self.assertIn('guard !localOnlyReview else { throw MerchantOperationsFailure.liveWritesDisabled }', draft)
        service = read('Core/MerchantOperationsService.swift').split('public func save(')[1]
        self.assertLess(service.index('let previews = try draft.previews()'), service.index('transport.send'))
        reader = read('Core/MerchantOperationsReading.swift').split('public func confirm(')[1]
        self.assertLess(reader.index('guard !value.draft.localOnlyReview'), reader.index('try await reader.document'))

    def test_editor_is_in_existing_merchant_template_and_review_uses_frozen_plan(self):
        app = read('App/MerchantOperationsEditor.swift')
        template = app.split('case .template(let value):')[1].split('private var currentTemplate:')[0]
        self.assertIn('MerchantTemplateExitPlanFields(model: model)', template)
        self.assertIn('value.exitPlan = .init(); model.edit(.template(value))', app)
        self.assertIn('plan[keyPath: path] = text; value.exitPlan = plan; model.edit(.template(value))', app)
        self.assertIn('value.exitPlan = nil; model.edit(.template(value))', app)
        self.assertIn('if case .template(let template) = confirmation.draft, let plan = template.exitPlan', app)
        self.assertIn('MerchantTemplateExitPlanReview(plan: plan)', app)
        self.assertIn('confirmation.draft.localOnlyReview || !model.coordinator.reader.canSave', app)

    def test_ai_allowlist_cannot_author_offline_or_exit_instructions(self):
        source = read('Core/MerchantTemplateAssistContracts.swift')
        for token in ['exitPlan', 'offlineAlternative', 'failureExit']:
            self.assertNotIn(token, source)
        app = read('App/MerchantOperationsEditor.swift').split('private struct MerchantTemplateExitPlanFields:')[1]
        for token in ['URLSession', 'UserDefaults', 'send(', 'save(', 'Publish', 'Generate']:
            self.assertNotIn(token, app)

    def test_fragment_covers_keys_and_does_not_promise_runtime_or_persistence(self):
        fragment = json.loads(read('Resources/MerchantTemplateExitPlanLocalizations.fragment.json'))
        keys = set()
        for path in ['Core/MerchantOperationsContracts.swift', 'App/MerchantOperationsEditor.swift']:
            source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', read(path))
            keys.update(re.findall(r'"(merchant\.exitPlan\.[A-Za-z]+)"', source))
        self.assertEqual(set(fragment), keys)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']:
                self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        self.assertIn('No runtime fallback is enabled.', fragment['merchant.exitPlan.reviewBoundary']['localizations']['en']['stringUnit']['value'])
        first = json.loads(read('Resources/MerchantTemplateParticipationPlanLocalizations.fragment.json'))
        self.assertIn('leaving, reloading or discarding removes them', first['merchant.participation.localOnly']['localizations']['en']['stringUnit']['value'])

    def test_authored_tests_cover_validation_independent_groups_and_no_dispatch(self):
        core = read('Tests/CoreTests/MerchantTemplateExitPlanTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 7)
        for token in ['reader.accessCount, readCount', 'reader.saveCount, 0', 'value.participationPlan = nil',
                      'value.exitPlan = nil', 'frozen.exitPlan, plan()', 'coordinator.discardChanges()',
                      'await coordinator.load()', 'reader.switchAccount()', 'String(repeating: "🧭", count: 300)']:
            self.assertIn(token, core)
        ui = read('Tests/AppUITests/MerchantTemplateExitPlanFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 2)
        self.assertIn('XCTAssertFalse(confirm.isEnabled)', ui)
        self.assertIn('XCTAssertEqual(field.value as? String, exit)', ui)


if __name__ == '__main__':
    unittest.main()
