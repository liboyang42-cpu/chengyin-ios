"""Local aftercare decision source contracts; not SwiftUI runtime evidence."""
from pathlib import Path
import hashlib
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
BASE_SHA256 = '841f3e4b16c2444e732423b050a0738670759e7341bd7f0376222c318fb07ed7'
HUNKS = [(1060, b'ion = false\n    @State private var pendingAftercareDecision: MerchantAftercareDecisionChange?\n    @State private var confirmAftercareDecis', b''), (3104, b'Binding(get: { ', b'$'), (3127, b' }, set: requestAftercareDecision)', b''), (5294, b'retireAftercareDecision()\n                    ', b''), (6331, b'confirmationDialog("merchant.aftercareDecision.changeTitle", isPresented: $confirmAftercareDecision, titleVisibility: .visible, presenting: pendingAftercareDecision) { change in\n                Button("merchant.aftercareDecision.discard", role: .destructive) { applyAftercareDecision(change) }\n                    .accessibilityIdentifier("merchant.aftercareDecision.discard")\n                Button("merchant.aftercareDecision.keep", role: .cancel) { retireAftercareDecision() }\n            } message: { _ in Text("merchant.aftercareDecision.changeBody") }\n            .onChange(of: confirmAftercareDecision) { _, showing in if !showing { pendingAftercareDecision = nil } }\n            .onChange(of: context.id) { _, _ in retireAftercareDecision() }\n            .onChange(of: snapshot) { _, _ in retireAftercareDecision() }\n            .onChange(of: decision) { _, _ in retireAftercareDecision() }\n            .onChange(of: content) { _, _ in retireAftercareDecision() }\n            .onChange(of: evidence) { _, _ in retireAftercareDecision() }\n            .onDisappear { retireAftercareDecision() }\n            .', b''), (7905, b' }\n    private func requestAftercareDecision(_ proposed: MerchantAftercareDecision) {\n        guard proposed != decision else { return }\n        retireAftercareDecision()\n        guard let change = MerchantAftercareDecisionChange(context: context, snapshot: snapshot, decision: decision,\n                                                          proposed: proposed, content: content, evidence: evidence) else { return }\n        pendingAftercareDecision = change\n        if change.requiresDiscardConfirmation { confirmAftercareDecision = true }\n        else { applyAftercareDecision(change) }\n    }\n    private func applyAftercareDecision(_ change: MerchantAftercareDecisionChange) {\n        guard pendingAftercareDecision?.id == change.id,\n              change.matches(context: context, snapshot: snapshot, decision: decision, content: content, evidence: evidence) else {\n            retireAftercareDecision(); return\n        }\n        decision = change.proposed; content = ""; issue = nil\n        retireAftercareDecision()\n    }\n    private func retireAftercareDecision() { pendingAftercareDecision = nil; confirmAftercareDecision = false', b''), (10463, b'\n    }\n}\n\n/// A local decision-change proposal. It never edits evidence or prepares a request.\nstruct MerchantAftercareDecisionChange: Identifiable {\n    let id = UUID()\n    let proposed: MerchantAftercareDecision\n    private let contextID: UUID\n    private let snapshot: MerchantBusinessSnapshot\n    private let row: MerchantBusinessRecord\n    private let decision: MerchantAftercareDecision\n    private let content: String\n    private let evidence: String\n    var requiresDiscardConfirmation: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }\n\n    init?(context: MerchantBusinessEditorContext, snapshot: MerchantBusinessSnapshot?, decision: MerchantAftercareDecision,\n          proposed: MerchantAftercareDecision, content: String, evidence: String) {\n        guard proposed != decision, case .aftercare(let row) = context.kind,\n              let snapshot, case .refund(let refund) = snapshot.document.query,\n              row.kind == .refund, row.id == String(refund.rawValue), snapshot.document.rows.contains(row),\n              (try? row.fields.mbStrings("allowedDecisions").contains(proposed.rawValue)) == true else { return nil }\n        self.proposed = proposed; contextID = context.id; self.snapshot = snapshot; self.row = row\n        self.decision = decision; self.content = content; self.evidence = evidence\n    }\n    func matches(context: MerchantBusinessEditorContext, snapshot: MerchantBusinessSnapshot?, decision: MerchantAftercareDecision,\n                 content: String, evidence: String) -> Bool {\n        guard context.id == contextID, case .aftercare(let row) = context.kind else { return false }\n        return row == self.row && snapshot == self.snapshot && decision == self.decision\n            && content.utf8.elementsEqual(self.content.utf8) && evidence.utf8.elementsEqual(self.evidence.utf8)', b'')]

class MerchantAftercareDecisionContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'App/MerchantBusinessEditor.swift').read_text()
    def test_exact_inverse_preserves_note_correction_review_and_other_editor_code(self):
        raw = self.source.encode()
        for offset, after, before in reversed(HUNKS):
            self.assertEqual(raw[offset:offset+len(after)], after)
            raw = raw[:offset] + before + raw[offset+len(after):]
        self.assertEqual(hashlib.sha256(raw).hexdigest(), BASE_SHA256)
    def test_nonblank_content_changes_require_explicit_discard_and_unchanged_is_noop(self):
        self.assertIn('selection: Binding(get: { decision }, set: requestAftercareDecision)', self.source)
        self.assertIn('!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', self.source)
        request = self.source.split('private func requestAftercareDecision(',1)[1].split('private func applyAftercareDecision',1)[0]
        self.assertLess(request.index('guard proposed != decision else { return }'), request.index('retireAftercareDecision()'))
        self.assertIn('if change.requiresDiscardConfirmation { confirmAftercareDecision = true }', request)
        self.assertIn('else { applyAftercareDecision(change) }', request)
        self.assertNotIn('content =', request)
        self.assertIn('Button("merchant.aftercareDecision.discard", role: .destructive) { applyAftercareDecision(change) }', self.source)
        self.assertIn('Button("merchant.aftercareDecision.keep", role: .cancel) { retireAftercareDecision() }', self.source)
    def test_confirmation_can_only_apply_original_context_source_and_raw_draft(self):
        for required in ['pendingAftercareDecision?.id == change.id','context.id == contextID','case .aftercare(let row) = context.kind','snapshot.document.rows.contains(row)','row.id == String(refund.rawValue)','snapshot == self.snapshot','decision == self.decision','content.utf8.elementsEqual(self.content.utf8)','evidence.utf8.elementsEqual(self.evidence.utf8)']:
            self.assertIn(required,self.source)
        self.assertIn('row.fields.mbStrings("allowedDecisions").contains(proposed.rawValue)',self.source)
    def test_pending_dialog_retires_on_context_snapshot_review_or_input_changes(self):
        for value in ['context.id','snapshot','decision','content','evidence']:
            self.assertIn('.onChange(of: '+value+') { _, _ in retireAftercareDecision() }', self.source)
        self.assertIn('.onDisappear { retireAftercareDecision() }', self.source)
        self.assertIn('.onChange(of: confirmAftercareDecision) { _, showing in if !showing { pendingAftercareDecision = nil } }', self.source)
        review=self.source.split('Button("merchant.business.reviewDraft") {',1)[1].split('}.accessibilityIdentifier',1)[0]
        self.assertLess(review.index('retireAftercareDecision()'),review.index('makeMutation()'))
    def test_apply_and_cancel_leave_evidence_and_requests_untouched(self):
        apply=self.source.split('private func applyAftercareDecision(',1)[1].split('private func makeMutation()',1)[0]
        self.assertIn('decision = change.proposed; content = ""; issue = nil',apply)
        self.assertNotIn('evidence =',apply)
        retire=apply.split('private func retireAftercareDecision()',1)[1]
        self.assertIn('pendingAftercareDecision = nil; confirmAftercareDecision = false',retire)
        for forbidden in ['content =','decision =','evidence =']: self.assertNotIn(forbidden,retire)
        model=self.source.split('struct MerchantAftercareDecisionChange: Identifiable {',1)[1].split('@MainActor struct MerchantBusinessReviewSheet',1)[0]
        for section in [apply,model]:
            for forbidden in ['Task {','await ','.request(','onReview(','journal','URLSession','.save(','.confirm(']:self.assertNotIn(forbidden,section)
    def test_fragment_is_bilingual_and_supports_exact_complete_merge(self):
        fragment=json.loads((ROOT/'Resources/MerchantAftercareDecisionLocalizations.fragment.json').read_text())
        self.assertEqual(set(fragment),{'merchant.aftercareDecision.'+x for x in ['changeTitle','changeBody','discard','keep']})
        main=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        present=set(fragment)&set(main)
        if present:
            self.assertEqual(present,set(fragment))
            for key in present:self.assertEqual(fragment[key],main[key])
        for entry in fragment.values():
            for locale in ['en','zh-Hans']:self.assertTrue(entry['localizations'][locale]['stringUnit']['value'])
        self.assertIn('evidence',fragment['merchant.aftercareDecision.changeBody']['localizations']['en']['stringUnit']['value'])

if __name__=='__main__':unittest.main(verbosity=2)
