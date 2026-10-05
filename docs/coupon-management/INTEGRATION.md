# Integrated status — 2026-10-02

Integrated into the shared native checkout, preserving the existing modules and six shards. Source marketing/recruiting now exposes the published-coupon destination only after its existing fresh merchant:marketing:read check. AppSession retains the coordinator and stable account/namespace/epoch/role revision. Optional read approval is checked against exact deployment/account/namespace/path; production supplies no grant, publisher authority or write enablement. The DEBUG fixture skips real session construction. App-private write-ahead locks use bounded SHA256 filenames with full embedded identity validation, backup exclusion and protected directory permissions.

Current cumulative inventory: 1,624 authored Core tests, 250 authored UI tests in 40 classes, 4,328 bilingual keys. This module contributes 22 Core and 5 UI cases. Seven source integration checks were added. Swift/Apple execution remains NOT_RUN. See integration-verification.json, source-results.txt, syntax-validation.txt and integration-manifest.json beside this document for exact local evidence.

The following implementation/source guide is retained for review; its copy/merge steps are now completed in this checkout.

# Coupon author and management migration

## Scope and ownership

Additive isolated implementation for `coupon_author`, based on:
- `app-audit/lib/data/api/coupon_api.dart`: `myPublishedList`, `publishWithReceipt`, `stop`
- `app-audit/lib/feature/coupon/coupon_publish_sheet.dart`: validation order, picker-to-wire values, dirty cancellation, errors
- `app-audit/lib/feature/coupon/my_published_coupons_page.dart`: status 0/1 stop eligibility, nullable counts, remaining stock, stop policy, refresh after success/failure
- `app-audit/test/data/api/coupon_merchant_test.dart`, `coupon_merchant_provenance_test.dart`, `test/feature/coupon/{coupon_publish,my_published_coupons_page}_test.dart`

`CouponDefinitionID` identifies `SmsCoupon`, never a received/history ID. Existing `AccountCollectionCoupon.id` remains the claimed coupon/history identity; its optional `couponID` is the relation only. No changes to AccountCollections, OrderLifecycle QR/pass issuance or verification, or Cooperation perk templates/offers/supply lifecycle. Their routes and types are not duplicated.

This module owns creation draft, immutable review, own published list, own definition detail by a fresh list read, and stop-distribution review. It supplies exact dormant HTTP write serialization and response handling, but does not enable production writes. Native review/simulation is clearly labeled and cannot be mistaken for an actual publication receipt.

## Additive integration steps

1. Copy all `Core/CouponManagement*.swift`, `App/CouponManagement*.swift`, `Tests/CoreTests/CouponManagementTests.swift`, and `Tests/AppUITests/CouponManagementFlowTests.swift` to their same paths in `chengyin-ios`. Add source and test membership through the existing project-generation/file-list workflow. No existing Swift files need replacement. The files depend on the existing APIConfiguration, HTTPTransport, and AuthRequestBuilder in the integrated Core target.
2. Merge the **71 key entries** in `Resources/CouponManagementLocalizations.fragment.json` into `Resources/Localizable.xcstrings["strings"]`; preserve every unrelated key. Every entry has English and Simplified Chinese. The fragment is not a replacement catalog.
3. Add a DEBUG-only branch in `QuestifyApp`'s existing UI-fixture switch for `--ui-coupon-management` returning `CouponManagementFixtureHost()`. Include that argument in the existing synthetic-launch/no-real-session predicate. Do not add a public debug route. Optional fixture flags: `--coupon-management-disabled`, `--coupon-management-blank`, `--coupon-management-unknown`.
4. At the **existing merchant published-coupon entry only**, inject a retained `CouponManagementCoordinator` and show `CouponManagementView(coordinator: ..., sessionKey: ..., isSourceVisible: existingSourceVisibility)`. Default `isSourceVisible` is false. Do not add new home-feed promotions, player campaign links or other feature visibility.
5. Construct `CouponManagementSession` using authenticated account ID, stable backend/region namespace, monotonically changing account/token/role/region epoch, and authorization revision. Pass a fresh current-session closure to the coordinator and the matching `sessionKey` to the view. Rotate the epoch on auth/role/config changes even when the account ID is unchanged. Retain the coordinator per mounted session. Call `leave()` on host teardown; update sessionKey promptly on logout/background invalidation.
6. For source-backed reads only, `CouponManagementHTTPReadTransport` accepts the existing approved `APIConfiguration`, ephemeral/no-redirect `HTTPTransport`, and a closure returning current `CouponManagementReadCredentials`. It performs POST multipart `/api/coupon/mypublishlist`, validates session/token again after await, rejects every mutating descriptor and requires no new network host. Never supply the default URLSession redirect policy. Adapter construction uses `CouponManagementAdapter(transport: readTransport)`; its default write grant is false.
The dormant write transport is additive, not wired into this production-facing view. For future separately approved integration, it uses the same approved configuration, HTTP transport and ephemeral credential closure; keep both grants false until the release authorization and runtime checks are satisfied.

