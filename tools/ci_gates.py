#!/usr/bin/env python3
"""Bind parallel native CI gates to one checked-out SHA and Apple toolchain.

The UI matrix emits one uniquely named completion output per successful shard.
The aggregate requires all configured outputs as well as every direct job's success;
missing, skipped, cancelled and partially completed work cannot pass.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from test_products import toolchain
import run_static_checks as static_checks

REQUIRED_JOBS = {'static-checks', 'native', 'device-build', 'us-build', 'secrets', 'app-unit-tests', 'ui-tests'}
SHARD_COUNT = 79


def validate_commit(commit):
    if not isinstance(commit, str) or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Exact GITHUB_SHA required')
    return commit


def checked_out_commit(commit):
    validate_commit(commit)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if head != commit:
        raise ValueError('Checked-out git HEAD does not match GITHUB_SHA')
    return head


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))


def fingerprint(commit):
    return encode({'version': 1, 'commit': validate_commit(commit),
                   'head': checked_out_commit(commit), 'toolchain': toolchain()})


def validated_fingerprint(value, commit):
    validate_commit(commit)
    if not isinstance(value, str) or not value:
        raise ValueError('Missing build fingerprint')
    data = json.loads(value)
    if (not isinstance(data, dict) or set(data) != {'version', 'commit', 'head', 'toolchain'}
            or type(data['version']) is not int or data['version'] != 1
            or data['commit'] != commit or data['head'] != commit):
        raise ValueError('Build fingerprint is not bound to this exact SHA')
    identity = data['toolchain']
    if (not isinstance(identity, dict) or set(identity) != {'xcode', 'developer'}
            or not all(isinstance(v, str) and v.strip() for v in identity.values())):
        raise ValueError('Incomplete Apple toolchain fingerprint')
    return encode(data)


def verify_build(expected, commit):
    expected = validated_fingerprint(expected, commit)
    if fingerprint(commit) != expected:
        raise ValueError('Build gate checkout or Apple toolchain differs from test-product builder')
    return expected


def completion_digest(value, commit):
    return hashlib.sha256(validated_fingerprint(value, commit).encode()).hexdigest()


def ui_completion(shard, value, commit):
    if type(shard) is not int or not 0 <= shard < SHARD_COUNT:
        raise ValueError('Unexpected UI shard')
    return f'shard_{shard}', completion_digest(value, commit)


def aggregate(needs, commit, static_receipt, run_id, run_attempt):
    validate_commit(commit)
    if not isinstance(needs, dict) or set(needs) != REQUIRED_JOBS:
        raise ValueError('Missing or unexpected required CI jobs')
    for name, job in needs.items():
        if not isinstance(job, dict) or job.get('result') != 'success':
            raise ValueError(f'Required CI job did not succeed: {name}')
        if not isinstance(job.get('outputs'), dict):
            raise ValueError(f'Missing outputs map for required CI job: {name}')
    static_receipt = static_checks.validated_receipt(static_receipt, commit, run_id, run_attempt)
    for name in ['static-checks', 'native']:
        actual = static_checks.validated_receipt(needs[name]['outputs'].get('static_receipt'), commit, run_id, run_attempt)
        if actual != static_receipt:
            raise ValueError('Required CI job used a different static receipt: ' + name)
    expected = validated_fingerprint(needs['native']['outputs'].get('build_fingerprint'), commit)
    for name in ['device-build', 'us-build', 'app-unit-tests']:
        actual = validated_fingerprint(needs[name]['outputs'].get('build_fingerprint'), commit)
        if actual != expected:
            raise ValueError(f'Required CI job used a different build fingerprint: {name}')
    outputs = needs['ui-tests']['outputs']
    expected_shards = {f'shard_{index}' for index in range(SHARD_COUNT)}
    if set(outputs) != expected_shards:
        raise ValueError('Missing or unexpected UI matrix completion outputs')
    digest = completion_digest(expected, commit)
    if any(value != digest for value in outputs.values()):
        raise ValueError('A UI shard did not complete for this exact build fingerprint')


def write_output(path, key, value):
    if '\n' in value or '\r' in value or not re.fullmatch(r'[a-z_0-9]+', key):
        raise ValueError('Invalid GitHub output')
    with Path(path).open('a') as output:
        output.write(f'{key}={value}\n')


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='action', required=True)
    for name in ['fingerprint', 'verify-build', 'complete-ui']:
        action = sub.add_parser(name)
        action.add_argument('--github-output', required=True)
        if name == 'complete-ui':
            action.add_argument('--shard', type=int, required=True)
    static = sub.add_parser('verify-static')
    static.add_argument('--static-artifact', type=Path, required=True)
    static.add_argument('--github-output', required=True)
    combined = sub.add_parser('aggregate')
    combined.add_argument('--static-artifact', type=Path, required=True)
    args = parser.parse_args()
    commit = os.environ['GITHUB_SHA']
    if args.action == 'aggregate':
        checked_out_commit(commit)
        needs = json.loads(os.environ['NEEDS_JSON'])
        receipt = static_checks.verify_bundle(args.static_artifact, Path(__file__).resolve().parents[1])
        aggregate(needs, commit, receipt, os.environ['GITHUB_RUN_ID'], os.environ['GITHUB_RUN_ATTEMPT'])
        print('All required native gates and', SHARD_COUNT, 'UI shards succeeded for', commit)
    elif args.action == 'verify-static':
        value = static_checks.verify_bundle(args.static_artifact, Path(__file__).resolve().parents[1],
                                            os.environ['EXPECTED_STATIC_RECEIPT'])
        write_output(args.github_output, 'static_receipt', value)
    elif args.action == 'complete-ui':
        # This step uses the default success() condition and runs after results
        # export, so a failed runtime or failed export cannot emit completion.
        value = verify_build(os.environ['EXPECTED_BUILD_FINGERPRINT'], commit)
        key, digest = ui_completion(args.shard, value, commit)
        write_output(args.github_output, key, digest)
    else:
        value = (fingerprint(commit) if args.action == 'fingerprint'
                 else verify_build(os.environ['EXPECTED_BUILD_FINGERPRINT'], commit))
        write_output(args.github_output, 'build_fingerprint', value)


if __name__ == '__main__':
    main()
