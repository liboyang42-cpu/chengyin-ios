# Read-only personal-center batch

## Implemented

Three authenticated native child flows, with injected services and no live backend dependency:

1. My orders: all own activity/topic orders, including unpaid orders; list → fresh detail read; known/missing amount; server order text; schedule/location/contact/verification/payment/refund record fields
2. Participant information: list → fresh owned-record detail, including an existing address if present
3. Badge wall: identity cards, city medals, achievements → native static detail; locked/unlocked state and source conditions; explicit medal-only partial failure

Each remote screen has a concrete loading root, empty/error states, explicit retry/refresh, cancellation/generation guards and account-session scoping. The account menu uses native NavigationLink; list/detail uses native List, LabeledContent and ContentUnavailableView. Labels are supplied in English and Simplified Chinese in `profile-localizations.json` as `[{key,en,zh-Hans}]` for the root catalog merge.

## Retained-source evidence

Paths are relative to the retained Flutter root, inspected 2026-10-01:

- `lib/feature/profile/profile_page.dart`: profile routes `/orders` and `/badges`
- `lib/core/router/app_router.dart`: `/orders`, `/address`, `/address/edit/:id`, `/badges`, `/badge`, `/tickets`, `/ticket/:id`
- `lib/data/api/activity_api.dart`, `orderList` and `ticketInfo`: multipart POST `/api/registration/list` with `owner_type=3`; multipart POST `/api/registration/info` with `id`
- `lib/data/models/activity.dart`, `MyRegistration` and `RegistrationDetail`: `data` list or `data.rows`, `cmsActivity` before `cmsTopic`, numeric monetary fields, registration/verification fields, server-enriched order text and optional refund facts
- `lib/feature/orders/order_list_state.dart`: order-list refund codes 1/4 refunded; 2/3 processing; payout 0 is present and different from no refund application. Native detail leaves unknown codes unknown and also preserves their raw value
- `lib/data/api/address_api.dart`: bodyless POST `/api/user/address/list`, `data.rows`; multipart POST `/api/user/address/info` with `id`; `province` is the complete region string; stored rows are shared with participants
- `lib/feature/account/address_list_page.dart`: the route is participant information for registration contact/on-site verification, not a shipping-address book; no default badge/switch in source UI
- `lib/data/api/badge_wall_api.dart`: POST `/api/badge/wall-v2` and `/api/medal/wall`, JSON `{}` body
- `lib/data/models/badge_wall.dart`: identity fields and medal fields; source scalar numeric/string/bool compatibility
- `lib/feature/p3/badges/badge_wall_controller.dart`: identity is required; medal failure is partial, never an empty full-success wall
- `lib/feature/p3/badges/badge_wall_logic.dart`: identity collection only from wall-v2; `kind=achievement` differs from city medals and must not borrow city-node conditions
- `lib/data/api/account_api.dart`: inspected, but its cancellation/consent/player-code endpoints are not used. Player-code POST can generate/reuse stored code, so it is deliberately outside this read-only batch

These are client contract observations, not live server acceptance evidence.

## Deliberate boundaries

- No account deletion, profile/participant edits, add/delete/default-address mutation, consent submission, QR issuance, payment, refund submission, cancellation or live account/backend calls
- No production default host, new credential storage or credential logging
- All order types remain visible; `owner_type=3` is never replaced by the paid-only tickets scopes 1/2
- Missing amount is unknown; numeric zero is distinct. No currency/unit conversion is inferred. UI reuses the existing AmountLabel with its explicit unconfirmed-currency note
- Missing and future registration statuses remain unknown; registration, verification, payment and refund are shown as distinct facts, never used to attest settlement or permit a write
- Detail responses must return the requested positive ID; missing/null/malformed success data fails instead of producing fake empty content
- No computed date-based order lifecycle, eight-tab filter parity, entitlements, team management, order write actions or 3D badge renderer in this batch
- Dates remain source strings. The module does not reinterpret a timezone-free server timestamp in the device timezone
- Source server strings display literally, not as localization keys; network/debug error descriptions are not exposed
- Remote badge icons use HTTPS only without embedded credentials; missing/unsupported URLs show a native symbol rather than inventing artwork
- Duplicate/missing badge codes are not invented; list identity is the stable order of the current immutable snapshot, including duplicate medal-template occurrences

