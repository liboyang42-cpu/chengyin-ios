# Native play/session vertical slice

## Scope and source evidence

Local code migration only. No live requests, purchases, starts, permission requests, proof collection, Mac access, commits or pushes were performed. Existing shared root navigation, AppSession, String Catalog and generated project are left for the integrating owner.

Source reviewed in the preserved Flutter checkout:

- `lib/data/api/play_api.dart`: `fetchNodes`, `fetchTopicNodes`, `_nodesResult`, `fetchRouteState`, `submitAnswer`, `submitTopicAnswer`, `_exactSession`, `_routeFormFields`
- `lib/data/models/checkin_models.dart`: `PlayNode`, `PlayNodesResult`, `PlayRouteState`, `CheckinReward`, chapter `name`/`chapterId`
- `lib/data/models/play_route_state.dart` and `lib/feature/play/play_session_page.dart`: separate branch-authority read, hidden/locked/playable/completed projection
- `lib/feature/play/play_empty_state.dart`: malformed nodes vs actual empty nodes; registration precedes empty; business 402 differs from HTTP 402
- `lib/feature/play/play_gap_logic.dart`: mode 2 onsite flow; validation method dispatch; unknown methods cannot fall back to GPS
- Source contract tests: `play_business_code_test.dart`, `play_route_api_test.dart`, `play_route_retry_test.dart`

## Implemented

A native SwiftUI session overview with server progress, route status, topic description, expiration text, chapter association and node cards. Task detail presents server narrative, rules, requirements, question and eligible text/choice inputs. It has completed, locked, currently unavailable, unknown, registration-required, pass-required-or-expired, authentication-expired, empty, error and unconfigured paths. A route marked COMPLETED is terminal; another non-ACTIVE branch status is displayed as unavailable with the raw status. No timezone or expiration reason is inferred from a date string.

Contracts accept source-supported numeric string integers and boolean forms, preserve missing optional values, and reject malformed required arrays/IDs. Unknown validation/route/config states never authorize a completion operation. No response message is used to infer authentication, payment success or navigation. Server text is displayed literally.

Reads:

- `GET /api/play/nodes?activityId=<positive ID>` or `?topicId=<positive ID>`
- For a branch response, `GET /api/play/route-state` with the same exact scope; the route session ID must match and version must not regress

One deliberately narrow mutation is implemented behind an integration-time opt-in and explicit Submit button:

- `POST /api/play/answer`, multipart form fields: exactly `activityId` **or** `topicId`, `nodeId`, `answer`
- Only a fresh, active, linear mode-1 text/choice node with `done == false`, a server question, a valid option key where applicable and no unmet known prerequisites
- No outcome, target node, fabricated code, coordinates, idempotency token or proof is sent
- Typed text is sent unchanged; validation trims only to reject all-whitespace input
- Successful receipts are shown separately. Progress only changes after another server nodes read

Every write attempt invalidates the loaded action snapshot. Accepted or uncertain writes remain blocked until a later read confirms that specific node completed. A decoded business rejection permits another explicit attempt only after a fresh read. No automatic mutation retry exists. The unresolved-attempt guard is in memory for the lifetime of the scoped reader; it is not a durable cross-launch idempotency store. Keep production answer dispatch disabled until an approved integration/acceptance decision. Do not recreate the reader to clear an uncertain result.

## Intentionally unavailable

Branch answer mutations await the source route-token conflict and uncertain-outcome recovery workflow. Mode-2 shop-day verification, QR arrival, GPS arrival, photo/upload, sensor challenges, preferences, advanced sessions, media playback, paid hints, reveal-with-score-effects, pass purchase, signup, session start/restart, rewards refresh outside this slice, endings and leaderboards are not implemented. They display an explanation rather than performing a different validation method. No API default host, location permissions, scanner, web view, remote image request, polling or hidden completion action is added.

The reference comments describe topic `/nodes` as establishing a self-play session; do not treat that endpoint as an anonymous generic catalog read. The integration must supply a known user-selected activity/topic entry and authenticated session. This work never called it against a live backend.

