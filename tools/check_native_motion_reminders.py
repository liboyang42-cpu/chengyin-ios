#!/usr/bin/env python3
"""Offline native protocol/source checks only; never opens devices or a network."""
import hashlib, json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text()
checks = []
def check(name, condition):
    assert condition, name
    checks.append(name)
fixture = json.loads(read('docs/native-platform-v1.json'))
canonical = fixture['canonicalPayload']
check('backend golden SHA-256', hashlib.sha256(canonical.encode()).hexdigest() == fixture['clientDataHashHex'])
check('18 canonical lines and no trailing LF', len(canonical.split('\n')) == 18 and not canonical.endswith('\n'))
core = read('Core/NativePlatformService.swift')
check('exact native action names', 'ISSUE_NATIVE_STEP_CHALLENGE' in core and 'SUBMIT_NATIVE_STEPS' in core)
check('scoped read-only reminder route', 'api/play/advanced/time-window' in core and 'raw["topicId"].integer == topicID' in core)
check('independent default-off capabilities', 'stepsEnabled: Bool = false, remindersEnabled: Bool = false' in core)
check('legacy WeRun validation unchanged', 'case .bingo, .walk, .steps: throw PlayExperienceError.unsupported' in read('Core/PlayKitScreenContracts.swift'))
provider = read('App/IPhonePedometerProvider.swift')
check('genuine iPhone CMPedometer query', 'queryPedometerData(from: from, to: to)' in provider and 'UIDevice.current.userInterfaceIdiom == .phone' in provider)
check('purpose and permission check before query', provider.index('purpose()?.trimmingCharacters') < provider.index('device.queryPedometerData'))
assertion = read('App/AppAttestStepAssertionProvider.swift')
check('existing enrolled key assertion only', 'generateAssertion(deviceKeyID, clientDataHash: hash)' in assertion and 'generateKey(' not in assertion and 'attestKey(' not in assertion)
notifications = read('App/AppleLocalReminderProvider.swift')
check('absolute nonrepeating notification', 'repeats: false' in notifications and 'TimeZone(secondsFromGMT: 0)' in notifications)
check('local pending readback and owned cancellation', 'pendingNotificationRequests()' in notifications and 'removePendingNotificationRequests' in notifications and 'userInfo["owner"]' in notifications)
all_new = '\n'.join(read(p) for p in ['App/IPhonePedometerProvider.swift','App/AppleLocalReminderProvider.swift','App/AppAttestStepAssertionProvider.swift'])
check('no HealthKit or APNs registration', all(x not in all_new for x in ['import HealthKit','registerForRemoteNotifications','HKHealthStore','WCSession']))
model = read('Core/NativeStepCoordinator.swift')
check('frozen unknown-result retry', 'await dispatch()' in model and 'public func retryExact()' in model and 'pending = nil; receipt = native' in model)
check('no local completion/reward mutation', all(x not in model for x in ['["reached"] =','["score"] =','["reward"] =']))
host = read('App/NativeMotionReminderViews.swift')
check('two-stage steps review', 'nativePlatform.steps.consent' in host and 'nativePlatform.steps.send' in host)
check('local reminder explicit opt-in', 'nativePlatform.reminder.consent' in host and 'await stage.enable(reviewed:' in host)
check('legacy subscribed not consumed', 'segment["subscribed"]' not in host)
check('normal and inline environment injection', '.environment(\\.nativePlatformRuntime, session.nativePlatformRuntime)' in read('App/SessionPlayRuntimeView.swift'))
check('pre-start reminder ordinary advanced host', 'NativeTimeWindowHostView(advanced: model, segment: .null)' in read('App/PlayAdvancedView.swift'))
check('session invalidation wired', 'retainedNativePlatform?.invalidate(); retainedNativePlatform = nil' in read('App/AppSession.swift'))
fragment = json.loads(read('Resources/NativePlatformLocalizations.fragment.json'))
catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
check('all native bilingual strings integrated', all(catalog.get(k) == v and set(v['localizations']) == {'en','zh-Hans'} for k,v in fragment.items()))
info = json.loads(read('Resources/InfoPlist.xcstrings'))['strings']
check('bilingual motion purpose preserves existing catalog', 'NSMotionUsageDescription' in info and len(info) > 1)
for item in checks: print('PASS', item)
print(f'{len(checks)} offline contract checks passed; Swift/Apple/runtime/physical-device tests NOT_RUN')
