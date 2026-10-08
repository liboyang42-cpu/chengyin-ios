"""Exact source-only inverse for historical assertions, never a budget bypass.

The new nested query allowance leaves twelve methods over900. The central runner
and profile are deliberately not changed or projected by this module.
"""
from pathlib import Path
import atexit,hashlib,json,tempfile
ROOT=Path(__file__).resolve().parents[1]
CONTRACT_SHA256='8637dc1f4fe1f1574424e173c28a71d9d6da600cb1195775071fb96416d494ee'
_lifetime=None

def contract():
 raw=(ROOT/'Tests/ContractChecks/fixtures/run130_submission_evidence.json').read_bytes()
 if hashlib.sha256(raw).hexdigest()!=CONTRACT_SHA256:raise ValueError('Changed receipt source and planning contract')
 return json.loads(raw)

def original_source(relative,source):
 row=contract()['files'][relative]
 if hashlib.sha256(source.encode()).hexdigest()!=row['after_sha256']:raise ValueError('Unknown current receipt source')
 if row['before_sha256'] is None:raise ValueError('New receipt helper has no original source')
 for hunk in row['hunks']:
  if source.count(hunk['after'])!=1:raise ValueError('Receipt hunk missing or ambiguous')
  source=source.replace(hunk['after'],hunk['before'],1)
 if hashlib.sha256(source.encode()).hexdigest()!=row['before_sha256']:raise ValueError('Original receipt file not restored exactly')
 return source

def previous_source(path):
 global _lifetime
 p=Path(path)
 if p.parent.name!='AppUITests':return p
 relative='Tests/AppUITests/'+p.name
 row=contract()['files'].get(relative)
 if row is None:return p
 before=original_source(relative,p.read_text())
 if _lifetime is None:_lifetime=tempfile.TemporaryDirectory(prefix='receipt-prior-source-')
 target=Path(_lifetime.name)/'AppUITests'/p.name;target.parent.mkdir(exist_ok=True);target.write_text(before)
 return target
atexit.register(lambda:_lifetime.cleanup() if _lifetime else None)


def previous_directory(directory):
 """Validate every actual UI source before preserving the exact prior audit input."""
 global _lifetime
 try:from branch_history_handshake_planning import previous_directory as before_handshake
 except ModuleNotFoundError:from tools.branch_history_handshake_planning import previous_directory as before_handshake
 directory=before_handshake(directory);c=contract()
 actual={p.name:{'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in directory.glob('*.swift')}
 if actual!=c['current_ui_sources']:raise ValueError('Incomplete or changed current receipt UI inventory')
 if _lifetime is None:_lifetime=tempfile.TemporaryDirectory(prefix='receipt-prior-source-')
 destination=Path(_lifetime.name)/'AppUITests';destination.mkdir(exist_ok=True)
 for name,row in c['previous_ui_sources'].items():
  p=directory/name;relative='Tests/AppUITests/'+name
  source=original_source(relative,p.read_text()) if relative in c['files'] else p.read_text()
  if hashlib.sha256(source.encode()).hexdigest()!=row['sha256']:raise ValueError('Prior UI source not restored exactly')
  (destination/name).write_text(source)
 return destination


def retained_display_family_source(name,source):
 """Only this exact current delta or its exact historical preimage is admissible."""
 relative='Tests/AppUITests/'+name+'.swift';row=contract()['files'][relative]
 if hashlib.sha256(source.encode()).hexdigest()==row['before_sha256']:return source
 try:return original_source(relative,source)
 except ValueError as error:raise AssertionError('Changed receipt display-family source') from error
