"""Source-bound structural checks only; authored Swift methods still require execution."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class ProjectPendingNewChapterChecks(unittest.TestCase):
    def text(self,p):return (ROOT/p).read_text()
    def test_real_button_uses_original_material_and_chapter_snapshot(self):
        ui=self.text('App/ProjectEditPendingPresentation.swift')
        for token in ['controller.captureNewChapter(material.id)','controller.createChapter(newChapter, name: name)','projectPending.newStoryChapter','projectPending.newFreeChapter','if !model.draft.chapters.isEmpty']:
            self.assertIn(token,ui)
        controller=self.text('App/ProjectEditPendingController.swift')
        for token in ['isCurrent(target.material)','exactData(model.draft.chapters) == target.chapters','if !ProjectEditStarterPolicy.canAddFormalNode(material.node) { open(target.material); return }']:
            self.assertIn(token,controller)
    def test_one_envelope_save_before_city_presentation(self):
        body=self.text('App/ProjectEditPendingController.swift').split('func createChapter(')[1].split('func chooseChapter')[0]
        self.assertLess(body.index('model.persistLocalChange(result.draft'),body.index('open(fresh, kind: .story'))
        self.assertIn('saveUnconfirmed = true; return',body)
        self.assertNotIn('model.draft.chapters.append',body)
    def test_pure_mode_branch_preserves_city_material_and_free_atomic_move(self):
        core=self.text('Core/ProjectEditPendingChapter.swift')
        self.assertIn('ProjectEditStarterPolicy.chapter(name: name, product: draft.product)',core)
        self.assertIn('if draft.product == .freeExplore',core)
        self.assertIn('ProjectEditPendingMaterials.arranging(materialID, into: chapter.id, in: next)',core)
        self.assertNotIn('removeAll',core);self.assertNotIn('URLSession',core)
        self.assertIn('ProjectEditStarterPolicy.canAddFormalNode(material.node)',core)
    def test_no_new_wire_field_or_handler_payload(self):
        wire=self.text('Core/ProjectEditContract.swift')
        self.assertNotIn('pendingMaterials',wire)
        self.assertNotIn('newChapter',wire)
        fixture=self.text('App/ProjectEditFixtureSupport.swift').strip()
        self.assertTrue(fixture.startswith('#if DEBUG'));self.assertTrue(fixture.endswith('#endif'))
    def test_complete_regressions_and_two_bilingual_keys(self):
        for path,count in [('Tests/CoreTests/ProjectEditPendingChapterTests.swift',5),('Tests/AppUnitTests/ProjectEditPendingChapterControllerTests.swift',6),('Tests/AppUITests/ProjectPendingNewChapterFlowTests.swift',2)]:
            self.assertEqual(len(re.findall(r'func test\w+',self.text(path))),count)
        strings=json.loads(self.text('Resources/ProjectPendingChapterLocalizations.fragment.json'))['strings']
        self.assertEqual(set(strings),{'projectPending.newStoryChapter','projectPending.newFreeChapter'})
        for row in strings.values():self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
