"""Bounded source contracts; not Swift compilation or device acceptance."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
class NodeHoursClearSourceTests(unittest.TestCase):
    def setUp(self):
        self.core=(ROOT/'Core/ProjectNodeBusinessHours.swift').read_text()
        self.app=(ROOT/'App/ProjectNodeBusinessHoursField.swift').read_text()
    def test_clear_is_distinct_from_existing_nil_noop(self):
        self.assertIn('public func clearing(in draft:',self.core)
        self.assertIn('guard value != nil else { return draft }',self.core)
        self.assertIn('localMetadata["businessTime"] = .string("")',self.core)
        self.assertIn('guard let selected, selected != value else { return draft }',self.core)
    def test_clear_requires_current_supported_whole_snapshot(self):
        clear=self.core[self.core.index('public func clearing'):self.core.index('public func replacing')]
        self.assertIn('guard isCurrent(in: draft)',clear)
        self.assertIn('reason == nil && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes',self.core)
    def test_select_and_cancel_stage_only(self):
        choose=self.app[self.app.index('func chooseClear'):self.app.index('func canApply')]
        self.assertNotIn('model.draft =',choose)
        for token in ['guard isCurrent(original), original.capture.snapshot.value != nil', 'selection = nil; clearSelected = true', 'selection = original.capture.snapshot.value; clearSelected = false']:
            self.assertIn(token,choose)
    def test_apply_clears_only_on_explicit_staged_intent(self):
        self.assertIn('if clearSelected {',self.app)
        self.assertIn('original.capture.snapshot.clearing(in: model.draft)',self.app)
        self.assertEqual(self.app.count('model.draft = next'),1)
        self.assertIn('original.capture.snapshot.replacing(with: selection, in: model.draft)',self.app)
    def test_owner_aba_and_old_dismissal_fences_remain(self):
        for token in ['model.isCurrentStarterLease(capture.lease)', 'model.draftMutationRevision == capture.revision', 'guard opening?.id == original.id else { return }; retire()', 'if $0 == nil, let original { self.close(original) }', 'clearSelected = false; generation += 1']:
            self.assertIn(token,self.app)
    def test_visible_two_step_clear_and_undo(self):
        for token in ['controller.chooseClear(original)', 'else if controller.clearSelected', 'projectNodeHours.clearPending', 'controller.undoClear(original)', '.disabled(!controller.canApply(original))']:
            self.assertIn(token,self.app)
        self.assertIn('guard isCurrent(original), selection == nil, !clearSelected',self.app)
    def test_new_strings_bilingual(self):
        strings=json.loads((ROOT/'Resources/ProjectNodeBusinessHours.xcstrings').read_text())['strings']
        for key in ['projectNodeHours.clear','projectNodeHours.clearPending','projectNodeHours.keep']:
            self.assertEqual(set(strings[key]['localizations']),{'en','zh-Hans'})
            self.assertIn('"'+key+'"',self.app)
    def test_no_new_transport_or_direct_save(self):
        for token in ['URLSession', 'upload(', 'saveLocal(', 'transport', 'Task {']:
            self.assertNotIn(token,self.core+self.app)
if __name__=='__main__':unittest.main()
