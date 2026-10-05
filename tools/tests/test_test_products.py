import hashlib
import importlib.util
import io
import pathlib
import plistlib
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('test_products', pathlib.Path(__file__).resolve().parents[1] / 'test_products.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TestProductTransferTests(unittest.TestCase):
    sha = 'a' * 40
    identity = {'xcode': 'fixture Xcode', 'developer': '/fixture/developer'}

    def setup_products(self, root):
        products = root / 'source/Products'
        app = products / 'Debug-iphonesimulator/Questify.app'
        app.mkdir(parents=True)
        executable = app / 'Questify'
        executable.write_text('synthetic test bytes, never executed')
        executable.chmod(0o755)
        for name in module.TARGETS:
            target = {'TestBundlePath': f'__TESTROOT__/Debug-iphonesimulator/{name}.xctest',
                      'TestHostPath': str(app)}
            # Cover modern TestConfigurations and legacy top-level target layouts.
            data = {'TestConfigurations': [{'TestTargets': [target]}]} if name == 'QuestifyUITests' else {name: target}
            (products / f'{name}.xctestrun').write_bytes(plistlib.dumps(data))
        return products

    def test_roundtrip_preserves_executable_and_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            products = self.setup_products(root)
            archive = root / 'products.tar.gz'
            module.pack(products, archive, self.sha, self.identity)
            result = module.restore(archive, root / 'restored', self.sha, self.identity)
            self.assertEqual(set(result), set(module.TARGETS.values()))
            self.assertTrue(all(pathlib.Path(p).is_file() for p in result.values()))
            self.assertTrue((root / 'restored/Products/Debug-iphonesimulator/Questify.app/Questify').stat().st_mode & 0o100)
            data = plistlib.loads(pathlib.Path(result['APP_UNIT_XCTESTRUN']).read_bytes())
            self.assertEqual(data['QuestifyAppUnitTests']['TestHostPath'], '__TESTROOT__/Debug-iphonesimulator/Questify.app')

    def test_missing_or_ambiguous_test_bundle_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            products = self.setup_products(pathlib.Path(tmp))
            path = products / 'QuestifyUITests.xctestrun'
            copy = products / 'duplicate.xctestrun'
            copy.write_bytes(path.read_bytes())
            with self.assertRaises(ValueError): module.inventory(products)
            copy.unlink(); path.unlink()
            with self.assertRaises(ValueError): module.inventory(products)

    def test_commit_and_toolchain_must_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp); products = self.setup_products(root); archive = root / 'products.tar.gz'
            module.pack(products, archive, self.sha, self.identity)
            with self.assertRaises(ValueError): module.restore(archive, root / 'wrong-commit', 'b' * 40, self.identity)
            with self.assertRaises(ValueError): module.restore(archive, root / 'wrong-tools', self.sha, {'xcode': 'other'})

    def test_corrupt_archive_fails_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp); archive = root / 'products.tar.gz'
            module.pack(self.setup_products(root), archive, self.sha, self.identity)
            archive.write_bytes(archive.read_bytes() + b'changed')
            with self.assertRaises(ValueError): module.restore(archive, root / 'dest', self.sha, self.identity)
            self.assertFalse((root / 'dest').exists())

    def test_path_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp); archive = root / 'products.tar.gz'
            with tarfile.open(archive, 'w:gz') as output:
                member = tarfile.TarInfo('Products/../../escape'); member.size = 1
                output.addfile(member, io.BytesIO(b'x'))
            archive.with_suffix('.gz.sha256').write_text(hashlib.sha256(archive.read_bytes()).hexdigest())
            with self.assertRaises(ValueError): module.restore(archive, root / 'dest', self.sha, self.identity)
            self.assertFalse((root / 'escape').exists())

    def test_nonportable_bundle_location_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            products = self.setup_products(pathlib.Path(tmp))
            path = products / 'QuestifyAppUnitTests.xctestrun'
            data = plistlib.loads(path.read_bytes())
            data['QuestifyAppUnitTests']['TestHostPath'] = '/other-build/App.app'
            path.write_bytes(plistlib.dumps(data))
            with self.assertRaises(ValueError): module.inventory(products, normalize=True)

    def test_source_root_symlink_aliases_are_portable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp).resolve()
            products = self.setup_products(root)
            alias = root / 'source-alias'
            alias.symlink_to(products.parent, target_is_directory=True)
            aliased_products = alias / 'Products'
            path = products / 'QuestifyAppUnitTests.xctestrun'
            data = plistlib.loads(path.read_bytes())
            data['QuestifyAppUnitTests']['TestHostPath'] = str(aliased_products / 'Debug-iphonesimulator/Questify.app')
            data['QuestifyAppUnitTests']['EnvironmentVariables'] = {'DYLD_FRAMEWORK_PATH': str(aliased_products / 'Frameworks') + ':' + str(products / 'OtherFrameworks')}
            path.write_bytes(plistlib.dumps(data))
            archive = root / 'products.tar.gz'
            module.pack(aliased_products, archive, self.sha, self.identity)
            result = module.restore(archive, root / 'restored', self.sha, self.identity)
            final = plistlib.loads(pathlib.Path(result['APP_UNIT_XCTESTRUN']).read_bytes())['QuestifyAppUnitTests']
            self.assertEqual(final['TestHostPath'], '__TESTROOT__/Debug-iphonesimulator/Questify.app')
            self.assertEqual(final['EnvironmentVariables']['DYLD_FRAMEWORK_PATH'], '__TESTROOT__/Frameworks:__TESTROOT__/OtherFrameworks')


if __name__ == '__main__': unittest.main()
