#!/usr/bin/env python3
"""Static source checks (not Swift execution) for W09.5/W09.6 NPC pre-send sensitive-info guard."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[2]
checks = 0
def check(value, message):
    global checks
    assert value, message
    checks += 1
core = (ROOT/'Core/SafetyDisclosure.swift').read_text()
shop = (ROOT/'App/ShopNPCView.swift').read_text()
merchant = (ROOT/'App/MerchantNPCViews.swift').read_text()
ops = (ROOT/'App/OpsSafetyViews.swift').read_text()
tests = (ROOT/'Tests/CoreTests/AIOutgoingSendGateTests.swift').read_text()
gate = core[core.index('public struct AIOutgoingSendGate'):core.index('// MARK: Offline safety')]
check('AIOutgoingTextScreen.findings(in: text)' in gate, 'gate uses the existing screen')
check('held.text.utf8.elementsEqual(text.utf8)' in gate and 'held.scope == scope' in gate and 'held.request == request' in gate, 'bound to exact text, scope, request')
check('defer { pending = nil }' in gate, 'single use')
for banned in ['UserDefaults', 'print(', 'NSLog', 'URLSession', 'FileManager', 'Logger(']:
    check(banned not in gate, 'gate: ' + banned)
for name, src in (('shop', shop), ('merchant', merchant)):
    check('AIOutgoingSensitiveConfirmation(findings: $sensitiveFindings, send: confirmedSend, cancel: cancelSensitiveConfirmation)' in src, name + ' modifier')
    check('sendGate.confirm(text:' in src, name + ' confirm rechecks')
    check(re.search(r'\.onChange\(of: (draft|text)\) \{ _, _ in cancelSensitiveConfirmation\(\) \}', src), name + ' edit invalidates')
    check('.onDisappear { cancelSensitiveConfirmation();' in src, name + ' exit invalidates')
    for banned in ['UserDefaults', 'NSLog', 'print(']:
        check(banned not in src, name + ' ' + banned)
check('guardedSend(current: { (draft, nil) })' in shop, 'shop input check')
check('guardedSend(current: { finalText(of: review) })' in shop, 'shop final review (reuse/regenerate/edit) check')
check('clearTransient() { cancelSensitiveConfirmation()' in shop and 'func suspend() {\n        cancelSensitiveConfirmation()' in shop, 'shop scope/suspend invalidates')
check('guardedSend(current: { (text, nil) }, request: nil)' in merchant, 'merchant input check')
check('request: capturedRequestID)' in merchant, 'merchant retry check')
check('.onChange(of: model.coordinator.scope)' in merchant, 'merchant scope invalidates')
check('var cancel: () -> Void = {}' in ops and 'findings = []; cancel()' in ops, 'edit keeps text and cancels')
check('send: () -> Void' in ops and 'findings = []; send()' in ops, 'confirm calls existing send')
for name in ['testTextChangedAfterConfirmPromptCannotSend', 'testAccountChangedAfterConfirmPromptCannotSend',
             'testCancelThenSendCannotUseOldConfirmation', 'testRegenerateThenFinalSendNeedsFreshConfirmation']:
    check(name in tests, name)
print(f'check_npc_send_guard: PASSED ({checks} checks)')
