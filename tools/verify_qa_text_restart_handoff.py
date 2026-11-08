#!/usr/bin/env python3
"""Check both QA handoff patches in a disposable copy; never edit shared files."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swiftc', default='swiftc')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((root / 'docs/qa-text-restart/integration-preimages.json').read_text())
    shared = ['Core/PlayAdvancedRuntime.swift', 'Core/PlayDurableRecovery.swift', 'App/AppSession.swift',
              'App/PlayAdvancedView.swift', 'App/PlayKitScreen.swift', 'Questify.xcodeproj/project.pbxproj']
    before = {p: sha(root / p) for p in shared}
    evidence = {'shared_checkout_unchanged': False, 'apple_type_compilation': False,
                'runtime_appunit_execution': False, 'system_storage_acceptance': False, 'live_backend': False}
    with tempfile.TemporaryDirectory(prefix='qa-restart-handoff-') as directory:
        copy = Path(directory) / 'source'
        shutil.copytree(root, copy, ignore=shutil.ignore_patterns('.git', '.build', '__pycache__'))
        subprocess.run(['git', 'init', '-q', str(copy)], check=True)
        subprocess.run(['git', 'apply', 'docs/qa-text-receipt/integration.patch'], cwd=copy, check=True)
        for path, row in manifest.items():
            if row['before_sha256'] is None: assert not (copy / path).exists(), path
            else: assert sha(copy / path) == row['before_sha256'], path
        subprocess.run(['git', 'apply', '--check', 'docs/qa-text-restart/integration-after-receipt.patch'], cwd=copy, check=True)
        subprocess.run(['git', 'apply', 'docs/qa-text-restart/integration-after-receipt.patch'], cwd=copy, check=True)
        for path, row in manifest.items(): assert sha(copy / path) == row['after_sha256'], path
        spec = importlib.util.spec_from_file_location('qa_current_ci', copy / 'tools/current_ci.py')
        ci = importlib.util.module_from_spec(spec); spec.loader.exec_module(ci)
        assert ci.pbx_registration_only((root / 'Questify.xcodeproj/project.pbxproj').read_text(), (copy / 'Questify.xcodeproj/project.pbxproj').read_text())
        spec = importlib.util.spec_from_file_location('qa_receipt_extract', copy / 'tools/test_qa_text_receipt_candidate.py')
        slices = importlib.util.module_from_spec(spec); spec.loader.exec_module(slices)
        original = (root / 'Core/PlayDurableRecovery.swift').read_text()
        patched = (copy / 'Core/PlayDurableRecovery.swift').read_text()
        for marker in ['private struct PlayEncryptedSnapshot:', 'private actor PlayEncryptedSlot']:
            assert slices.declaration(original, marker) == slices.declaration(patched, marker)
        fragment = (root / 'docs/qa-text-restart/PlayQATextDurableRestartJournal.swift.fragment').read_text()
        assert fragment in patched
        evidence['encrypted_engine_unchanged'] = evidence['fragment_matches_patched_shared_source'] = True
        with (output / 'scaffold.log').open('w') as log:
            result = subprocess.run(['python3', 'tools/check_scaffold.py'], cwd=copy, stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0, 'See scaffold.log'
        evidence['scaffold_exit_code'] = result.returncode
        swift = set(p for p in manifest if p.endswith('.swift'))
        swift.update(['App/PlayKitScreen.swift', 'Core/PlayQATextReceiptRequest.swift', 'Core/PlayQATextRestartJournal.swift',
                      'Core/PlayQATextRestartRecovery.swift', 'Core/PlayQATextActionReceipt.swift', 'Core/PlayQATextReceiptService.swift',
                      'Tests/CoreTests/PlayQATextRestartRecoveryTests.swift'])
        with (output / 'swift-syntax.log').open('w') as log:
            result = subprocess.run([args.swiftc, '-frontend', '-parse', *[str(copy / p) for p in sorted(swift)]], stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0, 'See swift-syntax.log'
        evidence['swift_syntax_exit_code'] = result.returncode
        evidence['patched_shared_hashes'] = {p: sha(copy / p) for p in shared}
    assert {p: sha(root / p) for p in shared} == before
    evidence['shared_checkout_unchanged'] = True
    (output / 'handoff-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__': main()
