#!/usr/bin/env python3
"""One source-pinned, offline, bounded owner screenshot pilot. Not acceptance CI."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import zlib
import time
try:
    from tools import current_native as n
except ModuleNotFoundError:
    import current_native as n

MODE = 'screenshot-pilot'
BRANCH = 'screenshot/codex-ui-20261103'
PUSH_BASE = 'ab2d3905ec0b0fb17b58ba6b53ec433d83164701'
PUSH_MARKER = 'UI-PILOT-ONCE: 20261103-g05-m04-cl02'
MANIFEST_PATH = 'tools/current_ui_pilot_manifest.json'
OWNER_TEST_CLASSES = {
    'G05': {'TeamFlowTests'},
    'M04': {'MerchantRegistrationAvailabilityFlowTests'},
    'CL02': {'ClubOperationsFlowTests', 'ClubProfileScopeFlowTests', 'ClubGovernanceFlowTests'},
}
MAX_METHOD_COUNT = 8
COMMON_SOURCE_BLOBS = {
    'Tests/AppUITests/FailureScreenshot.swift': '3b97ffdc0457cb312814ff2d90388b779881aed6',
    'Questify.xcodeproj/xcshareddata/xcschemes/Questify.xcscheme': 'd3ea23cfd60c38791f30ed9880c55fa032388a2b',
}
MAX_CAPTURE_COUNT = 24


def selection_from_manifest(data):
    n.require(type(data) is dict and set(data) == {'version', 'status', 'base_public_sha', 'owners', 'common_source_blobs'}, 'Unknown capture manifest schema')
    n.require(type(data['version']) is int and data['version'] == 1, 'Unsupported capture manifest version')
    n.require(data['status'] == 'READY', 'Owner capture manifest is pending; do not build or dispatch')
    n.require(re.fullmatch(r'[0-9a-f]{40}', data['base_public_sha'] or '') is not None, 'Missing reviewed public base')
    n.require(data['common_source_blobs'] == COMMON_SOURCE_BLOBS, 'Common fixture helper/scheme requires renewed review')
    owners = data['owners']
    n.require(type(owners) is list and len(owners) == 3 and {row.get('owner') for row in owners if isinstance(row, dict)} == set(OWNER_TEST_CLASSES), 'Expected exactly G05, M04 and CL02')
    selection = {}; sources = dict(COMMON_SOURCE_BLOBS); total = 0
    for row in owners:
        n.require(type(row) is dict and set(row) == {'owner', 'status', 'methods', 'source_blobs', 'capture_patch_sha256'}, 'Unknown owner capture schema')
        owner = row['owner']
        n.require(row['status'] == 'READY', 'Owner capture patch is pending: ' + owner)
        n.require(isinstance(row['capture_patch_sha256'], str) and re.fullmatch(r'[0-9a-f]{64}', row['capture_patch_sha256']), 'Missing exact owner patch hash')
        blobs = row['source_blobs']
        n.require(type(blobs) is dict and 1 <= len(blobs) <= 8, 'Missing exact owner source postimages')
        allowed_tests = {'Tests/AppUITests/' + cls + '.swift' for cls in OWNER_TEST_CLASSES[owner]}
        for name, blob in blobs.items():
            n.require(name in allowed_tests or re.fullmatch(r'App/[A-Za-z0-9_]+\.swift', name), 'Unexpected capture patch source path')
            n.require(name not in sources and isinstance(blob, str) and re.fullmatch(r'[0-9a-f]{40}', blob), 'Missing/duplicate source postimage')
            sources[name] = blob
        methods = row['methods']
        n.require(type(methods) is list and 1 <= len(methods) <= 4, 'Missing bounded owner methods')
        for entry in methods:
            n.require(type(entry) is dict and set(entry) == {'method', 'attachments'}, 'Unknown capture method schema')
            method = entry['method']
            n.require(isinstance(method, str) and n.METHOD.fullmatch(method), 'Malformed capture method')
            target, cls, _ = method.split('/')
            n.require(target == 'QuestifyUITests' and cls in OWNER_TEST_CLASSES[owner] and 'Tests/AppUITests/' + cls + '.swift' in blobs, 'Wrong owner capture method or missing test postimage')
            n.require(method not in selection, 'Duplicate owner method')
            attachments = entry['attachments']
            n.require(type(attachments) is list and 1 <= len(attachments) <= 8, 'Missing bounded owner attachment selection')
            labels = {}
            for item in attachments:
                n.require(type(item) is dict and set(item) == {'name', 'count'}, 'Unknown attachment selection')
                name, count = item['name'], item['count']
                n.require(isinstance(name, str) and 0 < len(name) <= 240 and name.endswith(' – synthetic fixture') and name not in labels, 'Missing/duplicate exact synthetic attachment label')
                n.require(type(count) is int and 1 <= count <= 4, 'Invalid screenshot occurrence count')
                labels[name] = count; total += count
            selection[method] = labels
    n.require(3 <= len(selection) <= MAX_METHOD_COUNT, 'Capture selection exceeds the bounded method count')
    n.require(3 <= total <= MAX_CAPTURE_COUNT, 'Capture selection exceeds the bounded pilot')
    return selection, sources


def load_capture_manifest(root):
    path = root / MANIFEST_PATH
    n.require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 65536, 'Missing/bounded capture manifest')
    data = n.read_json(path)
    selection, sources = selection_from_manifest(data)
    return data, selection, sources, n.digest(path)


IMAGE_LIMIT = 16 * 1024 * 1024
TOTAL_IMAGE_LIMIT = 64 * 1024 * 1024
ARCHIVE_LIMIT = 512 * 1024 * 1024


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_identity(path):
    return {'bytes': path.stat().st_size, 'sha256': n.digest(path)}


def guard_context(expected_sha, env):
    n.require(re.fullmatch(r'[0-9a-f]{40}', expected_sha or '') is not None, 'Exact 40-character pilot SHA required')
    n.require(env.get('GITHUB_REPOSITORY') == 'liboyang42-cpu/chengyin-ios', 'Wrong public repository')
    n.require(env.get('PILOT_REPOSITORY_PRIVATE') == 'false', 'Pilot repository must still be public')
    n.require(env.get('GITHUB_REF') == 'refs/heads/' + BRANCH, 'Wrong pilot branch')
    n.require(env.get('GITHUB_RUN_ATTEMPT') == '1', 'Pilot reruns are forbidden')
    n.require(env.get('GITHUB_SHA') == expected_sha == env.get('GITHUB_WORKFLOW_SHA'), 'Event source and workflow SHA must match')
    n.require(env.get('RUNNER_OS') == 'macOS', 'Native pilot requires macOS')
    event = env.get('GITHUB_EVENT_NAME')
    if event == 'workflow_dispatch':
        n.require(env.get('PILOT_MODE') == MODE, 'Explicit manual pilot mode required')
        return {'event': event, 'expected_sha_origin': 'manual_pilot_sha', 'expected_sha': expected_sha}
    n.require(event == 'push', 'Pilot permits only explicit manual or bounded publication push')
    n.require(env.get('PILOT_PUSH_REF') == 'refs/heads/' + BRANCH, 'Wrong publication event ref')
    n.require(env.get('PILOT_PUSH_CREATED') == 'false' and env.get('PILOT_PUSH_DELETED') == 'false'
              and env.get('PILOT_PUSH_FORCED') == 'false', 'Publication must be a nonforced update, not creation/deletion')
    n.require(env.get('PILOT_PUSH_BEFORE') == PUSH_BASE, 'Publication must advance the exact initial public base once')
    n.require(env.get('PILOT_PUSH_AFTER') == expected_sha == env.get('PILOT_PUSH_HEAD_SHA'), 'Publication after/head SHA differs from workflow checkout')
    n.require(expected_sha != PUSH_BASE, 'No-op publication cannot start a pilot')
    message = env.get('PILOT_PUSH_HEAD_MESSAGE', '')
    n.require(isinstance(message, str) and message == PUSH_MARKER, 'Exact intentional pilot commit marker required')
    return {'event': event, 'expected_sha_origin': 'push_event.after', 'expected_sha': expected_sha,
            'before': PUSH_BASE, 'after': expected_sha, 'head_sha': env['PILOT_PUSH_HEAD_SHA'],
            'created': False, 'deleted': False, 'forced': False, 'intent_marker': PUSH_MARKER}


def source_hashes(root, expected_blobs):
    rows = {}
    for name, permitted in expected_blobs.items():
        path = root / name
        n.require(path.is_file() and not path.is_symlink(), 'Missing/linked reviewed source: ' + name)
        data = path.read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        n.require(blob == permitted, 'Capture source requires renewed review: ' + name)
        rows[name] = {'git_blob': blob, 'bytes': len(data), 'sha256': sha(data)}
    return rows


def test_command(run, simulator, bundle, selection):
    return ['xcodebuild', '-xctestrun', str(run), '-destination', 'platform=iOS Simulator,id=' + simulator,
            '-destination-timeout', '60', '-resultBundlePath', str(bundle), '-parallel-testing-enabled', 'NO',
            '-maximum-concurrent-test-simulator-destinations', '1', '-test-timeouts-enabled', 'YES',
            '-default-test-execution-time-allowance', '180', '-maximum-test-execution-time-allowance', '180',
            *['-only-testing:' + method for method in selection], 'test-without-building']


def canonical_label(name, expected):
    if not isinstance(name, str):
        return None
    for label in expected:
        if name == label or name in [label + ext for ext in ('.png', '.jpg', '.jpeg')]:
            return label
        suffix = r'_(?:0|[1-9][0-9]*)_[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\.(?:png|jpg|jpeg)'
        if re.fullmatch(re.escape(label) + suffix, name):
            return label
    return None


def png_dimensions(data):
    n.require(data.startswith(b'\x89PNG\r\n\x1a\n'), 'Expected an original PNG attachment')
    offset = 8; dimensions = None; ended = False
    while offset < len(data):
        n.require(offset + 12 <= len(data), 'Truncated PNG chunk')
        size = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        end = offset + size + 12
        n.require(end <= len(data), 'Truncated PNG payload')
        payload = data[offset + 8:offset + 8 + size]
        crc = struct.unpack('>I', data[offset + 8 + size:end])[0]
        n.require(zlib.crc32(kind + payload) & 0xffffffff == crc, 'PNG CRC mismatch')
        if offset == 8:
            n.require(kind == b'IHDR' and size == 13, 'Missing PNG header')
            dimensions = struct.unpack('>II', payload[:8])
            n.require(all(0 < v <= 10000 for v in dimensions), 'Unexpected PNG dimensions')
        if kind == b'IEND':
            n.require(size == 0 and end == len(data), 'Invalid PNG end')
            ended = True
        offset = end
    n.require(ended and dimensions is not None, 'Incomplete PNG')
    return list(dimensions)


def collect_attachments(folder, method, output, selection):
    """Keep occurrence identity; equal labels or image bytes must not be deduplicated."""
    n.require(method in selection, 'Foreign pilot method')
    manifest = folder / 'manifest.json'
    n.require(manifest.is_file() and not manifest.is_symlink() and manifest.stat().st_size <= 131072, 'Invalid export manifest')
    groups = n.read_json(manifest)
    n.require(isinstance(groups, list) and len(groups) == 1 and isinstance(groups[0], dict), 'Wrong attachment group count')
    group = groups[0]
    short = method.split('/', 1)[1]
    n.require(group.get('testIdentifier') in (method, short, short + '()'), 'Missing or foreign attachment method')
    if 'testIdentifierURL' in group:
        n.require(group['testIdentifierURL'] == 'test://com.apple.xcode/Questify/' + method, 'Foreign attachment URL')
    attachments = group.get('attachments')
    n.require(isinstance(attachments, list) and len(attachments) <= 256, 'Invalid attachment list')
    counts = Counter(); used_files = set(); rows = []
    for index, attachment in enumerate(attachments):
        n.require(isinstance(attachment, dict), 'Invalid attachment entry')
        name = attachment.get('suggestedHumanReadableName')
        label = canonical_label(name, selection[method])
        if label is None:
            continue  # Failure diagnostics cannot replace the requested success states.
        filename = attachment.get('exportedFileName')
        n.require(isinstance(filename, str) and re.fullmatch(r'[A-Za-z0-9_.-]{1,200}', filename) and filename not in ('.', '..'), 'Unsafe exported image path')
        n.require(filename not in used_files, 'Repeated export file is not two screenshot occurrences')
        used_files.add(filename)
        path = folder / filename
        n.require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= IMAGE_LIMIT, 'Invalid bounded image')
        data = path.read_bytes()
        dimensions = png_dimensions(data)
        counts[label] += 1
        n.require(counts[label] <= selection[method][label], 'Too many matching screenshot occurrences')
        destination = str(list(selection).index(method)) + '-' + str(index) + '-' + sha(data) + '.png'
        n.require(not (output / destination).exists(), 'Refusing to replace an exported image')
        stored = sum(item.stat().st_size for item in output.glob('*.png'))
        n.require(stored + len(data) <= TOTAL_IMAGE_LIMIT, 'Pilot image packet exceeds size limit')
        (output / destination).write_bytes(data)
        rows.append({'method': method, 'attachment': label, 'exported_name': name, 'attachment_index': index,
                     'occurrence': counts[label], 'path': destination, 'bytes': len(data), 'sha256': sha(data),
                     'export_manifest_sha256': n.digest(manifest), 'dimensions': dimensions})
    n.require(dict(counts) == selection[method], 'Missing requested screenshot occurrence')
    return rows


def validate_packet(report, output, selection):
    n.require(report.get('kind') == 'SYNTHETIC_UI_PILOT_NOT_VISUAL_ACCEPTANCE', 'Wrong packet purpose')
    rows = report.get('files', [])
    expected_count = sum(sum(labels.values()) for labels in selection.values())
    n.require(len(rows) == expected_count, 'Pilot requires all manifest-selected screenshot occurrences')
    actual = Counter((row['method'], row['attachment']) for row in rows)
    expected = Counter({(method, label): count for method, labels in selection.items() for label, count in labels.items()})
    n.require(actual == expected, 'Screenshot selection differs')
    n.require(len({r['path'] for r in rows}) == expected_count, 'Screenshot occurrences share an output path')
    total = 0
    for row in rows:
        name = row['path']
        n.require(name == Path(name).name and name not in ('.', '..'), 'Unsafe packet path')
        path = output / name
        n.require(path.is_file() and not path.is_symlink(), 'Missing/linked packet image')
        n.require(file_identity(path) == {'bytes': row['bytes'], 'sha256': row['sha256']}, 'Image changed after export')
        total += row['bytes']
    n.require(total <= TOTAL_IMAGE_LIMIT, 'Pilot image packet exceeds size limit')
    return total


def execute(root, output, expected_sha, start_file):
    trigger = guard_context(expected_sha, os.environ)
    start = float(start_file.read_text())
    n.require(0 < start <= time.monotonic(), 'Invalid job-entry clock')
    # Leave the final two minutes of the 35-minute job for artifact delivery.
    hard_deadline = start + 33 * 60
    execution_deadline = start + 30 * 60
    n.require(not output.exists() and output.parent.resolve() == Path(os.environ['RUNNER_TEMP']).resolve(), 'Fresh runner-temp output required')
    output.mkdir(); evidence = output / 'images'; evidence.mkdir()
    commands = []
    report = {'version': 1, 'kind': 'SYNTHETIC_UI_PILOT_NOT_VISUAL_ACCEPTANCE', 'status': 'INCOMPLETE',
              'scope': MODE, 'expected_sha': expected_sha, 'trigger': trigger, 'expected': {}, 'actual': [], 'files': [], 'commands': commands}
    code = 1
    def save():
        n.write_json(output / 'pilot-manifest.json', report)
        (output / 'pilot-manifest.sha256').write_text(n.digest(output / 'pilot-manifest.json') + '  pilot-manifest.json\n')
    def run(argv, seconds, name, allow_failure=False, extraction=False):
        limit = hard_deadline if extraction else execution_deadline
        remaining = limit - time.monotonic() - 35  # bounded subprocess cleanup
        n.require(remaining > 0, 'Pilot shared deadline exhausted')
        before = time.monotonic()
        rc, raw = n.execute(argv, root, min(seconds, remaining), capture='stdout')
        path = output / (name + '.stdout'); path.write_bytes(raw)
        commands.append({'argv': [str(x) for x in argv], 'returncode': rc, 'seconds': time.monotonic() - before,
                         'log': path.name, 'sha256': sha(raw)})
        save()
        n.require(allow_failure or rc == 0, 'Command failed: ' + name)
        return raw, rc
    def standard_run(argv, seconds, name):
        return run(argv, seconds, name)[0]
    bundle = output / 'pilot.xcresult'
    try:
        manifest, selection, expected_blobs, manifest_hash = load_capture_manifest(root)
        report['capture_manifest'] = manifest
        report['capture_manifest_sha256'] = manifest_hash
        report['expected'] = selection
        report['identity'] = n.control.source_identity(root)
        report['workflow'] = {'sha': os.environ['GITHUB_WORKFLOW_SHA'], 'ref': os.environ.get('GITHUB_WORKFLOW_REF'),
                              'job_key': os.environ.get('GITHUB_JOB'),
                              'run_url': 'https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/' + os.environ['GITHUB_RUN_ID']}
        report['source_files'] = source_hashes(root, expected_blobs)
        report['selection_sha256'] = sha(n.encode(selection).encode())
        report['toolchain'] = n.toolchain(standard_run)
        sim = n.choose_simulator(json.loads(standard_run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 60, 'devices')))
        runtimes = json.loads(standard_run(['xcrun', 'simctl', 'list', 'runtimes', '--json'], 60, 'runtimes'))
        matches = [r for r in runtimes.get('runtimes', []) if r.get('identifier') == sim['runtime'] and r.get('isAvailable') is True]
        n.require(len(matches) == 1, 'Selected simulator runtime unavailable')
        report.update(simulator=sim, runtime=matches[0]); save()
        derived = output.parent / 'pilot-derived-data'
        n.require(not derived.exists(), 'Preexisting pilot build products forbidden')
        standard_run(['xcodebuild', '-project', 'Questify.xcodeproj', '-scheme', 'Questify', '-configuration', 'Debug',
                      '-sdk', 'iphonesimulator', '-destination', 'platform=iOS Simulator,id=' + sim['udid'],
                      '-destination-timeout', '60', '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO',
                      'ONLY_ACTIVE_ARCH=YES', 'build-for-testing'], 1200, 'build')
        products = derived / 'Build/Products'
        xctestrun = n.normalized_ui_products(products)
        report['xctestrun'] = dict(path=str(xctestrun.relative_to(derived)), **file_identity(xctestrun))
        standard_run(['xcrun', 'simctl', 'bootstatus', sim['udid'], '-b'], 180, 'boot')
        _, test_code = run(test_command(xctestrun, sim['udid'], bundle, selection), 540, 'test', allow_failure=True)
        docs = {}
        for kind in ('summary', 'tests'):
            raw, _ = run(['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--path', str(bundle), '--compact'],
                         30, kind, extraction=True)
            docs[kind] = json.loads(raw)
        report['actual'] = n.parse_xcresult(docs['tests'], 'QuestifyUITests'); save()
        try:
            n.validate_outcomes(report['actual'], list(selection), test_code)
            n.split404_validate_device_results(docs['summary'], docs['tests'], len(selection), sim, matches[0])
        except ValueError as error:
            report['test_error'] = str(error)
        passed = {row['method'] for row in report['actual'] if row['status'] == 'Passed'}
        for index, method in enumerate(selection):
            if method not in passed:
                continue
            folder = output / ('export-' + str(index))
            run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(folder),
                 '--test-id', method.split('/', 1)[1] + '()'], 30, 'export-' + str(index), extraction=True)
            report['files'].extend(collect_attachments(folder, method, evidence, selection)); save()
        n.require('test_error' not in report, report.get('test_error', 'Invalid selected test result'))
        report['image_bytes'] = validate_packet(report, evidence, selection)
        n.require(n.control.source_identity(root) == report['identity'], 'Source changed during pilot')
        n.require(source_hashes(root, expected_blobs) == report['source_files'], 'Capture source changed during pilot')
        n.require(n.digest(root / MANIFEST_PATH) == manifest_hash, 'Capture manifest changed during pilot')
        report['status'] = 'PASS'; code = 0
    except Exception as error:
        report['status'] = 'FAIL'
        report['error'] = str(error)
    finally:
        if bundle.is_dir() and not bundle.is_symlink():
            try:
                archive = output / 'pilot.xcresult.tar.gz'
                run(['tar', '-czf', str(archive), '-C', str(output), 'pilot.xcresult'], 60, 'archive', extraction=True)
                n.require(0 < archive.stat().st_size <= ARCHIVE_LIMIT, 'xcresult archive exceeds bounded upload size')
                report['xcresult_archive'] = dict(path=archive.name, **file_identity(archive))
            except Exception as error:
                report['archive_error'] = str(error)
                report['status'] = 'FAIL'; code = 1
                archive = output / 'pilot.xcresult.tar.gz'
                if archive.is_file(): archive.unlink()
        else:
            report['xcresult_archive'] = None
        save()
    return code


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-sha', required=True)
    parser.add_argument('--start-file', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    raise SystemExit(execute(n.control.ROOT, args.output, args.expected_sha, args.start_file))


if __name__ == '__main__':
    main()
