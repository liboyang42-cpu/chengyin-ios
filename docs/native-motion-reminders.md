# Native iPhone motion and local reminders: code preparation only

This increment implements the user-approved iPhone-only CMPedometer and one-time device-local reminder adaptation. It does not enable a production endpoint, request permission, enroll an App Attest key, record real steps, schedule a real notification, grant a reward, or publish a release. The normal app dependency composition remains nil/default-off.

## What is implemented

- Ordinary `SessionPlayRuntimeView` injects a session-owned native runtime through SwiftUI environment. Both navigation and chapter-inline PlayKit screens receive the same accepted configuration. `PlayAdvancedView` also exposes a pre-start reminder body when accepted reminder composition is provided, so a closed opening window does not require starting gameplay first
- Native `.steps` uses `IPhonePedometerProvider` with `CMPedometer.queryPedometerData`, iPhone-only availability, purpose-key checks, explicit user gesture, denied/restricted/unsupported states, generation-fenced cancellation and no HealthKit or Apple Watch source
- Two stages: review the purpose and read this iPhone, then inspect the cumulative count/server day and explicitly send the audit sample. Background, clock changes, account/token/epoch changes, unexpected server versions and expiry invalidate transient readings
- An already enrolled App Attest key can sign the exact native backend v1 payload. There is no key generation, enrollment, credential provisioning or production verifier. The assertion binds app/key/request integrity; neither it nor CMPedometer cryptographically proves walking
- HTTP adaptation has independent step/reminder gates, exact action allowlists, request/response scope validation and immutable idempotency envelopes. Uncertain sends retain the exact request/assertion/key for retry instead of issuing a fresh sample
- Local reminders fetch the authoritative server timezone and next opening, show the exact reviewed instant, request alert/sound only after explicit opt-in, add a nonrepeating UTC calendar trigger and verify pending readback before displaying success. The local scheduled state never reads or writes WeChat `subscribed`
- Cancellation, replacement via new opt-in, changed server window, expiry, denied permission, late permission/add callbacks and logout all remove the applicable request. Other notification namespaces are untouched. Generic notification text avoids revealing route/account details on the lock screen
- Session/foreground reconciliation and significant-time-change handling cancel stale schedules. Server changes while the app is closed cannot update an already scheduled local reminder; the user-facing purpose explains this limit. No silent background execution, server push, APNs token or delivery guarantee is claimed
- Bilingual screen catalog and system motion-purpose text, preserving existing InfoPlist localization keys

## Exact backend contract and readiness

Reference implementation is the private backend `migration/native-ios-platform` adaptation branch at `2cd0d28327daf46e417d4673aca621a27a244ff7` (PR #1188). Its owner verified the published commit, ten CI checks and both Funds checks, and compared the shared vector byte-for-byte. It is **undeployed** and does not represent deployed contract acceptance. The native request boundary now matches its assertion limit of 16,384 base64 characters and cumulative count limit of 100,000. The separate actual App Attest verifier follow-on remains unpublished; no enrollment or verifier availability is claimed.

`POST api/play/advanced/action` keeps the existing authenticated envelope `{sessionId,version,idempotencyKey,action,payload}`. New actions are `ISSUE_NATIVE_STEP_CHALLENGE` and `SUBMIT_NATIVE_STEPS`; `SUBMIT_STEPS` and its WeRun proof requirements remain unchanged and rejected by the native legacy validator.

The new challenge binds provider `IOS_CMPEDOMETER_V1`, account, device key, session, attempt start, server business day and resulting session version. It has a <=120-second lifetime capped at day end. Native checks server day/timezone boundaries and a 0..100000 integer count. Backend additionally enforces 30-second minimum sample/challenge intervals, 240 challenges per day, monotonic bounded deltas, nonce consumption, transactional counter/CAS replay checks and no device reset fallback. First verified sample is baseline-only; new service day starts a fresh zero-credit baseline.

`NativeStepCanonical` joins exactly 18 server-scoped/sample/request fields with LF and no trailing LF. `AppAttestStepAssertionProvider` SHA-256 hashes those bytes and calls `generateAssertion` with the already-enrolled key. The synthetic shared `native-platform-v1.json` vector is authorized test data, not a genuine Apple assertion. Its hash is `4b1f0eab9f480291c632216a2445ebb8c16a2c9ee7b838af43f1fa6bc7f8dce7`.

`GET api/play/advanced/time-window` uses `activityId` (zero for self-play), positive `topicId` and `nodeId`; returned scope must match. Fields are `enabled`, `notificationProvider=LOCAL_ONLY`, `serverNow`, `timeZone`, `openNow`, `nextOpenAt`, `nextCloseAt`, `windowVersion` and optional `stateVersion`. The server computes wall-clock/overnight/DST policy. No phone-timezone inference or 24-hour recurrence is used. A pre-start opening-chapter prerequisite returns `409/TIME_WINDOW_OPENING_REQUIRED`; the native view asks the user to enter the normal journey opening first and retry. The read never creates a route session. Disabling or changing the server window cancels the old local schedule and requires a new explicit review.

### Important product boundary

The native server protocol is deliberately audit-only: `rewardEnabled=false`, `status=AUDIT_ONLY` only with both gate and ready verifier. It cannot set `steps.reached`, score, task completion or reward. This increment therefore does **not** claim completed native steps-game parity. A reviewed production verification/enrollment implementation, trust/reward policy, legal purpose approval, deployment, physical-device acceptance and explicit activation remain necessary.

## Source reconciliation

The Flutter source is read-only context, not a template for copying its presentation. Existing walking/time-window widgets show business goals/opening labels, but platform-native handling is implemented independently. Current mini-program/backend derived requirements retain WeRun proof and WeChat subscription semantics; neither is imitated on iOS.

Read-only Flutter baseline `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d` inspected locally:

| Source | SHA-256 | Derived requirement |
| --- | --- | --- |
| `lib/feature/play/advanced/fullscreen/playkit_walk_view.dart` | `b5abbb2aed73f0e0f3541da48f704b2a2d7c68845a47d89bc790797917392d60` | Walking progress presentation is separate from proof |
| `lib/feature/play/advanced/fullscreen/playkit_timewindow_view.dart` | `66fbb3719f51653b615220fd771bce0c4d2403173612e82555205a2d7d51b5eb` | Opening/closing source labels; native must obtain explicit server timezone/instant |
| `lib/feature/play/advanced/playkit_host.dart` | `896150aa2a1341298d132311f350d255c138969876d2ce5d53e7e0776418e8b3` | Existing steps action is distinct and must stay unchanged |

The new backend contract was coordinated directly with its sole implementation owner; only its synthetic cross-client fixture is copied. No private backend or mini-program implementation is copied into the native deliverable.

Apple primary references: [CMPedometer authorization](https://developer.apple.com/documentation/coremotion/cmpedometer/authorizationstatus()), [calendar-trigger readback](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger/nexttriggerdate()), [App Attest server validation](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server).

## Validation

See `native-motion-reminders-verification.json`. Offline contract checks, Tree-sitter parsing and generated-project structural checks are supplementary and are not Swift compiler or Apple-runtime evidence. Domain/App-unit/UI tests are authored and must run in the Apple CI owner's next integrated cycle. All UI fixtures use synthetic in-memory HTTP, pedometer, assertion and notification providers; no fixture calls OS permission or hardware APIs.
