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

The source contract is unchanged: `POST api/registration/quote`, `POST api/registration/create`, and owner-checked `POST api/registration/info` with the original `id`. Existing server consent checks precede the writer. Public reference inspected: `liboyang42-cpu/hengyin` at `c6eac3b8cebf7311e8f00f208d294c3c8212aaec`, `ApiRegistrationController`, `RegistrationQueryApplication`, and `chengyinhub-xcx/pages/activity/baoming/baoming.js`. No private repository was read. The delegation's exact “frozen 58” SHA was not supplied or found in public launch documents; this patch introduces no inferred endpoint or field and does not claim independent verification of that unidentified revision.

A valid create envelope supplies a registration ID, never a payment verdict. The original account/deployment/target journal now retains that ID before caller cancellation or the post-response session fence. A different account cannot observe or read it. Missing/replaced journal records cannot be overwritten. A cancelled form stays UNKNOWN and offers an explicit read of the retained ID using the existing bilingual action; the readback is shown through the existing server-status presentation.

On host reconstruction, the form checks approved ticket targets and restores a pending non-default ticket, including one absent from the refreshed catalog. The original durable lock remains in place. Local observation of that lock ignores caller task cancellation while retaining all existing identity, origin, namespace, storefront, scope and approval checks; every network operation still checks cancellation.

If no usable create receipt ever arrives, the existing UNKNOWN record remains locked. This patch does not resend create, generate another request ID, persist participant PII, infer an order ID from an owned-order match, or claim that a missing list row means failure. The existing owned-order evidence path is read-only and cannot establish correlation after process death.

## Validation

Executed in the managed Linux environment, with Docker network disabled for compilation/tests:

```sh
python3 docs/launch/validate-registration-recovery.py --output /workspace/registration-check-current
docker run --rm --network none --mount type=bind,src=/workspace/registration-check-current,dst=/src --workdir /src swift:6.0.3-bookworm swift test -j 2
```

Swift image digest: `sha256:14de69a0d69106211df7e7c025e64e3abc4521f9f49d9b83fef8e34b6b46c762`.

Result: 135 XCTest methods, 0 failures, including six new tests. They cover original writer/readback, durable storage reconstruction, non-default/removed-ticket recovery, cancellation, account replacement, malformed receipts, conflicting journal records, legal checks, stale quotes, duplicate submission, and waitlist regressions. The normal-form test uses the real registration flow/coordinator/production service/service/request builders with a fake HTTP transport, and two separately constructed OperationDefaultsJournal adapters over the same isolated UserDefaults suite.

The reproducible harness copies 24 complete production sources and six exact unrelated declarations. It uses a fail-closed unexercised webhook-metadata stand-in because Apple CryptoKit is absent; registration never touches that optional metadata. Thirty synchronous test signatures gain `async` solely for Linux XCTest discovery; assertions and bodies remain unchanged. The script emits original/harness SHA256 manifests. An initial unadapted dependency build stopped on unavailable CryptoKit, then original Linux test discovery stopped on MainActor synchronous methods; neither failure was counted as a pass. These results do not validate the full original module or Apple XCTest discovery.

Also passed: Swift frontend parse of all five changed Swift files, `git diff --check`, and an added-line credential-pattern scan. `registration.form.readStatus` resolves to both `en` and `zh-Hans` in the existing catalog.

Not run: full Core/App typecheck, Xcode builds, simulator/device/UI tests, real test-backend requests, sandbox payment, redemption/refund/invoice, mini-program runtime regression, and CI. No CI/PR/public comment or real transaction was initiated.

## Remaining acceptance dependencies

The current normal entry still requires the existing registration approval/backend configuration from L2/L1; no grant is enabled here. A live backend and current approved session are needed to verify real requests, both theme types, payment and device restart. Total response loss without an ID remains safely UNKNOWN, with no invented recovery contract. Therefore this is a completed recovery slice, not section-2 whole-feature completion or L4 launch sign-off.

## SHA256

| Allowed file | SHA256 |
|---|---|
| `App/RegistrationSheetView.swift` | `23b67d972f895702c42daea97a9008761b89d47e844a49c1a636414e678d366b` |
| `Core/RegistrationService.swift` | `5cd382c5fcd0869baaea99038f144cf6d57ac47ac317a0d25469fd4d3939255d` |
| `Core/RegistrationProduction.swift` | `f808ad1d18ef77f2d01fae472abd4bf0c34c29bbdfca3a89a2e1d02ed3f53680` |
| `Core/RegistrationUIFlow.swift` | `6e68b5c76520e372292e72800ce381ef6db5c15c4eede134a5d910be2a67c425` |
| `Tests/CoreTests/RegistrationProductionTests.swift` | `798ca43cfdb68c3157e0c1b1c0e3ccef932736b95dd889ec44e2aae0147c89d8` |
| `docs/launch/validate-registration-recovery.py` | `fd0bc61f23b1fd4e76e9471a16a418d3b30119a96c71408d2e2b356418f11620` |
