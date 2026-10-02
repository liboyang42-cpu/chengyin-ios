"""Native integration/source-shape checks; no compiler or runtime assertions."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class PublishingIntegrationTests(unittest.TestCase):
 def text(self,path): return (ROOT/path).read_text()
 def test_real_host_is_reachable_and_typed(self):
  self.assertIn('SessionPublishingModesView()',self.text('App/ProjectEditLaunchView.swift'))
  host=self.text('App/SessionPublishingModesView.swift')
  for kind in ['case .topic:', 'case .activity:', 'case .template:']: self.assertIn(kind,host)
  self.assertIn('seed: seed',host); self.assertIn('session.publishingDraftStore',host)
 def test_session_epoch_includes_role_and_live_defaults_off(self):
  s=self.text('App/AppSession.swift');self.assertIn('publishingEpochCache?.role != role',s)
  self.assertIn('readApproval: OperationEndpointApproval? = nil',s)
  self.assertIn('lazy var publishingService: PublishingService? = makePublishingService()',s)
  part=s.split('func makePublishingService')[1].split('private var retainedTemplateAuthors')[0]
  self.assertNotIn('journal:',part);self.assertNotIn('PublishingAuxiliaryService(',s)
 def test_seed_preserves_existing_pending_and_restore_boundaries(self):
  s=self.text('App/ProjectEditView.swift');self.assertIn('seedSession == coordinator.session, fullEdit',s)
  self.assertIn('coordinator.snapshot?.topicID == nil',s);self.assertIn('seedSession != coordinator.session { incomingSeed = nil }',s)
  self.assertIn('!hasRestore',s);self.assertIn('!coordinator.isLocked',s)
 def test_reward_binding_is_validated_before_review(self):
  self.assertIn('PublishingTopicRewardsForm(rewards: model.rewards',self.text('App/ProjectEditView.swift'))
  self.assertIn('PublishingTopicRewards(draft: draft).applying(to: draft)',self.text('Core/ProjectEditDraft.swift'))
 def test_auxiliary_implementation_is_executable_and_gated(self):
  s=self.text('Core/PublishingAuxiliaryService.swift');self.assertIn('transport.send(request)',s)
  self.assertIn('approval: OperationEndpointApproval? = nil',s);self.assertIn('journal: (any OperationPendingJournal)? = nil',s)
  self.assertIn('review.session.region == .china',s);self.assertIn('reviews[review.id] == review',s)
 def test_identity_rechecks_without_persisting_sensitive_data(self):
  s=self.text('Core/PublishingAuxiliaryService.swift');self.assertIn('identityAlreadyRegistered(credential) == false',s)
  dispatch=s.split('public func confirm')[1];self.assertLess(dispatch.index('try journal.write(record)'),dispatch.index('transport.send(request)'))
  self.assertNotIn('JSONEncoder().encode(review)',s);self.assertNotIn('UserDefaults',s)
 def test_fixture_does_not_construct_production_session(self):
  s=self.text('App/QuestifyApp.swift');self.assertGreaterEqual(s.count('--ui-publishing-modes'),2)
  fixture=self.text('App/PublishingModesFixtureSupport.swift');self.assertIn('service: nil, account: nil',fixture)
 def test_exact_identity_and_ai_payload_tests_authored(self):
  s=self.text('Tests/CoreTests/PublishingAuxiliaryTests.swift')
  for name in ['testAIExactExecutableRequestsAndPayloads','testChinaIdentityExecutesExactTransientBodyAfterStatusRead','testLostAuxiliaryResponseBlocksRestartRetry','testRegisteredIdentityIsNotRebound']:self.assertIn(name,s)
 def test_localized_keys_in_default_table(self):
  c=json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
  for key in ['publishModes.title','publishModes.identityUSUnsupported','publishModes.seedPending','publishModes.savedLocal','projectEdit.validation.rewards']:
   self.assertEqual(set(c[key]['localizations']),{'en','zh-Hans'})
 def test_storage_pointer_scope_and_baseline(self):
  s=self.text('Core/PublishModesDraftStore.swift');self.assertIn('session.storageKey',s);self.assertIn('value.baseline == baseline',s)
  self.assertIn('draft.activity != nil',s);self.assertNotIn('idCard',s)

 def test_approved_read_uses_captured_credentials(self):
  s=self.text('Core/PublishModesService.swift')
  self.assertIn('approved.send(request, credential: credential)',s)
  self.assertIn('currentCredentials() == credential',s)
  self.assertIn('request.value(forHTTPHeaderField: "Authorization") == credential.token',s)
 def test_identity_unknown_is_not_authoritative_false(self):
  s=self.text('App/PublishingManagementViews.swift').split('struct PublishingIdentityStatusView')[1].split('/// Embed')[0]
  for state in ['case .unconfigured:', 'case .loading:', 'case .failed:', 'case .registered:', 'case .notRegistered:']:
   self.assertIn(state,s)
  self.assertIn('try await service.identityRegistered',s)
  core=self.text('Core/PublishModesService.swift').split('public func identityRegistered')[1].split('public func prepareActivity')[0]
  self.assertIn('async throws -> Bool',core)
  self.assertIn('throw PublishModesError.invalidContract',core)
  self.assertNotIn('return false',core)
