"""Exact accepted-173 timing/source history. Never used by the live UI runner.

Two published test sources and one accepted public-code source preserve the historical assertions
across intact class migrations. Current execution is separately exhaustive.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
BASELINE_PROFILE_SHA256 = '142fd023d01c7c822431b409e8d8c910fd38400b7d1e6e0114fdb959c8f03790'
HISTORICAL_SHARD_COUNT = 29
CURRENT_PROFILE_SHA256 = '9dd3a66bc5bec555f1bf0d77aa92c47ad1026d4ae871513ff1cee27edcdf9f36'
SOURCE_SHA256 = {'OwnerDraftBrowserFlowTests': 'de62873d78f04b6f766f9507b1b24186dddfa4b5ba4203ff78a6d1424b26c6c3', 'IntegratedNativeAcceptanceFlowTests': '8ce0537a36a2c870d3ecd61c2542642428ac4289cea0df341e44a2318dd13a55', 'TemplateEditorControlsFlowTests': '7586ff68d3037b28c221ae546644f571a723d1c75d386ac306cf6cde63875032'}
MOVED_CLASSES = {'OwnerDraftHistoryFlowTests', 'IntegratedActivityPlayJourneyFlowTests', 'TemplateHistoricalHintFlowTests'}
ROOT = Path(__file__).resolve().parents[2]

def before_run109_amendments(profile):
    result = deepcopy(profile)
    plan = result['planning_budget'].pop('run109_amendment_replan', None)
    if plan is not None:
        assert hashlib.sha256(json.dumps(profile,sort_keys=True,separators=(',',':')).encode()).hexdigest() == CURRENT_PROFILE_SHA256, 'Unreviewed current timing bytes'
        result['estimate_provenance']['methods'] = result.pop('run109_previous_estimate_provenance')
        result.pop('run109_method_observations')
        for method, previous in plan['previous_effective_records'].items():
            for key, field in [('method_seconds','observation'),('estimated_method_seconds','estimate')]:
                if previous[field] is None: result[key].pop(method,None)
                else: result[key][method] = previous[field]
    digest = hashlib.sha256(json.dumps(result,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    allowed = {BASELINE_PROFILE_SHA256}
    if plan is None and 'reviewed_native_functional_replan' not in result['planning_budget']:
        allowed.add('96f448d7b88761b70bc0829d9d72ff59768814fab3aad26fa0948f683d3e8682')
    assert digest in allowed, 'Accepted173 or already reconstructed published run109 profile must match exactly'
    return result

def historical_ui_source(directory, case):
    if case not in SOURCE_SHA256: return Path(directory)/(case+'.swift')
    folder = 'run109_accepted_sources' if case == 'OwnerDraftBrowserFlowTests' else 'run109_published_sources'
    path = ROOT/'tools/tests/fixtures'/folder/(case+'.swift.txt')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == SOURCE_SHA256[case], 'Immutable historical source changed'
    return path

def historical_ui_sources(directory):
    return [historical_ui_source(directory,p.stem) for p in sorted(Path(directory).glob('*.swift')) if p.stem not in MOVED_CLASSES]
