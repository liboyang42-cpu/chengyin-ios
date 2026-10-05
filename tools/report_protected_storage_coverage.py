#!/usr/bin/env python3
"""Report protected-storage coverage boundaries, never promote compilation to execution."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def report(compile_outcome, commit):
    inventory = json.loads((ROOT / 'tools/protected_storage_device_inventory.json').read_text())
    return {
        'version': 1,
        'commit': commit,
        'device_compile': {'success': 'COMPILED_UNSIGNED_NOT_EXECUTED',
                           'failure': 'COMPILE_FAILED', 'cancelled': 'COMPILE_CANCELLED',
                           'skipped': 'COMPILE_NOT_RUN'}[compile_outcome],
        'device_execution': 'NOT_RUN_DEVICE_REQUIRED',
        'device_lock_enforcement': 'NOT_RUN_DEVICE_REQUIRED',
        'tests': [{'test': f"QuestifyAppUnitTests/{item['class']}/{item['method']}",
                   'status': 'NOT_RUN_DEVICE_REQUIRED'} for item in inventory['tests']],
        'limits': 'Simulator Keychain and non-Class-A rejection are separate checks. '
                  'Neither those checks nor unsigned device compilation proves Class A success or device lock enforcement.'
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compile-outcome', required=True, choices=['success', 'failure', 'cancelled', 'skipped'])
    parser.add_argument('--commit', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--summary', type=Path, required=True)
    args = parser.parse_args()
    result = report(args.compile_outcome, args.commit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    lines = ['## Protected-storage acceptance boundary', '',
             f"Unsigned device test compilation: {result['device_compile']}", '',
             'Physical-device execution: NOT_RUN_DEVICE_REQUIRED',
             'Physical-device lock enforcement: NOT_RUN_DEVICE_REQUIRED', '']
    lines += [f"- {item['test']}: {item['status']}" for item in result['tests']]
    lines += ['', result['limits'], '']
    with args.summary.open('a') as stream:
        stream.write('\n'.join(lines))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
