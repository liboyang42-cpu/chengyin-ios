#!/usr/bin/env python3
"""Run every discovered XCTestCase exactly once across deterministic class-level shards."""
import argparse
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]

def discover(directory):
    weights = {}
    for path in sorted(pathlib.Path(directory).glob('*.swift')):
        source = path.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        if not methods:
            continue
        cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
        if len(cases) != 1:
            raise ValueError(f'{path.name}: keep one XCTestCase per test file; refusing incomplete inventory')
        name = cases[0]
        if name in weights or len(methods) != len(set(methods)):
            raise ValueError(f'{path.name}: duplicate class or test method')
        weights[name] = len(methods)
    if not weights:
        raise ValueError('No UI tests discovered')
    return weights

def partition(weights, count):
    if count < 1 or count > len(weights):
        raise ValueError('Shard count must be between one and the number of test classes')
    groups = [[] for _ in range(count)]
    totals = [0] * count
    for name, weight in sorted(weights.items(), key=lambda item: (-item[1], item[0])):
        target = min(range(count), key=lambda index: (totals[index], index))
        groups[target].append(name)
        totals[target] += weight
    flat = [name for group in groups for name in group]
    assert len(flat) == len(set(flat)) and set(flat) == set(weights)
    return groups

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--shard', type=int, required=True)
    parser.add_argument('--count', type=int, default=2)
    parser.add_argument('--simulator')
    parser.add_argument('--derived-data')
    parser.add_argument('--result-bundle')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    weights = discover(ROOT / 'Tests/AppUITests')
    groups = partition(weights, args.count)
    if not 0 <= args.shard < args.count:
        parser.error('shard index out of range')
    selected = groups[args.shard]
    print(f'Inventory: {sum(weights.values())} tests in {len(weights)} classes; shard {args.shard}: '
          f'{sum(weights[name] for name in selected)} tests in {selected}', flush=True)
    if args.dry_run:
        return 0
    if not all([args.simulator, args.derived_data, args.result_bundle]):
        parser.error('simulator, derived-data and result-bundle are required')
    command = ['xcodebuild', '-project', 'Questify.xcodeproj', '-scheme', 'Questify',
               '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={args.simulator}',
               '-derivedDataPath', args.derived_data, '-resultBundlePath', args.result_bundle,
               '-parallel-testing-enabled', 'NO']
    command += [f'-only-testing:QuestifyUITests/{name}' for name in selected]
    command += ['CODE_SIGNING_ALLOWED=NO', 'test']
    return subprocess.run(command, cwd=ROOT, check=False).returncode

if __name__ == '__main__':
    raise SystemExit(main())
