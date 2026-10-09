"""Bounded source contracts only; these do not execute Swift or replace Apple tests."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class AlbumPhotoOrderSourceTests(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT / 'Core/ProjectAlbumPhotoOrder.swift').read_text()
        self.app = (ROOT / 'App/ProjectEditRichStoryForms.swift').read_text()
    def test_exact_ids_and_whole_preimage(self):
        for token in ['filter { draft.chapters[$0].id == chapterID }', 'id.utf8.elementsEqual(chapterID.utf8)', 'filter({ $0.id == blockID }).count == 1', 'id.utf8.elementsEqual(blockID.utf8)', 'ProjectEditPendingMaterials.exactData(draft) == bytes']:
            self.assertIn(token, self.core)
    def test_raw_array_swap_preserves_objects_and_duplicates(self):
        for token in ['rows.allSatisfy({ $0.object != nil })', 'reordered.swapAt(index, index + direction.rawValue)', 'setField("images", .array(reordered))']:
            self.assertIn(token, self.core)
        for token in ['compactMap', 'Set(', '["url"]', '["line"]', 'removeAll']:
            self.assertNotIn(token, self.core)
    def test_bounds_and_known_schema(self):
        for token in ['schemaVersion == 1', 'kind == .dream', '(2...6).contains(rows.count)', 'rows.indices.contains(index)', 'available && rows.indices.contains(index + direction.rawValue)']:
            self.assertIn(token, self.core)
    def test_action_fences_include_same_byte_aba_and_capability(self):
        helper = self.app[self.app.index('@MainActor final class ProjectAlbumPhotoOrderPresentation'):]
        for token in ['guard active, captured.hostID == hostID, model.fullEdit', 'model.editorIncarnation == captured.incarnation', 'model.draftMutationRevision == captured.revision', 'model.isCurrentStarterLease(captured.lease)', 'hostID = UUID(); active = value', 'captured.snapshot.moving(direction, in: model.draft)']:
            self.assertIn(token, helper)
    def test_explicit_buttons_and_lifetime(self):
        for token in ['if allowsAlbumImageSource {\n                                ProjectAlbumPhotoOrderButtons', 'moveButton(.up', 'moveButton(.down', 'guard scenePhase == .active, let captured', '.onDisappear { presentation.setActive(false) }', 'phase == .active']:
            self.assertIn(token, self.app)
    def test_new_helper_has_no_network_or_persistence_calls(self):
        helper = self.app[self.app.index('@MainActor final class ProjectAlbumPhotoOrderPresentation'):]
        for token in ['URLSession', 'upload(', 'saveLocal(', 'Task {', 'clipboard', 'transport']:
            self.assertNotIn(token, helper + self.core)
    def test_bilingual_button_labels(self):
        strings = json.loads((ROOT / 'Resources/ProjectAlbumPhotoOrder.xcstrings').read_text())['strings']
        self.assertEqual(set(strings), {'projectAlbumOrder.up', 'projectAlbumOrder.down'})
        for entry in strings.values():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'})
            self.assertTrue(all(v['stringUnit']['value'] for v in entry['localizations'].values()))

if __name__ == '__main__': unittest.main()
