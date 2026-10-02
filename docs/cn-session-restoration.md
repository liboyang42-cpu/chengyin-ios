# CN cold-launch session restoration

## Corrected behavior

Previously, `AppSession.bootstrap` and remote logout reused the password-entry
`AuthService`. A reviewed CN deployment enabling only domestic phone login could
store its successful session but could not restore it on the next launch or
attempt server revocation on logout while password login stayed unavailable.

The host now retains a separate `CNAccountSessionService`. It accepts only a CN
configuration with an approved endpoint, a matching deployment storage scope, and
at least one available existing CN channel (password or domestic phone). Password
login still has its own unchanged capability check. No verification flag or
approved endpoint has been added, and all public configurations remain offline.

The service reuses the inspected Flutter `lib/data/api/auth_api.dart` contracts at
`a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`:

- Current account: bodyless `POST /api/userInfo`, raw Authorization token,
  `code: 200` and a valid `appUser`; a login-shaped `data` object cannot restore
- Logout: `POST /api/logout` with an empty multipart form and the captured old token

No password login, SMS, provider exchange or refresh request occurs during either
operation. Session credentials are read only from the same immutable bundle,
market, exact endpoint and realm Keychain identity paired with the service. The
restoration tombstone shares that identity. Older storage keys are not imported.
Changing a realm or endpoint requires a fresh sign-in. The CN source response does
not provide the US protected realm proof; local namespacing is not a claim of
server-side realm enforcement.

US is explicitly rejected by this service even with all verification flags.
Its separate Apple/protected-session adapter stays unmounted and hard-off.

Bootstrap still preserves the existing epoch checks: logout or a newer login
invalidates an older completion. Canceled work cannot publish an account or erase
a saved token. A current unauthorized response records the scoped tombstone and
clears only that scoped token; offline/server/malformed failures preserve it.
Logout closes the local session first, then attempts only the captured session's
remote revocation; late completion cannot mutate a new session.

## Evidence and limits

Twelve authored synthetic Swift tests cover phone-only restoration, password-only
compatibility, logout wire shape, unavailable/US/scope mismatch gates, realm-key
separation, invalid credentials, error distinctions, malformed/login-shaped
responses, and cancellation before/after dispatch. Four Python source checks
verify the actual host wiring, scoped tombstone order, stale/canceled commit
guards and local-first logout. Existing SessionOperationGate tests remain intact.

Swift/Xcode, XCTest, simulator and Keychain runtime checks have not run in this
Linux workspace. Source checks and advisory parsing are not compiler or cold-start
device evidence. No live backend/account, SMS, provider, security setting or
deployment was accessed or changed. Apple CI must run the full suite and unsigned
builds; an approved isolated environment is still needed for actual Keychain and
phone-login → terminate → relaunch → logout acceptance.
