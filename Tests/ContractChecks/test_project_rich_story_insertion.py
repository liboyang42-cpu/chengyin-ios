"""Bounded source checks only; no Swift compile/runtime claim."""
from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[2]
class RichStoryInsertionSourceTests(unittest.TestCase):
    def setUp(self):
        self.core=(ROOT/'Core/ProjectRichStoryInsertion.swift').read_text();self.app=(ROOT/'App/ProjectRichStoryInsertionButton.swift').read_text();self.form=(ROOT/'App/ProjectEditDetailForms.swift').read_text()
    def test_reuses_existing_anchor_capacity_and_default_contracts(self):
        for token in ['private let insertion: ProjectStoryTextInsertion','insertion.inserting(blockID: blockID, in: draft)','ProjectEditRichStoryContract.richKinds.contains(kind)','ProjectEditRichStoryContract.defaultBlock(kind)']:
            self.assertIn(token,self.core)
        self.assertNotIn('setField(',self.core)
    def test_exact_target_and_generated_identity(self):
        for token in ['id.utf8.elementsEqual(chapterID.utf8)','id.utf8.elementsEqual(blockID.utf8)','block.id = blockID','blocks?[bi] = block']:
            self.assertIn(token,self.core)
    def test_existing_six_kinds_drive_menu(self):
        self.assertIn('ForEach(ProjectEditRichStoryContract.richKinds',self.app)
        self.assertIn('action?.insert(kind)',self.app)
    def test_rendered_action_owner_revision_checks_before_and_after_id_generation(self):
        self.assertEqual(self.app.count('model.isCurrentStarterLease(lease)'),2)
        self.assertEqual(self.app.count('model.draftMutationRevision == revision'),2)
        self.assertIn('snapshot.isCurrent(in: model.draft)',self.app)
        self.assertIn('blockID: makeID()',self.app)
    def test_only_one_working_draft_write(self):
        self.assertEqual(self.app.count('model.draft = next'),1)
        for token in ['URLSession','transport','upload(', 'saveLocal(', 'Task {']:
            self.assertNotIn(token,self.app+self.core)
    def test_ordinary_gap_mount_retains_other_gap_actions(self):
        self.assertIn('let rich = ordinary ? ProjectRichStoryInsertionAction(',self.form)
        self.assertIn('if ordinary { ProjectRichStoryInsertionButton(action: rich, beforeBlockID: blockID) }',self.form)
        self.assertIn('text == nil && rich == nil && image == nil && audio == nil && template == nil',self.form)
        for token in ['ProjectStoryTextInsertionButton(action: text','projectStoryImage.insertBefore.','projectStoryAudio.insertBefore.','projectStoryTemplate.insertBefore.']:
            self.assertIn(token,self.form)
    def test_new_menu_title_bilingual(self):
        strings=json.loads((ROOT/'Resources/ProjectRichStoryInsertion.xcstrings').read_text())['strings']
        self.assertEqual(set(strings),{'projectRichStoryInsertion.before'})
        self.assertEqual(set(strings['projectRichStoryInsertion.before']['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
