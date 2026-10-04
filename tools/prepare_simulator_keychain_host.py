#!/usr/bin/env python3
"""Prepare only an ephemeral restored AppUnit simulator host; never release signing.

This helper requires explicit CLI opt-in. Calling validation functions or its unit
suite never runs codesign. No credentials, developer account, or profiles are used.
"""
import argparse
import os
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import tempfile

BUNDLE_ID = 'invalid.example.questify.ios'
APPLICATION_ID = 'TESTONLY.' + BUNDLE_ID
ENTITLEMENTS = {'application-identifier': APPLICATION_ID,
                'keychain-access-groups': [APPLICATION_ID]}
HOST_RELATIVE = 'Debug-iphonesimulator/Questify.app'


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def checked_path(root, path):
    """Only existing nonsymlink descendants of an already canonical trusted root."""
    path = Path(path)
    try:
        relative = path.relative_to(root)
    except ValueError:
        raise ValueError('Path outside temporary restore root') from None
    if not relative.parts or any(p in ('.', '..') for p in relative.parts):
        raise ValueError('Invalid restored relative path')
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink() or not current.exists():
            raise ValueError('Missing or symlinked restored path')
    return current


def verify_simulator_executable(data, require_entitlements=False):
    """Require every Mach-O slice to declare iOS Simulator, not an iOS device."""
    def thin(blob):
        if len(blob) < 32 or blob[:4] != b'\xcf\xfa\xed\xfe':
            raise ValueError('Expected a 64-bit little-endian Mach-O executable')
        _, cpu, _, kind, count, size, _, _ = struct.unpack_from('<8I', blob)
        if cpu not in (0x01000007, 0x0100000c) or kind != 2 or count > 4096 or size > len(blob) - 32:
            raise ValueError('Invalid simulator Mach-O header')
        position, platforms, payloads = 32, [], []
        for _ in range(count):
            if position + 8 > 32 + size:
                raise ValueError('Truncated Mach-O command')
            command, length = struct.unpack_from('<2I', blob, position)
            if length < 8 or position + length > 32 + size:
                raise ValueError('Invalid Mach-O command size')
            if command == 0x19 and require_entitlements:  # LC_SEGMENT_64
                if length < 72:
                    raise ValueError('Truncated segment')
                sections = struct.unpack_from('<I', blob, position + 64)[0]
                if length != 72 + sections * 80:
                    raise ValueError('Invalid segment section table')
                for index in range(sections):
                    section = position + 72 + index * 80
                    name, segment = struct.unpack_from('<16s16s', blob, section)
                    name, segment = name.rstrip(b'\0'), segment.rstrip(b'\0')
                    if name in (b'__entitlements', b'__ents_der'):
                        if (name != b'__entitlements' or segment != b'__TEXT'
                                or blob[position + 8:position + 24].rstrip(b'\0') != b'__TEXT'):
                            raise ValueError('Unexpected simulated entitlement section')
                        size_bytes = struct.unpack_from('<Q', blob, section + 40)[0]
                        offset = struct.unpack_from('<I', blob, section + 48)[0]
                        fileoff, filesize = struct.unpack_from('<QQ', blob, position + 40)
                        flags = struct.unpack_from('<I', blob, section + 64)[0]
                        if flags & 0xff or offset < fileoff or offset + size_bytes > fileoff + filesize:
                            raise ValueError('Entitlements must be a file-backed regular text section')
                        if not 0 < size_bytes <= 16384 or offset < 32 + size or offset + size_bytes > len(blob):
                            raise ValueError('Invalid entitlement section bounds')
                        payloads.append(blob[offset:offset + size_bytes])
            if command == 0x32:  # LC_BUILD_VERSION
                if length < 24:
                    raise ValueError('Truncated build version')
                platforms.append(struct.unpack_from('<I', blob, position + 8)[0])
            if command in (0x24, 0x25, 0x2f, 0x30):
                raise ValueError('Legacy/ambiguous platform command is not allowed')
            position += length
        if position != 32 + size or platforms != [7]:  # PLATFORM_IOSSIMULATOR
            raise ValueError('Every slice must declare exactly iOS Simulator')
        if require_entitlements:
            if len(payloads) != 1 or readback_entitlements(payloads[0], b'') != ENTITLEMENTS:
                raise ValueError('Every slice must contain exactly the synthetic simulated entitlements')
    if data[:4] != b'\xca\xfe\xba\xbe':
        thin(data)
        return
    if len(data) < 8:
        raise ValueError('Truncated fat header')
    count = struct.unpack_from('>I', data, 4)[0]
    if not 1 <= count <= 2 or len(data) < 8 + count * 20:
        raise ValueError('Invalid fat slice table')
    ranges = []
    for index in range(count):
        _, _, offset, size, _ = struct.unpack_from('>5I', data, 8 + index * 20)
        if offset < 8 + count * 20 or size > len(data) - offset:
            raise ValueError('Invalid fat slice bounds')
        if any(offset < end and start < offset + size for start, end in ranges):
            raise ValueError('Overlapping fat slices')
        ranges.append((offset, offset + size))
        thin(data[offset:offset + size])


