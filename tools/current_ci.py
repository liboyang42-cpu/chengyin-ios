#!/usr/bin/env python3
"""Daily current-checkout planning. Historical reconstruction is never imported.

The complete test ledger remains visible even when daily execution selects only
changed product groups plus smoke. Full current regression is an explicit mode.
"""
import argparse
import ast
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'tools/current_ci_manifest.json'
TARGETS = {'Tests/CoreTests': 'QuestifyCoreTests', 'Tests/AppUnitTests': 'QuestifyAppUnitTests', 'Tests/AppUITests': 'QuestifyUITests'}
PARTITIONS = {'QuestifyCoreTests': 'core', 'QuestifyAppUnitTests': 'app-unit', 'QuestifyUITests': 'ui'}
FAMILIES = ('Club', 'Merchant', 'Profile', 'Ticket', 'Roam', 'Template', 'Project', 'Play', 'Search', 'Account', 'Activity', 'Map', 'Growth', 'Coupon')
SHARD_LIMIT = 1500
METHOD_LIMIT = 900
LIMIT = 10 * 1024 * 1024

# These eight declarations are absent from simulator binaries by their existing
# outer compile guard. Keep their identities in the complete ledger and report
# physical-device acceptance as NOT_RUN, never as passed simulator coverage.
# Any source change requires an explicit review of this exact classification.
DEVICE_ONLY_SOURCES = [{'path': 'Tests/AppUnitTests/ContentDraftDeviceStorageAcceptanceTests.swift', 'sha256': 'f6e68e77cc1f9b5bd80efdb31f5ded921a1c25142caafc2900e8f2a4073f7189', 'class': 'ContentDraftDeviceStorageAcceptanceTests', 'methods': ['testRealExclusiveCiphertextFileBoundedReadAndCleanup', 'testRealPresenceMarkerIsExclusivePermanentAndEmpty', 'testSyntheticFilesystemPrerequisitesReportNumericStage', 'testSyntheticFoundationClassAIndependentControl', 'testSyntheticRegularFileClassAIndependentControl']}, {'path': 'Tests/AppUnitTests/PlayRecoveryDeviceStorageAcceptanceTests.swift', 'sha256': '2b01f4132b1ddfafde26491f4d8534ca46efa2d346b6784043992ecf855e3dbf', 'class': 'PlayRecoveryDeviceStorageAcceptanceTests', 'methods': ['testConcreteOSRelaunchCASAndNoPlaintextOrCredentialFiles', 'testMissingKeychainAfterWrittenPresenceFailsClosedWithoutReplacement', 'testPartialCiphertextAndForeignRoleNeverUnlockOSPending']}]


def device_only_ledger():
    return {"QuestifyAppUnitTests/"+row['class']+"/"+method: row['path']
            for row in DEVICE_ONLY_SOURCES for method in row['methods']}


def classify_device_only(native_sources, native):
    expected = device_only_ledger()
    for row in DEVICE_ONLY_SOURCES:
        path = row['path']
        require(path in native_sources, 'Missing explicit device-only source: '+path)
        target, source = native_sources[path]
        require(target == 'QuestifyAppUnitTests' and digest(source.encode()) == row['sha256'],
                'Device-only source requires renewed explicit platform review: '+path)
        directives = re.findall(r'^\s*#(?:if|elseif|else|endif)\b[^\n]*', source, re.M)
        require([line.strip() for line in directives] == ['#if os(iOS) && !targetEnvironment(simulator)', '#endif'],
                'Device-only compile guard changed')
        require({method for method, owner in native.items() if owner == path} ==
                {method for method, owner in expected.items() if owner == path}, 'Device-only declaration set changed')
    require(all(native.get(method) == path for method, path in expected.items()), 'Device-only identity or path changed')
    return expected


