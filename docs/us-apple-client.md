# US Apple client adapter: implemented, production unavailable

## Status and scope

This isolated native slice implements the approved US Apple wire contract using new client-only code. Production admission is deliberately `false` in `USAppleProductionGate`. It adds no origin, Apple audience, entitlement, credentials, provider account, billing account, legal agreement, configuration, deployment or real sign-in. This client-only authentication slice makes no provider-eligibility, payments, tax, legal-entity or settlement claim.

At integration, the Xcode project and String Catalog include this adapter and its labels; the AppSession and root do not construct or mount it. Regional authentication capability remains unchanged. US `availableCapabilities` remains empty even when all verification flags are supplied. This adapter is not connected to production UI or session storage. Google, email/password, US SMS, payments and payouts remain unavailable. The legacy CN service is not referenced or used as fallback. Guest browsing does not create an account.

The two US routes are not registered when the server gate is off. Neither 401 nor 404 can prove readiness, and this client performs no capability probes. Missing ready US account/session persistence, abuse controls, independently configured Redis/account stores, and protected-route realm enforcement prevent activation. A `market: US` JSON field alone is not evidence of session isolation.

## Public wire contract

One explicitly approved HTTPS origin is supplied as `USAppleDeployment`. It must be an origin, without a path prefix, query, fragment or user information. Approval is exact, including port and trailing slash; do not populate the allowlist from the requested URL. `realm` is a host-owned deployment/session-storage identity. It is never submitted as a client override, inferred from an Apple audience, or derived from language/storefront. This adapter has no default URL.

1. `POST /api/us/auth/apple/challenges`, body exactly `{}`
2. Require HTTP 200 and numeric AjaxResult `code: 200`. Read `data.challengeId`, `rawNonce`, `state`, `expiresIn`, `market`, `provider`. Each random string must be canonical 43-character unpadded base64url for 32 bytes; the three strings must differ. Accept a positive TTL no greater than 300 seconds, exact `market: US` and `provider: apple`
3. Set native Apple request `nonce` to lowercase hexadecimal SHA-256 of the UTF-8 raw nonce, and native `state` to the challenge state. CryptoKit is the production hash implementation. No CryptoKit means unavailable; there is no alternate/plaintext fallback. No email/full-name scope is requested
4. Require the provider's returned state to exactly match before any exchange. Treat the identity token as opaque, visible ASCII, 1–16,384 bytes. It is not decoded into an identity, used for local signature verification, logged or persisted
5. `POST /api/us/auth/apple/exchange`, JSON containing exactly `challengeId`, `state`, `identityToken`. No email, subject, name, role, member ID, market, realm, nonce, audience or authorization-code field is submitted
6. Require HTTP 200, `code: 200`, `market: US`, a nonempty header-safe session token, and all five safe profile fields: positive integer `id`, integer `userType`, string `avatar`, string `nickname`, string `role`. Reconstruct `Account` from only those fields; extra entity fields/email are not imported. The provisional local session-token limit is also 16,384 ASCII bytes
7. Before any persistence, independently verify this candidate against the future approved US protected current-account boundary. Require matching positive account ID, explicit US market and the expected deployment realm, then pass its refreshed account to the injected atomic session commit

Requests are JSON POSTs with no CN bearer token, cookies, raw-nonce header, locale or market override. They ask for no-store/no-cache and disable local caching/cookie handling. The existing ephemeral `URLSessionTransport` refuses redirects; custom transports must offer equivalent protection. The transport interface returns body/status, so response Cache-Control/Pragma headers are not independently asserted here. Responses larger than 64 KiB are rejected before decoding, after the transport has received them; a future bounded streaming transport/ingress remains responsible for an absolute receive-memory limit.

### Stable handled errors

The numeric HTTP status must equal AjaxResult `code`, and `errorCode` must match its documented status. Server `msg` is never parsed or displayed.

| HTTP | errorCode | Client handling |
| --- | --- | --- |
| 400 | US_APPLE_INVALID_REQUEST | Clear attempt; user may start a fresh attempt |
| 401 | US_APPLE_INVALID_CHALLENGE | Clear attempt; require fresh challenge |
| 401 | US_APPLE_INVALID_IDENTITY | Clear attempt; no provider/endpoint switching |
| 429 | US_APPLE_RATE_LIMITED | Clear attempt; explain retry later, without inventing a wait duration |
| 503 | US_APPLE_UNAVAILABLE | Clear attempt; no fallback; a new user attempt obtains a new challenge |

Unknown errors, mismatched codes, non-JSON, unregistered routes, redirects and network failures are failures. There is no automatic network/provider retry or restoration of a potentially consumed challenge. A new tap always requests a new challenge. Credentials and server response text never appear in error state.

## Integration APIs (future, after independent approval)

