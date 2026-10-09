"""Exact pre-club profile/source projection for historical assertions only.

Live planning and discovery continue to use every current test and its complete
cost. Historical callers first undo the reviewed club layer, then use pinned
full source files; no new method can enter a pre-club inventory.
"""
from tools.tests.story_template_budget_history import before_story_template
from tools.tests.player_map_history_budget_history import validated_pre_run129_directory
from tools.run129_repair_planning import historical_source as pre_run129_source
from copy import deepcopy
import hashlib
from importlib.machinery import SourceFileLoader
import importlib.util
import json
from pathlib import Path
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tools/tests/fixtures/club_parity'
BASELINE_PROFILE_SHA256 = '2c14c8379bec9b2a4a0c00127bc0467243140a1dac630422e45641d488d7fb7c'
CURRENT_PROFILE_SHA256 = 'bc3eacc024dcaf97898192f26cde9b4479bce72697339ccd33ca1e7a5a91d2bb'
SOURCE_INDEX_SHA256 = 'cfb64b7440c4ef64b20e960f4cdbd8fc7ce4d6d3713bb9f9aff470d08c0bf32c'
HISTORICAL_SHARD_COUNT = 65
NEW_CLASS = 'ClubProfileScopeFlowTests'
PROVENANCE_SOURCE = 'parentApprovedClubParityWholeMethodPlanning20261006'


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def source_index():
    data = (FIXTURES / 'source-index.json').read_bytes()
    assert hashlib.sha256(data).hexdigest() == SOURCE_INDEX_SHA256, 'Unreviewed pre-club source index'
    return json.loads(data)


def before_club_parity(profile):
    """Reverse only the reviewed club layer, fail closed on partial/corrupt layers."""
    profile = before_story_template(profile)
    result = deepcopy(profile)
    plan = result['planning_budget'].get('reviewed_club_parity_replan')
    if plan is None:
        assert not any(key.startswith('club_parity_previous_') for key in result), 'Missing club planning identity'
        assert 'method_planning_floors' not in result, 'Missing club planning identity for floor'
        assert not any(key.startswith(NEW_CLASS + '.') for key in result['estimated_method_seconds']), 'Missing club planning identity for new estimates'
        assert not any(row.get('source') == PROVENANCE_SOURCE or row.get('method', '').startswith(NEW_CLASS + '.')
                       for row in result['estimate_provenance']['methods']), 'Missing club planning identity for provenance'
        return result
    assert canonical(profile) == CURRENT_PROFILE_SHA256, 'Unreviewed club parity planning profile'
    result['planning_budget'].pop('reviewed_club_parity_replan')
    for method in plan['new_methods']:
        result['estimated_method_seconds'].pop(method)
    result.pop('method_planning_floors')
    result['estimate_provenance']['methods'] = result.pop('club_parity_previous_estimate_provenance')
    assert canonical(result) == BASELINE_PROFILE_SHA256, 'Published 710-method profile not exactly restored'
    return result


def historical_pre_club_source(path):
    """Return hash-pinned complete pre-club bytes for the files changed here."""
    path = Path(path)
    name = path.name.removesuffix('.txt')
    assert name != NEW_CLASS + '.swift', 'No pre-club source exists for the new UI class'
    for original, row in source_index()['historical_sources'].items():
        if name == Path(original).name:
            source = FIXTURES / row['historical_file']
            assert hashlib.sha256(source.read_bytes()).hexdigest() == row['sha256'], original
            return source
    return pre_run129_source(path)


def materialize_pre_club_ui(directory):
    """Materialize the complete, fixed 710-method/146-class historical inventory."""
    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    rows = source_index()['baseline_ui_sources']
    allowed = {Path(row['path']).name for row in rows}
    assert not {path.name for path in destination.glob('*.swift')} - allowed, 'Foreign UI source in pre-club destination'
    with validated_pre_run129_directory(ROOT) as current:
        for row in rows:
            data = historical_pre_club_source(current / Path(row['path']).name).read_bytes()
            assert hashlib.sha256(data).hexdigest() == row['sha256'], row['path']
            (destination / Path(row['path']).name).write_bytes(data)
    return destination


def historical_pre_club_module(path, name):
    """Load the original runner/gate, including its frozen 65-shard semantics."""
    source = historical_pre_club_source(path)
    assert source.parent == FIXTURES and source.name in ('run_ui_shard.py.txt', 'ci_gates.py.txt')
    loader = SourceFileLoader(name, str(source))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    with patch.object(sys, 'path', [str(ROOT / 'tools')] + sys.path), patch.object(sys, 'dont_write_bytecode', True):
        loader.exec_module(module)
    return module
