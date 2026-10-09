from tools.tests.story_media_budget_history import before_story_media, historical_pre_media_ui_source
from tools.tests.player_map_history_budget_history import validated_pre_run129_directory
"""Immutable 5e2f9c12 planning/source projection for historical tests only."""
from copy import deepcopy
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tools/tests/fixtures/pre_reviewed_features'
BASELINE_PROFILE_SHA256 = 'cec85861477b17cb8942744516eacb4a2c6deccb3b81ee904b7c20722244e8eb'
CURRENT_PROFILE_SHA256 = '242c561c0efd4bb4b7d084ac552df42cd29f34c47e89d2773a6fb6c5169d77d1'
SOURCE_INDEX_SHA256 = '817f1803249e82c5eaad218699367ea2dd7cf8b9e9247e6baf6fcc0042f1e027'
HISTORICAL_SHARD_COUNT = 36

def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def source_index():
    data = (FIXTURES / 'source-index.json').read_bytes()
    assert hashlib.sha256(data).hexdigest() == SOURCE_INDEX_SHA256
    return json.loads(data)

def before_reviewed_features(profile):
    profile = before_story_media(profile)
    result = deepcopy(profile)
    if 'reviewed_native_features_replan' not in result['planning_budget']:
        assert not any(k.startswith('reviewed_features_previous_') for k in result)
        return result
    assert canonical(profile) == CURRENT_PROFILE_SHA256, 'Unreviewed current feature profile'
    result['planning_budget'].pop('reviewed_native_features_replan')
    result['method_seconds'] = result.pop('reviewed_features_previous_method_seconds')
    result['estimated_method_seconds'] = result.pop('reviewed_features_previous_estimated_method_seconds')
    result['estimate_provenance']['methods'] = result.pop('reviewed_features_previous_estimate_provenance')
    assert canonical(result) == BASELINE_PROFILE_SHA256, 'Published 5e2f9c12 profile not exactly restored'
    return result

def historical_pre_feature_ui_source(path):
    path = historical_pre_media_ui_source(Path(path))
    case = path.name.removesuffix('.swift.txt') if path.name.endswith('.swift.txt') else path.stem
    expected = source_index()['changed_source_sha256'].get(case)
    if expected is None:
        return path
    result = FIXTURES / (case + '.swift.txt')
    assert hashlib.sha256(result.read_bytes()).hexdigest() == expected
    return result

def historical_pre_feature_ui_sources(directory):
    directory = Path(directory)
    return [historical_pre_feature_ui_source(directory / name)
            for name in source_index()['baseline_ui_filenames']]

def materialize_historical_pre_feature_ui(directory):
    """Use actual unmodified discovery against pinned full historical source files."""
    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    with validated_pre_run129_directory(ROOT) as current:
        for name in source_index()['baseline_ui_filenames']:
            source = historical_pre_feature_ui_source(current / name)
            (destination / name).write_bytes(source.read_bytes())
    return destination

def historical_pre_feature_workflow():
    source = FIXTURES / 'native-ios.yml.txt'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_index()['workflow_sha256']
    return source
