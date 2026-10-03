"""Integrated offline source checks. No Swift compiler or external actions."""
from pathlib import Path
import json, unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path): return (ROOT/path).read_text()
class RemainingNativeClients(unittest.TestCase):
 def test_merchant_row_is_distinct_from_node(self):
  s=read('Core/MerchantNPCAuthenticatedTransport.swift')
  for text in ['case "/api/ai/npc/merchant-chat"','fields["bizId"] as? Int == input.scope.merchantRowID.rawValue','enabled: Bool = false','default: throw MerchantNPCFailure.invalid']: self.assertIn(text,s)
  self.assertNotIn('case "/api/ai/npc/shop-chat"',s)
 def test_authenticated_dispatch_rechecks_scope_and_grants(self):
  s=read('Core/MerchantNPCAuthenticatedTransport.swift')
  self.assertGreaterEqual(s.count('scope(input.scope.merchantRowID) == input.scope'),3)
  self.assertIn('token() == credential, grants() == policy',s)
  self.assertIn('throw MerchantNPCFailure.unknownOutcome',s)
 def test_normal_merchant_npc_host_is_dormant_and_scoped(self):
  s=read('App/AppSession.swift')
  for text in ['merchantPublicFactory?.chatGrants ?? .init()','context.installMerchantNPC(', 'merchantNPCClient(resource: true)', 'scopeForRow:', 'value.identity.merchantID == row.rawValue', 'namespace: namespace', 'journal: merchantNPCJournal']: self.assertIn(text,s)
  self.assertIn('merchantPublicApproval: MerchantPublicProductionApproval? = nil',read('App/NativeRuntimeDependencies.swift'))
  self.assertIn('merchantNPCGrants: MerchantNPCGrants = .init()',read('App/NativeRuntimeDependencies.swift'))
  self.assertIn('supportsLegacyResources else',s)
  self.assertIn('operationsDestinationFactory:',read('App/AccountView.swift'))
 def test_normal_publisher_uses_fresh_existing_readers(self):
  s=read('App/AppSession.swift')
  for text in ['PublisherSourceAuthorityReader(topics: topicReader, clubs: self','PublisherLifecycleHostContext(configuration: configuration','freshPublisherAuthority(resource, session: captured)']: self.assertIn(text,s)
  self.assertIn('grants: PublisherLifecycleGrants = .dormant',read('App/PublisherLifecycleHostHooks.swift'))
  self.assertIn('CreatorApplicationHostLink(context: publisherContext',read('App/CreatorContentViews.swift'))
  self.assertIn('PublisherLifecycleNavigationLink',read('App/PlatformConsumerSessionOwner.swift'))
 def test_saved_topic_xp_preserves_editor(self):
  s=read('App/ProjectEditView.swift')
  self.assertIn('if let topicID = model.coordinator.snapshot?.topicID, let publisherClient',s)
  self.assertIn('PublisherXPBudgetSection(topicID: topicID',s)
  self.assertIn('model.coordinator.snapshot?.scope == .whitelist',s)
 def test_im_native_picker_reuses_upload_owner(self):
  s=read('App/AppSession.swift')
  self.assertIn('if let existing = imImageCoordinators[scope] { return existing }',s)
  self.assertIn('writer: imExpandedWriter, picker: retainedImagePickerHost.imPicker(scope: scope',s)
  self.assertIn('self.imExpandedWriter.identity == scope.identity',s)
  self.assertIn('var nativeSelectionEnabled = false',read('App/RetainedImagePresenterHost.swift'))
  self.assertIn('RetainedImagePresenterHost(host: session.retainedImagePickerHost)',read('App/QuestifyApp.swift'))
 def test_fixture_roots_skip_production_session(self):
  s=read('App/QuestifyApp.swift'); root,container=s.split('final class AppSessionContainer',1)
  for flag in ['--merchant-npc-fixture','--publisher-lifecycle-fixture','--retained-images-fixture']:
   self.assertIn(flag,root); self.assertIn(flag,container)
 def test_wechat_shared_commit_preserves_existing_sync(self):
  s=read('App/AppSession.swift'); body=s.split('private func commitChannelLogin',1)[1].split('// Official writes',1)[0]
  for text in ['vault.write(result.token)','gate.invalidate()','synchronizeRegistration()','clubGovernanceCoordinator.cancelReview()','merchantOnboardingCoordinator.synchronizeSession()']:self.assertIn(text,body)
  self.assertIn('session.weChatAuth.cancel(); password="";showsOtherSignIn=true',read('App/LoginView.swift'))
 def test_fragment_catalogs_equal_default_table(self):
  main=json.loads(read('Resources/Localizable.xcstrings'))['strings']
  for name in ['MerchantNPC','RetainedImages','WeChatAppAuth']:
   fragment=json.loads(read(f'Resources/{name}Localizations.fragment.json'))['strings']
   for key,value in fragment.items():self.assertEqual(value,main[key])
 def test_image_role_background_and_unknown_fences(self):
  session=read('App/AppSession.swift'); cache=read('App/RetainedImageContextCache.swift')
  self.assertIn('entryObservedRole != account?.effectiveRole',session)
  self.assertIn('authorizationRevision: account.effectiveRole',session)
  self.assertIn('credentials == capturedCredentials',read('App/MerchantRetainedImageHost.swift'))
  self.assertIn('sameUnresolvedTarget',cache)
  for path in ['App/RetainedImageSelectionView.swift','App/PublicMerchantReviewEditor.swift','App/MerchantOperationsViews.swift']:
   self.assertIn('.onChange(of: scenePhase)',read(path))
 def test_npc_avatar_uses_typed_scope_bridge(self):
  s=read('App/AppSession.swift'); ui=read('App/MerchantNPCViews.swift')
  self.assertIn('accessRevision: captured.accessRevision, namespace: captured.namespace',s)
  self.assertIn('imageContext: merchantNPCAvatarContext(captured)',s)
  self.assertIn('approvedImageHosts: []',s)
  self.assertIn('proof.npcAvatar(scope: model.coordinator.scope',ui)
  self.assertIn('imageContext.currentScope() == proof.scope',ui)
 def test_sdk_not_added_and_apple_tests_not_claimed(self):
  for text in ['WechatOpenSDK','WeChatSDK']:
   self.assertNotIn(text,read('Package.swift'))
  self.assertIn('no adapter, no service',read('docs/remaining-native-clients/wechat/wechat-app-auth-integration.md'))
if __name__=='__main__':unittest.main()
