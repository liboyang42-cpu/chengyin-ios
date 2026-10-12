import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class MerchantTeamCurrentAccessContract(unittest.TestCase):
 def test_actual_roster_entry_and_server_fields(self):
  s=(ROOT/'App/MerchantOperatorRosterSections.swift').read_text()
  for t in ['if access.canManageOperators {','access.name','access.role','access.merchantID','DisclosureGroup("merchant.operatorRoster.accessDetails"','@Binding var detailsExpanded']:self.assertIn(t,s)
  self.assertNotIn('@State',s)
 def test_stable_owner_and_identity_gates(self):
  s=(ROOT/'App/MerchantBusinessViews.swift').read_text()
  for t in ['@State private var teamAccessDetailsExpanded = false','reader.scope == renderedTeamScope','reader.authorizationGeneration == renderedTeamAuthorization','state.snapshot == snapshot','query == .operators','detailsExpanded: Binding']:self.assertIn(t,s)
  self.assertEqual(s.count('teamAccessDetailsExpanded = false'),4)
 def test_disclosure_is_local_only(self):
  s=(ROOT/'App/MerchantBusinessViews.swift').read_text().split('detailsExpanded: Binding')[1].split('})) { row in')[0]
  self.assertIn('teamAccessDetailsExpanded = expanded',s)
  for t in ['Task {','model.prepare','confirm(','reload(','request(']:self.assertNotIn(t,s)
if __name__=='__main__':unittest.main()