def device_only_not_run(snapshot):
    classified = snapshot.get('device_only_methods', {})
    require(type(classified) is dict and (not classified or classified == device_only_ledger()),
            'Unknown physical-device classification')
    require(all(snapshot['native_methods'].get(method) == path for method,path in classified.items()),
            'Physical-device classification is outside the complete ledger')
    return [{'method':method, 'path':path, 'platform':'physical-ios-device', 'status':'NOT_RUN',
             'reason':'Excluded from simulator by existing compile guard; hardware acceptance not executed'}
            for method,path in sorted(classified.items())]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_json(path):
    raw = Path(path).read_bytes()
    require(len(raw) <= LIMIT, 'Oversized current CI document')
    return json.loads(raw, object_pairs_hook=unique)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def source_identity(root=ROOT, environ=None):
    env = os.environ if environ is None else environ
    head = git(root, 'rev-parse', 'HEAD').decode().strip()
    require(re.fullmatch('[a-f0-9]{40}', head) is not None and env.get('GITHUB_SHA', head) == head, 'Foreign current checkout SHA')
    require(not git(root, 'status', '--porcelain', '--untracked-files=all'), 'Current checkout has uncommitted files')
    require(env.get('GITHUB_WORKFLOW_SHA',head)==head,'Workflow/source SHA differs')
    if env.get('CI')=='true':
        require(env.get('GITHUB_REPOSITORY')=='liboyang42-cpu/chengyin-ios' and env.get('GITHUB_EVENT_NAME') in {'push','pull_request','workflow_dispatch'},'Unexpected current CI origin')
    result = {'sha': head, 'tree': git(root, 'rev-parse', 'HEAD^{tree}').decode().strip()}
    for key, name in [('run_id', 'GITHUB_RUN_ID'), ('attempt', 'GITHUB_RUN_ATTEMPT')]:
        value = env.get(name, '1')
        require(re.fullmatch('[1-9][0-9]*', value) is not None, 'Invalid same-run identity')
        result[key] = value
    return result


def swift_tokens(source):
    """Declaration lexer; nested comments, raw strings, interpolation stay opaque."""
    result = []; i = 0; n = len(source)
    token = re.compile(r'[A-Za-z_][A-Za-z_0-9]*|[{}():,<>]')
    def comment(at):
        if source.startswith('//', at):
            end = source.find('\n', at); return n if end < 0 else end
        depth = 1; at += 2
        while at < n and depth:
            if source.startswith('/*', at): depth += 1; at += 2
            elif source.startswith('*/', at): depth -= 1; at += 2
            else: at += 1
        require(depth == 0, 'Unterminated Swift comment'); return at
    def string(at):
        start = at
        while at < n and source[at] == '#': at += 1
        hashes = at - start
        if at >= n or source[at] != '"': return None
        quote = '"""' if source.startswith('"""', at) and re.match(r'"""[ \t]*\r?\n', source[at:]) else '"'
        end = quote + '#' * hashes; escape = '\\' + '#' * hashes; at += len(quote)
        while at < n:
            if source.startswith(end, at): return at + len(end)
            if source.startswith(escape + '(', at):
                at += len(escape) + 1; depth = 1
                while at < n and depth:
                    if source.startswith(('//', '/*'), at): at = comment(at); continue
                    nested = string(at) if source[at] in '#"' else None
                    if nested is not None: at = nested; continue
                    if source[at] == '(': depth += 1
                    elif source[at] == ')': depth -= 1
                    at += 1
                require(depth == 0, 'Unterminated Swift interpolation')
            elif source.startswith(escape, at): at += len(escape) + 1
            else: at += 1
        raise ValueError('Unterminated Swift string')
    while i < n:
        if source.startswith(('//', '/*'), i): i = comment(i); continue
        end = string(i) if source[i] in '#"' else None
        if end is not None: i = end; continue
        match = token.match(source, i)
        if match: result.append(match.group()); i = match.end()
        else: i += 1
    return result


def declared_case_names(source):
    tokens=swift_tokens(source); result=set()
    for i,value in enumerate(tokens[:-2]):
        if value!='class': continue
        end=i+2
        while end<len(tokens) and tokens[end] not in ('{','}'): end+=1
        if 'XCTestCase' in tokens[i+2:end]: result.add(tokens[i+1])
    return result


def swift_methods(source, target, known_cases=None):
    tokens = swift_tokens(source); depth = 0; owners = []; extensions=[]; out = []
    cases=declared_case_names(source)|set(known_cases or ())
    for i, value in enumerate(tokens):
        if value in {'class','extension'} and i + 2 < len(tokens):
            end = i + 2
            while end < len(tokens) and tokens[end] not in ('{', '}'): end += 1
            require(end<len(tokens),'Type declaration missing body')
            name=tokens[i+1]
            if value=='extension': extensions.append((name,depth+1))
            if name in cases:
                require(tokens[end] == '{', 'Test class/extension missing body')
                owners.append((name, depth + 1))
        if value == '{': depth += 1
        elif value == '}':
            depth -= 1
            while owners and owners[-1][1] > depth: owners.pop()
            while extensions and extensions[-1][1] > depth: extensions.pop()
        elif value == 'func' and i + 2 < len(tokens) and tokens[i + 1].startswith('test') and tokens[i + 2] == '(':
            if owners:
                require(depth == owners[-1][1], 'Nested test declaration cannot be silently inventoried')
                out.append(target + '/' + owners[-1][0] + '/' + tokens[i + 1])
            elif extensions:
                raise ValueError('Unresolved test-bearing extension: '+extensions[-1][0])
    require(depth == 0 and len(out) == len(set(out)), 'Invalid or duplicate Swift test declarations')
    return out


