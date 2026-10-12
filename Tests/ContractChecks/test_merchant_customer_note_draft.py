import pathlib,unittest,json
ROOT=pathlib.Path(__file__).resolve().parents[2]
class MerchantCustomerNoteDraftContract(unittest.TestCase):
 def setUp(self):
  self.flow=(ROOT/'App/MerchantCustomerNoteDraft.swift').read_text();self.host=(ROOT/'App/MerchantBusinessViews.swift').read_text();self.editor=(ROOT/'App/MerchantBusinessEditor.swift').read_text()
 def test_merchant_host_opens_both_existing_note_actions(self):
  self.assertIn('noteDrafts.open(customer: customer, corrects: note)',self.host);self.assertIn('noteDrafts.open(customer: id, corrects: nil)',self.host)
  self.assertIn('noteDrafts: noteDrafts',self.host)
 def test_identity_customer_authorization_and_exact_source_gates(self):
  for s in ['scope == source.scope','scope.realm.utf8.elementsEqual','authorizationGeneration == source.authorization','snapshot == source.snapshot','snapshot.document.query == .customer(customer)','merchant:crm:read','merchant:crm:segment','Self.fingerprint(snapshot.document.payload) == source.payload']: self.assertIn(s,self.flow)
 def test_old_editor_and_discard_tokens_are_rejected(self):
  self.assertIn('lease.id == editorID',self.flow);self.assertIn('expected == nil || expected == generation',self.flow)
  self.assertIn('if lease?.id == editorID { lease = nil }',self.flow)
 def test_no_request_or_persistence_capability(self):
  for s in ['.execute(','.reserve(','.prepare(','UserDefaults','FileManager','URLSession','requestID:'] : self.assertNotIn(s,self.flow)
  for s in ['!c.isBusy','!c.isLocked','c.confirmation == nil','c.receipt == nil','c.failureKey == nil']:self.assertIn(s,self.flow)
 def test_review_boundary_retires_before_prepare(self):
  self.assertIn('guard noteDrafts.retireForReview(editorID: context.id)',self.host)
  self.assertIn('discard(); return true',self.flow)
  self.assertIn('if sourcePageCanPrepare(mutation) { model.prepare(mutation) }',self.host)
 def test_background_and_source_changes_clear_drafts(self):
  self.assertIn('noteDrafts.synchronize()',self.host);self.assertIn('phase != .active, let retired = noteDrafts.retire()',self.host)
  for line in self.host.splitlines():
   if '.onChange(of: reader.scope)' in line or '.onChange(of: reader.authorizationGeneration)' in line:self.assertIn('noteDrafts.discard()',line)
  self.assertIn('.onDisappear { noteDrafts.retire();',self.host)
 def test_clear_close_and_cancelled_mode_are_explicit(self):
  self.assertIn('.confirmationDialog("merchant.noteDraft.clearTitle"',self.editor)
  self.assertIn('saveNoteDraft(); noteDrafts?.close(editorID: context.id)',self.editor)
  self.assertIn('noteCorrectionCancelled = value.correctionCancelled',self.editor)
  self.assertIn('discard(ifGeneration: generation)',self.host)
 def test_bilingual_fragment_complete(self):
  rows=json.loads((ROOT/'Resources/MerchantCustomerNoteDraftLocalizations.fragment.json').read_text());self.assertEqual(len(rows),10)
  for value in rows.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
