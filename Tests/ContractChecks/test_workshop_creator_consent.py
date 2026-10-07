"""Source/shape regressions only. These do not execute Swift or the app."""
import hashlib,json,pathlib,re,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def read(p):return (ROOT/p).read_text()
class CreatorConsentContracts(unittest.TestCase):
 def test_disclosure_is_pinned_and_not_mutable_from_a_remote_boolean(self):
  s=read('Core/WorkshopCreatorConsentContracts.swift')
  text=re.search(r'public static let text = "([^"]+)"',s).group(1)
  self.assertEqual(hashlib.sha256(text.encode()).hexdigest(),'1b14aeefe0ea5c5f9c36aa1819976910acbb8bbfcb64fd8be1246217df03dc5b')
  for literal in ['disclosureVersion == WorkshopCreatorDisclosure.version','disclosureHash == WorkshopCreatorDisclosure.hash','same(disclosureText, WorkshopCreatorDisclosure.text)']:self.assertIn(literal,s)
 def test_preview_rejects_unmapped_source_and_preserves_exact_bytes(self):
  s=read('Core/WorkshopCreatorConsentContracts.swift')
  for token in ['sha(Data(packageSourceJson.utf8)) == packageContentHash','allowed.contains(name)','bindings','merchantGuide','utf16.count','omittedPlanningMetadata','isSubset(of: allowedOmissions)']:self.assertIn(token,s)
 def test_complete_terms_are_shown_and_hashed_before_selection_can_confirm(self):
  c=read('Core/WorkshopCreatorConsentContracts.swift');v=read('App/WorkshopCreatorConsentView.swift')
  self.assertIn('sha(Data(termsDocument.utf8)) == termsDocumentHash',c)
  self.assertIn('Text(verbatim: target.termsDocument)',v)
  self.assertIn('Text(verbatim: preview.disclosureText)',v)
  self.assertIn('controller.targets.isEmpty',v)
 def test_distinct_default_off_read_write_grants_and_empty_target_factory(self):
  s=read('App/AppCompositionRoot.swift')
  for kind in ['Read','Write']:
   self.assertGreaterEqual(s.count(f'WorkshopCreatorConsent{kind}Approval? = {{ _ in nil }}'),2)
  self.assertIn('[WorkshopCreatorDeclarationTarget] = { _, _ in [] }',s)
  self.assertIn('WorkshopCreatorConsentRequest.accepts(request, baseURL: api.baseURL), route != .declare',s)
  self.assertIn('authorization.consume(request, context: context, revision: write.revision)',s)
 def test_root_and_transport_clone_preserve_selectors(self):
  s=read('App/AppCompositionRoot.swift')
  for kind in ['Read','Write']:
   field='workshopCreatorConsent'+kind+'Approval'
   self.assertEqual(s.count(field+': '+field),2)
 def test_context_is_real_role_and_configuration_change_invalidates_first(self):
  s=read('App/AppSession.swift')
  body=s.split('func withWorkshopCreatorConsentConfigurationChange',1)[1].split('func makeWorkshopCreatorConsentController',1)[0]
  self.assertLess(body.index('invalidate()'),body.index('change()'))
  self.assertIn('workshopCreatorConfigurationChanging = true',body)
  self.assertIn('currentWorkshopPaidInstalledTextContext',s)
  self.assertIn('workshopCreatorConfigurationRevision == configuration',s)
 def test_queued_buttons_capture_action_before_task_and_close_revokes(self):
  v=read('App/WorkshopCreatorConsentView.swift');c=read('Core/WorkshopCreatorConsentController.swift')
  self.assertIn('run(controller.offerConfirm(appearance))',v)
  self.assertIn('guard let action else { return }',v)
  self.assertIn('controller.close(appearance); task?.cancel()',v)
  self.assertIn('!displayed.started, !displayed.closed',c)
  self.assertIn('displayed.action == ticket',c)
  self.assertIn('acknowledgments = []; phase = .submitting',c)
 def test_old_receipt_is_pending_review_only(self):
  c=read('Core/WorkshopCreatorConsentContracts.swift')
  for flag in ['packageReviewed','listed','licenseIssued']:self.assertIn(f'forKey: .{flag}) == false',c)
  self.assertIn('CREATOR_DECLARED_PENDING_PACKAGE_REVIEW',c)
  self.assertIn('receipt.matches(command, owner:',read('Core/WorkshopCreatorConsentService.swift'))
 def test_recovery_journal_precedes_dispatch_and_does_not_store_text_or_token(self):
  s=read('Core/WorkshopCreatorConsentController.swift')
  confirm=s.split('public func offerConfirm',1)[1]
  self.assertLess(confirm.index('try store.retain(command)'),confirm.index('self.service.declare(confirmation)'))
  self.assertIn('if let existing = try load()',s)
  self.assertIn('existing.data() == command.data()',s)
  self.assertIn('case .recorded(let receipt)',s)
  command=read('Core/WorkshopCreatorConsentContracts.swift').split('public struct WorkshopCreatorDeclarationCommand:',1)[1].split('public struct WorkshopCreatorDeclarationReceipt:',1)[0]
  self.assertNotIn('packageSourceJson',command);self.assertNotIn('session.token',command)
 def test_visible_entry_uses_existing_owned_member_id(self):
  s=read('App/TemplateAuthoringMineView.swift')
  self.assertIn('WorkshopCreatorConsentSelection(source: id)',s)
  self.assertIn('MemberPlayTemplateID(rawValue: row.id), creatorConsent != nil',s)
  self.assertIn('creatorConsent: { AnyView(SessionWorkshopCreatorConsentView(selection: $0)) }',read('App/TemplateAuthoringLaunchView.swift'))
 def test_localization_complete(self):
  keys=json.loads(read('Resources/WorkshopCreatorConsent.xcstrings'))['strings']
  for k,v in keys.items():
   self.assertEqual(set(v['localizations']),{'en','zh-Hans'},k)
   for loc in v['localizations'].values():self.assertTrue(loc['stringUnit']['value'].strip(),k)
  for prefix,names in [('field.', ['title','description','ruleInstructions','merchantGuide','questionName','questionAnswer','hint1','hint2','answerReveal']),('omitted.', ['categoryId','activityCategoryids','players','usageLocation','requiredMaterials','duration','difficulty'])]:
   for name in names:self.assertIn('workshopCreator.'+prefix+name,keys)
 def test_authored_runtime_coverage_is_explicit_and_bounded(self):
  core=read('Tests/CoreTests/WorkshopCreatorConsentTests.swift');app=read('Tests/AppUnitTests/WorkshopCreatorConsentNormalFlowTests.swift')
  self.assertEqual(len(re.findall(r'func test\w+\(',core)),16)
  self.assertEqual(len(re.findall(r'func test\w+\(',app)),8)
  for token in ['withCheckedContinuation','resume401','commitThenThrow','f.store.load()','f.choices=[]']:self.assertIn(token,core)
  self.assertIn('Date().addingTimeInterval(5)',app)
  self.assertIn('XCTAssertEqual(actual,expected)',app)
if __name__=='__main__':unittest.main()
