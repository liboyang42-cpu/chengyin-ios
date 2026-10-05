#!/usr/bin/env python3
"""Static/source checks only: does not execute or typecheck Swift."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = root.parent / 'app-audit/lib/data/api/coop_api.dart'
contracts_path = root / 'Core/CooperationFlowContracts.swift'
if not contracts_path.exists():
    contracts_path = root.parent / 'chengyin-ios/Core/CooperationFlowContracts.swift'
contracts = contracts_path.read_text()
service = (root/'Core/CooperationFlowService.swift').read_text()
coordinator = (root/'Core/CooperationFlowCoordinator.swift').read_text()
gate = (root/'Core/CooperationProtectedDispatch.swift').read_text()
tests = (root/'Tests/CoreTests/CooperationProtectedDispatchTests.swift').read_text()
checks = []
def check(label, result):
    checks.append({'name': label, 'pass': bool(result)})
    assert result, label
for operation, path in [('invite','invite'), ('handle','handle'), ('contact','contact'), ('complaint','complaint/report'), ('enrollOffer','offer/enroll')]:
    check('source path '+operation, '/api/coop/'+path in source.read_text() and '"'+path+'"' in contracts)
    check('separate grant '+operation, 'case .'+operation+': self = .'+operation in gate)
check('all shipping defaults off', 'dormantWritesEnabled: Bool = false' in service and 'protectedDispatch: CoopFlowProtectedDispatch? = nil' in service and 'enabled: Bool = false' in coordinator and 'operations: Set<CoopFlowProtectedOperation> = []' in gate)
check('real transports cannot opt in accidentally', 'transport is any CoopFlowOfflineHTTPTransport' in service)
check('gate binds exact endpoint', 'self.endpoint == endpoint' in gate)
check('actual injected send', 'try await transport.send(request)' in service)
check('permanent block replaced', 'guard permitsDispatch(operation)' in service and 'dormantWritesEnabled && !operation.requiresSeparateEnablement' not in service)
check('fresh evidence twice', coordinator.count('try await evidence.freshEvidence') == 2)
check('exact review comparison', 'review == accepted' in coordinator and 'fresh.baseline == accepted.baseline' in coordinator)
check('scope bound to review', coordinator.count('executor.dispatchScope == accepted.dispatchScope') == 3)
check('session epoch and token equality', 'session == accepted.capturedSession' in coordinator and 'session.epoch == accepted.epoch' in coordinator)
check('durable lock before dispatch', coordinator.index('try locks.acquire(key)') < coordinator.index('try await executor.execute'))
check('no automatic unlock on errors', 'defer { try' not in coordinator and coordinator.index('try locks.complete(key)') > coordinator.index('try await executor.execute'))
check('old lock migration preserved', 'locks.contains(lockKey(op, account: account))' in coordinator)
check('new keys endpoint scoped and cross epoch', 'Data(scope.utf8).base64EncodedString()' in coordinator and 'return "\\(account):\\(resource)"' in coordinator)
check('contact validates source result', 'case .number = result["conversationId"]' in service and '(result["conversationId"].integer ?? 0) > 0' in service)
check('raw business text', 'envelope["msg"].text' in service)
check('financial contracts not expanded', not any(v in service+gate for v in ['deposit/create/app','deposit/refund/retry','URLSession.shared']))
for name in ['testAllFiveExactWireRequestsThroughReviewAndFakeHTTP', 'testDefaultOffGlobalOffIndependentGrantsEndpointAndMarker', 'testEveryOperationServerUnauthorizedAndMalformedErrors', 'testEveryUnknownOutcomePersistsAcrossRelaunchAndEpoch', 'testFreshEvidenceChangePermissionLossAndSessionChangeNeverSend', 'testEndpointSwapInvalidatesPreparedReview', 'testOldUnknownLocksSurviveUpgradeToEndpointKeys']:
    check('authored coverage '+name, 'func '+name in tests)
result = {'static_source_checks': 'PASS', 'checks': len(checks), 'swift_compilation':'NOT_RUN', 'swift_unit_tests':'NOT_RUN', 'ios_runtime':'NOT_RUN', 'external_requests':0, 'details':checks}
(root/'docs/cooperation-adapter-repair/source-checks.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='details'}, indent=2))
