#!/usr/bin/env python3
"""Run every discovered XCTestCase exactly once across deterministic class-level shards."""
import argparse
import pathlib
import re
import subprocess
import os
import signal
import json
import math
try:
    from ui_failure_evidence import EvidenceStream
except ModuleNotFoundError:
    from tools.ui_failure_evidence import EvidenceStream

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_SHARD_COUNT = 65

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

def measured_weights(directory, profile):
    """Observed/declared estimated costs affect grouping only; source defines every case."""
    counts = discover(directory)
    data = json.loads(pathlib.Path(profile).read_text())
    if data.get('version') != 1 or not isinstance(data.get('method_seconds'), dict):
        raise ValueError('Invalid UI duration profile')
    default = data.get('unobserved_method_seconds')
    timings = data['method_seconds']
    estimates = data.get('estimated_method_seconds', {})
    if not isinstance(estimates, dict):
        raise ValueError('Invalid estimated UI duration profile')
    def valid(value):
        return type(value) in (int, float) and math.isfinite(value) and 0 < value <= 900
    if not valid(default) or any(not re.fullmatch(r'[A-Za-z_]\w*\.test\w+', name) or not valid(seconds)
                                 for name, seconds in list(timings.items()) + list(estimates.items())):
        raise ValueError('Invalid UI duration or method identity')
    result = {}
    for path in sorted(pathlib.Path(directory).glob('*.swift')):
        source = path.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        if not methods:
            continue
        name = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)[0]
        result[name] = sum(timings.get(name + '.' + method, estimates.get(name + '.' + method, default)) for method in methods)
    assert set(result) == set(counts)
    return result


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
    parser.add_argument('--count', type=int, default=DEFAULT_SHARD_COUNT)
    parser.add_argument('--simulator')
    parser.add_argument('--derived-data')
    parser.add_argument('--result-bundle')
    parser.add_argument('--xctestrun')
    parser.add_argument('--deadline-seconds', type=int)
    parser.add_argument('--evidence-directory', type=pathlib.Path)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--duration-profile', type=pathlib.Path, default=ROOT/'tools/ui_duration_weights.json')
    args = parser.parse_args()
    weights = discover(ROOT / 'Tests/AppUITests')
    costs = measured_weights(ROOT / 'Tests/AppUITests', args.duration_profile)
    groups = partition(costs, args.count)
    if not 0 <= args.shard < args.count:
        parser.error('shard index out of range')
    selected = groups[args.shard]
    print(f'Inventory: {sum(weights.values())} tests in {len(weights)} classes; shard {args.shard}: '
          f'{sum(weights[name] for name in selected)} tests, estimated {sum(costs[name] for name in selected):.1f}s in {selected}', flush=True)
    if args.dry_run:
        return 0
    if not all([args.simulator, args.result_bundle]) or not (args.xctestrun or args.derived_data):
        parser.error('simulator, result-bundle and xctestrun or derived-data are required')
    if args.deadline_seconds is not None and args.deadline_seconds < 1:
        parser.error('deadline-seconds must be positive')
    if args.xctestrun:
        if not pathlib.Path(args.xctestrun).is_file():
            parser.error('Verified xctestrun is missing; refusing an implicit rebuild')
        command = ['xcodebuild', '-xctestrun', args.xctestrun]
        action = 'test-without-building'
    else:
        command = ['xcodebuild', '-project', 'Questify.xcodeproj', '-scheme', 'Questify',
                   '-configuration', 'Debug', '-derivedDataPath', args.derived_data]
        action = 'test'
    command += ['-destination', f'platform=iOS Simulator,id={args.simulator}',
               '-resultBundlePath', args.result_bundle,
               '-parallel-testing-enabled', 'NO']
    command += [f'-only-testing:QuestifyUITests/{name}' for name in selected]
    command += ['CODE_SIGNING_ALLOWED=NO', action]
    try:
        evidence = EvidenceStream(args.evidence_directory) if args.evidence_directory else None
    except (OSError, ValueError):
        print('UI evidence directory unavailable; continuing authoritative test execution', flush=True)
        evidence = None
    process = subprocess.Popen(command, cwd=ROOT, start_new_session=True,
                               **({'stdout': subprocess.PIPE, 'stderr': subprocess.STDOUT} if evidence else {}))
    if evidence:
        evidence.start(process.stdout)
    try:
        code = process.wait(timeout=args.deadline_seconds)
        if evidence:
            evidence.finish(code)
        return code
    except subprocess.TimeoutExpired:
        # Give xcodebuild time to finalize partial results before the job limit.
        # A partial run always fails, even if its graceful interrupt returns zero.
        print('UI shard deadline reached: incomplete, never passed; requesting result finalization', flush=True)
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        if evidence:
            evidence.finish(124)
        return 124

if __name__ == '__main__':
    raise SystemExit(main())
