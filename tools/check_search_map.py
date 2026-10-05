#!/usr/bin/env python3
"""Offline source/structure assertions, not Swift compilation or execution."""
import argparse, json, pathlib, re
parser=argparse.ArgumentParser();parser.add_argument('--root',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1]);parser.add_argument('--flutter',type=pathlib.Path);args=parser.parse_args()
root=args.root.resolve(); checks=[]
def check(name,condition):
    assert condition,name;checks.append(name)
service=(root/'Core/SearchMapService.swift').read_text(); contracts=(root/'Core/SearchMapContracts.swift').read_text(); reading=(root/'Core/SearchMapReading.swift').read_text()
app='\n'.join(p.read_text() for p in (root/'App').glob('*Search*swift'))
keys=json.loads((root/'docs/search-map-localizations.json').read_text())
check('bilingual catalog entries', all(set(v)=={'en','zh-Hans'} and all(isinstance(x,str) and x for x in v.values()) for v in keys.values()))
app_without_ids=re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', '', app)
literal_keys={x for x in re.findall(r'"(searchMap\.[A-Za-z][A-Za-z0-9.]*)"',app_without_ids) if not x.endswith('.')}
check('all literal UI localization keys', literal_keys <= set(keys))
check('all domain/mode/validation localization keys', {f'searchMap.kind.{x}' for x in ['topic','activity','club','merchant']} | {f'searchMap.mode.{x}' for x in ['walking','driving','transit']} | {f'searchMap.validation.{x}' for x in range(8)} <= set(keys))
check('all four explicit source routes', all(x in service for x in ['api/topic/list','api/activity/list','api/club/list','api/merchant/list']))
check('read-only node/map/category routes', all(x in service for x in ['api/category/list','api/city/nodes','api/map/nearby','api/map/reverse-geocode']))
check('no live location/directions APIs', all(x not in app for x in ['CLLocationManager','requestWhenInUseAuthorization','startUpdatingLocation','MKDirections(','openInMaps(','UserAnnotation(']))
check('no search/map mutation routes', all(x not in service for x in ['/favorite','/checkin','/save','/create','/publish','/delete']))
check('session checks context before expiry', 'currentContext() == context, scope == capturedScope' in reading and 'context.accountID != nil { onUnauthorized(context) }' in reading)
check('guest epoch represented', 'guestEpoch' in reading and 'credential' in reading and 'epoch' in reading)
check('query completion fenced', 'SearchMapQueryGate' in reading and 'ticket.scope == scope && !Task.isCancelled' in reading and 'filter == query' in app)
check('local filters and first-page scope', 'Dates/prices are intentionally absent' in service and 'pageSize: 12' in service and 'pageSize: 50' in service)
check('private sources require a credential', service.count('guard token != nil else { throw APIError.unauthorized }')>=3)
check('city/detail IDs distinct from nearby/node IDs', 'case topic(Int), activity(Int), club(Int), merchant(Int), cityNode(Int)' in contracts and 'result.poiID == id' in service)
check('secure local-only history', 'SecItemCopyMatching' in app and 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' in app and 'guard let namespace else' in app)
check('route fallback never invents ETA/instructions', 'self.etaSeconds = isStraightLine ? nil : etaSeconds' in (root/'Core/SearchRoutePreview.swift').read_text())
check('fixture omits external map tiles', 'if offline {' in (root/'App/SearchMapCanvas.swift').read_text())
check('read-only synthetic fixtures', 'https://' not in (root/'Core/SearchMapSyntheticFixtures.swift').read_text())
if args.flutter:
    flutter=args.flutter.resolve()
    source=(flutter/'lib/feature/search/search_controller.dart').read_text()
    for relative, expected in [('topic_api.dart','/api/topic/list'),('activity_api.dart','/api/activity/list'),('club_api.dart','/api/club/list'),('merchant_api.dart','/api/merchant/list'),('city_node_api.dart','/api/city/nodes'),('map_api.dart','/api/map/nearby')]:
        check('retained source '+expected,expected in (flutter/'lib/data/api'/relative).read_text())
    check('source local filtering and partial aggregation', all(x in source for x in ['matchesDatePriceFilter','failedTypes','loginGated','pageSize: 12','pageSize: 50','radius: 20000']))
    check('source source-category contract', "list(type: '1')" in source)
    check('source directions modes', 'enum DirectionsMode { walking, driving, transit }' in (flutter/'lib/core/map/directions.dart').read_text())
print(f'PASS {len(checks)} search/map offline structural/source checks; {len(keys)} bilingual keys')
for name in checks:print(' - '+name)
print('Swift unit tests, iOS compilation, XCUITest, accessibility/device/provider/backend acceptance: NOT_RUN')
