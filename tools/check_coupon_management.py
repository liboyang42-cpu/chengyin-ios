#!/usr/bin/env python3
"""Supplementary static/source checks, never Swift compiler/runtime evidence."""
from pathlib import Path
import json, re
root = Path(__file__).resolve().parents[1]
source = root.parent/'app-audit/lib'
contract = (root/'Core/CouponManagementContract.swift').read_text()
coordinator = (root/'Core/CouponManagementCoordinator.swift').read_text()
domain = (root/'Core/CouponManagementDomain.swift').read_text()
locks = (root/'Core/CouponManagementLocks.swift').read_text()
ui = (root/'App/CouponManagementView.swift').read_text()
api = (source/'data/api/coupon_api.dart').read_text()
bridge = (root/'Core/CouponManagementReadTransport.swift').read_text()
checks = []
def check(label, condition):
    if not condition: raise AssertionError(label)
    checks.append(label)
paths = set(re.findall(r'"(/api/coupon/[^"\n]+)"', contract))
check('Only source author-management paths', paths == {'/api/coupon/mypublishlist','/api/coupon/publish','/api/coupon/stop'})
for path in paths: check('Audited endpoint '+path, path in api)
for key in ['name','startTime','endTime','publishCount','couponType','description']:
    check('Published field '+key, "'"+key+"'" in api and '"'+key+'"' in contract)
check('Multipart stop definition ID', '.multipart(["couponId": String(id.value)])' in contract)
check('JSON publication', '.json(try JSONSerialization.data' in contract)
check('No unauthorized claim route', not re.search(r'/api/coupon/(claim|receive|recv|info|delete|update|resume)', contract))
check('Read method is POST', 'var method: String { "POST" }' in contract)
check('Optional counts', 'let publishCount: Int?' in domain and 'let receiveCount: Int?' in domain)
check('Nullable money and currency', 'let amount: Decimal?' in domain and 'let currency: String?' in domain)
check('No default money', 'amount ?? 0' not in domain+ui and 'currency ?? "USD"' not in domain+ui)
check('Unknown status is not active', 'default: self = .unknown' in domain)
check('Server stop statuses only', 'self == .scheduled || self == .active' in domain)
check('No date-based eligibility', 'Date()' not in domain)
check('HTTP bridge refuses writes', 'guard !descriptor.mutates' in bridge)
check('HTTP bridge session/token fence', 'credentials() == captured' in bridge)
check('HTTP bridge source path only', 'descriptor.path == "/api/coupon/mypublishlist"' in bridge)
check('Dormant HTTP default off', 'dormantWritesEnabled: Bool = false' in bridge and 'guard dormantWritesEnabled' in bridge)
check('Dormant coordinator default off', 'dormantWritesEnabled: Bool = false' in contract and 'guard canSubmit, request.mutates' in contract)
check('Dormant HTTP exact payload', 'request.setValue(payload.contentType' in bridge and 'request.httpBody = payload.data' in bridge)
check('Writes default off', 'syntheticWritesEnabled: Bool = false' in contract)
check('Synthetic debug-only grants', '#if DEBUG' in contract and 'transport?.isSynthetic == true' in contract)
check('Pre-dispatch durable acquisition', coordinator.index('try locks.acquire(record)') < coordinator.index('await adapter.submit'))
check('Fresh publisher checks at review and confirm', coordinator.count('await authorizer.freshPermission') == 2)
check('Fresh stop snapshot equality', 'fresh == baseline, fresh.state.canStop' in coordinator)
check('Account epoch equality fences', 'currentSession() == session' in coordinator)
check('Immutable accepted payload', 'request: accepted.request' in coordinator and 'review == accepted' in coordinator)
check('Session epoch excluded from durable identity', 'namespace):\\(accountID)' in domain and '"publish"' in coordinator)
check('Exclusive file lock', '.withoutOverwriting' in locks)
check('No automatic reconciliation clearing', 'refreshAfterMutation' in coordinator and 'locks.release' not in coordinator[coordinator.index('private func refreshAfterMutation'):])
check('Claim explicit gap', 'couponManagement.claimUnavailable' in ui)
check('Feature visibility default off', 'isSourceVisible: Bool = false' in ui)
check('Dirty dismiss guarded', '.interactiveDismissDisabled(model.core.draft.dirty || model.working)' in ui)
fragment = json.loads((root/'Resources/CouponManagementLocalizations.fragment.json').read_text())
for file in list((root/'Core').glob('*.swift'))+list((root/'App').glob('*.swift')):
    for key in re.findall(r'"(couponManagement\.[A-Za-z][A-Za-z0-9]*)"', re.sub(r'\.accessibilityIdentifier\([^\n]*', '', file.read_text())):
        check('Localized '+key, key in fragment)
for key, val in fragment.items(): check('Bilingual '+key, {'en','zh-Hans'} <= set(val['localizations']))
result = {'static_source_checks':'PASS','check_count':len(checks),'swift_compilation':'NOT_RUN','swift_unit_tests':'NOT_RUN','ios_ui_runtime':'NOT_RUN','real_network_requests':0,'authored_core_test_cases':22,'authored_ui_test_cases':5,'claim_contract':'BLOCKED_SOURCE_GAP','live_write_grants':False}
(root/'docs/coupon-management/validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
