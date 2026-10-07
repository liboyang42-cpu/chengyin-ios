"""Exact 73-shard profile/source projection, never a live inventory filter."""
from tools.run129_repair_planning import before_run129_repairs, historical_source as pre_run129_source
from copy import deepcopy
from importlib.machinery import SourceFileLoader
import importlib.util
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tools/tests/fixtures/player_map_history'
BASELINE_PROFILE_SHA256 = '59b68999329cc14c609d7e7cf2f7f617fd7b9e8060b577b09827882927c98511'
CURRENT_PROFILE_SHA256 = '4114146aa1418c14322a8c94a38d87414822862b069aa62272d6918aec073273'
SOURCE_INDEX_SHA256 = '0246c8abcac1d1e45436f504b6a21221196b920bf29d60fb26a7015191184640'
PLAN = 'reviewed_player_map_history_replan'
MARKER = 'playerRouteHistoryWholeMethodReview20261007'

def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def source_index():
    data = (FIXTURES / 'source-index.json').read_bytes()
    assert hashlib.sha256(data).hexdigest() == SOURCE_INDEX_SHA256, 'Unreviewed pre-player-map history index'
    return json.loads(data)

def before_player_map_history(profile):
    profile = before_run129_repairs(profile)
    result = deepcopy(profile)
    plan = result.get('planning_budget', {}).get(PLAN)
    prefixes = ('PlayRouteMap', 'PlayBranchHistory')
    if plan is None:
        assert not any(key.startswith(prefixes) for key in result.get('estimated_method_seconds', {})), 'Missing player-map/history plan'
        assert not any(row.get('source') == MARKER or row.get('method', '').startswith(prefixes) for row in result.get('estimate_provenance', {}).get('methods', [])), 'Missing player-map/history provenance identity'
        return result
    assert canonical(profile) == CURRENT_PROFILE_SHA256, 'Unreviewed player-map/history planning profile'
    result['planning_budget'].pop(PLAN)
    for key in plan['new_methods']:
        result['estimated_method_seconds'].pop(key)
    result['estimate_provenance']['methods'] = [row for row in result['estimate_provenance']['methods'] if row['method'] not in plan['new_methods']]
    assert canonical(result) == BASELINE_PROFILE_SHA256, 'Frozen 73-shard profile not exactly restored'
    return result

def historical_player_source(path):
    path = Path(path)
    for original, row in source_index()['historical_files'].items():
        if path.name.removesuffix('.txt') == Path(original).name:
            file = FIXTURES / row['historical_file']
            assert hashlib.sha256(file.read_bytes()).hexdigest() == row['sha256'], original
            return file
    return path

def materialize_pre_player_ui(directory):
    target = Path(directory)
    target.mkdir(parents=True, exist_ok=True)
    rows = source_index()['baseline_ui_sources']
    allowed = {Path(row['path']).name for row in rows}
    assert not {p.name for p in target.glob('*.swift')} - allowed, 'Foreign UI in pre-player projection'
    for row in rows:
        data = pre_run129_source(ROOT / row['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == row['sha256'], row['path']
        (target / Path(row['path']).name).write_bytes(data)
    return target

def frozen_story_context():
    """Run the original 20 story-budget cases on the exact retained 73-shard source."""
    lifetime = tempfile.TemporaryDirectory(prefix='frozen-story-budget-')
    root = Path(lifetime.name)
    materialize_pre_player_ui(root / 'Tests/AppUITests')
    for original, row in source_index()['historical_files'].items():
        data = (FIXTURES / row['historical_file']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == row['sha256'], original
        output = root / original
        output.parent.mkdir(parents=True, exist_ok=True); output.write_bytes(data)
    for relative, expected in source_index()['contract_files'].items():
        data = (ROOT / relative).read_bytes()
        assert hashlib.sha256(data).hexdigest() == expected, relative
        output = root / relative; output.parent.mkdir(parents=True, exist_ok=True); output.write_bytes(data)
    def load(relative, name):
        loader = SourceFileLoader(name, str(root / relative))
        module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
        with patch.object(sys, 'path', [str(ROOT / 'tools')] + sys.path), patch.object(sys, 'dont_write_bytecode', True):
            loader.exec_module(module)
        return module
    return SimpleNamespace(root=root, runner=load('tools/run_ui_shard.py','exact_73_story_runner'), gates=load('tools/ci_gates.py','exact_73_story_gates'), lifetime=lifetime)
