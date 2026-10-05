#!/usr/bin/env python3
"""Supplementary source-contract gates. Never substitutes for Swift/Xcode execution."""
import json, re, hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=root.parent/'app-audit'
core='\n'.join(p.read_text() for p in (root/'Core').glob('*.swift') if 'Fixture' not in p.name and p.name.startswith(('MerchantContent', 'MerchantStationContracts')))
ui='\n'.join(p.read_text() for p in (root/'App').glob('*.swift') if 'Fixture' not in p.name and p.name.startswith(('MerchantContent', 'MerchantStationContracts')))
refs=[source/'lib/data/api'/name for name in ['merchant_api.dart','merchant_npc_api.dart','topic_api.dart','my_project_api.dart','game_session_api.dart','template_api.dart','page_parity_api.dart']]
dart='\n'.join(p.read_text() for p in refs)
endpoints=set(re.findall(r'"(api/[a-zA-Z0-9_/-]+)"',core))
missing=[p for p in sorted(endpoints) if '/'+p not in dart]
assert not missing, ('Unbacked endpoint',missing)
commands=(root/'Core/MerchantContentCommands.swift').read_text()
assert '"xpValue"' not in commands
assert 'fields["xpValue"]' not in core
assert "'xpValue': ?xpValue" in dart
assert 'setXpValue' in (source/'test/blocked_by_backend_test.dart').read_text()
assert '"applicationId": .integer(id)' in commands
assert '"merchantMemberId": .integer(member)' in commands
assert '"greeting": greeting' in commands
assert '"voiceSample": sample' in commands
assert 'sampleUrls' not in commands
assert 'scope: capturedScope' in core
assert 'guard latest == baseline' in core
assert 'try journal.insert(record)' in core
assert 'execution: Execution = .disabled' in core
assert '"perspective": "MERCHANT"' in core
assert '"PLAYER_SUBMIT"' not in core and '"CLUB_BEGIN"' not in core
assert 'record.accountID == session.accountID' in core
assert 'raw["outcome"].text == "PENDING"' in core
assert '"chaptersList"' in commands
assert '"topic"]["chapters"]' not in core
assert 'q == .gameEntries' in core
assert 'snapshot.observedAt' in ui
assert 'query: .nodeAuthoring(chapterID: chapter)' in ui
catalog=json.loads((root/'Resources/MerchantContentLocalizations.fragment.json').read_text())
assert all(set(v['localizations'])=={'en','zh-Hans'} for v in catalog.values())
for key,val in catalog.items():
    assert all(v['stringUnit']['value'].strip() for v in val['localizations'].values()),key
# Full literal keys, plus source field names used by dynamic display and input helpers.
keys=set(re.findall(r'"(merchant\.content\.[A-Za-z0-9.]+)"',core+ui))
ignored={k for k in keys if k.endswith('.') or '.fixture.' in k or '.entry.' in k or '.row.' in k or '.field.' in k or '.open.' in k or k in {'merchant.content.contactHint','merchant.content.boundary','merchant.content.editor','merchant.content.issue','merchant.content.serverMessage','merchant.content.reload','merchant.content.close','merchant.content.review.cancel','merchant.content.codeExpired'}}
assert not (keys-ignored-set(catalog)),('Missing literal keys',keys-ignored-set(catalog))
fields=set()
for match in re.finditer(r'names:\s*\[([^\]]+)\]',ui): fields.update(re.findall(r'"([A-Za-z0-9]+)"',match.group(1)))
for match in re.finditer(r'field\("([A-Za-z0-9]+)"\)',ui): fields.add(match.group(1))
assert all('merchant.content.field.'+f in catalog for f in fields)
assert 'URLSession' not in ui and 'CLLocationManager' not in ui and 'AVAudioRecorder' not in ui
swift_files=sorted(root.rglob('*.swift'))
assert len(swift_files)>0
result={'status':'PASS','scope':'Static source and localization gates only; Swift/Xcode/UI runtime NOT_RUN','endpoint_count':len(endpoints),'core_tests_authored':sum(len(re.findall(r'func test\w+\(',p.read_text())) for p in (root/'Tests/CoreTests').glob('MerchantContent*.swift')),'ui_tests_authored':sum(len(re.findall(r'func test\w+\(',p.read_text())) for p in (root/'Tests/AppUITests').glob('MerchantContent*.swift')),'bilingual_keys':len(catalog),'swift_files':len(swift_files),'source_sha256':{str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in refs},'endpoints':sorted(endpoints)}
(root/'docs/merchant-content-static-evidence.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['source_sha256','endpoints']},indent=2))
