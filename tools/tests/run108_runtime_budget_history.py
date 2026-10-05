"""Reconstruct the frozen run108 timing profile for historical tests only.

Live CI always uses the current full profile. This helper reverses exactly the
six declared complete-method replacements, preserving every earlier assertion.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re

HISTORICAL_SHARD_COUNT = 23
BASELINE_SHA256 = '6b4124953309dd0ba7a2abd8382d1fd4370cb3ff38d831a4509daf2b295f25a8'


def historical_profile(profile):
    result = deepcopy(profile)
    replan = result['planning_budget'].pop('run108_runtime_replan')
    methods = set(replan['expanded_methods'])
    records = result['estimate_provenance']['methods']
    current = records[-replan['new_provenance_record_count']:]
    if {record['method'] for record in current} != methods:
        raise AssertionError('Ambiguous runtime replacement provenance')
    del records[-replan['new_provenance_record_count']:]
    for previous in result.pop('superseded_estimate_provenance'):
        records.insert(previous['index'], previous['record'])
    for method, previous in replan['previous_effective_records'].items():
        for key, field in [('method_seconds', 'observation'), ('estimated_method_seconds', 'estimate')]:
            if previous[field] is None:
                result[key].pop(method, None)
            else:
                result[key][method] = previous[field]
    result['superseded_method_observations'] = [record for record in result['superseded_method_observations']
        if record.get('superseded_by') != 'run108_runtime_replan']
    digest = hashlib.sha256(json.dumps(result, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if digest != BASELINE_SHA256 or digest != replan['baseline_canonical_profile_sha256']:
        raise AssertionError('Historical profile no longer reconstructs exactly')
    return result


def historical_costs(directory, profile_path):
    profile = historical_profile(json.loads(Path(profile_path).read_text()))
    result = {}
    for path in sorted(Path(directory).glob('*.swift')):
        source = path.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        if not methods:
            continue
        case = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)[0]
        result[case] = sum(profile['method_seconds'].get(case + '.' + method,
            profile['estimated_method_seconds'].get(case + '.' + method, profile['unobserved_method_seconds']))
            for method in methods)
    return result