def validate_host(xctestrun, runner_temp, commit, restore_name="prebuilt-tests"):
    if not re.fullmatch('[a-f0-9]{40}', commit):
        raise ValueError('Exact commit is required')
    temporary_spelling = Path(runner_temp).absolute()
    temporary = temporary_spelling.resolve(strict=True)
    # This layout is owned by test_products.py restore in the AppUnit job only.
    if restore_name not in ('prebuilt-tests', 'app-unit-linked'):
        raise ValueError('Invalid test product scope')
    restore = checked_path(temporary, temporary / restore_name)
    products = checked_path(restore, restore / 'Products')
    run_spelling = Path(xctestrun).absolute()
    # macOS may spell the trusted temporary root through /var -> /private/var.
    # Translate ONLY that known root prefix; never resolve an untrusted descendant.
    if run_spelling.is_relative_to(temporary_spelling):
        run_spelling = temporary / run_spelling.relative_to(temporary_spelling)
    run = checked_path(products, run_spelling)
    manifest_path = checked_path(products, products / 'questify-test-products.json')
    import json
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('commit') != commit or manifest.get('targets', {}).get('QuestifyAppUnitTests') != run.name:
        raise ValueError('Not the exact restored AppUnit product manifest')
    records = [v for v in walk(plistlib.loads(run.read_bytes())) if isinstance(v.get('TestBundlePath'), str)]
    units = [v for v in records if Path(v['TestBundlePath']).stem == 'QuestifyAppUnitTests']
    if len(units) != 1 or len(records) != 1:
        raise ValueError('Expected only one AppUnit test target')
    if units[0].get('TestHostPath') != '__TESTROOT__/' + HOST_RELATIVE:
        raise ValueError('Unexpected portable AppUnit host')
    host = checked_path(products, products / HOST_RELATIVE)
    info = plistlib.loads(checked_path(products, host / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != BUNDLE_ID or info.get('CFBundleExecutable') != 'Questify'
            or info.get('CFBundleSupportedPlatforms') != ['iPhoneSimulator']):
        raise ValueError('Unexpected host identity or platform')
    if (host / 'embedded.mobileprovision').exists():
        raise ValueError('Provisioned host is outside this test-only scope')
    executable = checked_path(products, host / 'Questify')
    verify_simulator_executable(executable.read_bytes())
    return host, temporary


class UniqueEntitlementKeys(dict):
    def __setitem__(self, key, value):
        if key in self:
            raise ValueError('Duplicate entitlement key')
        super().__setitem__(key, value)


def readback_entitlements(stdout, stderr):
    # Apple TN3125 documents --entitlements - --xml: plist to stdout;
    # normal codesign diagnostics remain on stderr. Never merge or scrape streams.
    # Bound the expected tiny, self-only dictionary and reject ambiguous duplicate keys.
    try:
        if not stdout or len(stdout) > 16_384:
            raise ValueError('Unexpected entitlement output size')
        return plistlib.loads(stdout, fmt=plistlib.FMT_XML, dict_type=UniqueEntitlementKeys)
    except Exception:
        stripped = stdout.lstrip()
        kind = ('empty' if not stripped else 'xml-like' if stripped.startswith(b'<')
                else 'binary-plist' if stripped.startswith(b'bplist') else 'other')
        raise ValueError('Entitlement XML readback invalid: '
                         f'stdout_bytes={len(stdout)} stderr_bytes={len(stderr)} format={kind}') from None


def sign_host(host, temporary, run=subprocess.run):
    # Ad-hoc '-' uses no signing identity, certificate, or keychain lookup.
    # Never use --deep, preserve-metadata, or inject a team/app-group entitlement.
    with tempfile.TemporaryDirectory(prefix='questify-test-entitlements-', dir=temporary) as folder:
        entitlement_path = Path(folder) / 'host.plist'
        entitlement_path.write_bytes(plistlib.dumps({}))
        run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none',
             '--entitlements', str(entitlement_path), str(host)], check=True, capture_output=True)
        run(['/usr/bin/codesign', '--verify', '--strict', str(host)], check=True, capture_output=True)
        executable = (host / 'Questify').read_bytes()
        verify_simulator_executable(executable)
        offsets = ([struct.unpack_from('>I', executable, 8 + index * 20 + 8)[0]
                    for index in range(struct.unpack_from('>I', executable, 4)[0])]
                   if executable[:4] == b'\xca\xfe\xba\xbe' else [0])
        architectures = [struct.unpack_from('<I', executable, offset + 4)[0] for offset in offsets]
        if len(set(architectures)) != len(architectures):
            raise ValueError('Duplicate Mach-O architecture')
        for architecture in architectures:
            name = {0x01000007: 'x86_64', 0x0100000c: 'arm64'}[architecture]
            result = run(['/usr/bin/codesign', '--display', '--arch', name,
                          '--entitlements', '-', '--xml', str(host)], check=True, capture_output=True)
            if readback_entitlements(result.stdout, result.stderr) != {}:
                raise ValueError('Signed host entitlements must be empty in every architecture')
            identity = run(['/usr/bin/codesign', '--display', '--arch', name, '--verbose=4', str(host)], check=True, capture_output=True)
            lines = identity.stderr.decode('utf-8').splitlines()
            if 'Signature=adhoc' not in lines or 'TeamIdentifier=not set' not in lines:
                raise ValueError('Host signature is not team-free ad-hoc signing')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xctestrun', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--approve-ephemeral-simulator-host', action='store_true')
    args = parser.parse_args()
    if not args.approve_ephemeral_simulator_host or sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Explicit opt-in on the ephemeral Apple CI runner is required')
    if not os.environ.get('RUNNER_TEMP'):
        raise ValueError('RUNNER_TEMP is required')
    host, temporary = validate_host(args.xctestrun, os.environ['RUNNER_TEMP'], args.commit)
    verify_simulator_executable((host / 'Questify').read_bytes(), require_entitlements=True)
    sign_host(host, temporary)
    verify_simulator_executable((host / 'Questify').read_bytes(), require_entitlements=True)
    print('Verified ephemeral AppUnit simulator host: synthetic self-only Keychain entitlement')


if __name__ == '__main__':
    main()
