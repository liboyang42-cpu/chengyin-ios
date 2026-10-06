"""Lossless pre-run114 public timing/source reconstruction; never used by live XCTest."""
from copy import deepcopy
import hashlib,json
from pathlib import Path
BASELINE_PROFILE_SHA256 = '9dd3a66bc5bec555f1bf0d77aa92c47ad1026d4ae871513ff1cee27edcdf9f36'
CURRENT_PROFILE_SHA256 = 'b2bebef2726f1780b7e3bf5f96b8a25200d3fc47a08c28933c4d990dc94d42e4'
HISTORICAL_SHARD_COUNT = 32
ROOT=Path(__file__).resolve().parents[2]
SOURCE_SHA256 = {'ClubStoryFlowTests': '471059ee2487f440dec86f8ce8eb0a7d5756b9b35108470597b62b99a9898712', 'MerchantClubDiscoveryFlowTests': 'a915f72422cd49f4c51f7cc71036f00717546552a5d39491274ca9e51aeb5e0b', 'MerchantContentFlowTests': '0da29cc6271024373dad28f7594658fa85e379c3a480a4bdab18edb811701a63', 'NonCashRewardFlowTests': '9645c281782362cff2a97d05b946d1e59e6eafc0ffe66c5cba24616900ce770b', 'ProjectEditFlowTests': '525e46daaccd0acbfe4e8f7695310b1aade62853bd6935488df7d9333768f0ee', 'PublicPlayTemplatePresentationFlowTests': '3e65cb80fc573506d93b9447a5e6178693893f3dc91cb1ab32aef80ccc7d15c0', 'TemplateAuthoringFlowTests': '0882328e8904182027c9bf98a3b0d7e4a0fc2e04f7e1bf29310236a0f4748a70', 'TemplatePreferenceDraftEditorFlowTests': '67d1bce4fe7bd46e9285e02264767ede5f250e3ac6d525dae0ea762ac4605b12', 'TopicTemplateNameSearchFlowTests': 'bf37bcb52547c2cfd99a2a8b4fdb302a8c7d2773d92b83caacc5fd97ac837dca', 'TopicFlowTests': '4882e6be7ddf0cef180d1863d6c3d22c5b750d94de55129fb9e5ccd5abe38ada', 'SocialAccountFlowTests': '4e3c95d4acbfe3b6d0301e65b97e41c4ef3f689a65e4057a9bbbc9e72a82586d', 'TemplateCompositionFlowTests': '8e932fd24ac017048ad1576da17919e5a61c5316cda219d9b11fb43b2c2dd580'}

def before_run114_repairs(profile):
    result=deepcopy(profile)
    plan=result['planning_budget'].get('run114_repair_replan')
    if plan is None:
        assert 'run114_previous_estimate_provenance' not in result
        assert 'run114_method_observations' not in result
        return result
    assert hashlib.sha256(json.dumps(profile,sort_keys=True,separators=(',',':')).encode()).hexdigest()==CURRENT_PROFILE_SHA256, 'Unreviewed current repair profile'
    result['planning_budget'].pop('run114_repair_replan')
    result['estimate_provenance']['methods']=result.pop('run114_previous_estimate_provenance')
    result.pop('run114_method_observations')
    for method,previous in plan['previous_effective_records'].items():
        for key,field in [('method_seconds','observation'),('estimated_method_seconds','estimate')]:
            if previous[field] is None:result[key].pop(method,None)
            else:result[key][method]=previous[field]
    assert hashlib.sha256(json.dumps(result,sort_keys=True,separators=(',',':')).encode()).hexdigest()==BASELINE_PROFILE_SHA256, 'Published run114 profile not exactly recovered'
    return result

def historical_run114_ui_source(path):
    path=Path(path)
    if path.stem not in SOURCE_SHA256:return path
    result=ROOT/'tools/tests/fixtures/run114_published_sources'/(path.stem+'.swift.txt')
    assert hashlib.sha256(result.read_bytes()).hexdigest()==SOURCE_SHA256[path.stem], 'Immutable run114 public source changed'
    return result
