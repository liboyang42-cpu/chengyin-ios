import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class OperatorRoleNoChangeContract(unittest.TestCase):
 def test_local_return_precedes_mutation(self):
  s=(ROOT/'App/MerchantBusinessEditor.swift').read_text();branch=s.split('if let unchangedRole {')[1].split('retireEvidenceFlow()')[0]
  self.assertIn('onUnchangedRole?(unchangedRole) == true',branch)
  self.assertNotIn('onReview(',branch);self.assertNotIn('makeMutation()',branch)
  self.assertIn('case .role(let row): return .operatorRole',s)
 def test_host_rejects_old_or_foreign_editor(self):
  s=(ROOT/'App/MerchantBusinessViews.swift').read_text().split('onUnchangedRole: { ticket in')[1].split('}, onReview:')[0]
  for token in ['editor?.id == context.id','ticket.editorID == context.id','pendingMutation == nil','reader.scope == roleReturnScope','reader.authorizationGeneration == roleReturnAuthorization','state.snapshot == roleReturnSnapshot','snapshot.access.canManageOperators','scenePhase == .active','editor = nil']:self.assertIn(token,s)
  self.assertNotIn('model.prepare',s);self.assertNotIn('pendingMutation = mutation',s)
 def test_ticket_is_pure_and_existing_wording(self):
  s=(ROOT/'Core/MerchantOperatorRoster.swift').read_text().split('public struct MerchantOperatorRoleNoChange')[1]
  for token in ['URLSession','MerchantBusinessMutation','permissions =','execute(']:self.assertNotIn(token,s)
  self.assertIn('merchant.done',(ROOT/'App/MerchantBusinessEditor.swift').read_text())
if __name__=='__main__':unittest.main()
