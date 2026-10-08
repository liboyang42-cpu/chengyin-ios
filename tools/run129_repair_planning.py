"""Fail-closed current repair layer over an immutable, independently replayed baseline.

Historical source projection is exclusively for computing the retained old cost.
Every byte in the actual current UI inventory is validated first, and every whole
method is mapped once. The five proposed 930-second repairs are not in this layer.
"""
from collections import defaultdict
from copy import deepcopy
import hashlib
import importlib.util
from importlib.machinery import SourceFileLoader
import json
from pathlib import Path
import re
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tools/tests/fixtures/run129_repairs'
CONTRACT_SHA256 = 'e25a074752564213dc99b553ad26029a126c62466ba857fd22b87851fb08834a'
INDEX_SHA256 = '1dbb5d5f38189ca6d05caa726e9f543b6991a72e39b6b023641fa5a0ee25cce5'
CURRENT_PROFILE_SHA256 = '207456fac995fe820dae2c618286eef75a3144f8e48524e3c8234645bc0f1611'
BASELINE_PROFILE_SHA256 = '4114146aa1418c14322a8c94a38d87414822862b069aa62272d6918aec073273'
PLAN = 'reviewed_run129_repairs'
NEW_CLASSES = {'ProjectSubmissionAcknowledgmentChineseFlowTests', 'ApprovedReleasePreparationChineseFlowTests'}
PATTERN = r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def pinned_json(path, expected):
    raw = Path(path).read_bytes()
    if digest(raw) != expected:
        raise ValueError('Unreviewed run129 repair identity: ' + str(path))
    return json.loads(raw)


def source_index():
    return pinned_json(FIXTURES / 'source-index.json', INDEX_SHA256)


def before_run129_repairs(profile):
    try:
        from run129_late_readiness import previous_profile
    except ModuleNotFoundError:
        from tools.run129_late_readiness import previous_profile
    result = previous_profile(profile)
    plan = result.get('planning_budget', {}).get(PLAN)
    if plan is None:
        if any(key.startswith(tuple(name+'.' for name in NEW_CLASSES)) for key in result.get('estimated_method_seconds', {})):
            raise ValueError('Missing run129 repair planning identity')
        return result
    if canonical(result) != CURRENT_PROFILE_SHA256:
        raise ValueError('Unreviewed current repair profile')
    result['planning_budget'].pop(PLAN)
    if canonical(result) != BASELINE_PROFILE_SHA256:
        raise ValueError('Prior 78-shard evidence not restored exactly')
    return result


def historical_source(path):
    """Only exact reviewed current bytes may project to pinned old source bytes."""
    try:
        from run129_late_readiness import previous_source
    except ModuleNotFoundError:
        from tools.run129_late_readiness import previous_source
    path = previous_source(path)
    index = source_index()
    if path.parent.name == 'AppUITests':
        relative = 'Tests/AppUITests/' + path.name
        row = index['historical_ui_sources'].get(relative)
        if row is None:
            raise ValueError('No historical source exists for this new wrapper')
        raw = path.read_bytes()
        current = index['current_ui_sources'].get(relative, {}).get('sha256')
        if digest(raw) not in {row['sha256'], current}:
            raise ValueError('Unknown current UI cannot be projected to history')
        if digest(raw) == row['sha256']:
            return path
        if 'historical_file' not in row:
            raise ValueError('Changed source has no reviewed exact inverse')
        file = FIXTURES / row['historical_file']
        if digest(file.read_bytes()) != row['sha256']:
            raise ValueError('Historical source snapshot changed')
        return file
    return path


def materialize_baseline_ui(directory, current_directory=None):
    destination = Path(directory); destination.mkdir(parents=True, exist_ok=True)
    current = Path(current_directory or ROOT / 'Tests/AppUITests')
    for relative, row in source_index()['historical_ui_sources'].items():
        raw = historical_source(current / Path(relative).name).read_bytes()
        if digest(raw) != row['sha256']:
            raise ValueError('Incomplete historical projection')
        (destination / Path(relative).name).write_bytes(raw)
    return destination


def frozen_player_context():
    from types import SimpleNamespace
    lifetime = tempfile.TemporaryDirectory(prefix='frozen-run129-player-')
    root = Path(lifetime.name)
    materialize_baseline_ui(root / 'Tests/AppUITests')
    index = source_index()
    for relative, row in index['historical_files'].items():
        raw = (FIXTURES / row['historical_file']).read_bytes()
        if digest(raw) != row['sha256']:raise ValueError('Historical tooling snapshot changed')
        p=root/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
    for relative, expected in index['baseline_other_files'].items():
        raw=(ROOT/relative).read_bytes()
        if digest(raw)!=expected:raise ValueError('Protected previous-layer fixture changed')
        p=root/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
    def load(relative,name):
        loader=SourceFileLoader(name,str(root/relative))
        module=importlib.util.module_from_spec(importlib.util.spec_from_loader(name,loader))
        with patch.object(sys,'path',[str(ROOT/'tools')]+sys.path),patch.object(sys,'dont_write_bytecode',True):loader.exec_module(module)
        return module
    return SimpleNamespace(root=root,runner=load('tools/run_ui_shard.py','frozen_before_run129_runner'),gates=load('tools/ci_gates.py','frozen_before_run129_gates'),lifetime=lifetime)


