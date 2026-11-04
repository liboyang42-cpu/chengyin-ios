# L9 second group: system notification permission lifecycle

Status: independent lifecycle implementation and offline checks complete;
**Apple device acceptance and the overall L9 launch journey remain unaccepted**.

Public repository: `liboyang42-cpu/chengyin-ios`.
Branch: `codex/l9-original-recovery-20261104`.
Integration base: `eec839502b11f1119a6ede212c768bb3f2de4f29`.
Previous delivered head / parent: `f96a1a04ecb780f1b65d605a0ed80f9fb38ed66e`.
Frozen public backend contract: `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
The final commit SHA is reported after pushing and remote byte verification.

Before this group, public issue #135 still had no assignee/comment and branch
search returned only this existing L9 branch. Integration and lane heads were
checked before implementation and again before publishing. The same worker keeps
this group; no new public claim/comment, PR, or duplicate writer was created.

## Exact whitelist

- `Core/NativeNotificationPermissionState.swift`
- `App/NativeNotificationPermissionNudgeView.swift`
- `Tests/CoreTests/NativeNotificationPermissionLifecycleTests.swift`
- `tools/l9_offline_checks.py`
- `docs/launch/l9-permission-delivery-20261104.md`

No shared AppSession/Composition/PBX/Runtime, workflow/CI manifest, backend,
database, authentication, credential, or dependency file was edited. The existing
SettingsView -> NativeNotificationPermissionEntry -> NudgeView entry, original
NativeNotificationPermissionAdapter and UNUserNotificationCenter methods remain
the only permission flow. The view changes are lifecycle/gesture wiring only;
visual layout, labels and localization tables are unchanged.

## Full independent flow

Appearance/reentry reads the OS state without prompting. Only an explicit gesture
with a current revision and a returned notDetermined snapshot can request the
existing alert/sound/badge options. Denied/provisional/ephemeral/future states
cannot trigger another permission request. An explicit Settings action reads the
OS result afterward; opening Settings is not treated as a permission change.

The destination retires its revision on disappearance. A gesture queued before
leaving cannot act on a replacement visit. Already-started OS operations stay
serialized until their callbacks return; retirement cannot undo an OS effect that
was already submitted. A fresh visit can queue its own read while that operation
drains. Foreground/manual refreshes received while busy coalesce into one later
read instead of being lost. Retirement drops the old queued read.

Cancelled tasks cannot start a read, permission prompt or Settings open. Cancelled
or retired callbacks do not publish success. An interrupted prompt clears its
promptable snapshot and requires another OS read before retry. Open failure and
readback failure retain their separate original localized error meanings. There
is no timer, automatic prompt, device binding, APNs registration or send.

## Verification

```sh
python3 tools/l9_offline_checks.py --swift /path/to/linux/swift-6.2.3
swiftc -frontend -parse App/NativeNotificationPermissionNudgeView.swift
git diff --check
```

Results: **53 XCTest methods, zero failures**, comprising the previous 41 plus
12 new lifecycle methods. The new cases cover normal entry/reentry, pre-start
cancellation, stale gestures, late retired reads, serialized replacement visits,
coalesced foreground refresh, exact post-prompt readback, interrupted prompts,
queued-work retirement, failure/retry and future authorization values. The view
passes syntax parsing; this is not SwiftUI typechecking or device execution.

The first run with Swift 6.2.1 compiled source/tests but failed to link its Linux
Observation runtime with an undefined `swift::threading::fatal` symbol. That failed
run was retained. Repeating with the official Swift 6.2.3 distribution passed using
its real Observation macro and runtime. No source stripping, missing-symbol stub,
link-error suppression, or removed test assertion was used. The broader harness
still has the explicitly documented Linux SHA256/publication adapters for the
previous friend/webhook/push groups; those do not establish Apple framework
equivalence. No application package dependency was changed.

Current group source bytes:

| File | Bytes | SHA256 |
| --- | ---: | --- |
| Core/NativeNotificationPermissionState.swift | 5539 | 624a133770789ea7c88f4543113e218d5cf143b9a8e66552e42b3d2d37533a67 |
| App/NativeNotificationPermissionNudgeView.swift | 3587 | b25f9b8eadf2c4b9c26d3898ea58fc11b7a464426ffc9a1fd78007c455c05cdb |
| Tests/CoreTests/NativeNotificationPermissionLifecycleTests.swift | 9653 | 2bd469859029c3d3166c422cf342f5d2731756ace33a7737a1253625b8409740 |
| tools/l9_offline_checks.py | 6121 | 378d2266dece29ed8aebd2099e6763d8866b88a3007cde3f9f64ddad09fc9b46 |

The earlier `l9-source-hashes-20261104.json` remains a historical receipt for the
first delivery at f96a1a04; its runner hash is superseded by the row above.

## Remaining boundaries and cleanup

Not run: Apple SwiftUI typecheck, Xcode/iOS build, simulator/device permission UI,
real OS Settings transition, CI, live backend, two-account journey, mini-program,
push/webhook delivery, production or money operations. L9's missing frozen friend,
device/outbox and webhook route families, server DM gate/source, progress privacy
and N-02 writer work remain blockers as listed in the first delivery. This group
does not manufacture those contracts or enable default-empty grants.

Publishing uses `[skip ci]` on the existing lane branch, which is excluded from
the workflow push branch list. After publishing, fetch and raw-by-commit downloads
must match each changed local file byte for byte. Only then may corresponding
unchanged local source copies be removed. Cleanup uses exact sparse exclusions
for verified lane-delivered files, preserving unrelated files, local test evidence
and toolchains. No deletion is staged or committed; `git sparse-checkout disable`
restores those tracked copies from the verified commit. The worker reports actual
verification and cleanup counts after these operations finish.
