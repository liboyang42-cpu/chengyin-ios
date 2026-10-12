"""Bounded source contracts; does not fetch images or run Apple UI."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class PhotoFrameChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(ROOT/'Core/TemplatePhotoFrameConfiguration.swift').read_text();cls.app=(ROOT/'App/TemplatePhotoFrameEditor.swift').read_text();cls.form=(ROOT/'App/TemplateCreatorConfigurationView.swift').read_text()
        cls.tests=(ROOT/'Tests/CoreTests/TemplatePhotoFrameConfigurationTests.swift').read_text()+(ROOT/'Tests/AppUnitTests/TemplatePhotoFrameEditorTests.swift').read_text()
    def test_exact_frame_entry_and_generic_legacy_fallback(self):
        for token in ['family == .photoCheck && path == [.field("frameOpacity")] && TemplatePhotoFrameConfiguration(model.draft.advanced).isSupported','family == .photoCheck, path == [.field("frameUrl")], TemplatePhotoFrameConfiguration(model.draft.advanced).isSupported','NavigationLink("templateFrame.title") { TemplatePhotoFrameEditor(model: model) }','TextField(LocalizedStringKey(field.labelKey), text: text, axis: .vertical)']:self.assertIn(token,self.form)
    def test_explicit_reference_opacity_and_clear_preserve_contract(self):
        for token in ['case .reference(let value): next.set("photoCheck", "frameUrl", .string(value))','next.set("photoCheck", "frameOpacity", .number(value))','next.set("photoCheck", "frameUrl", .string(""))','(0...100).contains(value)']:self.assertIn(token,self.core)
        self.assertIn('Slider(value: editor.opacityInput(), in: 0...100, step: 5)',self.app)
        self.assertIn('if editor.isSupported && !editor.reference.isEmpty',self.app)
    def test_validated_https_request_and_no_automatic_load(self):
        for token in ['reference.utf8.count <= 512','reference.utf8.allSatisfy','url.scheme?.lowercased() == "https"','url.user == nil, url.password == nil, url.fragment == nil','!reference.contains("\\\\")']:self.assertIn(token,self.core)
        self.assertIn('Button("templateFrame.load", systemImage: "photo", action: editor.loadAction())',self.app)
        self.assertEqual(self.app.count('self.request = .init('),1)
        self.assertIn('if let request = editor.scene { preview(request).id(request.id) }',self.app)
    def test_loaded_image_updates_opacity_and_ignores_stale_callbacks(self):
        for token in ['AsyncImage(url: request.url)','image.resizable().scaledToFit().opacity(editor.opacity / 100)','request?.id == candidate.id','Data(configuration.reference.utf8) == candidate.reference','func imageReady(_ candidate: Request) { guard isCurrent(candidate)','func imageFailed(_ candidate: Request) { guard isCurrent(candidate)']:self.assertIn(token,self.app)
    def test_own_edits_parent_refresh_and_external_lifecycle_guards(self):
        for token in ['model.$draft.dropFirst().sink','guard let self, !self.writing else','model.coordinator.session == session','model.coordinator.identity == identity','mediaGeneration == model.mediaReviewGeneration','self.model.metadataGeneration == metadata','self.actionGeneration == stamp','self.textGeneration == stamp','Data(updated.reference.utf8) != Data(configuration.reference.utf8)','model.mediaReferencesWillChange()','if !updated.isCurrent(model.draft.advanced)','.onDisappear { editor.retire() }','.onChange(of: scenePhase)']:self.assertIn(token,self.app)
    def test_no_upload_sensor_grant_storage_or_review_execution(self):
        for token in ['PhotosPicker','UIImagePickerController','CLLocationManager','AVCapture','grantXP','submit(','UserDefaults','HTTPTransport','factory','Codable']:self.assertNotIn(token,self.app+self.core)
        self.assertIn('creatorIssues(.photoCheck)',self.app)
    def test_localization_and_registration_fragments(self):
        strings=json.loads((ROOT/'docs/localization/template-photo-frame.json').read_text())['strings'];keys=set(re.findall(r'"(templateFrame\.[^"\\]+)"',self.app+self.form));self.assertTrue(keys<=set(strings),keys-set(strings));self.assertIn('templateFrame.opacity %lld',strings)
        for entry in strings.values():
            for lang in ['en','zh-Hans']:self.assertTrue(entry['localizations'][lang]['stringUnit']['value'])
        reg=json.loads((ROOT/'docs/registration/template-photo-frame.json').read_text());self.assertEqual(reg['dependencies'],[])
        for key in ['app_sources','app_unit_tests','package_tests']:
            for path in reg[key]:self.assertTrue((ROOT/path).is_file())
    def test_authored_native_input_request_and_storage_coverage(self):
        for token in ['testPreviewRejectsRelativeInsecureCredentialFragmentAndControlAddresses','testExistingNormalizationRemovesClearedOptionalFrameFieldsOnlyAtSerialize','testExplicitLoadAdjustOpacityAndClearFullFlow','testInitReloadAndAddressEditingNeverAutomaticallyStartPreview','testParentChangedRefreshAndContinuousSliderKeepLoadedRequest','testFailureRetryCreatesNewRequestAndRejectsLateOldCallback','testURLChangeRetiresImageAndOldSliderButAllowsContinuedAddressTyping','testUnsupportedExternalOpacityKeepsDataAndDisablesSpecializedControls','testLocalSaveRestoreRetainsFrameFieldsButNotPreviewRequests','testPendingLockDeniesImageLoadingAndFrameWrites']:self.assertIn(token,self.tests)
if __name__=='__main__':unittest.main()
