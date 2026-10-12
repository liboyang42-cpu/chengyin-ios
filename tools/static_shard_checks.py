"""Class-preserving partitions for the complete native static prerequisite.

A plan is an inventory, never a passing receipt. Every assigned method must have
an original validate_report outcome before the existing full-suite receipt can
be produced. No test, skip, or timeout policy is changed here.
"""
from collections import Counter
from copy import deepcopy
import hashlib
import json
import math

VERSION = 1
SHARDS = 12
SUITE_NAMES = ('tools', 'contracts')
OUTCOMES = ('successes', 'failures', 'errors', 'expected_failures', 'unexpected_successes')


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def sha(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def checked_ids(values):
    if not isinstance(values, list) or not values or any(not isinstance(v, str) or len(v.split('.')) < 3 for v in values):
        raise ValueError('Missing or malformed full test inventory')
    if len(set(values)) != len(values):
        raise ValueError('Duplicate test inventory')
    return values


def assignment(ids, count=SHARDS):
    if type(count) is not int or not 1 <= count <= 32:
        raise ValueError('Invalid static shard count')
    checked_ids(ids)
    classes = {}
    for identifier in ids:
        classes.setdefault(identifier.rsplit('.', 1)[0], []).append(identifier)
    # Keep class fixtures and approved class skips intact. Stable round-robin
    # distributes the expensive historical classes instead of placing an
    # alphabetical range of them in one worker.
    output = [[] for _ in range(count)]
    for offset, name in enumerate(sorted(classes)):
        output[offset % count].extend(classes[name])
    return output


def make_plan(identity, discoveries, count=SHARDS):
    if set(discoveries) != set(SUITE_NAMES):
        raise ValueError('Both full discoveries are required')
    suites = {}
    for name in SUITE_NAMES:
        ids = checked_ids(discoveries[name])
        suites[name] = {'discovered_ids': list(ids), 'assignments': assignment(ids, count)}
    return {'version': VERSION, 'identity': deepcopy(identity), 'count': count, 'suites': suites}


def validate_plan(plan, identity, discoveries=None):
    if not isinstance(plan, dict) or set(plan) != {'version', 'identity', 'count', 'suites'} or type(plan['version']) is not int or plan['version'] != VERSION:
        raise ValueError('Invalid static plan schema')
    if plan['identity'] != identity or not isinstance(plan['suites'], dict) or set(plan['suites']) != set(SUITE_NAMES):
        raise ValueError('Static plan belongs to another source/run/attempt')
    for name in SUITE_NAMES:
        row = plan['suites'][name]
        if not isinstance(row, dict) or set(row) != {'discovered_ids', 'assignments'}:
            raise ValueError('Invalid static plan suite')
        ids = checked_ids(row['discovered_ids'])
        if row['assignments'] != assignment(ids, plan['count']):
            raise ValueError('Static assignment altered, omitted or duplicated')
        if discoveries is not None and ids != discoveries[name]:
            raise ValueError('Plan differs from fresh complete discovery')
    return plan


def validate_shard(plan, shard, identity, validate_report, root):
    validate_plan(plan, identity)
    if not isinstance(shard, dict) or set(shard) != {'version', 'identity', 'plan_sha256', 'index', 'reports', 'log_sha256'} or type(shard['version']) is not int or shard['version'] != VERSION:
        raise ValueError('Invalid static shard schema')
    index = shard['index']
    if type(index) is not int or not 0 <= index < plan['count'] or shard['identity'] != identity or shard['plan_sha256'] != sha(plan):
        raise ValueError('Static shard identity or plan mismatch')
    if not isinstance(shard['reports'], dict) or set(shard['reports']) != set(SUITE_NAMES) or not isinstance(shard['log_sha256'], dict) or set(shard['log_sha256']) != set(SUITE_NAMES):
        raise ValueError('Static shard must account for both suite assignments')
    for name in SUITE_NAMES:
        ids = plan['suites'][name]['assignments'][index]
        report = shard['reports'][name]
        digest = shard['log_sha256'][name]
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
            raise ValueError('Missing exact shard log digest')
        if not ids:
            if report is not None:
                raise ValueError('Empty assignment fabricated a report')
            continue
        if not isinstance(report, dict) or report.get('discovered_ids') != ids:
            raise ValueError('Shard ran a different, missing or duplicate method set')
        validate_report(report, name, root)
    return shard


def aggregate_suite(plan, shards, name, identity, validate_report, root, process_id):
    validate_plan(plan, identity)
    if name not in SUITE_NAMES or type(process_id) is not int or process_id <= 0:
        raise ValueError('Invalid aggregate process')
    if len(shards) != plan['count']:
        raise ValueError('Missing complete static shards')
    indexed = {}
    for shard in shards:
        validate_shard(plan, shard, identity, validate_report, root)
        if shard['index'] in indexed:
            raise ValueError('Duplicate static shard')
        indexed[shard['index']] = shard
    if set(indexed) != set(range(plan['count'])):
        raise ValueError('Incomplete static shard inventory')
    reports = [indexed[i]['reports'][name] for i in range(plan['count']) if indexed[i]['reports'][name] is not None]
    if not reports:
        raise ValueError('Empty static suite')
    report = deepcopy(reports[0])
    report['discovered_ids'] = list(plan['suites'][name]['discovered_ids'])
    report['executed_ids'] = [i for r in reports for i in r['executed_ids']]
    for key in OUTCOMES:
        report[key] = [i for r in reports for i in r[key]]
    report['skipped'] = [i for r in reports for i in r['skipped']]
    report['discovery_errors'] = [i for r in reports for i in r['discovery_errors']]
    report['tests_run'] = sum(r['tests_run'] for r in reports)
    report['duration_seconds'] = sum(r['duration_seconds'] for r in reports)
    report['process_id'] = process_id  # This real, independent suite aggregation process.
    report['discovered_count'] = len(report['discovered_ids'])
    report['executed_count'] = len(report['executed_ids'])
    report['skip_count'] = len(report['skipped'])
    report['outcome_counts'] = {key: len(report[key]) for key in OUTCOMES}
    if Counter(i for r in reports for i in r['discovered_ids']) != Counter(report['discovered_ids']):
        raise ValueError('Full suite coverage does not match plan exactly once')
    validate_report(report, name, root)
    return report


def main():
    import argparse
    import os
    from pathlib import Path
    import subprocess
    import sys
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root))
    from tools import run_static_checks as base
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'shard', 'merge', '_merge-suite'])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--plan', type=Path)
    parser.add_argument('--input', type=Path)
    parser.add_argument('--index', type=int)
    parser.add_argument('--suite', choices=SUITE_NAMES)
    parser.add_argument('--github-output', type=Path)
    args = parser.parse_args()
    if sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE'):
        raise ValueError('Optimized Python is forbidden')
    base.check_configured_sources()
    output = base.checked_output(args.output, root)
    identity = base.source_identity(root)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')

    def boundary():
        if base.source_identity(root) != identity:
            raise ValueError('Static source identity changed')

    def discoveries(directory):
        # Keep the original independent interpreters, but avoid adding their
        # import/admission durations together within the unchanged plan budget.
        from concurrent.futures import ThreadPoolExecutor
        def discover_one(name):
            boundary()
            target = directory / (name + '-discovery.json')
            subprocess.run([sys.executable, '-B', str(root / 'tools/run_static_checks.py'), '_discover',
                            '--suite', name, '--report', str(target)], cwd=root, env=env, check=True)
            boundary()
            return checked_ids(base.read_json(target))
        with ThreadPoolExecutor(max_workers=len(SUITE_NAMES)) as pool:
            pending = {name: pool.submit(discover_one, name) for name in SUITE_NAMES}
            return {name: future.result() for name, future in pending.items()}

    def load_plan():
        if args.plan is None:
            raise ValueError('Missing full static plan')
        return validate_plan(base.read_json(base.checked_output(args.plan, root)), identity)

    def load_shards(plan):
        if args.input is None:
            raise ValueError('Missing static shard directory')
        directory = base.checked_output(args.input, root)
        expected = {'shard-' + str(i) for i in range(plan['count'])}
        if not directory.is_dir() or {x.name for x in directory.iterdir()} != expected:
            raise ValueError('Missing or extra static shard artifacts')
        shards, logs = [], {name: [] for name in SUITE_NAMES}
        for index in range(plan['count']):
            folder = directory / ('shard-' + str(index))
            if folder.is_symlink():
                raise ValueError('Symlink shard directory')
            shard = base.read_json(folder / 'shard.json')
            if shard.get('index') != index:
                raise ValueError('Shard directory/index mismatch')
            validate_shard(plan, shard, identity, base.validate_report, root)
            shards.append(shard)
            for name in SUITE_NAMES:
                path = folder / (name + '.log')
                if path.is_symlink() or not path.is_file():
                    raise ValueError('Missing regular shard log')
                raw = path.read_bytes()
                if base.digest(raw) != shard['log_sha256'][name]:
                    raise ValueError('Static shard log bytes changed')
                if shard['reports'][name] is not None:
                    base.validate_log_identity_report(raw, shard['reports'][name], root)
                logs[name].append(b'\nSHARD ENVELOPE ' + encoded(shard) + b'\n' + raw)
        return shards, logs

    if args.action == 'plan':
        output.mkdir(parents=True, exist_ok=False)
        plan = make_plan(identity, discoveries(output))
        boundary()
        base.atomic_json(output / 'plan.json', plan)
    elif args.action == 'shard':
        plan = load_plan()
        if type(args.index) is not int or not 0 <= args.index < plan['count']:
            raise ValueError('Invalid shard index')
        output.mkdir(parents=True, exist_ok=False)
        reports, log_hashes = {}, {}
        for name in SUITE_NAMES:
            boundary()
            assigned = plan['suites'][name]['assignments'][args.index]
            log = output / (name + '.log')
            if assigned:
                ids = output / (name + '-assigned.json')
                base.atomic_json(ids, assigned)
                report_path = output / (name + '.json')
                command = [sys.executable, '-B', '-u', str(root / 'tools/run_static_checks.py'), '_suite',
                           '--suite', name, '--report', str(report_path), '--test-ids', str(ids)]
                result = base.run_logged_process(command, root, env, log)
                boundary()
                if result.returncode:
                    raise ValueError('Assigned static suite did not succeed')
                report = base.read_json(report_path)
                if report['discovered_ids'] != assigned:
                    raise ValueError('Loaded methods differ from assignment')
                base.validate_report(report, name, root)
                base.validate_log_identity_report(log.read_bytes(), report, root)
                reports[name] = report
            else:
                log.write_text('No methods assigned in this suite. Full coverage required at aggregate.\n')
                reports[name] = None
            log_hashes[name] = base.digest(log.read_bytes())
        boundary()
        shard = {'version': VERSION, 'identity': identity, 'plan_sha256': sha(plan),
                 'index': args.index, 'reports': reports, 'log_sha256': log_hashes}
        validate_shard(plan, shard, identity, base.validate_report, root)
        base.atomic_json(output / 'shard.json', shard)
    elif args.action == '_merge-suite':
        plan = load_plan()
        shards, logs = load_shards(plan)
        report = aggregate_suite(plan, shards, args.suite, identity, base.validate_report, root, os.getpid())
        output.mkdir(parents=True, exist_ok=True)
        base.atomic_json(output / (args.suite + '.json'), report)
        (output / (args.suite + '.log')).write_bytes(b''.join(logs[args.suite]))
        boundary()
    else:
        plan = load_plan()
        output.mkdir(parents=True, exist_ok=False)
        validate_plan(plan, identity, discoveries(output))
        load_shards(plan)
        completed = {}
        for name in SUITE_NAMES:
            boundary()
            subprocess.run([sys.executable, '-B', str(Path(__file__).resolve()), '_merge-suite', '--suite', name,
                            '--output', str(output), '--plan', str(args.plan), '--input', str(args.input)],
                           cwd=root, env=env, check=True)
            boundary()
            completed[name] = {'report_sha256': base.digest((output / (name + '.json')).read_bytes()),
                               'log_sha256': base.digest((output / (name + '.log')).read_bytes())}
        base.atomic_json(output / 'manifest.json', {'version': 1, 'identity': identity, 'suites': completed})
        value = base.verify_bundle(output, root)
        if args.github_output is None:
            raise ValueError('Missing aggregate output destination')
        base.write_output(args.github_output, value)


if __name__ == '__main__':
    main()
