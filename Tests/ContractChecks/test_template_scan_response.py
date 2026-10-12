import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class ScanResponseSourceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplateScanResponseConfiguration.swift').read_text();cls.app=(ROOT/'App/TemplateScanResponseEditor.swift').read_text();cls.host=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
    def test_mount_filters_only_managed_fields_and_preserves_hotspot(self):
        for token in ['TemplateScanResponseEditor(model: model)','TemplateScanResponseConfiguration.managedFields.contains($0.id)','usesHotspotPlacement','TemplateHotspotPlacementView(model: model)']:self.assertIn(token,self.host)
        keys=re.search(r'managedFields: Set<String> = \[([^\]]+)\]',self.core).group(1)
        self.assertEqual(set(re.findall(r'"([^"]+)"',keys)),{'kind','reply','audioUrl','imageUrl','overlayUrl','overlayScale','arMode','markerUrl','modelUrl'})
        self.assertNotIn('"xp"',keys)
    def test_exact_source_enums_and_scalar_only_edits(self):
        for value in ['TEXT','VOICE','IMAGE','OVERLAY','NONE','PLANE','MARKER']:self.assertIn('"'+value+'"',self.core)
        for token in ['next.set("scan", "kind"','next.set("scan", "arMode"','next.set("scan", "modelUrl", .string(""))']:self.assertIn(token,self.core)
        self.assertNotIn('removeValue(forKey:',self.core)
    def test_retained_fields_remain_reachable(self):
        for token in ['retainedTextFields','showsRetainedAR','!currentTextFields.contains($0)','!text($0).isEmpty']:self.assertIn(token,self.core)
        for token in ['Section("templateScan.retained")','if editor.showsRetainedAR { arPicker }','ForEach(editor.retainedFields)','editor.issues']:self.assertIn(token,self.app)
    def test_explicit_image_load_and_size_not_camera(self):
        for token in ['Slider(value: editor.scaleInput(), in: 20...100, step: 5)','geometry.size.width * editor.widthPercent / 100','AsyncImage(url: scene.url)','if let scene = editor.scene','.id(scene.id)']:self.assertIn(token,self.app)
        for token in ['url.scheme?.lowercased() == "https"','url.user == nil','url.fragment == nil','raw.utf8.count <= 512']:self.assertIn(token,self.core)
    def test_state_and_ownership_guards(self):
        for token in ['session == model.coordinator.session','identity == model.coordinator.identity','model.$draft.dropFirst()','Publishers.CombineLatest(model.$busy, model.$review)','self.inputGeneration == stamp','snapshot.isCurrent(self.model.draft.advanced)','request?.id == candidate.id','.onDisappear { editor.retire() }','phase != .active']:self.assertIn(token,self.app)
        for token in ['fingerprint: Data?','.sortedKeys','.withoutEscapingSlashes','guard canEdit, isCurrent(draft)']:self.assertIn(token,self.core)
    def test_no_new_runtime_or_backend_permission_calls(self):
        for token in ['URLSession','AVPlayer','ARSession','AVCapture','requestAuthorization','requestWhenInUseAuthorization','capabilityGrant','ProductionTransport','chooseImage','chooseDocument','submit(','sendEvent(']:self.assertNotIn(token,self.core+self.app)
    def test_bilingual_registration_fragment(self):
        fragment=json.loads((ROOT/'docs/localization/template-scan-response.json').read_text())['strings']
        used=set(re.findall(r'"(templateScan\.[a-zA-Z]+)"',self.app))-{'templateScan.kind','templateScan.arMode','templateScan.scale','templateScan.image','templateScan.saveLocal'}
        self.assertTrue(used.issubset(fragment),used-set(fragment));self.assertIn('templateScan.width %lld',fragment)
        for entry in fragment.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        registration=json.loads((ROOT/'docs/registration/template-scan-response.json').read_text());self.assertEqual(registration['dependencies'],[])
    def test_native_coverage_authored_not_claimed_run(self):
        core=(ROOT/'Tests/CoreTests/TemplateScanResponseConfigurationTests.swift').read_text();app=(ROOT/'Tests/AppUnitTests/TemplateScanResponseEditorTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',core)),12);self.assertEqual(len(re.findall(r'func test',app)),14)
        for token in ['testModeSwitchFencesOldInputsAndShowsRetainedARConflicts','testBusyABARetiresRequestEvenAfterUnlock','testLocalSaveRestoreRetainsExactConfigurationWithoutPreview','testUnsupportedExternalShapeNeverDrivesSliderOrMutation']:self.assertIn(token,app)