- `USAppleDeployment(market:origin:realm:approvedUSOrigins:)`: exact US deployment boundary
- `USAppleService(deployment:transport:)`: challenge/exchange adapter. All public construction is production-gated off
- `USAppleAuthorizing`: injectable main-actor `authorize(_:)` and `cancel()`, allowing offline provider fixtures
- `USAppleCoordinator(deployment:service:authorizer:currentSession:verifyCurrentAccount:commitLogin:now:)`: full attempt flow. `now` defaults to Swift ContinuousClock elapsed time, which includes device sleep and is independent of wall-clock changes
- `USAppleSessionSnapshot`: epoch, market, realm, account ID and session-busy state. Increment epoch on every bootstrap, login/logout, expiration or replacement, including same-account relogin
- `verifyCurrentAccount`: injected async closure taking only the candidate US session token and returning `USAppleVerifiedCurrentAccount`. Its returned realm must be independently verified by the US protected-session implementation. Do not implement it by echoing requested values, parsing unsigned token claims, or using the exchange market field
- `commitLogin`: synchronous main-actor closure. Atomically compare the entire captured snapshot, require an idle anonymous US session in the expected realm, persist to that realm's own approved Keychain namespace, advance epoch, and publish the verified account. On failure, leave the prior session intact. No suspension or observable partial state. Returning `false` reports changed session; throwing reports storage failure
- `USAppleSignInModel` and `USAppleSignInButton`: optional standalone app-layer model and real `ASAuthorizationAppleIDButton`/controller adapter. They are not mounted in the app. Public production gate also blocks a direct native-authorizer call

The approved contract does not define the US current-account, refresh, logout/revocation, upload or alternate-transport routes, so no URL for any of them is invented here. An implementation of protected current-account verification is required before login can complete. Client checks do not replace server realm enforcement across all protected surfaces.

A future authorized integration must merge `us-apple-client-localizations.json` into the existing catalog and regenerate the project, then create the stable model in the correct US host session. Recreate the native button on color-scheme changes (for example, `.id(colorScheme)`) and give it an appropriate minimum 44-point hit target. Present the existing approved privacy/terms flow; no legal acceptance is performed here. Show unavailable text rather than a usable sign-in action until all gates are reviewed. Enabling a UI button, changing one constant or setting a regional flag alone is insufficient.

Call `model.cancel()` on sheet dismissal, navigation away, scene shutdown and external account/realm/session changes. Call `model.becameActive()` when returning to the foreground. The coordinator automatically schedules expiry after acquiring a challenge and rechecks monotonic TTL after every asynchronous boundary, before exchange and before persistence. Time consumed by challenge transport and device sleep counts toward TTL. The expiration task also uses the continuous clock. See [Apple ContinuousClock documentation](https://developer.apple.com/documentation/swift/clock/continuous) and [Duration components](https://developer.apple.com/documentation/swift/duration/components). A backward/nonfinite clock fails closed. The injected clock is a testability seam, never a market selector.

Only the challenge's ID/state/digest/deadline are retained for an active attempt; raw nonce has no retained owner after request preparation. Cancellation and every terminal outcome clear the active attempt, cancel expiration/provider work and discard uncommitted session candidates. Swift does not guarantee secure zeroization of discarded String/Data storage. Opaque generation IDs, provider-controller identity and single-use continuations fence duplicate taps, duplicate delegates, canceled/replaced attempts and late challenge/exchange/verification responses. Canceling locally cannot revoke a request already accepted by the server.

## Offline tests and verification limits

`Tests/CoreTests/USAppleServiceTests.swift` and `USAppleCoordinatorTests.swift` use synthetic data, fake transports/providers and controlled continuations. Debug-only internal constructors admit only fixture usage by convention; they are absent from Release. No public runtime/configuration flag can turn on production. The debug tests are conditionally compiled and are not exercised by `swift test -c release`; use `swift test` for the offline suite. CryptoKit known-vector tests run where CryptoKit is present; platforms without it assert fail-closed hashing while coordinator fixtures inject a known synthetic digest.

The suite contains 32 synthetic Swift test methods. Coverage includes exact routes/body/header shape, wrong HTTP/error pair, unregistered/non-JSON/redirect results, malformed challenge/randomness/TTL/market/provider, oversized/missing tokens, profile field allowlisting, SHA-256 vectors, production no-dispatch, fresh-attempt behavior, state echo, ID/market/realm verification, compare-and-commit refusal/storage failure, duplicate taps, challenge/provider/exchange/verification cancellation, stale old callbacks, epoch changes, expiry/clock rollback and reentrant dismissal.

Executed in this Linux workspace: seven client-only static contract checks (`python3 -m unittest discover -s Tests/ContractChecks -p 'test_*.py' -v`), JSON/localization validation and whitespace checks. The static checks inspect source, not Swift runtime behavior. Swift and Xcode are unavailable, so the Swift tests, Swift type checking, native Apple APIs, simulator/device UI, accessibility and real provider/backend flows have NOT been run. The existing project structural checker is intentionally not run against this unintegrated branch because project/catalog updates are out of scope.

Before considering activation: compile the full app and offline suite on an authorized Swift/Xcode environment; integrate and test the disabled UI in English/Chinese and light/dark/large-text/VoiceOver modes; verify Apple callback/scene/background cancellation on a simulator/device; independently approve the US origin, exact legitimate Apple audience, entitlement and legal flow; implement and verify isolated account/session/abuse dependencies and real Redis expiry/replay behavior; establish protected-route/refresh/revocation/alternate-transport realm isolation; then separately authorize deployment and controlled real Apple sign-in. No provider, finance, account, credential or deployment setup is implied by these files.
