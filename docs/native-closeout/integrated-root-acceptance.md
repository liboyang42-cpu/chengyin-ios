# Integrated normal-root synthetic acceptance

This bounded DEBUG-only journey uses `QuestifyApp` → `AppSessionContainer` →
`SessionRootView`, the actual phone-entry sheets and normal Home, activity detail,
manual-area Roam, Play and Account order destinations. It does not mount a separate
feature fixture host or sign in from a fixture task. Its visible evidence strip
only reads the sealed transport ledger and session state; it has no action buttons.

The one launch selector is `--uitesting-integrated-native ready` (or `denied`). It
selects a fixed typed synthetic composition at `https://native-acceptance.example/native`.
No argument accepts a deployment URL, token, capability, account projection or
response. Unknown modes fail closed to `denied`. An explicitly supplied composition
wins over this selector. All fixture implementation is excluded from Release.
`RegionalLaunchConfiguration`, production grants, transport policy and normal
session/navigation implementations are unchanged.

## Scope and safety boundary

- One in-process recorder handles only canonical synthetic SMS-send action, phone exchange,
  authoritative account readback, logout, six Home reads, activity 21 detail,
  a manually entered area read, activity 21 Play nodes/route-state, and owner-only
  registration list/fresh detail. Unexpected endpoint/method/body/identity reaches
  a recorded failure, never a generic success or a real-network fallback.
- The two fictitious input numbers, static one-time code, accounts 7/8 and synthetic
  tokens are test values. The normal Send code button makes one `api/sms/send`
  request to the in-process recorder; there is no SMS provider delivery or real
  credential input. Phone exchange includes positive provisional `data.id`, then
  the bodyless `userInfo` response supplies matching authoritative `appUser.userId`
  and role before anything is persisted.
- Manual-map and owned-order leases bind exact current owner, epoch, namespace,
  base URL, market, role and token. Play has an independently retained per-context
  read issuance and only nodes/route-state endpoint capabilities. No mutation,
  payment, GPS, sensor, upload, provider or routing grant is supplied.
- The UI case switches the normal Roam presentation to list mode before entering
  the center; it does not request device location or show a provider permission.
  The recorder proves the app API request boundary only. It does not instrument
  every operating-system, SDK, DNS or MapKit tile request, and is not a claim of
  whole-device zero network traffic.
- Token storage is in memory; defaults use a fresh dedicated synthetic suite.
  Logout clears token/account/manual area and revokes retained order authority.
  A new launch starts empty. No production keychain factory is selected.

## Authored acceptance cases

Three UI cases are discovered by the existing dynamic class-level sharder:

1. Type the phone number, tap Send code, observe the synthetic success UI, type the
   supplied test code and tap sign-in, inspect Home, open the actual activity, enter a manual
   center, return to the activity and open read-only Play, then open Account orders
   and fetch a differently titled fresh detail. Assert the exact ledger, canonical
   forms/queries, complete current identity, visible/hidden Play nodes and absence
   of order lifecycle actions. The concurrent initial Home subledger is compared
   as an exact multiset; subsequent navigation requests are compared in order.
2. Cancel the phone sheet with no dispatch, sign in as owner 7, inspect fresh orders,
   use normal sign-out confirmation, sign in as owner 8 and prove no prior-owner
   detail remains. The real SMS cooldown is retained across sign-out, so the second
   owner uses the supplied synthetic code without sending again or resetting the
   cooldown. Relaunch and assert an empty ledger, account, token and area.
3. A reviewed synthetic login alone cannot grant activity details, manual-map,
   Play or owned-order reads. The user selects a valid manual center in list mode,
   then sees unavailable Roam and orders with no corresponding API dispatch.
   Normal unavailable screens retain the signed-in user.

Three app-unit factory proofs cover opt-in/container identity/closed production
input, real phone-parser regression (token-only, malformed, nonpositive and mismatched
provisional-ID responses never commit), stable lease issuance and stale-context/credential rejection after logout/account
switch, and missing-grant/unexpected-mutation rejection at both composition and
sealed recorder boundaries. These use the real auth-channel coordinator directly;
only the UI cases claim typed input and tapped navigation. A retained owned-order
reader is deliberately dynamic: a new call after account switching reads the current
owner. The proof rejects a captured old context and old credential before dispatch,
then verifies that same retained reader fetches owner 8 without changing session semantics.

## Verification limits

Local Python structural/contracts checks and the optional pinned Tree-sitter parser
are source evidence only. Swift type checking, both unsigned app builds, app-unit
XCTest and simulator UI execution require the Apple CI toolchain and remain UNRUN
until an exact-commit CI run establishes them. In particular, the authored lifecycle
request order and UI selectors must pass the simulator gate before acceptance.
This is normal UI with synthetic transport, not real HTTP, provider, account,
backend deployment, SMS or release acceptance.
