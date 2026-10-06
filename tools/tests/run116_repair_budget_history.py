"""Exact pre-run116 planning/source reconstruction; never changes live XCTest."""
from copy import deepcopy
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
BASELINE_PROFILE_SHA256 = 'ae0ebfd4ecbb1fb7bf95f6882dcd4fb929ad3a4ed0cdcb91f94cc35b6cd490ca'
CURRENT_PROFILE_SHA256 = '399198d09ca7777a4ce5a9cb9457c6a077dea95f98abda0549e21abf06490170'
HISTORICAL_SHARD_COUNT = 34
SOURCE_SHA256 = {'ClubStoryFlowTests': '3ab00421d123e98eebb9661ab41bc67974bd586e86b4c83d7f3e165a1b063112', 'CoopRelationDiscoveryFlowTests': '17352cd1909e0f7db938e4c5830878fc8fce8fb1d952020349366e516dee5c4e', 'CouponCommandRecoveryFlowTests': '57e0e505e7539f51a67fae5218ca4a16edd025081567f0ce5fb126350bad78a8', 'CouponRuntimeFlowTests': '454103a8bc4b54d33f027c1c2aed6bd1bff442e253caefaccb8d972ab0510b8c', 'IntegratedNativeAcceptanceFlowTests': '840e3e19f19a461905bcb3d299094b764c0df312bffb289861f6756ad275e78b', 'MerchantOperationsFlowTests': '9cbddfe2eebfcf6196aa790f967c3cc022cf43cf1c4933a8953773549e47bb98', 'ProjectEditFlowTests': '7a17f183f0eac3978dfadb8c0cdd39634522fb1b5d0637979970d57344493891', 'PublicMerchantHomeFlowTests': 'f1bef5eaaf5dcd1a918a05221edd32701c94781c7713ba398c87d6c3da1f4fca', 'PublicPlayTemplatePresentationFlowTests': '9a3b090b5d5b927fd6492ac933b96f3c19c8bfb14d45c75f2f905e3e5c58cf48', 'SocialAccountFlowTests': '0df47b7b889d2f42b2e9e74daea7428e97acf63078fce6c3cb04b0b149a268a5', 'TemplatePreferenceDraftEditorFlowTests': '74622d7000bf9bd0c7c2790d1cb6dc8d4933007a6f6ec7f753179c93f83b267e', 'TopicFlowTests': '37ed57cb1ac759f62dd3dcb7e78166048273bdce4888ccb7d610564a54a06627', 'TopicTemplateNameSearchFlowTests': '86c607f5cdfeca11af3f0ab8f7f13a69cb17617c661bc5b876abf64b9a6b9996'}
WORKFLOW_SHA256 = 'dbd6843b651026fddf571f5e87ac64203570f47310b080c62752d20abfef39fa'

def before_run116_repairs(profile):
    result=deepcopy(profile)
    plan=result['planning_budget'].get('run116_repair_replan')
    if plan is None:
        assert 'run116_previous_estimate_provenance' not in result
        assert 'run116_method_observations' not in result
        return result
    canonical=lambda x:hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    assert canonical(profile)==CURRENT_PROFILE_SHA256, 'Unreviewed run116 repair profile'
    result['planning_budget'].pop('run116_repair_replan')
    result['estimate_provenance']['methods']=result.pop('run116_previous_estimate_provenance')
    result.pop('run116_method_observations')
    for method,previous in plan['previous_effective_records'].items():
        for key,field in [('method_seconds','observation'),('estimated_method_seconds','estimate')]:
            if previous[field] is None:result[key].pop(method,None)
            else:result[key][method]=previous[field]
    assert canonical(result)==BASELINE_PROFILE_SHA256, 'Published run116 profile not exactly recovered'
    return result

def historical_run116_ui_source(path):
    path=Path(path)
    case=path.name.removesuffix('.swift.txt') if path.name.endswith('.swift.txt') else path.stem
    if case not in SOURCE_SHA256:return path
    result=ROOT/'tools/tests/fixtures/run116_published_sources'/(case+'.swift.txt')
    assert hashlib.sha256(result.read_bytes()).hexdigest()==SOURCE_SHA256[case], 'Immutable run116 source changed'
    return result

def historical_run116_workflow():
    result=ROOT/'tools/tests/fixtures/run116_published_sources/native-ios.yml.txt'
    assert hashlib.sha256(result.read_bytes()).hexdigest()==WORKFLOW_SHA256, 'Immutable run116 workflow changed'
    return result
