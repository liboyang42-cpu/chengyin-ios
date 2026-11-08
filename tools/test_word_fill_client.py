#!/usr/bin/env python3
"""Run the real word-fill model and its tests in an isolated Swift package.

No Xcode project, backend contract, action registration, network or production
service is exercised. The app's full Core target can run the same XCTest file.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift', default='swift')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    paths = ['Core/PlayWordFillDraft.swift', 'Tests/CoreTests/PlayWordFillDraftTests.swift']
    evidence = {'scope': 'production word-fill model and unchanged XCTest source copies only',
                'sources': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths}}
    with tempfile.TemporaryDirectory(prefix='word-fill-client-') as directory:
        package = Path(directory)
        sources = package / 'Sources/QuestifyCore'; sources.mkdir(parents=True)
        tests = package / 'Tests/QuestifyCoreTests'; tests.mkdir(parents=True)
        shutil.copyfile(root / paths[0], sources / 'PlayWordFillDraft.swift')
        shutil.copyfile(root / paths[1], tests / 'PlayWordFillDraftTests.swift')
        (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WordFillClient", targets: [.target(name: "QuestifyCore"), .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"])])
''')
        environment = os.environ.copy()
        environment['CLANG_MODULE_CACHE_PATH'] = str(package / 'cache/clang')
        environment['SWIFTPM_MODULECACHE_OVERRIDE'] = str(package / 'cache/swift')
        command = [args.swift, 'test', '--package-path', str(package), '--cache-path', str(package / 'cache/pm'),
                   '--config-path', str(package / 'config'), '--security-path', str(package / 'security'), '--jobs', '2']
        with (output / 'tests.log').open('w') as log:
            result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT)
        evidence['exit_code'] = result.returncode
        (output / 'test-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps(evidence, indent=2))
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
