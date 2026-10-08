"""Exact two-method UI0 migration. Current sources validate before historical projection."""
from copy import deepcopy
import hashlib,json,re,tempfile,atexit
from pathlib import Path
from types import SimpleNamespace
try:
 from run130_receipt_planning import previous_profile as before_receipt_profile, previous_source as before_receipt_source, previous_directory as before_receipt_directory
except ModuleNotFoundError:
 from tools.run130_receipt_planning import previous_profile as before_receipt_profile, previous_source as before_receipt_source, previous_directory as before_receipt_directory
ROOT=Path(__file__).resolve().parents[1]
FIXTURES=ROOT/'tools/tests/fixtures/run130_prepared_readiness'
PLAN='reviewed_run130_prepared_readiness'
CONTRACT_SHA256='b1186140ed33d50e9240278518c60534c9988c6dfc9ae648b550f53edd32a6b9'
OLD='ProjectEditPreparedNodesFlowTests.swift'
NEW='ProjectEditPreparedStoryOrderFlowTests.swift'
PATTERN=r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'
_lifetimes=[]
_cache={}
def digest(raw):return hashlib.sha256(raw).hexdigest()
def canonical(o):return digest(json.dumps(o,sort_keys=True,separators=(',',':')).encode())
def contract():
 raw=(ROOT/'tools/run130_prepared_readiness_contract.json').read_bytes()
 if digest(raw)!=CONTRACT_SHA256:raise ValueError('Unknown prepared family contract')
 return json.loads(raw)
def previous_profile(profile):
 result=before_receipt_profile(profile)
 if PLAN not in result.get('planning_budget',{}):return result
 c=contract()
 if canonical(result)!=c['current_profile_canonical_sha256']:raise ValueError('Changed prepared profile')
 result['planning_budget'].pop(PLAN)
 if canonical(result)!=c['previous_profile_canonical_sha256']:raise ValueError('Previous late repair evidence was not restored exactly')
 return result
def previous_source(path):
 p=before_receipt_source(path)
 if p.parent.name!='AppUITests':return p
 if p.name==NEW:raise ValueError('New prepared scheduling wrapper has no direct historical source')
 if p.name!=OLD:return p
 c=contract();actual=digest(p.read_bytes())
 if actual==c['before_file_sha256']:return p
 row=next(r for r in c['required_floors'].values() if Path(r['path']).name==OLD)
 if actual!=row['file_sha256']:raise ValueError('Unknown prepared source cannot project to history')
 before=FIXTURES/'AppUITests'/OLD
 if digest(before.read_bytes())!=c['before_file_sha256']:raise ValueError('Changed prepared family preimage')
 return before