def python_methods(source, path):
    tree = ast.parse(source); out = []
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            for method in node.body:
                if isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)) and method.name.startswith('test_'):
                    out.append(path + '::' + node.name + '.' + method.name)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith('test_'):
            out.append(path + '::' + node.name)
    require(len(out) == len(set(out)), 'Duplicate Python declaration identity')
    return out


def source_hashes(snapshot):
    rows=snapshot['sources']
    require(type(rows) is list,'Current source rows must be a list')
    result={}
    for row in rows:
        require(type(row) is dict and set(row)=={'path','sha256'},'Unknown source row fields')
        path,value=row['path'],row['sha256']
        require(isinstance(path,str) and path and path not in result and isinstance(value,str) and re.fullmatch('[a-f0-9]{64}',value) is not None,'Invalid/duplicate current source row')
        result[path]=value
    return result


def snapshot(root=ROOT, revision=None):
    entries = {line.split('\t',1)[1]:line.split()[2] for line in git(root,'ls-tree','-r',revision).decode().splitlines()} if revision else {}
    names = sorted(entries) if revision else git(root, 'ls-files').decode().splitlines()
    sources = {}; native = {}; portable = {}; native_sources = {}
    for path in names:
        if path == MANIFEST: continue
        file = Path(root) / path
        require(revision is not None or not file.is_symlink(), 'Tracked source is a symlink: ' + path)
        require(revision is not None or file.is_file(), 'Missing tracked source: ' + path)
        raw = file.read_bytes() if file.is_file() else b''
        if revision and hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=entries[path]: raw=git(root,'show',revision+':'+path)
        sources[path] = digest(raw)
        for directory, target in TARGETS.items():
            if path.startswith(directory + '/') and path.endswith('.swift'):
                native_sources[path]=(target,raw.decode())
        if path.endswith('.py') and (path.startswith('tools/tests/test_') or path.startswith('Tests/ContractChecks/test_')):
            portable.update({method: path for method in python_methods(raw.decode(), path)})
    cases={target:set() for target in TARGETS.values()}
    for target,source in native_sources.values(): cases[target].update(declared_case_names(source))
    for path,(target,source) in native_sources.items():
        for method in swift_methods(source,target,cases[target]):
            require(method not in native,'Duplicate native identity across files'); native[method]=path
    require(bool(native) and bool(portable), 'Empty complete source test ledger')
    return {'sources': [{'path':p,'sha256':h} for p,h in sorted(sources.items())], 'native_methods': native, 'portable_methods': portable, 'device_only_methods': classify_device_only(native_sources,native)}


def audit(previous, current, retired=None):
    retired = {} if retired is None else retired
    require(type(retired) is dict and all(isinstance(k, str) and isinstance(v, str) and v.strip() for k, v in retired.items()), 'Invalid explicit test retirement review')
    old = set(previous['native_methods']) | set(previous['portable_methods'])
    new = set(current['native_methods']) | set(current['portable_methods'])
    removed = old - new
    require(set(retired) == removed, 'Missing or extraneous explicit test retirement review')
    current_hashes,previous_hashes=source_hashes(current),source_hashes(previous)
    return {'added': sorted(new - old), 'removed': sorted(removed), 'retirement_review': retired,
            'changed_test_sources': sorted(p for p in set(current['native_methods'].values()) | set(current['portable_methods'].values())
                                           if current_hashes[p] != previous_hashes.get(p))}


def partition(costs):
    groups = []
    for method, cost in sorted(costs.items(), key=lambda item: (-item[1], item[0])):
        require(type(cost) in (int, float) and math.isfinite(cost) and 0 < cost <= METHOD_LIMIT, 'Invalid complete method cost')
        choices = [i for i, row in enumerate(groups) if row['seconds'] + cost <= SHARD_LIMIT]
        index = min(choices, key=lambda i: (groups[i]['seconds'], i)) if choices else len(groups)
        if index == len(groups): groups.append({'methods': [], 'seconds': 0})
        groups[index]['methods'].append(method); groups[index]['seconds'] += cost
    for group in groups: group['methods'].sort()
    require(Counter(method for row in groups for method in row['methods']) == Counter(costs.keys()), 'Incomplete or duplicate UI partition')
    return groups


