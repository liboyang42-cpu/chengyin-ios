import pathlib,unittest,json
R=pathlib.Path(__file__).resolve().parents[2]
class MerchantAcceptedProjectContract(unittest.TestCase):
 def setUp(self):
  self.route=(R/'Core/MerchantAcceptedProjectRoute.swift').read_text();self.app=(R/'App/MerchantAcceptedProjectView.swift').read_text();self.host=(R/'App/CooperationFlowWorkbench.swift').read_text()
 def test_exact_merchant_roles_accepted_nonlegacy(self):
  for token in ['row["status"].integer == 1','row["inviteType"].integer == 0 && direction == .received','row["inviteType"].integer == 1 && direction == .sent','row["legacyReadonly"]','row["identityError"]']:self.assertIn(token,self.route)
 def test_ids_keep_numeric_safety_and_string_precision(self):
  self.assertIn('id <= 9_007_199_254_740_991',self.route);self.assertIn('text.utf8.allSatisfy',self.route)
  self.assertIn('positive(row["inviteId"]) != invitation',self.route);self.assertIn('matches.count == 1',self.route)
 def test_source_direction_is_explicit_and_old_role_logic_unchanged(self):
  self.assertIn('section: "cooperation.received", direction: .received',self.host)
  self.assertIn('section: "cooperation.sent", direction: .sent',self.host)
  self.assertIn('let isFrom = direction == .sent',self.host)
 def test_fresh_access_then_invitation_before_navigation(self):
  self.assertLess(self.app.index('try await merchant.merchantAccess()'),self.app.index('try await source.revalidate()'))
  self.assertIn('access.allows(.projects)',self.app);self.assertIn('reader.read(.invitations, isCurrent:',self.app)
  self.assertIn('(try? row.canonical()) == rowBytes',self.app)
 def test_source_identity_scope_and_late_callbacks(self):
  for token in ['merchant.sessionRevision == originRevision','service.scope == originServiceScope','reader.session == session','generation == stamp','Task.checkCancellation()','source.reader === session.cooperationFlowReader']:self.assertIn(token,self.app)
  self.assertIn('func retire() { active = false; generation = UUID(); destination = nil',self.app)
 def test_existing_merchant_document_and_runtime_factory(self):
  self.assertIn('MerchantContentDocumentView(service: gate.service, query: .project(topicID: gate.source.route.topicID)',self.app)
  self.assertIn('focusedMerchantID: destination.merchantID',self.app);self.assertIn('projectEntryIsCurrent: { gate.canPresent',self.app)
  self.assertIn('.merchantAcceptedProjectDestination, { AnyView(SessionMerchantAcceptedProjectView(session: session, source: $0)) }',(R/'App/QuestifyApp.swift').read_text())
 def test_new_source_and_gate_do_not_write_or_create_grants(self):
  for token in ['.perform(','.reserve(','.execute(','execution: .','dormantWritesEnabled: true','URLSession']:self.assertNotIn(token,self.app)
  self.assertIn('ZStack {',self.app)
 def test_bilingual_route_boundaries(self):
  rows=json.loads((R/'Resources/MerchantAcceptedProjectLocalizations.fragment.json').read_text());self.assertEqual(len(rows),3)
  for row in rows.values():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
