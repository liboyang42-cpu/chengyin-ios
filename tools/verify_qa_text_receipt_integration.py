#!/usr/bin/env python3
"""Apply the handoff patch only in a disposable source copy, then verify it.

This never edits the checkout's shared files, invokes CI, contacts a backend or
claims Apple type compilation. Swift frontend parsing checks syntax only.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swiftc', default='swiftc')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((root / 'docs/qa-text-receipt/integration-preimages.json').read_text())
    allowed = {'Core/PlayAdvancedRuntime.swift', 'App/PlayAdvancedView.swift', 'App/PlayKitScreen.swift', 'Questify.xcodeproj/project.pbxproj'}
    assert set(manifest) == allowed
    initial = {p: digest(root / p) for p in allowed}
    for p, row in manifest.items():
        assert initial[p] == row['before_sha256'], ('Unexpected shared preimage', p)
    evidence = {'checkout_shared_files_unchanged': False, 'patch_applied_in_disposable_copy': False,
                'apple_type_compilation': 'not run', 'appunit_execution': 'not run', 'real_backend': 'not contacted'}
    with tempfile.TemporaryDirectory(prefix='qa-receipt-integration-') as directory:
        copy = Path(directory) / 'source'
        shutil.copytree(root, copy, ignore=shutil.ignore_patterns('.git', '.build', '__pycache__'))
        # An empty isolated Git worktree prevents git apply from discovering a
        # parent repository or considering the real checkout as its worktree.
        subprocess.run(['git', 'init', '-q', str(copy)], check=True)
        subprocess.run(['git', 'apply', '--check', 'docs/qa-text-receipt/integration.patch'], cwd=copy, check=True)
        subprocess.run(['git', 'apply', 'docs/qa-text-receipt/integration.patch'], cwd=copy, check=True)
        for p, row in manifest.items():
            assert digest(copy / p) == row['after_sha256'], ('Unexpected integration postimage', p)
        spec = importlib.util.spec_from_file_location('qa_receipt_current_ci', copy / 'tools/current_ci.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        assert module.pbx_registration_only((root / 'Questify.xcodeproj/project.pbxproj').read_text(), (copy / 'Questify.xcodeproj/project.pbxproj').read_text())
        evidence['pbx_registration_only'] = True
        with (output / 'scaffold.log').open('w') as log:
            result = subprocess.run(['python3', 'tools/check_scaffold.py'], cwd=copy, stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0, 'See scaffold.log'
        evidence['scaffold_exit_code'] = result.returncode
        swift = [str(copy / p) for p in sorted(allowed) if p.endswith('.swift')]
        swift += [str(copy / p) for p in ['Core/PlayQATextActionReceipt.swift', 'Core/PlayQATextReceiptService.swift',
                                         'Tests/CoreTests/PlayQATextActionReceiptTests.swift', 'Tests/AppUnitTests/PlayQATextReceiptRecoveryTests.swift']]
        with (output / 'swift-syntax.log').open('w') as log:
            result = subprocess.run([args.swiftc, '-frontend', '-parse', *swift], stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0, 'See swift-syntax.log'
        evidence['syntax_parse_exit_code'] = result.returncode
        evidence['patch_applied_in_disposable_copy'] = True
    assert {p: digest(root / p) for p in allowed} == initial
    evidence['checkout_shared_files_unchanged'] = True
    (output / 'integration-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
