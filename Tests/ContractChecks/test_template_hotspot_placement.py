"""Bounded source contracts. These checks do not compile or run Swift/Apple UI."""
import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class HotspotPlacementChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateHotspotPlacement.swift').read_text()
        cls.app=(ROOT/'App/TemplateHotspotPlacementView.swift').read_text()
        cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplateHotspotPlacementTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplateHotspotPlacementControllerTests.swift').read_text()
    def test_top_level_entry_and_supported_only_field_delegation(self):
        for token in ['family == .hiddenObject && TemplateHotspotPlacement(model.draft.advanced).isSupported','!usesHotspotPlacement || $0.id != "hotspots"','fields: configurationFields','TemplateHotspotPlacementView(model: model)','TemplateHotspotPlacement(model.draft.advanced).sceneURL != nil']:
            self.assertIn(token,self.form)
        self.assertIn('case .rows',self.form)
    def test_actual_image_bounds_and_explicit_load_readiness(self):
        for token in ['Button("templateHotspots.loadScene"','AsyncImage(url: request.url)','image.resizable().scaledToFit().overlay','SpatialTapGesture()','Double(geometry.size.width)','Double(geometry.size.height)','editor.imageReady(request)','editor.imageFailed(request)','self.isSceneReady']:
            self.assertIn(token,self.app)
        self.assertIn('requestID == self.scene?.id',self.app)
    def test_normalized_rounded_xy_preserves_radius(self):
        for token in ['width > 0, height > 0','min(1, max(0, coordinate / extent)) * 10000','row["x"] = .number(point.x); row["y"] = .number(point.y)','let point = Self.point']:
            self.assertIn(token,self.core)
        self.assertEqual(self.core.count('row["r"]'),1)
        for token in ['Slider(', 'TextField("creator.field.x"', 'TextField("creator.field.y"', 'TextField("creator.field.r"']:
            self.assertNotIn(token,self.app)
    def test_full_target_lifecycle_and_existing_count_contract(self):
        for token in ['targets.count < 5','targets.count > 3','"x": .number(0.5), "y": .number(0.5), "r": .number(0.08)','used.insert(id).inserted','case .label','case .remove','case .place']:
            self.assertIn(token,self.core)
        for token in ['editor.addAction()','editor.label(target.id)','editor.removeAction(target.id)','editor.moveAction(target.id, to: index - 1)','editor.armAction(target.id)','self.armedID == id ? nil : id','self.armedID = nil']:
            self.assertIn(token,self.app)
    def test_stale_scope_and_image_fences(self):
        for token in ['model.objectWillChange.sink','if !self.writing && !self.canEdit { self.clearScene() }','draftObservation = model.$draft.sink','guard let self, !self.writing else { return }','self.actionGeneration == stamp','self.textGeneration == stamp','snapshot.isCurrent(self.model.draft.advanced)','session == model.coordinator.session','identity == model.coordinator.identity','mediaGeneration == model.mediaReviewGeneration','sceneRequest?.id == request.id','.onDisappear { editor.retire() }','phase == .active']:
            self.assertIn(token,self.app)
        self.assertIn('fingerprint == Self.snapshot(draft)',self.core)
    def test_explicit_https_scene_boundary_and_no_new_upload_or_backend(self):
        for token in ['url.scheme?.lowercased() == "https"','url.user == nil, url.password == nil, url.fragment == nil','sceneReference.utf8.count <= 512']:
            self.assertIn(token,self.core)
        for token in ['URLSession','HTTPTransport','upload(', 'factory', 'submit(', 'UserDefaults']:
            self.assertNotIn(token,self.app+self.core)
        self.assertIn('model.changed()',self.app)
    def test_localization_and_registration_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-hotspot-placement.json').read_text())['strings']
        keys=set(re.findall(r'"(templateHotspots\.[^"\\]+)"',self.app+self.form))
        self.assertTrue(keys<=set(strings),keys-set(strings));self.assertIn('templateHotspots.targetNumber %lld',strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-hotspot-placement.json').read_text())
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_native_coverage_includes_complete_flow_restore_and_interruptions(self):
        for token in ['testMeasuredCoordinatesClampAndRoundToFourDecimals','testPlaceWritesOnlyChosenXYAndKeepsRadiusAndUnknownFields','testCompleteLoadSelectPlaceAddRenameRemoveFlow','testImageFailureRetryAndOldImageCallbackStayFenced','testSceneChangeAndSameValueABAClearSelectionAndRequest','testLifecycleOwnerAndMediaChangesDenyRetainedCallbacks','testLocalSaveRestoreRetainsPositionsButNeverRestoresImageOrArming','testPendingWriteLockDeniesSceneAndTargetEdits']:
            self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
