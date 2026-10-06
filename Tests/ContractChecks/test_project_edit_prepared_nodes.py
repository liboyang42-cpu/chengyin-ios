"""Captured node request review source contracts, not Apple execution."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()

class ProjectEditPreparedNodeChecks(unittest.TestCase):
    def test_projection_reads_payload_order_and_keeps_missing_empty_null_distinct(self):
        core=read('Core/ProjectEditPreparedNodes.swift')
        self.assertIn('public init(payload: [String: ProjectEditJSON]) { raw = payload["chapters"] }',core)
        self.assertIn('raw?.array?.enumerated().map',core)
        self.assertIn('case name, description, address, longitude, latitude, imgUrl, nodeTime, templateId, sortID',core)
        self.assertIn('raw.object?[field.rawValue]',core)
        self.assertIn('value.isNaN { return nil }',core)
        for forbidden in ['draft.', 'ProjectEditContract.payload', '.sorted(', 'trimmingCharacters', 'URL(']:self.assertNotIn(forbidden,core)
    def test_review_uses_original_confirmation_payload_and_labels_draft_context(self):
        view=read('App/ProjectEditDetailForms.swift')
        self.assertIn('ProjectEditPreparedNodesView(value: .init(payload: confirmation.payload))',view)
        self.assertIn('ProjectEditPreparedPayloadView(payload: confirmation.payload)',view)
        self.assertIn('Text("projectPrepared.draftContext")',view)
        review=view.split('struct ProjectEditReviewView:')[1]
        self.assertNotIn('ForEach(chapter.nodes) { node in',review)
        source=read('App/ProjectEditPreparedReview.swift')
        self.assertIn('ProjectEditReviewView(confirmation: original',source)
        self.assertIn('Text(verbatim: text)',source)
        for forbidden in ['AsyncImage','URLSession','upload(','openURL']:self.assertNotIn(forbidden,source)
    def test_old_dismissal_and_queued_confirmation_are_id_and_owner_bound(self):
        source=read('App/ProjectEditPreparedReview.swift')
        for token in ['let original = model.confirmation','model.cancelReview(original)',
                      'confirmation?.id == value.id && coordinator.confirmation?.id == value.id',
                      'reviewLease.session == coordinator.session','reviewLease.identity == coordinator.identity',
                      'reviewLease.incarnation == editorIncarnation','guard ownsReview(value), let current',
                      'return current == captured']:
            self.assertIn(token,source)
        self.assertNotIn('onDismiss:',source)
        model=read('App/ProjectEditView.swift')
        self.assertIn('guard reviewIsCurrent(value), canEdit, !busy else',model)
        self.assertNotIn('onDismiss: { model.coordinator.cancelReview() }',model)
    def test_raw_edit_restore_and_discard_invalidate_before_reusing_prepared_review(self):
        model=read('App/ProjectEditView.swift')
        for token in ['ProjectEditPendingMaterials.exactData(oldValue)',
                      'if before == nil || after == nil || before != after { cancelReview() }',
                      'func restore() { guard ownsVisit else { return }; cancelReview(); editorIncarnation = UUID()',
                      'func discard() { guard ownsVisit else { return }; cancelReview(); editorIncarnation = UUID()']:
            self.assertIn(token,model)
        self.assertIn('guard canEdit, let session',read('App/ProjectEditPreparedReview.swift'))
        self.assertNotIn('guard fullEdit',read('App/ProjectEditPreparedReview.swift'))
    def test_local_saving_result_is_explicit_and_real_node_save_uses_captured_lease(self):
        model=read('App/ProjectEditView.swift')
        self.assertIn('let saved = coordinator.saveLocal(draft); coordinator.prepare(draft)',model)
        self.assertIn('reviewLocalSaveConfirmed = saved',model)
        view=read('App/ProjectEditDetailForms.swift')
        self.assertIn('if !localSaveConfirmed',view)
        self.assertIn('model.currentReviewLease() == lease, model.fullEdit',view)
        self.assertIn('targetChapter.wrappedValue.nodes.contains(where: { $0.id == nodeID })',view)
        self.assertIn('projectPrepared.saveNodeDraft',view)
    def test_actual_source_fields_and_regressions_remain_no_new_wire_fields(self):
        core=read('Core/ProjectEditContract.swift')
        for field in ['"description": node.description','"imgUrl": node.imgUrl','"nodeTime": .number(Decimal(node.nodeTime))','row["templateId"] = .number(Decimal(id))']:
            self.assertIn(field,core)
        for path,count in [('Tests/CoreTests/ProjectEditPreparedNodesTests.swift',6),('Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift',7),('Tests/AppUITests/ProjectEditPreparedNodesFlowTests.swift',2)]:self.assertEqual(read(path).count('func test'),count)
        tests=read('Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift')
        for token in ['storage.failAt = storage.writes + 2','model.draft.chapters[0].blocks?.swapAt(1, 2)',
                      'await model.submit(old); model.cancelReview(old)','XCTAssertFalse(model.reviewLocalSaveConfirmed)',
                      'XCTAssertTrue(fresh.canRestore); fresh.restore(); fresh.review()']:
            self.assertIn(token,tests)
    def test_all_new_labels_are_bilingual(self):
        strings=json.loads(read('Resources/ProjectEditPreparedLocalizations.fragment.json'))['strings']
        self.assertEqual(len(strings),23)
        for value in strings.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})

if __name__=='__main__':unittest.main()
