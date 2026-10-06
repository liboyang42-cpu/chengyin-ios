"""Exact run117-to-published-f128 inverse; live source and costs are checked separately."""
from copy import deepcopy
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
BASELINE_PROFILE_SHA256 = '399198d09ca7777a4ce5a9cb9457c6a077dea95f98abda0549e21abf06490170'
CURRENT_PROFILE_SHA256 = 'cec85861477b17cb8942744516eacb4a2c6deccb3b81ee904b7c20722244e8eb'
SOURCE_SHA256 = {'ClubStoryFlowTests': '2ab6488d5df1a96e325edf80e28bc38c766a7359ab532c12049f4052ddea1b11', 'TopicFlowTests': 'ecd736aa03e5e3ab62bf8eeea7b7af67b55e7d99f001d3710b6065f7e7b6d079', 'IntegratedNativeAcceptanceFlowTests': '78753d12bd20d754d6825b4b8700b1f6349686f1274c2a975127aba266165d7f', 'MerchantOnboardingFlowTests': '90f9f76ca8418f1fc19bcf264445b93faab4c077dd6356b80bfb4cbe75493e2b'}

def canonical(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def before_run117_repairs(profile):
    result=deepcopy(profile)
    plan=result['planning_budget'].get('run117_repair_replan')
    if plan is None:
        assert 'run117_previous_estimate_provenance' not in result
        assert 'run117_method_observations' not in result
        return result
    assert canonical(profile)==CURRENT_PROFILE_SHA256, 'Unreviewed run117 repair profile'
    result['planning_budget'].pop('run117_repair_replan')
    result['estimate_provenance']['methods']=result.pop('run117_previous_estimate_provenance')
    result.pop('run117_method_observations')
    for method,previous in plan['previous_effective_records'].items():
        for key,field in [('method_seconds','observation'),('estimated_method_seconds','estimate')]:
            if previous[field] is None:result[key].pop(method,None)
            else:result[key][method]=previous[field]
    assert canonical(result)==BASELINE_PROFILE_SHA256, 'Published f128 profile not exactly recovered'
    return result

def historical_run117_ui_source(path):
    path=Path(path)
    case=path.name.removesuffix('.swift.txt') if path.name.endswith('.swift.txt') else path.stem
    if case not in SOURCE_SHA256:return path
    result=ROOT/'tools/tests/fixtures/run117_published_sources'/(case+'.swift.txt')
    assert hashlib.sha256(result.read_bytes()).hexdigest()==SOURCE_SHA256[case], 'Immutable f128 source changed'
    return result

WORKFLOW_SHA256 = '3293a7cea5fc50f0827d65c93ba8197e57bd7c8c6facdca3df6d645caae5b1b1'
def historical_run117_workflow():
    path=ROOT/'tools/tests/fixtures/run117_published_sources/native-ios.yml.txt'
    assert hashlib.sha256(path.read_bytes()).hexdigest()==WORKFLOW_SHA256, 'Immutable f128 workflow changed'
    return path
