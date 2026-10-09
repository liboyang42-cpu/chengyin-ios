"""Source contracts only; not Swift compilation or native execution."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class NodeDurationSourceTests(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT/'Core/ProjectNodeDuration.swift').read_text()
        self.app = (ROOT/'App/ProjectNodeDurationField.swift').read_text()
        self.form = (ROOT/'App/ProjectEditDetailForms.swift').read_text()
    def test_wire_integer_minutes_bound(self):
        for token in ['maximumMinutes = 2_147_483_647', '(1...10).contains(text.utf8.count)', 'text.utf8.allSatisfy({ (48...57).contains($0) })', 'value <= maximumMinutes']:
            self.assertIn(token,self.core)
        for token in ['trimmingCharacters', 'Double(', 'Float(']: self.assertNotIn(token,self.core)
    def test_exact_identity_and_whole_draft_fences(self):
        for token in ['id.utf8.elementsEqual(chapterID.utf8)', 'filter({ $0.id == nodeID }).count == 1', 'id.utf8.elementsEqual(nodeID.utf8)', 'ProjectEditPendingMaterials.exactData(draft) == bytes']:
            self.assertIn(token,self.core)
    def test_only_node_time_mutates_without_unit_conversion(self):
        self.assertIn('guard value != minutes else { return draft }',self.core)
        self.assertIn('next.chapters[chapterIndex].nodes[nodeIndex].nodeTime = value',self.core)
        self.assertNotIn('* 60',self.core)
    def test_guarded_stepper_and_legacy_preservation(self):
        self.assertNotIn('Stepper(value: $node.nodeTime, in: 0...Int.max)',self.form)
        for token in ['ProjectNodeDuration.adjusted(node.nodeTime, by: 1)', 'ProjectNodeDuration.adjusted(node.nodeTime, by: -1)', '.disabled(!(0...ProjectNodeDuration.maximumMinutes).contains(node.nodeTime))']:
            self.assertIn(token,self.form)
        self.assertIn('guard (0...maximumMinutes).contains(minutes)',self.core)
    def test_ordinary_node_entry_only(self):
        self.assertIn('''if allowsGameplayRemoval ?? (chapterOverride == nil && starterLease == nil) {
                ProjectNodeDurationField''',self.form)
        self.assertEqual(self.form.count('ProjectNodeDurationField('),1)
    def test_current_owner_aba_incarnation_and_controller_fences(self):
        for token in ['capture.controllerID == controllerID', 'capture.generation == generation && model.fullEdit', 'model.editorIncarnation == capture.incarnation', 'model.isCurrentStarterLease(capture.lease)', 'model.draftMutationRevision == capture.revision', 'capture.snapshot.isCurrent(in: model.draft)']:
            self.assertIn(token,self.app)
    def test_staged_text_cancel_and_old_dismissal(self):
        for token in ['guard isCurrent(original) else { return }; text = value', 'guard opening?.id == original.id else { return }; retire()', 'if $0 == nil, let original { self.close(original) }', 'guard canApply(original)', 'generation = UUID()', '.onDisappear { controller.retire() }']:
            self.assertIn(token,self.app)
    def test_no_network_or_persistence_side_effect(self):
        for token in ['URLSession', 'transport', 'upload(', 'saveLocal(', 'Task {']:
            self.assertNotIn(token,self.app+self.core)
        self.assertEqual(self.app.count('model.draft = next'),1)
    def test_all_labels_bilingual(self):
        strings=json.loads((ROOT/'Resources/ProjectNodeDuration.xcstrings').read_text())['strings']
        self.assertEqual(len(strings),6)
        for key,value in strings.items():
            self.assertIn('"'+key+'"',self.app)
            self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
if __name__=='__main__': unittest.main()
