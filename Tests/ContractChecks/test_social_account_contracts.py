"""Source-structure checks only. No Swift compiler, simulator or live service is run."""
import json, pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class SocialAccountSourceTests(unittest.TestCase):
 def read(self, path): return (ROOT/path).read_text()
 def test_read_route_allowlist_uses_public_profile_and_source_information_spelling(self):
  value = self.read('Core/SocialAccountService.swift')
  self.assertEqual(set(re.findall(r'"(api/[^" ]+)"', value)), {'api/user/public-info','api/common/infomation_list','api/common/infomation_detail','api/user/invite_list','api/user/points/list'})
  self.assertNotIn('api/user/info"', value)
 def test_private_reads_preserve_complete_session_and_stale401_boundary(self):
  value = self.read('Core/SocialAccountReading.swift')
  self.assertIn('currentSession() == snapshot',value); self.assertIn('snapshot.token != nil',value)
  self.assertIn('identity.accountID != nil',value)
  app=self.read('App/AppSession.swift'); self.assertIn('self.currentSocialAccountSession == captured',app)
  self.assertIn('role: account.effectiveRole',app)
 def test_production_factory_uses_member_grants_and_requires_scoped_media_approval(self):
  app=self.read('App/AppSession.swift')
  self.assertIn('SocialMemberActionSessionOwner(configuration:',app)
  self.assertIn('SocialMemberActionFactory.make(',self.read('Core/SocialMemberActionSessionOwner.swift'))
  self.assertIn('return self.runtimeDependencies.socialMemberActionApprovals',app)
  self.assertIn('lazy var socialMessageMediaReader = makeSocialMessageMediaReader()',app)
  self.assertIn('socialReaderApproval: SocialReaderProductionApproval? = nil',self.read('App/NativeRuntimeDependencies.swift'))
  production=self.read('Core/SocialReaderProduction.swift')
  self.assertIn('approval.messageImages',production);self.assertIn('authorize: { try await readback.validate($0) }',production)
  self.assertNotIn('SocialActionService(',app);self.assertNotIn('SocialMessageMediaService(',app)
  access=self.read('Core/SocialActionCoordinator.swift')
  body=access.split('public func perform(',1)[1].split('\n}',1)[0]
  self.assertIn('throw SocialActionWriteFailure.notSent',body);self.assertNotIn('transport.send',body)
 def test_dormant_writer_has_actual_injected_transport_and_no_retry_or_fabricated_object(self):
  value=self.read('Core/SocialActionService.swift')
  self.assertIn('try await transport.send(request)',value)
  self.assertIn('SocialActionWriteFailure.outcomeUnknown',value)
  self.assertIn('envelope["data"]["conversationId"].integer',value)
  self.assertIn('message.contains("取消关注")',value)
  self.assertNotIn('SquarePost(',value);self.assertNotIn('MessagingMessage(',value)
 def test_exact_mutation_shapes_preserve_post_link_and_id_only_report(self):
  value=self.read('Core/SocialActionContracts.swift')
  for required in ['"request_id": requestID','"reply_id": String(snapshot.target.commentID ?? 0)','"owner_type": "3"','"follow_member_id"','"target_member_id"','"APP_SQUARE"','fields["data_id"]','fields["data_type"]']:
   self.assertIn(required,value)
  self.assertIn('"reason": reason.trimmingCharacters',value);self.assertNotIn('"author_id":',value);self.assertNotIn('"latitude":',value)
 def test_unknown_action_locks_survive_navigation_and_account_epoch(self):
  value=self.read('Core/SocialActionCoordinator.swift')
  for required in ['accountID: Int; let target: SocialActionTarget','case .submitting, .outcomeUnknown: records[key]?.state = .outcomeUnknown','fresh.sameContext(as: review.snapshot)','records[key]?.id == review.id','ownerID == ownerID']:
   self.assertIn(required,value)
  self.assertNotIn('func retry',value)
 def test_reward_partial_unknown_and_numeric_title_semantics(self):
  value=self.read('Core/SocialAccountContracts.swift')
  self.assertIn('notSynchronized',value);self.assertIn('row["eventType"].integer == 5',value)
  self.assertIn('amount > 0',value);self.assertIn('summary != nil',value)
  self.assertIn('total.map { $0 <= fetchedCount } ?? false',value)
  self.assertIn('guard v["total"].isNull || total != nil',value)
  self.assertIn('page.total.map { members.count < $0 }',value)
  self.assertIn('SocialAccountService',self.read('Core/SocialAccountService.swift'))
 def test_message_media_does_not_send_credentials_or_implicitly_load(self):
  core=self.read('Core/SocialMessageMedia.swift');ui=self.read('App/SocialMessageMediaView.swift')
  for required in ['approvedOrigins.contains(origin)','request.httpShouldHandleCookies = false','request.httpMethod = "GET"','data.count <= Self.maximumBytes','identity == expectedIdentity']:
   self.assertIn(required,core)
  self.assertNotIn('Authorization',core);self.assertNotIn('AsyncImage',ui);self.assertNotIn('.task',ui)
  self.assertIn('width.doubleValue * height.doubleValue <= 32_000_000',ui)
 def test_navigation_back_does_not_delete_rows_owning_destination_links(self):
  for name in ['SocialAccountComponents.swift','SocialPublicProfileView.swift','SocialInviteHistoryView.swift']:
   value=self.read('App/'+name)
   disappear='\n'.join(re.findall(r'\.onDisappear\s*\{([^}]*)\}',value))
   self.assertNotIn('pagination =',disappear);self.assertNotIn('value = nil',disappear)
 def test_bilingual_keys_fixture_isolation_and_real_guide_tab_mapping(self):
  catalog=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
  keys={key:entry for key,entry in catalog.items() if key.startswith('social.')}
  self.assertEqual(len(keys),106)
  for key,entry in keys.items():
   for language in ['en','zh-Hans']:self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip(),key)
  fixture=self.read('App/SocialAccountFixtureSupport.swift'); self.assertTrue(fixture.startswith('#if DEBUG'))
  self.assertNotIn('URLSession',fixture);self.assertNotIn('AppSession(',fixture)
  self.assertIn('destination == .roam ? 3 : 0',self.read('App/QuestifyApp.swift'))
if __name__=='__main__':unittest.main()
