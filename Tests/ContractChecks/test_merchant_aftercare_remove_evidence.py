import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class AftercareRemoveEvidenceContract(unittest.TestCase):
 def test_only_local_evidence_and_error_are_changed(self):
  s=(ROOT/'App/MerchantBusinessEditor.swift').read_text().split('Button("merchant.aftercareRemoveEvidence.remove")')[1].split('.disabled')[0]
  for token in ['evidence = cleared.evidence; issue = nil','removalDraft.removingEvidence()']:self.assertIn(token,s)
  for token in ['content =','decision =','model.prepare','onReview(','.execute(','Task {']:self.assertNotIn(token,s)
 def test_old_or_busy_context_cannot_remove(self):
  s=(ROOT/'App/MerchantBusinessEditor.swift').read_text().split('Button("merchant.aftercareRemoveEvidence.remove")')[1].split('.disabled')[0]
  for token in ['scenePhase == .active','evidenceFlow == nil','pendingAftercareDecision == nil','removalOwner.isCurrent','removalOwner.editorID == context.id','removalOwner.snapshot == snapshot','currentRow == row','aftercareEvidenceDraft == removalDraft']:self.assertIn(token,s)
 def test_exact_draft_value_and_no_server_delete(self):
  s=(ROOT/'App/MerchantAftercareEvidenceFlow.swift').read_text();self.assertIn('func removingEvidence() -> Self { .init(decision: decision, content: content, evidence: "") }',s)
  self.assertIn('lhs.content.utf8.elementsEqual(rhs.content.utf8)',s)
if __name__=='__main__':unittest.main()
