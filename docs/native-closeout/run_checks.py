#!/usr/bin/env python3
"""Offline integration verification. Exit codes retained; parser baseline remains FAIL."""
from pathlib import Path
import json,hashlib,subprocess,re,sys
root=Path(__file__).resolve().parents[2]; workspace=root.parent; out=root/'docs/native-closeout/checks';out.mkdir(exist_ok=True)
results=[]
def run(name,command,cwd=root):
 result=subprocess.run(command,cwd=cwd,capture_output=True,text=True)
 text=result.stdout+result.stderr;(out/(name+'.txt')).write_text(text)
 row={'name':name,'command':list(map(str,command)),'cwd':str(cwd),'exit_code':result.returncode,'status':'PASS' if result.returncode==0 else 'FAIL','output':'checks/'+name+'.txt'}
 if name in ['swift-availability','xcode-availability']:row['status']='AVAILABLE' if result.returncode==0 else 'NOT_RUN'
 if name=='whole-parser':
  prior=(root/'docs/community-media-templates/checks/whole-parser.txt').read_text()
  diagnostics=lambda value:[re.sub(r':\d+:\d+: tree-sitter', ':LINE:COL: tree-sitter', line) for line in value.splitlines() if ': tree-sitter ' in line]
  row['known_baseline_match']=diagnostics(text)==diagnostics(prior)
  row['diagnostic_count']=len(diagnostics(text))
  row['baseline_comparison']='File, diagnostic kind/order and count; line offsets can shift from additive host edits. Exact diagnostics retained in logs.'
 results.append(row);print(name,'EXIT='+str(result.returncode),row['status'],flush=True)
 return text
for old in json.loads((root/'docs/remaining-native-clients/checks/results.json').read_text()):
 if old['name'] in ['focused-parser','touched-historical-parser','whole-parser','whitespace','swift-availability','xcode-availability']:continue
 run(old['name'],old['command'],Path(old['cwd']))
for name,command in [
 ('voice-samples',['python','tools/check_merchant_voice_samples.py']),
 ('image-recovery',['python','tools/check_image_upload_recovery.py']),
 ('app-unit-inclusion',['python','-m','unittest','discover','-s','tools/tests','-p','test_app_unit_target.py','-v']),
]: run(name,command)
# Focus only changed/new source files, excluding historical failures in untouched files.
before=json.loads((root/'docs/native-closeout/before-hashes.json').read_text())
changed=sorted(str(p.relative_to(root)) for p in root.rglob('*.swift') if '.git' not in p.parts and hashlib.sha256(p.read_bytes()).hexdigest()!=before.get(str(p.relative_to(root))))
(root/'docs/native-closeout/changed-swift-files.json').write_text(json.dumps(changed,indent=2)+'\n')
parser=[str(workspace/'swift-syntax-venv/bin/python'),str(root/'tools/check_swift_syntax.py'),'--root',str(root)]
run('focused-parser',parser+[p for p in changed if p not in ['App/MerchantHomeView.swift']])
if 'App/MerchantHomeView.swift' in changed: run('touched-historical-parser',parser+['App/MerchantHomeView.swift'])
run('whole-parser',parser)
run('whitespace',['git','diff','--check'])
run('swift-availability',['sh','-c','command -v swift'])
run('xcode-availability',['sh','-c','command -v xcodebuild'])
(out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
unexpected=[x['name'] for x in results if x['status']=='FAIL' and x['name']!='touched-historical-parser' and not (x['name']=='whole-parser' and x.get('known_baseline_match'))]
print('Unexpected failures:',unexpected)
print('Whole-tree parser remains FAIL; Apple execution NOT_RUN.')
sys.exit(1 if unexpected else 0)
