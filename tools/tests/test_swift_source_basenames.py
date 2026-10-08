"""Protect per-target Swift outputs without disabling localization extraction.

These generator/scaffold regression checks do not execute Swift or Xcode.
"""
import contextlib
import io
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class SwiftSourceBasenameTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['App', 'Core', 'Tests/AppUITests', 'Tests/AppUnitTests',
                       'Config', 'Resources', 'tools', 'Vendor/GLTFKit2/GLTFKit2.xcodeproj']:
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        for name in ['generate_project.py', 'check_scaffold.py']:
            shutil.copy2(ROOT / 'tools' / name, self.root / 'tools' / name)
        # Small synthetic project exercises the real generator and scaffold.
        self.write('App/Main.swift', '// preferences.language\n')
        self.write('Core/Domain.swift', '// Domain fixture\n')
        self.write('Tests/AppUITests/SharedTests.swift', '// UI target fixture\n')
        self.write('Tests/AppUnitTests/SharedTests.swift', '// App-unit target fixture\n')
        self.write('Config/Base.xcconfig', 'PRODUCT_BUNDLE_IDENTIFIER = invalid.example.questify.ios\n')
        self.write('Config/AppUnitTests.xcconfig', '// Test configuration fixture\n')
        self.write('Resources/Localizable.xcstrings', json.dumps({'sourceLanguage': 'en', 'strings': {}}))
        self.write('Vendor/GLTFKit2/GLTFKit2.xcodeproj/project.pbxproj',
                   '834FF1C425C27938001887C2 /* product */ = {};\n'
                   '834FF1C325C27938001887C2 /* target */ = {};\n')

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def generate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return runpy.run_path(str(self.root / 'tools/generate_project.py'))

    def check_scaffold(self):
        return subprocess.run([sys.executable, str(self.root / 'tools/check_scaffold.py')],
                              capture_output=True, text=True)

    def outputs(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in (self.root / 'Questify.xcodeproj').rglob('*') if p.is_file()}

    def test_separate_target_basenames_are_allowed_and_extraction_stays_enabled(self):
        generated = self.generate()
        objects = generated['objects']
        app = objects[generated['target']]
        configs = objects[app['buildConfigurationList']]['buildConfigurations']
        self.assertEqual({objects[c]['name'] for c in configs}, {'Debug', 'Release'})
        for config in configs:
            self.assertEqual(objects[config]['buildSettings']['SWIFT_EMIT_LOC_STRINGS'], 'YES')
        result = self.check_scaffold()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        before = self.outputs()
        self.generate()
        self.assertEqual(self.outputs(), before)

    def test_app_core_collisions_fail_before_overwriting_any_generated_output(self):
        self.generate()
        before = self.outputs()
        # CI135 regression and the next two independently developed candidates.
        for stem in ['IMConversationRowActions', 'IMConversationReadAll', 'ProjectChapterRemoval']:
            with self.subTest(stem=stem):
                app = self.write(f'App/{stem}.swift', '// App fixture\n')
                core = self.write(f'Core/{stem}.swift', '// Core fixture\n')
                try:
                    with self.assertRaises(SystemExit) as failure:
                        self.generate()
                    message = str(failure.exception)
                    self.assertIn('Duplicate Swift basenames in target Questify:', message)
                    self.assertIn(f'App/{stem}.swift', message)
                    self.assertIn(f'Core/{stem}.swift', message)
                    self.assertIn('keep Swift localization extraction enabled', message)
                    self.assertEqual(self.outputs(), before)
                finally:
                    app.unlink()
                    core.unlink()

    def test_case_only_collisions_fail_on_case_sensitive_hosts_too(self):
        self.write('Core/main.swift', '// Case-only collision with App/Main.swift\n')
        with self.assertRaisesRegex(SystemExit, 'Duplicate Swift basenames in target Questify:'):
            self.generate()
        self.assertFalse((self.root / 'Questify.xcodeproj').exists())

    def test_nested_app_unit_duplicate_is_rejected_per_target(self):
        self.write('Tests/AppUnitTests/Nested/SharedTests.swift', '// Duplicate test fixture\n')
        with self.assertRaises(SystemExit) as failure:
            self.generate()
        message = str(failure.exception)
        self.assertIn('Duplicate Swift basenames in target QuestifyAppUnitTests:', message)
        self.assertIn('Tests/AppUnitTests/Nested/SharedTests.swift', message)
        self.assertIn('Tests/AppUnitTests/SharedTests.swift', message)

    def test_ui_target_case_only_duplicate_is_rejected(self):
        # A default macOS volume cannot create both case variants in one folder.
        # Supply the conflicting enumeration explicitly so CI exercises the UI
        # target guard on both case-sensitive and case-insensitive filesystems.
        original_glob = Path.glob
        def glob(root, pattern):
            if root.resolve() == self.root.resolve() and pattern == 'Tests/AppUITests/*.swift':
                return iter([root / 'Tests/AppUITests/SharedTests.swift',
                             root / 'Tests/AppUITests/sharedtests.swift'])
            return original_glob(root, pattern)
        with patch.object(Path, 'glob', glob):
            with self.assertRaisesRegex(SystemExit, 'Duplicate Swift basenames in target QuestifyUITests:'):
                self.generate()

    def test_ui_collision_mock_supports_resolved_temporary_root_alias(self):
        # macOS exposes temporary paths through /var -> /private/var. The
        # generator resolves __file__; the synthetic enumerator must match it.
        original = self.root
        alias = original.parent / (original.name + '-alias')
        alias.symlink_to(original, target_is_directory=True)
        self.addCleanup(alias.unlink)
        self.root = alias
        self.assertNotEqual(self.root, self.root.resolve())
        self.test_ui_target_case_only_duplicate_is_rejected()

    def test_scaffold_independently_rejects_duplicate_build_membership(self):
        generated = self.generate()
        objects = generated['objects']
        phase = objects[generated['src_phase']]
        phase['files'].append(phase['files'][0])
        project = {'archiveVersion': 1, 'classes': {}, 'objectVersion': 56,
                   'objects': objects, 'rootObject': generated['project']}
        self.write('Questify.xcodeproj/project.pbxproj',
                   '// !$*UTF8*$!\n' + generated['serialize'](project) + '\n')
        before = self.outputs()
        result = self.check_scaffold()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Duplicate Swift basenames in target', result.stderr)
        self.assertIn('Questify', result.stderr)
        self.assertIn('App/Main.swift', result.stderr)
        self.assertEqual(self.outputs(), before)

    def test_scaffold_independently_rejects_two_paths_with_same_basename(self):
        generated = self.generate()
        objects = generated['objects']
        core = self.root / 'Core/Domain.swift'
        core.rename(self.root / 'Core/Main.swift')
        for obj in objects.values():
            if obj.get('path') == 'Core/Domain.swift':
                obj['path'] = 'Core/Main.swift'
        project = {'archiveVersion': 1, 'classes': {}, 'objectVersion': 56,
                   'objects': objects, 'rootObject': generated['project']}
        self.write('Questify.xcodeproj/project.pbxproj',
                   '// !$*UTF8*$!\n' + generated['serialize'](project) + '\n')
        result = self.check_scaffold()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Duplicate Swift basenames in target', result.stderr)
        for path in ['App/Main.swift', 'Core/Main.swift']:
            self.assertIn(path, result.stderr)


if __name__ == '__main__':
    unittest.main()
