"""Synthetic source/link fixtures only: no Apple commands or permissions."""
import copy
import io
import json
from pathlib import Path
import plistlib
import struct
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_simulator_keychain_host as build
import prepare_simulator_keychain_host as host


def executable(payload=None, *, platform=7, section=b'__entitlements', segment=b'__TEXT'):
    payload = plistlib.dumps(host.ENTITLEMENTS) if payload is None else payload
    command_size = 24 + 72 + 80
    offset = 32 + command_size
    header = struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 2, 2, command_size, 0, 0)
    version = struct.pack('<6I', 0x32, 24, platform, 0, 0, 0)
    seg = struct.pack('<2I16s4Q4I', 0x19, 152, segment, 0, offset+len(payload), 0, offset+len(payload), 5, 5, 1, 0)
    sec = struct.pack('<16s16s2Q8I', section, segment, offset, len(payload), offset, 0, 0, 0, 0, 0, 0, 0)
    return header + version + seg + sec + payload


def project():
    return {'objects': {'host': {'isa': 'PBXNativeTarget', 'name': 'Questify', 'productType': 'com.apple.product-type.application', 'buildConfigurationList': 'configs'},
                        'configs': {'buildConfigurations': ['debug', 'release']},
                        'debug': {'name': 'Debug', 'buildSettings': {'PRODUCT_NAME': '$(TARGET_NAME)'}},
                        'release': {'name': 'Release', 'buildSettings': {}},
                        'test': {'name': 'Debug', 'buildSettings': {'PRODUCT_NAME': 'QuestifyAppUnitTests'}}}}


def archive(name='Questify.xcodeproj/project.pbxproj', kind=tarfile.REGTYPE):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode='w') as tar:
        member = tarfile.TarInfo(name); member.type = kind
        data = plistlib.dumps(project()); member.size = len(data) if kind == tarfile.REGTYPE else 0
        tar.addfile(member, io.BytesIO(data))
    return out.getvalue()


