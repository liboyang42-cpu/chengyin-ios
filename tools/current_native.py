#!/usr/bin/env python3
"""Direct current native execution; exact existing parsers, no history imports."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET
try:
    from tools import current_ci as control
except ModuleNotFoundError:
    import current_ci as control

METHOD = re.compile(r'(QuestifyCoreTests|QuestifyAppUnitTests|QuestifyUITests)/([A-Za-z][A-Za-z0-9_]*)/(test[A-Za-z0-9_]+)')


LIMIT = 10 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True)


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(encode(value) + '\n')
    temporary.replace(path)


def execute(command, cwd, timeout, capture=False, env=None):
    """Every process tree gets bounded interrupt/terminate/kill cleanup."""
    require(timeout > 0, 'Diagnostic deadline exhausted')
    process = subprocess.Popen([str(x) for x in command], cwd=cwd, start_new_session=True,
                               stdout=subprocess.PIPE if capture else None,
                               stderr=subprocess.PIPE if capture is True else None, env=env)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        for sig, grace in [(signal.SIGINT, 20), (signal.SIGTERM, 10), (signal.SIGKILL, 5)]:
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = process.communicate(timeout=grace)
                break
            except subprocess.TimeoutExpired:
                continue
        else:
            raise RuntimeError('Process tree did not exit within bounded cleanup')
    stdout, stderr = stdout or b'', stderr or b''
    require(len(stdout) <= LIMIT and len(stderr) <= LIMIT, 'Oversized captured command output')
    return (124 if timed_out else process.returncode), stdout


def choose_simulator(data):
    require(isinstance(data, dict) and isinstance(data.get('devices'), dict), 'Invalid simulator inventory')
    choices = []
    for runtime, devices in data['devices'].items():
        if not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
            continue
        for device in devices:
            if device.get('isAvailable') is True and device.get('name', '').startswith('iPhone'):
                require(re.fullmatch('[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', device.get('udid', '')) is not None, 'Invalid simulator UUID')
                choices.append({'runtime': runtime, 'name': device['name'], 'udid': device['udid']})
    require(bool(choices), 'No available iPhone simulator')
    return sorted(choices, key=lambda d: (d['runtime'], d['name'], d['udid']))[-1]


def core_command(group, output):
    alternatives = []
    for identifier in group['methods']:
        target, cls, method = identifier.split('/')
        alternatives.append(re.escape(target + '.' + cls + '/' + method))
    require(bool(alternatives), 'Empty Core selection')
    return ['swift', 'test', '--skip-build', '--verbose', '--parallel', '--num-workers', '1', '--filter',
            '^(?:' + '|'.join(alternatives) + ')$', '--xunit-output', str(output)]


def xcode_test_command(group, run, simulator, result):
    allowance = '120' if group['name'] == 'app-unit' else '900'
    return ['xcodebuild', '-xctestrun', str(run), '-destination', 'platform=iOS Simulator,id=' + simulator,
            '-destination-timeout', '60', '-resultBundlePath', str(result), '-parallel-testing-enabled', 'NO',
            '-maximum-concurrent-test-simulator-destinations', '1', '-test-timeouts-enabled', 'YES',
            '-default-test-execution-time-allowance', allowance, '-maximum-test-execution-time-allowance', allowance,
            *['-only-testing:' + method for method in group['methods']], 'test-without-building']


def parse_xunit(raw):
    require(len(raw) <= LIMIT, 'Oversized xUnit')
    tree = ET.fromstring(raw)
    require(tree.tag in {'testsuite', 'testsuites'}, 'Unknown xUnit root')
    result = []
    for node in tree.iter('testcase'):
        cls, name = node.get('classname', ''), node.get('name', '')
        require(cls.startswith('QuestifyCoreTests.') and name, 'Unknown xUnit method identity')
        if name.endswith('()'):
            name = name[:-2]
        identifier = cls.replace('.', '/', 1) + '/' + name
        require(METHOD.fullmatch(identifier) is not None, 'Malformed xUnit method')
        require(node.get('status', 'run') in {'run', 'passed', 'Passed'}, 'Unexpected xUnit case status')
        children = {child.tag for child in node}
        require(children <= {'failure', 'error', 'skipped', 'system-out', 'system-err'}, 'Unknown xUnit result schema')
        result.append({'method': identifier, 'status': 'Skipped' if 'skipped' in children else
                       'Failed' if children & {'failure', 'error'} else 'Passed'})
    for suite in tree.iter():
        if suite.tag in {'testsuite', 'testsuites'}:
            if 'tests' in suite.attrib:
                require(suite.get('tests', '').isdigit() and int(suite.get('tests')) == len(list(suite.iter('testcase'))), 'xUnit suite count does not match cases')
            for key in ['failures', 'errors', 'skipped']:
                require(suite.get(key, '0') == '0', 'xUnit suite has non-passing outcomes')
    return result


def parse_core_transcript(raw):
    """SwiftPM xUnit records process success, including XCTSkip/zero execution.

    Require the real Darwin XCTest started/terminal lines as independent evidence.
    --verbose makes SwiftPM print successful child transcripts too.
    """
    require(len(raw) <= LIMIT, 'Oversized Core transcript')
    starts, rows = [], []
    pattern = re.compile(r"^Test Case '-\[(QuestifyCoreTests)\.([A-Za-z][A-Za-z0-9_]*) (test[A-Za-z0-9_]+)\]' (.+)$")
    for line in raw.decode('utf-8').splitlines():
        if not line.startswith('Test Case '):
            continue
        match = pattern.fullmatch(line)
        require(match is not None, 'Unknown Core XCTest transcript schema')
        target, cls, method, outcome = match.groups()
        identifier = target + '/' + cls + '/' + method
        if outcome == 'started.':
            starts.append(identifier)
        else:
            terminal = re.fullmatch(r'(passed|failed|skipped) \([0-9]+(?:\.[0-9]+)? seconds\)\.', outcome)
            require(terminal is not None, 'Unknown Core XCTest terminal result')
            rows.append({'method': identifier, 'status': {'passed': 'Passed', 'failed': 'Failed', 'skipped': 'Skipped'}[terminal[1]]})
    require(bool(rows) and len(starts) == len(set(starts)) and sorted(starts) == sorted(r['method'] for r in rows),
            'Missing/duplicate Core XCTest start or terminal result')
    return rows


def validate_core_evidence(xml, transcript, expected, returncode):
    rows = parse_xunit(xml)
    executed = parse_core_transcript(transcript)
    validate_outcomes(rows, expected, returncode)
    validate_outcomes(executed, expected, returncode)
    require(sorted(rows, key=lambda r: r['method']) == sorted(executed, key=lambda r: r['method']),
            'Core xUnit does not match actual XCTest execution')
    return rows


def parse_xcresult(data, target):
    require(isinstance(data, dict) and isinstance(data.get('testNodes'), list), 'Unknown xcresult tests schema')
    result = []
    def visit(node, ancestors):
        require(isinstance(node, dict) and isinstance(node.get('nodeType'), str), 'Malformed xcresult node')
        ancestry = ancestors + [node.get('name', '')]
        if node['nodeType'] == 'Test Case':
            identifier = node.get('nodeIdentifier')
            require(isinstance(identifier, str), 'Missing XCTest method identity')
            url = node.get('nodeIdentifierURL') or node.get('testIdentifierURL')
            if url:
                parsed = urlparse(url)
                parts = unquote(parsed.path).strip('/').split('/')
                require(parsed.scheme == 'test' and parsed.netloc == 'com.apple.xcode' and target in parts, 'Wrong XCTest target URL')
                require(not any(t in parts for t in ['QuestifyAppUnitTests', 'QuestifyUITests'] if t != target), 'Conflicting XCTest target URL')
            else:
                require(target in ancestors or target + '.xctest' in ancestors or identifier.startswith(target + '/'), 'Missing XCTest target binding')
            require(not any(t in ancestors for t in ['QuestifyAppUnitTests', 'QuestifyUITests'] if t != target), 'Wrong XCTest bundle')
            if identifier.endswith('()'):
                identifier = identifier[:-2]
            if identifier.count('/') == 1:
                identifier = target + '/' + identifier
            require(METHOD.fullmatch(identifier) is not None and identifier.startswith(target + '/'), 'Malformed XCTest method')
            require(isinstance(node.get('result'), str), 'Missing XCTest outcome')
            require(node['result'] != 'Passed' or not node.get('children'), 'Unexpected nested result/repetition in passed XCTest case')
            result.append({'method': identifier, 'status': node['result']})
        for child in node.get('children', []):
            # Test Case children include diagnostics/activities, not new methods.
            if node['nodeType'] != 'Test Case':
                visit(child, ancestry)
    for node in data['testNodes']:
        visit(node, [])
    return result


def validate_outcomes(rows, expected, returncode):
    require(type(returncode) is int and returncode == 0, 'Test process did not succeed')
    require(isinstance(rows, list) and all(isinstance(r, dict) and set(r) == {'method', 'status'} for r in rows), 'Unknown actual result rows')
    require(bool(rows), 'Zero actual tests is never success')
    identifiers = [row['method'] for row in rows]
    require(len(identifiers) == len(set(identifiers)), 'Duplicate actual tests')
    require(set(identifiers) == set(expected) and len(identifiers) == len(expected), 'Actual methods differ from exact selection')
    require(all(row['status'] == 'Passed' for row in rows), 'Failed/skipped/incomplete selected method')


def validate_summary(summary, count, simulator):
    require(isinstance(summary, dict), 'Invalid XCTest summary')
    for key, value in [('totalTestCount', count), ('passedTests', count), ('failedTests', 0), ('skippedTests', 0)]:
        require(type(summary.get(key)) is int and summary[key] == value, 'Wrong XCTest summary count: ' + key)
    require(summary.get('expectedFailures', 0) == 0, 'Expected failures are not passes')
    def contains(value):
        if isinstance(value, str):
            return value.lower() == simulator.lower()
        if isinstance(value, dict):
            return any(contains(v) for v in value.values())
        if isinstance(value, list):
            return any(contains(v) for v in value)
        return False
    require(contains(summary.get('devicesAndConfigurations')), 'Result does not identify selected simulator')


def plist_records(value):
    if isinstance(value, dict):
        if isinstance(value.get('TestBundlePath'), str):
            yield value
        for child in value.values():
            yield from plist_records(child)
    elif isinstance(value, list):
        for child in value:
            yield from plist_records(child)


def select_xctestrun(products, target):
    products = products.resolve(strict=True)
    # Expand only tokens in original templates; injected physical paths are literal.
    def expand(template, tokens):
        def replace(match):
            require(match[0] in tokens, 'Unresolved test product path')
            return tokens[match[0]]
        return re.sub(r'__[A-Z][A-Z0-9_]*?__', replace, template)

    candidates = []
    for run in products.glob('*.xctestrun'):
        require(not run.is_symlink(), 'Linked xctestrun forbidden')
        records = list(plist_records(plistlib.loads(run.read_bytes())))
        if any(Path(r['TestBundlePath']).stem == target for r in records):
            require(len(records) == 1, 'Unexpected extra test target')
            tokens = {'__TESTROOT__': str(products)}
            if records[0].get('TestHostPath'):
                tokens['__TESTHOST__'] = expand(records[0]['TestHostPath'], tokens)
            for key in ['TestBundlePath', 'TestHostPath', 'UITargetAppPath']:
                if key not in records[0]:
                    continue
                raw = expand(records[0][key], tokens)
                require(Path(raw).is_absolute(), 'Unresolved test product path')
                path = Path(raw)
                require(path.exists() and path.resolve().is_relative_to(products), 'Test product escaped build root')
            candidates.append(run)
    require(len(candidates) == 1, 'Expected exactly one matching xctestrun')
    return candidates[0]


def split404_hash(value):
    return hashlib.sha256(encode(value).encode()).hexdigest()


def split404_ledger(products):
    entries=[]; products=products.resolve(strict=True)
    for path in sorted(products.rglob('*'), key=lambda item: str(item.relative_to(products))):
        relative=str(path.relative_to(products))
        if path.is_symlink():
            require(path.resolve(strict=True).is_relative_to(products),'Products link escaped build root')
            entries.append([relative,'link',os.readlink(path)])
        elif path.is_file(): entries.append([relative,'file',digest(path)])
    require(bool(entries),'Empty product ledger')
    return entries


def split404_json(raw):
    require(len(raw)<=LIMIT,'Oversized JSON evidence')
    return json.loads(raw,object_pairs_hook=unique_object)


def split404_validate_schema(raw, kind):
    """Narrow consumed contract observed from xcresulttool24757 schema0.1.0.

    Apple Summary declares two collection fields as direct object references;
    their actual JSON arrays are separately checked in validate_device_results.
    Unknown types, references, enumerations and modifiers remain rejected.
    """
    require(kind in ('summary','tests'),'Unknown requested schema model')
    data=split404_json(raw)
    require(type(data) is dict and type(data.get('schemas')) is dict,'Unknown xcresulttool JSON schema root')
    schemas=data['schemas']
    def obj(name):
        value=schemas.get(name)
        require(type(value) is dict and value.get('type')=='object' and type(value.get('properties')) is dict,'Unsupported schema object: '+name)
        require(set(value)<={'type','properties','required','description','title','additionalProperties'},'Unsupported schema object modifiers: '+name)
        required=value.get('required',[])
        require(type(required) is list and all(type(x) is str for x in required) and len(required)==len(set(required)) and set(required)<=set(value['properties']),'Invalid schema required fields')
        return value['properties'],set(required)
    def scalar(value,expected,enum=None,format=None):
        require(type(value) is dict and value.get('type')==expected,'Unsupported schema scalar type')
        allowed={'type','description','title'}
        if enum is not None:
            allowed.add('enum');require(value.get('enum')==enum,'Unsupported schema enum domain')
        if format is not None:
            allowed.add('format');require(value.get('format')==format,'Unsupported schema numeric format')
        require(set(value)<=allowed,'Unsupported schema scalar modifier')
        require(all(type(value[k]) is str for k in ('description','title') if k in value),'Invalid schema documentation field')
    def ref(value,name):
        require(value=={'$ref':'#/schemas/'+name},'Unbound consumed schema reference')
        return schemas.get(name)
    def array(value,name):
        require(type(value) is dict and value.get('type')=='array' and set(value)<={'type','items','description','title'},'Unsupported schema array')
        ref(value.get('items'),name);obj(name)
    def result(value):
        scalar(ref(value,'TestResult'),'string',['Passed','Failed','Skipped','Expected Failure','unknown'])
    fields={'deviceId','deviceName','architecture','modelName','platform','osVersion','osBuildNumber'}
    device,required=obj('Device')
    require(set(device)==fields and {'deviceId','deviceName','architecture','modelName','osVersion'}<=required,'Unsupported Device schema')
    for value in device.values():scalar(value,'string')
    config,required=obj('Configuration');require(set(config)=={'configurationId','configurationName'} and set(config)<=required,'Unsupported Configuration schema')
    for value in config.values():scalar(value,'string')
    if kind=='summary':
        counts={'passedTests','failedTests','skippedTests','expectedFailures'}
        row,required=obj('DeviceAndConfigurationSummary');require(set(row)==counts|{'device','testPlanConfiguration'} and set(row)<=required,'Unsupported summary row schema')
        ref(row['device'],'Device');ref(row['testPlanConfiguration'],'Configuration')
        for field in counts:scalar(row[field],'integer')
        summary,required=obj('Summary');needed=counts|{'totalTestCount','result','testFailures','devicesAndConfigurations'}
        require(needed<=set(summary) and needed<=required,'Incomplete Summary schema')
        for field in counts|{'totalTestCount'}:scalar(summary[field],'integer')
        result(summary['result'])
        ref(summary['testFailures'],'TestFailure');failure,_=obj('TestFailure');scalar(failure.get('failureText'),'string')
        ref(summary['devicesAndConfigurations'],'DeviceAndConfigurationSummary')
    else:
        tests,required=obj('Tests');refs={'devices':'Device','testPlanConfigurations':'Configuration','testNodes':'TestNode'}
        require(set(refs)<=required,'Incomplete Tests schema')
        for field,name in refs.items():array(tests.get(field),name)
        node,required=obj('TestNode');require({'nodeType','name','nodeIdentifier','result','children','durationInSeconds'}<=set(node) and {'nodeType','name'}<=required,'Incomplete TestNode schema')
        for field in ('name','nodeIdentifier'):scalar(node[field],'string')
        scalar(ref(node['nodeType'],'TestNodeType'),'string',['Test Plan','Unit test bundle','UI test bundle','Test Suite','Test Case','Device','Test Plan Configuration','Arguments','Repetition','Test Case Run','Failure Message','Source Code Reference','Attachment','Expression','Test Value','Runtime Warning'])
        result(node['result']);array(node['children'],'TestNode');scalar(node['durationInSeconds'],'number',format='double')


def split404_validate_device_results(summary, tests, count, simulator, runtime):
    require(isinstance(summary,dict) and isinstance(tests,dict),'Unknown XCTest raw documents')
    for key,value in [('totalTestCount',count),('passedTests',count),('failedTests',0),('skippedTests',0),('expectedFailures',0)]:
        require(type(summary.get(key)) is int and summary[key]==value,'Wrong raw summary count: '+key)
    require(summary.get('result')=='Passed' and summary.get('testFailures')==[],'Raw summary reports nonpassing/incomplete execution')
    rows=summary.get('devicesAndConfigurations')
    require(isinstance(rows,list) and len(rows)==1,'XCTest summary must have exactly one device/configuration')
    row=rows[0]
    require(isinstance(row,dict) and set(row)=={'device','testPlanConfiguration','passedTests','failedTests','skippedTests','expectedFailures'},'Unknown device/configuration summary fields')
    for key,value in [('passedTests',count),('failedTests',0),('skippedTests',0),('expectedFailures',0)]:
        require(type(row.get(key)) is int and row[key]==value,'Wrong device-specific count')
    device=row['device'];config=row['testPlanConfiguration']
    fields={'deviceId','deviceName','architecture','modelName','platform','osVersion','osBuildNumber'}
    require(isinstance(device,dict) and set(device)==fields and all(isinstance(v,str) and v for v in device.values()),'Unknown actual XCTest device schema')
    require(device['deviceId'].lower()==simulator['udid'].lower() and device['deviceName']==simulator['name'] and device['platform']=='iOS Simulator' and device['osVersion']==runtime['version'] and device['osBuildNumber']==runtime['buildversion'],'Executed device/OS differs from actual selected runtime')
    require(isinstance(config,dict) and set(config)=={'configurationId','configurationName'} and all(isinstance(v,str) and v for v in config.values()),'Unknown test-plan configuration')
    require(tests.get('devices')==[device] and tests.get('testPlanConfigurations')==[config],'Raw tests/summary device or configuration differs')


def read_json(path):
    raw = Path(path).read_bytes()
    require(len(raw) <= LIMIT, 'Oversized JSON evidence')
    return json.loads(raw, object_pairs_hook=unique_object)

def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()

# Current-only orchestration. No call below restores historical source or imports
# the predecessor runner. The original parsing functions above remain exact.
import platform
import tarfile

BUDGET = {'core-build': 720, 'core-test': 180, 'app-build': 1200, 'app-test': 660,
          'ui-build': 1200, 'ui-test': 2190, 'boot': 180}
WORKER_CAP = 2700
RESERVE = 240


def verify_plan(root, path):
    plan = control.read_json(path); manifest = control.verified_manifest(root)
    require(plan['identity'] == control.source_identity(root), 'Foreign SHA/tree/run/attempt plan')
    mode = 'full' if plan['scope'] == 'full-current-regression' else 'related'
    require(control.make_plan(root, manifest, plan['base'], mode) == plan, 'Changed current selection or incomplete plan')
    return plan


def toolchain(run):
    commands = {'xcode': ['xcodebuild', '-version'], 'developer': ['xcode-select', '-p'],
                'swift': ['swift', '--version'], 'sdk_version': ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'],
                'sdk_path': ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path']}
    result = {key: run(command, 60, 'toolchain-' + key).decode().strip() for key, command in commands.items()}
    result['architecture'] = platform.machine()
    require(all(result.values()), 'Missing actual toolchain field')
    return result


def same_identity(receipt, plan):
    require(receipt.get('identity') == plan['identity'] and receipt.get('plan_sha256') == control.digest(control.encode(plan)), 'Foreign current result provenance')


def normalized_ui_products(products):
    try:
        from tools.test_products import normalize_paths
    except ModuleNotFoundError:
        from test_products import normalize_paths
    for path in products.glob('*.xctestrun'):
        data = plistlib.loads(path.read_bytes())
        path.write_bytes(plistlib.dumps(normalize_paths(data, products)))
    run = select_xctestrun(products, 'QuestifyUITests')
    app = products / 'Debug-iphonesimulator/Questify.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    require(info.get('QuestifyAPIBaseURL') in (None, '') and info.get('CFBundleSupportedPlatforms') == ['iPhoneSimulator']
            and not (app / 'embedded.mobileprovision').exists(), 'UI products are not isolated unsigned fixtures')
    return run


def pack_ui(products, destination, receipt):
    run = normalized_ui_products(products); ledger = split404_ledger(products)
    archive = destination / 'products.tar.gz'
    with tarfile.open(archive, 'w:gz', compresslevel=1) as output: output.add(products, arcname='Products')
    receipt.update(status='BUILT', executed_methods=[], product_ledger=ledger,
                   xctestrun=run.name, archive_sha256=digest(archive))
    write_json(destination / 'receipt.json', receipt)


def restore_ui(directory, destination, plan, actual_toolchain):
    require(directory.is_dir() and not directory.is_symlink(), 'Missing actual UI build artifact')
    receipt = read_json(directory / 'receipt.json'); same_identity(receipt, plan)
    require(receipt.get('status') == 'BUILT' and receipt.get('role') == 'ui-build' and receipt.get('executed_methods') == [], 'Build is not a native execution result')
    require(receipt.get('toolchain') == actual_toolchain, 'UI worker toolchain/SDK/architecture differs from builder')
    archive = directory / 'products.tar.gz'
    require(not archive.is_symlink() and digest(archive) == receipt.get('archive_sha256'), 'Downloaded build archive changed')
    require(not destination.exists(), 'Pre-existing UI test products forbidden'); destination.mkdir()
    with tarfile.open(archive, 'r:gz') as stream:
        for member in stream.getmembers():
            p = Path(member.name)
            require(not p.is_absolute() and '..' not in p.parts and p.parts and p.parts[0] == 'Products', 'Archive path escape')
        stream.extractall(destination, filter='data')
    products = destination / 'Products'
    require(split404_ledger(products) == receipt['product_ledger'], 'Restored build file ledger differs')
    run = select_xctestrun(products, 'QuestifyUITests')
    require(run.name == receipt['xctestrun'], 'Restored test target differs')
    return products, run, receipt


def group(plan, partition, index=None):
    target = {'core': 'QuestifyCoreTests', 'app-unit': 'QuestifyAppUnitTests', 'ui': 'QuestifyUITests'}[partition]
    if partition == 'ui':
        require(type(index) is int and 0 <= index < len(plan['ui_shards']), 'Foreign UI shard')
        methods = plan['ui_shards'][index]['methods']
    else: methods = plan['groups'][partition]
    require(methods and len(methods) == len(set(methods)), 'Empty/duplicated exact selection')
    return {'name': partition, 'target': target, 'methods': methods}


def core_bundle_ledger(root):
    build=(root/'.build').resolve(strict=True)
    found={p.resolve() for p in build.rglob('QuestifyCorePackageTests.xctest') if p.is_dir() and not p.is_symlink()}
    require(len(found)==1,'Expected one fresh actual Core XCTest bundle')
    bundle=next(iter(found));require(bundle.is_relative_to(build),'Core bundle escaped build root')
    return split404_ledger(bundle)


def execute_current(root, plan, role, output, start_file, index=None, build=None):
    start = float(start_file.read_text()); now = time.monotonic()
    require(0 < start <= now, 'Invalid actual job-entry clock')
    deadline = start + WORKER_CAP - RESERVE
    require(not output.exists() and output.parent.resolve() == Path(os.environ['RUNNER_TEMP']).resolve(), 'Fresh runner-temp output required')
    output.mkdir(); commands = []; receipt = {'version': 1, 'identity': plan['identity'], 'plan_sha256': control.digest(control.encode(plan)), 'role': role, 'index': index, 'status': 'INCOMPLETE', 'expected': [], 'actual': []}
    def save():
        if (output/'commands.json').is_file(): receipt['commands_sha256']=digest(output/'commands.json')
        write_json(output / 'receipt.json', receipt)
    def run(argv, seconds, stem, allow_failure=False):
        remaining = deadline - time.monotonic(); require(remaining > 0, 'Actual worker execution window exhausted')
        before = time.monotonic(); code, raw = execute(argv, root, min(seconds, remaining), capture='stdout')
        (output / (stem + '.stdout')).write_bytes(raw)
        commands.append({'stem': stem, 'argv': [str(x) for x in argv], 'returncode': code, 'seconds': time.monotonic()-before, 'stdout_sha256': control.digest(raw)})
        write_json(output / 'commands.json', commands)
        require(allow_failure or code == 0, 'Command failed: ' + stem)
        return raw
    def inventory():
        argv = ['xcrun', 'simctl', 'list', 'devices', 'available', '--json']
        raw = run(argv, 60, 'devices-first', True)
        if commands[-1]['returncode'] != 0:
            # One bounded same-environment retry; preserve the timeout diagnostic.
            # No service reset, chosen-device substitution, or infinite wait.
            raw = run(argv, 60, 'devices-retry')
        raw = json.loads(raw, object_pairs_hook=unique_object)
        sim = choose_simulator(raw)
        runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '--json'], 60, 'runtimes'), object_pairs_hook=unique_object)
        matches = [x for x in runtimes.get('runtimes', []) if x.get('identifier') == sim['runtime'] and x.get('isAvailable') is True]
        require(len(matches) == 1, 'Selected simulator has no exact available runtime')
        return sim, matches[0]
    try:
        receipt['toolchain'] = toolchain(run); save()
        if role == 'core':
            g = group(plan, 'core'); receipt['expected'] = g['methods']; save()
            require(not (root / '.build').exists(), 'Preexisting Core products forbidden')
            target=json.loads(run(['swift','-print-target-info'],60,'host-target'),object_pairs_hook=unique_object)
            host={'triple':target['target']['triple'],'sdk_path':run(['xcrun','--sdk','macosx','--show-sdk-path'],60,'host-sdk-path').decode().strip(),'sdk_version':run(['xcrun','--sdk','macosx','--show-sdk-version'],60,'host-sdk-version').decode().strip()}
            require(all(type(v) is str and v for v in host.values()),'Incomplete actual Core host target')
            receipt['host_target']=host; host_args=['--sdk',host['sdk_path'],'--triple',host['triple']]
            run(['swift', 'build', '--build-tests']+host_args, BUDGET['core-build'], 'core-build')
            before=core_bundle_ledger(root);receipt['product_ledger_sha256']=split404_hash(before)
            for checker in ['check_content_draft_api_boundary.py','check_play_recovery_api_boundary.py']:
                run([sys.executable,'-B','tools/'+checker,'--module-path','.build/debug/Modules'],60,checker)
            result = output / 'core.xml'; argv = core_command(g, result)+host_args
            raw = run(argv, BUDGET['core-test'], 'core-test', True)
            rows = validate_core_evidence(result.read_bytes(), raw, g['methods'], commands[-1]['returncode'])
            require(core_bundle_ledger(root)==before,'Core test bundle changed during skip-build execution')
            receipt['actual'] = rows; receipt['raw_sha256']={name:digest(output/name) for name in ['core.xml','core-test.stdout']}
        else:
            sim, runtime = inventory(); receipt.update(simulator=sim, runtime=runtime); save()
            if role == 'ui-build':
                derived = output / 'ui-build'
                argv = ['xcodebuild', '-project', 'Questify.xcodeproj', '-scheme', 'Questify', '-configuration', 'Debug', '-sdk', 'iphonesimulator', '-destination', 'platform=iOS Simulator,id='+sim['udid'], '-destination-timeout', '60', '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO', 'ONLY_ACTIVE_ARCH=NO', 'build-for-testing']
                run(argv, BUDGET['ui-build'], 'ui-build'); receipt['build_argv']=argv; receipt['build_returncode']=commands[-1]['returncode']
                require(toolchain(run) == receipt['toolchain'], 'Toolchain changed during UI build')
                require(control.source_identity(root) == plan['identity'], 'Source changed during UI build')
                app=derived/'Build/Products/Debug-iphonesimulator/Questify.app'
                run([sys.executable,'-B','tools/check_built_profile.py','--market','CN','--plist',str(app/'Info.plist')],60,'compiled-cn-privacy')
                run([sys.executable,'-B','tools/check_gltf_linked.py','--app',str(app)],60,'compiled-gltf-link')
                pack_ui(derived / 'Build/Products', output, receipt); return
            if role == 'app-unit':
                g = group(plan, 'app-unit')
                run([sys.executable, '-B', 'tools/build_simulator_keychain_host.py', '--source-root', str(root), '--commit', plan['identity']['sha'], '--simulator', sim['udid'], '--approve-ephemeral-simulator-host'], BUDGET['app-build'], 'app-build')
                products = Path(os.environ['RUNNER_TEMP']) / 'app-unit-linked/Products'
                selected_run = select_xctestrun(products, g['target']); binding = read_json(products / 'questify-test-products.json')
                require(binding.get('commit') == plan['identity']['sha'] and binding.get('purpose') == 'isolated-simulator-app-unit' and binding.get('toolchain') == {k: receipt['toolchain'][k] for k in ('xcode', 'developer')}, 'App host belongs to another current build')
            else:
                require(role == 'ui' and build is not None, 'Unknown current native role')
                g = group(plan, 'ui', index); products, selected_run, build_receipt = restore_ui(build, output / 'restored', plan, receipt['toolchain'])
                receipt['build_receipt_sha256'] = control.digest(control.encode(build_receipt))
            receipt['expected'] = g['methods']; before = split404_ledger(products); receipt['product_ledger_sha256'] = split404_hash(before); save()
            run(['xcrun', 'simctl', 'bootstatus', sim['udid'], '-b'], BUDGET['boot'], 'boot')
            result = output / (role + '.xcresult'); argv = xcode_test_command(g, selected_run, sim['udid'], result)
            run(argv, BUDGET['app-test' if role == 'app-unit' else 'ui-test'], 'native-test', True); code = commands[-1]['returncode']
            docs = {}
            for kind in ('summary', 'tests'):
                raw = run(['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--path', str(result), '--compact'], 60, kind)
                (output / (kind+'.json')).write_bytes(raw); docs[kind] = json.loads(raw, object_pairs_hook=unique_object)
            rows = parse_xcresult(docs['tests'], g['target']); validate_outcomes(rows, g['methods'], code)
            split404_validate_device_results(docs['summary'], docs['tests'], len(g['methods']), sim, runtime)
            require(split404_ledger(products) == before, 'Products changed or rebuilt during test-without-building')
            receipt['actual'] = rows; receipt['raw_sha256']={name:digest(output/name) for name in ['summary.json','tests.json']}
        require(toolchain(run) == receipt['toolchain'], 'Toolchain changed during actual execution')
        require(control.source_identity(root) == plan['identity'], 'Current source changed during execution')
        receipt.update(status='PASS', worker_seconds=time.monotonic()-start); save()
    except BaseException as error:
        receipt.update(status='FAIL', error=str(error), worker_seconds=time.monotonic()-start); save(); raise


def reparse_actual_result(directory, plan):
    receipt=read_json(directory/'receipt.json'); same_identity(receipt,plan)
    require(receipt.get('status')=='PASS','Incomplete actual result artifact')
    commands=read_json(directory/'commands.json')
    require(digest(directory/'commands.json')==receipt.get('commands_sha256'),'Recorded actual command evidence changed')
    role=receipt.get('role'); g=group(plan,role,receipt.get('index'))
    stem='core-test' if role=='core' else 'native-test'
    tests=[row for row in commands if row.get('stem')==stem]
    require(len(tests)==1 and tests[0].get('returncode')==0,'Missing or failed unique actual native command')
    for name, expected in receipt.get('raw_sha256',{}).items():
        require(name in {'core.xml','core-test.stdout','summary.json','tests.json'} and digest(directory/name)==expected,'Actual result bytes changed')
    if role=='core':
        require(set(receipt['raw_sha256'])=={'core.xml','core-test.stdout'},'Missing Core raw evidence')
        argv=tests[0]['argv']; marker=argv.index('--xunit-output') if '--xunit-output' in argv else -1
        host=receipt['host_target'];require(set(host)=={'sdk_path','sdk_version','triple'} and all(type(v) is str and v for v in host.values()),'Missing actual Core host identity')
        require(marker>=0 and argv==core_command(g,argv[marker+1])+['--sdk',host['sdk_path'],'--triple',host['triple']],'Actual Core filter/SDK/target differs from current selected methods')
        require(control.digest((directory/'core-test.stdout').read_bytes())==tests[0]['stdout_sha256'],'Core transcript not bound to actual command')
        actual=validate_core_evidence((directory/'core.xml').read_bytes(),(directory/'core-test.stdout').read_bytes(),g['methods'],0)
    else:
        require(set(receipt['raw_sha256'])=={'summary.json','tests.json'},'Missing raw XCTest result documents')
        argv=tests[0]['argv']; flags={flag:argv[argv.index(flag)+1] for flag in ('-xctestrun','-resultBundlePath') if flag in argv}
        require(set(flags)=={'-xctestrun','-resultBundlePath'} and argv==xcode_test_command(g,flags['-xctestrun'],receipt['simulator']['udid'],flags['-resultBundlePath']),'Actual XCTest command differs from complete selected shard')
        summary=read_json(directory/'summary.json'); tests_doc=read_json(directory/'tests.json')
        actual=parse_xcresult(tests_doc,g['target']);validate_outcomes(actual,g['methods'],0)
        split404_validate_device_results(summary,tests_doc,len(g['methods']),receipt['simulator'],receipt['runtime'])
    require(actual==receipt.get('actual'),'Receipt does not match reparsed raw execution')
    return receipt


def aggregate_current(plan, artifacts, needs):
    require(type(needs) is dict and set(needs) == {'controls', 'secrets', 'native', 'ui', 'platforms'} and all(needs[key].get('result') == 'success' for key in ('controls','secrets','native','ui')), 'A required current worker failed/skipped/cancelled')
    require(needs['platforms'].get('result') == ('success' if plan['scope']=='full-current-regression' else 'skipped'), 'Required full platform checks did not succeed')
    expected = {'core': group(plan, 'core')['methods'], 'app-unit': group(plan, 'app-unit')['methods']}
    expected.update({'ui-'+str(i): row['methods'] for i, row in enumerate(plan['ui_shards'])})
    require(set(artifacts) == set(expected), 'Missing, duplicate, or foreign native receipt')
    actual = []
    for key, methods in expected.items():
        receipt = artifacts[key]; same_identity(receipt, plan)
        role = 'ui' if key.startswith('ui-') else key
        tc=receipt.get('toolchain');require(type(tc) is dict and set(tc)=={'xcode','developer','swift','sdk_version','sdk_path','architecture'} and all(type(v) is str and v for v in tc.values()),'Missing actual Apple toolchain identity')
        require(type(receipt.get('worker_seconds')) in (int,float) and 0<receipt['worker_seconds']<=WORKER_CAP,'Invalid bounded worker observation')
        require(receipt.get('role') == role and receipt.get('status') == 'PASS' and receipt.get('expected') == methods, 'Incomplete or wrong current native receipt')
        require(receipt.get('index') == (int(key[3:]) if role == 'ui' else None), 'Wrong UI shard index')
        validate_outcomes(receipt.get('actual'), methods, 0); actual.extend(row['method'] for row in receipt['actual'])
    union = [m for methods in plan['groups'].values() for m in methods]
    require(len(actual) == len(set(actual)) and set(actual) == set(union), 'Current selected execution union is incomplete or duplicated')
    return {'version': 1, 'scope': plan['scope'], 'status': 'PASS', 'identity': plan['identity'], 'selected_count': len(union), 'executed_count': len(actual), 'full_ledger_count': plan['complete_native_ledger_count'], 'plan_sha256': control.digest(control.encode(plan))}


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['run', 'aggregate']); parser.add_argument('--root', type=Path, default=control.ROOT); parser.add_argument('--plan', type=Path, required=True); parser.add_argument('--role', choices=['core','app-unit','ui-build','ui']); parser.add_argument('--output', type=Path, required=True); parser.add_argument('--start-file', type=Path); parser.add_argument('--index', type=int); parser.add_argument('--build', type=Path); parser.add_argument('--artifacts', type=Path); args = parser.parse_args(); plan = verify_plan(args.root, args.plan)
    if args.action == 'run':
        require(args.role and args.start_file, 'Native role and actual start clock required'); execute_current(args.root, plan, args.role, args.output, args.start_file, args.index, args.build)
    else:
        require(args.artifacts is not None, 'Actual downloaded artifacts required')
        receipts = {}
        for p in args.artifacts.glob('*/receipt.json'):
            receipt = reparse_actual_result(p.parent,plan); key = 'ui-'+str(receipt['index']) if receipt.get('role') == 'ui' else receipt.get('role')
            require(key not in receipts, 'Duplicate result artifact'); receipts[key] = receipt
        result = aggregate_current(plan, receipts, json.loads(os.environ['NEEDS_JSON'], object_pairs_hook=unique_object)); write_json(args.output, result); print(json.dumps(result))


if __name__ == '__main__': main()
