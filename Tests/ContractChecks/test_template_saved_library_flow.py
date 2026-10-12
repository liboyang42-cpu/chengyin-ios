#!/usr/bin/env python3
"""Focused source contracts, not native behavior or compilation."""
from pathlib import Path
import json,re,sys,unittest
R=Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 and not sys.argv[1].startswith('-') else Path(__file__).resolve().parents[2]
CORE=(R/'Core/TemplateAuthoringSavedResult.swift').read_text();PANEL=(R/'App/TemplateAuthoringSavedResultPresentation.swift').read_text();FLOW=(R/'App/TemplateAuthoringSaveFlow.swift').read_text();HOST=(R/'App/TemplateAuthoringView.swift').read_text();LAUNCH=(R/'App/TemplateAuthoringLaunchView.swift').read_text();DOC=(R/'docs/template-saved-library-flow.md').read_text();LOC=json.loads((R/'Resources/CreatorSavedResult.xcstrings').read_text())['strings'];REG=json.loads((R/'docs/registration/template-saved-library-flow.json').read_text())
CT=(R/'Tests/CoreTests/TemplateAuthoringSavedResultTests.swift').read_text();AT=(R/'Tests/AppUnitTests/TemplateAuthoringSavedResultTests.swift').read_text()
class SavedLibrarySourceContracts(unittest.TestCase):
 def test_existing_receipt_is_authoritative(self):
  for x in ['coordinator.state == .acknowledged','coordinator.savedDraft','pending.savedDraft == receipt','receipt.matches(pending, session: session)','receipt.identity == identity','pending.identity == identity']:self.assertIn(x,CORE)
 def test_normal_root_is_one_additive_observation_and_node_branch_is_excluded(self):
  self.assertEqual(HOST.count('.preference(key: TemplateAuthoringSavedResultPreferenceKey.self,'),1);self.assertIn('eligible: onSavedDraft == nil',HOST)
  self.assertIn('if let onSavedDraft {',HOST);self.assertIn('Button(action: { onSavedDraft(saved) }',HOST)
 def test_normal_launch_reuses_full_existing_library_destination(self):
  self.assertEqual(LAUNCH.count('TemplateAuthoringSaveFlow('),1)
  for name in ['session.templateShelfCoordinator()','SessionOwnedMemberTemplateDetailView','SessionOwnedTemplateConfigurationView','SessionWorkshopCreatorConsentView','session.templateShelfViewIdentity']:
   self.assertEqual(LAUNCH.count(name),2)
  self.assertIn('templateAuthor.openMine',LAUNCH);self.assertIn('templateAuthor.openPrefab',LAUNCH)
 def test_no_new_network_storage_write_or_resubmit(self):
  source=CORE+PANEL+FLOW
  self.assertNotRegex(source,r'URLSession|requestAuthorization|coordinator\.(confirm|change|prepare|saveLocal|discardLocal|beginNewDraft|synchronizeSession)\(|store\.(save|discard)|transport\.send')
 def test_fresh_editable_visit_is_required_before_success(self):
  for x in ['latest.state == .editing','latest.editableNow()','admitted.identity == signal.result.receipt.identity','latest = nil; admitted = nil']:self.assertIn(x,FLOW)
  self.assertIn('A terminal receipt restored when opening an editor is not a new save event.',PANEL)
 def test_pinned_two_second_delay_and_cancel_are_real(self):
  self.assertIn('displayMilliseconds = 2_000',CORE);self.assertIn('Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)',FLOW)
  self.assertIn('schedule(TemplateAuthoringSavedResult.displayMilliseconds, closeAction(value))',FLOW)
  self.assertIn('guard !Task.isCancelled else { return }',FLOW);self.assertIn('task.cancel()',FLOW)
 def test_old_ticks_and_close_actions_are_generation_fenced(self):
  for x in ['self.active','!self.showingLibrary','self.presentation?.id == value.id','self.generation == value.generation','value.signal.isCurrent()','value.signal.result.isCurrent(in: self.coordinator)']:self.assertIn(x,FLOW)
  self.assertIn('self.invalidate(); self.latest = nil; self.showingLibrary = true',FLOW)
 def test_live_model_fences_owner_identity_and_metadata_before_propagation(self):
  for x in ['[weak model]','model.canReadMetadataDraft','model.metadataGeneration == metadata','model.mediaReviewGeneration == media','model.revision == revision','snapshot(model.draft) == draft','!model.busy','model.review == nil','model.coordinator.review == nil']:self.assertIn(x,PANEL)
  self.assertIn('lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8)',CORE);self.assertIn('lhs.authorizationRevision.utf8.elementsEqual(rhs.authorizationRevision.utf8)',CORE)
 def test_background_and_navigation_lifetimes_are_distinct(self):
  self.assertIn('func suspend() { active = false; invalidate() }',FLOW);self.assertIn('func retire() { suspend(); latest = nil; admitted = nil }',FLOW)
  self.assertIn('.onDisappear { controller.retire() }',FLOW);self.assertIn('else { controller.suspend() }',FLOW)
 def test_destination_replacement_and_result_ui_are_complete(self):
  for x in ['if controller.showingLibrary { library() }','TemplateAuthoringView(coordinator: coordinator','.onPreferenceChange(TemplateAuthoringSavedResultPreferenceKey.self)','.sheet(item: controller.presentationBinding())','close: controller.closeAction(value)']:self.assertIn(x,FLOW)
  self.assertIn('result.memberTemplateID.rawValue',PANEL);self.assertIn('.interactiveDismissDisabled(true)',PANEL)
 def test_bilingual_named_table_is_exact(self):
  keys=set(re.findall(r'"(templateSavedResult\.(?:title|detail|identity|destination|openLibrary))"',PANEL))
  self.assertEqual(keys,set(LOC));self.assertEqual(len(LOC),5);self.assertEqual(PANEL.count('tableName: "CreatorSavedResult"'),5)
  self.assertTrue(all(set(v['localizations'])=={'en','zh-Hans'} for v in LOC.values()));self.assertEqual(REG['tableName'],'CreatorSavedResult')
 def test_native_tests_cover_boundaries_without_claiming_execution(self):
  self.assertEqual(CT.count('func test'),12);self.assertEqual(AT.count('func test'),16)
  for x in ['advance(1999)','advance(1)','forceOldTick','testRestoredTerminalJournal','testProjectNodeReturnEligibility','testMissingIDSimulationUnknownAndPublish','testDisappearAndReentry']:self.assertIn(x,AT)
  self.assertIn('NOT_RUN',DOC)
 def test_no_unsupported_publish_receipt_claim(self):
  for x in ['NOT_IMPLEMENTED_DEPENDENCY','/api/template/publish','legacy acknowledged status alone is insufficient','No private Mini module']:self.assertIn(x,DOC)
 def test_registration_is_whole_not_fragment(self):
  self.assertEqual(len(REG['production_sources']),3);self.assertEqual(len(REG['app_tests']),1);self.assertEqual(len(REG['core_tests']),1)
  self.assertTrue(REG['actual_PBX_registration']);self.assertTrue(REG['CoreTests_directory_discovery'])
if __name__=='__main__':unittest.main(verbosity=2)
