# W17 owner reward read integration

This independent unit adds actual HTTP request/decoding code for the backend read candidate, not a production activation. Source contracts: `chengyinhub-admin/.../ApiNonCashRewardReadController.java`, `chengyinhub-system/.../NonCashRewardReadService.java`, and the existing noncash ledger service. The backend controller is profile/bean gated. AppSession's `nonCashRewardService` remains explicitly nil; no regional configuration, deployment grants, host, token authority, redirect handling, write endpoint or credential factory is enabled.

## Wire and normal App flow

- GET `api/rewards/noncash?limit=20[&cursor=...]`; backend supports explicit limits 1–50. Cursor/award IDs are exactly 64 lowercase hexadecimal characters. No owner parameter exists; Authorization uses the existing App token header convention.
- GET `api/rewards/noncash/{awardId}` with exact contextType/contextId/releaseId/instanceId from the selected list result. Scope never falls back to another run/season.
- AjaxResult code 200 and data page items/nextCursor/asOf or one flat reward. IDs are positive decimal strings, quantity exactly one, timestamps nonnegative integer epoch milliseconds. The client presentation range stops at year 9999 and fails closed outside it rather than wrapping. Server title/terms whitespace is preserved; UTF-16 length cap is 512.
- Required PHYSICAL/context/state/validity/fulfillment enums fail closed. Validity must agree with server asOf and the half-open validity window. ELAPSED never changes persisted AWARDED to EXPIRED. UNVERIFIED never means redeemable. Every page item must match page.asOf; pagination is explicitly not a frozen snapshot.
- Normal Account → shared account links → reward reader → list/pagination → fresh detail. Loading/error/empty/retry states use existing account lifecycle and styles. Merchant disabled/unavailable/unverified and validity states are bilingual. No live row can display a redemption credential or open even the synthetic preview.

## Isolation and failure behavior

Session identity contains owner, epoch and token privately. Credential-free scopes rotate on any change. Late success/401 after logout, token replacement or epoch change is discarded and cannot expire a newer session. Detail reads never reuse list data as fresh detail. Detail must retain immutable scope/merchant/store/quantity/title/conditions/validity/awardedAt; its asOf cannot go backward, and terminal states cannot change. A newer legitimate AWARDED→terminal result is accepted.

Refresh clears old data and advances generation. Concurrent load-more calls coalesce. Failed next pages retain the existing rows and same retry cursor. Duplicate IDs and repeated/cyclic cursors fail closed instead of silently overwriting awards or looping. Cancelled/stale pages cannot overwrite a newer refresh. Unauthorized pagination clears earlier rows. Response decoding is bounded to 1 MiB; requests use no-store and reloadIgnoringLocalCacheData. The existing HTTPTransport protocol exposes status/data only, so response Cache-Control cannot be independently inspected here; backend source sets no-store, and actual transport/caching behavior remains a runtime gate.

## Evidence limits

Core transport/session/collection tests and one App composition test are authored. Existing normal-root synthetic UI tests remain in place. Python contracts, project generation, scaffold, parser and patch replay are supplementary source evidence only. Swift/Xcode, Core XCTest, app-unit/UI compilation, simulator/device, real backend interoperability, cancellation timing, rendered bilingual/VoiceOver/Dynamic Type checks remain UNRUN. No remote CI, deployment or publication was started. This adds no decision about real merchant fulfillment, stock, enrollment, redemption or money.

Captured backend MVC list/detail/404 JSON is retained at `Tests/ContractChecks/fixtures/noncash-mvc-wire-examples.json` (SHA256 `6a65210fb9a53b35d1df3c5395745f643968351a7fb04a8edd6f248cc18e8caa`). An authored Swift interoperability test consumes identical bodies; Python verifies fixture identity, but Swift decoding execution remains UNRUN.
