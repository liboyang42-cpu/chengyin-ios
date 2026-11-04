# L4 activity registration receipt recovery

Status: IMPLEMENTED / ISOLATED_TESTED. Whole commerce and live launch acceptance remain incomplete.

Base: `bf683917cc140d19d51db897d9ae2ac49594c294` from `integration/launch-20261204`.
Branch: `codex/l4-registration-receipt-recovery-20261104`.
Read #130 and implementation-plan sections 2/4 before editing. The original inspection was at `eec839502b11f1119a6ede212c768bb3f2de4f29`; the patch was moved onto the newer integration base before publication and retested.

## Ownership and file allowlist

Existing branches inspected: `codex/l4-invoice-launch`, `codex/l4-free-explore-recovery-20261104`, `codex/l4-order-readback-owner-20261104`, `codex/l4-ticket-owner-readback-20261104`, and `codex/l4-registration-supplemental-20261104`. #130 had no assignees/comments at inspection. The supplemental registration branch only adds separate readers; this change uses the existing activity registration writer and form.

Only the six files in the hash table plus this report are in this patch. No shared composition/project/CI files changed; no shared wiring diff is required for these existing consumers. No backend, order, ticket wallet, invoice, free-explore, auth, capability or money-rule code is changed. The App change adds the existing localized status-read action in the existing UNKNOWN section; it changes no visual styling or copy.

## Ordinary entry and server authority

Existing entry: `ActivityDetailView` → `SessionRegistrationSheet` → `RegistrationSheetView` → `RegistrationUIFlow` → `RegistrationCoordinator` → `RegistrationProductionService` → `RegistrationService`. Existing AppSession composition supplies the original scoped production service only when its existing approval is present.

The source contract is unchanged: `POST api/registration/quote`, `POST api/registration/create`, and owner-checked `POST api/registration/info` with the original `id`. Existing server consent checks precede the writer. Frozen reference verified: `liboyang42-cpu/hengyin` at `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`, `ApiRegistrationController`, `RegistrationQueryApplication`, and `chengyinhub-xcx/pages/activity/baoming/baoming.js`. No private repository was read. The initial inspection used public `c6eac3b8cebf7311e8f00f208d294c3c8212aaec`; a follow-up supplied the exact frozen SHA and verified it directly with `git show`. The frozen version confirms the quote/create/info contracts, consent fields and owner checks; the absent-latest-consent difference described below was fixed. No endpoint or field was inferred.

A valid create envelope supplies a registration ID, never a payment verdict. The original account/deployment/target journal now retains that ID before caller cancellation or the post-response session fence. A different account cannot observe or read it. Missing/replaced journal records cannot be overwritten. A cancelled form stays UNKNOWN and offers an explicit read of the retained ID using the existing bilingual action; the readback is shown through the existing server-status presentation.

On host reconstruction, the form checks approved ticket targets and restores a pending non-default ticket, including one absent from the refreshed catalog. The original durable lock remains in place. Local observation of that lock ignores caller task cancellation while retaining all existing identity, origin, namespace, storefront, scope and approval checks; every network operation still checks cancellation.

If no usable create receipt ever arrives, the existing UNKNOWN record remains locked. This patch does not resend create, generate another request ID, persist participant PII, infer an order ID from an owned-order match, or claim that a missing list row means failure. The existing owned-order evidence path is read-only and cannot establish correlation after process death.

## Validation

Executed in the managed Linux environment, with Docker network disabled for compilation/tests:

```sh
python3 docs/launch/validate-registration-recovery.py --output /workspace/registration-frozen58-check
docker run --rm --network none --mount type=bind,src=/workspace/registration-frozen58-check,dst=/src --workdir /src swift:6.0.3-bookworm swift test -j 2
```

Swift image digest: `sha256:14de69a0d69106211df7e7c025e64e3abc4521f9f49d9b83fef8e34b6b46c762`.

Result after the frozen-contract fix: 138 XCTest methods, 0 failures, including nine new tests across the two commits. The first commit ran 135 methods with zero failures; the follow-up adds three methods for frozen-consent response shapes. They cover original writer/readback, durable storage reconstruction, non-default/removed-ticket recovery, cancellation, account replacement, malformed receipts, conflicting journal records, legal checks, stale quotes, duplicate submission, and waitlist regressions. The normal-form test uses the real registration flow/coordinator/production service/service/request builders with a fake HTTP transport, and two separately constructed OperationDefaultsJournal adapters over the same isolated UserDefaults suite.

The reproducible harness copies 24 complete production sources and six exact unrelated declarations. It uses a fail-closed unexercised webhook-metadata stand-in because Apple CryptoKit is absent; registration never touches that optional metadata. Thirty synchronous test signatures gain `async` solely for Linux XCTest discovery; assertions and bodies remain unchanged. The script emits original/harness SHA256 manifests. An initial unadapted dependency build stopped on unavailable CryptoKit, then original Linux test discovery stopped on MainActor synchronous methods; neither failure was counted as a pass. These results do not validate the full original module or Apple XCTest discovery.

