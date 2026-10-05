"""Per-field AI review source contracts, not Apple or provider acceptance."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()


class MerchantTemplateFieldReviewChecks(unittest.TestCase):
    def test_only_one_field_commits_after_fresh_permission_and_final_current_checks(self):
        flow = read('Core/MerchantTemplateAssistFlow.swift')
        change = flow.split('public func change(')[1].split('private func abandon')[0]
        self.assertIn('try await readAccess()', change)
        self.assertIn('stamp == generation, isCurrent, !Task.isCancelled, isConfigured', change)
        self.assertIn('access.allows(coordinator.destination)', change)
        self.assertIn('case .template(let current) = coordinator.draft', change)
        self.assertIn('review.proposedDraft(action, change: change, current: current', change)
        self.assertIn('coordinator.edit(.template(next))', change)
        final = change.split('busy = false', 1)[1].split('} catch', 1)[0]
        self.assertNotIn('await ', final)
        self.assertNotIn('func apply()', flow)
        self.assertNotIn('result.merge(', flow)
        for forbidden in ['.saveExample(', '.saveReviewed(', 'URLSession', 'send(']: self.assertNotIn(forbidden, change)

    def test_original_bytes_and_field_revisions_fence_accept_and_undo(self):
        review = read('Core/MerchantTemplateSuggestionReview.swift')
        for token in ['public let original: String', 'public let proposed: String',
                      'a.utf8.elementsEqual(b.utf8)', 'edits.unchanged(value.field, since: value.expectedEdits)',
                      'exact(value.field.value(in: current), value.original)',
                      'exact(value.field.value(in: current), value.proposed)',
                      'var next = current', 'next[keyPath: path] = replacement']:
            self.assertIn(token, review)
        self.assertIn('!field.value(in: old).utf8.elementsEqual(field.value(in: new).utf8)', read('Core/MerchantTemplateAssistContracts.swift'))
        self.assertIn('value.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', review)

    def test_old_review_actions_and_rejected_fields_cannot_be_reactivated(self):
        review = read('Core/MerchantTemplateSuggestionReview.swift')
        for token in ['guard action.reviewID == id else', '$0.id == action.suggestionID && $0.field == action.field',
                      '$0.revision == action.suggestionRevision', 'suggestions[index].revision = UUID()',
                      'value.state == .pending || value.state == .undone',
                      'suggestions[index].state = .rejected', 'current.id == captured.id']:
            self.assertIn(token, review)
        flow = read('Core/MerchantTemplateAssistFlow.swift')
        self.assertIn('coordinator.draftIdentity == draftIdentity', flow)
        self.assertIn('client?.session == session', flow)
        self.assertIn('visibleReview: MerchantTemplateSuggestionReview? { isCurrent ? review : nil }', flow)

    def test_answer_dependencies_include_every_option_and_ordered_undo(self):
        review = read('Core/MerchantTemplateSuggestionReview.swift')
        self.assertIn('current.method == .quiz', review)
        self.assertIn('fields.allSatisfy { exact($0.value(in: current), result.suggestion($0) ?? "") }', review)
        self.assertIn('$0.field == .correctAnswer && $0.state == .applied', review)
        self.assertIn('exact(current.questionName, question)', review)

    def test_independent_form_buttons_have_real_tap_regression(self):
        panel = read('App/MerchantTemplateSuggestionReviewPanel.swift')
        self.assertEqual(panel.count('.buttonStyle(.borderless)'), 3)
        self.assertIn('let action = review.action(for: suggestion)', panel)
        ui = read('Tests/AppUITests/MerchantTemplateAssistFlowTests.swift')
        for token in ['fieldAction("accept", "title", in: app)', 'fieldAction("undo", "title", in: app)',
                      'fieldAction("reject", "description", in: app)',
                      'XCTAssertFalse(rejectTitle.isEnabled)', 'XCTAssertFalse(acceptDescription.isEnabled)',
                      'fieldState("title", "Applied to the local draft", in: app)',
                      'fieldState("description", "Rejected", in: app)', 'merchant.assist.unsupported']:
            self.assertIn(token, ui)
        self.assertIn('UNMEASURED full-method replacement:360s', ui)
        self.assertIn('UNMEASURED full-method replacement:180s', ui)

    def test_full_decoded_result_is_inspectable_but_unsupported_fields_are_not_mapped(self):
        contracts = read('Core/MerchantTemplateAssistContracts.swift')
        self.assertIn('public let response: ProjectEditJSON', contracts)
        self.assertIn('self.response = response', contracts)
        sheet = read('App/MerchantTemplateAssistSheet.swift')
        self.assertIn('ForEach(result.unsupportedKeys', sheet)
        self.assertIn('encoder.encode(result.response)', sheet)
        self.assertIn('Text(verbatim: decodedResult(result)).textSelection(.enabled)', sheet)
        self.assertNotIn('document.edit(.template', sheet)
        self.assertIn('document.templateAssistChanged()', sheet)

    def test_bilingual_fragment_and_authored_inventory_preserve_existing_coverage(self):
        fragment = json.loads(read('Resources/MerchantTemplateSuggestionReviewLocalizations.fragment.json'))['strings']
        self.assertEqual(len(fragment), 15)
        for value in fragment.values():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'})
            self.assertTrue(all(item['stringUnit']['value'] for item in value['localizations'].values()))
        core = '\n'.join(read('Tests/CoreTests/' + name) for name in ['MerchantTemplateAssistTests.swift', 'MerchantTemplateAssistRuntimeTests.swift', 'MerchantTemplateSuggestionReviewTests.swift', 'MerchantTemplateAssistPermissionLifetimeTests.swift'])
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 42)
        for token in ['testFinalFieldCheckAfterPermissionReadPreservesConcurrentEdits',
                      'testCancelOrIdentityReplacementDuringFieldPermissionReadPreventsCommit',
                      'testCanonicalUnicodeEditStillChangesRevisionAndBlocksUndo',
                      'testChangedUnselectedOptionAlsoBlocksGeneratedAnswer']:
            self.assertIn(token, core)

    def test_flow_owns_permission_task_and_cancel_reaches_real_reader_401_guard(self):
        flow = read('Core/MerchantTemplateAssistFlow.swift')
        for token in ['private var permissionRead: Task<MerchantOperationsAccess, Error>?',
                      'permissionRead = task; permissionReadID = id',
                      'if permissionReadID == id', 'onCancel: { task.cancel() }',
                      'permissionRead?.cancel(); permissionRead = nil; permissionReadID = nil',
                      'generation += 1; cancelPermissionRead(); client?.cancel()']:
            self.assertIn(token, flow)
        tests = read('Tests/CoreTests/MerchantTemplateAssistPermissionLifetimeTests.swift')
        for token in ['MerchantOperationsSessionReader(service: service', 'MerchantOperationsService(configuration:',
                      'withCheckedThrowingContinuation', 'wire.release401()', 'latestSheetTask.cancel()',
                      'XCTAssertFalse(original.isCancelled', 'XCTAssertEqual(expired.count, 0)',
                      'XCTAssertEqual(expired.count, 1)', 'for operation in ["generate", "accept", "undo"]']:
            self.assertIn(token, tests)


if __name__ == '__main__': unittest.main()
