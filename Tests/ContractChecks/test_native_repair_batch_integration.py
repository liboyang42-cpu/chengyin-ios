"""Source integration guards only; no compiler, Apple runtime or network evidence."""
from pathlib import Path
import json,unittest
R=Path(__file__).resolve().parents[2]
class NativeRepairBatchIntegrationTests(unittest.TestCase):
 def read(self,p):return (R/p).read_text()
 def test_object_host_observes_epoch_and_is_dormant(self):
  s=self.read('App/SessionObjectCardsView.swift');self.assertIn('@EnvironmentObject private var session',s);self.assertIn('.id(session.objectCardReader.scope)',s)
  s=self.read('App/AppSession.swift');self.assertIn('ObjectCardSessionReader(service: nil',s);self.assertIn('self.currentObjectCardSession == captured',s)
  self.assertIn('}).id(session.sessionRevision)',self.read('App/QuestifyApp.swift'))
 def test_badge_wall_has_reviewed_media_boundary(self):
  self.assertIn('ObjectBadgeWallView(reader: reader)',self.read('App/ProfileAccountLinks.swift'))
  self.assertNotIn('AsyncImage(',self.read('App/ObjectCardViews.swift'))
 def test_merchant_workspace_is_reachable_with_scoped_recovery(self):
  self.assertIn('engagementReader:session.merchantEngagementReader',self.read('App/AccountView.swift'))
  self.assertIn('.id(engagementReader.scope)',self.read('App/MerchantHomeView.swift'))
  s=self.read('App/AppSession.swift');self.assertIn('self.currentMerchantBusinessSession == captured',s);self.assertIn('(storageScope?.service ?? "unconfigured") + "/MerchantBusiness/export-tasks-v1.json"',s)
  self.assertNotIn('testingActionTransport:',s)
 def test_debug_hosts_do_not_construct_production_session(self):
  self.assertEqual(self.read('App/QuestifyApp.swift').count('--uitesting-merchant-engagement-fixture'),2)
  s=self.read('App/ModuleFixtureSupport.swift');self.assertIn('case objectCards',s);self.assertIn('case .objectCards: ObjectCardFixtureHostView()',s)
 def test_new_catalog_keys_match_fragments(self):
  c=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
  for f in ['ObjectCardLocalizations.fragment.json','NearbyTeamWriteLocalizations.fragment.json','MerchantEngagementLocalizations.fragment.json']:
   d=json.loads(self.read('Resources/'+f))
   for k,v in d.get('strings',d).items():self.assertEqual(c[k],v,k)
 def test_all_write_device_media_grants_remain_off(self):
  s=self.read('App/AppSession.swift');self.assertIn('writeApproval: OperationEndpointApproval? = nil',s);self.assertIn('writeEvidence: ((NearbyTeamReview) async throws -> NearbyTeamWriteEvidence)? = nil',s)
  self.assertIn('protectedDispatch: CoopFlowProtectedDispatch? = nil',self.read('Core/CooperationFlowService.swift'))
  self.assertIn('var cameraSelectionEnabled = false',self.read('App/MerchantEvidenceSelectionView.swift'))
 def test_unknown_merchant_and_scanner_unlock_only_proven_unsent(self):
  for p in ['Core/MerchantBusinessCoordinator.swift','Core/MerchantRedemptionContext.swift']:
   self.assertIn('MerchantMutationFailureDisposition.provesNoDispatch(error)',self.read(p))
