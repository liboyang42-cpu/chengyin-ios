"""Twelve exact 902–908 second exceptions; every other 900-second cap stays intact.

Actual source/helper bytes validate before projecting immutable old audit inputs.
No Apple timing observation is inferred or consumed by this planning layer.
"""
from pathlib import Path
from copy import deepcopy
from types import SimpleNamespace
import atexit,hashlib,json,re,tempfile
ROOT=Path(__file__).resolve().parents[1]
PLAN='reviewed_run130_receipt_semantics'
CONTRACT_SHA256='de0cd006285c64088ad5ad82124f8667072feccc1769fb03df12ca8d9d26d171'
FIXTURES=ROOT/'tools/tests/fixtures/run130_receipt_semantics'
FIXED_EXCEPTIONS={
 'ApprovedReleasePublicationFlowTests.testCapturedConfirmationCreatesOneImmutableReceiptAndReopensWithoutAnotherPublish':906,
 'ApprovedReleaseReceiptRecoveryFlowTests.testLocalReceiptWriteFailureRecoversOnlyThePersistedRequest':904,
 'ApprovedReleaseRecoveryFlowTests.testChineseMaximumTextUnknownRecoveryKeepsOnlyThePersistedRequest':904,
 'ApprovedTopicFrozenCoverPublicationFlowTests.testApprovedCoverConfirmationAndUnknownPublicationRestoreOriginalManifest':908,
 'ApprovedTopicFrozenCoverReviewFlowTests.testBoundCoverReviewConfirmCancelAndUnknownRecoveryKeepOneExactRequest':904,
 'ApprovedTopicReviewCurrentChineseFlowTests.testChineseMaximumTextCurrentTaskReadRemainsSeparateFromSavedSubmissionAndClearsOnReopen':906,
 'ApprovedTopicReviewCurrentFlowTests.testExplicitCurrentTaskReadUpdatesObservationWithoutChangingEitherHistoricalReceipt':908,
 'ApprovedTopicReviewUnknownFlowTests.testChineseMaximumTextUnknownRequestRecoversSameIDWithoutAnotherSubmission':908,
 'ApprovedTopicSelectedCoverChineseFlowTests.testChineseMaximumTextShowsAuthorOnlyBoundaryAndKeepsOriginalReceipt':908,
 'ApprovedTopicSelectedCoverFlowTests.testCapturedAuthorCoverRemainsExactAndNeverCreatesAReviewRequest':904,
 'OwnedTopicCoverRecoveryFlowTests.testChineseMaximumTextUnknownSelectionReopensAndChecksOriginalRequestWithoutReupload':902,
 'OwnedTopicCoverSelectionFlowTests.testExplicitLocalPickUploadSelectionAndCapturedReviewImageUseOneExactAsset':902,
}
PATTERN=r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'
_lives=[]
def digest(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return digest(json.dumps(v,sort_keys=True,separators=(',',':')).encode())
def contract():
 raw=(ROOT/'tools/run130_receipt_planning_contract.json').read_bytes()
 if digest(raw)!=CONTRACT_SHA256:raise ValueError('Unreviewed receipt planning contract')
 c=json.loads(raw)
 if c['fixed_over900_exceptions']!=FIXED_EXCEPTIONS:raise ValueError('Over900 exception allowlist changed')
 return c

def source_layer():
 try:import run130_submission_evidence as source
 except ModuleNotFoundError:from tools import run130_submission_evidence as source
 return source

def previous_profile(profile):
 try:from branch_history_handshake_planning import previous_profile as before_handshake
 except ModuleNotFoundError:from tools.branch_history_handshake_planning import previous_profile as before_handshake
 p=before_handshake(profile)
 if PLAN not in p.get('planning_budget',{}):return p
 c=contract()
 if canonical(p)!=c['current_profile_canonical_sha256']:raise ValueError('Changed current receipt profile')
 p['planning_budget'].pop(PLAN)
 if canonical(p)!=c['previous_profile_canonical_sha256']:raise ValueError('Original prepared profile not restored exactly')
 return p

def previous_source(path):
 try:from branch_history_handshake_planning import previous_source as before_handshake
 except ModuleNotFoundError:from tools.branch_history_handshake_planning import previous_source as before_handshake
 p=before_handshake(path)
 if p.parent.name!='AppUITests':return p
 c=contract();allowed=c['accepted_historical_sources'].get(p.name)
 if allowed is None:
  if p.name in c['current_ui_sources'] and p.name not in c['previous_ui_sources']:
   raise ValueError('New receipt helper has no original source')
  return p
 if digest(p.read_bytes()) in allowed:return p
 return source_layer().previous_source(p)

def validate_current(directory):
 directory=Path(directory);c=contract()
 actual={p.name:{'sha256':digest(p.read_bytes())} for p in directory.glob('*.swift')}
 if actual!=c['current_ui_sources']:raise ValueError('Changed or incomplete current receipt UI sources')
 keys=[]
 for p in directory.glob('*.swift'):
  s=p.read_text();methods=re.findall(r'\bfunc\s+(test\w+)\s*\(',s)
  if not methods:continue
  classes=re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b',s)
  if len(classes)!=1 or len(methods)!=len(set(methods)):raise ValueError('Repeated or hidden method identity')
  keys.extend(classes[0]+'.'+m for m in methods)
 if sorted(keys)!=c['current_inventory'] or len(set(keys))!=736:raise ValueError('Receipt method inventory changed')
 for path,row in c['critical_App_sources'].items():
  if digest((ROOT/path).read_bytes())!=row['sha256']:raise ValueError('Receipt semantic App source changed')
 if digest((ROOT/'Tests/ContractChecks/fixtures/run130_submission_evidence.json').read_bytes())!=c['source_contract_sha256']:raise ValueError('Receipt source/phase evidence changed')
 for key,row in c['required_floors'].items():
  text=(directory/Path(row['path']).name).read_text();decls={name:body for body,name in re.findall(PATTERN,text)}
  if len(decls)!=1 or digest(decls[key.split('.')[1]].encode())!=row['declaration_sha256'] or digest(re.sub(PATTERN,'',text).encode())!=row['all_non_test_source_sha256']:raise ValueError('Complete receipt method or local helper changed')
  helper=directory/'ProjectSubmissionEvidenceUITestSupport.swift'
  if digest(helper.read_bytes())!=row['helper_sha256']:raise ValueError('Receipt shared helper changed')
  extra=2*(row['positive_receipt_lookups']+row['positive_history_lookups']+row['global_absence_assertions'])
  seconds=row['candidate_complete_method_seconds']
  if row['measured'] is not False or extra!=row['added_unmeasured_seconds'] or seconds!=row['historical_floor_seconds']+extra:raise ValueError('Receipt cost/floor derivation changed')
  if seconds>900 and FIXED_EXCEPTIONS.get(key)!=seconds:raise ValueError('Unapproved over900 method')
  if seconds<=900 and key in FIXED_EXCEPTIONS:raise ValueError('Historical floor or exception silently lowered')
 if sum(r['added_unmeasured_seconds'] for r in c['required_floors'].values())!=118:raise ValueError('Receipt delta changed')
 return c

def previous_directory(directory):
 try:from branch_history_handshake_planning import previous_directory as before_handshake
 except ModuleNotFoundError:from tools.branch_history_handshake_planning import previous_directory as before_handshake
 directory=before_handshake(directory)
 if directory.resolve()!=(ROOT/'Tests/AppUITests').resolve() and not (directory/'ProjectSubmissionEvidenceUITestSupport.swift').exists():return directory
 validate_current(directory)
 return source_layer().previous_directory(directory)

def weights(directory,profile_path):
 directory=Path(directory);profile=json.loads(Path(profile_path).read_text())
 if PLAN not in profile.get('planning_budget',{}):
  if directory.resolve()==(ROOT/'Tests/AppUITests').resolve() or (directory/'ProjectSubmissionEvidenceUITestSupport.swift').exists():raise ValueError('Current receipt source requires its exact plan')
  return None
 c=validate_current(directory);prior=previous_profile(profile);old_ui=previous_directory(directory)
 try:from run130_prepared_readiness import weights as prepared_weights
 except ModuleNotFoundError:from tools.run130_prepared_readiness import weights as prepared_weights
 with tempfile.TemporaryDirectory(prefix='receipt-prior-profile-') as d:
  p=Path(d)/'profile.json';p.write_text(json.dumps(prior));result=prepared_weights(old_ui,p)
 if result is None or abs(sum(result.values())-c['budget_total_before'])>1e-7:raise ValueError('Historical class costs changed')
 result=dict(result)
 for key,row in c['required_floors'].items():
  cls=key.split('.')[0]
  if result[cls]!=row['historical_floor_seconds']:raise ValueError('Old receipt method floor changed')
  result[cls]=row['candidate_complete_method_seconds']
 if abs(sum(result.values())-c['budget_total_after'])>1e-7:raise ValueError('Receipt total drift')
 return result

def frozen_prepared_context():
 """Preserve all original prepared-layer tests against their exact reviewed input."""
 c=contract();life=tempfile.TemporaryDirectory(prefix='frozen-pre-receipt-');_lives.append(life);root=Path(life.name)
 old=previous_directory(ROOT/'Tests/AppUITests');target=root/'Tests/AppUITests';target.mkdir(parents=True)
 for p in old.glob('*.swift'):(target/p.name).write_bytes(p.read_bytes())
 for path,row in c['historical_audit_files'].items():
  raw=(FIXTURES/path).read_bytes()
  if digest(raw)!=row['sha256']:raise ValueError('Frozen pre-receipt audit input changed')
  p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
 return SimpleNamespace(root=root,lifetime=life)
atexit.register(lambda:[x.cleanup() for x in _lives])