7. Inject fresh `CouponPublisherAuthorizing` from a verified host publisher entitlement source. No publisher role endpoint or complete role/quota contract exists in the audited coupon API. Until verified, use `CouponPublisherUnavailable()`, keeping publication review blocked. Stop ownership comes only from a fresh authenticated `/mypublishlist`; status must be 0 or 1 at both review and confirmation. The backend still owns final authorization and quota enforcement.
8. Use `CouponManagementFileLocks` rooted in an app-private Application Support directory (exclude credentials and backups as appropriate to host policy). Never replace it with fixture memory locks in shipped code. Creation uses one account+namespace publication lock; stop uses account+namespace+definition ID. These keys intentionally exclude session epoch and review UUID. Corrupt storage, exclusive-create failure and interrupted writes fail closed. No UI can clear unknown outcomes.
9. Run existing project generators and full project checks after integrating. Then run Swift package tests, iOS build, and the UI suite in Xcode. This Linux delivery has no Swift or Xcode and cannot substantiate runtime/typechecking claims.

## Contracts

| Action | HTTP | Body | Behavior |
|---|---|---|---|
| Published list / metadata detail | POST `/api/coupon/mypublishlist` | multipart optional nonempty `keyword` | `code=200`, array `data`; duplicates, missing IDs and missing array fail closed |
| Publish | POST `/api/coupon/publish` | JSON `name,startTime,endTime,publishCount,couponType`, optional nonempty `description` | All source validation gates; wire type 0=gift, 1=10% off, 2=20% off, 3=experience |
| Stop distribution | POST `/api/coupon/stop` | multipart `couponId` as definition ID string | Review immutable policy; reread ownership/status before dispatch and list again after response/error |

No fabricated `/info`, claim, update, resume, delete, receipt, payment or reconciliation routes. No actual publication, claims, issuance, redemption, provider, backend or financial actions were performed.

Dates: selected native calendar days are represented as absolute Date values and serialized as ISO8601 seconds; server date strings are displayed by their original validated date prefix without timezone shifts. Calendar display does not confer claim/use eligibility. No local wall-clock status promotion. Source publication states 0 scheduled / 1 active / 2 ended / 3 invalid / 4 stopped; unknown stays unknown. Amount/currency/perLimit are nullable optional metadata only, never writable fields, defaults, savings calculations or eligibility evidence. Their detailed semantics are not established by the author API; UI marks them “if provided”.

## Safety and known gaps

- **Claim operation: source gap.** The entire audited coupon API has no claim endpoint, request schema, claim-limit rule or claim receipt. The native detail explains unavailability; no generic “receive” endpoint is guessed. Existing claimed metadata stays accessible via its existing wallet route.
- **Production publication/stop: intentionally disabled.** Synthetic execution is DEBUG-only. The real injectable CouponManagementHTTPDormantTransport implements exact JSON publication and multipart stop plus response handling, but requires its own dormantWritesEnabled=true AND the coordinating adapter dormantWritesEnabled=true. Both default false; no shipped host supplies either. The read-only HTTP transport refuses writes regardless of flags. Tests use fake HTTPTransport to cover the dormant HTTP path; no real dispatch was performed. Business rejections retain original server message; parse failures, HTTP 5xx, redirects, cancelled or thrown transports retain unknown-outcome lock.
- **Fresh publisher entitlement:** host integration remains required; arbitrary local roles do not grant permission. Published own-list membership confirms stop ownership but does not establish a create quota.
- **Uncertain reconciliation:** no source operation ID/status endpoint. A matching title/list refresh or changing draft/session never clears the lock. Publication lock is intentionally conservative across all drafts for that account/backend until an authoritative operational resolution contract is supplied.
- **Creation draft persistence:** in-memory for the retained coordinator; dirty Cancel requires discard confirmation. No claim of automatic cross-launch draft recovery. Write-ahead pending records persist across launch and block duplicate effects.
- **No edit/activation/delete:** absent source contracts. Stopping only affects new issuance/claims; previously received coupons retain their server-defined usability.
- **Runtime:** Swift compiler, XCTest execution, iOS simulator, VoiceOver and dynamic-type visual QA are NOT_RUN. Accessible native List/Form/Picker/DatePicker/Button controls and identifiers are provided; runtime verification is still required.

## Verification

`python tools/check_coupon_management.py`: Final validation JSON records the current static check count. It verifies routes, encoding keys, gates, stable locks, source states and bilingual literals. It is not a behavioral or compiler test.

Supplementary Tree-sitter script parses the original Swift bytes, pinned existing 0.26.0/0.7.3 dependencies. It is not Swift typechecking.

Authored XCTest cases cover source validation and type mapping, exact fields, multipart ID, null/unknown states, duplicate IDs, default/non-synthetic gate, changed review, fresh publisher revocation, fresh stop ownership/state, unknown lock across a new coordinator/epoch/draft, storage failure, stale account, error refresh without lock clearing, exact rejection message, exclusive persistent lock and corrupt storage. UI fixture tests cover owned list/detail, review, disabled confirmation, blank validation, sign-out and stopped-state behavior. Additional fake-HTTP tests exercise both dormant grants off, exact POST URL/body/header serialization, positive acknowledgements, exact business rejections, and a timeout through the persistent-lock coordinator. None were executed in this environment.
