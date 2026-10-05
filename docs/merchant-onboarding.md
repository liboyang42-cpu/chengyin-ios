# Native merchant application and status

## Delivered and explicitly blocked

This slice adds a genuine native four-step application form, source-backed business-hours picker, local license-photo review, separately confirmed upload, application review/confirmation, rejected-application backfill, and server-reported status. It is not a role-selection grant or an extension of the read-only dashboard.

**US release blocker:** the supplied source only implements publisher identity enrollment using a mainland Chinese resident-ID rule. A supported US enrollment contract, regional eligibility/legal requirements and privacy flow have not been supplied. The native form checks whether registration already exists; unregistered or unconfirmed users cannot upload or submit. No national-ID, SSN, EIN, bank, payment or fabricated US fields are collected. This is a visible product/backend gate, not completed US merchant enrollment. Existing server-registered users can use the source-backed application contract once root integration/configuration and runtime verification are complete.

The source calls this identity **registration**, not independently verified identity. The native UI preserves that distinction.

## Source evidence (unchanged sibling `app-audit`)

- `lib/data/models/merchant_apply.dart:1–111`: draft fields and trimming; only rejected reapplications carry `id`; required name/phone, address/hours, and license; no country-specific phone validation
- `lib/feature/merchant/merchant_apply_page.dart:147–172`: rejected backfill deliberately omits coordinates, WeChat and derivatives
- `lib/feature/merchant/merchant_apply_page.dart:375–402`: exact businessTime weekday/time grammar
- `lib/feature/merchant/merchant_apply_page.dart:404–423`: explicit gallery selection then image upload
- `lib/data/api/play_api.dart:436–453`: `/api/common/uploadOSS`, multipart field `file`, success code 200, top-level `url`
- `lib/data/api/merchant_api.dart:423–431`: `/api/merchant/merchant_registration`, JSON draft, acknowledgement determined by code 200
- `lib/data/api/merchant_api.dart:754–785`: `/api/merchant/info`, empty multipart, explicit absence only; request/malformed failure is not no application
- `lib/data/models/merchant_application.dart`: positive ID, separate review `status` and `accountStatus`; valid values 0…2; disabled precedence; `reson` is rejection reason, `disableReason` is distinct; explicit top-level `applicationState: NONE`
- `lib/feature/merchant/merchant_apply_page.dart:426–455`: publisher identity must be registered before application submission
- `lib/data/api/publisher_identity_api.dart:21–37`: JSON `{}` POST `/api/publisher/identity/status`, `data.registered == true`
- `lib/data/api/publisher_identity_api.dart:44–65`: unsupported-in-this-slice enrollment POST accepts `realName`, `idCard`, `consent`, `source`
- `lib/feature/publisher/publisher_identity.dart:30–85`: 18-character `^\d{17}[0-9X]$` ID rule; embedded date; weights `[7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2]`; check codes `10X98765432`
- `lib/feature/publisher/publisher_identity.dart:124–136`: name 2–20 characters, no ASCII digits, ID checksum and separate consent; existing registration satisfies the gate

These are migration contracts established from client source. No backend code, live service or production identity behavior was independently verified.

## Exact request/response boundaries

All requests use the injected approved `APIConfiguration`, raw `Authorization` token, JSON Accept, 20-second timeout and disabled cache. Use the existing no-redirect ephemeral `URLSessionTransport`; the UI constructs no endpoint or transport.

| Operation | Route | Encoding / result |
| --- | --- | --- |
| Application state | POST `/api/merchant/info` | Empty multipart; code 200; data application or top-level `applicationState: NONE` with missing/null/empty object data |
| Existing identity registration | POST `/api/publisher/identity/status` | JSON `{}`; code 200; strict Boolean `data.registered` |
| License upload | POST `/api/common/uploadOSS` | One multipart `file`, JPEG bytes, generated non-PII filename; code 200 and top-level safe HTTPS `url` |
| Application submit | POST `/api/merchant/merchant_registration` | JSON `name, preference, phone, description, address, businessTime, businessLicense, wechat`; `id` only for a server-confirmed rejected non-disabled application |

No `merchantId`, role, permissions, approval status, coordinates, identity value, community-media receipt or community `bizType` is invented. Native application parsing rejects fractional/Boolean identifiers rather than silently truncating them. Invalid rows never open a new form. HTTPS upload URL validation is deliberately stricter than the Flutter string coercion.

The 10 MiB pre-processing cap and 4096-pixel JPEG rendering bound are local safety limits, not claims about backend limits. The native picker accesses only the item explicitly selected, loads it after selection, re-renders without metadata, and keeps bytes in memory. It never calls `PHPhotoLibrary.requestAuthorization`, saves to Photos, or writes a file. Selection is followed by a visible preview and a separate upload confirmation identifying the document, recipient service and purpose. The draft can receive a license reference only from a valid upload response or server-confirmed reapplication data. There is no editable URL text field or fallback invented URL. No remote license image fetch is performed.

Persisted businessTime uses the exact source Chinese weekday grammar regardless of UI locale. Known generated weekday strings are localized for English UI display only; unknown server text is preserved.

## Safety, submission and status

