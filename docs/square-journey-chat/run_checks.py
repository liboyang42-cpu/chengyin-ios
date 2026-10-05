#!/usr/bin/env python3
"""Offline integration verification. Exit codes retained; parser baseline remains FAIL."""
from pathlib import Path
import json,hashlib,subprocess,re,sys
root=Path(__file__).resolve().parents[2]; workspace=root.parent; out=root/'docs/square-journey-chat/checks';out.mkdir(exist_ok=True)
results=[]
def run(name,command,cwd=root):
 result=subprocess.run(command,cwd=cwd,capture_output=True,text=True)
 text=result.stdout+result.stderr;(out/(name+'.txt')).write_text(text)
 row={'name':name,'command':list(map(str,command)),'cwd':str(cwd),'exit_code':result.returncode,'status':'PASS' if result.returncode==0 else 'FAIL','output':'checks/'+name+'.txt'}
 if name in ['swift-availability','xcode-availability']:row['status']='AVAILABLE' if result.returncode==0 else 'NOT_RUN'
 if name=='whole-parser':
  prior=(root/'docs/community-media-templates/checks/whole-parser.txt').read_text()
  diagnostics=lambda value:[line for line in value.splitlines() if ': tree-sitter ' in line]
  row['known_baseline_match']=diagnostics(text)==diagnostics(prior)
  row['diagnostic_count']=len(diagnostics(text))
 results.append(row);print(name,'EXIT='+str(result.returncode),row['status'],flush=True)
 return text
for old in json.loads((root/'docs/community-media-templates/checks/results.json').read_text()):
 if old['name'] in ['focused-parser','whole-parser','whitespace']:continue
 run(old['name'],old['command'],Path(old['cwd']))
for name,command in [
 ('check_square_governance',['python','tools/check_square_governance.py','--root',str(root),'--flutter',str(workspace/'app-audit')]),
 ('check_journey_content',['python','tools/check_journey_content.py']),
 ('check_shop_npc',['python','Tests/ContractChecks/check_shop_npc.py']),
 ('check_shop_npc_host',['python','tools/check_shop_npc_host.py',str(root)]),
 ('check_square_workspace',['python','Tests/ContractChecks/test_square_workspace.py'])]:run(name,command)
for index in range(6):run('ui-shard-'+str(index),['python','tools/run_ui_shard.py','--shard',str(index),'--count','6','--dry-run'])
# Focus only changed/new source files, excluding historical failures in untouched files.
before=json.loads((root/'docs/square-journey-chat/before-hashes.json').read_text())
changed=sorted(str(p.relative_to(root)) for p in root.rglob('*.swift') if '.git' not in p.parts and hashlib.sha256(p.read_bytes()).hexdigest()!=before.get(str(p.relative_to(root))))
(root/'docs/square-journey-chat/changed-swift-files.json').write_text(json.dumps(changed,indent=2)+'\n')
parser=[str(workspace/'swift-syntax-venv/bin/python'),str(root/'tools/check_swift_syntax.py'),'--root',str(root)]
run('focused-parser',parser+changed)
run('whole-parser',parser)
run('whitespace',['git','diff','--check'])
run('swift-availability',['sh','-c','command -v swift'])
run('xcode-availability',['sh','-c','command -v xcodebuild'])
(out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
unexpected=[x['name'] for x in results if x['status']=='FAIL' and not (x['name']=='whole-parser' and x.get('known_baseline_match'))]
print('Unexpected failures:',unexpected)
print('Whole-tree parser remains FAIL; Apple execution NOT_RUN.')
sys.exit(1 if unexpected else 0)
