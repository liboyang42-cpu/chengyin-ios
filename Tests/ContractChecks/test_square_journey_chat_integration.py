"""Offline source/host integration checks; no Apple/runtime/network evidence."""
from pathlib import Path
import json,unittest
R=Path(__file__).resolve().parents[2]
def read(p):return (R/p).read_text()
class SquareJourneyChatIntegration(unittest.TestCase):
 def test_normal_square_route_observes_session(self):
  s=read('App/SessionSquareBrowserView.swift')
  for x in ['@ObservedObject var session: AppSession','.id(session.sessionRevision)','session.squareWorkspace()','session.squareGovernance()']:self.assertIn(x,s)
  self.assertIn('SessionSquareBrowserView(session: session',read('App/SessionHomeFeedView.swift'))
 def test_workspace_private_storage_and_grants_off(self):
  s=read('App/AppSession.swift');self.assertIn('SquareWorkspaceSecureStorage(scope: storageScope)',s)
  self.assertIn('model.session == identity',s);self.assertIn('self.currentSquareWorkspaceSession == identity',s)
  self.assertNotIn('SquareWorkspaceMemoryStorage()',s)
  for key in ['live','media','legal']:self.assertIn('var '+key+' = false',read('Core/SquareWorkspaceContracts.swift'))
 def test_workspace_normal_compose_edit_and_draft_routes(self):
  s=read('App/SquareBrowserView.swift');self.assertIn('if workspace != nil { showsWorkspace = true } else { showsComposer = true }',s)
  self.assertIn('openDrafts: { if workspace != nil { showsWorkspace = true } }',s)
  s=read('App/SquareDetailView.swift');self.assertIn('SquareWorkspaceView(coordinator: workspace, initialPostID: id)',s)
  s=read('Core/SquareWorkspaceCoordinator.swift');self.assertIn('post.id == postID, post.authorID == session.accountID',s)
  self.assertIn('initialPostID != nil && !editReady',read('App/SquareWorkspaceView.swift'))
 def test_fresh_comment_projection_never_invents_version_or_author(self):
  s=read('Core/SquareContracts.swift');self.assertIn('public let version: Int?',s);self.assertIn('version = value["version"].number',s);self.assertNotIn('version = value["version"].number ??',s)
  s=read('App/AppSession.swift')
  for x in ['squareReader.squareDetail(id: postID)','squareReader.squareComments(postID: postID, pageNumber: 1)','self.squareReader.scope == readScope','SquareGovernanceComment(comment: $0, post: post)']:self.assertIn(x,s)
 def test_governance_dormant_per_operation_transport(self):
  s=read('Core/SquareGovernanceService.swift');self.assertIn('grant: SquareGovernanceMutationGrant = .disabled',s);self.assertIn('mutationCapabilities.contains(SquareGovernanceCapability(action))',s)
  self.assertNotIn('reviewedInjection',read('App/AppSession.swift'))
 def test_journey_additive_models_and_loss_tolerant_eggs(self):
  s=read('App/SessionPlayRuntimeView.swift')
  for x in ['session.playDevice(','session.playPlayer(','session.playCircle(','session.playStillness(','session.playPrefab(','session.journeyCheck(','session.journeyAmbient(','session.platformConsumers.audioFactory','session.platformConsumers.mapsFactory']:self.assertIn(x,s)
  self.assertIn('eggs = JourneyEgg.project((try? c.decode',read('Core/PlayContracts.swift'))
  s=read('App/PlayExperienceView.swift');self.assertIn('PlayJourneyCheckView(model: journey',s);self.assertIn('PlatformChapterAudioSelection.resolve(snapshot: model.snapshot',s)
 def test_journey_server_checks_are_separate_from_local_dice(self):
  s=read('Core/JourneyContentService.swift')
  for x in ['readsEnabled: Bool = false','checksEnabled: Bool = false','collectEnabled: Bool = false']:self.assertIn(x,s)
  self.assertNotIn('random',s);self.assertNotIn('PlayPrefab',s)
  self.assertIn('JourneyStoredCheckJournal(',read('App/AppSession.swift'))
 def test_new_debug_fixtures_bypass_production_session(self):
  s=read('App/QuestifyApp.swift')
  for x in ['--square-governance-fixture','--shop-npc-fixture']:self.assertGreaterEqual(s.count(x),2)
  s=read('App/ModuleFixtureSupport.swift')
  for x in ['case journeyContent','case squareWorkspace = "square-workspace"','JourneyContentFixtureHostView()','SquareWorkspaceFixtureHost()']:self.assertIn(x,s)
 def test_real_bilingual_catalog_contains_all_packet_entries(self):
  actual=json.loads(read('Resources/Localizable.xcstrings'))['strings'];root='docs/square-journey-chat/packets/'
  for file in ['native-square-workspace-new/docs/square-workspace-localizations.json','native-square-governance-new/Resources/SquareGovernanceLocalizations.fragment.json','native-shop-npc-new/Resources/ShopNPC.xcstrings']:
   for k,v in json.loads(read(root+file))['strings'].items():self.assertEqual(actual[k],v,k)
  for k,langs in json.loads(read(root+'native-journey-checks-new/docs/localizations.json')).items():
   for lang,value in langs.items():self.assertEqual(actual[k]['localizations'][lang]['stringUnit']['value'],value)
 def test_merchant_and_node_identity_domains_stay_separate(self):
  self.assertNotIn('npcDestination:',read('App/AppSession.swift'))
  s=read('Core/ShopNPCHTTP.swift');self.assertNotIn('bizId',s);self.assertNotIn('merchantId',s)
  self.assertIn('nodeId:',s)
 def test_shop_npc_normal_host_requires_fresh_node_authority(self):
  s=read('App/AppSession.swift')
  for x in ['runtime.hasCurrentMediaSnapshot','snapshot.availability == .active','node.npc == npc','account.effectiveRole','shopNPCSessionOwner.accessRevision','runtimeDependencyFactory?.accepted?.shopNPCWrites == true','runtimeDependencyFactory?.accepted != nil ? runtimeDependencies.shopNPCGrants : ShopNPCGrants()']:self.assertIn(x,s)
  self.assertIn('session.shopNPCNodeHost(scope: scope, nodeID: $0, runtime: model)',read('App/SessionPlayRuntimeView.swift'))
  self.assertIn('ShopNPCNodeEntrance(name: shopNPC.name',read('App/PlayExperienceView.swift'))
 def test_shop_npc_owned_destination_and_observable_invalidation(self):
  s=read('App/ShopNPCSessionHost.swift')
  for x in ['@State private var coordinator: ShopNPCCoordinator?','if coordinator == nil','conversations.forEach { $0.value?.invalidate() }']:self.assertIn(x,s)
  self.assertIn('@MainActor @Observable public final class ShopNPCCoordinator',read('Core/ShopNPCCoordinator.swift'))
  self.assertIn('.onChange(of: coordinator.active)',read('App/ShopNPCView.swift'))
 def test_shop_npc_concrete_transport_is_auth_scoped_and_default_off(self):
  s=read('Core/ShopNPCAuthenticatedTransport.swift')
  for x in ['productionWritesEnabled: Bool = false','captured.scope == input.scope','currentSession() == captured, currentGrants() == grants','request.setValue(captured.token, forHTTPHeaderField: "Authorization")','try await transport.send(request)']:self.assertIn(x,s)
  self.assertNotIn('URLSession',s)