def parse_project(text):
    text=re.sub(r'^//.*$', '', text, flags=re.M)
    tokens=re.findall(r'"(?:\\.|[^"\\])*"|\d+|[{}()=;,]', text)
    index=0
    def take(expected=None):
        nonlocal index
        value=tokens[index]; index+=1
        if expected is not None: assert value==expected, (value,expected)
        return value
    def value():
        token=take()
        if token=='{':
            result={}
            while tokens[index]!='}':
                key=json.loads(take()); take('='); result[key]=value(); take(';')
            take('}'); return result
        if token=='(':
            result=[]
            while tokens[index]!=')': result.append(value()); take(',')
            take(')'); return result
        return json.loads(token)
    result=value(); assert index==len(tokens); return result

def pbx_registration_only(before, after, exact_renames=None):
    """Only added file/build-file/group registrations; settings/targets unchanged."""
    old,new=parse_project(before),parse_project(after)
    if {k:v for k,v in old.items() if k!='objects'}!={k:v for k,v in new.items() if k!='objects'}: return False
    a,b=old['objects'],new['objects']
    for value in a.values():
        if value.get('isa')=='PBXFileReference' and value.get('path') in (exact_renames or {}):
            value['path']=exact_renames[value['path']]
    if not set(a)<=set(b): return False
    for key,value in a.items():
        current=b[key]
        allowed = {'children'} if value.get('isa')=='PBXGroup' else {'files'} if value.get('isa') in {'PBXSourcesBuildPhase','PBXResourcesBuildPhase'} else set()
        if {k:v for k,v in value.items() if k not in allowed}!={k:v for k,v in current.items() if k not in allowed}: return False
        for field in allowed:
            previous=value.get(field,[]); following=current.get(field,[])
            if len(following)!=len(set(following)) or [x for x in following if x in set(previous)]!=previous: return False
    return all(b[key].get('isa') in {'PBXFileReference','PBXBuildFile','PBXGroup'} for key in set(b)-set(a))


def select(snapshot, changed_paths, smoke, mode='related', dependencies=None, registration_only=False):
    require(mode in {'related', 'full'}, 'Unknown current regression mode')
    all_methods = snapshot['native_methods']; selected = set(smoke)
    require(selected <= set(all_methods), 'Smoke points outside current source')
    changed = set(changed_paths); dependencies = {} if dependencies is None else dependencies
    full = mode == 'full'
    broad_units = any(p in changed for p in ['Package.swift','Config/Base.xcconfig','App/AppSession.swift']) or ('Questify.xcodeproj/project.pbxproj' in changed and not registration_only)
    for path in changed:
        if path.startswith(('Core/', 'App/')) and path.endswith('.swift'):
            # The generated, reviewable symbol dependency table is conservative.
            # Unmapped/global changes cannot silently discard product coverage.
            reviewed=dependencies.get('reviewed_impacts',{}).get(path)
            if reviewed is not None:
                selected.update(method for method,test in all_methods.items() if test in reviewed['test_files']); continue
            if path == 'App/AppSession.swift' or path not in dependencies.get('dependents', {}): broad_units = True; continue
            affected = set(); pending = [path]
            while pending:
                source = pending.pop()
                if source in affected: continue
                affected.add(source); pending.extend(dependencies['dependents'][source])
            tests = {test for test, owners in dependencies['test_sources'].items() if set(owners) & affected}
            if not tests: broad_units = True
            named_ui=set(dependencies.get('named_ui_groups',{}).get(path,[]))
            selected.update(method for method, test in all_methods.items() if test in tests or test in named_ui)
    for method, path in all_methods.items():
        if full or (broad_units and not method.startswith('QuestifyUITests/')) or path in changed: selected.add(method)
    selected.difference_update(row['method'] for row in device_only_not_run(snapshot))
    return {part: sorted(m for m in selected if PARTITIONS[m.split('/')[0]] == part) for part in ('core', 'app-unit', 'ui')}


