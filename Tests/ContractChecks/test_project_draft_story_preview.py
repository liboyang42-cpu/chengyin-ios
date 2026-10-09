"""Static contracts for local author story-content preview, not Swift execution."""
from pathlib import Path
import json
import re
import unittest
ROOT=Path(__file__).resolve().parents[2]
CORE=(ROOT/'Core/ProjectDraftStoryPreview.swift').read_text()
UI=(ROOT/'App/ProjectDraftStoryPreviewView.swift').read_text()
HOST=(ROOT/'App/ProjectEditView.swift').read_text()
CT=(ROOT/'Tests/CoreTests/ProjectDraftStoryPreviewTests.swift').read_text()
AT=(ROOT/'Tests/AppUnitTests/ProjectDraftStoryPreviewPresentationTests.swift').read_text()
class DraftStoryPreviewContracts(unittest.TestCase):
    def test_existing_editor_has_one_preview_entry(self):
        self.assertEqual(HOST.count('ProjectDraftStoryPreviewEntry(model: model)'),1)
        self.assertIn('ProjectEditPendingSection(model: model, controller: pending)',HOST)
        self.assertIn('chapterStructure(opening: opening)',HOST)
    def test_projected_data_is_current_local_draft(self):
        self.assertIn('ProjectDraftStoryPreview(draft: model.draft)',UI)
        self.assertIn('sourceBytes = bytes',CORE)
        self.assertIn('ProjectEditPendingMaterials.exactData(draft) == sourceBytes',CORE)
    def test_no_network_media_runtime_or_write_adapters(self):
        for forbidden in ['URLSession','URLRequest','AsyncImage','PlatformAudioHost','PlayExperienceCoordinator','JourneyCheckCoordinator','.submit(','.saveLocal(','.register(','model.draft =','withAnimation','Task {']:
            self.assertNotIn(forbidden,CORE+UI)
    def test_condition_labels_do_not_evaluate_or_hide_authored_text(self):
        self.assertIn('let conditional = condition != nil && condition != .null',CORE)
        self.assertIn('text: block.content, conditional: conditional',CORE)
        self.assertIn('if row.conditional { text("conditional")',UI)
    def test_explicit_block_order_and_legacy_fallback(self):
        self.assertIn('for block in blocks { rows += Self.rows',CORE)
        self.assertIn('if !chapter.description.isEmpty',CORE)
        self.assertIn('for node in chapter.nodes { rows.append',CORE)
        self.assertIn('unplacedNodeCount: unplaced',CORE)
    def test_duplicate_id_and_resource_bounds(self):
        for expected in ['Self.unique(chapterIDs)','Self.unique(nodeIDs)','Self.unique(($0.blocks ?? []).map(\\.id))','draft.chapters.count <= 128','<= 512','<= 200','<= 4096','bytes.count <= 1024 * 1024']:
            self.assertIn(expected,CORE)
    def test_branch_and_unknown_routes_do_not_fake_rehearsal(self):
        self.assertIn('mode == .string("BRANCH_GRAPH") { reason = .branchRoute',CORE)
        self.assertIn('mode == .string("LINEAR")',CORE)
        self.assertIn('reason = .unsupportedRoute',CORE)
    def test_unsupported_and_empty_content_have_visible_states(self):
        for key in ['unsupportedChapter','unsupportedBlock','emptyChapter','emptyText','emptyAlbum','emptyCaption','emptyMedia','empty']:
            self.assertIn('text("'+key+'")',UI) if key!='emptyMedia' else self.assertIn('"emptyMedia"',UI)
    def test_media_projection_omits_urls(self):
        row=CORE.split('public struct Row: Identifiable {',1)[1].split('    public struct Chapter',1)[0]
        self.assertNotIn('url',row.lower())
        self.assertIn('details: captions',CORE)
        self.assertIn('text("mediaScope")',UI)
    def test_full_edit_owner_exact_draft_and_controller_fences(self):
        for expected in ['model.fullEdit','model.captureStarterLease()','capture.controller == identity','capture.generation == generation','model.isCurrentStarterLease(capture.lease)','model.draftMutationRevision == capture.revision','capture.projection.isCurrent(in: model.draft)']:
            self.assertIn(expected,UI)
    def test_stale_taps_and_selection_are_fenced(self):
        self.assertIn('let captured = controller.capture(projection)',UI)
        self.assertIn('guard presentation == nil, current(capture)',UI)
        self.assertIn('guard isCurrent(original), original.capture.projection.chapters.indices.contains(index)',UI)
        self.assertIn('guard presentation?.id == original.id else { return }; retire()',UI)
    def test_back_owner_and_draft_changes_retire_presentation(self):
        for expected in ['.onChange(of: model.draftMutationRevision)','.onChange(of: model.editorIncarnation)','.onChange(of: model.coordinator.session)','.onDisappear { controller.retire() }','.onDisappear { controller.close(original) }']:
            self.assertIn(expected,UI)
    def test_previous_next_and_picker_keep_existing_order(self):
        self.assertIn('controller.selectedChapter - 1',UI);self.assertIn('controller.selectedChapter + 1',UI)
        self.assertIn('ForEach(projection.chapters.indices',UI);self.assertNotIn('.sorted(',CORE)
    def test_no_text_truncation_or_condition_substitution(self):
        self.assertIn('Text(verbatim: row.text)',UI);self.assertNotIn('.lineLimit(',UI)
        self.assertNotIn('replacingOccurrences',CORE)
    def test_catalog_covers_fixed_and_dynamic_cases(self):
        strings=json.loads((ROOT/'Resources/ProjectDraftStoryPreview.xcstrings').read_text())['strings']
        keys={'projectDraftStoryPreview.'+x for x in re.findall(r'text\("([A-Za-z]+)"\)',UI)}
        for prefix,values in [('kind',['text','voice','narrative','node','image','audio','album','thought','mood','odd','reveal','unsupported']),('role',['chapter','opening','ending','unsupported']),('reason',['identity','limit','branchRoute','unsupportedRoute'])]:
            keys.update('projectDraftStoryPreview.'+prefix+'.'+x for x in values)
        self.assertFalse(keys-set(strings));self.assertEqual(len(strings),46)
        for entry in strings.values():
            self.assertEqual(set(entry['localizations']),{'en','zh-Hans'})
            for v in entry['localizations'].values():self.assertTrue(v['stringUnit']['value'].strip())
    def test_core_regressions_cover_actual_projection(self):
        for name in ['CurrentUnsavedText','LegacyDescriptionThenNodes','ExplicitBlocksRemain','ConditionalContentAlwaysVisible','MediaURLsAreExcluded','DuplicateAndCanonicalEquivalent','ExactUnsavedBytesFence','PendingMaterialsAreExcluded']:
            self.assertIn(name,CT)
    def test_hosted_tests_use_actual_controller_boundaries(self):
        for name in ['PreviewUsesCurrentUnsavedDraft','QueuedOpeningAfterDeparture','ForeignController','OwnerEpochLogoutAndLeave','SameByteABA','OldCallbacksCannotCloseNew','UnsupportedBranch']:
            self.assertIn(name,AT)
        self.assertIn('ProjectDraftStoryPreviewController',AT)
    def test_conditional_fallback_rows_keep_unevaluated_label(self):
        for kind in ['unsupported', 'album', 'thought']:
            self.assertIn('row(start, .'+kind+', conditional: conditional, unsupported: true)', CORE)
        for name in ['UnresolvedConditionalNode', 'UnresolvedConditionalThought', 'MalformedAndOverLimitConditionalAlbum']:
            self.assertIn(name, CT)
    def test_thought_reference_uses_exact_bytes_and_rejects_alias_declarations(self):
        self.assertIn('thought.0.utf8.elementsEqual(key.utf8)', CORE)
        self.assertIn('labels[key] == nil', CORE)
        self.assertIn('labels[key] = (key, name,', CORE)
        self.assertIn('ThoughtReferencesRequireExactUTF8Identity', CT)
        self.assertIn('CanonicalEquivalentThoughtDeclarationsRemainAmbiguous', CT)
if __name__=='__main__':unittest.main()