class SimulatedEntitlementTests(unittest.TestCase):
    def verify(self, data): host.verify_simulator_executable(data, require_entitlements=True)

    def test_exact_section(self): self.verify(executable())

    def test_missing_extra_wrong_and_duplicate_values(self):
        values = [{}, {**host.ENTITLEMENTS, 'get-task-allow': True},
                  {**host.ENTITLEMENTS, 'keychain-access-groups': ['other']},
                  {**host.ENTITLEMENTS, 'application-identifier': 'other'}]
        for value in values:
            with self.subTest(value=value), self.assertRaises(ValueError): self.verify(executable(plistlib.dumps(value)))
        xml = plistlib.dumps(host.ENTITLEMENTS).replace(b'<dict>', b'<dict><key>application-identifier</key><string>other</string>', 1)
        with self.assertRaises(ValueError): self.verify(executable(xml))

    def test_format_platform_section_and_segment_fail_closed(self):
        for data in [executable(b'bad'), executable(plistlib.dumps(host.ENTITLEMENTS, fmt=plistlib.FMT_BINARY)),
                     executable(platform=2), executable(section=b'__ents_der'), executable(segment=b'__DATA'),
                     executable(section=b'__other')]:
            with self.assertRaises(ValueError): self.verify(data)

    def test_bounds_flags_and_segment_table_rejected(self):
        for offset, fmt, value in [(56+64, '<I', 2), (128+48, '<I', 0),
                                   (128+40, '<Q', 999999), (128+64, '<I', 1), (56+48, '<Q', 1)]:
            data = bytearray(executable()); struct.pack_into(fmt, data, offset, value)
            with self.assertRaises(ValueError): self.verify(bytes(data))

    def test_every_fat_slice_must_match(self):
        first = executable(); second = executable()
        def fat(a,b):
            return struct.pack('>2I', 0xcafebabe, 2) + struct.pack('>5I', 0x0100000c, 0, 48, len(a), 0) + struct.pack('>5I', 0x0100000c, 0, 48+len(a), len(b), 0) + a+b
        self.verify(fat(first, second))
        with self.assertRaises(ValueError): self.verify(fat(first, executable(plistlib.dumps({}))))
        with self.assertRaises(ValueError): self.verify(fat(executable(platform=2), second))

    def test_only_copied_host_debug_simulator_settings_change(self):
        data = project(); before = copy.deepcopy(data)
        build.configure_host(data, Path('/temporary/own.plist'))
        settings = data['objects']['debug']['buildSettings']
        self.assertEqual(settings.pop('ENABLE_DEBUG_DYLIB[sdk=iphonesimulator*]'), 'NO')
        self.assertEqual(settings.pop('OTHER_LDFLAGS[sdk=iphonesimulator*]'), ['$(inherited)', '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__entitlements', '-Xlinker', '/temporary/own.plist'])
        self.assertEqual(data, before)

    def test_ambiguous_host_or_preexisting_linker_override_rejected(self):
        for mutation in ['host', 'debug', 'flags']:
            data = project()
            if mutation == 'host': data['objects']['host2'] = copy.deepcopy(data['objects']['host'])
            elif mutation == 'debug': data['objects']['configs']['buildConfigurations'].append('debug')
            else: data['objects']['debug']['buildSettings']['OTHER_LDFLAGS[sdk=iphonesimulator*]'] = '-anything'
            with self.assertRaises(ValueError): build.configure_host(data, Path('/tmp/own'))

    def test_archive_rejects_links_and_traversal(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('/escape', tarfile.REGTYPE), ('link', tarfile.SYMTYPE), ('hard', tarfile.LNKTYPE)]:
            with tempfile.TemporaryDirectory() as temp, self.assertRaises(ValueError):
                build.export_source(archive(name, kind), Path(temp)/'source')

    def test_source_export_is_fresh(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp)/'source'; build.export_source(archive(), dest)
            self.assertTrue((dest/'Questify.xcodeproj/project.pbxproj').is_file())
            with self.assertRaises(FileExistsError): build.export_source(archive(), dest)

    def test_exact_build_command_and_product_selection(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); calls=[]; commit='a'*40; simulator='01234567-0123-0123-0123-012345678901'
            def run(command, **kwargs):
                calls.append(command)
                if command[0] == 'git':
                    return SimpleNamespace(stdout=(commit+'\n').encode() if 'rev-parse' in command else archive())
                if command[0] == '/usr/bin/plutil': return SimpleNamespace(stdout=plistlib.dumps(project()))
                self.assertEqual(command[0], 'xcodebuild')
                self.assertEqual(command[command.index('-scheme')+1], 'QuestifyAppUnitTests')
                self.assertIn('CODE_SIGNING_ALLOWED=NO', command)
                derived=Path(command[command.index('-derivedDataPath')+1]); products=derived/'Build/Products'
                app=products/host.HOST_RELATIVE; app.mkdir(parents=True)
                (app/'Questify').write_bytes(executable())
                (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':host.BUNDLE_ID,'CFBundleExecutable':'Questify','CFBundleSupportedPlatforms':['iPhoneSimulator']}))
                (products/'unit.xctestrun').write_bytes(plistlib.dumps({'TestTargets':[{'TestBundlePath':str(app/'PlugIns/QuestifyAppUnitTests.xctest'), 'TestHostPath':str(app)}]}))
                return SimpleNamespace(stdout=b'')
            with patch.object(build, 'toolchain', return_value={'xcode':'synthetic'}), patch.object(build, 'sign_host') as sign:
                result=build.build(root,root,commit,simulator,run)
                self.assertTrue(result.is_relative_to(root/'app-unit-linked/Products'))
                sign.assert_called_once()
                self.assertEqual(len(calls),4)
                self.assertEqual(calls[1][-1],commit)
                with self.assertRaises(FileExistsError): build.build(root,root,commit,simulator,run)

    def test_bad_commit_uuid_and_checkout_fail_before_build(self):
        with tempfile.TemporaryDirectory() as temp:
            for commit, uuid in [('bad','bad'), ('a'*40,'bad')]:
                with self.assertRaises(ValueError): build.build(temp,temp,commit,uuid)
            with self.assertRaises(ValueError):
                build.build(temp,temp,'a'*40,'01234567-0123-0123-0123-012345678901',lambda *a,**k: SimpleNamespace(stdout=b'b'*40))