def source_dependencies(root, snapshot):
    sources = {}; declarations = {}
    for path, source_sha256 in source_hashes(snapshot).items():
        if path.startswith(('Core/', 'App/')) and path.endswith('.swift'):
            tokens = swift_tokens((Path(root)/path).read_text()); sources[path] = set(tokens)
            depth = 0
            for i, token in enumerate(tokens[:-1]):
                if token == '{': depth += 1
                elif token == '}': depth -= 1
                elif depth == 0 and token in {'class','struct','enum','actor','protocol','typealias'}:
                    declarations.setdefault(tokens[i+1],set()).add(path)
    direct = {path: set() for path in sources}
    for path, tokens in sources.items():
        for token in tokens:
            for owner in declarations.get(token, ()):
                if owner != path: direct[owner].add(path)
    methods_by_file = {}
    for method, path in snapshot['native_methods'].items(): methods_by_file.setdefault(path, []).append(method)
    test_sources = {}
    for path in methods_by_file:
        owners = set()
        for token in set(swift_tokens((Path(root)/path).read_text())):
            owners.update(declarations.get(token, ()))
        test_sources[path] = sorted(owners)
    def words(name):
        return [part.rstrip('s') for part in re.findall(r'[A-Z]+(?=[A-Z][a-z]|$)|[A-Z]?[a-z]+|[0-9]+', name)]
    ui_names = {p:words(Path(p).stem) for p in methods_by_file if p.startswith('Tests/AppUITests/')}
    named_ui = {p:sorted(test for test,parts in ui_names.items() if len(words(Path(p).stem))>=2 and parts[:2]==words(Path(p).stem)[:2]) for p in sources}
    return {'dependents':{path:sorted(value) for path,value in direct.items()}, 'test_sources':test_sources, 'named_ui_groups':named_ui}


def current_ui_costs(root, snapshot):
    # Use the already source-bound current costs as data, never its old planner.
    contract = read_json(Path(root)/'tools/run138_editor_readiness_contract.json')
    profile = read_json(Path(root)/'tools/ui_duration_weights.json')
    measured = profile.get('method_seconds', {}); estimated = profile.get('estimated_method_seconds', {})
    rows = {}
    for key in ('product_ui_budget', 'club_leaderboard_member_budget'):
        rows.update(contract.get(key, {}).get('methods', {}))
    result = {}
    for method in snapshot['native_methods']:
        if not method.startswith('QuestifyUITests/'): continue
        short = method.split('/', 1)[1]; dotted = short.replace('/', '.', 1)
        values = [profile.get('unobserved_method_seconds', 60)]
        for table in (measured, estimated):
            value = table.get(short, table.get(dotted))
            if isinstance(value, dict): value = value.get('seconds')
            if value is not None: values.append(value)
        row = rows.get(dotted, rows.get(short))
        if row is not None: values.append(row['seconds'])
        require(all(type(v) in (int,float) and math.isfinite(v) and v > 0 for v in values), 'Invalid current UI cost input')
        value = max(values); require(value <= METHOD_LIMIT, 'Current UI method exceeds unchanged limit')
        result[method] = value
    return result


# Exact reviewed current localization diffs; any additional byte uses normal coverage.
REVIEWED_DISPLAY_IMPACTS = {'App/ProfileIdentityShareSection.swift': {'kind': 'reviewed-existing-localization-only', 'before_sha256': '0e9f595304cf3c5ab896f42e17742da4cb246cf7b652923e2502000f72f3b956', 'after_sha256': '5808a7e8755deeb447e1fb14d7a1c4fb5e31fc5efdbb10ed99189e7d624ae5f9', 'test_files': ['Tests/AppUnitTests/ProfileIdentityShareFlowTests.swift', 'Tests/CoreTests/ProfileIdentityShareCardTests.swift']}, 'App/RoamStampCameraView.swift': {'kind': 'reviewed-existing-localization-only', 'before_sha256': '20612c05eab78e8f012fc8b2a5793ead216032a5e312ea9281b1c7db64987a3e', 'after_sha256': '70d6784f4e303117fdbc82808f3d90dd299904916dbf3f7ff9e6bf9612b9b9e8', 'test_files': ['Tests/AppUnitTests/RoamStampFramingPixelTests.swift', 'Tests/CoreTests/RoamStampFramingTests.swift']}, 'App/RoamStampFramingCamera.swift': {'kind': 'reviewed-existing-localization-only', 'before_sha256': 'd1cf4948b6a69f0ba568a584cc873887d258465f5cff38984d4b6c05cae116d2', 'after_sha256': '4e3300239d976da0e52db389df6f2b17cd22bc0a70f1aec6094d62bf754ec529', 'test_files': ['Tests/AppUnitTests/RoamStampFramingPixelTests.swift', 'Tests/CoreTests/RoamStampFramingTests.swift']}, 'App/RoamShareAlbumGuideView.swift': {'kind': 'reviewed-existing-localization-only', 'before_sha256': '7bafc7d4480b2108de11cdc9428ae710241abef1ffbd40a89489f06200e02e4c', 'after_sha256': '479eb365f1482a21fabd3bebc5a4d554d6fe9e45ea849a2d8594b31efc8af1e1', 'test_files': ['Tests/AppUnitTests/RoamShareAlbumGuideFlowTests.swift', 'Tests/CoreTests/RoamShareAlbumGuideTests.swift']}, 'App/ClubEventCalendarView.swift': {'kind': 'reviewed-existing-localization-only', 'before_sha256': '3d8e8f6d9ac1d6852bfb4fd263d071065332ce8f6f48196a238df1104bc3d35f', 'after_sha256': '95798589dfc5e3c3e889d9eac82cde73a95107b1b38492ce07195dea577a4814', 'test_files': ['Tests/AppUnitTests/ClubEventCalendarReadTests.swift', 'Tests/AppUnitTests/ClubActivityOverviewReadTests.swift', 'Tests/CoreTests/ClubEventCalendarTests.swift']}}


