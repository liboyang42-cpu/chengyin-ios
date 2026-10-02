"""Static contract assertions only; never ARKit/device acceptance."""
import json,pathlib,re,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PlayKitSpatialRenderingChecks(unittest.TestCase):
    def read(self,p):return (ROOT/p).read_text()
    def test_ar_requires_accepted_modes_assets_and_server_scan(self):
        core=self.read('Core/PlayKitSpatialContracts.swift')
        for token in ['modes: Set<PlayKitSpatialMode> = []','artworkHosts: Set<String> = []','segment["scanned"].bool == true','approval.modes.contains(mode)','markerWidthsMeters[marker.absoluteString]']:
            self.assertIn(token,core)
    def test_glb_is_not_silently_accepted(self):
        core=self.read('Core/PlayKitSpatialContracts.swift')
        self.assertIn('PlayKitGLBPolicy.approvedURL(model, hosts: approval.modelHosts)',core)
        self.assertIn('throw PlayKitSpatialError.unsupportedModel',core)
    def test_plane_uses_real_raycast_and_marker_actual_anchor(self):
        ui=self.read('App/PlayKitSpatialRevealView.swift')
        for token in ['.existingPlaneGeometry','alignment: .horizontal','view.session.raycast(query).first','anchor is ARImageAnchor','lockMarker(hasActualAnchor: true)','root.simdPosition']:
            self.assertIn(token,ui)
        for token in ['SUBMIT_SCAN','START_CHALLENGE','readyForBase','awardedXp']:
            self.assertNotIn(token,ui)
    def test_marker_uses_measured_physical_width_no_constant_guess(self):
        ui=self.read('App/PlayKitSpatialRevealView.swift')
        self.assertIn('physicalWidth: CGFloat(width)',ui)
        self.assertIn('let width = prepared.request.markerWidthMeters',ui)
        self.assertNotIn('physicalWidth: 1',ui)
    def test_asset_loader_has_bounded_bytes_pixels_and_redirects(self):
        text=self.read('App/PlayKitSpatialAssets.swift')
        for token in ['URLSessionConfiguration.ephemeral','configuration.urlCredentialStorage = nil','configuration.httpCookieStorage = nil','session.bytes(for: request)','data.count < maximum','24_000_000','kCGImageSourceCreateThumbnailWithTransform','willPerformHTTPRedirection','completionHandler(nil)']:
            self.assertIn(token,text)
        self.assertNotIn('Authorization',text)
    def test_lifecycle_fallback_and_reduced_motion_are_explicit(self):
        ui=self.read('App/PlayKitSpatialRevealView.swift')
        for token in ['loadTask?.cancel()','token == generation','uiView.session.pause()','phase != .placed','failedThisVisit','finishDecorativeMotion()','guard !reduceMotion else']:
            self.assertIn(token,ui)
    def test_normal_and_inline_hosts_keep_empty_approval(self):
        for path in ['App/PlayKitScreen.swift','App/PlayAdvancedView.swift']:
            self.assertIn('var spatialApproval = PlayKitSpatialApproval()',self.read(path))
        self.assertIn('PlayKitSpatialRevealButton(segment: raw, approval: spatialApproval',self.read('App/PlayKitPersonalForms.swift'))
    def test_new_copy_and_error_keys_are_bilingual(self):
        m=json.loads(self.read('docs/playkit-spatial-localizations.json'))
        ui=self.read('App/PlayKitSpatialRevealView.swift')
        for key in re.findall(r'"(playkitSpatial\.[A-Za-z.]+)"',ui):
            if key.endswith('.'):continue
            self.assertIn(key,m);self.assertEqual(set(m[key]),{'en','zh-Hans'})
        for key in ['disabled','unvalidatedScan','unsupportedMode','unsupportedModel','assetUnavailable','markerCalibrationRequired','permissionDenied','deviceUnavailable','interrupted']:
            self.assertIn('playkitSpatial.error.'+key,m)
if __name__=='__main__':unittest.main()