## Root integration contract

1. Merge `play-localizations.json` (`[{key,en,zh-Hans}]`) into `Resources/Localizable.xcstrings`; regenerate the Xcode project so the new `Core/Play*.swift` and `App/Play*.swift` files are in the app target
2. Create one stable `PlaySessionReader` per navigation entry. Its immutable `scope` is `.activity(activityID)` for a known selected activity or `.topic(topicID)` for a known selected self-play topic. IDs must be positive. Never derive one ID from the other, use arbitrary defaults, or let the user type an unverified internal ID into a generic launcher
3. Pass optional `PlayService(configuration: approvedConfiguration, transport: existingNoRedirectTransport)`. Nil produces a native unconfigured screen. No default production service is supplied
4. Supply `currentSession` from the live AppSession token snapshot using `PlayReadSession(accountID:epoch:token:)`; the epoch must advance for logout, expiry and every authentication attempt, including same-account relogin. Do not log or persist this wrapper
5. In `onUnauthorized`, expire only if the captured `PlayReadSession` still equals the live session. The reader also checks cancellation, generation and the full captured credential before dispatching that callback
6. Mount `PlaySessionView(reader: reader)` inside the existing NavigationStack. `.id(reader.identity)` may be used on the entry container if the root rebuilds account-specific navigation. Pass a stable reader instead of constructing one in a computed body on every refresh
7. `answersEnabled` defaults to false. The reader and UI are therefore read-only unless the integrating owner explicitly opts in. DEBUG fixtures enable only the fake transport. Integration may add verified upstream activity/topic navigation callbacks; do not add purchase/start mutations or use a catalog list as an owned-session entitlement
8. Preserve the reader while a result is uncertain. Reconstruct only for a genuinely new navigation/account scope, and disclose that durable cross-launch reconciliation is still absent

DEBUG host: add `play` to the existing DEBUG module router and mount `PlayFixtureHostView()`. It accepts `--uitesting-play-scenario <scenario>` with default `success`. The fixture uses real decoders/service/reader and a fake in-memory HTTP transport. It never instantiates URLSessionTransport. The fake URL is only a valid URLRequest construction base.

Scenarios: `success`, `choice`, `empty`, `error`, `expired`, `passRequired`, `registrationRequired`, `locked`, `terminal`, `unavailable`, `unknown`, `branch`, `media`, `advanced`, `loading`, `readbackError`, `uncertainAnswer`, `unconfigured`.

## Verification

Added 30 pure Swift tests covering wire shapes, optional facts, source booleans, exact scope, text/choice eligibility, unsupported proof gates, branch hiding/authority/version/session identity, terminal states, XP absence, GET/multipart payloads, business/HTTP distinction, malformed receipts, account/epoch/token changes, stale 401, latest-wins loads, opt-in mutation, duplicate prevention, uncertain write/readback, definite rejection and cancellation.

The local cloud container has no `swift` or Xcode toolchain. `swift test --filter Play` could not run (`swift: command not found`). No claim of compilation, simulator, accessibility, UI runtime or live-backend verification is made. Local static checks validate localization coverage, JSON, allowed file scope, no forbidden dispatch surface, and project/catalog inclusion in a temporary integration copy; those are not compiler tests.

Required acceptance in an approved toolchain after root integration:

- `swift test --filter Play`, then full `swift test`
- Unsigned iOS simulator build and targeted XCUITests; no device permissions or live accounts
- Both locales, large Dynamic Type, dark mode and VoiceOver reading order
- Success fixture: node 701 text task -> Submit -> receipt/readback -> completed node and unlocked node 702 -> exact choice key -> completed route
- Repeated Submit while in flight, navigate back during response, account switch during load/submission, logout/relogin, hidden branch node, missing media, malformed/empty route, readback error and uncertain answer
- Verify an unresolved answer cannot be resent after a stale incomplete read; refresh stays read-only until completion is confirmed
- Any later live service activation, cross-launch reconciliation, branch writes or physical proof flow is a separate acceptance gate
