#!/usr/bin/env python3
"""Execute receipt identity/failure-policy production code on Linux.

The isolated package uses exact existing production declarations, without service,
coordinator or UI substitutes. AppUnit integration tests require Apple and the
documented Runtime/PBX patch; this runner does not claim to execute those tests.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def declaration(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift', default='swift')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    dependencies = [('Core/APIConfiguration.swift', 'public enum APIError:'),
                    ('Core/PlayExperienceContracts.swift', 'public indirect enum PlayWireValue:'),
                    ('Core/PlayExperienceContracts.swift', 'public enum PlayExperienceError:'),
                    ('Core/PlayAdvancedRuntime.swift', 'public struct PlayAdvancedPending:')]
    evidence = {'scope': 'production receipt identity decoder and failure policy; no coordinator/service/App execution', 'declarations': []}
    with tempfile.TemporaryDirectory(prefix='qa-text-receipt-') as directory:
        package = Path(directory)
        sources = package / 'Sources/QuestifyCore'; sources.mkdir(parents=True)
        tests = package / 'Tests/QuestifyCoreTests'; tests.mkdir(parents=True)
        extracted = []
        for relative, marker in dependencies:
            path = root / relative; fragment = declaration(path.read_text(), marker)
            extracted.append(fragment)
            evidence['declarations'].append({'path': relative, 'marker': marker,
                'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'fragment_sha256': hashlib.sha256(fragment.encode()).hexdigest()})
        (sources / 'ExactProductionDependencies.swift').write_text('import Foundation\n' + '\n'.join(extracted) + '\n')
        shutil.copyfile(root / 'Core/PlayQATextActionReceipt.swift', sources / 'PlayQATextActionReceipt.swift')
        shutil.copyfile(root / 'Tests/CoreTests/PlayQATextActionReceiptTests.swift', tests / 'PlayQATextActionReceiptTests.swift')
        (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QATextReceiptCandidate", targets: [.target(name: "QuestifyCore"), .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"])])
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
