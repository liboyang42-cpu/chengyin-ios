#!/usr/bin/env python3
"""Source assertions only, not executed Swift/HTTP/runtime tests."""
import pathlib,json,re
root=pathlib.Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text()
checks=[]
def require(name, condition):
 if not condition: raise AssertionError(name)
 checks.append(name)
service=read('Core/JourneyContentService.swift');coord=read('Core/JourneyCheckCoordinator.swift');ambient=read('Core/JourneyAmbientCoordinator.swift')
require('Default live gates off', all(x in service for x in ['readsEnabled: Bool = false','checksEnabled: Bool = false','collectEnabled: Bool = false']))
require('Exact encounter GET/query', '"api/play/encounter"' in service and 'query: ["topicId": String(topicID), "nodeId": String(nodeID)]' in service)
require('Exact action multipart fields', 'form: ["topicId": String(review.topicID), "nodeId": String(review.nodeID), "checkId": review.checkID]' in service)
require('No fabricated receipt endpoint', '/receipt' not in service)
require('Companion exact session fields', '"api/play/companionLine", query: scope.fields' in service)
require('Egg collect exact fields', '"eggId": String(egg.id), "content": egg.text' in service and '"api/play/egg/collect", form: fields' in service)
require('Server settled recovery', 'message?.contains("已结算")' in coord and 'guard result.settled' in coord)
require('Durable write ahead before dispatch', coord.index('journal.save(checkID: approved.checkID') < coord.index('service.act(approved)'))
require('Session and review fencing', 'review == approved' in coord and 'currentSession() == approved.session, generation == stamp' in coord)
require('Probe failure quiet single attempt', 'probed = true' in coord and 'Exactly one silent optional probe' in coord)
require('Account region session seen state', all(x in ambient for x in ['scope.region','scope.accountID','scope.session.id','scope.session.fields.keys']))
require('Bounded cooldown and bubble timing', all(x in ambient for x in ['>= 180','addingTimeInterval(6)','addingTimeInterval(3.5)']))
require('No system location or random die', all(x not in '\n'.join(p.read_text() for p in (root/'Core').glob('*.swift')) for x in ['CLLocationManager','requestWhenInUseAuthorization','Int.random','Double.random']))
require('Normal host and eggs projection patch', all(x in read('tools/apply_host_hooks.py') for x in ['JourneyEgg.project','journeyModel: { session.journeyCheck','PlayJourneyCheckView(model: journey','PlayAmbientView(model: ambientModel)','journeyContent']))
strings=json.loads(read('docs/localizations.json'))
require('Bilingual strings',len(strings)>=25 and all(set(v)=={'en','zh-Hans'} for v in strings.values()))
require('Core and UI test artifacts', 'testPersistentUnknownRestores' in read('Tests/CoreTests/JourneyContentTests.swift') and 'testProbeFailureDoesNotBlockMainTask' in read('Tests/AppUITests/JourneyContentFlowTests.swift'))
print(json.dumps({'status':'PASS','kind':'source assertions only','checks':checks,'swift_tests':'NOT_RUN','apple_build':'NOT_RUN','runtime':'NOT_RUN','network':'NOT_RUN'},indent=2))