def reviewed_display_impact(path, before, after):
    row=REVIEWED_DISPLAY_IMPACTS.get(path)
    return row if row is not None and digest(before)==row['before_sha256'] and digest(after)==row['after_sha256'] else None


def refresh(root, base, required_since=None):
    current = snapshot(root)
    prior_raw = subprocess.run(['git','-C',str(root),'show',base+':'+MANIFEST], capture_output=True)
    if prior_raw.returncode == 0:
        prior = json.loads(prior_raw.stdout, object_pairs_hook=unique)['snapshot']
    else:
        # Bootstrap compares declarations once against the immediate base. It
        # never imports/replays that version, and is not called by daily CI.
        prior = snapshot(root, base)
    smoke = ['QuestifyCoreTests/RegionalConfigurationTests/testFirstLaunchDefaultsAndExistingChoices',
             'QuestifyAppUnitTests/NormalHomeRuntimeRecoveryTests/testUnconfiguredLaunchNeverReadsVaultOrDispatches',
             'QuestifyUITests/EntryFlowTests/testSettingsReopensAfterRepeatedColdLaunch']
    require(set(smoke) <= set(current['native_methods']), 'Missing explicit current smoke identity')
    existing=read_json(Path(root)/MANIFEST) if (Path(root)/MANIFEST).is_file() else {}
    required_since=required_since or existing.get('required_since') or base
    require(re.fullmatch('[a-f0-9]{40}',required_since) is not None,'Exact initial required-coverage baseline required')
    changed_tests=set(git(root,'diff','--no-renames','--name-only',required_since,base).decode().splitlines())
    required=sorted(m for m,p in current['native_methods'].items() if p in changed_tests)
    deps=source_dependencies(root,current)
    relative='App/MerchantProjectsView.swift'
    original=git(root,'show',base+':'+relative)
    after=(Path(root)/relative).read_bytes()
    old=b'Button("merchant.done") { presentation.closeSummary(id: selected.id) }'
    new=old+b'.accessibilityIdentifier("merchant.projectSummary.close")'
    if original.count(old)==1 and original.replace(old,new,1)==after:
        deps['reviewed_impacts']={relative:{'kind':'existing-close-AX-identifier-only','before_sha256':digest(original),'after_sha256':digest(after),'test_files':['Tests/AppUnitTests/MerchantProjectWorkspaceEntryTests.swift','Tests/AppUITests/MerchantProjectBrowserFlowTests.swift']}}
    for path in REVIEWED_DISPLAY_IMPACTS:
        before=git(root,'show',base+':'+path);after=(Path(root)/path).read_bytes()
        row=reviewed_display_impact(path,before,after)
        if row is not None:deps.setdefault('reviewed_impacts',{})[path]=row
    data = {'version':1, 'required_current_methods':required, 'required_since':required_since, 'comparison_base':base, 'snapshot':current, 'audit':audit(prior,current), 'smoke':smoke,
            'source_dependencies':deps, 'ui_costs':current_ui_costs(root,current)}
    data['additional_base_test_reviews'] = existing.get('additional_base_test_reviews', {})
    additional_base_test_reviews(root, data)
    raw=encode(data)+b'\n'; require(len(raw)<=LIMIT,'Current manifest exceeds unchanged10MiB limit'); (Path(root)/MANIFEST).write_bytes(raw)
    return data


