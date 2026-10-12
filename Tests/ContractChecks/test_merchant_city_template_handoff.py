"""Supplementary source assertions, not Swift compilation or runtime testing."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def read(path): return (ROOT/path).read_text()
class CityTemplateHandoffContracts(unittest.TestCase):
 def test_01_no_new_network_or_mutation_dispatch(self):
  source='\n'.join(read(p) for p in ['Core/MerchantCityTemplateHandoff.swift','App/MerchantCityTemplateHandoffModel.swift','App/MerchantCityTemplateHandoffView.swift'])
  for forbidden in ['URLSession','https://','/api/','saveTemplateReviewed(','.perform(','.confirm(','.saveExample(','UserDefaults','FileManager']: self.assertNotIn(forbidden,source)
 def test_02_exact_native_full_editor_is_reused(self):
  s=read('App/MerchantCityTemplateHandoffView.swift')
  self.assertIn('MerchantOperationsDocumentView(reader: original.launch.reader, destination: .template(nil)',s)
  self.assertIn('imageHost: original.launch.imageHost',s);self.assertIn('templateAssistFactory: original.launch.templateAssistFactory',s)
 def test_03_explicit_return_does_not_save(self):
  s=read('App/MerchantCityTemplateHandoffView.swift')
  self.assertIn('Button("merchant.cityTemplate.useSaved")',s);self.assertIn('.disabled(!action.canReturn(coordinator))',s)
 def test_04_new_editor_identity_is_required(self):
  s=read('App/MerchantCityTemplateHandoffModel.swift')
  for marker in ['coordinator.destination == .template(nil)','editor === coordinator','ObjectIdentifier(coordinator.reader) == ObjectIdentifier(original.launch.reader)']: self.assertIn(marker,s)
 def test_05_saved_document_and_current_draft_agree(self):
  s=read('App/MerchantCityTemplateHandoffModel.swift')
  for marker in ['!coordinator.isDirty','coordinator.baseline == .template(value)','coordinator.document == .draft(.template(value))','c.draftIdentity == value.identity','candidateIsCurrent(candidate, original: original)']: self.assertIn(marker,s)
 def test_06_unknown_save_and_parent_replay_locks_not_cleared(self):
  s=read('App/MerchantCityTemplateHandoffModel.swift')
  for marker in ['!coordinator.isLocked','!coordinator.reader.hasPending(.template(nil))','!coordinator.reader.hasPending(.template(id))','binding.canReload()']: self.assertIn(marker,s)
  self.assertNotIn('coordinator.invalidate()',s);self.assertNotIn('coordinator.load()',s)
 def test_07_dual_scope_merchant_and_permission_fences(self):
  s=read('App/MerchantCityTemplateHandoffModel.swift')
  for marker in ['binding.scope() == original.parent.scope','original.launch.reader.scope == original.readerScope','access.identity.merchantID == original.merchantID','access.allows(.template(candidate.id))','binding.draft() == original.local']: self.assertIn(marker,s)
 def test_08_read_retry_never_uses_returned_object_as_row(self):
  s=read('App/MerchantCityTemplateHandoffModel.swift')
  self.assertIn('await binding.reload()',s);self.assertIn('expectedSnapshot = binding.snapshot()',s)
  self.assertIn('MerchantCityTemplateHandoff.returnedTemplate(id: candidate.id, snapshot: refreshed',s)
  self.assertNotIn('.append(',s)
 def test_09_unique_owned_id_and_album_source_fields(self):
  s=read('Core/MerchantCityTemplateHandoff.swift')
  for marker in ['matches.count == 1','row["advancedConfigJson"]','config["album"]["enabled"]','MerchantCityTemplateReturnFailure.albumOnly']: self.assertIn(marker,s)
 def test_10_raw_bytes_and_observation_revision_are_preserved(self):
  s=read('Core/MerchantCityTemplateHandoff.swift')
  self.assertIn('value.utf8.elementsEqual(other.utf8)',s);self.assertIn('lhs.observedAt == rhs.observedAt',s)
 def test_11_late_completion_is_generation_fenced(self):
  s=read('App/MerchantCityTemplateHandoffModel.swift')
  self.assertGreaterEqual(s.count('ticket == generation'),5);self.assertIn('opening?.id == original.id',s)
  self.assertIn('generation += 1; opening = nil',s)
 def test_12_lifecycle_revokes_return(self):
  s=read('App/MerchantCityTemplateHandoffView.swift')
  for marker in ['.onChange(of: binding.scope())','.onChange(of: original.launch.reader.scope)','if phase == .active && isVisible { model.activate() } else { model.deactivate() }','.onDisappear { isVisible = false; model.deactivate() }']: self.assertIn(marker,s)
 def test_13_synthetic_parent_cannot_be_a_live_return(self):
  s=read('App/MerchantCityTemplateHandoffModel.swift')
  self.assertIn('var isOfflineFixture = false',s);self.assertIn('launch.reader.isOfflineExample == binding.isOfflineFixture',s)
  self.assertTrue(read('App/MerchantCityTemplateHandoffFixture.swift').startswith('#if DEBUG'))
 def test_14_localization_keys_have_both_languages(self):
  catalog=json.loads(read('Resources/MerchantCityTemplateHandoffLocalizations.fragment.json'))
  self.assertEqual(len(catalog),17)
  for value in catalog.values():
   for language in ['en','zh-Hans']: self.assertTrue(value['localizations'][language]['stringUnit']['value'])
  source='\n'.join(read(p) for p in ['Core/MerchantCityTemplateHandoff.swift','App/MerchantCityTemplateHandoffView.swift','App/MerchantCityTemplateHandoffFixture.swift'])
  keys=set(re.findall(r'(?:Text\(|Button\(|return |\.appNavigationTitle\()"(merchant\.cityTemplate\.[^"]+)"',source))
  self.assertTrue(keys <= set(catalog), keys-set(catalog))
 def test_15_native_test_scenarios_are_authored_not_claimed_run(self):
  for path,count in [('Tests/CoreTests/MerchantCityTemplateHandoffTests.swift',12),('Tests/AppUnitTests/MerchantCityTemplateHandoffPresentationTests.swift',19),('Tests/AppUITests/MerchantCityTemplateHandoffFlowTests.swift',3)]:
   self.assertEqual(len(re.findall(r'func test\w+\(',read(path))),count)
  self.assertIn('NOT_RUN',read('docs/merchant-city-template-handoff.md'))
 def test_16_stable_editor_and_fixture_own_presentation_not_lazy_entry(self):
  host=read('App/MerchantContentEditor.swift');view=read('App/MerchantCityTemplateHandoffView.swift');fixture=read('App/MerchantCityTemplateHandoffFixture.swift')
  self.assertIn('@StateObject private var cityTemplateHandoff = MerchantCityTemplateHandoffModel()',host)
  self.assertIn('.modifier(MerchantCityTemplateHandoffPresentation(model: cityTemplateHandoff, binding: placementTemplateBinding))',host)
  self.assertIn('MerchantCityTemplateHandoffField(binding: placementTemplateBinding, model: cityTemplateHandoff)',host)
  row=view.split('@MainActor struct MerchantCityTemplateHandoffField')[1].split('@MainActor struct MerchantCityTemplateHandoffPresentation')[0]
  for marker in ['@StateObject', '.sheet(', '.onDisappear', '.onChange']:self.assertNotIn(marker,row)
  self.assertIn('.id(model.opening?.id)',view);self.assertIn('content.background {',view)
  self.assertIn('.modifier(MerchantCityTemplateHandoffPresentation(model: handoff, binding: state.binding))',fixture)
 def test_17_old_sheet_callbacks_are_exact_opening_scoped(self):
  view=read('App/MerchantCityTemplateHandoffView.swift');model=read('App/MerchantCityTemplateHandoffModel.swift')
  host=view.split('@MainActor private struct MerchantCityTemplateHandoffHost')[1]
  self.assertNotIn('model.close()',host);self.assertEqual(host.count('model.close(id: original.id)'),5)
  self.assertIn('self?.close(id: presentedID)',model)
  self.assertIn('guard opening?.id == id else { return }; close()',model)
  retry=model.split('func retryRead(_ original: Opening')[1]
  self.assertLess(retry.index('guard opening?.id == original.id else { return }'),retry.index('issue = .contextChanged'))
 def test_18_queued_actions_require_active_generation_before_protocol(self):
  model=(ROOT/'App/MerchantCityTemplateHandoffModel.swift').read_text()
  view=(ROOT/'App/MerchantCityTemplateHandoffView.swift').read_text()
  self.assertEqual(model.count('guard active, permit == nil || permit == generation else { return }'),2)
  self.assertIn('func deactivate() {\n        active = false\n        close()',model)
  self.assertEqual(view.count('let permit = model.generation'),2)
  self.assertIn('guard model.accepts(permit) else { return }',view)
  self.assertIn('if scenePhase == .active { model.activate() } else { model.deactivate() }',view)
 def test_19_hidden_host_cannot_reactivate_on_scene_foreground(self):
  view=read('App/MerchantCityTemplateHandoffView.swift')
  owner=view.split('struct MerchantCityTemplateHandoffPresentation: ViewModifier',1)[1].split('@MainActor private struct MerchantCityTemplateHandoffHost',1)[0]
  self.assertIn('@State private var isVisible = false',owner)
  self.assertIn('.onAppear {\n            isVisible = true',owner)
  self.assertIn('if phase == .active && isVisible { model.activate() } else { model.deactivate() }',owner)
  self.assertIn('.onDisappear { isVisible = false; model.deactivate() }',owner)
  self.assertNotIn('if phase == .active { model.activate() }',owner)
if __name__=='__main__': unittest.main(verbosity=2)
