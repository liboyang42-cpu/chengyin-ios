#!/usr/bin/env python3
"""Authored source inventory; never a substitute for Apple test execution."""
from pathlib import Path
import hashlib, json, re, sys, importlib.util
root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('shards',root/'tools/run_ui_shard.py'); shards=importlib.util.module_from_spec(spec);spec.loader.exec_module(shards)
weights=shards.discover(root/'Tests/AppUITests');groups=shards.partition(weights,6)
count=lambda folder:sum(len(re.findall(r'\bfunc\s+test\w+\s*\(',p.read_text())) for p in (root/folder).glob('*.swift'))
value={'scope':'Authored/source counts only; Apple compiler, XCTest, XCUITest and runtime NOT_RUN','core_test_methods':count('Tests/CoreTests'),'ui_test_methods':sum(weights.values()),'ui_classes':len(weights),'app_unit_test_methods':count('Tests/AppUnitTests'),'app_unit_target':'QuestifyAppUnitTests','app_unit_execution':'NOT_RUN; app-hosted target and separate CI job implemented','ui_shard_counts':[sum(weights[n] for n in g) for g in groups],'ui_shards':groups,'app_swift_files':len(list((root/'App').glob('*.swift'))),'core_swift_files':len(list((root/'Core').glob('*.swift'))),'whole_tree_swift_files':len(list(root.rglob('*.swift'))),'bilingual_keys':len(json.loads((root/'Resources/Localizable.xcstrings').read_text())['strings'])}
(root/'docs/native-closeout/inventory.json').write_text(json.dumps(value,indent=2)+'\n')
before=json.loads((root/'docs/native-closeout/before-hashes.json').read_text()); target=root/'docs/native-closeout/changed-files.json';changes=[]
for p in sorted(root.rglob('*')):
 if not p.is_file() or '.git' in p.parts or '__pycache__' in p.parts or p==target:continue
 rel=str(p.relative_to(root)); digest=hashlib.sha256(p.read_bytes()).hexdigest()
 if before.get(rel)!=digest:changes.append({'path':rel,'before_sha256':before.get(rel),'sha256':digest,'bytes':p.stat().st_size})
target.write_text(json.dumps({'files':changes,'deleted':[p for p in before if not (root/p).exists()]},indent=2)+'\n')
print(json.dumps(value,indent=2)); print('changed_files',len(changes))
