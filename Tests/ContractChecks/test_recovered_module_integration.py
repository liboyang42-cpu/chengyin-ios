"""Integration contracts only; these checks never claim Swift or Apple execution."""
from pathlib import Path
import importlib.util,json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
class RecoveredModuleIntegrationTests(unittest.TestCase):
 def text(self,name):return (ROOT/name).read_text()
 def test_play_navigation_observes_session(self):
  s=self.text('App/ActivityDetailView.swift'); self.assertIn('SessionPlayRuntimeView(session: session, destination: .journey(.activity(id)))',s);self.assertIn('destination: .director(id)',s)
  s=self.text('App/SessionPlayRuntimeView.swift');self.assertIn('@ObservedObject var session',s);self.assertIn('.id(session.sessionRevision)',s)
 def test_production_play_capabilities_remain_empty(self):
  s=self.text('App/AppSession.swift');self.assertIn('runtimeDependencyFactory?.playService()',s);self.assertIn('retainedDependencies = injectedRuntimeDependencies ?? composition.sessionDependencies(context)',s);self.assertIn('enabled: accepted?.play ?? []',self.text('Core/RuntimeDependencyConfiguration.swift'));self.assertNotIn('enabled: [.reads',s)
 def test_production_merchant_factories_have_no_test_executor(self):
  s=self.text('App/AppSession.swift');self.assertIn('MerchantBusinessService(configuration:configuration,readTransport:transport)',s);self.assertNotIn('testingMutationTransport:',s);self.assertNotIn('execution: .',s)
 def test_private_readers_capture_exact_current_session(self):
  s=self.text('App/AppSession.swift')
  for name in ['MerchantBusiness','MerchantContent','CooperationFlow']:self.assertIn('self.current'+name+'Session == captured',s)
 def test_merchant_destinations_are_reachable(self):
  s=self.text('App/AccountView.swift')
  for arg in ['businessReader:session.merchantBusinessReader','contentService:session.merchantContentService','cooperationFlowReader:session.cooperationFlowReader']:self.assertIn(arg,s)
 def test_fixture_flags_also_bypass_restore(self):
  s=self.text('App/QuestifyApp.swift')
  for flag in ['--uitesting-merchant-business-fixture','--uitesting-merchant-content-fixture','--cooperation-flow-fixture']:self.assertEqual(s.count(flag),2)
 def test_supply_terms_are_never_guessed(self):
  s=self.text('App/MerchantCooperationSupplyView.swift');self.assertIn('guard let raw = source.termsMode',s);self.assertIn('TermsMode(rawValue: raw)',s);self.assertIn('supplyTermsUnknown',s);self.assertNotIn('?? .traffic',s)
 def test_supply_perks_require_read_and_session_fence(self):
  s=self.text('App/MerchantCooperationSupplyView.swift');self.assertIn('reader.read(.templates)',s);self.assertIn('reader.session == captured',s);self.assertIn('source.canEnroll',s);self.assertIn('source.canReconfirmOrPause',s)
 def test_configured_shards_cover_every_class_once(self):
  spec=importlib.util.spec_from_file_location('shards',ROOT/'tools/run_ui_shard.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  w=m.discover(ROOT/'Tests/AppUITests');groups=m.partition(w,m.DEFAULT_SHARD_COUNT);flat=sum(groups,[]);self.assertEqual(len(flat),len(set(flat)));self.assertEqual(set(flat),set(w))
 def test_expected_platform_floors_preserved(self):
  s=self.text('Package.swift');self.assertIn('.macOS(.v14)',s);self.assertIn('.iOS(.v17)',s)
 def test_no_second_cooperation_runtime_table(self):
  self.assertFalse((ROOT/'Resources/CooperationFlowLocalizations.xcstrings').exists());catalog=json.loads(self.text('Resources/Localizable.xcstrings'))['strings'];self.assertIn('coopflow.title',catalog)
 def test_business_intent_storage_is_deployment_scoped(self):
  s=self.text('App/AppSession.swift');self.assertIn('(storageScope?.service ?? "unconfigured") + "/MerchantBusiness/intents-v1.json"',s)
