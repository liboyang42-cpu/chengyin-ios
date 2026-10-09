"""Focused note-correction UI contract checks; not Apple UI execution."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

class MerchantNoteCorrectionPresentationContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_correction_target_and_append_meaning_are_visible_in_draft_and_review(self):
        source = self.read('App/MerchantBusinessEditor.swift')
        self.assertIn('LabeledContent("merchant.business.field.correctsNoteId", value: String(note))', source)
        self.assertEqual(source.count('Text("merchant.noteCorrection.append")'), 2)
        self.assertIn('if case .addNote(let customer, _, let correction) = review.mutation, let note = correction', source)
        self.assertIn('correctsNoteID: noteCorrectionCancelled ? nil : corrects', source)
        core = self.read('Core/MerchantBusinessMutation.swift')
        self.assertIn('correction == nil ? "merchant.business.addNote" : "merchant.business.correctNote"', core)
    def test_only_explicit_destructive_confirmation_clears_text_and_local_target(self):
        source = self.read('App/MerchantBusinessEditor.swift')
        self.assertIn('Button("merchant.noteCorrection.cancel") { confirmCancelCorrection = true }', source)
        block = source.split('.confirmationDialog("merchant.noteCorrection.cancelTitle"', 1)[1].split('.onAppear', 1)[0]
        self.assertIn('Button("merchant.noteCorrection.confirmCancel", role: .destructive)', block)
        self.assertIn('noteCorrectionCancelled = true; content = ""; issue = nil', block)
        self.assertIn('Button("merchant.noteCorrection.keep", role: .cancel) { }', block)
        self.assertIn('merchant.noteCorrection.cancelBody', block)
        for forbidden in ['requestID', 'journal', 'Task {', 'onReview(', 'prepare(', 'save(', 'execute(']: self.assertNotIn(forbidden, block)
        appearance = source.split('.onAppear {', 1)[1].split('private func makeMutation', 1)[0]
        self.assertNotIn('noteCorrectionCancelled', appearance)
        self.assertNotIn('.note(', appearance)
    def test_summary_is_read_only_and_scoped_to_exact_customer_and_note(self):
        source = self.read('App/MerchantBusinessEditor.swift')
        self.assertIn('MerchantNoteCorrectionTargetSummary(customer: customer, noteID: note, snapshot: snapshot)', source)
        self.assertIn('MerchantNoteCorrectionTargetSummary(customer: customer, noteID: note, snapshot: review.baseline)', source)
        summary = source.split('private struct MerchantNoteCorrectionTargetSummary: View {', 1)[1]
        for required in ['snapshot.document.query == .customer(customer)', '$0.kind == .timeline', '["NOTE", "NOTE_CORRECTION"]', '$0.fields["noteId"]?.integer == noteID', '?.fields.mbText("description")', 'LabeledContent("merchant.noteCorrection.originalSummary", value: summary)']:
            self.assertIn(required, summary)
        for forbidden in ['$content', 'TextField(', 'content =', 'request(', 'Task {', 'execute(', 'onReview(']:
            self.assertNotIn(forbidden, summary)
    def test_mode_and_local_cancel_are_repeat_safe_without_prefill(self):
        source = self.read('App/MerchantBusinessEditor.swift')
        self.assertIn('Text(noteCorrectionID == nil ? "merchant.business.addNote" : "merchant.business.correctNote")', source)
        self.assertIn('LabeledContent("merchant.business.target", value: "customer:\\(customer.rawValue)")', source)
        self.assertIn('guard !noteCorrectionCancelled, case .note(_, let correction) = context.kind else { return nil }', source)
        self.assertIn('@State private var content = ""', source)
        self.assertIn('if let note = noteCorrectionID {', source)
        correction_block = source.split('if let note = noteCorrectionID {', 1)[1].split('case .tag:', 1)[0]
        self.assertNotIn('content =', correction_block)
        self.assertNotIn('Task {', correction_block)
    def test_fragment_is_bilingual_and_accepts_exact_full_merge(self):
        fragment = json.loads(self.read('Resources/MerchantNoteCorrectionLocalizations.fragment.json')); self.assertEqual(len(fragment), 7)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']; present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for lang in ['en', 'zh-Hans']: self.assertTrue(entry['localizations'][lang]['stringUnit']['value'].strip())
if __name__ == '__main__': unittest.main()
