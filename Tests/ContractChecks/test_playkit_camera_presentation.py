"""Native source contracts only; never a camera/Swift/visual execution claim."""
import json,pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PlayKitCameraPresentationChecks(unittest.TestCase):
    def read(self,p):return (ROOT/p).read_text()
    def test_frame_uses_typed_capture_and_original_pixels(self):
        self.assertIn('framed.capturePhoto(frame: cameraFrame, context: context)',self.read('Core/PlayDeviceTasks.swift'))
        native=self.read('App/PlayNativeDeviceProvider.swift')
        self.assertIn('picker.cameraOverlayView = host.view',native)
        self.assertIn('info[.originalImage] as? UIImage',native)
        self.assertIn('capturePhoto(frame: PlayKitPhotoFrame',native)
    def test_frame_failure_does_not_block_shutter_or_upload(self):
        ui=self.read('App/PlayKitCameraPresentation.swift').split('struct PlayKitCameraOverlayButton',1)[0]
        self.assertIn('else { Color.clear }',ui)
        self.assertIn('allowsHitTesting(false)',ui)
        self.assertNotIn('submit',ui)
    def test_library_selection_is_narrow_and_typed(self):
        text=self.read('App/PlayKitCameraPresentation.swift')
        for value in ['PHPickerConfiguration()', 'selectionLimit = 1', 'configuration.filter = .images','generation: generation']:
            self.assertIn(value,text)
        self.assertNotIn('PHPhotoLibrary.requestAuthorization',text)
        self.assertIn('library.captureLibraryPhoto(context: context)',self.read('Core/PlayDeviceTasks.swift'))
    def test_camera_overlay_is_not_claimed_to_be_ar(self):
        text=self.read('App/PlayKitCameraPresentation.swift')
        self.assertIn('camera.showsCameraControls = false',text)
        self.assertIn('playkitCamera.screenSpaceOnly',text)
        for value in ['ARSession', 'SUBMIT_SCAN','START_CHALLENGE','capturePhoto()']:
            self.assertNotIn(value,text)
    def test_permission_inactivity_does_not_destroy_sensor_child(self):
        screen=self.read('App/PlayKitScreen.swift')
        self.assertIn('if phase == .background { childReset = UUID() }',screen)
        self.assertIn('device?.isAuthorizing != true',screen)
        session=self.read('App/SessionPlayRuntimeView.swift')
        self.assertIn('!session.playNativeDeviceProvider.authorizationInFlight',session)
    def test_late_picker_callbacks_are_generation_guarded(self):
        text=self.read('App/PlayNativeDeviceProvider.swift')
        for value in ['generation != cameraGeneration','cameraGeneration == generation','cameraGeneration &+= 1; authorizationInFlight = false']:
            self.assertIn(value,text)
    def test_empty_grants_and_approved_assets_remain_required(self):
        self.assertIn('init(grants: Set<PlayDeviceKind> = [])',self.read('App/PlayNativeDeviceProvider.swift'))
        core=self.read('Core/PlayKitCameraContracts.swift')
        for value in ['segment["scanned"].bool == true','parts.user == nil','parts.port == nil || parts.port == 443','approvedHosts: Set<String>']:
            self.assertIn(value,core)
    def test_localizations_are_bilingual(self):
        text=self.read('App/PlayKitCameraPresentation.swift')+self.read('App/PlayKitPersonalForms.swift')
        import re
        strings=json.loads(self.read('docs/playkit-camera-localizations.json'))
        for key in re.findall(r'"(playkitCamera\.[A-Za-z]+)"',text):
            self.assertIn(key,strings);self.assertEqual(set(strings[key]),{'en','zh-Hans'})
if __name__=='__main__':unittest.main()
