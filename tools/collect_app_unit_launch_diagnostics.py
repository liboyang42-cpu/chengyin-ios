#!/usr/bin/env python3
"""Read-only bounded launch evidence; never emit raw logs, paths or environments.

This does not repair or classify a launch failure as a pass. Original XCTest
status and full xcresult retention remain independent and unchanged.
"""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import time

MAX_CAPTURE = 1_048_576
MAX_REPORT = 65_536
MAX_RECORDS = 80
PREDICATE = 'eventMessage CONTAINS[c] "Questify" OR eventMessage CONTAINS[c] "invalid.example.questify.ios"'
CATEGORIES = {
    'launch_constraint': 'launch constraint', 'constraint_violation': 'constraint violation',
    'code_signature': 'code signature', 'signature_invalid': 'signature invalid',
    'library_validation': 'library validation', 'missing_image': 'image not found',
    'unsuitable_image': 'no suitable image', 'invalid_library': 'not valid for use in process',
    'permission_denied': 'not permitted', 'request_denied': 'requestdenied',
    'spawn_failed': 'launchd job spawn failed', 'migration_failed': 'data migration failed',
    'missing_entitlement': 'errsecmissingentitlement', 'debug_entitlement': 'get-task-allow',
    'codesigning_termination': 'os_reason_codesigning', 'codesigning_killed': 'cs_killed',
    'amfi': 'amfi', 'dyld': 'dyld', 'launch_failed': 'launch failed',
}
DOMAINS = ('FBSOpenApplicationServiceErrorDomain', 'RBSRequestErrorDomain',
           'NSPOSIXErrorDomain', 'FBProcessExit', 'NSCocoaErrorDomain', 'OSLaunchdErrorDomain')
COUNTS = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'expectedFailures', 'testFailuresCount')


