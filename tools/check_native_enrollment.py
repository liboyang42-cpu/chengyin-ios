#!/usr/bin/env python3
"""Offline source/fixture checks. Does not execute Apple APIs, keys, or network."""
import base64, hashlib, json, pathlib
R = pathlib.Path(__file__).resolve().parents[1]
def read(path): return (R / path).read_text()
checks=[]
def check(name, result):
    assert result, name
    checks.append(name)
f=json.loads(read('docs/native-app-attest-enrollment-v1.json'))
nonce=base64.b64decode(f['challenge']['challengeBase64'], validate=True)
check('backend nonce is exact bytes00..1f', nonce == bytes(range(32)))
check('backend decoded-nonce SHA256 vector', hashlib.sha256(nonce).hexdigest()==f['clientDataHashHex'])
check('fixture has no genuine attestation', f['attestationObject'] is None and f['fixtureKind'].startswith('SYNTHETIC'))
service=read('Core/NativeEnrollmentService.swift')
check('exact four routes', all('api/native/device/'+s in service for s in ['status','enrollment-challenge','enroll','revoke']))
check('independent default-off grants', 'enabled: Bool = false, enrollmentEnabled: Bool = false, revocationEnabled: Bool = false' in service)
check('session checked around dispatch', 'try gate(); try Task.checkCancellation()' in service)
contracts=read('Core/NativeEnrollmentContracts.swift')
check('strict canonical Base64', 'bytes.base64EncodedString() == text' in contracts)
check('production-only scope', 'environment == "production"' in contracts)
check('no hardware or reward assertion', 'raw["rewardEnabled"].bool == false' in contracts and 'raw["hardwareVerified"].bool == false' in contracts)
check('scope and prior-key reuse validation', 'scope == expected' in contracts and '!retiredKeys.contains(key)' in contracts)
driver=read('App/AppleEnrollmentDeviceProvider.swift')
check('genuine default-off DeviceCheck adapter', 'enabled: Bool = false' in driver and 'service.generateKey' in driver and 'service.attestKey' in driver)
check('SHA256 decoded challenge exactly once', 'SHA256.hash(data: challengeBytes)' in driver and 'challengeBytes.count == 32' in driver)
store=read('App/NativeEnrollmentKeychainStore.swift')
check('device-only no-sync protected journal', 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' in store and 'kSecAttrSynchronizable as String: false' in store)
check('no private key export or SDK delete', all(x not in driver+store for x in ['SecKeyCopyExternalRepresentation','kSecClassKey','SecItemDelete','generateKeyPair']))
model=read('Core/NativeEnrollmentCoordinator.swift')
check('durable before key creation', model.index('try save(next); phase = "generating"') < model.index('await device.generateKey()'))
check('durable proof before enrollment', 'next.phase = .enrolling; try save(next)' in model and 'await service.enroll(proof)' in model)
check('late SDK callback persists original scope', 'preserveSDKResult(next)' in model and 'existing.operationID == next.operationID' in model)
check('revoke requires explicit method and readback', 'public func revokeReviewed()' in model and 'guard readback.state == .revoked' in model)
check('no automatic revoke in lifecycle', 'device.cancel(); busy = false; status = nil' in model and 'func invalidate() { suspend();' in model)
check('normal host has actual enrollment composition', 'NativeEnrollmentComposition.make(owner:' in read('App/AppSession.swift') and 'NativeEnrollmentView(model:' in read('App/NativeMotionReminderViews.swift'))
check('native assertion new strict size gate', 'canonicalBase64(assertion, count: 1...4096)' in read('Core/NativePlatformService.swift'))
fragment=json.loads(read('Resources/NativeEnrollmentLocalizations.fragment.json'));catalog=json.loads(read('Resources/Localizable.xcstrings'))['strings']
check('all enrollment copy bilingual and integrated', all(catalog.get(k)==v and set(v['localizations'])=={'en','zh-Hans'} for k,v in fragment.items()))
for name in checks: print('PASS',name)
print(f'{len(checks)} offline enrollment checks passed. Swift/Apple/runtime tests NOT_RUN; no keys or attestations created.')
