"""Synthetic validation only. No actual codesign, Keychain, or Apple account access."""
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location('simulator_keychain_host', Path(__file__).resolve().parents[1] / 'prepare_simulator_keychain_host.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def binary(platform=7):
    return struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 2, 1, 24, 0, 0) + struct.pack('<6I', 0x32, 24, platform, 0, 0, 0)


class SimulatorKeychainHostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.products = self.root / 'prebuilt-tests/Products'
        self.host = self.products / module.HOST_RELATIVE
        self.host.mkdir(parents=True)
        self.run = self.products / 'unit.xctestrun'
        self.record = {'TestBundlePath': '__TESTROOT__/Debug-iphonesimulator/Questify.app/PlugIns/QuestifyAppUnitTests.xctest',
                       'TestHostPath': '__TESTROOT__/' + module.HOST_RELATIVE}
        self.write_run()
        self.info = {'CFBundleIdentifier': module.BUNDLE_ID, 'CFBundleExecutable': 'Questify',
                     'CFBundleSupportedPlatforms': ['iPhoneSimulator']}
        self.write_info()
        (self.host / 'Questify').write_bytes(binary())
        self.commit = 'a' * 40
        (self.products / 'questify-test-products.json').write_text(json.dumps({'commit': self.commit, 'targets': {'QuestifyAppUnitTests': self.run.name}}))

    def write_run(self):
        self.run.write_bytes(plistlib.dumps({'TestConfigurations': [{'TestTargets': [self.record]}]}))

    def write_info(self):
        (self.host / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def validate(self):
        return module.validate_host(self.run, self.root, self.commit)

    def test_exact_restored_simulator_host_is_selected(self):
        self.assertEqual(self.validate(), (self.host.resolve(strict=True), self.root.resolve(strict=True)))

    def test_wrong_commit_and_manifest_target_fail(self):
        self.commit = 'b' * 40
        with self.assertRaises(ValueError): self.validate()
        self.commit = 'not-a-sha'
        with self.assertRaises(ValueError): self.validate()

    def test_device_and_other_platforms_fail(self):
        for platform in [1, 2, 6, 8]:
            (self.host / 'Questify').write_bytes(binary(platform))
            with self.assertRaises(ValueError): self.validate()

    def test_wrong_bundle_id_executable_or_platform_plist_fail(self):
        for key, value in [('CFBundleIdentifier', 'real.customer.app'), ('CFBundleExecutable', '../Other'), ('CFBundleSupportedPlatforms', ['iPhoneOS'])]:
            old = self.info[key]; self.info[key] = value; self.write_info()
            with self.assertRaises(ValueError): self.validate()
            self.info[key] = old

    def test_wrong_target_and_host_paths_fail(self):
        for key, value in [('TestBundlePath', '__TESTROOT__/QuestifyUITests.xctest'), ('TestHostPath', str(self.host)), ('TestHostPath', '__TESTROOT__/../other.app')]:
            old = self.record[key]; self.record[key] = value; self.write_run()
            with self.assertRaises(ValueError): self.validate()
            self.record[key] = old

    def test_missing_host_and_symlinked_executable_fail(self):
        executable = self.host / 'Questify'
        executable.unlink()
        with self.assertRaises(ValueError): self.validate()
        outside = self.root / 'outside'; outside.write_bytes(binary())
        executable.symlink_to(outside)
        with self.assertRaises(ValueError): self.validate()

    def test_symlinked_restore_root_fails(self):
        restore = self.root / 'prebuilt-tests'
        restore.rename(self.root / 'elsewhere')
        restore.symlink_to(self.root / 'elsewhere', target_is_directory=True)
        with self.assertRaises(ValueError): self.validate()

    def test_run_outside_restore_root_fails(self):
        self.run = self.root / 'outside.xctestrun'; self.write_run()
        with self.assertRaises(ValueError): self.validate()

    def test_profile_and_ambiguous_targets_fail(self):
        profile = self.host / 'embedded.mobileprovision'; profile.write_bytes(b'synthetic')
        with self.assertRaises(ValueError): self.validate()
        profile.unlink()
        self.run.write_bytes(plistlib.dumps({'TestTargets': [self.record, self.record]}))
        with self.assertRaises(ValueError): self.validate()

    def test_truncated_and_overlapping_binary_fail(self):
        for data in [b'', binary()[:-1], b'\xca\xfe\xba\xbe', struct.pack('>2I', 0xcafebabe, 100),
                     struct.pack('>2I', 0xcafebabe, 2) + struct.pack('>5I', 0, 0, 48, 56, 0) * 2 + binary()]:
            with self.assertRaises(ValueError): module.verify_simulator_executable(data)

    def test_fat_binary_requires_each_slice_to_be_simulator(self):
        table = struct.pack('>2I', 0xcafebabe, 2) + struct.pack('>5I', 0, 0, 48, 56, 0) + struct.pack('>5I', 0, 0, 104, 56, 0)
        module.verify_simulator_executable(table + binary() + binary())
        with self.assertRaises(ValueError): module.verify_simulator_executable(table + binary() + binary(2))

    def fake_codesign(self, *, entitlements=None, identity=None, failure=None, readback=None):
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            self.assertTrue(kwargs['check']); self.assertTrue(kwargs['capture_output'])
            self.assertEqual(command[0], '/usr/bin/codesign')
            self.assertEqual(command[-1], str(self.host))
            self.assertNotIn('--deep', command)
            if failure is not None and len(calls) == failure:
                raise subprocess.CalledProcessError(1, command)
            if '--force' in command:
                path = Path(command[command.index('--entitlements') + 1])
                self.assertTrue(path.is_relative_to(self.root))
                self.assertEqual(plistlib.loads(path.read_bytes()), {})
                self.assertEqual(command[command.index('--sign') + 1], '-')
            if '--display' in command and '--entitlements' in command:
                if readback is not None:
                    return SimpleNamespace(stdout=readback[0], stderr=readback[1])
                # Documented modern default display is human-readable, not an XML plist.
                # This fixture is representative, not a claim about run94's unlogged bytes.
                output = (plistlib.dumps({} if entitlements is None else entitlements)
                          if '--xml' in command else b'[Dict]\n    [Key] application-identifier\n    [Value]\n        [String] TESTONLY.invalid.example.questify.ios\n')
                return SimpleNamespace(stdout=output, stderr=b'Executable=/synthetic/Questify.app/Questify\n')
            return SimpleNamespace(stdout=b'',
                                   stderr=(identity or 'Signature=adhoc\nTeamIdentifier=not set\n').encode())
        return calls, run

    def test_sign_commands_are_exact_and_temporary_plist_is_cleaned(self):
        calls, run = self.fake_codesign()
        module.sign_host(self.host, self.root, run)
        self.assertEqual(len(calls), 4)
        self.assertEqual(calls[2], ['/usr/bin/codesign', '--display', '--arch', 'arm64', '--entitlements', '-', '--xml', str(self.host)])
        self.assertFalse(list(self.root.glob('questify-test-entitlements-*')))

    def test_empty_signature_readback_is_required_for_each_architecture(self):
        first = binary()
        second = bytearray(binary()); struct.pack_into('<I', second, 4, 0x01000007)
        table = struct.pack('>2I', 0xcafebabe, 2) + struct.pack('>5I', 0x0100000c, 0, 48, 56, 0) + struct.pack('>5I', 0x01000007, 0, 104, 56, 0)
        (self.host / 'Questify').write_bytes(table + first + second)
        calls, run = self.fake_codesign()
        module.sign_host(self.host, self.root, run)
        self.assertEqual(len(calls), 6)
        self.assertEqual([call[call.index('--arch') + 1] for call in calls[2:]], ['arm64', 'arm64', 'x86_64', 'x86_64'])
        calls, fake = self.fake_codesign()
        def mismatch(command, **kwargs):
            result = fake(command, **kwargs)
            if '--arch' in command and 'x86_64' in command and '--entitlements' in command:
                result.stdout = plistlib.dumps(module.ENTITLEMENTS)
            return result
        with self.assertRaises(ValueError): module.sign_host(self.host, self.root, mismatch)
        self.assertEqual(len(calls), 5)

    def test_missing_extra_or_wrong_entitlement_fails(self):
        for entitlements in [module.ENTITLEMENTS, {**module.ENTITLEMENTS, 'get-task-allow': True},
                             {**module.ENTITLEMENTS, 'keychain-access-groups': ['real.user.group']}]:
            _, run = self.fake_codesign(entitlements=entitlements)
            with self.assertRaises(ValueError): module.sign_host(self.host, self.root, run)

    def test_failed_sign_or_verify_never_continues(self):
        for failure in [1, 2, 3, 4]:
            calls, run = self.fake_codesign(failure=failure)
            with self.assertRaises(subprocess.CalledProcessError): module.sign_host(self.host, self.root, run)
            self.assertEqual(len(calls), failure)
            self.assertFalse(list(self.root.glob('questify-test-entitlements-*')))

    def test_nonadhoc_or_team_signature_fails(self):
        for identity in ['Signature=Developer ID\nTeamIdentifier=not set\n', 'Signature=adhoc\nTeamIdentifier=REALTEAM\n']:
            _, run = self.fake_codesign(identity=identity)
            with self.assertRaises(ValueError): module.sign_host(self.host, self.root, run)

    def test_cli_without_explicit_optin_cannot_sign(self):
        from unittest.mock import patch
        with patch('sys.argv', ['prepare', '--xctestrun', str(self.run), '--commit', self.commit]), \
             patch.object(module, 'sign_host') as sign, patch.object(module.sys, 'platform', 'darwin'), \
             patch.dict(module.os.environ, {'GITHUB_ACTIONS': 'true', 'RUNNER_TEMP': str(self.root)}):
            with self.assertRaises(ValueError): module.main()
            sign.assert_not_called()

    def test_workflow_is_app_unit_only_after_restore_before_execution(self):
        source = (Path(__file__).resolve().parents[2] / '.github/workflows/native-ios.yml').read_text()
        app_unit = source.split('  app-unit-tests:\n', 1)[1].split('  ui-tests:\n', 1)[0]
        self.assertEqual(source.count('python3 tools/build_simulator_keychain_host.py'), 1)
        self.assertLess(app_unit.index('test_products.py restore'), app_unit.index('build_simulator_keychain_host.py'))
        self.assertLess(app_unit.index('build_simulator_keychain_host.py'), app_unit.index('test-without-building'))
        self.assertIn('--approve-ephemeral-simulator-host', app_unit)
        self.assertNotIn('continue-on-error', app_unit)
        self.assertIn('CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build-for-testing', source)

    def test_trusted_temp_root_alias_accepts_lexical_and_canonical_run(self):
        # Exercise macOS-style /var -> /private/var spelling on every platform.
        with tempfile.TemporaryDirectory() as alias_parent:
            alias = Path(alias_parent) / "trusted-temp-alias"
            alias.symlink_to(self.root.resolve(strict=True), target_is_directory=True)
            lexical_run = alias / self.run.relative_to(self.root)
            expected = (self.host.resolve(strict=True), self.root.resolve(strict=True))
            self.assertEqual(module.validate_host(lexical_run, alias, self.commit), expected)
            self.assertEqual(module.validate_host(self.run.resolve(strict=True), alias, self.commit), expected)

    def test_trusted_alias_does_not_resolve_descendant_symlinks(self):
        with tempfile.TemporaryDirectory() as alias_parent:
            alias = Path(alias_parent) / "trusted-temp-alias"
            alias.symlink_to(self.root.resolve(strict=True), target_is_directory=True)
            lexical_run = alias / self.run.relative_to(self.root)
            original = self.run.with_suffix('.original')
            self.run.rename(original)
            self.run.symlink_to(original.name)  # even an in-root link must fail
            with self.assertRaises(ValueError): module.validate_host(lexical_run, alias, self.commit)
            self.run.unlink(); original.rename(self.run)
            restore = self.root / 'prebuilt-tests'
            restore.rename(self.root / 'elsewhere')
            restore.symlink_to(self.root / 'elsewhere', target_is_directory=True)
            with self.assertRaises(ValueError): module.validate_host(lexical_run, alias, self.commit)

    def test_trusted_alias_still_rejects_traversal_and_unrelated_alias(self):
        with tempfile.TemporaryDirectory() as alias_parent:
            alias = Path(alias_parent) / "trusted-temp-alias"
            alias.symlink_to(self.root.resolve(strict=True), target_is_directory=True)
            run_tail = self.run.relative_to(self.root)
            traversal = alias / 'prebuilt-tests/Products/../Products' / self.run.name
            with self.assertRaises(ValueError): module.validate_host(traversal, alias, self.commit)
            unrelated = Path(alias_parent) / "untrusted-alias"
            unrelated.symlink_to(self.root.resolve(strict=True), target_is_directory=True)
            with self.assertRaises(ValueError): module.validate_host(unrelated / run_tail, alias, self.commit)

    def test_default_display_is_not_treated_as_a_plist(self):
        _, run = self.fake_codesign()
        result = run(['/usr/bin/codesign', '--display', '--entitlements', '-', str(self.host)],
                     check=True, capture_output=True)
        with self.assertRaises(plistlib.InvalidFileException): plistlib.loads(result.stdout)
        with self.assertRaises(ValueError): module.readback_entitlements(result.stdout, result.stderr)

    def test_xml_readback_ignores_stderr_diagnostics(self):
        xml = plistlib.dumps({})
        calls, run = self.fake_codesign(readback=(xml, b'Executable=/synthetic/path\nwarning: synthetic diagnostic\n'))
        module.sign_host(self.host, self.root, run)
        self.assertEqual(len(calls), 4)

    def test_bad_format_wrong_stream_and_ambiguous_keys_fail_closed(self):
        xml = plistlib.dumps(module.ENTITLEMENTS)
        duplicate = xml.replace(b'<dict>', b'<dict><key>application-identifier</key><string>WRONG</string>', 1)
        cases = [(b'', xml), (b'[Dict]\n [Key] application-identifier', b''),
                 (b'Executable=/synthetic/path\n' + xml, b''), (xml[:-20], b''),
                 (plistlib.dumps(module.ENTITLEMENTS, fmt=plistlib.FMT_BINARY), b''),
                 (duplicate, b''), (b'x' * 16_385, b''), (b'not-xml', b'PRIVATE-DIAGNOSTIC')]
        for output in cases:
            with self.subTest(length=len(output[0])):
                calls, run = self.fake_codesign(readback=output)
                with self.assertRaises(ValueError) as caught: module.sign_host(self.host, self.root, run)
                self.assertEqual(len(calls), 3)  # never retry signing or fall back to stderr
                self.assertIn('stdout_bytes=', str(caught.exception))
                self.assertIn('stderr_bytes=', str(caught.exception))
                self.assertNotIn('PRIVATE-DIAGNOSTIC', str(caught.exception))
                self.assertNotIn('/synthetic/path', str(caught.exception))
                self.assertNotIn('WRONG', str(caught.exception))
                self.assertFalse(list(self.root.glob('questify-test-entitlements-*')))
