"""Exact pre-creator profile and full-source projection for historical assertions."""
from tools.tests.club_parity_budget_history import before_club_parity, historical_pre_club_source
from tools.tests.player_map_history_budget_history import validated_pre_run129_directory
from copy import deepcopy
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
BASELINE_PROFILE_SHA256 = 'f4acbff048c8b28b7097de229371a5e3093213cb06b9e32df33c62016ef21d10'
CURRENT_PROFILE_SHA256 = '2c14c8379bec9b2a4a0c00127bc0467243140a1dac630422e45641d488d7fb7c'
SOURCE_INDEX_SHA256 = '2ff025a7fdea1cde71f91f6323baff5477f172e768ddd86282866fd37a5831bb'


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def source_index():
    data = (ROOT / 'tools/tests/fixtures/creator_pending/source-index.json').read_bytes()
    assert hashlib.sha256(data).hexdigest() == SOURCE_INDEX_SHA256
    return json.loads(data)


def before_creator_pending(profile):
    profile = before_club_parity(profile)
    result = deepcopy(profile)
    plan = result['planning_budget'].get('reviewed_creator_pending_replan')
    if plan is None:
        assert not any(row.get('source') == 'reviewedCreatorNative16AuthoringR4'
                       for row in result['estimate_provenance']['methods'])
        return result
    assert canonical(profile) == CURRENT_PROFILE_SHA256, 'Unreviewed creator planning profile'
    result['planning_budget'].pop('reviewed_creator_pending_replan')
    for key in plan['new_methods']:
        result['estimated_method_seconds'].pop(key)
    result['estimate_provenance']['methods'] = [
        row for row in result['estimate_provenance']['methods']
        if row['method'] not in plan['new_methods']]
    assert canonical(result) == BASELINE_PROFILE_SHA256, 'Published 707-method union not exactly restored'
    return result


def materialize_pre_creator_ui(directory):
    """Use unchanged real discovery on every pinned complete historical UI file."""
    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    with validated_pre_run129_directory(ROOT) as current:
        for row in source_index()['baseline_ui_sources']:
            data = historical_pre_club_source(current / Path(row['path']).name).read_bytes()
            assert hashlib.sha256(data).hexdigest() == row['sha256'], row['path']
            (destination / Path(row['path']).name).write_bytes(data)
    return destination
