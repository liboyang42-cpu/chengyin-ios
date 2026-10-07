"""Exact source/profile projection of the frozen 712-method club R2 layer."""
from copy import deepcopy
import hashlib
from importlib.machinery import SourceFileLoader
import importlib.util
import json
from pathlib import Path
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tools/tests/fixtures/story_template'
BASELINE_PROFILE_SHA256 = 'bc3eacc024dcaf97898192f26cde9b4479bce72697339ccd33ca1e7a5a91d2bb'
CURRENT_PROFILE_SHA256 = '59b68999329cc14c609d7e7cf2f7f617fd7b9e8060b577b09827882927c98511'
SOURCE_INDEX_SHA256 = 'dea758b732c1aa14af5cc8bbff677e5fcb7abd1b5c74220ebf7dee4667232634'
PLAN = 'reviewed_story_template_replan'
MARKER = 'storyTemplateWholeMethodCandidate20261007'


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def source_index():
    data = (FIXTURES / 'source-index.json').read_bytes()
    assert hashlib.sha256(data).hexdigest() == SOURCE_INDEX_SHA256, 'Unreviewed pre-story source index'
    return json.loads(data)


def before_story_template(profile):
    """Remove only the exact reviewed additive layer, never unknown mutations."""
    result = deepcopy(profile)
    plan = result.get('planning_budget', {}).get(PLAN)
    if plan is None:
        assert not any(key.startswith('ProjectStoryTemplate') for key in result.get('estimated_method_seconds', {})), 'Missing story-template plan for estimates'
        assert not any(row.get('source') == MARKER or row.get('method', '').startswith('ProjectStoryTemplate') for row in result.get('estimate_provenance', {}).get('methods', [])), 'Missing story-template provenance identity'
        return result
    assert canonical(profile) == CURRENT_PROFILE_SHA256, 'Unreviewed story-template planning profile'
    result['planning_budget'].pop(PLAN)
    for key in plan['new_methods']:
        result['estimated_method_seconds'].pop(key)
    result['estimate_provenance']['methods'] = [row for row in result['estimate_provenance']['methods'] if row['method'] not in plan['new_methods']]
    assert canonical(result) == BASELINE_PROFILE_SHA256, 'Frozen club R2 profile not exactly restored'
    return result


def historical_pre_story_source(path):
    path = Path(path)
    for original, row in source_index()['historical_sources'].items():
        if path.name.removesuffix('.txt') == Path(original).name:
            candidate = FIXTURES / row['historical_file']
            assert hashlib.sha256(candidate.read_bytes()).hexdigest() == row['sha256'], original
            return candidate
    return path


def materialize_pre_story_ui(directory):
    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    rows = source_index()['baseline_ui_sources']
    allowed = {Path(row['path']).name for row in rows}
    assert not {p.name for p in destination.glob('*.swift')} - allowed, 'Foreign source in pre-story projection'
    for row in rows:
        data = (ROOT / row['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == row['sha256'], row['path']
        (destination / Path(row['path']).name).write_bytes(data)
    return destination


def historical_pre_story_module(path, name):
    source = historical_pre_story_source(path)
    assert source.parent == FIXTURES and source.name in ('run_ui_shard.py.txt', 'ci_gates.py.txt')
    loader = SourceFileLoader(name, str(source))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    with patch.object(sys, 'path', [str(ROOT / 'tools')] + sys.path), patch.object(sys, 'dont_write_bytecode', True):
        loader.exec_module(module)
    module.ROOT = ROOT
    if hasattr(module, 'CLUB_PARITY_CONTRACT_PATH'):
        module.CLUB_PARITY_CONTRACT_PATH = ROOT / 'tools/club_parity_planning_contract.json'
    return module
