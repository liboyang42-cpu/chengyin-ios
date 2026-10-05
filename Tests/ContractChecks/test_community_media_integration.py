"""Offline integration assertions only: no Swift compiler, backend or Apple runtime."""
from pathlib import Path
import json, unittest
R=Path(__file__).resolve().parents[2]
def read(p):return (R/p).read_text()
class CommunityMediaIntegration(unittest.TestCase):
 def test_club_public_entry_is_outside_governance(self):
  s=read('App/ClubDetailView.swift');self.assertLess(s.index('ClubCommunityEntry('),s.index('// V2 governance'))
  self.assertIn('ClubCommunityFeedView(context: community, identity: reader.clubIdentity)',read('App/ClubHomeView.swift'))
 def test_club_evidence_is_fresh_and_exact(self):
  s=read('App/AppSession.swift')
  for n in ['try await clubDetail(id: clubID)','exact.clubID == clubID','exactComment.postID == exact.id','try currentCommunitySession() == captured','private lazy var communityCoordinator'] :self.assertIn(n,s)
  self.assertIn('CommunityDormantHTTPTransport()',s)
 def test_public_merchant_identity_routes_remain_distinct(self):
  s=read('Core/NativeEntryRouting.swift')
  self.assertIn('.publicMerchant(.ownerMemberID(owner))',s);self.assertIn('.publicMerchant(.legacyMerchantRowID(row))',s)
  self.assertIn('verifiedHTTPSOrigins: Set<String> = []',s)
  s=read('App/TopicDetailView.swift');self.assertIn('PublicMerchantOwnerID(merchant.memberID)',s)
  self.assertNotIn('PublicMerchantRowID(merchant.memberID)',s)
 def test_public_review_context_remains_disabled(self):
  s=read('App/AppSession.swift');self.assertIn('DisabledPublicMerchantHomeReader()',s);self.assertIn('DisabledPublicMerchantReviewReader()',s)
  self.assertIn('PublicMerchantReviewsView(target: $0, reader: reviews, imageReader: images, writes: writes)',s)
  self.assertIn('PublicMerchantReviewGatedWriter(base: concrete, enabled: false',read('App/RetainedPublicMerchantReviewHost.swift'))
  self.assertNotIn('PublicMerchantReviewWriteContext(',s)
 def test_chapter_media_is_same_snapshot_locked_and_current(self):
  s=read('Core/PlatformChapterAudioBridge.swift')
  for n in ['snapshot.visibleNodes.first','!snapshot.isLocked(node)','node.chapterID','$0.id == chapterID','chapter.audioURL']:self.assertIn(n,s)
  s=read('App/PlayExperienceView.swift');self.assertIn('PlatformChapterAudioSelection.resolve(snapshot: model.snapshot',s)
  self.assertIn('currentRead: model.hasCurrentMediaSnapshot',s);self.assertNotIn('node.questionAudio ?? model.extras',s)
 def test_media_owner_invalidates_before_identity_replacement(self):
  s=read('App/AppSession.swift')
  self.assertIn('if account?.id != newValue?.id { platformConsumers.invalidate() }',s)
  token_owner = next(line for line in s.splitlines() if 'private var token: String?' in line).split('didSet')[0]
  self.assertIn('willSet {', token_owner)
  self.assertIn('invalidateOwnerDraftBrowser(); if token != newValue { invalidateShopNPCConversations(); platformConsumers.invalidate() } }',token_owner)
  s=read('App/PlatformConsumerSessionOwner.swift');self.assertIn('audio.forEach { $0.dispose() }',s);self.assertIn('maps.forEach { $0.invalidate() }',s)
  self.assertIn('audio: (() -> PlatformAudioPlayback)? = nil',s)
 def test_maps_use_ticket_poi_and_selected_node(self):
  self.assertIn('order.gatherLatitude',read('App/ProfileOrdersView.swift'))
  self.assertIn('node.coordinate?.latitude',read('App/RoamItemDetailView.swift'))
  self.assertIn('latitude: destination.latitude',read('App/SearchRoutePreviewView.swift'))
  self.assertIn('latitude: node.latitude',read('App/PlayExperienceView.swift'))
  self.assertIn('case cmsActivity, cmsTopic, omsTicket',read('Core/ProfileContracts.swift'))
 def test_play_host_repair_is_preserved(self):
  s=read('App/SessionPlayRuntimeView.swift')
  for n in ['session.playDevice(', 'session.playPlayer(', 'session.playCircle(', 'session.playStillness(', 'session.platformConsumers.audioFactory','PlayNativeCameraSheet(']:self.assertIn(n,s)
 def test_real_catalog_contains_exact_fragments(self):
  actual=json.loads(read('Resources/Localizable.xcstrings'))['strings']
  for name in ['ClubCommunity','PublicMerchantHome','PlatformConsumers']:
   fragment=json.loads(read('docs/community-media-templates/catalogs/'+name+'.xcstrings'))['strings']
   for k,v in fragment.items():self.assertEqual(actual[k],v,k)
 def test_debug_roots_bypass_production_session(self):
  s=read('App/QuestifyApp.swift')
  for flag in ['--club-community-fixture','--public-merchant-home-fixture'] :self.assertGreaterEqual(s.count(flag),2)
  self.assertIn('#if DEBUG',read('App/ClubCommunityFixture.swift'))
