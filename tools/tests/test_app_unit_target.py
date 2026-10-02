"""Source/project/CI contracts only; these checks do not execute authored XCTest."""
import contextlib
import io
import pathlib
import re
import runpy
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
TARGET = 'QuestifyAppUnitTests'


class AppUnitTargetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = pathlib.Path(cls.temp.name)
        for folder in ['App', 'Core', 'Resources', 'Config', 'Tests/AppUITests', 'Tests/AppUnitTests']:
            shutil.copytree(ROOT / folder, cls.root / folder)
        (cls.root / 'tools').mkdir()
        shutil.copy2(ROOT / 'tools/generate_project.py', cls.root / 'tools/generate_project.py')
        with contextlib.redirect_stdout(io.StringIO()):
            cls.generated = runpy.run_path(str(cls.root / 'tools/generate_project.py'))
        cls.objects = cls.generated['objects']
        cls.targets = {o['name']: o for o in cls.objects.values() if o['isa'] == 'PBXNativeTarget'}
        cls.unit = cls.targets[TARGET]
        cls.scheme = ET.parse(cls.root / f'Questify.xcodeproj/xcshareddata/xcschemes/{TARGET}.xcscheme')

    def source_paths(self, target):
        return [self.objects[self.objects[b]['fileRef']]['path']
                for p in target['buildPhases'] if self.objects[p]['isa'] == 'PBXSourcesBuildPhase'
                for b in self.objects[p]['files']]

    def test_every_app_unit_source_is_compiled_exactly_once_and_only_in_unit_target(self):
        expected = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'Tests/AppUnitTests').rglob('*.swift'))
        self.assertTrue(expected)
        self.assertEqual(sorted(self.source_paths(self.unit)), expected)
        for name in ['Questify', 'QuestifyUITests']:
            self.assertFalse(set(expected) & set(self.source_paths(self.targets[name])))
        self.assertEqual(self.unit['productType'], 'com.apple.product-type.bundle.unit-test')
        self.assertEqual(self.objects[self.unit['productReference']]['path'], TARGET + '.xctest')

    def test_authored_methods_are_not_silently_removed_or_filtered(self):
        inventory = {p.stem: re.findall(r'func\s+(test\w+)\s*\(', p.read_text())
                     for p in (ROOT / 'Tests/AppUnitTests').rglob('*.swift')}
        self.assertEqual(len(inventory['RetainedImageNormalHostTests']), 6)
        self.assertEqual(len(inventory['RetainedImageSanitizerTests']), 4)
        for names in inventory.values():
            self.assertTrue(names)
            self.assertEqual(len(names), len(set(names)))
        self.assertFalse(self.scheme.findall('.//SkippedTests'))
        self.assertFalse(self.scheme.findall('.//SelectedTests'))

    def test_host_dependency_and_debug_testability(self):
        app_id = self.generated['target']
        dependency, = self.unit['dependencies']
        self.assertEqual(self.objects[dependency]['target'], app_id)
        proxy = self.objects[self.objects[dependency]['targetProxy']]
        self.assertEqual(proxy['remoteGlobalIDString'], app_id)
        self.assertEqual(proxy['containerPortal'], self.generated['project'])
        app_configs = self.objects[self.targets['Questify']['buildConfigurationList']]['buildConfigurations']
        debug, = [self.objects[c] for c in app_configs if self.objects[c]['name'] == 'Debug']
        self.assertEqual(debug['buildSettings']['ENABLE_TESTABILITY'], 'YES')
        configs = self.objects[self.unit['buildConfigurationList']]['buildConfigurations']
        for config in configs:
            ref = self.objects[self.objects[config]['baseConfigurationReference']]
            self.assertEqual(ref['path'], 'Config/AppUnitTests.xcconfig')
        config = (ROOT / 'Config/AppUnitTests.xcconfig').read_text()
        self.assertIn('TEST_HOST = $(BUILT_PRODUCTS_DIR)/Questify.app/Questify', config)
        self.assertIn('BUNDLE_LOADER = $(TEST_HOST)', config)
        self.assertIn('GENERATE_INFOPLIST_FILE = YES', config)
        self.assertNotIn('#include', config)
        self.assertNotIn('INFOPLIST_FILE = Config/Info.plist', config)

    def test_shared_scheme_matches_target_and_isolated_from_ui_scheme(self):
        action = self.scheme.find('TestAction')
        self.assertEqual(action.get('buildConfiguration'), 'Debug')
        testable, = action.findall('Testables/TestableReference')
        self.assertEqual(testable.get('skipped'), 'NO')
        ref = testable.find('BuildableReference')
        self.assertEqual(ref.get('BlueprintIdentifier'), self.generated['unit_target'])
        self.assertEqual(ref.get('BlueprintName'), TARGET)
        builds = self.scheme.findall('BuildAction/BuildActionEntries/BuildActionEntry')
        self.assertEqual({b.find('BuildableReference').get('BlueprintName') for b in builds}, {'Questify', TARGET})
        self.assertTrue(all(b.get('buildForTesting') == 'YES' for b in builds))
        ui = ET.parse(self.root / 'Questify.xcodeproj/xcshareddata/xcschemes/Questify.xcscheme')
        self.assertEqual([r.get('BlueprintName') for r in ui.findall('TestAction/Testables/TestableReference/BuildableReference')], ['QuestifyUITests'])

    def test_ci_runs_whole_target_once_in_bounded_separate_job(self):
        workflow = (ROOT / '.github/workflows/native-ios.yml').read_text()
        job = re.search(r'^  app-unit-tests:\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.M | re.S).group(1)
        self.assertIn('timeout-minutes: 20', job)
        self.assertIn('-xctestrun "$APP_UNIT_XCTESTRUN"', job)
        self.assertIn('test_products.py restore', job)
        self.assertIn('--commit "$GITHUB_SHA"', job)
        self.assertEqual(re.findall(r'-only-testing:([^\s]+)', job), [TARGET])
        self.assertNotIn('-skip-testing', job)
        self.assertNotIn('continue-on-error', job)
        native=workflow.split('  native:\n',1)[1].split('  secrets:\n',1)[0]
        self.assertIn('for scheme in Questify QuestifyAppUnitTests; do', native)
        self.assertIn('-configuration Debug', native)
        self.assertIn('CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build-for-testing', native)
        self.assertIn('test-without-building', job)
        self.assertIn('-maximum-test-execution-time-allowance 120', job)
        self.assertIn('-resultBundlePath', job)
        self.assertIn('simctl bootstatus', job)
        self.assertEqual(workflow.count('-only-testing:' + TARGET), 1)
        self.assertIn('run: swift test', workflow)
        self.assertIn('shard: [0, 1, 2, 3, 4, 5]', workflow)
        self.assertIn('--count 6', workflow)

    def test_generation_is_deterministic_and_committed_outputs_match(self):
        paths = ['project.pbxproj', 'xcshareddata/xcschemes/Questify.xcscheme', f'xcshareddata/xcschemes/{TARGET}.xcscheme']
        before = {p: (self.root / 'Questify.xcodeproj' / p).read_bytes() for p in paths}
        with contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(self.root / 'tools/generate_project.py'))
        for p in paths:
            self.assertEqual(before[p], (self.root / 'Questify.xcodeproj' / p).read_bytes())
            self.assertEqual(before[p], (ROOT / 'Questify.xcodeproj' / p).read_bytes())

    def test_nested_future_source_is_automatically_included(self):
        path = self.root / 'Tests/AppUnitTests/Future/NewTests.swift'
        path.parent.mkdir(exist_ok=True)
        path.write_text('import XCTest\nfinal class NewTests: XCTestCase { func testNew() {} }\n')
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                result = runpy.run_path(str(self.root / 'tools/generate_project.py'))
            builds = result['objects'][result['unit_sources']]['files']
            paths = [result['objects'][result['objects'][b]['fileRef']]['path'] for b in builds]
            self.assertIn('Tests/AppUnitTests/Future/NewTests.swift', paths)
        finally:
            path.unlink()
            with contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(self.root / 'tools/generate_project.py'))

    def test_swiftpm_keeps_core_test_scope(self):
        package = (ROOT / 'Package.swift').read_text()
        self.assertIn('path: "Tests/CoreTests"', package)
        self.assertNotIn('Tests/AppUnitTests', package)
