"""Bounded source contracts; these do not execute Swift or UI lifecycle code."""
from pathlib import Path
import json,unittest
ROOT=Path(__file__).resolve().parents[2]
CORE=(ROOT/'Core/ProjectCityStoryNodeRemoval.swift').read_text()
APP=(ROOT/'App/ProjectCityStoryNodeRemovalController.swift').read_text()
HOST=(ROOT/'App/ProjectEditDetailForms.swift').read_text()
class CityNodeRemovalContracts(unittest.TestCase):
    def test_city_personal_ordinary_scope(self):
        for text in ['draft.product == .city','draft.owner == .personal','chapter.schemaVersion==1','chapter.required==1','["opening"]','["ending"]','["_storyGame"]','["locationRequired"]']:
            self.assertIn(text,CORE)
    def test_raw_identity_and_ambiguity_guards(self):
        for text in ['Data($0.id.utf8)==Data(chapterID.utf8)','Data($0.id.utf8)==Data(nodeID.utf8)','ProjectEditPendingMaterials.validateIDs','Set(allBlocks.map(\\.id))','allBlocks.filter({ $0.nodeID==nodeID }).count==1']:
            self.assertIn(text,CORE)
    def test_graph_and_dependency_data_fail_closed(self):
        for text in ['routeMode','routeGraphJson','Failure.referenced','["node","grant","quest","graph"]','trimmed=="{}" || trimmed=="[]"','depth<32']:
            self.assertIn(text,CORE)
    def test_all_carry_over_contexts_inspected(self):
        for text in ['guarder.inspect(.object(draft.preserved))','guarder.inspect(.object(c.preserved))','guarder.inspect(.object(metadata))','guarder.inspect(.object(block.sourceFields ?? [:]))','pending.node.localMetadata','ticket.localMetadata']:
            self.assertIn(text,CORE)
    def test_exact_node_and_block_only_mutations(self):
        self.assertIn('next.chapters[ci].blocks?.remove(at:bi)',CORE)
        self.assertIn('next.chapters[ci].nodes.remove(at:ni)',CORE)
        self.assertNotIn('next.pendingMaterials =',CORE)
        self.assertNotIn('next.preserved',CORE)
        self.assertNotIn('removeNode(id:',CORE)
    def test_undo_entire_postimage_and_composition(self):
        self.assertIn('ProjectEditPendingMaterials.exactData(current)==expected',CORE)
        self.assertIn('return receipt.before',CORE)
        self.assertIn('ProjectEditPendingMaterials.exactData(later.before)==expected',CORE)
        self.assertIn('earlier.nodeIDs+later.nodeIDs',CORE)
    def test_owner_remount_and_active_scope(self):
        self.assertIn('ProjectCityStoryNodeRemovalHostIdentity(owner: ObjectIdentifier(model)',HOST)
        self.assertIn('let owner:ObjectIdentifier,chapter:Data',APP)
        self.assertIn('@Published private var active=false',APP)
        self.assertIn('active && !saveUnconfirmed',APP)
    def test_full_lease_revision_and_bytes(self):
        for text in ['model.captureStarterLease()','model.isCurrentStarterLease(capture.lease)','model.draftMutationRevision==capture.revision','ProjectEditPendingMaterials.exactData(model.draft)==capture.bytes','capture.controllerID==controllerID','capture.generation==generation']:
            self.assertIn(text,APP)
    def test_rendered_route_never_falls_through(self):
        self.assertIn('let handlesCityNodeRemoval = model.draft.product == .city && chapterOverride == nil && mediaScope == nil && starterLease == nil',HOST)
        self.assertIn('blocks[$0].kind == .node',HOST)
        self.assertIn('cityRemoval.interceptStory(offsets: offsets, captured: cityRemovalCapture)\n                                return',HOST)
        self.assertIn('cityRemoval.openNodes(offsets: offsets, captured: cityRemovalCapture)\n                            return',HOST)
    def test_one_selection_and_no_mixed_partial_delete(self):
        self.assertIn('offsets.count==1,nodeIDs.count==1',APP)
        self.assertIn('offsets.count==1,let index=offsets.first',APP)
        self.assertIn('if nodeIDs.isEmpty{return false}',APP)
    def test_confirmation_explicit_and_current(self):
        self.assertIn('guard isCurrent(original) else{return}',APP)
        self.assertIn('Button(role:.destructive){controller.confirm(value)}',APP)
        self.assertIn('.disabled(!controller.isCurrent(value))',APP)
        self.assertIn('controller.close(value)',APP)
    def test_monotonic_deadline_not_display_countdown(self):
        self.assertIn('ProcessInfo.processInfo.systemUptime',APP)
        self.assertIn('now()<value.deadline',APP)
        self.assertIn('deadline:now()+5',APP)
        self.assertIn('5_000_000_000',APP)
        self.assertNotIn('Date()',APP)
    def test_owned_local_save_and_unconfirmed_failure(self):
        self.assertIn('model.persistLocalChange(draft,lease:captured.lease)',APP)
        self.assertIn('model.draftMutationRevision==captured.revision+1',APP)
        self.assertIn('saveUnconfirmed=true;confirmation=nil;undo=nil',APP)
        self.assertNotIn('model.draft =',APP)
    def test_all_retirement_boundaries(self):
        for text in ['.onDisappear{controller.setActive(false)}','.onChange(of:phase)','.onChange(of:model.editorIncarnation)','.onChange(of:model.coordinator.session)','.onChange(of:model.canEdit)','.onChange(of:model.draftMutationRevision)']:
            self.assertIn(text,APP)
    def test_old_callback_identifiers(self):
        self.assertIn('undo?.id==value.id',APP)
        self.assertIn('confirmation?.id==value.id',APP)
        self.assertIn('if undo?.id==id',APP)
        self.assertIn('if confirmation?.id==original.id',APP)
    def test_no_network_persistent_timer_or_storage_reinterpretation(self):
        for forbidden in ['URLSession','URLRequest','HTTPTransport','UserDefaults','Keychain','storage.write','JSONDecoder','JSONEncoder']:
            self.assertNotIn(forbidden,CORE+APP)
    def test_free_explore_existing_path_still_present(self):
        self.assertIn('pendingNodeRemoval.open(offsets: offsets, captured: removalCapture)',HOST)
        self.assertIn('ProjectPendingNodeRemovalPresentation(controller: pendingNodeRemoval)',HOST)
        self.assertIn('let handlesPendingRemoval = usesPendingNodeRemoval',HOST)
    def test_catalog_named_bilingual_and_complete(self):
        rows=json.loads((ROOT/'Resources/ProjectCityStoryNodeRemoval.xcstrings').read_text())['strings'];self.assertEqual(len(rows),8)
        for key,value in rows.items():
            self.assertEqual(set(value['localizations']),{'en','zh-Hans'});self.assertIn('"'+key+'"',APP+HOST)
    def test_actual_model_regressions_are_authored(self):
        tests=(ROOT/'Tests/AppUnitTests/ProjectCityStoryNodeRemovalPresentationTests.swift').read_text()
        for name in ['testSameByteABARejectsConfirmationAndUndo','testReplacementEditorWithSameIDsHasDifferentHostIdentity','testEnvelopeOrPointerFailureIsUnconfirmedWithoutAdoptingDraft','testBackgroundReturnCannotReuseOldUndo','testMixedOrMultipleSelectionsNeverPartiallyDelete']:
            self.assertIn(name,tests)
if __name__=='__main__':unittest.main()