- Choosing merchant entry never constructs `MerchantAccess`, changes an Account role, or authorizes operating features
- Name, phone, address, hours and uploaded license are validated on every prepare and again when JSON is built; optional fields stay optional
- US/new identity enrollment is blocked; registered-state lookup failures stay distinguishable from an explicit unregistered response
- Confirmation freezes the draft and account/epoch; cancelling or repeated taps cannot dispatch another write
- Immediately before submission the coordinator re-reads application state and identity registration; a changed state stops submission
- Acknowledgement triggers one status read. It never becomes local approval, activation or a merchant role
- Review pending, rejected, awaiting activation, effective, and account disabled stay distinct. Disabled always takes precedence and never borrows an old rejection reason
- An explicit server business rejection retains server text rather than inventing a permanent club-leader conflict rule
- Malformed/timeout/cancellation/uncertain mutation results retain an in-memory unresolved-operation lock. A subsequent status read does not prove that an unchanged/missing record means the mutation failed. There is no automatic retry or manual resend from that locked coordinator
- Acknowledged submissions stay locked until readback reaches a definitive non-editable application state (pending, awaiting activation, effective or disabled). The acknowledgement remains visible for that result; a later explicit read can expose a subsequent rejection for a new, confirmed reapplication. Missing or unchanged rejected readback does not unlock. Unknown-outcome locks are never cleared by this rule. User-initiated status refresh is read-only
- PhotosPicker, hours sheets and confirmation presentation are guarded against navigation-disappearance cleanup; returning from a transient sheet does not rerun draft initialization for the same revision. Final confirmation marks busy and clears the sheet token synchronously before dispatching its captured immutable intent
- Actual navigation dismissal, account replacement, logout or stale completions clear/hide draft, selected photo, confirmation and readback; PII-free account operation locks remain in memory for same-account reentry
- The operation lock is intentionally not persisted. Killing/restarting the process loses it; there is no source-backed idempotency key or operation-status endpoint. End-to-end duplicate prevention remains a backend responsibility and a release gate
- No PII, credentials, file bytes or raw transport errors are logged or persisted by this module

## Root integration contract

The slice is integrated into root AppSession, AccountView, the shared String Catalog and generated Xcode project. `MerchantHomeView` gains optional `openApplication: (() -> Void)? = nil` for the inactive identity section; this is a navigation callback, not authorization.

1. The integrated AppSession retains a `MerchantOnboardingSessionAdapter(service:currentSession:onUnauthorized:)` and a `MerchantOnboardingCoordinator(server:)` in the session owner, outside screen lifetimes
2. Construct `MerchantOnboardingSession(accountID:epoch:token:)` only from the live signed-in account and credential; advance the epoch on logout, expiration and every login, including same-account login
3. A matching unauthorized callback must expire only that captured session. The adapter already rejects stale account, epoch and credential responses before exposing them
4. AppSession adopts `MerchantOnboardingObserving` on the observable session with `isConfigured`, `isSignedIn`, `sessionRevision`; render `MerchantOnboardingView(session:coordinator:openMerchant:)` inside the existing NavigationStack
5. AccountView now exposes this real application/status view directly and through the inactive merchant home callback. Cross-login navigation-intent wiring is deferred to root after login lifecycle review. Merchant entry does not select a server role. An optional active-application navigation action must enter the normal merchant home, which rechecks `access/me`
6. All 88 `docs/merchant-onboarding-localizations.json` entries are merged into the shared String Catalog; the Xcode project was regenerated through the existing tool
7. Root adds optional DEBUG launch routing to `MerchantOnboardingFixtureRoot(name:)`. Suggested argument: `--uitesting-merchant-onboarding-fixture`

The core protocol `MerchantOnboardingServing` is main-actor isolated and exposes only scoped application/identity reads, license upload and submit. It does not expose credentials to form state.

## Offline fixtures and verification

`MerchantOnboardingFixtureRoot` supports `form` (or any unrecognized name), `identity-required`, `identity-error`, `retry`, `pending`, `rejected`, `disabled`, `activation`, `effective`, `submit-unknown`, `submit-rejected`. Fixtures are DEBUG-only and synthetic. Rejected and identity-gated fixtures contain an explicit synthetic server license reference to exercise submission without actual Photos access or upload. They never fetch that URL. The switch-test-account toolbar action exercises revision invalidation.

41 authored pure Swift tests cover contract states/required fields/URL validation, exact requests, explicit no-application semantics, identity status, upload response topology, transport failures, prepare/cancel/frozen confirmation, status preflight, single dispatch, acknowledged/uncertain readback, same-account relogin locks and stale unauthorized/session responses.

Three authored offline UI scenarios cover rejected backfill/cancel/submit/pending readback, the US identity gate, and unknown-outcome readback without resubmission.

Locally verified: localization JSON shape/unique keys/literal and dynamic key coverage; merged catalog values; scoped file diff; deterministic project regeneration and structural scaffold check; `git diff --check`. **Not run:** Swift tests, SwiftUI compilation, simulator interaction, PhotosPicker behavior, accessibility/Dynamic Type, live network, regional/legal review. Swift and Xcode are absent here. Root's GitHub macOS CI must compile/run these tests after merge and catalogue/project integration.

Suggested simulator checks: English and Chinese four-step navigation; hours save/cancel; selected-photo discard; no upload on select; upload cancel; submit cancel and repeated confirm; identity gate; rejected backfill; disabled reason; success then status; unknown submission then manual read; close/reopen; account switch during each await; no stale form or result; Dynamic Type and VoiceOver.

No actual application, upload, personal-data transmission, Photos permission, Apple/signing configuration, live request, commit or push occurred.
