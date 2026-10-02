"""Offline verifier regressions only; synthetic outputs are not Apple link evidence."""
import importlib.util,pathlib,plistlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('gltf_link_check',ROOT/'tools/check_gltf_linked.py')
check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)

class GLTFLinkedVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.app=pathlib.Path(self.temp.name)/'Questify.app';self.app.mkdir()
        (self.app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'Questify'}))
        self.framework=self.app/'Frameworks/GLTFKit2.framework';self.framework.mkdir(parents=True)
        for file in [self.app/'Questify',self.app/'GLTFKit2Notices.txt',self.framework/'GLTFKit2',self.framework/'PrivacyInfo.xcprivacy']:file.touch()
        self.archs={'Questify':['arm64','x86_64'],'GLTFKit2':['arm64','x86_64'],'Questify.debug.dylib':['arm64','x86_64']}
        self.links={('Questify',arch):[check.GLTF_INSTALL_NAME] for arch in self.archs['Questify']}
        self.symbols='\n'.join('0000000000010000 S '+symbol for symbol in check.DECODER_SYMBOLS)
        self.commands=[]
    def command(self,*args):
        self.commands.append(args);name=pathlib.Path(args[-1]).name
        if args[:2]==('lipo','-archs'):return ' '.join(self.archs[name])+'\n'
        if args[0]=='nm':return self.symbols
        if args[0]=='otool':
            return str(args[-1])+':\n'+''.join('\t'+lib+' (compatibility version 1.0.0, current version 1.0.0)\n' for lib in self.links.get((name,args[2]),[]))
        raise AssertionError(args)
    def debug_layout(self):
        (self.app/'Questify.debug.dylib').touch()
        for arch in self.archs['Questify']:
            self.links[('Questify',arch)]=['@rpath/Questify.debug.dylib']
            self.links[('Questify.debug.dylib',arch)]=[check.GLTF_INSTALL_NAME]
    def test_direct_release_link_passes_for_every_architecture(self):
        self.assertEqual(len(check.verify(self.app,self.command)),2)
        self.assertFalse(any('Questify.debug.dylib' in c[-1] for c in self.commands))
    def test_exact_launcher_to_debug_to_framework_chain_passes(self):
        self.debug_layout()
        paths=check.verify(self.app,self.command)
        self.assertEqual(len(paths),2);self.assertTrue(all('Questify.debug.dylib -> GLTFKit2' in path for path in paths))
    def test_executable_path_debug_install_name_passes(self):
        self.debug_layout()
        self.links[('Questify','arm64')]=['@executable_path/Questify.debug.dylib']
        self.assertEqual(len(check.verify(self.app,self.command)),2)
    def test_adjacent_unlinked_debug_dylib_cannot_mask_missing_link(self):
        self.debug_layout();self.links[('Questify','arm64')]=[]
        with self.assertRaisesRegex(AssertionError,'exact debug dylib'):check.verify(self.app,self.command)
    def test_preview_or_unrelated_dylib_cannot_mask_missing_link(self):
        self.debug_layout();self.links[('Questify','arm64')]=['@rpath/__preview.dylib','@rpath/Other.debug.dylib']
        with self.assertRaisesRegex(AssertionError,'exact debug dylib'):check.verify(self.app,self.command)
    def test_missing_debug_file_is_failure(self):
        self.debug_layout();(self.app/'Questify.debug.dylib').unlink()
        with self.assertRaisesRegex(AssertionError,'debug dylib missing'):check.verify(self.app,self.command)
    def test_debug_dylib_without_framework_link_is_failure(self):
        self.debug_layout();self.links[('Questify.debug.dylib','arm64')]=[]
        with self.assertRaisesRegex(AssertionError,'debug dylib does not link'):check.verify(self.app,self.command)
    def test_one_missing_architecture_link_is_failure(self):
        self.links[('Questify','x86_64')]=[]
        with self.assertRaisesRegex(AssertionError,'x86_64'):check.verify(self.app,self.command)
    def test_missing_framework_or_debug_architecture_is_failure(self):
        self.archs['GLTFKit2']=['arm64']
        with self.assertRaisesRegex(AssertionError,'missing an app architecture'):check.verify(self.app,self.command)
        self.archs['GLTFKit2']=['arm64','x86_64'];self.debug_layout();self.archs['Questify.debug.dylib']=['arm64']
        with self.assertRaisesRegex(AssertionError,'missing app architecture'):check.verify(self.app,self.command)
    def test_framework_notices_and_privacy_are_still_required(self):
        for path in [self.framework/'GLTFKit2',self.app/'GLTFKit2Notices.txt',self.framework/'PrivacyInfo.xcprivacy']:
            with self.subTest(path=path.name):
                path.unlink()
                with self.assertRaises(AssertionError):check.verify(self.app,self.command)
                path.touch()
    def test_missing_or_undefined_decoder_symbol_does_not_pass(self):
        self.symbols='                 U '+check.DECODER_SYMBOLS[0]
        with self.assertRaisesRegex(AssertionError,'decoder definition missing'):check.verify(self.app,self.command)
    def test_optional_codec_is_still_rejected(self):
        self.symbols+='\n0000000000010000 T _ktxTexture2_CreateFromMemory\n'
        with self.assertRaisesRegex(AssertionError,'Optional codec'):check.verify(self.app,self.command)
    def test_otool_failure_is_not_suppressed(self):
        def broken(*args):raise subprocess.CalledProcessError(1,args)
        with self.assertRaises(subprocess.CalledProcessError):check.verify(self.app,broken)
    def test_dependency_substring_is_not_a_load_command(self):
        self.links[('Questify','arm64')]=[check.GLTF_INSTALL_NAME+'-unrelated']
        with self.assertRaisesRegex(AssertionError,'does not link'):check.verify(self.app,self.command)

if __name__=='__main__':unittest.main()