def capture(command, timeout=30, limit=MAX_CAPTURE):
    """Bound both pipe streams while running only our diagnostic subprocess."""
    buffers = {'stdout': bytearray(), 'stderr': bytearray()}
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    except OSError:
        return {'state': 'unavailable'}, b''
    state = 'complete'
    deadline = time.monotonic() + timeout
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
        selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
        while selector.get_map():
            if time.monotonic() >= deadline:
                state = 'timeout'; break
            for key, _ in selector.select(min(0.1, max(0, deadline - time.monotonic()))):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj); continue
                remaining = limit - sum(len(b) for b in buffers.values())
                buffers[key.data].extend(chunk[:remaining])
                if len(chunk) > remaining:
                    state = 'output_limit'; break
            if state != 'complete': break
    if state != 'complete':
        try: os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
    try: code = process.wait(timeout=max(0.1, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        try: os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        code = process.wait(); state = 'timeout'
    process.stdout.close(); process.stderr.close()
    metadata = {'state': state, 'exit_code': code,
                'stdout_bytes': len(buffers['stdout']), 'stderr_bytes': len(buffers['stderr'])}
    # Never return stderr contents. Incomplete/failed output is not parseable evidence.
    return metadata, bytes(buffers['stdout']) if state == 'complete' and code == 0 else b''


def facts(text):
    lower = text.lower()
    result = {'categories': sorted(key for key, value in CATEGORIES.items() if value in lower),
              'domains': sorted(domain for domain in DOMAINS if domain in text)}
    result['codes'] = sorted({int(x) for x in re.findall(r'\b(?:code|errno)\s*[=: ]\s*(-?\d{1,7})\b', text, re.I)})[:20]
    # Fixed AMFI constraint slot labels with numeric values only; no raw error text.
    result['constraint_slots'] = sorted(set(re.findall(r'\b[cpme]\[\d{1,4}\]', text)))[:16]
    return result


def strings(value):
    if isinstance(value, str): yield value
    elif isinstance(value, list):
        for child in value: yield from strings(child)
    elif isinstance(value, dict):
        for child in value.values(): yield from strings(child)


def summarize(data, logs=False):
    try: value = json.loads(data)
    except (ValueError, UnicodeError): return {'format': 'unavailable_or_non_json'}
    result = {'format': 'json'}
    if not logs:
        if isinstance(value, dict):
            result['counts'] = {key: value[key] for key in COUNTS if type(value.get(key)) is int and 0 <= value[key] <= 1_000_000}
        result['facts'] = facts('\n'.join(strings(value)))
        return result
    if not isinstance(value, list): return {'format': 'unexpected_json_shape'}
    records = []
    for item in value:
        if not isinstance(item, dict) or not isinstance(item.get('eventMessage'), str): continue
        message = item['eventMessage']
        # Recheck the OS predicate defensively; only the synthetic test app is relevant.
        if 'questify' not in message.lower() and 'invalid.example.questify.ios' not in message.lower(): continue
        record = facts(message)
        if not any(record.values()): continue
        timestamp = item.get('timestamp')
        if isinstance(timestamp, str) and re.fullmatch(r'\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:?\d\d)?', timestamp):
            record['timestamp'] = timestamp
        records.append(record)
    result.update(records=records[-MAX_RECORDS:], record_limit=MAX_RECORDS,
                  matched_records=len(records), source_records=len(value))
    return result


def collect(temporary, simulator, run=capture):
    report = {'version': 1, 'diagnostic_only': True, 'root_cause_established': False,
              'limits': {'capture_bytes_per_command': MAX_CAPTURE, 'records_per_log': MAX_RECORDS, 'command_timeout_seconds': 30}}
    boot = temporary / 'questify-app-unit-boot.log'
    if boot.is_file() and not boot.is_symlink():
        with boot.open('rb') as source: data = source.read(MAX_CAPTURE + 1)
        report['boot'] = {'state': 'complete' if len(data) <= MAX_CAPTURE else 'output_limit',
                          'facts': facts(data[:MAX_CAPTURE].decode('utf-8', errors='replace'))}
    else: report['boot'] = {'state': 'missing'}
    bundle = temporary / 'questify-app-unit-results.xcresult'
    if bundle.is_dir() and not bundle.is_symlink():
        meta, data = run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle), '--compact'])
        report['xcresult_summary'] = {**meta, **summarize(data)}
    else: report['xcresult_summary'] = {'state': 'missing'}
    log_args = ['log', 'show', '--last', '15m', '--style', 'json', '--info', '--debug', '--predicate', PREDICATE]
    meta, data = run(['/usr/bin/' + log_args[0], *log_args[1:]])
    report['host_launch_log'] = {**meta, **summarize(data, logs=True)}
    if re.fullmatch(r'[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}', simulator):
        meta, data = run(['xcrun', 'simctl', 'spawn', simulator, *log_args])
        report['simulator_launch_log'] = {**meta, **summarize(data, logs=True)}
    else: report['simulator_launch_log'] = {'state': 'missing_or_invalid_simulator_id'}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner-temp', required=True)
    parser.add_argument('--simulator', default='')
    args = parser.parse_args()
    temporary = Path(args.runner_temp).resolve(strict=True)
    report = collect(temporary, args.simulator)
    commit = os.environ.get('GITHUB_SHA', '')
    report['commit'] = commit if re.fullmatch(r'[a-f0-9]{40}', commit) else 'unknown'
    data = (json.dumps(report, sort_keys=True, indent=2) + '\n').encode()
    if len(data) > MAX_REPORT:
        data = b'{"diagnostic_only":true,"state":"report_limit","root_cause_established":false}\n'
    output = temporary / 'questify-app-unit-launch-diagnostics.json'
    # Never follow a preexisting path on the ephemeral runner.
    with output.open('xb') as destination: destination.write(data)
    print('Saved bounded AppUnit launch diagnostics; no raw logs or root-cause claim')


if __name__ == '__main__': main()
