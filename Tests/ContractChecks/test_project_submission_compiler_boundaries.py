"""Source-only compiler boundaries; these checks do not compile or execute SwiftUI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProjectSubmissionCompilerBoundaries(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/ProjectEditView.swift').read_text()

    def parts(self):
        body, rest = self.source.split('    private func submissionBinding(', 1)
        binding, rest = rest.split('    @ViewBuilder private func submissionResult(', 1)
        result = rest.split('    private func chapterStructure(', 1)[0]
        return body, binding, result

    def test_render_captures_feed_explicit_typed_boundaries(self):
        body, binding, result = self.parts()
        for token in ['let presentedSubmission = submission',
                      'let submissionIncarnation = model.editorIncarnation',
                      '.sheet(item: submissionBinding(presentedSubmission: presentedSubmission, submissionIncarnation: submissionIncarnation)) { receipt in',
                      'submissionResult(receipt: receipt, submissionIncarnation: submissionIncarnation)']:
            self.assertIn(token, body)
        self.assertIn('presentedSubmission: PublishingSubmissionHandoff?, submissionIncarnation: UUID) -> Binding<PublishingSubmissionHandoff?>', binding)
        self.assertIn('Binding<PublishingSubmissionHandoff?>(get: { () -> PublishingSubmissionHandoff? in', binding)
        self.assertIn('}, set: { (next: PublishingSubmissionHandoff?) in', binding)
        self.assertIn('receipt: PublishingSubmissionHandoff, submissionIncarnation: UUID) -> some View', result)
        self.assertNotIn('PublishingSubmissionResultSheet(', body)
        for forbidden in ['captureStarterLease()', 'let submissionIncarnation =', 'let presentedSubmission = submission',
                          'AnyView', '@State', 'StateObject', '.onAppear', '.task']:
            self.assertNotIn(forbidden, binding + result)

    def test_binding_preserves_original_getter_and_old_dismissal_fences(self):
        _, binding, _ = self.parts()
        self.assertIn('guard let original = presentedSubmission, model.submissionIsCurrent(original, incarnation: submissionIncarnation), submission?.id == original.id else { return nil }\n            return submission', binding)
        self.assertIn('guard model.editorIncarnation == submissionIncarnation, next == nil, let presentedSubmission, submission?.id == presentedSubmission.id else { return }; submission = nil', binding)
        self.assertEqual(binding.count('submission = nil'), 1)
        self.assertNotIn('submission = next', binding)

    def test_result_preserves_render_and_navigation_guards(self):
        _, _, result = self.parts()
        for token in ['if model.submissionIsCurrent(receipt, incarnation: submissionIncarnation) {',
                      'PublishingSubmissionResultSheet(receipt: receipt, canNavigate: publisherHost != nil, canVerifyRelease: model.approvedReleaseReadIsConfigured)',
                      'guard model.submissionIsCurrent(receipt, incarnation: submissionIncarnation), submission?.id == receipt.id else { return }',
                      'submission = nil\n                if publisherHost != nil { submittedResource = receipt.resource }']:
            self.assertIn(token, result)
        self.assertEqual(result.count('submission = nil'), 1)
        self.assertEqual(result.count('submittedResource ='), 1)

    def test_source_checks_reject_weakened_boundaries_and_stale_callbacks(self):
        mutations = [
            ('Binding<PublishingSubmissionHandoff?>(get:', 'Binding(get:'),
            ('{ () -> PublishingSubmissionHandoff? in', '{'),
            ('{ (next: PublishingSubmissionHandoff?) in', '{ next in'),
            ('submissionBinding(presentedSubmission: presentedSubmission, submissionIncarnation: submissionIncarnation)', 'submissionBinding(presentedSubmission: submission, submissionIncarnation: model.editorIncarnation)'),
            ('model.submissionIsCurrent(original, incarnation: submissionIncarnation), ', ''),
            ('submission?.id == original.id', 'true'),
            ('return submission\n', 'return original\n'),
            ('model.editorIncarnation == submissionIncarnation, ', ''),
            ('next == nil, ', ''),
            ('let presentedSubmission, submission?.id == presentedSubmission.id', 'true'),
            ('submission?.id == presentedSubmission.id', 'true'),
            ('if model.submissionIsCurrent(receipt, incarnation: submissionIncarnation) {', 'if true {'),
            ('guard model.submissionIsCurrent(receipt, incarnation: submissionIncarnation), submission?.id == receipt.id', 'guard submission?.id == receipt.id'),
            ('submission?.id == receipt.id', 'true'),
            ('canNavigate: publisherHost != nil', 'canNavigate: true'),
            ('canVerifyRelease: model.approvedReleaseReadIsConfigured', 'canVerifyRelease: true'),
            ('if publisherHost != nil { submittedResource = receipt.resource }', 'submittedResource = receipt.resource'),
        ]
        methods = ['test_render_captures_feed_explicit_typed_boundaries',
                   'test_binding_preserves_original_getter_and_old_dismissal_fences',
                   'test_result_preserves_render_and_navigation_guards']
        for before, after in mutations:
            with self.subTest(mutation=before):
                self.assertIn(before, self.source)
                mutant = self.source.replace(before, after, 1)
                rejected = False
                for method in methods:
                    test = type(self)(method)
                    test.source = mutant
                    try:
                        getattr(test, method)()
                    except (AssertionError, ValueError):
                        rejected = True
                        break
                self.assertTrue(rejected, before)


if __name__ == '__main__':
    unittest.main()
