#!/usr/bin/env python3
"""Run the actual restart component and encrypted-slot handoff on cloud Linux.

Uses pinned official apple/swift-crypto for CryptoKit-compatible AES-GCM, without
changing the production engine. Apple CryptoKit, Security/filesystem primitives,
full Core/App compilation and actual App acceptance are not exercised.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift', default='swift')
    parser.add_argument('--swift-crypto', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    crypto = args.swift_crypto.resolve()
    pin = '06dc63c6d8da54ee11ceb268cde1fa68161afc96'
    assert subprocess.check_output(['git', '-C', str(crypto), 'rev-parse', 'HEAD'], text=True).strip() == pin
    assert not subprocess.check_output(['git', '-C', str(crypto), 'diff', '--name-only'], text=True).strip()
    spec = importlib.util.spec_from_file_location('qa_receipt_runner', root / 'tools/test_qa_text_receipt_candidate.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    extract = module.declaration
    dependencies = [('Core/APIConfiguration.swift', 'public enum APIError:'),
                    ('Core/APIConfiguration.swift', 'public struct APIConfiguration'),
                    ('Core/APIConfiguration.swift', 'public enum AuthEndpoint:'),
                    ('Core/PlayExperienceContracts.swift', 'public indirect enum PlayWireValue:'),
                    ('Core/PlayExperienceContracts.swift', 'public struct PlayExperienceSession:'),
                    ('Core/PlayExperienceContracts.swift', 'extension PlayExperienceSession'),
                    ('Core/PlayExperienceContracts.swift', 'public enum PlayExperienceError:'),
                    ('Core/PlayAdvancedRuntime.swift', 'public struct PlayAdvancedPending:'),
                    ('Core/PlayRecoveryStorage.swift', 'public struct PlayRecoveryOwner:'),
                    ('Core/PlayContracts.swift', 'public enum PlaySessionScope:'),
                    ('Core/PlayRunLifecycle.swift', 'public enum PlayRunStorageKey'),
                    ('Core/VersionedContentDraftContracts.swift', 'public enum ContentDraftIssue:'),
                    ('Core/ContentDraftDurableJournal.swift', 'public struct ContentDraftAnchorItem:'),
                    ('Core/ContentDraftDurableJournal.swift', 'public protocol ContentDraftAnchorStore:'),
                    ('Core/ContentDraftDurableJournal.swift', 'public protocol ContentDraftCiphertextStore:')]
    package = output / 'package'
    source = package / 'Sources/QuestifyCore'; source.mkdir(parents=True, exist_ok=True)
    tests = package / 'Tests/QuestifyCoreTests'; tests.mkdir(parents=True, exist_ok=True)
    adapter = package / 'Sources/CryptoKit'; adapter.mkdir(parents=True, exist_ok=True)
    (adapter / 'Exports.swift').write_text('@_exported import Crypto\n')
    evidence = {'scope': 'actual receipt identity, restart state machine and encrypted-slot handoff; synthetic stores/reader',
                'crypto': {'upstream': 'https://github.com/apple/swift-crypto', 'tag': '3.9.1', 'commit': pin,
                           'backend': 'Swift Crypto on Linux, re-exported as CryptoKit; Apple implementation not exercised'},
                'declarations': []}
    snippets = []
    for relative, marker in dependencies:
        path = root / relative; code = extract(path.read_text(), marker); snippets.append(code)
        evidence['declarations'].append({'path': relative, 'marker': marker, 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                        'fragment_sha256': hashlib.sha256(code.encode()).hexdigest()})
    (source / 'ExactProductionDependencies.swift').write_text('import Foundation\n' + '\n'.join(snippets) + '\n')
    shutil.copyfile(root / 'Core/AuthRequestBuilder.swift', source / 'AuthRequestBuilder.swift')
    production = ['PlayQATextActionReceipt.swift', 'PlayQATextReceiptRequest.swift', 'PlayQATextRestartJournal.swift', 'PlayQATextRestartRecovery.swift']
    for name in production: shutil.copyfile(root / 'Core' / name, source / name)
    shared = (root / 'Core/PlayDurableRecovery.swift').read_text()
    engine = extract(shared, 'private struct PlayEncryptedSnapshot:') + '\n' + extract(shared, 'private actor PlayEncryptedSlot')
    fragment = (root / 'docs/qa-text-restart/PlayQATextDurableRestartJournal.swift.fragment').read_text()
    (source / 'EncryptedRestartHandoff.swift').write_text('import Foundation\nimport CryptoKit\n' + engine + '\n' + fragment)
    evidence['encrypted_engine_sha256'] = hashlib.sha256(engine.encode()).hexdigest()
    evidence['adapter_fragment_sha256'] = hashlib.sha256(fragment.encode()).hexdigest()
    fixture_source = (root / 'Tests/CoreTests/ContentDraftDurableJournalTests.swift').read_text()
    fixture = extract(fixture_source, '    actor Anchors:') + '\n' + extract(fixture_source, '    actor Blobs:')
    (tests / 'ExistingStorageFixtures.swift').write_text('import Foundation\n@testable import QuestifyCore\nenum ContentDraftDurableJournalTests {\n' + fixture + '\n}\n')
    evidence['existing_storage_fixture_sha256'] = hashlib.sha256(fixture.encode()).hexdigest()
    for name in ['PlayQATextActionReceiptTests.swift', 'PlayQATextRestartRecoveryTests.swift']:
        shutil.copyfile(root / 'Tests/CoreTests' / name, tests / name)
    shutil.copyfile(root / 'docs/qa-text-restart/PlayQATextDurableRestartTests.swift.fragment', tests / 'PlayQATextDurableRestartTests.swift')
    (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QATextRestartCandidate", dependencies: [.package(path: ''' + json.dumps(str(crypto)) + ''')], targets: [
    .target(name: "CryptoKit", dependencies: [.product(name: "Crypto", package: "swift-crypto-3.9.1")]),
    .target(name: "QuestifyCore", dependencies: ["CryptoKit"]),
    .testTarget(name: "QuestifyCoreTests", dependencies: ["QuestifyCore"])])
''')
    environment = os.environ.copy()
    environment['CLANG_MODULE_CACHE_PATH'] = str(package / 'cache/clang')
    environment['SWIFTPM_MODULECACHE_OVERRIDE'] = str(package / 'cache/swift')
    environment['SWIFTPM_TESTS_MODULECACHE'] = str(package / 'cache/tests')
    command = [args.swift, 'test', '--package-path', str(package), '--cache-path', str(package / 'cache/pm'),
               '--config-path', str(package / 'config'), '--security-path', str(package / 'security'), '--jobs', '4']
    with (output / 'tests.log').open('w') as log:
        result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT)
    evidence['exit_code'] = result.returncode
    resolved = package / 'Package.resolved'
    if resolved.is_file(): evidence['resolved_dependencies'] = json.loads(resolved.read_text())
    evidence['apple_compile'] = evidence['system_storage_exercised'] = evidence['real_backend_contacted'] = False
    (output / 'test-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'exit_code': result.returncode, 'crypto_commit': pin, 'evidence': str(output / 'test-evidence.json')}, indent=2))
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
