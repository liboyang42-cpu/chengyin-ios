from tools.tests.story_media_budget_history import historical_pre_media_ui_source
from tools.tests.combined_native_budget_history import before_combined
"""Exact 9581 planning/source projection for tests of earlier reviewed batches."""
from copy import deepcopy
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tools/tests/fixtures/map_alternative_list_r2'
BASELINE_PROFILE_SHA256 = '242c561c0efd4bb4b7d084ac552df42cd29f34c47e89d2773a6fb6c5169d77d1'
CURRENT_PROFILE_SHA256 = '9ac2fb0a92553a2705d278711b935779f8cf6469aa57d2361da338e82d36846e'
SOURCE_INDEX_SHA256 = '57cc132a3a468c2204593c0ae101375ad9c748257f4f00a6aa19fb896b86f05a'
HISTORICAL_SHARD_COUNT = 38


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def source_index():
    data = (FIXTURES / 'integration-source-index.json').read_bytes()
    assert hashlib.sha256(data).hexdigest() == SOURCE_INDEX_SHA256
    return json.loads(data)


def before_reviewed_map(profile):
    profile = before_combined(profile, 'map')
    result = deepcopy(profile)
    plan = result['planning_budget'].get('reviewed_map_alternative_list_replan')
    if plan is None:
        assert not any(row.get('source') == 'reviewedMapAlternativeListR2'
                       for row in result['estimate_provenance']['methods'])
        return result
    assert canonical(profile) == CURRENT_PROFILE_SHA256, 'Unreviewed map planning profile'
    result['planning_budget'].pop('reviewed_map_alternative_list_replan')
    for key in plan['new_methods']:
        result['estimated_method_seconds'].pop(key)
    result['estimate_provenance']['methods'] = [
        row for row in result['estimate_provenance']['methods']
        if row['method'] not in plan['new_methods']]
    assert canonical(result) == BASELINE_PROFILE_SHA256, 'Published 9581 profile not exactly restored'
    return result


def materialize_historical_pre_map_ui(directory):
    """Keep actual complete published source files and unmodified test discovery."""
    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    for row in source_index()['baseline_ui_sources']:
        name, expected = row['path'], row['sha256']
        data = historical_pre_media_ui_source(ROOT / 'Tests/AppUITests' / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == expected, 'Published UI source changed: ' + name
        (destination / name).write_bytes(data)
    return destination


def historical_pre_map_workflow():
    source = FIXTURES / 'native-ios.yml.txt'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_index()['historical_workflow_sha256']
    return source
