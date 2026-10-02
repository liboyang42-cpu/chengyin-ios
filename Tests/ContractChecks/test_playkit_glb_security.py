"""Source/security/dependency contract checks, not Apple compiler or AR acceptance."""
import json,pathlib,subprocess,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PlayKitGLBSecurityChecks(unittest.TestCase):
    def read(self,p):return (ROOT/p).read_text()
    def test_no_unverified_binary_or_floating_dependency(self):
        subprocess.run(['python3',str(ROOT/'tools/check_gltf_source.py')],check=True)
        g=self.read('tools/generate_project.py')
        for token in ['gltf_dependency','gltf_link','gltf_embed',"'CodeSignOnCopy'","'projectReferences'" if "'projectReferences'" in g else 'projectReferences=']:
            self.assertIn(token,g)
        self.assertNotIn('master',g);self.assertNotIn('binaryTarget',g)
    def test_all_local_bytes_are_validated_before_native_decode(self):
        source=self.read('App/PlayKitGLBAssets.swift')
        for token in ['PlayKitGLBPolicy.sanitizedData(data)','validateTextures(data: data','GLTFAsset.load(with: data','GLTFSCNSceneSource(asset: asset).defaultScene','stop.pointee = true','withTaskCancellationHandler','timer?.cancel()']:
            self.assertIn(token,source)
        self.assertNotIn('canImport(GLTFKit2)',source)
        self.assertNotIn('write(to:',source)
    def test_network_is_separate_ephemeral_bounded_and_redirect_free(self):
        s=self.read('App/PlayKitGLBAssets.swift')
        for token in ['URLSessionConfiguration.ephemeral','configuration.urlCredentialStorage = nil','configuration.httpCookieStorage = nil','configuration.urlCache = nil','timeoutIntervalForResource','session.bytes(for: request)','data.count < PlayKitGLBPolicy.maximumBytes','completionHandler(nil)','session.invalidateAndCancel()']:
            self.assertIn(token,s)
    def test_manifest_covers_external_includes_extensions_and_budgets(self):
        s=self.read('Core/PlayKitGLBPolicy.swift')
        for token in ['if key == "uri"','extensionsRequired','maximumBytes = 20 * 1024 * 1024','maximumJSONBytes = 1024 * 1024','budget = 100_000','depth <= 32','sparse','count <= 250_000','primitiveCount <= 512','parents.insert(child).inserted','visiting.contains(node)','sanitizedData']:
            self.assertIn(token,s)
    def test_approved_source_parameters_and_empty_runtime_approval(self):
        c=self.read('Core/PlayKitSpatialContracts.swift');u=self.read('App/PlayKitSpatialRevealView.swift')
        self.assertIn('modelHosts: Set<String> = []',c)
        self.assertIn('mode == .plane ? 0.4 : 0.8 * (markerWidthMeters ?? 0)',c)
        self.assertIn('child.clone()',u);self.assertIn('PlayKitModelFit',u)
        self.assertIn('atan2(delta.x, delta.z)',u)
        for p in ['App/PlayKitScreen.swift','App/PlayAdvancedView.swift']:self.assertIn('var spatialApproval = PlayKitSpatialApproval()',self.read(p))
    def test_real_decoder_test_is_not_skipped_or_conditional(self):
        t=self.read('Tests/AppUnitTests/PlayKitGLBDecoderTests.swift')
        self.assertIn('PlayKitGLBDecoder().scene(from: triangle())',t)
        self.assertIn('primitiveCount,1',t)
        self.assertNotIn('XCTSkip',t);self.assertNotIn('#if',t)
if __name__=='__main__':unittest.main()