## Root integration

Do not create a new NavigationStack inside AccountView. Insert `ProfileAccountLinks(reader: session.profileReader)` into its existing Form and remove/replace only the matching pending-features placeholder. Keep the account root identity scoped to the signed-in session so old navigation cannot survive account replacement.

`ProfileSessionReader` is public and main-actor isolated. Add a `ProfileService?` beside the other services in AppSession, initialized from the same explicit APIConfiguration and no-redirect URLSessionTransport. Leave it nil when configuration is absent. Construct the reader in AppSession, where private token/gate access is available:

```swift
lazy var profileReader = ProfileSessionReader(
    service: profileService,
    currentSession: { [weak self] in
        guard let self, let account = self.account, let token = self.token else { return nil }
        return try? ProfileReadSession(accountID: account.id,
                                       epoch: self.gate.currentStamp, token: token)
    },
    onUnauthorized: { [weak self] snapshot in
        guard let self,
              self.gate.isCurrent(snapshot.identity.epoch),
              self.account?.id == snapshot.identity.accountID else { return }
        self.expireIfMatching(error: APIError.unauthorized,
                              stamp: snapshot.identity.epoch, credential: self.token)
    }
)
```

The reader verifies captured account + token + epoch before returning values or handling unauthorized. The epoch must advance on logout, expiry and every login, including same-account relogin. A stale 401 never expires a newer session. `identity` is the public nonsecret view refresh key; the credential is private to the Core reader. `onUnauthorized` executes synchronously after the matching-session check on MainActor.

An alternative is to make AppSession implement ProfileReading directly, retaining the same freshness checks. Do not expose tokens to SwiftUI or instantiate a new backend client in each screen.

After merging, root must merge localization entries and regenerate the Xcode project using the existing generator. No project/catalog/workflow/shared navigation files were changed in this worktree.

## Offline acceptance harness

`ProfileFixtureHostView(scenario:)` exists under `#if DEBUG`, using ProfileFixtureReader without networking or stored credentials. Scenarios: `success`, `empty`, `error`, `partial`, `unauthorized`, `unconfigured`. Root can mount this only behind its existing explicit UI-test/debug entry routing. Do not add it to release navigation.

Recommended root simulator assertions:

- `profile.open.orders` → `profile.order.901` → order detail; back → `profile.order.902` shows unknown price/status; refresh and repeat navigation
- `profile.open.participants` → `profile.participant.911` → contact and stored full-region/address; no add/delete/default controls
- `profile.open.badges` → `profile.badge.identity.0`, locked detail; city medal and achievement details are separate groups
- Empty scenario: `profile.orders.empty`, `profile.participants.empty`, `profile.badges.empty`
- Error scenario: leaf labels `profile.orders.error`, `profile.participants.error`, `profile.badges.error`, corresponding `.retry` controls; repeated retry remains usable
- Partial scenario: `profile.badges.partial` plus identity row, no fabricated empty medals
- Unconfigured/unauthorized: explanatory state with no request/retry loop
- English/Chinese, dark mode, accessibility text sizes, VoiceOver, slow reads, navigation away during load, logout/account switch during load

## Verification

Synthetic XCTest coverage covers contract decoding, owner/price/status unknowns, participant shared rows, badge family semantics, request endpoints/bodies/credentials, business versus HTTP failures, response-ID matching, malformed envelopes, badge partial failures/cancellation, same-account relogin, changed credentials, logout and stale unauthorized handling.

No Swift or Xcode executable is available in this cloud worktree. XCTest and SwiftUI compilation/simulator checks are therefore **not run locally**; root CI must run `swift test`, unsigned simulator compilation and the fixture UI checks before this is considered verified native behavior. Static JSON/localization/source checks are reported separately in the handoff.