def validate_current(directory):
 directory=before_receipt_directory(directory);c=contract()
 actual={p.name:{'sha256':digest(p.read_bytes())} for p in directory.glob('*.swift')}
 if actual!=c['current_ui_sources']:raise ValueError('Unknown incomplete or changed current prepared inventory')
 keys=[]
 for p in directory.glob('*.swift'):
  s=p.read_text();names=re.findall(r'\bfunc\s+(test\w+)\s*\(',s)
  if not names:continue
  classes=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',s)
  if len(classes)!=1 or len(set(names))!=len(names):raise ValueError('Invalid prepared whole-method inventory')
  keys.extend(classes[0]+'.'+name for name in names)
 if sorted(keys)!=c['current_inventory'] or len(set(keys))!=len(keys):raise ValueError('Prepared method omitted repeated or added')
 if sorted(c['aliases'].get(k,k) for k in keys)!=c['previous_inventory']:raise ValueError('Previous complete method identity not mapped once')
 for key,row in c['required_floors'].items():
  p=directory/Path(row['path']).name;s=p.read_text();decls={name:body for body,name in re.findall(PATTERN,s)}
  non=re.sub(r'(?m)^[ \t]*\n','',re.sub(PATTERN,'',s))
  if digest(decls[key.split('.')[1]].encode())!=row['declaration_sha256'] or digest(non.encode())!=row['all_non_test_source_sha256']:raise ValueError('Prepared method/helper changed')
  actual_seconds=row['historical_seconds']+row['launch_count']*(row['new_launch_reveal_maximum_swipes']+1)*row['new_reveal_iteration_seconds_assumption']+row['new_menu_readiness_seconds']
  if actual_seconds!=row['derived_seconds'] or ((actual_seconds+9)//10)*10!=row['seconds'] or not row['historical_seconds']<=row['seconds']<=900 or row['measured'] is not False:raise ValueError('Invalid complete prepared allowance')
 return c

def previous_directory(directory):
 """A checked current directory may materialize only the exact previous family."""
 directory=before_receipt_directory(directory);c=contract();old=directory/OLD
 relevant=(directory/NEW).exists() or (old.exists() and digest(old.read_bytes())!=c['before_file_sha256'])
 if not relevant:return directory
 validate_current(directory)
 key=str(directory.resolve())
 if key in _cache:return _cache[key]
 life=tempfile.TemporaryDirectory(prefix='prepared-prior-ui-');_lifetimes.append(life)
 target=Path(life.name)/'AppUITests';target.mkdir()
 for p in directory.glob('*.swift'):
  if p.name==NEW:continue
  (target/p.name).write_bytes(previous_source(p).read_bytes())
 _cache[key]=target;return target
atexit.register(lambda:[life.cleanup() for life in _lifetimes])

def weights(directory,profile_path):
 directory=Path(directory);profile=json.loads(Path(profile_path).read_text());c=contract()
 if PLAN not in profile.get('planning_budget',{}):
  p=directory/OLD
  compatible = p.exists() and any(digest(p.read_bytes())==r['file_sha256'] and canonical(profile)==r['profile_canonical_sha256'] for r in c['historical_compatible_sources'])
  if directory.resolve()==(ROOT/'Tests/AppUITests').resolve() or (directory/NEW).exists() or (p.exists() and digest(p.read_bytes())!=c['before_file_sha256'] and not compatible):raise ValueError('Current prepared family requires its plan')
  return None
 validate_current(directory);prior=previous_profile(profile);old_ui=previous_directory(directory)
 try:from run129_late_readiness import weights as previous_weights
 except ModuleNotFoundError:from tools.run129_late_readiness import weights as previous_weights
 with tempfile.TemporaryDirectory(prefix='prepared-prior-profile-') as d:
  p=Path(d)/'profile.json';p.write_text(json.dumps(prior));result=previous_weights(old_ui,p)
 if result.get(OLD[:-6])!=1470:raise ValueError('Historical prepared whole-class cost changed')
 result=dict(result)
 for key,row in c['required_floors'].items():result[key.split('.')[0]]=row['seconds']
 return result

def frozen_late_context():
 """Retain the thirteen previous late-layer test methods against their exact inputs."""
 lifetime=tempfile.TemporaryDirectory(prefix='frozen-5a7fd-late-');root=Path(lifetime.name)
 old=previous_directory(ROOT/'Tests/AppUITests');target=root/'Tests/AppUITests';target.mkdir(parents=True)
 for p in old.glob('*.swift'):(target/p.name).write_bytes(p.read_bytes())
 for rel in ['tools/run129_late_readiness_contract.json','docs/run129-late-readiness-budget.json','tools/tests/fixtures/run129_repairs/source-index.json']:
  p=root/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/rel).read_bytes())
 profile=previous_profile(json.loads((ROOT/'tools/ui_duration_weights.json').read_text()));(root/'tools/ui_duration_weights.json').write_text(json.dumps(profile))
 raw=(FIXTURES/'ui-shard-inventory.json').read_bytes()
 if digest(raw)!=contract()['previous_shard_inventory_sha256']:raise ValueError('Changed previous prepared shard inventory')
 (root/'docs/ui-shard-inventory.json').write_bytes(raw)
 return SimpleNamespace(root=root,lifetime=lifetime)

def retained_family_source(directory):
 """Prove exact original statements/helper bytes, then expose the historical input."""
 directory=Path(directory);c=validate_current(directory)
 before=(FIXTURES/'AppUITests'/OLD).read_text()
 if digest(before.encode())!=c['before_file_sha256']:raise ValueError('Changed prepared original source')
 original={name:body for body,name in re.findall(PATTERN,before)}
 old_launch='value.launch(); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5)); return value'
 new_launch='value.launch(); XCTAssertTrue(revealFixtureElement(value.textFields["projectEdit.name"], in: value, maximumSwipes: 10, requiresHittable: false)); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5)); return value'
 prefix=before.split('    // UNMEASURED',1)[0]
 for file in [OLD,NEW]:
  text=(directory/file).read_text()
  head=text.split('    // UNMEASURED',1)[0].replace('final class '+NEW[:-6]+': XCTestCase','final class '+OLD[:-6]+': XCTestCase')
  if head.count(new_launch)!=1 or head.replace(new_launch,old_launch,1)!=prefix:raise ValueError('Changed or extra prepared helper/launch')
  [(body,name)]=re.findall(PATTERN,text)
  if file==OLD:
   start=body.index('        let chapterMenuReady = ');end=body.index('        let choices = ',start)
   body=body[:start]+body[end:]
  if body!=original[name]:raise ValueError('An original complete prepared step changed')
 return before