def repair_weights(directory, profile_path):
    """Return None only for actual old/small synthetic inventories, never current repairs."""
    directory=Path(directory);profile=json.loads(Path(profile_path).read_text())
    names={p.stem for p in directory.glob('*.swift')}
    relevant=(directory.resolve()==(ROOT/'Tests/AppUITests').resolve() or bool(names & NEW_CLASSES) or PLAN in profile.get('planning_budget',{}))
    if not relevant:return None
    contract=pinned_json(ROOT/'tools/run129_repair_planning_contract.json',CONTRACT_SHA256)
    index=source_index()
    if PLAN not in profile.get('planning_budget',{}):raise ValueError('Current source requires the repair plan')
    prior=before_run129_repairs(profile)
    actual={}
    for path in directory.glob('*.swift'):
        relative='Tests/AppUITests/'+path.name
        if index['current_ui_sources'].get(relative, {}).get('sha256')!=digest(path.read_bytes()):raise ValueError('Changed or unknown current UI source')
        text=path.read_text();methods=re.findall(r'\bfunc\s+(test\w+)\s*\(',text)
        if not methods:continue
        classes=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',text)
        if len(classes)!=1 or len(set(methods))!=len(methods):raise ValueError('Invalid current whole-method inventory')
        for method in methods:
            key=classes[0]+'.'+method
            if key in actual:raise ValueError('Repeated current complete method')
            actual[key]=(path,text)
    if {p.name for p in directory.glob('*.swift')}!={Path(p).name for p in index['current_ui_sources']}:raise ValueError('Missing current UI file')
    if sorted(actual)!=contract['current_inventory']:raise ValueError('Current methods do not match reviewed exact inventory')
    aliases=contract['aliases']
    if sorted(aliases.get(k,k) for k in actual)!=contract['historical_inventory']:raise ValueError('Historical identity lost or mapped twice')
    for key,row in contract['required_floors'].items():
        path,text=actual[key];method=key.split('.')[1]
        declarations={name:body for body,name in re.findall(PATTERN,text)}
        non=re.sub(r'(?m)^[ \t]*\n','',re.sub(PATTERN,'',text))
        if (digest(path.read_bytes())!=row['test_file_sha256'] or digest(declarations[method].encode())!=row['declaration_sha256'] or digest(non.encode())!=row['all_non_test_source_sha256']):raise ValueError('Current method/helper changed')
        for rel,expected in row['shared_helper_source_sha256'].items():
            if digest((directory/Path(rel).name).read_bytes())!=expected:raise ValueError('Shared helper changed')
        if not row['historical_seconds']<=row['seconds']<=900 or row['measured'] is not False:raise ValueError('Invalid complete repair allowance')
    with tempfile.TemporaryDirectory(prefix='run129-source-cost-') as temporary:
        temp=Path(temporary);old_ui=materialize_baseline_ui(temp/'Tests/AppUITests',directory)
        baseline=FIXTURES/'tools__run_ui_shard.py.txt'
        expected=index['historical_files']['tools/run_ui_shard.py']['sha256']
        if digest(baseline.read_bytes())!=expected:raise ValueError('Unreviewed frozen runner')
        loader=SourceFileLoader('run129_prior_cost_runner',str(baseline));module=importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name,loader))
        with patch.object(sys,'path',[str(ROOT/'tools')]+sys.path),patch.object(sys,'dont_write_bytecode',True):loader.exec_module(module)
        module.ROOT=ROOT
        for name in ['CLUB_PARITY','STORY_TEMPLATE','PLAYER_MAP_HISTORY']:setattr(module,name+'_CONTRACT_PATH',ROOT/('tools/'+name.lower()+'_planning_contract.json'))
        prior_path=temp/'profile.json';prior_path.write_text(json.dumps(prior))
        retained_class_costs=module.measured_weights(old_ui,prior_path)
        historical_order=[]
        for path in sorted(old_ui.glob("*.swift")):
            text=path.read_text();methods=re.findall(r"\bfunc\s+(test\w+)\s*\(",text)
            if methods:
                name=re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b",text)[0]
                historical_order.extend(name+"."+method for method in methods)
    required={}
    for name in ['club_parity','story_template','player_map_history']:required.update(json.loads((ROOT/f'tools/{name}_planning_contract.json').read_text())['required_floors'])
    old_costs={key:max(prior['method_seconds'].get(key,prior['estimated_method_seconds'].get(key,prior['unobserved_method_seconds'])),prior.get('method_planning_floors',{}).get(key,{}).get('seconds',0),required.get(key,{}).get('seconds',0)) for key in contract['historical_inventory']}
    grouped=defaultdict(list)
    for key in historical_order:grouped[key.split('.')[0]].append(old_costs[key])
    grouped={key:sum(values) for key,values in grouped.items()}
    if grouped!=retained_class_costs:raise ValueError('Per-method reconstruction differs from exact historical runner')
    result=defaultdict(list)
    for key in actual:
        old=aliases.get(key,key);row=contract['required_floors'].get(key)
        if row and row['historical_seconds']!=old_costs[old]:raise ValueError('Historical whole-method cost changed')
        result[key.split('.')[0]].append(max(old_costs[old],row['seconds'] if row else 0))
    return {key:sum(values) for key,values in result.items()}
