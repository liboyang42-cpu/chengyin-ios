"""Bounded source assertions; not Swift compilation or UI runtime acceptance."""
from pathlib import Path
import json,unittest
ROOT=Path(__file__).resolve().parents[2]
class AlbumPhotoRemovalSourceTests(unittest.TestCase):
    def setUp(self):
        self.core=(ROOT/'Core/ProjectAlbumPhotoRemoval.swift').read_text();self.app=(ROOT/'App/ProjectAlbumPhotoRemovalButton.swift').read_text();self.form=(ROOT/'App/ProjectEditRichStoryForms.swift').read_text()
    def test_exact_ordinal_identity_and_entire_preimage(self):
        for token in ['id.utf8.elementsEqual(chapterID.utf8)','filter({ $0.id == blockID }).count == 1','id.utf8.elementsEqual(blockID.utf8)','rows.indices.contains(index)','ProjectEditPendingMaterials.exactData(draft) == bytes']:
            self.assertIn(token,self.core)
    def test_no_compaction_or_url_deduplication(self):
        for token in ['rows.allSatisfy','object["url"]?.text != nil','object["line"] == nil || object["line"]?.text != nil','remaining.remove(at: index)','setField("images", .array(remaining))']:
            self.assertIn(token,self.core)
        self.assertNotIn('compactMap',self.core);self.assertNotIn('Set(',self.core)
    def test_known_schema_and_bounds(self):
        for token in ['schemaVersion == 1','kind == .dream','(1...6).contains(rows.count)']:
            self.assertIn(token,self.core)
    def test_scoped_ordinary_mount_preserves_existing_override_action(self):
        self.assertIn('if allowsAlbumImageSource {\n                                ProjectAlbumPhotoRemovalButton',self.form)
        self.assertIn('''                            } else {
                                Button("projectEdit.rich.removeImage", role: .destructive) { block.removeDreamImage(index: index) }
''',self.form)
        self.assertIn('ProjectAlbumPhotoRemovalIdentity(owner: ObjectIdentifier(model)',self.form)
    def test_confirmation_and_owner_aba_presentation_fences(self):
        for token in ['capture.controllerID == controllerID','capture.generation == generation && model.fullEdit','model.editorIncarnation == capture.incarnation','model.isCurrentStarterLease(capture.lease)','model.draftMutationRevision == capture.revision','guard isCurrent(original), let next','guard opening?.id == original.id else { return }']:
            self.assertIn(token,self.app)
    def test_binding_background_and_retirement(self):
        for token in ['if $0 == nil, let original { self.close(original) }','onDisappear { controller.setActive(false) }','controller.setActive(phase == .active)','guard scenePhase == .active']:
            self.assertIn(token,self.app)
    def test_review_never_fetches_or_deletes_remote_media(self):
        for token in ['AsyncImage','URLSession','URLRequest','upload(', 'saveLocal(', 'removeItem(', 'transport', 'Link(']:
            self.assertNotIn(token,self.app+self.core)
        self.assertEqual(self.app.count('model.draft = next'),1)
        self.assertIn('Text(verbatim: snapshot.reference)',self.app)
    def test_bilingual_confirmation_labels(self):
        strings=json.loads((ROOT/'Resources/ProjectAlbumPhotoRemoval.xcstrings').read_text())['strings']
        self.assertEqual(len(strings),4)
        for key,value in strings.items():self.assertIn('"'+key+'"',self.app);self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