Also passed: Swift frontend parse of all five changed Swift files, `git diff --check`, and an added-line credential-pattern scan. `registration.form.readStatus` resolves to both `en` and `zh-Hans` in the existing catalog.

Not run: full Core/App typecheck, Xcode builds, simulator/device/UI tests, real test-backend requests, sandbox payment, redemption/refund/invoice, mini-program runtime regression, and CI. No CI/PR/public comment or real transaction was initiated.

## Remaining acceptance dependencies

The current normal entry still requires the existing registration approval/backend configuration from L2/L1; no grant is enabled here. A live backend and current approved session are needed to verify real requests, both theme types, payment and device restart. Total response loss without an ID remains safely UNKNOWN, with no invented recovery contract. Therefore this is a completed recovery slice, not section-2 whole-feature completion or L4 launch sign-off.

## Frozen-58 follow-up

Follow-up parent: `9ed8837a59367eb52b0775652b1c001a102ad10e`. Only `Core/RegistrationProduction.swift`, `Tests/CoreTests/RegistrationProductionTests.swift`, and this report change in the follow-up.

`ApiComplianceController.consents/latest` lines 125–155 returns `success()` when `latest == null`; the resulting successful AjaxResult omits `data`. The original iOS consent reader required a `data` key, preventing a first-time user from recording an explicit agreement. The reader now treats exactly a numeric-200 envelope with an absent `data` key as no agreement. Missing/malformed codes, business refusals, and malformed data remain failures. A missing agreement never authorizes quote/create. The existing explicit agreement, matching version/scene/AGREE readback and durable unknown-consent lock remain mandatory.

The three new tests exercise first-time agreement → original quote/create → original ID status read, rejection of quote/create with no agreement, and malformed/refused envelopes. No server consent/authentication/permission rule was changed.

The frozen `RegistrationCheckoutServiceImpl` response builder returns registrationId, registrationNo, payableAmount and optional payParams; `/registration/info` requires the authenticated owner. The original writer may create an order then fail payment preparation before returning its ID. There is no lookup-by-requestId route in the frozen registration controller. Such total response loss stays UNKNOWN and locked; this patch does not replay a body that the existing journal does not persist.

## Remaining L4 allocation check

| Candidate | Evidence and exact dependency |
|---|---|
| Invoice, free explore, orders, ticket wallet, supplemental registration reads | Existing named L4 branches listed above own these paths. Continue with their owners; do not duplicate them. |
| Merchant coupon publish/stop | Existing `CouponManagement*` consumer uses merchant COUPON_MANAGE authority (L6 boundary). iOS requests `api/coupon/command-receipt`, absent from frozen `ApiCouponController`; L7/backend contract is needed before original-request recovery can complete. |
| Wallet reads | Existing `AppSession.makeWalletCommerceReader(readApproval: nil)` leaves its normal reader without a service. Requires the approved per-environment endpoint grant from L2 and shared composition from L1, rather than another duplicate reader. |
| Fast wallet withdrawal | Frozen `ApiWalletController` defaults `withdrawal.fast-withdraw.enabled` to false. `/wallet/withdraw` accepts amount without a requestId; `/withdraws` lists records but does not provide a correlated original-request lookup. Environment/provider enablement and an agreed unknown-outcome contract are dependencies; no funds rule or switch is changed here. |
| Minor guardian | Frozen `ApiMinorGuardianController` provides policy/status/invite/accept/revoke/list behind `feature.flag.minorMode`, plus separate payment/orienteering switches. No existing ordinary guardian UI consumer was found in the inspected iOS base. Needs a chosen ordinary entry from the UI owner and reviewed L2/L1 composition before a complete consumer journey; no unused standalone client or activation is added. |
| Team commands | Frozen `ApiPlayTeamController` exposes `/api/team` but no `command*` controller mapping was found. Needs a frozen command/receipt contract from backend owner, coordinated with the ticket/team owner. |

No additional unclaimed flow with an existing consumer, complete frozen contract, and independent ready composition was found within this recovery group's boundary. These are dependency findings, not evidence that the corresponding L4 launch features are complete. No live server configuration was inspected or changed.

## SHA256

| Allowed file | SHA256 |
|---|---|
| `App/RegistrationSheetView.swift` | `23b67d972f895702c42daea97a9008761b89d47e844a49c1a636414e678d366b` |
| `Core/RegistrationService.swift` | `5cd382c5fcd0869baaea99038f144cf6d57ac47ac317a0d25469fd4d3939255d` |
| `Core/RegistrationProduction.swift` | `a06aa50aaeef1019775a754fbc6a49682ca9787ae75097ee244311f475d6f5ec` |
| `Core/RegistrationUIFlow.swift` | `6e68b5c76520e372292e72800ce381ef6db5c15c4eede134a5d910be2a67c425` |
| `Tests/CoreTests/RegistrationProductionTests.swift` | `235cd577d187fe308c2cb1d27cb2904e2c62830abedfa63dd1ed2159b41f6be5` |
| `docs/launch/validate-registration-recovery.py` | `fd0bc61f23b1fd4e76e9471a16a418d3b30119a96c71408d2e2b356418f11620` |
