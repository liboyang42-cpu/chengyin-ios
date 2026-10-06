"""Local pending material implementation boundaries; not Swift/Apple execution proof."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()

class ProjectEditPendingMaterialsChecks(unittest.TestCase):
    def test_full_native_node_and_metadata_are_retained_in_local_material(self):
        source=read('Core/ProjectEditPendingMaterials.swift')
        for token in ['public var node: ProjectEditNode', 'public var id: String { node.id }', 'case node, place',
                      'rows[index].node = node', 'copy.chapters[index].nodes.append(material.node)',
                      'copy.pendingMaterials?.removeAll', 'try validateIDs(draft)']:
            self.assertIn(token,source)
        self.assertNotIn('node.name =',source);self.assertNotIn('localMetadata = [:]',source)
    def test_only_named_incomplete_candidates_can_be_saved_and_formal_validation_remains(self):
        source=read('App/ProjectEditStarterController.swift').split('func finish(')[1].split('func close(')[0]
        self.assertIn('if ProjectEditStarterPolicy.canAddFormalNode(candidate)',source)
        self.assertIn('ProjectEditPendingMaterials.saving(candidate, in: next)',source)
        self.assertIn('guard model.persistLocalChange(next, lease: value.lease)',source)
        self.assertIn('saveUnconfirmed = true; return',source)
        view=read('App/ProjectEditStarterPresentation.swift')
        self.assertIn('controller.willSaveToPending(original)',view);self.assertIn('projectPending.saveMaterial',view)
    def test_new_envelopes_are_versioned_and_old_drafts_remain_readable(self):
        draft=read('Core/ProjectEditDraft.swift');store=read('Core/ProjectEditLocalStore.swift')
        self.assertIn('public var pendingMaterials: [ProjectEditPendingMaterial]?',draft)
        self.assertIn('version = draft.pendingMaterials == nil ? 1 : 2',store)
        self.assertIn('envelope.version == 1 && envelope.draft.pendingMaterials == nil',store)
        self.assertIn('envelope.version == 2 && envelope.draft.pendingMaterials != nil',store)
        self.assertIn('JSONEncoder().encode(envelope)',store)
        self.assertIn('envelope.accountID == session.accountID',store)
        self.assertIn('envelope.identity == identity',store)
    def test_save_success_is_observed_and_failure_does_not_replace_the_model(self):
        coordinator=read('Core/ProjectEditCoordinator.swift').split('public func saveLocal(')[1].split('public func prepare')[0]
        self.assertIn('-> Bool',coordinator)
        self.assertIn('try store.save(draft, session: session, identity: identity)',coordinator)
        self.assertIn('messageKey = "projectEdit.localSaved"; return true',coordinator)
        self.assertIn('messageKey = "projectEdit.localFailed"; return false',coordinator)
        model=read('App/ProjectEditView.swift').split('func persistLocalChange(')[1].split('func saveLocal()')[0]
        self.assertLess(model.index('autosave?.cancel()'),model.index('coordinator.saveLocal(value)'))
        self.assertLess(model.index('guard coordinator.saveLocal(value)'),model.index('draft = value'))
        self.assertIn('value.baseRevision.utf8.elementsEqual(draft.baseRevision.utf8)',model)
    def test_city_requires_explicit_story_gap_while_free_uses_node_list(self):
        core=read('Core/ProjectEditPendingMaterials.swift')
        for token in ['draft.product == .city','draft.chapters[index].hasRealStory','blocks.map(\\.id) == expectedBlocks',
                      'blocks.insert(.init(kind: .node, nodeID: material.id), at: insertion)',
                      'draft.chapters[index].blocks == nil, blockID == nil, expectedBlocks == nil']:
            self.assertIn(token,core)
        controller=read('App/ProjectEditPendingController.swift')
        self.assertIn('slot.topologyRevision == model.storyTopologyRevision',controller)
        self.assertIn('open(fresh, kind: .story(chapterID: id))',controller)
        self.assertIn('before: slot.beforeBlockID, expectedBlocks: slot.blocks',controller)
        view=read('App/ProjectEditPendingPresentation.swift')
        self.assertIn('controller.slot(original, before: before)',view)
        self.assertIn('controller.insert(slot)',view)
    def test_stale_targets_and_old_sheet_callbacks_are_bound_to_original_bytes_and_id(self):
        source=read('App/ProjectEditPendingController.swift')
        for token in ['let materialRevision: Int','let bytes: Data','ProjectEditPendingMaterials.exactData(row)',
                      'materialRevision: model.materialRevision','destination?.id == value.id',
                      'destination?.target == value.target','guard self.isCurrent(value), value.kind == .edit']:
            self.assertIn(token,source)
        host=read('App/ProjectEditView.swift')
        self.assertIn('ProjectEditPendingMaterials.exactData(oldValue.pendingMaterials)',host)
        self.assertIn('materialRevision += 1',host);self.assertIn('storyTopologyRevision += 1',host)
        view=read('App/ProjectEditPendingPresentation.swift');self.assertIn('let original = controller.destination',view)
        self.assertIn('controller.close(original)',view);self.assertNotIn('onDismiss:',view)
    def test_payload_exclusion_and_mode_copy_boundaries_are_explicit(self):
        self.assertNotIn('pendingMaterials',read('Core/ProjectEditContract.swift'))
        self.assertIn('copy.pendingMaterials?[index].node.localMetadata.removeValue(forKey: "id")',read('Core/ProjectDraftModeCopy.swift'))
        self.assertIn('confirmation.draft.pendingMaterials',read('App/ProjectEditDetailForms.swift'))
        for path in ['App/ProjectEditPendingController.swift','App/ProjectEditPendingPresentation.swift','Core/ProjectEditPendingMaterials.swift']:
            source=read(path)
            for forbidden in ['URLSession','AsyncImage','requestAuthorization','startUpdatingLocation','microphone','upload(']:self.assertNotIn(forbidden,source)
    def test_bilingual_and_meaningful_storage_and_real_ui_regressions_exist(self):
        strings=json.loads(read('Resources/ProjectEditPendingLocalizations.fragment.json'))['strings'];self.assertEqual(len(strings),18)
        for row in strings.values():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
        for path,count in [('Tests/CoreTests/ProjectEditPendingMaterialsTests.swift',10),('Tests/AppUnitTests/ProjectEditPendingControllerTests.swift',10),('Tests/AppUITests/ProjectEditPendingFlowTests.swift',2),('Tests/AppUITests/ProjectEditPendingRestoreFlowTests.swift',1)]:self.assertEqual(read(path).count('func test'),count)
        tests=read('Tests/AppUnitTests/ProjectEditPendingControllerTests.swift')
        for token in ['storage.failAt = storage.writes + 2','Cancelled autosave must not overwrite the uncertain envelope','"unicodeABA"','"deleteABA"','controller.insert(stale)','XCTAssertTrue(model.coordinator.isLocked)']:
            self.assertIn(token,tests)
        ui=read('Tests/AppUITests/ProjectEditPendingFlowTests.swift') + '\n' + read('Tests/AppUITests/ProjectEditPendingRestoreFlowTests.swift')
        for token in ['tap("projectEdit.restore"','tap("projectPending.close"','tap("projectPending.insert.end"','XCTAssertEqual(snapshot.submissionCount, 0)','XCTAssertNil(try inspect(app).savedDraft']:
            self.assertIn(token,ui)

if __name__=='__main__':unittest.main()
