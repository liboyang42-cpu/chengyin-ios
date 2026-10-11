"""Focused source seams. These assertions do not execute Swift or verify iOS navigation."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
class ProfileSelfEditSourceChecks(unittest.TestCase):
 def setUp(self):
  self.core=read('Core/ProfileSelfEditNavigation.swift');self.view=read('App/SocialPublicProfileView.swift');self.access=read('App/ProfileSelfEditAccess.swift');self.account=read('App/AccountView.swift')
 def test_own_account_and_editor_both_match_target(self):
  self.assertIn('viewer.accountID == memberID, let editorIdentity, editorIdentity.accountID == memberID',self.core)
 def test_no_unconfigured_or_retired_context(self):
  self.assertIn('guard isCurrent, readerConfigured, editorConfigured, memberID > 0',self.core)
 def test_full_context_captures_reader_and_editor_revisions(self):
  for value in ['readerRevision','editorRevision','editorIdentity','viewer','ObjectIdentifier(reader)','ObjectIdentifier(coordinator)']:self.assertIn(value,self.core)
 def test_controller_has_no_network_or_storage(self):
  for value in ['URLSession','HTTPTransport','UserDefaults','token','save(','ProfileEditPayload']:self.assertNotIn(value,self.core)
 def test_repeat_open_does_not_replace_ticket(self):
  self.assertIn('guard ticket == nil, let context else { return nil }',self.core)
 def test_context_equality_checks_active_ticket(self):
  self.assertIn('ticket == proposed && context == proposed.context',self.core)
 def test_pop_captures_exact_presentation(self):
  self.assertIn('guard let value = ticket, value.id == id else { return false }',self.core)
  self.assertIn('let captured = selfEditNavigation.ticket',self.view)
  self.assertIn('selfEditNavigation.finish(captured.id, context: selfEditContext)',self.view)
 def test_return_consumes_ticket_before_refresh(self):
  body=self.core.split('public func finish(')[1];self.assertLess(body.index('ticket = nil'),body.index('refreshID = UUID()'))
 def test_stale_return_cannot_refresh(self):
  self.assertIn('guard context == value.context else { return false }',self.core)
 def test_normal_account_actually_injects_owned_editor(self):
  self.assertIn('selfEditAccess: .init(coordinator: session.profileEditCoordinator, sessionRevision: session.contentDetailRevision, categoryReader: session)',self.account)
 def test_other_public_callers_default_to_no_self_access(self):
  self.assertIn('var selfEditAccess: ProfileSelfEditAccess? = nil',self.view)
 def test_entry_only_exists_in_about_when_context_available(self):
  body=self.view.split('case .about:')[1];self.assertIn('if selfEditContext != nil',body)
  self.assertIn('Button("profile.selfEdit.open") { selfEditNavigation.open(selfEditContext) }',body)
 def test_return_rekeys_existing_public_read(self):
  self.assertIn('requestKey: "profile-\\(memberID)-\\(selfEditNavigation.refreshID)"',self.view)
  self.assertIn('let loaded = try await reader.publicProfile(memberID: memberID)',self.view)
 def test_public_projection_still_has_parent_read_fence(self):
  self.assertEqual(self.view.count('guard isCurrent() else { throw CancellationError() }'),2)
 def test_destination_reuses_existing_whole_editor(self):
  self.assertIn('ProfileEditView(coordinator: access.coordinator, sessionRevision: access.sessionRevision,',self.access)
  self.assertIn('categoryReader: access.categoryReader)',self.access)
  self.assertIn('.id(ticket.id)',self.access)
 def test_stale_destination_hides_editor(self):
  self.assertIn('if isCurrent(), let access',self.access)
  self.assertIn('profile.selfEdit.changed',self.access)
  self.assertIn('selfEditNavigation.isCurrent(ticket, context: selfEditContext)',self.view)
 def test_no_new_write_or_save_shortcut(self):
  for text in [self.core,self.access,self.view]:
   for bad in ['OperationEndpointApproval','coordinator.save(','.makeFormRequest','api/user/update','onSaved:']:self.assertNotIn(bad,text)
 def test_prior_author_refresh_and_local_cover_preserved(self):
  self.assertIn('ProfileAuthorPostsSection(memberID: memberID',self.view);self.assertIn('ProfileLocalCoverSection(owner: localCoverOwner',self.view)
  self.assertIn('localCoverOwner: localCoverOwner',self.account)
 def test_existing_social_and_public_about_preserved(self):
  for value in ['purpose: .toggleFollow','purpose: .startChat','profile.introduction','profile.interests','profile.workImages']:self.assertIn(value,self.view)
 def test_fixture_uses_actual_public_view_and_editor_service(self):
  text=read('App/ProfileSelfEditFixture.swift');self.assertTrue(text.startswith('#if DEBUG'));self.assertIn('SocialPublicProfileView(',text);self.assertIn('ProfileEditCoordinator',text);self.assertIn('ProfileEditServing',text)
  self.assertNotIn('URLSession',text)
 def test_failed_reads_are_not_optimistic_saved_data(self):
  self.assertNotIn('draft',self.view);self.assertIn('SocialReadScreen(reader: reader',self.view)
  component=read('App/SocialAccountComponents.swift');self.assertIn('else if let error { SocialIssueView(error: error)',component)
 def test_two_bilingual_keys_and_registration(self):
  reg=json.loads(read('docs/profile-self-edit-return-registration.fragment.json'));self.assertEqual(reg['new_endpoints'],[]);self.assertEqual(reg['new_production_approvals'],[])
  loc=json.loads(read(reg['localization_fragment']))['strings'];self.assertEqual(len(loc),2)
  for value in loc.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
 def test_native_case_inventory(self):
  self.assertEqual(read('Tests/CoreTests/ProfileSelfEditNavigationTests.swift').count('func test'),17)
  self.assertEqual(read('Tests/AppUnitTests/ProfileSelfEditReturnTests.swift').count('func test'),8)
  self.assertEqual(read('Tests/AppUITests/ProfileSelfEditReturnFlowTests.swift').count('func test'),6)
if __name__=='__main__':unittest.main()
