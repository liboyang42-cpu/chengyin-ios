#!/usr/bin/env python3
"""Source/static contract evidence only. Does NOT compile or execute Swift."""
from pathlib import Path
import json, re
root = Path(__file__).resolve().parents[1]
source = root.parent / 'app-audit/lib/data/api/coop_api.dart'
contracts = (root/'Core/CooperationFlowContracts.swift').read_text()
service = (root/'Core/CooperationFlowService.swift').read_text()
coordinator = (root/'Core/CooperationFlowCoordinator.swift').read_text()
checks = []
def check(name, ok):
    checks.append((name, bool(ok)))
    if not ok: raise AssertionError(name)
for endpoint in ['pool/apply','pool/withdraw','pool/decline','candidates/confirm','candidates/reject','perk-template/save','perk-template/delete','perks/attach','offer/enroll','offer/circle-supply/reconfirm-current','offer/circle-supply/pause','review/save','complaint/report']:
    check('source endpoint '+endpoint, '/api/coop/'+endpoint in source.read_text() and '"'+endpoint+'"' in contracts)
for field in ['registrationId','applyId','topicId','handleReason','message','comment','templateIds','offerId']:
    check('wire key '+field, '"'+field+'"' in contracts)
check('no source-less signature path', not re.search(r'api/[^"\n]*(?:sign|agreement|reconcile)', contracts+service))
check('default dormant', 'dormantWritesEnabled: Bool = false' in service and 'enabled: Bool = false' in coordinator)
check('pre-dispatch durable lock', coordinator.index('try locks.acquire(key)') < coordinator.index('try await executor.execute'))
check('fresh evidence twice', coordinator.count('try await evidence.freshEvidence') == 2)
check('compare baseline', 'fresh.baseline == accepted.baseline' in coordinator)
check('cross-epoch durable key', 'return "\\(account):\\(resource)"' in coordinator)
check('no persisted credentials', 'token' not in coordinator[coordinator.index('public final class CoopFlowFileLocks'):coordinator.index('public struct CoopFlowReview')])
check('source complaint selector', 'api/coop/complaint/topics' in service)
check('nearby multipart', 'multipart/form-data; boundary=' in service)
check('null costs stay absent', 'unitCost.map' in contracts and '?? 0' not in contracts[contracts.index('public struct CoopFlowMoney'):contracts.index('public struct CoopFlowSettlement')])
catalog = json.loads((root/'Resources/Localizable.xcstrings').read_text())['strings']
for path in (root/'App').glob('*.swift'):
    for key in re.findall(r'"(coopflow\.[A-Za-z0-9_.]+)"', path.read_text()):
        if key.startswith(('coopflow.route.', 'coopflow.settlement.finance.', 'coopflow.submit.disabled')) or key in ['coopflow.workbench','coopflow.issue','coopflow.review','coopflow.template.name']: continue
        check('localized '+key, any(existing.startswith(key) for existing in catalog) if key.endswith('.') else key in catalog)
for key, value in catalog.items():
    if not key.startswith('coopflow.'): continue
    check('bilingual '+key, {'en','zh-Hans'} <= value['localizations'].keys())
result = {'static_source_checks':'PASS','checks':len(checks),'swift_compilation':'NOT_RUN','swift_unit_tests':'NOT_RUN','ios_ui_runtime':'NOT_RUN','network_requests':0}
(root/'docs/cooperation-flows/validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
