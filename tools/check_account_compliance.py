#!/usr/bin/env python3
"""Source-contract checks only. These do not execute Swift or simulate HTTP transport."""
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
workspace=root.parent
service=(root/'Core/AccountComplianceService.swift').read_text()
contracts=(root/'Core/AccountComplianceContracts.swift').read_text()
coordinator=(root/'Core/AccountComplianceCoordinator.swift').read_text()
views=(root/'App/AccountComplianceViews.swift').read_text()
source=(workspace/'app-audit/lib/data/api/account_api.dart').read_text()+(workspace/'app-audit/lib/data/api/page_parity_api.dart').read_text()
checks=0
def check(ok,label):
 global checks
 assert ok,label
 checks+=1
for path in ('/api/compliance/consents/latest','/api/compliance/consents','/api/merchant/crm/marketing-consents','/api/user/deregister/status','/api/user/deregister/precheck','/api/user/deregister/apply','/api/user/deregister/cancel'):
 check(path in service and path in source,path)
check('fields["docVersion"]' not in service and '"docVersion":' not in service,'server-owned version')
check('readsEnabled: Bool = false, writesEnabled: Bool = false' in service,'default gates off')
check('AuthChannelInput.code(smscode)' in service and 'form: ["smscode"' in service,'multipart SMS code')
check('scopeType == subject.scopeType && scopeId == subject.scopeID' in contracts,'scope readback')
check('authoritativeMerchantID() != id' in service,'authoritative scope fencing')
check('current() == session' in service and 'generation == stamp' in coordinator,'session and generation fences')
check('try journal.begin' in service and 'options: .atomic' in contracts,'durable before-send journal')
check('private func write' in service and 'try journal.resolve' in service,'explicit mutation resolution')
check('AuthChannelServing' in coordinator and 'auth.sendSMSCode' in coordinator,'reuse auth SMS')
check(coordinator.index('effects.stopTracking()') < coordinator.index('effects.clearMapPrivacy()'),'roam effect order')
check('await self.invalidateSession(session)' in coordinator,'accepted application invalidation')
check('pending.epoch == session.epoch' in service,'fresh-login fence')
check('SettingsLegalDocumentView' in views and 'SettingsLegalReading' in views,'existing legal reader')
check('interactiveDismissDisabled' in views and 'accessibilityIdentifier' in views,'UI interruption/a11y hooks')
check('URLSessionTransport(' not in service,'no default live transport')
catalog=json.loads((root/'Resources/AccountCompliance.xcstrings').read_text())
for key,value in catalog['strings'].items():
 check(set(value['localizations'])=={'en','zh-Hans'},key)
tests=(root/'Tests/CoreTests/AccountComplianceTests.swift').read_text()
fixtures=re.findall(r'#"(.*?)"#',tests)
for fixture in fixtures: json.loads(fixture)
check('ComplianceHTTPFake: HTTPTransport' in tests,'fake injectable HTTP tests')
print(f'PASS {checks} static/source-contract checks; {len(fixtures)} JSON fixture literals valid')
print(f'AUTHORED {len(re.findall(r"func test",tests))} Swift XCTest methods; NOT EXECUTED (Swift/Apple SDK absent)')
