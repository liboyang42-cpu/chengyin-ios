# Integrated status (2026-10-02)

The additive files are now present in the main local checkout. AppSession supplies a retained, disabled review coordinator and durable app-private lock file; Home passes it through the existing official browser to detail, published and inbox screens. Current-account read preflight is implemented. The new synthetic launch route bypasses production AppSession. Project/catalog registration is complete. No live write transport is wired. Arrival and merchant invitation host reads intentionally throw disabled until verified upstream integrations exist. The instructions below remain the integration contract for future enablement, not permission to enable.

Validation: 276 Python contract checks and 16 tool tests PASS; structural regeneration PASS (459 Xcode Swift sources, 3997 keys). All changed Swift files parse without recovery. Whole-checkout supplementary parsing reports the same six unrelated files/ten diagnostics; this is not a Swift compiler result. 1521 core and 233 UI tests authored; Swift/Xcode runtime NOT_RUN.

# Official actions: additive host integration

This folder is an additive module for `chengyin-ios`. It deliberately does not replace the existing official list/detail/joined/published/inbox/stats readers. No remote calls, location operations, uploads, invitations, broadcasts or participation mutations were executed during implementation.

## Files and targets

1. Copy `Core/OfficialAction*.swift` (4 files) into the existing `Core` directory. The existing Swift package discovers them automatically. Required existing types: `OfficialEvent`, `OfficialPartyInvite`, `OfficialStatisticValue`, `HTTPTransport`, `APIConfiguration`, `AuthRequestBuilder`.
2. Add `App/OfficialActionViews.swift` and `App/OfficialActionFixtureHost.swift` to the iOS app target; do not put them in the core package. Native screens use Form, Section, NavigationStack, system fields/pickers, dynamic text, 44-point controls and accessibility identifiers.
3. Merge the `strings` object from `Resources/OfficialActionLocalizations.fragment.json` into the app's existing String Catalog. Reject duplicate keys with differing content; do not replace the catalog. All 74 new keys include English and Simplified Chinese.
4. Copy `Tests/CoreTests/OfficialActionTests.swift` into the existing package test target and `Tests/AppUITests/OfficialActionUITests.swift` into the UI target.
5. In the DEBUG launch-argument router, add a branch for `--official-action-fixture` that displays `OfficialActionFixtureHost()`. This fixture is entirely synthetic, has writes disabled, and never constructs a network transport. It does not replace production routing.

## Access and session boundary

Construct `OfficialActionInjectedAccess` with `enabled: false` (default). The low-level `OfficialActionService` and tracking adapter independently default off. Do not enable any production route as part of this merge. Supply no global/default URLSession transport.

- `current`: current account ID, session epoch UUID and stable environment/storage namespace. A token refresh, logout, account switch, region/API origin switch must invalidate the epoch. Namespace must separate environments. Never use the access token as namespace.
- `read`: fetch a fresh source-backed snapshot for the exact command. Use existing OfficialEventService methods: `canPublish`, event `detail`, and current-account `partyInbox`. A publish, broadcast, merchant invite or OFFICIAL response requires fresh canPublish == true. A party response target must be present in the current account's inbox. A broadcast bound to an event requires the exact event, verified from the current account's published events; never substitute a public event with the same displayed title. Verify each selected merchant through authorized current merchant sources; snapshot.merchantIDs must exactly equal the reviewed ordered IDs. There is no invented merchant search endpoint here.
- `write`: capture the same identity and token, recheck it immediately before invoking the injected adapter. Do not log body, token, invite reason, coordinates or recipients. Do not implement retries. After any credential invalidation cancel/destroy this coordinator and its sheet.
- Keep one coordinator per active identity subtree and apply `.id(sessionEpoch)` at the subtree's root. Call cancelReview before navigation dismissal or identity transition. Clear draft/review/receipt UI on account change, including same-account relogin. Current-identity reads are revalidated after every await.
- Instantiate `OfficialActionFileLocks` with a private Application Support file URL in an already existing protected directory. Do not synchronize, clear on logout, or share across installations. Retain its stable path across launches; do not use a temporary directory in production. Storage errors fail closed. Use one writer/coordinator per application process and namespace.

## Native entry points (add alongside, not instead of readers)

- Existing published screen: after canPublish returns true, present `OfficialPublishEditor(coordinator:)` or `OfficialBroadcastEditor(coordinator:)`. The publishing editor edits an UNSENT draft; there is no supplied persisted-event update endpoint. Publishing and broadcasting are separate reviews and requests; publish never automatically broadcasts.
- Existing event detail Form: append `OfficialParticipationActions(coordinator:event:arrival:)`. Inject the latest event from the existing reader. Pass arrival nil by default. Legacy completion requires explicit signed == true, live status 3, not paused, not V2, and not roam-bound. Signup requires explicit signed == false and status 2/3. Unknown state fails closed.
- Existing inbox Form: append `OfficialInviteResponseActions(coordinator:invite:publisher:)`. OFFICIAL routes to lowercase organizer accept/decline; MERCHANT/CLUB route to uppercase parties ACCEPT/DECLINE/WITHDRAW. Other types never expose commands.
- Merchant invitation entry: `OfficialMerchantInviteEditor(coordinator:candidates:)` takes already verified synthetic/authorized candidates. Only explicit selections go into merchantIds. Reverify those IDs in read. Source API accepts a map; the only tested merchant invitation field is merchantIds. Do not claim richer event/contract invitation authoring without additional source contracts.
- Arrival evidence must come from the existing approved roam/session/location integration. It includes the exact current account epoch, event ID, mission code, current server roam session ID, stable request ID, approved coordinates, accuracy, and a host-controlled freshness expiry. Never fabricate a session, generate a new request ID to get around a lock, request permissions or collect location from this module. Verify the session is still current in `read` before returning the snapshot. The review reveals the exact location payload before confirmation.

## Completion and unknown outcomes

The review captures immutable command, exact body, account epoch and facts. Confirm does fresh preflight; any changed snapshot requires a new review. The disk lock is written before dispatch. Repeated taps, cancellation and stale identity cannot reuse a review.

Malformed responses, transport failures, cancellation/identity change after dispatch and ambiguous HTTP responses retain an account+namespace+scope lock across relaunch/relogin. There is no Retry or Reset button. A received explicit business rejection releases it only if persistence succeeds. No receipt/recovery/reconcile endpoint is invented.

Validated publish IDs, broadcast IDs and invitation IDs establish those commands' acceptance and release their lock; this never means cover approved or notification delivered. Generic signup/complete/party acknowledgment and arrival responses remain conservatively locked. They do not mutate `signed`, mission progress, eligibility, rewards, arrival or attendance in the existing model. Refresh the original source readers independently after acknowledgment. Unlocking a participation/party operation based on independently verified server facts is intentionally deferred to a separately reviewed reconciliation policy; do not silently remove these locks. An unrelated broadcast failure cannot rerun publish.

## Verification

Run `python3 tools/check_official_actions.py` from this module for source/static checks. Run the project Swift syntax preflight with explicit file arguments (this folder is not a git checkout). On a Mac, after adding files run `swift test` in the target package and the three new XCTest UI tests on the fixture route in both English and Simplified Chinese. Then test VoiceOver, accessibility text sizes, sheet dismissal, account/epoch transitions, read/write races, network disconnect after send, relaunch with locked state, and interrupted preflight. These runtime stages are NOT_RUN here because Swift/Xcode/simulator are unavailable.