def additional_base_test_reviews(root, manifest):
    """Validate reviewed migrations for named Git bases, never a general waiver."""
    entries = manifest.get('additional_base_test_reviews', {})
    require(type(entries) is dict, 'Invalid additional-base test review map')
    current = manifest['snapshot']
    identities = dict(current['native_methods']); identities.update(current['portable_methods'])
    hashes = source_hashes(current)
    reviewed = {}
    for base, entry in entries.items():
        require(type(base) is str and re.fullmatch('[a-f0-9]{40}', base) is not None,
                'Additional test review requires exact base SHA')
        require(base != manifest['comparison_base'], 'Additional review cannot shadow comparison-base audit')
        require(type(entry) is dict and set(entry) == {'base_tree', 'retirements'},
                'Invalid additional-base test review fields')
        require(type(entry['base_tree']) is str and re.fullmatch('[a-f0-9]{40}', entry['base_tree']) is not None,
                'Additional test review requires exact base tree')
        require(git(root, 'cat-file', '-t', base).decode().strip() == 'commit', 'Review base is not a commit')
        require(git(root, 'rev-parse', base+'^{tree}').decode().strip() == entry['base_tree'], 'Review base tree differs')
        retirements = entry['retirements']
        require(type(retirements) is dict and bool(retirements), 'Empty additional-base migration review')
        reasons = {}
        for old, row in retirements.items():
            require(type(old) is str and old.strip() == old and old and old not in identities,
                    'Invalid or still-current reviewed old identity')
            require(type(row) is dict and set(row) == {'reason', 'replacements'}, 'Invalid migration review fields')
            require(type(row['reason']) is str and bool(row['reason'].strip()), 'Missing migration review reason')
            replacements = row['replacements']
            require(type(replacements) is list and bool(replacements), 'Missing current replacement test')
            seen = set()
            for replacement in replacements:
                require(type(replacement) is dict and set(replacement) == {'method', 'path', 'sha256'},
                        'Invalid replacement test binding fields')
                method, path, source_hash = replacement['method'], replacement['path'], replacement['sha256']
                require(type(method) is str and method in identities and method not in seen,
                        'Missing or duplicate current replacement identity')
                require(type(path) is str and identities[method] == path, 'Replacement test path differs')
                require(type(source_hash) is str and re.fullmatch('[a-f0-9]{64}', source_hash) is not None
                        and hashes.get(path) == source_hash, 'Replacement test source changed; review required')
                seen.add(method)
            reasons[old] = row['reason']
        reviewed[base] = reasons
    return reviewed


def retirement_review_for_base(root, manifest, base):
    reviewed = additional_base_test_reviews(root, manifest)
    if base == manifest['comparison_base']:
        return manifest['audit']['retirement_review']
    # No fallback to another base, even if old method names happen to coincide.
    return reviewed.get(base, {})


def verified_manifest(root=ROOT):
    data = read_json(Path(root) / MANIFEST)
    require(data.get('version') == 1 and type(data.get('version')) is int, 'Unknown current ledger version')
    actual = snapshot(root)
    require(data['snapshot'] == actual, 'Current source or test inventory changed without manifest audit')
    additional_base_test_reviews(root, data)
    return data


def audit_changed_test_declarations(root, base, current, retirement_review):
    """Audit just the real change against its immediate Git base, without import."""
    changed=git(root,'diff','--no-renames','--name-only',base,'HEAD').decode().splitlines()
    before=set(); after=set()
    for path in changed:
        target=next((target for folder,target in TARGETS.items() if path.startswith(folder+'/') and path.endswith('.swift')),None)
        portable=path.endswith('.py') and path.startswith(('tools/tests/test_','Tests/ContractChecks/test_'))
        if target is None and not portable: continue
        result=subprocess.run(['git','-C',str(root),'show',base+':'+path],capture_output=True)
        if result.returncode==0:
            before.update(swift_methods(result.stdout.decode(),target,{m.split('/')[1] for m in current['native_methods'] if m.startswith(target+'/')}) if target else python_methods(result.stdout.decode(),path))
        actual=Path(root)/path
        if actual.is_file(): after.update(swift_methods(actual.read_text(),target,{m.split('/')[1] for m in current['native_methods'] if m.startswith(target+'/')}) if target else python_methods(actual.read_text(),path))
    entire=set(current['native_methods'])|set(current['portable_methods'])
    removed=before-entire
    require(type(retirement_review) is dict and set(retirement_review)==removed and all(isinstance(v,str) and v.strip() for v in retirement_review.values()),'Actual diff removes tests without explicit exact retirement review')
    return {'added_in_changed_files':sorted(after-before),'removed':sorted(removed),'reviewed_retirements':retirement_review}


