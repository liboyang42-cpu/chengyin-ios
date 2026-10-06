from tools.tests.combined_native_budget_history import before_combined
"""Exact pre-media profile and source projection; current media remains separately exhaustive."""
from copy import deepcopy
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
FIXTURES=ROOT/'tools/tests/fixtures/pre_story_media'
BASELINE_PROFILE_SHA256= '242c561c0efd4bb4b7d084ac552df42cd29f34c47e89d2773a6fb6c5169d77d1'
CURRENT_PROFILE_SHA256= '8c43a38311c7d309253f6dd9fc8051df05337a5b5c1f810f5420d7d0ae354ef0'
SOURCE_INDEX_SHA256= '232f1bb287b450207a6bfb0f95b68f399c155ff59d2a572e4d22fc538a67e6ea'
HISTORICAL_SHARD_COUNT=38
def canonical(x):return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def source_index():
 data=(FIXTURES/'source-index.json').read_bytes();assert hashlib.sha256(data).hexdigest()==SOURCE_INDEX_SHA256;return json.loads(data)
def before_story_media(profile):
 profile = before_combined(profile, 'media')
 result=deepcopy(profile)
 if 'reviewed_story_media_replan' not in result['planning_budget']:
  assert not any(k.startswith('story_media_previous_') for k in result);return result
 assert canonical(profile)==CURRENT_PROFILE_SHA256,'Unreviewed current story-media profile'
 result['planning_budget'].pop('reviewed_story_media_replan')
 result['method_seconds']=result.pop('story_media_previous_method_seconds')
 result['estimated_method_seconds']=result.pop('story_media_previous_estimated_method_seconds')
 result['estimate_provenance']['methods']=result.pop('story_media_previous_estimate_provenance')
 assert canonical(result)==BASELINE_PROFILE_SHA256,'Current published feature profile not exactly restored'
 return result
def historical_pre_media_ui_source(path):
 path=Path(path);name=path.name.removesuffix('.txt');expected=source_index()['changed_sources'].get(name)
 if expected is None:return path
 result=FIXTURES/(name+'.txt');assert hashlib.sha256(result.read_bytes()).hexdigest()==expected;return result
def materialize_historical_pre_media_ui(directory):
 destination=Path(directory);destination.mkdir(parents=True,exist_ok=True)
 for name in source_index()['baseline_ui_filenames']:(destination/name).write_bytes(historical_pre_media_ui_source(ROOT/'Tests/AppUITests'/name).read_bytes())
 return destination
def historical_pre_media_workflow():
 p=FIXTURES/'native-ios.yml.txt';assert hashlib.sha256(p.read_bytes()).hexdigest()==source_index()['workflow_sha256'];return p
