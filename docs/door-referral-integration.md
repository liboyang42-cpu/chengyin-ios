# Door/referral native package

Status: isolated additive implementation. No main-tree edits, service traffic, permissions, auth changes, signing, entitlement changes or remote writes. Apple compilation, Core XCTest, UI XCTest and device runtime: **NOT_RUN** (Swift/Xcode unavailable). Source checks and supplemental Tree-sitter parsing are separate, non-runtime evidence.

## Exact source evidence

Flutter revision a63e9e91c82a3282e8dd7138f943b1a8cbfc021d:
- `lib/core/router/door_entry.dart:7–34`: one percent-decode, trim, 32 ASCII hex, lowercase; play with activity / topic self-play / topic detail
- `lib/data/models/scan_entry.dart:1–42`: action, topicId, activityId, nodeId; numeric and string IDs
- `lib/data/api/play_api.dart:709–723`: multipart POST /api/play/scan-entry, code; preserve server msg, no progress writes
- `lib/feature/account/door_entry_page.dart:38–116`: restoration wait, generation cancellation, Home fallback, inviter independent of scene
- `lib/core/router/app_router.dart:258–336`: preserve pending startup URI, latest intent wins; /door scene + inviter/id
- `lib/data/api/registration_api.dart:273–294`: multipart POST /api/user/setInviter, inviter_id; exact session scope
- `lib/feature/account/inviter_sheet.dart:17–20,47–63`: explicit one-time manual bind
- `lib/feature/account/pending_inviter.dart:4–83`: guest capture, account claim before send, account-bound truth; explicitly excludes legacy device-global flag
- `lib/data/models/invitation.dart`: invalid/self guards and ambiguous remote-rejection explanation

Conservative hardening: native IDs must be positive integral Int values (fractional IDs are not truncated); unknown/interrupted inviter attempts are durably locked and not automatically retried. No invented status/receipt endpoint is used to clear a lock. No native phone-binding or WeChat getPhoneNumber contract exists in this packet.

## Additive host integration, explicit build manifest

Copy exactly the paths listed in `door-referral-manifest.json`. Core files use existing APIConfiguration, HTTPTransport and AuthRequestBuilder. App files join the existing app target, where Core is also compiled (no QuestifyCore import in App). Core tests join QuestifyCoreTests; UI tests join existing UI target. Merge only new `door.*` keys from the localization fragment into Localizable.xcstrings. Regenerate the project using `python tools/generate_project.py`; never overwrite AppSession, navigation or project files from a different packet.

1. Construct one DoorEntryCoordinator and DoorReferralQueue on MainActor. Inject the existing configured endpoint and a transport with redirects forbidden. The default `scanEnabled=false, bindingEnabled=false` must remain in production. Test fixtures may explicitly set these true only with fake HTTPTransport. No implicit URLSession/default API origin exists here.
2. Build DoorReferralSession from authoritative session state: positive account ID or nil, current token or nil, restored only after initial restoration/loading finishes. Assign a fresh epoch whenever auth/session/token identity changes, including logout/login of the same account. Never derive account from a URL, inviter value or UI language.
3. Supply DoorReferralFileStore an app-private durable path and create its parent directory through the host's normal storage system. Maintain one queue owner per store. Atomic synchronous saves must succeed before dispatch. Do not write tokens to this journal. Do not delete journals on logout or import old global has_inviter; account attempt locks must survive restart. Treat corruption/storage failure as blocked mutation, not an empty journal.
4. OS URLs use DoorLinkPolicy with an explicitly verified HTTPS origin set. Default set is empty; this package does not choose association domains, custom schemes or entitlements. `.onOpenURL` / browsing-web activity attachment is a separate approved runtime integration. Never pass a naked scene string through a generic URL launcher.
5. Supported URL route matrix: HTTPS exact approved origin, no credentials/port/fragment, exact literal `/door`, unique literal `scene`, `inviter`, `id` query keys only. Unknown or duplicate keys are rejected. Inviter takes precedence even if empty. URL scene stays raw until DoorParsing.scene; do not use already-decoded URLQueryItem then decode it again. Double-encoded scenes fail. URL spoofing or unsupported routes should navigate nowhere (host can show the localized unavailable notice), not capture inviter data.
6. Once a valid intent is accepted, independently `try? queue.capture(intent.inviter)` only if a nonempty inviter exists; a capture/storage error must never prevent door routing. `coordinator.receive(intent)` replaces the prior pending scene; preserve it while restoration is incomplete. Update session then resolve. After a restored account changes, pending route is cancelled; do not call receive again for that old intent. A fresh external user intent can be received explicitly.
7. DoorEntrySheet handles initial restore and latest intent but does not capture/refire referral mutations itself. On destination callback, map `.activityPlay(activityID,topicID)` to the existing activity play host, `.topicSelfPlay(topicID)` to topic self-play, `.topicDetail(topicID)` to existing topic detail, `.home` to the existing appropriate Home root. This is typed navigation only. Clear/dismiss sheet; display raw server failure as plain Text (never URL/HTML), localize known door.* fallback keys.
8. Separately call `queue.replay()` after restoration/authentication only under the independent referral activation gate. It claims guest referral to that account first; guest intent cannot jump to another account after failure. Bound/rejected/attempting/unknown entries are terminal for automatic replay. No receipt endpoint, fake success, inferred already-bound reason or automated retries.
9. Manual binding mounts DoorInviterSheet using current session and a production-disabled queue. Explicit review confirmation is required by UI. Host must dismiss/recreate sheet on account/epoch changes; close/disappear cancels the UI task, but any already-dispatched attempt remains locked. Do not unlock via a Retry button. The backend remains authoritative about one-time binding.
10. Existing scanner capture is unchanged. At its verified result callback, pass a raw 32-hex scene to DoorParsing.scene and receive a DoorIntent, or parse a full URL through DoorLinkPolicy. Do not feed arbitrary QR text into URLs, scan gameplay, or inviter binding. No live camera tests or permission prompts belong to this package.
11. DEBUG only: route `--door-referral-fixture` to DoorReferralFixtureView before normal tabs. UI fixture uses no transport, camera or auth. Remove the long-press requirement if the test runner's keyboard insertion differs; the intended assertion is simply invalid scene -> invalid label. Additional Apple acceptance should cover manual review, double-tap, dismiss while pending, auth restoration, session changes, newer scenes, failure/Home notice, and accessibility/text expansion in both languages.

## Validation

Run `python tools/check_door_referral.py --root <packet> --flutter <app-audit>` and the pinned supplemental parser over manifest Swift files. After integration on an Apple toolchain run Swift package tests and Xcode build/UI tests. This packet includes authored fake-transport tests but their existence does not mean they executed. Fixture domains example.test are only supplied to fake transports; no requests were sent there.
