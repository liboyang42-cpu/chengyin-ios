"""Exact independent media/map planning and source projections from the union."""
from pathlib import Path
from copy import deepcopy
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
FIXTURES=ROOT/'tools/tests/fixtures/combined_native'
CURRENT_PROFILE_SHA256='f4acbff048c8b28b7097de229371a5e3093213cb06b9e32df33c62016ef21d10'
SOURCE_INDEX_SHA256='70d81d60c54baae8b08abade04208a8d16f399c2c7ed6d7d2f55867ae8ee300f'

def canonical(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def source_index():
 data=(FIXTURES/'source-index.json').read_bytes();assert hashlib.sha256(data).hexdigest()==SOURCE_INDEX_SHA256;return json.loads(data)
def before_combined(profile,branch):
 result=deepcopy(profile)
 if 'reviewed_combined_native_replan' not in result['planning_budget']:
  assert not {'reviewed_story_media_replan','reviewed_map_alternative_list_replan'}.issubset(result['planning_budget']), 'Missing union identity'
  return result
 assert canonical(profile)==CURRENT_PROFILE_SHA256,'Unreviewed combined native profile'
 index=source_index()[branch];data=(FIXTURES/(branch+'-inverse.json')).read_bytes();assert hashlib.sha256(data).hexdigest()==index['inverse_sha256'];inverse=json.loads(data)
 assert inverse['current_canonical_sha256']==CURRENT_PROFILE_SHA256
 for op in inverse['operations']:
  target=result
  for key in op['path'][:-1]:target=target[key]
  if op['op']=='remove':target.pop(op['path'][-1])
  else:target[op['path'][-1]]=deepcopy(op['value'])
 assert canonical(result)==inverse['restored_canonical_sha256']==index['profile_canonical_sha256'],'Independent profile not exactly restored'
 return result

def materialize_independent_ui(directory,branch):
 destination=Path(directory);destination.mkdir(parents=True,exist_ok=True)
 for row in source_index()[branch]['ui_sources']:
  source=FIXTURES/row['historical_file'] if 'historical_file' in row else ROOT/row['path'];data=source.read_bytes();assert hashlib.sha256(data).hexdigest()==row['sha256'],row['path'];(destination/Path(row['path']).name).write_bytes(data)
 return destination

def independent_workflow(branch):
 p=FIXTURES/(branch+'-native-ios.yml.txt');assert hashlib.sha256(p.read_bytes()).hexdigest()==source_index()[branch]['workflow_sha256'];return p
