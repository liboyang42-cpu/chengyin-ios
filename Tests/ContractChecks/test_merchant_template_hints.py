"""Source-level checks only; Swift and simulator tests require an Apple toolchain."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplateHintsChecks(unittest.TestCase):
    def test_three_exact_optional_fields_decode_strictly_and_no_enabled_flag_is_sent(self):
        source = read('Core/MerchantOperationsContracts.swift')
        for key in ['hint1', 'hint2', 'answerReveal']:
            self.assertIn('try c.decodeIfPresent(String.self, forKey: .' + key + ')', source)
        self.assertIn('for (key, value) in hints.fields { fields[key] = value }', source)
        self.assertNotIn('fields["hintEnabled"]', source)
        self.assertNotIn('fields["hints"]', source)

    def test_explicit_empty_updates_and_untouched_source_have_distinct_semantics(self):
        group = read('Core/MerchantOperationsContracts.swift').split('public struct MerchantTemplateHints:')[1].split('public struct MerchantNodeTemplate:')[0]
        for token in ['guard isEdited else { return sourceFields }', 'enabled ? text($0) : ""',
                      'if !value { for field in Field.allCases { values[field] = "" } }',
                      'public var clearedFields:', 'fields[$0.rawValue] == ""']:
            self.assertIn(token, group)
        self.assertNotIn('prefix(', group)

    def test_method_compatibility_matches_mini_and_requires_explicit_clear(self):
        group = read('Core/MerchantOperationsContracts.swift').split('public struct MerchantTemplateHints:')[1].split('public struct MerchantNodeTemplate:')[0]
        self.assertIn('method == .secretWord || method == .quiz || method == .gps', group)
        self.assertIn('enabled && !Self.supports(method) && (isEdited || method != sourceMethod)', group)
        self.assertIn('if let blocker = hints.blocker(method: method) { return blocker }', read('Core/MerchantOperationsContracts.swift'))
        app = read('App/MerchantOperationsEditor.swift')
        self.assertIn('.disabled(!MerchantTemplateHints.supports(value.method) && !value.hints.enabled)', app)
        self.assertIn('.disabled(!MerchantTemplateHints.supports(value.method))', app)

    def test_editor_preview_and_frozen_review_complete_the_group(self):
        app = read('App/MerchantOperationsEditor.swift')
        for token in ['MerchantTemplateHintsFields(model: model)', 'action(&value.hints); model.edit(.template(value))',
                      '$0.setEnabled(enabled)', '$0.update(field, text: text)',
                      'MerchantTemplateHintsPreview(hints: value.hints).id(model.coordinator.draftIdentity)',
                      'MerchantTemplateHintsReview(hints: template.hints)', 'hints.clearedFields.contains(field)']:
            self.assertIn(token, app)
        preview = app.split('private struct MerchantTemplateHintsPreview:')[1].split('private struct MerchantTemplateHintsReview:')[0]
        for token in ['@State private var revealed = 0', '.prefix(revealed)', '.onChange(of: hints) { _, _ in revealed = 0 }', '== .answerReveal']:
            self.assertIn(token, preview)
        for token in ['model.edit', 'save(', 'URLSession', 'complete(', 'reward(']: self.assertNotIn(token, preview)

    def test_fixture_readback_reconstructs_source_state_after_ack(self):
        fixture = read('Core/MerchantOperationsSyntheticFixtures.swift')
        for token in ['let hintFields = draft.hints.fields', 'returned.hints = .init(', 'method: returned.method']:
            self.assertIn(token, fixture)
        for field in ['hint1', 'hint2', 'answerReveal']:
            self.assertIn('hintFields["' + field + '"] ?? baseline.hints.fields["' + field + '"]', fixture)
        reader = read('Core/MerchantOperationsReading.swift')
        self.assertIn('baseline = .template(returned); draft = .template(returned)', reader)
        self.assertIn('guard reader.canSave', reader)

    def test_ai_allowlist_and_local_planning_write_block_remain_unchanged(self):
        fields = read('Core/MerchantTemplateAssistContracts.swift').split('public enum MerchantTemplateAssistField:')[1].split('public struct MerchantTemplateAssistEdits:')[0]
        for token in ['hint1', 'hint2', 'answerReveal']: self.assertNotIn(token, fields)
        self.assertIn('guard !localOnlyReview else { throw MerchantOperationsFailure.liveWritesDisabled }', read('Core/MerchantOperationsDraft.swift'))

    def test_localization_covers_dynamic_fields_and_says_preview_has_no_runtime_authority(self):
        fragment = json.loads(read('Resources/MerchantTemplateHintsLocalizations.fragment.json'))
        source = read('Core/MerchantOperationsContracts.swift') + read('App/MerchantOperationsEditor.swift')
        source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', source)
        keys = set(re.findall(r'"(merchant\.hints\.[A-Za-z]+)"', source)) | {'merchant.hints.hint1', 'merchant.hints.hint2', 'merchant.hints.answerReveal'}
        self.assertEqual(set(fragment), keys); self.assertEqual(len(fragment), 18)
        for value in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(value['localizations'][locale]['stringUnit']['value'])
        boundary = fragment['merchant.hints.previewBoundary']['localizations']['en']['stringUnit']['value']
        self.assertIn('does not unlock hints', boundary); self.assertIn('grant rewards', boundary)

    def test_authored_core_tests_cover_clear_partial_clear_scope_conflict_and_real_adapter(self):
        core = read('Tests/CoreTests/MerchantTemplateHintsTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 19)
        for token in ['HintTransport: HTTPTransport', 'reader.switchAccount()', 'coordinator.cancelConfirmation()',
                      'coordinator.discardChanges()', 'hints.clearedFields, [.hint2]', 'XCTAssertEqual(saves.count, 1)',
                      'source.hints.fields, canonical', '"/prod-api/api/template/myinfo"', 'exerciseSave(disable: true)',
                      'XCTAssertTrue(transport.requests.isEmpty)', 'Changed elsewhere']:
            self.assertIn(token, core)

    def test_authored_ui_tests_cover_sequence_reset_cancel_disable_discard_and_method_change(self):
        ui = read('Tests/AppUITests/MerchantTemplateHintsFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 3)
        for token in ['merchant.hints.preview.answerReveal', 'merchant.hints.preview.restart', 'merchant.hints.review.clear.',
                      'Keep editing', 'Discard and reload', 'app.buttons["Photo"].tap()', 'XCTAssertFalse(review.isEnabled)']:
            self.assertIn(token, ui)


if __name__ == '__main__': unittest.main()
