#!/usr/bin/env python3
"""Exact-commit, AppUnit-only simulator relink in ephemeral CI storage.

Apple Swift Build Embedded-Simulator.xcspec documents __TEXT,__entitlements.
Only the copied app Debug configuration changes. Never alters checkout/shared
products, release/device settings, nested signatures, profiles or credentials.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import sys
import tarfile

from prepare_simulator_keychain_host import (ENTITLEMENTS, checked_path, sign_host,
                                             validate_host, verify_simulator_executable)
from test_products import normalize_paths, walk, toolchain


def export_source(archive, destination):
    destination.mkdir()  # must be fresh, never reuse/overwrite a prior build
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        for entry in source:
            relative = PurePosixPath(entry.name)
            if relative.is_absolute() or not relative.parts or '..' in relative.parts or not (entry.isdir() or entry.isfile()):
                raise ValueError('Unsafe source archive member')
            target = destination.joinpath(*relative.parts)
            if entry.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open('xb') as output:
                    output.write(source.extractfile(entry).read())


def configure_host(project, entitlement_path):
    objects = project['objects']
    hosts = [o for o in objects.values() if o.get('isa') == 'PBXNativeTarget'
             and o.get('name') == 'Questify' and o.get('productType') == 'com.apple.product-type.application']
    if len(hosts) != 1:
        raise ValueError('Expected exactly one test host app target')
    configurations = objects[hosts[0]['buildConfigurationList']]['buildConfigurations']
    debug = [objects[key] for key in configurations if objects[key].get('name') == 'Debug']
    if len(debug) != 1:
        raise ValueError('Expected one host Debug configuration')
    settings = debug[0]['buildSettings']
    if any(key.startswith(('OTHER_LDFLAGS', 'ENABLE_DEBUG_DYLIB')) for key in settings):
        raise ValueError('Unexpected existing host linker override')
    settings['ENABLE_DEBUG_DYLIB[sdk=iphonesimulator*]'] = 'NO'
    settings['OTHER_LDFLAGS[sdk=iphonesimulator*]'] = [
        '$(inherited)', '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT',
        '-Xlinker', '__entitlements', '-Xlinker', str(entitlement_path)]


def build(source_root, runner_temp, commit, simulator, run=subprocess.run):
    if not re.fullmatch('[a-f0-9]{40}', commit) or not re.fullmatch('[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}', simulator):
        raise ValueError('Exact commit and simulator UUID required')
    source_root = Path(source_root).resolve(strict=True)
    temporary = Path(runner_temp).resolve(strict=True)
    def git(*args):
        return run(['git', '-C', str(source_root), *args], check=True, capture_output=True).stdout
    if git('rev-parse', 'HEAD').decode().strip() != commit:
        raise ValueError('Checkout does not match requested build commit')
    work = temporary / 'app-unit-linked'
    work.mkdir()  # fresh per job, fail on links or stale products
    source = work / 'source'
    archive = git('archive', '--format=tar', commit)
    export_source(archive, source)
    entitlement = work / 'simulated-entitlements.plist'
    entitlement.write_bytes(plistlib.dumps(ENTITLEMENTS))
    project = source / 'Questify.xcodeproj/project.pbxproj'
    result = run(['/usr/bin/plutil', '-convert', 'xml1', '-o', '-', str(project)], check=True, capture_output=True)
    data = plistlib.loads(result.stdout)
    configure_host(data, entitlement)
    project.write_bytes(plistlib.dumps(data))
    derived = work / 'DerivedData'
    run(['xcodebuild', '-project', str(project.parent), '-scheme', 'QuestifyAppUnitTests',
         '-configuration', 'Debug', '-sdk', 'iphonesimulator', '-destination',
         'platform=iOS Simulator,id=' + simulator, '-destination-timeout', '60',
         '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO', 'ONLY_ACTIVE_ARCH=NO',
         'build-for-testing'], check=True)
    built = checked_path(work, derived / 'Build/Products')
    products = work / 'Products'
    built.rename(products)
    runs = list(products.glob('*.xctestrun'))
    if len(runs) != 1:
        raise ValueError('Expected only AppUnit xctestrun')
    test_run = runs[0]
    # Normalize the original build location before it was moved.
    data = normalize_paths(plistlib.loads(test_run.read_bytes()), built)
    records = [v for v in walk(data) if isinstance(v.get('TestBundlePath'), str)]
    if len(records) != 1 or Path(records[0]['TestBundlePath']).stem != 'QuestifyAppUnitTests':
        raise ValueError('Unexpected rebuilt test target')
    test_run.write_bytes(plistlib.dumps(data))
    (products / 'questify-test-products.json').write_text(json.dumps({
        'commit': commit, 'targets': {'QuestifyAppUnitTests': test_run.name},
        'toolchain': toolchain(), 'source_archive_sha256': hashlib.sha256(archive).hexdigest(),
        'purpose': 'isolated-simulator-app-unit'}))
    host, temporary = validate_host(test_run, temporary, commit, restore_name='app-unit-linked')
    verify_simulator_executable((host / 'Questify').read_bytes(), require_entitlements=True)
    sign_host(host, temporary)
    verify_simulator_executable((host / 'Questify').read_bytes(), require_entitlements=True)
    return test_run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--approve-ephemeral-simulator-host', action='store_true')
    args = parser.parse_args()
    if not args.approve_ephemeral_simulator_host or sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Explicit opt-in on ephemeral Apple CI required')
    result = build(args.source_root, os.environ['RUNNER_TEMP'], args.commit, args.simulator)
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write('APP_UNIT_XCTESTRUN=' + str(result) + '\n')
    print('Verified isolated AppUnit simulator: exact simulated entitlements and empty ad-hoc signature entitlements')


if __name__ == '__main__':
    main()