def make_plan(root, manifest, base, mode, environ=None):
    identity = source_identity(root, environ)
    require(re.fullmatch('[a-f0-9]{40}', base) is not None, 'Exact comparison base required')
    changed = git(root, 'diff', '--no-renames', '--name-only', base, identity['sha']).decode().splitlines()
    actual_audit=audit_changed_test_declarations(root,base,manifest['snapshot'],retirement_review_for_base(root,manifest,base))
    for path,row in manifest['source_dependencies'].get('reviewed_impacts',{}).items():
        if path not in changed: continue
        original=git(root,'show',base+':'+path); actual=(Path(root)/path).read_bytes()
        if row['kind']=='reviewed-existing-localization-only':
            require(reviewed_display_impact(path,original,actual)==row,'Reviewed locale diff changed');continue
        old=b'Button("merchant.done") { presentation.closeSummary(id: selected.id) }'; new=old+b'.accessibilityIdentifier("merchant.projectSummary.close")'
        require(path=='App/MerchantProjectsView.swift' and row['kind']=='existing-close-AX-identifier-only' and digest(original)==row['before_sha256'] and digest(actual)==row['after_sha256'] and original.count(old)==1 and original.replace(old,new,1)==actual,'Reviewed narrow impact no longer matches actual source change')
    # Git's 100% rename classification is additionally checked byte for byte.
    # Pure filename repairs keep the unchanged implementation's coverage.
    exact_renames={}
    for line in git(root,'diff','--name-status','--find-renames=100%',base,identity['sha']).decode().splitlines():
        fields=line.split('\t')
        if len(fields)==3 and fields[0]=='R100':
            before,after=fields[1:]
            if before.startswith(('App/','Core/')) and after.startswith(('App/','Core/')) and before.endswith('.swift') and after.endswith('.swift'):
                require(git(root,'show',base+':'+before)==(Path(root)/after).read_bytes(),'Non-identical source rename')
                exact_renames[before]=after
    registration_only = False
    if 'Questify.xcodeproj/project.pbxproj' in changed:
        registration_only=pbx_registration_only(git(root,'show',base+':Questify.xcodeproj/project.pbxproj').decode(),(Path(root)/'Questify.xcodeproj/project.pbxproj').read_text(),exact_renames)
    selection_paths=[p for p in changed if p not in exact_renames and p not in exact_renames.values()]
    groups = select(manifest['snapshot'], selection_paths, manifest['smoke']+manifest['required_current_methods'], mode, manifest['source_dependencies'],registration_only)
    shards = partition({method: manifest['ui_costs'][method] for method in groups['ui']})
    return {'version': 1, 'scope': 'full-current-regression' if mode == 'full' else 'current-related-and-smoke', 'identity': identity,
            'base': base, 'exact_source_renames':exact_renames, 'pbx_pure_registration':registration_only, 'ui_selection_policy':'Related explicit groups plus smoke; global/unmapped changes require full unit coverage, full UI is manual full mode', 'manifest_sha256': digest(encode(manifest)), 'changed_paths': changed, 'groups': groups, 'ui_shards': shards,
            'complete_native_ledger_count': len(manifest['snapshot']['native_methods']), 'device_only_not_run': device_only_not_run(manifest['snapshot']), 'execution_platforms': ['macos-host', 'ios-simulator'], 'test_audit': actual_audit,
            'limits': {'worker_seconds': 2700, 'finalization_reserve_seconds': 240, 'macos_parallel': 20, 'method_seconds': 900, 'ui_shard_seconds': 1500}}


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['check', 'plan', 'refresh']); parser.add_argument('--root', type=Path, default=ROOT); parser.add_argument('--base'); parser.add_argument('--required-since'); parser.add_argument('--mode', choices=['related', 'full'], default='related'); parser.add_argument('--output', type=Path); args = parser.parse_args()
    if args.action == 'refresh':
        require(args.base is not None, 'Refresh requires exact comparison base'); data=refresh(args.root,args.base,args.required_since); print(json.dumps({'status':'CURRENT_LEDGER_WRITTEN','bytes':len(encode(data)),'added':len(data['audit']['added']),'removed':len(data['audit']['removed'])})); return
    manifest = verified_manifest(args.root)
    if args.action == 'check':
        print(json.dumps({'status': 'PASS_CURRENT_SOURCE_LEDGER', 'sources': len(manifest['snapshot']['sources']), 'native_methods': len(manifest['snapshot']['native_methods']), 'portable_methods': len(manifest['snapshot']['portable_methods'])})); return
    require(args.base and args.output, 'Plan needs exact base and output')
    plan = make_plan(args.root, manifest, args.base, args.mode); args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_bytes(encode(plan) + b'\n'); print(json.dumps({'status': 'PLAN_ONLY', 'selected': {key: len(value) for key, value in plan['groups'].items()}, 'ui_shards': len(plan['ui_shards'])}))


if __name__ == '__main__': main()
