#!/usr/bin/env python3
"""Static source checks, not Swift compilation or runtime verification."""
import argparse, hashlib, json, re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--flutter',type=Path,default=Path(__file__).resolve().parents[2]/'app-audit');a=p.parse_args();r=a.root
source_paths=['lib/core/router/door_entry.dart','lib/data/models/scan_entry.dart','lib/data/api/play_api.dart','lib/data/api/registration_api.dart','lib/feature/account/pending_inviter.dart','lib/feature/account/door_entry_page.dart','lib/core/router/app_router.dart','lib/feature/account/inviter_sheet.dart','lib/data/models/invitation.dart']
sources={s:(a.flutter/s).read_text() for s in source_paths}
service=(r/'Core/DoorReferralService.swift').read_text(); contracts=(r/'Core/DoorReferralContracts.swift').read_text(); queue=(r/'Core/DoorReferralCoordinator.swift').read_text(); app=(r/'App/DoorReferralViews.swift').read_text()
for path,field,source in [('api/play/scan-entry','code','lib/data/api/play_api.dart'),('api/user/setInviter','inviter_id','lib/data/api/registration_api.dart')]:
    assert '/'+path in sources[source] and '"'+path+'"' in service
    assert "'"+field+"'" in sources[source] and 'field: "'+field+'"' in service
assert 'scanEnabled: Bool = false, bindingEnabled: Bool = false' in service
assert 'try await transport.send(request)' in service and 'URLSession' not in service
assert 'session == currentSession()' in service
assert 'value.utf8.count == 32' in contracts and 'verifiedHTTPSOrigins: Set<String> = []' in contracts
assert 'c.percentEncodedPath == "/door"' in contracts and 'query[key] == nil' in contracts
assert 'entry.status = .attempting' in queue and queue.index('entry.status = .attempting') < queue.index('try await service.bind')
assert 'scope == session' in queue and 'ticket == generation' in queue
assert 'has_inviter' not in queue and 'confirmationDialog' in app
catalog=json.loads((r/'Resources/DoorReferralLocalizations.fragment.json').read_text())['strings']
for key in set(re.findall(r'"(door\.[A-Za-z.]+)"',app+service+queue)):
    # Accessibility-only identifiers are not localization keys.
    if key in ['door.inviter.input','door.inviter.error','door.entry.loading','door.fixture.normalized']:continue
    assert key in catalog,key
for k,v in catalog.items():
    for lang in ['en','zh-Hans']:assert v['localizations'][lang]['stringUnit']['value']
files=sorted(['App/DoorReferralViews.swift', 'Core/DoorReferralContracts.swift', 'Core/DoorReferralCoordinator.swift', 'Core/DoorReferralService.swift', 'Resources/DoorReferralLocalizations.fragment.json', 'Tests/AppUITests/DoorReferralUITests.swift', 'Tests/CoreTests/DoorReferralTests.swift'])
manifest={'files':files,'dependencies':['Core/APIConfiguration.swift','Core/AuthService.swift (HTTPTransport)','Core/AuthRequestBuilder.swift'],'gates':{'scanEnabled':False,'bindingEnabled':False,'verifiedHTTPSOrigins':[]}}
(r/'docs/door-referral-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
evidence={'static_source_checks':'PASS','core_tests_authored':len(re.findall(r'func test\w+', (r/'Tests/CoreTests/DoorReferralTests.swift').read_text())),'ui_tests_authored':len(re.findall(r'func test\w+', (r/'Tests/AppUITests/DoorReferralUITests.swift').read_text())),'bilingual_keys':len(catalog),'swift_tests':'NOT_RUN: Swift unavailable','apple_build_ui_runtime':'NOT_RUN: Xcode/simulator unavailable','source_hashes':{s:hashlib.sha256((a.flutter/s).read_bytes()).hexdigest() for s in source_paths},'packet_hashes':{f:hashlib.sha256((r/f).read_bytes()).hexdigest() for f in files}}
(r/'docs/door-referral-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({k:v for k,v in evidence.items() if not k.endswith('hashes')},indent=2))
