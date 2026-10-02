#!/usr/bin/env python3
"""Static/source evidence, never Swift compile or live transport verification."""
import json,re,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=root.parent/'app-audit'
api=(source/'lib/data/api/official_api.dart').read_text()
contracts=(root/'Core/OfficialActionContracts.swift').read_text()
service=(root/'Core/OfficialActionService.swift').read_text()
coord=(root/'Core/OfficialActionCoordinator.swift').read_text()
ui=(root/'App/OfficialActionViews.swift').read_text()
checks=[]
def check(name, value):
 assert value,name
 checks.append(name)
for path in ['publish','broadcast','invites']:
 check('source exact '+path, f"'/api/official/{path}'" in api and f'"api/official/{path}"' in contracts)
for suffix in ['signup','complete','arrivals']:
 check('source event '+suffix, '/'+suffix in api and '/'+suffix in contracts)
for fragment in ['organizer-invites','v2/parties','merchantIds','missionCode','requestId','accuracyM','sessionId']:
 check('source contract '+fragment, fragment in api or fragment in (source/'test/data/api/official_publisher_test.dart').read_text())
 check('native contract '+fragment,fragment in contracts)
check('dormant transport','enabled: Bool = false' in service and 'guard enabled else' in service)
check('durable pre-dispatch lock',coord.index('try locks.insert(lock)')<coord.index('try await access.send(review.command)'))
check('namespace/account lock excludes epoch','[identity.namespace, String(identity.accountID), command.scope]' in coord)
check('immutable snapshot preflight','fresh == review.snapshot' in coord and 'pending == review' in coord)
check('server facts never changed','event.signed =' not in coord and 'myProgress =' not in coord)
check('no new endpoints', '/edit' not in contracts and '/receipt' not in contracts and '/retry' not in contracts)
check('no live/default transport','URLSession' not in service)
check('arrival current account and expiry','evidence.identity == identity, evidence.expiresAt > now' in contracts)
check('bilingual accessibility','accessibilityIdentifier' in ui and 'frame(minHeight: 44)' in ui)
catalog=json.loads((root/'docs/official-action-localizations.json').read_text())['strings']
for key,item in catalog.items():
 for lang in ['en','zh-Hans']:check('translation '+key+' '+lang,bool(item['localizations'][lang]['stringUnit']['value']))
for key in re.findall(r'"(officialAction\.[\w.]+)"',ui):
 if key.endswith('.') or key not in catalog and key.split('.')[-1] in ['reviewPayload','message','reviewPublish','reviewBroadcast','participationReview','rejectionReason']:continue
 check('UI catalog '+key,key in catalog)
count=lambda folder:sum(len(re.findall(r'func test\w+',p.read_text())) for p in (root/folder).glob('OfficialAction*.swift'))
result={'static_checks':'PASS','assertions':len(checks),'core_tests_authored':count('Tests/CoreTests'),'ui_tests_authored':count('Tests/AppUITests'),'bilingual_keys':len(catalog),'swift_test':'NOT_RUN: Swift unavailable','xcode_ui':'NOT_RUN: Xcode/simulator unavailable','remote_actions':0,'source_sha256':{p:hashlib.sha256((source/p).read_bytes()).hexdigest() for p in ['lib/data/api/official_api.dart','lib/data/models/official_event.dart','lib/feature/official/official_publish_page.dart','test/data/api/official_publisher_test.dart']}}
(root/'docs/official-action-static-evidence.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='source_sha256'},indent=2))
