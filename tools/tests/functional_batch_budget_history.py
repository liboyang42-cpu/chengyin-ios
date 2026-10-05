from tools.tests.run109_amendment_budget_history import before_run109_amendments
from tools.tests.run109_amendment_budget_history import historical_ui_sources
"""Reconstruct the published run109 profile/inventory for historical tests only.

The runner uses the current full source inventory. Historical assertions use this
exact reversible projection rather than changing earlier plans or omitting tests.
"""
from copy import deepcopy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re

BASELINE_PROFILE_SHA256 = '96f448d7b88761b70bc0829d9d72ff59768814fab3aad26fa0948f683d3e8682'
HISTORICAL_SHARD_COUNT = 23
ROOT = Path(__file__).resolve().parents[2]


def before_functional_batch(profile):
    result = before_run109_amendments(profile)
    if 'reviewed_native_functional_replan' not in result['planning_budget']:
        digest = hashlib.sha256(json.dumps(result, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        if digest != BASELINE_PROFILE_SHA256:
            raise AssertionError('Not the verified published run109 profile')
        return result
    plan = result['planning_budget'].pop('reviewed_native_functional_replan')
    records = result['estimate_provenance']['methods']
    count = plan['provenance_record_count']
    if {record['method'] for record in records[-count:]} != set(plan['expanded_or_reestimated_methods']):
        raise AssertionError('Ambiguous functional-batch estimate provenance')
    del records[-count:]
    for previous in result.pop('functional_batch_superseded_estimates'):
        records.insert(previous['index'], previous['record'])
    for method, values in plan['previous_effective_records'].items():
        for key, field in [('method_seconds', 'observation'), ('estimated_method_seconds', 'estimate')]:
            if values[field] is None:
                result[key].pop(method, None)
            else:
                result[key][method] = values[field]
    result['superseded_method_observations'] = [record for record in result['superseded_method_observations']
        if record.get('superseded_by') != 'reviewed_native_functional_replan']
    digest = hashlib.sha256(json.dumps(result, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if digest != BASELINE_PROFILE_SHA256 or digest != plan['baseline_canonical_profile_sha256']:
        raise AssertionError('Published run109 profile no longer reconstructs exactly')
    return result


def baseline_ids():
    data = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
    plan = data['planning_budget']['reviewed_native_functional_replan']
    names = plan['baseline_inventory']
    if len(names) != 654 or len(set(names)) != 654:
        raise AssertionError('Incomplete historical UI inventory')
    digest = hashlib.sha256('\n'.join(sorted(names)).encode()).hexdigest()
    if digest != '7136fd8faceb176a342ba3cb73c9c999d29722624b562acdfff50032fc54009f':
        raise AssertionError('Historical UI method identities changed')
    return set(names)


def historical_names(case, names):
    allowed = baseline_ids()
    return [name for name in names if case + '.' + name in allowed]


def historical_counts(directory):
    result = {}
    for path in historical_ui_sources(directory):
        source = path.read_text(); names = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        if not names:
            continue
        case = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)[0]
        retained = historical_names(case, names)
        if retained:
            result[case] = len(retained)
    if sum(result.values()) != 654 or len(result) != 98:
        raise AssertionError('Historical methods missing from current source')
    return result


def published_runtime_costs(directory, profile_path):
    profile = before_functional_batch(json.loads(Path(profile_path).read_text()))
    result = {}
    for method in sorted(baseline_ids()):
        case = method.split('.')[0]
        result.setdefault(case, Decimal(0))
        result[case] += Decimal(str(profile['method_seconds'].get(method,
            profile['estimated_method_seconds'].get(method, profile['unobserved_method_seconds']))))
    return result
